import 'package:flutter/material.dart';

/// 艺术家封面渐变占位：主题色低饱和渐变 + 首字母大字。
/// 封面解析链路第 5 级兜底（docs/音乐库艺术家页改版技术方案.md §4.2），
/// 保证服务端一张图都没有时，艺术家网格也不出现灰底墙。
class ArtistPlaceholder extends StatelessWidget {
  final String name;

  /// 固定尺寸；为 null 时撑满父约束（要求父级已限定宽高）。
  final double? size;

  final double borderRadius;

  const ArtistPlaceholder({
    super.key,
    required this.name,
    this.size,
    this.borderRadius = 10,
  });

  /// 低饱和渐变对（深/浅色主题通用），按名字 hash 稳定取色——同一艺人
  /// 在所有位置显示同色，视觉有归属感；与拼音分组首字母无关（用首字符）。
  static const List<List<Color>> _palettes = [
    [Color(0xFF7B5EA7), Color(0xFF4A3B77)], // 紫
    [Color(0xFFC96F4A), Color(0xFF8E3B46)], // 橙红
    [Color(0xFF3A9D7A), Color(0xFF1F5C60)], // 青绿
    [Color(0xFF5B8DEF), Color(0xFF3D348B)], // 蓝
    [Color(0xFFC2452E), Color(0xFF7A3B8E)], // 红紫
    [Color(0xFF2E8FA3), Color(0xFF1B4B63)], // 湖蓝
    [Color(0xFF8F9A6B), Color(0xFF4E5D3A)], // 橄榄
  ];

  static int _hash(String seed) {
    var hash = 0;
    for (final c in seed.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    return hash;
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();
    final size = this.size;
    if (size == null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: content,
          );
        },
      );
    }
    return SizedBox(width: size, height: size, child: content);
  }

  Widget _buildContent() {
    final colors = _palettes[_hash(name) % _palettes.length];
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors[0], colors[1]],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 字号随封面尺寸缩放（约 38% 宽），小卡 ~50px、网格卡 ~50px+，
          // 不随字体缩放差异变形。
          final fontSize =
              (constraints.maxWidth * 0.38).clamp(16.0, 96.0).toDouble();
          return Center(
            child: Text(
              initial,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w700,
                fontSize: fontSize,
                height: 1,
              ),
            ),
          );
        },
      ),
    );
  }
}
