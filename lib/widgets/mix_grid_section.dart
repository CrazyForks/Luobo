import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/album_artwork.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/section_header.dart';
import 'home_v2_tokens.dart';

/// 网格卡数据（§5.1 模块 3/6：为你制作 / 探索发现）。
class MixCardData {
  final String title;
  final String? subtitle;
  final String? coverArt;
  final List<String>? coverArts;

  /// 是否圆形封面；[coverArts] 拼贴（≥2 张）时为方形圆角。
  final bool round;
  final VoidCallback? onTap;

  /// 占位态（如 Mix 暂无内容）：灰态封面 + 「生成中」，不可点击。
  final bool disabled;

  const MixCardData({
    required this.title,
    this.subtitle,
    this.coverArt,
    this.coverArts,
    this.round = true,
    this.onTap,
    this.disabled = false,
  });
}

/// 2 列网格段落（标题 + 查看全部 + 网格卡片），替代旧首页的纵向文字行列表。
class MixGridSection extends StatelessWidget {
  final String title;
  final List<MixCardData> cards;
  final VoidCallback? onSeeAllTap;
  final double hPad;
  final int columns;

  const MixGridSection({
    super.key,
    required this.title,
    required this.cards,
    this.onSeeAllTap,
    this.hPad = 16,
    this.columns = 2,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = HomeV2Tokens.of(context);
    final l10n = AppLocalizations.of(context)!;
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: title,
            actionText: onSeeAllTap != null ? l10n.seeAll : null,
            onActionTap: onSeeAllTap,
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              childAspectRatio: columns == 2 ? 0.74 : 0.9,
            ),
            itemCount: cards.length,
            itemBuilder: (context, index) => _MixCard(
              data: cards[index],
              tokens: tokens,
            ),
          ),
        ],
      ),
    );
  }
}

class _MixCard extends StatelessWidget {
  final MixCardData data;
  final HomeV2Tokens tokens;

  const _MixCard({required this.data, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    Widget cover;
    if (data.disabled) {
      cover = Container(
        decoration: BoxDecoration(
          color: tokens.cardBorder.withValues(alpha: 0.4),
          shape: data.round ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: data.round ? null : BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.hourglass_top_rounded,
          color: tokens.secondaryText,
        ),
      );
    } else if (data.coverArts != null && data.coverArts!.isNotEmpty) {
      // 2×2 封面拼贴（Spotify Daily Mix 风格），方形圆角。
      cover = CoverCollage(coverArts: data.coverArts!);
    } else {
      cover = data.round
          ? ClipOval(
              child: AlbumArtwork(coverArt: data.coverArt, borderRadius: 0),
            )
          : AlbumArtwork(coverArt: data.coverArt, borderRadius: 12);
    }

    return PressableScale(
      onTap: data.disabled ? null : data.onTap,
      child: Opacity(
        opacity: data.disabled ? 0.7 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(aspectRatio: 1, child: cover),
            const SizedBox(height: 8),
            Text(
              data.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              data.disabled ? l10n.generating : (data.subtitle ?? ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: tokens.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}

/// 播放按钮角标（网格卡右上角红色圆形播放键），供卡片 hover/常显。
class GridPlayBadge extends StatelessWidget {
  final VoidCallback onTap;

  const GridPlayBadge({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.appleMusicRed,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

/// 2×2 封面拼贴（Spotify Daily Mix 风格），最多 4 张，方形圆角。
class CoverCollage extends StatelessWidget {
  final List<String> coverArts;

  const CoverCollage({super.key, required this.coverArts});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _cell(0)),
                const SizedBox(width: 2),
                Expanded(child: _cell(1)),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _cell(2)),
                const SizedBox(width: 2),
                Expanded(child: _cell(3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(int index) {
    if (index >= coverArts.length) {
      return const ColoredBox(color: Colors.transparent);
    }
    return AlbumArtwork(coverArt: coverArts[index], borderRadius: 0);
  }
}
