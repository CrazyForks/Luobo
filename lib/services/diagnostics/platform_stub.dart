/// Web 平台能力（无 dart:io）。
class PlatformInfo {
  const PlatformInfo._();

  /// Web 无 ProcessInfo，返回 null（内存指标跳过）。
  static Future<int?> currentRssKb() async => null;
}
