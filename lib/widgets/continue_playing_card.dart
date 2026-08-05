import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/album_artwork.dart';
import '../widgets/pressable_scale.dart';
import 'home_v2_tokens.dart';

/// 继续播放小卡（§5.1 模块 2）：封面 + 歌名/歌手 + 圆形播放按钮，点击续播。
class ContinuePlayingCard extends StatelessWidget {
  final Song song;
  final String? coverArt;
  final VoidCallback onTap;
  final double width;

  const ContinuePlayingCard({
    super.key,
    required this.song,
    this.coverArt,
    required this.onTap,
    this.width = 200,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist ?? '',
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
          ),
        ),
      ),
    );
  }
}
