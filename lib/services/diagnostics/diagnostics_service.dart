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
      final saved = prefs.getString(_appSessionKey);
      _appSessionId = (saved != null && saved.isNotEmpty)
          ? saved
          : 'as-${_uuid.v4().substring(0, 8)}';
      await prefs.setString(_appSessionKey, _appSessionId);
      await _store.init();
    } catch (_) {
      _appSessionId = 'as-${_uuid.v4().substring(0, 8)}';
      // 存储初始化失败：降级为仅内存 ring 模式，避免 _pending 无界增长
      _persistDisabled = true;
    }
    _inited = true;

    // 初始化前暂存的事件补录
    if (_pending.isNotEmpty) {
      final events = List<DiagnosticEvent>.from(_pending);
      _pending.clear();
      for (final e in events) {
        _persist(e);
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

  Future<void> flush() => _store.flush();

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

  void _persist(DiagnosticEvent e) {
    if (_persistDisabled) return;
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
    if (_persistDisabled) {
      // 熔断恢复探测：每 60s 走事件写入路径试写一次（与熔断同源），
      // 成功则恢复持久化；按完整事件结构写入，避免污染事件流解析
      try {
        final probe = DiagnosticEvent(
          seq: ++_seq,
          ts: DateTime.now(),
          sessionId: 'app',
          appSessionId: _appSessionId,
          type: 'app.probe',
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
  /// 统一为可读格式，并按 seq 去重（文件侧 JSONL 解析后与 ring 合并）。
  Future<String> readableText({int maxLines = 500}) async {
    final bySeq = <int, String>{};
    try {
      final fileText = await _store.readEventLines(maxLines: maxLines * 2);
      for (final line in fileText.split('\n')) {
        if (line.trim().isEmpty) continue;
        final ev = DiagnosticEvent.fromJsonLine(line);
        if (ev != null) bySeq[ev.seq] = ev.toReadable();
      }
    } catch (_) {}
    for (final ev in _ring) {
      bySeq[ev.seq] = ev.toReadable();
    }
    final seqs = bySeq.keys.toList()..sort();
    final lines = seqs.map((s) => bySeq[s]!).toList();
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

  Future<void> clear() async {
    await _store.clear();
    _ring.clear();
    notifyListeners();
  }

  void setAppVersion(String version) => _appVersion = version;
}
