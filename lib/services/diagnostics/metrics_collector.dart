import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import 'diagnostics_service.dart';
import 'event_types.dart';
import 'platform.dart';

/// 性能指标采集器。
///
/// - 帧摘要：FrameTimings 入帧数据环形缓冲（10s），供派生检测器消费；
/// - 派生检测器：单帧 UI 线程 build+raster >50ms 产出 frame.jank（带当前
///   路由/交互上下文；不采用 totalSpan，避免低帧率上下文误报）；
/// - 启动里程碑：main() 各阶段打点；
/// - 页面 build 计时：>16ms 记录 screen.buildTime；
/// - 内存/缓存：60s 采样（原生端 RSS + 图片缓存）；
/// - 网络：计数器由 Dio 拦截器喂入。
class MetricsCollector {
  MetricsCollector._();

  static final MetricsCollector instance = MetricsCollector._();

  static const int _jankThresholdMs = 50;
  static const int _slowBuildMs = 16;
  static const Duration _frameWindow = Duration(seconds: 10);
  static const Duration _sampleInterval = Duration(seconds: 60);

  final List<FrameTiming> _frames = [];
  Timer? _sampleTimer;
  int _frameSeq = 0;
  DateTime? _lastJankRecordedAt;

  bool _started = false;

  /// 启动里程碑记录（main() 各阶段）。
  static void milestone(String name, int elapsedMs,
      {Map<String, dynamic>? extra}) {
    DiagnosticsService.instance.record(
      EventType.appLaunchMilestone,
      LogLevel.info,
      {'name': name, 'elapsedMs': elapsedMs, ...?extra},
    );
  }

  /// 页面 build 耗时（>16ms 记录）。
  static void buildTime(String screen, int buildMs) {
    if (buildMs > _slowBuildMs) {
      DiagnosticsService.instance.record(
        EventType.screenBuildTime,
        LogLevel.info,
        {'screen': screen, 'buildMs': buildMs},
      );
    }
  }

  /// 网络请求计时喂入（Dio 拦截器调用）。
  static void networkRequest({required int ms, required bool ok}) {
    DiagnosticsService.instance.networkRequest(ms: ms, ok: ok);
  }

  /// 歌词加载结果记录（lrclib/netease 共用）。
  static void lyricsLoad({
    required String source,
    required bool ok,
    required bool found,
    required int elapsedMs,
    Object? error,
    String? artist,
    String? title,
  }) {
    DiagnosticsService.instance.record(
      EventType.lyricsLoad,
      LogLevel.info,
      {
        'source': source,
        'ok': ok,
        'found': found,
        'elapsedMs': elapsedMs,
        if (error != null) 'error': '$error',
        if (artist != null) 'artist': artist,
        if (title != null) 'title': title,
      },
    );
  }

  /// 歌词加载结果记录（Stopwatch 版，内部 stop 后上报，供多个歌词源共用）。
  static void lyricsLoadFrom(
    Stopwatch sw, {
    required String source,
    required bool ok,
    required bool found,
    Object? error,
    String? artist,
    String? title,
  }) {
    sw.stop();
    lyricsLoad(
      source: source,
      ok: ok,
      found: found,
      elapsedMs: sw.elapsedMilliseconds,
      error: error,
      artist: artist,
      title: title,
    );
  }

  void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _sampleTimer ??=
        Timer.periodic(_sampleInterval, (_) => unawaited(_sample()));
  }

  void stop() {
    _sampleTimer?.cancel();
    _sampleTimer = null;
  }

  void _onTimings(List<FrameTiming> timings) {
    final now = DateTime.now();
    for (final t in timings) {
      _frames.add(t);
      _frameSeq++;
      // jank 判定用 UI 线程实际工作量（build+raster），而非 totalSpan：
      // totalSpan 含帧管线等待（vsync 错过、低帧率上下文如 Android Auto
      // 投射/后台），build/raster 仅 ~10ms 却报 50ms+，会系统性误报
      // （曾见 892 条 jank 全部 buildMs 5-8ms）。
      final buildMs = t.buildDuration.inMicroseconds / 1000;
      final rasterMs = t.rasterDuration.inMicroseconds / 1000;
      final uiMs = buildMs + rasterMs;
      final totalMs = t.totalSpan.inMicroseconds / 1000;
      if (uiMs > _jankThresholdMs) {
        // 秒级聚合：持续卡顿时避免逐帧事件淹没缓冲
        final last = _lastJankRecordedAt;
        if (last == null ||
            now.difference(last) >= const Duration(seconds: 1)) {
          _lastJankRecordedAt = now;
          DiagnosticsService.instance.record(
            EventType.frameJank,
            LogLevel.warn,
            {
              'frame': _frameSeq,
              'totalMs': totalMs.round(), // 保留管线总耗时供上下文参考
              'buildMs': buildMs.round(),
              'rasterMs': rasterMs.round(),
              'route': DiagnosticsService.instance.currentRoute,
            },
          );
        }
      }
    }
    // 只保留最近 ~10s 帧（60fps ≈ 600 帧）
    if (_frames.length > 900) {
      _frames.removeRange(0, _frames.length - 900);
    }
  }

  /// 计算最近窗口 FPS 与 jank 率。
  void _aggregate() {
    if (_frames.isEmpty) return;
    // 以采样到的帧数估算 FPS：帧间采样无法精确计时，
    // 采用"最近 10s 窗口内 jank 帧占比"作为卡顿指标（与事件判定同源）。
    final jank = _frames.where((f) {
      return (f.buildDuration.inMicroseconds +
                  f.rasterDuration.inMicroseconds) /
              1000 >
          _jankThresholdMs;
    }).length;
    final jankRate = jank / _frames.length;
    final fps = _estimateFps();
    DiagnosticsService.instance.updateFrameStats(fps: fps, jankRate: jankRate);
  }

  double _estimateFps() {
    // 依据 buildDuration 采样间隔粗略估计；窗口内帧数 / 窗口时长
    return (_frames.length * 1000) / _frameWindow.inMilliseconds;
  }

  Future<void> _sample() async {
    _aggregate();
    final rss = await PlatformInfo.currentRssKb();
    final cache = PaintingBinding.instance.imageCache;
    DiagnosticsService.instance.record(
      EventType.metricsMemory,
      LogLevel.info,
      {
        'sample': 'memory',
        'rssKb': rss,
        'imageCacheCount': cache.currentSize,
        'imageCacheBytes': cache.currentSizeBytes,
        'imageCacheLimitBytes': cache.maximumSizeBytes,
      },
      sessionId: 'app',
    );
  }
}
