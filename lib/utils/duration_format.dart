/// 时长格式化工具。
///
/// 统一有声书列表页/章节页的 m:ss / h:mm:ss 展示（R002 修复：
/// 此前是各页面各自的第 4/5 份内联副本）。
String formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// 从毫秒格式化（进度显示用），复用 [formatDuration]。
String formatDurationMs(int ms) {
  return formatDuration((ms / 1000).round());
}
