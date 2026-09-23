import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/cover_palette.dart';

/// 有声书伪封面（API 无封面字段，见 docs/有声书接入技术方案.md §3 决策）。
///
/// FNV-1a(书名) 稳定 hash → 从精选渐变集中**确定性取色**（同书颜色恒定，
/// 列表/详情/书架处处一致）；主体 = 书名首字大字居中 + 右上角半透明书 icon。
///
/// 尺寸由调用方传入（详情 header 64 / shelf 120×160 /
/// 网格用 AspectRatio(3/4) + double.infinity 自适应，组件内部按实际约束取边长）。
class AudiobookCover extends StatelessWidget {
  final String title;
  final double width;
  final double height;
  final double radius;

  const AudiobookCover({
    super.key,
    required this.title,
    required this.width,
    required this.height,
    this.radius = 12,
  });

  /// 12 组精选渐变（浅色/深色各一套，取色索引一一对应）。
  static const List<List<Color>> _lightPalette = [
    [Color(0xFF3949AB), Color(0xFF6A1B9A)], // 靛蓝→深紫
    [Color(0xFF00897B), Color(0xFF00838F)], // 青→深青
    [Color(0xFFC2185B), Color(0xFFE64A19)], // 品红→深橙
    [Color(0xFF7B1FA2), Color(0xFFD81B60)], // 紫→品红
    [Color(0xFF1E88E5), Color(0xFF546E7A)], // 蓝→蓝灰
    [Color(0xFF00897B), Color(0xFF2E7D32)], // 蓝绿→深绿
    [Color(0xFF1E88E5), Color(0xFF3949AB)], // 蓝→靛
    [Color(0xFF6D4C41), Color(0xFFE64A19)], // 棕→深橙
    [Color(0xFFE53935), Color(0xFF8E24AA)], // 红→紫
    [Color(0xFF546E7A), Color(0xFF37474F)], // 深灰→蓝灰
    [Color(0xFF00ACC1), Color(0xFF1E88E5)], // 深青→蓝
    [Color(0xFF5E35B1), Color(0xFF3949AB)], // 深紫→靛
  ];

  static const List<List<Color>> _darkPalette = [
    [Color(0xFF1A237E), Color(0xFF4A148C)],
    [Color(0xFF004D40), Color(0xFF006064)],
    [Color(0xFF880E4F), Color(0xFFBF360C)],
    [Color(0xFF4A148C), Color(0xFF880E4F)],
    [Color(0xFF0D47A1), Color(0xFF37474F)],
    [Color(0xFF00695C), Color(0xFF1B5E20)],
    [Color(0xFF0D47A1), Color(0xFF1A237E)],
    [Color(0xFF4E342E), Color(0xFFBF360C)],
    [Color(0xFFB71C1C), Color(0xFF6A1B9A)],
    [Color(0xFF37474F), Color(0xFF263238)],
    [Color(0xFF00838F), Color(0xFF0D47A1)],
    [Color(0xFF4527A0), Color(0xFF1A237E)],
  ];

  /// FNV-1a 32bit：跨 Dart 版本稳定（String.hashCode 不保证稳定），
  /// 保证同一书名在任何运行环境都取到同一颜色。
  ///
  /// 取色索引：空书名给 0，避免全空书名撞到同一色。
  int _paletteIndex(String title) =>
      coverPaletteIndex(title, _lightPalette.length);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? _darkPalette : _lightPalette;
    final colors = palette[_paletteIndex(title)];

    // 用 LayoutBuilder 取**实际布局约束**的边长，而非信任入参：网格调用方传
    // double.infinity，若按入参 min(width,height) 会得到 ∞，使 Positioned 书
    // icon 偏移到无穷远被裁剪（P1 修复，2026-08-21）。
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w =
              constraints.maxWidth.isFinite ? constraints.maxWidth : width;
          final h =
              constraints.maxHeight.isFinite ? constraints.maxHeight : height;
          final side = w < h ? w : h;
          final trimmed = title.trim();
          // 空书名兜底走 l10n 首字（"有声书"/"Audiobooks"），避免硬编码文案（P3 修复）。
          final fallbackChar =
              AppLocalizations.of(context)!.audiobooks.characters.first;
          final initial =
              trimmed.isEmpty ? fallbackChar : trimmed.characters.first;
          final fontSize = (side * 0.35).clamp(20.0, 64.0);
          final iconSize = (side * 0.16).clamp(10.0, 26.0);

          return Stack(
            children: [
              Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.95),
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: side * 0.06,
                right: side * 0.06,
                child: Icon(
                  CupertinoIcons.book_fill,
                  size: iconSize,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
