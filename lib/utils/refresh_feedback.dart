import 'package:flutter/material.dart';
import '../providers/library_provider.dart';
import '../l10n/app_localizations.dart';

/// 执行刷新并按结果弹提示（成功数字 / 本地重载 / 失败）。
///
/// 已在同步中的合并请求（[RefreshResult.merged]）静默，避免重复弹窗；
/// 按钮自身的 loading 态由 [LibraryProvider.refreshStatus] 驱动。
/// 提示用原生 SnackBar（floating）经 margin 垂直居中到屏幕中部。
Future<void> refreshLibraryWithFeedback(
  BuildContext context,
  LibraryProvider libraryProvider,
) async {
  final result = await libraryProvider.refresh();
  if (!context.mounted || result.merged) return;
  final l10n = AppLocalizations.of(context)!;
  final message = result.success
      ? (result.isLocal
            ? l10n.refreshLocalComplete
            : l10n.refreshComplete(result.albumCount, result.songCount))
      : l10n.refreshFailed;
  showCenteredToast(context, message);
}

/// 原生 SnackBar（floating）经 margin 垂直居中到屏幕中部：
/// 完整保留 SnackBar 的观感与行为（主题样式、滑动关闭、消息队列），
/// 仅改变出现位置。
void showCenteredToast(BuildContext context, String message) {
  // 减掉 SnackBar 自身高度的一半（约 28），使条体中心对齐屏幕垂直中心。
  final bottom = MediaQuery.of(context).size.height / 2 - 28;
  final messenger = ScaffoldMessenger.of(context);
  messenger.removeCurrentSnackBar(); // 替换而非排队，连续刷新不堆积提示
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      margin: EdgeInsets.fromLTRB(24, 0, 24, bottom < 24 ? 24 : bottom),
    ),
  );
}
