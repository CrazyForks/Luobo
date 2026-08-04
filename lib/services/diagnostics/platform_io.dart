import 'dart:io';

/// 原生平台能力（dart:io 可用）。
/// Web 端使用 platform_stub.dart 替代。
class PlatformInfo {
  const PlatformInfo._();

  /// 当前进程物理内存占用（KB），失败返回 null。
  static Future<int?> currentRssKb() async {
    try {
      return ProcessInfo.currentRss ~/ 1024;
    } catch (_) {
      return null;
    }
  }
}
