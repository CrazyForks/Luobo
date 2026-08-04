import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 原生平台事件/快照文件存储（dart:io）。
///
/// - events.jsonl：事件流，增量追加、跨冷启动保留；
/// - 轮转：单文件满 [maxFileBytes] 切新文件，最多 [maxFiles] 个，删最旧；
/// - metrics.jsonl：60s 指标快照，独立上限；
/// - 导出：拷贝文件 + 生成可读文本 + meta.json 到 `export_<ts>/` 目录。
///
/// 所有写入经单一串行 Future 链执行，避免并发 append 与轮转
/// （close/rename/reopen）交错导致的竞态。
class DiagFileStore {
  final int maxFileBytes;
  final int maxFiles;

  DiagFileStore({
    this.maxFileBytes = 1 * 1024 * 1024, // 1MB
    this.maxFiles = 5,
  });

  Directory? _dir;
  IOSink? _eventSink;
  IOSink? _metricsSink;
  int _eventBytes = 0;
  int _metricsBytes = 0;
  Future<void> _writeChain = Future.value(); // 串行化写入队列

  Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/diagnostics');
    await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  Future<void> init() async {
    final dir = await _ensureDir();
    // 续接已有文件大小（字节），避免重启后轮转阈值失效
    final f = File('${dir.path}/events.jsonl');
    if (await f.exists()) {
      _eventBytes = await f.length();
    }
    final m = File('${dir.path}/metrics.jsonl');
    if (await m.exists()) {
      _metricsBytes = await m.length();
    }
    // 清理上次轮转/崩溃残留的 tmp 文件
    final tmp = File('${dir.path}/metrics.tmp');
    if (await tmp.exists()) {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }

  Future<IOSink> _openEventSink() async {
    _eventSink ??= File('${(await _ensureDir()).path}/events.jsonl')
        .openWrite(mode: FileMode.append);
    return _eventSink!;
  }

  Future<IOSink> _openMetricsSink() async {
    _metricsSink ??= File('${(await _ensureDir()).path}/metrics.jsonl')
        .openWrite(mode: FileMode.append);
    return _metricsSink!;
  }

  int _utf8Bytes(String s) => utf8.encode(s).length;

  Future<void> appendEvent(String line) {
    final op =
        _writeChain.catchError((_) {}).then((_) => _appendEventInner(line));
    // 链保持存活：错误仅由本次调用方感知，不毒化后续任务
    _writeChain = op.catchError((_) {});
    return op;
  }

  Future<void> _appendEventInner(String line) async {
    final sink = await _openEventSink();
    sink.write(line);
    sink.write('\n');
    _eventBytes += _utf8Bytes(line) + 1;
    if (_eventBytes >= maxFileBytes) {
      await _rotateEvents();
    }
  }

  Future<void> appendMetrics(String line) {
    final op =
        _writeChain.catchError((_) {}).then((_) => _appendMetricsInner(line));
    _writeChain = op.catchError((_) {});
    return op;
  }

  Future<void> _appendMetricsInner(String line) async {
    final sink = await _openMetricsSink();
    sink.write(line);
    sink.write('\n');
    _metricsBytes += _utf8Bytes(line) + 1;
    if (_metricsBytes >= 2 * maxFileBytes) {
      // 指标独立轮转：tmp + rename 原子替换，避免中途崩溃留半截文件
      await _metricsSink?.flush();
      await _metricsSink?.close();
      _metricsSink = null;
      final dir = await _ensureDir();
      final f = File('${dir.path}/metrics.jsonl');
      if (await f.exists()) {
        final content = await f.readAsBytes();
        final keep = content.length > maxFileBytes
            ? content.sublist(content.length - maxFileBytes)
            : content;
        final tmp = File('${dir.path}/metrics.tmp');
        await tmp.writeAsBytes(keep, flush: true);
        await tmp.rename('${dir.path}/metrics.jsonl');
      }
      _metricsBytes = (await f.exists()) ? await f.length() : 0;
    }
  }

  Future<void> _rotateEvents() async {
    await _eventSink?.flush();
    await _eventSink?.close();
    _eventSink = null;
    final dir = await _ensureDir();
    // events.4 -> 删除；events.3 -> events.4 ... events.1 -> events.2；events.jsonl -> events.1
    final oldest = File('${dir.path}/events.$maxFiles.jsonl');
    if (await oldest.exists()) await oldest.delete();
    for (var i = maxFiles - 1; i >= 1; i--) {
      final src = File('${dir.path}/events.$i.jsonl');
      if (await src.exists()) {
        await src.rename('${dir.path}/events.${i + 1}.jsonl');
      }
    }
    final cur = File('${dir.path}/events.jsonl');
    if (await cur.exists()) {
      await cur.rename('${dir.path}/events.1.jsonl');
    }
    _eventBytes = 0;
    await _openEventSink();
  }

  Future<void> _flushSinks() async {
    try {
      await _eventSink?.flush();
      await _metricsSink?.flush();
    } catch (_) {}
  }

  Future<void> flush() async {
    // 先等待写链排空，再 flush sink，避免与链内轮转交错
    await _writeChain.catchError((_) {});
    await _flushSinks();
  }

  Future<void> close() async {
    await _writeChain.catchError((_) {});
    try {
      await _eventSink?.flush();
      await _metricsSink?.flush();
      await _eventSink?.close();
      await _metricsSink?.close();
    } catch (_) {}
    _eventSink = null;
    _metricsSink = null;
  }

  /// 清空全部日志/指标/导出目录。与写入、导出共享同一串行链，避免竞态。
  Future<void> clear() {
    final op = _writeChain.catchError((_) {}).then((_) => _clearInner());
    _writeChain = op.catchError((_) {});
    return op;
  }

  Future<void> _clearInner() async {
    // 已在串行链内执行：直接 flush+close sink，不再等待链（避免自等待死锁）
    try {
      await _eventSink?.flush();
      await _metricsSink?.flush();
      await _eventSink?.close();
      await _metricsSink?.close();
    } catch (_) {}
    _eventSink = null;
    _metricsSink = null;
    final dir = await _ensureDir();
    // 删除轮转分卷、当前文件、指标与历史导出目录（避免磁盘无界增长）
    for (var i = 1; i <= maxFiles; i++) {
      final f = File('${dir.path}/events.$i.jsonl');
      if (await f.exists()) await f.delete();
    }
    final e = File('${dir.path}/events.jsonl');
    if (await e.exists()) await e.delete();
    final m = File('${dir.path}/metrics.jsonl');
    if (await m.exists()) await m.delete();
    final tmp = File('${dir.path}/metrics.tmp');
    if (await tmp.exists()) await tmp.delete();
    await for (final entry in dir.list()) {
      if (entry is Directory &&
          entry.uri.pathSegments.isNotEmpty &&
          entry.uri.pathSegments.last.startsWith('export_')) {
        try {
          await entry.delete(recursive: true);
        } catch (_) {}
      }
    }
    _eventBytes = 0;
    _metricsBytes = 0;
  }

  /// 导出：拷贝原始文件 + 生成可读文本 + meta.json，返回导出目录路径。
  /// 与写入、清空共享同一串行链，避免与轮转/删除交错。
  Future<String?> export(String readableText, Map<String, dynamic> meta) {
    final op = _writeChain
        .catchError((_) {})
        .then((_) => _exportInner(readableText, meta));
    _writeChain = op.catchError((_) => null);
    return op;
  }

  Future<String?> _exportInner(
      String readableText, Map<String, dynamic> meta) async {
    await _flushSinks();
    final dir = await _ensureDir();
    final exportDir = Directory(
      '${dir.path}/export_${DateTime.now().millisecondsSinceEpoch}',
    );
    await exportDir.create(recursive: true);
    for (var i = maxFiles; i >= 1; i--) {
      final src = File('${dir.path}/events.$i.jsonl');
      if (await src.exists()) {
        await src.copy('${exportDir.path}/events.$i.jsonl');
      }
    }
    final e = File('${dir.path}/events.jsonl');
    if (await e.exists()) {
      await e.copy('${exportDir.path}/events.jsonl');
    }
    final m = File('${dir.path}/metrics.jsonl');
    if (await m.exists()) {
      await m.copy('${exportDir.path}/metrics.jsonl');
    }
    await File('${exportDir.path}/export.txt')
        .writeAsString(readableText, flush: true);
    await File('${exportDir.path}/meta.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(meta),
        flush: true);
    return exportDir.path;
  }

  /// 读取最近事件文件尾部（用于导出可读文本 / 诊断页加载）。
  /// 按时间序拼接：最旧分卷（events.$maxFiles）→ 最新分卷（events.1）→ 当前文件，
  /// 尾部截断时保留最新数据。
  Future<String> readEventLines({int maxLines = 500}) async {
    final dir = await _ensureDir();
    final lines = <String>[];
    for (var i = maxFiles; i >= 1; i--) {
      final f = File('${dir.path}/events.$i.jsonl');
      if (await f.exists()) {
        lines.addAll(await f.readAsLines());
      }
    }
    final cur = File('${dir.path}/events.jsonl');
    if (await cur.exists()) {
      lines.addAll(await cur.readAsLines());
    }
    if (lines.length > maxLines) {
      return lines.sublist(lines.length - maxLines).join('\n');
    }
    return lines.join('\n');
  }
}
