import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 「继续收听」卡片（R004 修复：抽取列表页/详情页同构 banner 的共享组件）。
///
/// 结构：播放图标 | 标题（加粗）+ 副标题（可选）+ 详细行（可选）| chevron；
/// 圆角 12、白/深色底。[detail] 用于列表页的"第 X 章 · 已播至 mm:ss"行。
class ContinueListeningCard extends StatelessWidget {
  final String title;
  final String? subtitle; // 常规色第二行（列表页 = 书名）
  final String? detail; // 主色第三行（章节+进度）
  final VoidCallback onTap;

  const ContinueListeningCard({
    super.key,
    required this.title,
    this.subtitle,
    this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(CupertinoIcons.play_circle_fill,
                    color: accentColor, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ],
                      if (detail != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: accentColor),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(CupertinoIcons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
