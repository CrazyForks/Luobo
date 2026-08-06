import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/album_artwork.dart';
import '../widgets/pressable_scale.dart';
import 'home_v2_tokens.dart';

/// 歌曲横卡（§5.1 模块 2）：封面 + 歌名/歌手 + 圆形播放按钮，点击播放。
/// 播放按钮与歌名行数可配：探索发现（§8-9）隐藏按钮、歌名允许两行——未听过的
/// 歌重点是认歌名，按钮意义不大。
class ContinuePlayingCard extends StatelessWidget {
  final Song song;
  final String? coverArt;
  final VoidCallback onTap;
  final double width;
  final bool showPlayButton;
  final int titleMaxLines;
  final String? subtitle;

  const ContinuePlayingCard({
    super.key,
    required this.song,
    this.coverArt,
    required this.onTap,
    this.width = 200,
    this.showPlayButton = true,
    this.titleMaxLines = 1,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = HomeV2Tokens.of(context);
    return SizedBox(
      width: width,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: tokens.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tokens.cardBorder, width: 0.8),
          ),
          child: Row(
            children: [
              AlbumArtwork(
                coverArt: coverArt,
                size: 52,
                borderRadius: 10,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: titleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle ?? song.artist ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: tokens.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              if (showPlayButton) ...[
                const SizedBox(width: 6),
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: AppTheme.appleMusicRed,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
