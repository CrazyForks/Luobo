import 'dart:convert';

import 'event_types.dart';

/// 诊断事件（一条 = 时间线中的一个点）。
///
/// 序列化为紧凑 JSON 单行，写入 events.jsonl。
class DiagnosticEvent {
  final int seq;
  final DateTime ts;
  final String sessionId;
  final String appSessionId;
  final String? netSessionId;
  final String type;
  final LogLevel level;
  final Map<String, dynamic> payload;

  const DiagnosticEvent({
    required this.seq,
    required this.ts,
    required this.sessionId,
    required this.appSessionId,
    this.netSessionId,
    required this.type,
    required this.level,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'ts': ts.toIso8601String(),
        'sessionId': sessionId,
        'appSessionId': appSessionId,
        if (netSessionId != null) 'netSessionId': netSessionId,
        'type': type,
        'level': level.name,
        'payload': payload,
      };

  /// 落盘用单行 JSON。
  String toJsonLine() => jsonEncode(toJson());

  /// 人类可读格式（导出/诊断页展示）。
  String toReadable() {
    final t = ts.toIso8601String();
    final payloadStr =
        payload.entries.map((e) => '${e.key}=${e.value}').join(' ');
    return '[$t] [${level.name}] [$sessionId] $type $payloadStr';
  }

  /// 从单行 JSON 解析；解析失败返回 null。
  static DiagnosticEvent? fromJsonLine(String line) {
    try {
      final m = jsonDecode(line) as Map<String, dynamic>;
      return DiagnosticEvent(
        seq: (m['seq'] as num).toInt(),
        ts: DateTime.parse(m['ts'] as String),
        sessionId: m['sessionId'] as String,
        appSessionId: m['appSessionId'] as String? ?? '',
        netSessionId: m['netSessionId'] as String?,
        type: m['type'] as String,
        level: LogLevel.values.firstWhere(
          (l) => l.name == m['level'],
          orElse: () => LogLevel.info,
        ),
        payload: (m['payload'] as Map<String, dynamic>?) ?? const {},
      );
    } catch (_) {
      return null;
    }
  }
}
