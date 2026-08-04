import 'package:flutter/foundation.dart';

import 'diagnostics_service.dart';
import 'event_types.dart';

/// 统一日志静态 API。
///
/// - 懒格式化：调用方仍会拼字符串，热路径请避免高频调用；
/// - release 默认仅 info 及以上落盘（debug 级不落盘）；
/// - 事件转发 DiagnosticsService 统一落盘/轮转/导出。
class Log {
  Log._();

  static bool debugEnabled = !kReleaseMode;

  static DiagnosticsService get _diag => DiagnosticsService.instance;

  static void d(String tag, String msg,
          {Object? error, Map<String, dynamic>? extra}) =>
      _emit(LogLevel.debug, tag, msg, error: error, extra: extra);

  static void i(String tag, String msg,
          {Object? error, Map<String, dynamic>? extra}) =>
      _emit(LogLevel.info, tag, msg, error: error, extra: extra);

  static void w(String tag, String msg,
          {Object? error, Map<String, dynamic>? extra}) =>
      _emit(LogLevel.warn, tag, msg, error: error, extra: extra);

  static void e(String tag, String msg,
          {Object? error, Map<String, dynamic>? extra}) =>
      _emit(LogLevel.error, tag, msg, error: error, extra: extra);

  static void _emit(
    LogLevel level,
    String tag,
    String msg, {
    Object? error,
    Map<String, dynamic>? extra,
  }) {
    if (level == LogLevel.debug && !debugEnabled) return;
    final payload = <String, dynamic>{
      'tag': tag,
      'msg': msg,
      if (error != null) 'error': '$error',
      ...?extra,
    };
    final type = switch (level) {
      LogLevel.debug => EventType.logDebug,
      LogLevel.info => EventType.logInfo,
      LogLevel.warn => EventType.logWarn,
      LogLevel.error => EventType.logError,
    };
    _diag.record(type, level, payload);
  }
}
