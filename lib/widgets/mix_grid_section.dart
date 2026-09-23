import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fluid_mesh_background/fluid_mesh_background.dart';

import '../l10n/app_localizations.dart';
import '../services/diagnostics/diagnostics.dart';
import '../theme/app_theme.dart';
import '../utils/image_cache.dart';
import '../widgets/album_artwork.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/section_header.dart';
import 'home_v2_tokens.dart';

/// 网格卡数据（§5.1 模块 3/6：为你制作 / 探索发现）。
class MixCardData {
  final String title;
  final String? subtitle;
  final String? coverArt;

  /// 流体渐变背景的取色源（封面 URL）。[useFluidGradient] 为 true 时生效。
  final String? imageUrl;

  /// 是否圆形封面。仅在不使用流体渐变时生效（流体恒为方形圆角）。
  final bool round;

  /// 用「封面取色流体渐变」替代封面图（2026-09-23：为你制作 4 卡由 2×2
  /// 拼贴改为流体）。无 [imageUrl] 时回落到默认深色 mesh。
  final bool useFluidGradient;

  final VoidCallback? onTap;

  /// 占位态（如 Mix 暂无内容）：灰态封面 + 「生成中」，不可点击。
  final bool disabled;

  const MixCardData({
    required this.title,
    this.subtitle,
    this.coverArt,
    this.imageUrl,
    this.round = true,
    this.useFluidGradient = false,
    this.onTap,
    this.disabled = false,
  });
}

/// 2 列网格段落（标题 + 查看全部 + 网格卡片），替代旧首页的纵向文字行列表。
///
/// 内部用 [FluidBackgroundScope] 包住整个网格，让 4 张卡的流体背景**共用一个
/// 时钟**（一个 Ticker 而非四个）。
class MixGridSection extends StatefulWidget {
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
  State<MixGridSection> createState() => _MixGridSectionState();
}

class _MixGridSectionState extends State<MixGridSection> {
  bool _modeRecorded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recordModeOnce();
  }

  /// 记录本段用了哪种流体背景。
  ///
  /// 用途：`frame.jank` / `frame.slow` 事件只带 `route`，而首页有多种背景模式，
  /// 无法归属。着色器**是否可用**另有一条 `fluidMeshShader` 事件（来自
  /// `fluid_mesh_background` 包的 `FluidBackgroundEvents`），两条合起来即可判断
  /// 本次运行的实际渲染路径。
  void _recordModeOnce() {
    if (_modeRecorded || widget.cards.isEmpty) return;
    _modeRecorded = true;
    final cards = widget.cards.length;
    // 放到帧后，确保 route observer 已写入当前路由。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DiagnosticsService.instance.record(
        EventType.animActive,
        LogLevel.info,
        {
          'anim': 'mixCardFluidBackground',
          'cards': cards,
          'clock': 'monotonic',
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HomeV2Tokens.of(context);
    final l10n = AppLocalizations.of(context)!;
    if (widget.cards.isEmpty) return const SizedBox.shrink();
    return FluidBackgroundScope(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.hPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: widget.title,
              actionText: widget.onSeeAllTap != null ? l10n.seeAll : null,
              onActionTap: widget.onSeeAllTap,
            ),
            const SizedBox(height: 4),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: widget.columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
                childAspectRatio: widget.columns == 2 ? 0.74 : 0.9,
              ),
              itemCount: widget.cards.length,
              itemBuilder: (context, index) => _MixCard(
                data: widget.cards[index],
                tokens: tokens,
                // 每张卡一套不同的流动图案（45° 方向步进 + 不同噪声区域）
                seed: FluidBackground.seedForIndex(index),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MixCard extends StatelessWidget {
  final MixCardData data;
  final HomeV2Tokens tokens;

  /// 本卡的流体 seed（见 `FluidBackground.seedForIndex`）：决定流动图案。
  final double seed;

  const _MixCard({
    required this.data,
    required this.tokens,
    required this.seed,
  });

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
    } else if (data.useFluidGradient) {
      // 封面取色的「流沙」流体场（`fluid_mesh_background` 包），替代 2×2 拼贴封面。
      // 时钟来自上层 FluidBackgroundScope；着色器不可用时包内自动回落。
      // 传 CachedNetworkImageProvider 是为了复用 App 的封面磁盘/内存缓存，
      // 避免为背景再下载一次同一张封面。
      final url = data.imageUrl;
      cover = FluidBackground(
        imageProvider: url == null || url.isEmpty
            ? null
            : CachedNetworkImageProvider(
                url,
                cacheManager: coverCacheManager,
                cacheKey: coverArtCacheKeyFromUrl(url),
              ),
        borderRadius: 12,
        seed: seed,
      );
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
