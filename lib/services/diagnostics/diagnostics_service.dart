import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'diagnostic_event.dart';
import 'event_types.dart';
import 'file_store.dart';

/// 诊断聚合服务：唯一落盘者。
///
/// - 事件环形缓冲（最近 [ringSize] 条）供诊断页实时查看；
/// - 事件/快照异步批量落盘（见 [flushInterval]），崩溃不丢最后事件；
/// - `seq` 全局递增并跨启动持久化（SharedPreferences）；
/// - 会话管理：PlaybackSession / NetSession / AppSession；
/// - 60s 指标快照（帧率/网络/内存/图片缓存）；
/// - 导出/清空/剪贴板。
class DiagnosticsService extends ChangeNotifier {
  DiagnosticsService._internal();

  static final DiagnosticsService instance = DiagnosticsService._internal();

  static const int ringSize = 500;
  static const int pendingCap = 2000;
  static const int persistFailLimit = 5;
  static const Duration flushInterval = Duration(milliseconds: 200);
  static const Duration snapshotInterval = Duration(seconds: 60);
  static const Duration notifyThrottle = Duration(milliseconds: 200);
  static const String _seqPrefsKey = 'diag_seq';
  static const String _appSessionKey = 'diag_app_session';

  final DiagFileStore _store = DiagFileStore();
  final List<DiagnosticEvent> _ring = [];
  final List<DiagnosticEvent> _pending = []; // 初始化前暂存
  final Uuid _uuid = const Uuid();

  Timer? _flushTimer;
  Timer? _snapshotTimer;
  Timer? _notifyTimer;
  int _seq = 0;
  bool _inited = false;
  bool _persistDisabled = false;

  /// 写锁被其他存活实例持有：本实例降级为仅内存 ring，不落盘；
  /// 快照定时器周期性尝试接管（旧实例可能已退出）。
  bool _secondaryInstance = false;
  int _persistFailures = 0;
  String _appSessionId = 'as-init';
  String _playbackSessionId = '';
  String _netSessionId = '';
  String _currentRoute = 'unknown';

  // 指标快照聚合数据
  int _netCount = 0;
  int _netOk = 0;
  final List<int> _netMs = [];
  double _fps = 0;
  double _jankRate = 0;

  // ---- 对外只读状态 ----

  List<DiagnosticEvent> get ring => List.unmodifiable(_ring);
  String get appSessionId => _appSessionId;
  String get currentRoute => _currentRoute;
  String? get netSessionId => _netSessionId.isEmpty ? null : _netSessionId;
  bool get isInited => _inited;

  // ---- 生命周期 ----

  Future<void> init() async {
    if (_inited) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSeq = prefs.getInt(_seqPrefsKey) ?? 0;
      if (savedSeq > _seq) _seq = savedSeq; // 不覆盖本启动已推进的 seq
      await _store.init();
      // 写锁：防止进程/引擎重建后两个实例并发追加同一文件（曾导致 JSONL
      // 写穿、seq 重复、双 appSessionId 并存）。busy → 降级为仅内存 ring，
      // 由快照定时器周期性尝试接管（旧实例可能已退出）。
      final lock = await _store.acquireWriterLock();
      if (lock == WriterLockResult.busy) {
        _secondaryInstance = true;
      }
      // 从文件尾对账 seq/appSessionId（与 prefs 取大/补齐），修复实例重建
      // 后 seq 回退、会话分叉导致的重复序号与时间线割裂。
      final tail = await _store.readTailState();
      if (tail.seq != null && tail.seq! > _seq) _seq = tail.seq!;
      final saved = prefs.getString(_appSessionKey);
      if (saved != null && saved.isNotEmpty) {
        _appSessionId = saved;
      } else if (tail.appSessionId != null) {
        _appSessionId = tail.appSessionId!; // 沿用文件尾会话，跨启动时间线连续
      } else {
        _appSessionId = 'as-${_uuid.v4().substring(0, 8)}';
      }
      // 仅持锁实例落 prefs：次级实例（busy）不写，避免并发冷启动时自生成的
      // 会话 id 覆盖主写入者，导致下次启动会话分叉。
      if (!_secondaryInstance) {
        await prefs.setString(_appSessionKey, _appSessionId);
        // 立即固化对账后的 seq：快速引擎重建（双实例窗口）时，新实例若只
        // 依赖每 50 条的节流持久化，可能在旧实例尚未停写时复用重复 seq，
        // 导致导出按 seq 去重丢事件。对账完成即落盘，缩小重叠窗口。
        await _saveSeq(_seq);
      }
      if (lock == WriterLockResult.staleTakenOver) {
        // 前序实例崩溃残留：轮转隔离可能仍持有旧句柄的僵尸写入者，
        // 本实例从 0 字节的干净文件开始追加。
        await _store.rotateEvents();
      }
    } catch (_) {
      _appSessionId = 'as-${_uuid.v4().substring(0, 8)}';
      // 存储初始化失败：降级为仅内存 ring 模式，避免 _pending 无界增长
      _persistDisabled = true;
    }
    _inited = true;

    // 初始化前暂存的事件补录；补录时把默认 as-init 改写为真实 appSessionId，
    // 避免启动早期事件永久归属错误会话（曾导致 19 条 as-init 落盘）。
    if (_pending.isNotEmpty) {
      final events = List<DiagnosticEvent>.from(_pending);
      _pending.clear();
      for (final e in events) {
        final appSessionId = e.appSessionId;
        _persist(appSessionId.isEmpty || appSessionId == 'as-init'
            ? _withAppSessionId(e, _appSessionId)
            : e);
      }
      notifyListeners();
    }

    _flushTimer ??= Timer.periodic(flushInterval, (_) => flush());
    _snapshotTimer ??=
        Timer.periodic(snapshotInterval, (_) => unawaited(_writeSnapshot()));
    record(EventType.appStart, LogLevel.info, {
      'appSessionId': _appSessionId,
      'seq': _seq,
    });
  }

  Future<void> flush() async {
    await _store.flush();
    // 写锁被其他实例接管（后台心跳暂停致锁过期被接管）：本实例失去写权，
    // 转入 secondary——事件保留在内存 ring，由快照定时器周期尝试重新接管，
    // 避免两个实例继续并发落盘（曾见接管后旧实例继续写旧分卷）。
    if (_store.lockLost && !_secondaryInstance) {
      _secondaryInstance = true;
    }
  }

  /// 供 App 生命周期（detached）调用：flush + 关闭 sink，保证进程退出前
  /// 缓冲落盘。不 cancel 定时器、不置不可逆状态——detach 是瞬态场景
  /// （Android 重建/桌面关窗重开），sink 关闭后由 [_openEventSink] 惰性重开，
  /// 周期 flush/快照可持续工作。
  Future<void> disposeAsync() async {
    await flush();
    await _store.close();
  }

  // ---- 事件记录 ----

  /// 记录一条事件。所有埋点统一走这里。
  DiagnosticEvent record(
    String type,
    LogLevel level,
    Map<String, dynamic> payload, {
    String? sessionId,
  }) {
    final event = DiagnosticEvent(
      seq: ++_seq,
      ts: DateTime.now(),
      sessionId: sessionId ?? _effectiveSessionId(),
      appSessionId: _appSessionId,
      netSessionId: netSessionId,
      type: type,
      level: level,
      payload: payload,
    );
    _ring.add(event);
    if (_ring.length > ringSize) {
      _ring.removeRange(0, _ring.length - ringSize);
    }
    if (!_inited) {
      _pending.add(event);
      if (_pending.length > pendingCap) {
        _pending.removeRange(0, _pending.length - pendingCap);
      }
    } else {
      _persist(event);
    }
    _maybePersistSeq();
    _scheduleNotify();
    return event;
  }

  String _effectiveSessionId() =>
      _playbackSessionId.isNotEmpty ? _playbackSessionId : 'app';

  /// 生成 appSessionId 被改写的事件副本（用于 pending 补录时修正 as-init）。
  DiagnosticEvent _withAppSessionId(DiagnosticEvent e, String appSessionId) =>
      DiagnosticEvent(
        seq: e.seq,
        ts: e.ts,
        sessionId: e.sessionId,
        appSessionId: appSessionId,
        netSessionId: e.netSessionId,
        type: e.type,
        level: e.level,
        payload: e.payload,
      );

  void _persist(DiagnosticEvent e) {
    if (_persistDisabled || _secondaryInstance) return;
    unawaited(_appendSafe(e));
  }

  /// 落盘失败不抛出：连续失败达到阈值后熔断，降级为仅内存 ring，
  /// 避免 IO 故障时异常进入 guarded zone onError 形成错误风暴回环。
  Future<void> _appendSafe(DiagnosticEvent e) async {
    try {
      await _store.appendEvent(e.toJsonLine());
      _persistFailures = 0;
    } catch (_) {
      _persistFailures++;
      if (_persistFailures >= persistFailLimit) {
        _persistDisabled = true;
      }
    }
  }

  int _seqPersistCounter = 0;
  void _maybePersistSeq() {
    // 次级实例不写 prefs：避免覆盖主写入者的 seq 造成跨实例回退
    if (_secondaryInstance) return;
    if (++_seqPersistCounter < 50) return;
    _seqPersistCounter = 0;
    final seqSnapshot = _seq; // 快照，避免 await 期间被后续 record 递增
    unawaited(_saveSeq(seqSnapshot));
  }

  Future<void> _saveSeq(int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_seqPrefsKey, value);
    } catch (_) {}
  }

  /// 事件批量通知节流：高频埋点（Dio 拦截器、jank）不逐条触发 UI 重建。
  void _scheduleNotify() {
    _notifyTimer ??= Timer(notifyThrottle, () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  // ---- 会话管理 ----

  String beginPlaybackSession() {
    _playbackSessionId = 'ps-${_uuid.v4().substring(0, 8)}';
    return _playbackSessionId;
  }

  void endPlaybackSession() {
    _playbackSessionId = '';
  }

  /// 网络类型切换时调用，轮换 netSessionId。
  void rotateNetSession(String networkType) {
    _netSessionId = 'ns-$networkType-${_uuid.v4().substring(0, 6)}';
  }

  void setCurrentRoute(String route) {
    if (_currentRoute == route) return;
    _currentRoute = route;
  }

  // ---- 指标聚合输入 ----

  void networkRequest({required int ms, required bool ok}) {
    _netCount++;
    if (ok) _netOk++;
    _netMs.add(ms);
    if (_netMs.length > 200) _netMs.removeAt(0);
  }

  void updateFrameStats({required double fps, required double jankRate}) {
    _fps = fps;
    _jankRate = jankRate;
  }

  double get fps => _fps;
  double get jankRate => _jankRate;
  int get netCount => _netCount;
  int? get netP90Ms {
    if (_netMs.isEmpty) return null;
    final sorted = [..._netMs]..sort();
    return sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)];
  }

  double get netErrorRate => _netCount == 0 ? 0 : (1 - _netOk / _netCount);

  // ---- 指标快照 ----

  Future<void> _writeSnapshot() async {
    if (_secondaryInstance) {
      // 周期性尝试接管写锁：旧实例可能已退出；成功后恢复落盘并同步
      // 文件尾状态，避免与旧实例残留写入产生重复 seq。
      try {
        final lock = await _store.acquireWriterLock();
        if (lock != WriterLockResult.busy) {
          _secondaryInstance = false;
          if (lock == WriterLockResult.staleTakenOver) {
            await _store.rotateEvents();
          }
          final tail = await _store.readTailState();
          if (tail.seq != null && tail.seq! > _seq) _seq = tail.seq!;
        }
      } catch (_) {}
      return; // 未接管期间不写指标快照（事件也不落盘，见 _persist）
    }
    if (_persistDisabled) {
      // 熔断恢复探测：每 60s 走事件写入路径试写一次（与熔断同源），
      // 成功则恢复持久化；按完整事件结构写入，避免污染事件流解析
      try {
        final probe = DiagnosticEvent(
          seq: ++_seq,
          ts: DateTime.now(),
          sessionId: 'app',
          appSessionId: _appSessionId,
          type: EventType.appProbe,
          level: LogLevel.debug,
          payload: const <String, dynamic>{},
        );
        await _store.appendEvent(probe.toJsonLine());
        _persistDisabled = false;
        _persistFailures = 0;
      } catch (_) {}
      return;
    }
    final snapshot = <String, dynamic>{
      'ts': DateTime.now().toIso8601String(),
      'fps': _fps,
      'jankRate': _jankRate,
      'netCount': _netCount,
      'netP90Ms': netP90Ms,
      'netErrorRate': netErrorRate,
      'route': _currentRoute,
    };
    try {
      await _store.appendMetrics(jsonEncode(snapshot));
    } catch (_) {
      _persistFailures++;
      if (_persistFailures >= persistFailLimit) _persistDisabled = true;
    }
  }

  // ---- 导出 / 清空 / 剪贴板 ----

  /// 最近 [maxLines] 条事件的可读文本（诊断页/剪贴板用）。
  /// 统一为可读格式，并按「appSessionId#seq」去重（文件侧 JSONL 解析后与
  /// ring 合并）。
  ///
  /// 加固说明：双实例（进程/引擎重建）可能产生重复 seq（诊断日志实证：
  /// restore.end 两次 seq=56406，分属 as-6cc54e05 / as-915146f0）。按 seq 单键
  /// 去重会把不同实例的事件互相覆盖、导出静默丢事件。复合键让同实例的
  /// 文件/ring 副本正常去重（ring 后写覆盖），不同实例的重复 seq 两条都保留。
  Future<String> readableText({int maxLines = 500}) async {
    final byKey = <String, ({int seq, String text})>{};
    void add(DiagnosticEvent ev) {
      byKey['${ev.appSessionId}#${ev.seq}'] =
          (seq: ev.seq, text: ev.toReadable());
    }

    try {
      final fileText = await _store.readEventLines(maxLines: maxLines * 2);
      for (final line in fileText.split('\n')) {
        if (line.trim().isEmpty) continue;
        final ev = DiagnosticEvent.fromJsonLine(line);
        if (ev != null) add(ev);
      }
    } catch (_) {}
    for (final ev in _ring) {
      add(ev);
    }
    final entries = byKey.values.toList()
      ..sort((a, b) {
        final c = a.seq.compareTo(b.seq);
        if (c != 0) return c;
        return a.text.compareTo(b.text);
      });
    final lines = entries.map((e) => e.text).toList();
    if (lines.length > maxLines) {
      return lines.sublist(lines.length - maxLines).join('\n');
    }
    return lines.join('\n');
  }

  Map<String, dynamic> _meta() => {
        'appVersion': _appVersion,
        'platform': defaultTargetPlatform.name,
        'isWeb': kIsWeb,
        'appSessionId': _appSessionId,
        'startedAt': _startedAt.toIso8601String(),
      };

  String _appVersion = 'unknown';
  final DateTime _startedAt = DateTime.now();

  /// 导出日志到文件（原生），返回导出目录路径；Web 返回 null（用剪贴板）。
  Future<String?> export() async {
    final text = await readableText(maxLines: 2000);
    return _store.export(text, _meta());
  }

  /// 生成自包含的单文件导出文本（meta 概要 + 可读日志），供移动端
  /// 手选路径保存。release 下 adb 无法访问 app 私有目录，需走系统
  /// 保存对话框（SAF）才能把日志取出来。
  Future<String> exportReadableText() async {
    // 先 flush：sink 中可能有未落盘的缓冲，直接读文件会缺失最近事件，
    // 导致 raw 尾部与可读文本时间线不一致（曾见 raw 尾部停在 11:28:47、
    // 可读文本已到 11:29:28）。
    await _store.flush();
    final text = await readableText(maxLines: 2000);
    final meta = _meta();
    // 原始 JSONL 尾部：供核对 seq/appSessionId/写穿——可读文本是解析产物，
    // 损坏行会被静默丢弃，无法验证数据完整性。
    final raw = await _store.readEventLines(maxLines: 400);
    // 指标快照尾部：fps/jankRate/网络聚合只写 metrics.jsonl，不进事件流，
    // 不加这段单文件导出里永远搜不到 fps。
    final metrics = await _store.readMetricsTail(maxLines: 120);
    final buffer = StringBuffer()
      ..writeln('# Luobo diagnostics export')
      ..writeln('appVersion: ${meta['appVersion']}')
      ..writeln('platform: ${meta['platform']}')
      ..writeln('appSessionId: ${meta['appSessionId']}')
      ..writeln('startedAt: ${meta['startedAt']}')
      ..writeln('---')
      ..write(text);
    if (raw.trim().isNotEmpty) {
      buffer
        ..writeln('')
        ..writeln('--- raw events (tail, JSONL) ---')
        ..write(raw);
    }
    if (metrics.trim().isNotEmpty) {
      buffer
        ..writeln('')
        ..writeln('--- metrics (fps/jankRate/net, 60s snapshots) ---')
        ..write(metrics);
    }
    return buffer.toString();
  }

  Future<void> clear() async {
    await _store.clear();
    _ring.clear();
    notifyListeners();
  }

  void setAppVersion(String version) => _appVersion = version;
}
