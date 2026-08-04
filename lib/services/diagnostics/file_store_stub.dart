/// Web 平台文件存储空实现（无文件系统）。
/// 事件仅存内存（由 DiagnosticsService 环形缓冲承载），导出走剪贴板。
class DiagFileStore {
  const DiagFileStore();

  Future<void> init() async {}

  Future<void> appendEvent(String line) async {}

  Future<void> appendMetrics(String line) async {}

  Future<void> flush() async {}

  Future<void> close() async {}

  Future<void> clear() async {}

  /// 导出目录路径；Web 返回 null（使用剪贴板导出）。
  Future<String?> export(
          String readableText, Map<String, dynamic> meta) async =>
      null;

  /// Web 无文件：返回空。
  Future<String> readEventLines({int maxLines = 500}) async => '';
}
