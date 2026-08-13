import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 加载失败视图（R003 修复：抽取 RadioScreen/有声书列表页/章节页复用的
/// 三态 error UI，避免逐段复制内联实现）。
///
/// [message] 为错误详情（可选），[retryLabel]/[onRetry] 提供重试入口。
class LoadErrorView extends StatelessWidget {
  final String title;
  final String? message;
  final VoidCallback onRetry;
  final String retryLabel;

  const LoadErrorView({
    super.key,
    required this.title,
    this.message,
    required this.onRetry,
    required this.retryLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 64,
              color: Colors.orange,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(CupertinoIcons.refresh),
              label: Text(retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空态视图（列表为空时的占位提示）。
class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool isDark;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.message,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(icon, size: 64, color: isDark ? Colors.white24 : Colors.black26),
        const SizedBox(height: 16),
        Center(
          child: Text(message, style: TextStyle(color: Colors.grey[600])),
        ),
      ],
    );
  }
}
