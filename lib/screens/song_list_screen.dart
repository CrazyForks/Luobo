import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import '../utils/image_cache.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/widgets.dart';

/// 通用歌曲列表页：首页「每日推荐 / 场景 Mix / 你的最爱 / 探索发现」详情页。
///
/// 布局（多轮反馈收敛）：
/// - 顶部渐变 hero（约屏高 38%）：背景跟随列表首歌封面取色（vibrant 优先，
///   暗化 45%→原色；取不到/过亮回退红→紫红）；内容仅一句随机 slogan，
///   放在接近底部位置（大标题去掉，导航栏 34pt 标题承担列表名）
/// - 三键（随机播放 / 播放 / 加入当前播放列表）紧跟 hero 下方
/// - 歌曲列表一体滚动；背景默认主题
class SongListScreen extends StatefulWidget {
  final String title;
  final List<Song> songs;

  /// 候选 slogan 组（每次进入随机展示一句）。
  final List<String> slogans;

  /// 首歌封面图片 URL，用于 hero 渐变取色。
  final String? imageUrl;

  const SongListScreen({
    super.key,
    required this.title,
    required this.songs,
    this.slogans = const [],
    this.imageUrl,
  });

  @override
  State<SongListScreen> createState() => _SongListScreenState();
}

class _SongListScreenState extends State<SongListScreen> {
  String? _slogan;
  Color? _palette;

  /// 纯白等亮色封面回退的亮度阈值。
  static const double _maxLuminance = 0.5;

  double get _heroHeight => MediaQuery.of(context).size.height * 0.38;

  @override
  void initState() {
    super.initState();
    // 每次进入页面随机选一句 slogan。
    if (widget.slogans.isNotEmpty) {
      _slogan = widget.slogans[Random().nextInt(widget.slogans.length)];
    }
    _extractPalette();
  }

  @override
  void didUpdateWidget(covariant SongListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _extractPalette();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _extractPalette() async {
    final url = widget.imageUrl;
    if (url == null || url.isEmpty) {
      if (_palette != null && mounted) setState(() => _palette = null);
      return;
    }
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        // 与展示图同一 300 URL + coverCacheManager，命中共享磁盘缓存
        // （图片缓存文档 §4.2/§4.3：取色不重复下载）。
        CachedNetworkImageProvider(url, cacheManager: coverCacheManager),
        maximumColorCount: 12,
      );
      final color = palette.vibrantColor?.color ??
          palette.dominantColor?.color;
      if (color == null || color.computeLuminance() > _maxLuminance) {
        if (_palette != null && mounted) setState(() => _palette = null);
        return;
      }
      final darkened = Color.lerp(color, Colors.black, 0.45)!;
      if (!mounted || darkened == _palette) return;
      setState(() => _palette = darkened);
    } catch (_) {
      if (_palette != null && mounted) setState(() => _palette = null);
    }
  }

  void _playAll() {
    if (widget.songs.isEmpty) return;
    Provider.of<PlayerProvider>(context, listen: false).playSong(
      widget.songs.first,
      playlist: widget.songs,
      startIndex: 0,
    );
  }

  void _playShuffle() {
    if (widget.songs.isEmpty) return;
    final shuffled = [...widget.songs]..shuffle();
    Provider.of<PlayerProvider>(context, listen: false).playSong(
      shuffled.first,
      playlist: shuffled,
      startIndex: 0,
    );
  }

  void _addToQueue() {
    if (widget.songs.isEmpty) return;
    Provider.of<PlayerProvider>(context, listen: false)
        .addAllToQueue(widget.songs);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.addedToQueue),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final heroGradient = _palette != null
        ? LinearGradient(
            colors: [
              Color.lerp(_palette, Colors.black, 0.45)!,
              _palette!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [AppTheme.appleMusicRed, Color(0xFFA02E8C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: _heroHeight,
            // 折叠后与渐变底部同色（跟随取色）。
            backgroundColor:
                _palette != null
                    ? Color.lerp(_palette, Colors.black, 0.2)!
                    : const Color(0xFFA02E8C),
            foregroundColor: Colors.white,
            title: Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                decoration: BoxDecoration(gradient: heroGradient),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Text(
                      _slogan ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _buildHeaderButtons(context, l10n)),
          if (widget.songs.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  l10n.noContentAvailable,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: widget.songs.length,
              itemBuilder: (context, index) {
                final song = widget.songs[index];
                return SongTile(
                  song: song,
                  playlist: widget.songs,
                  index: index,
                  showArtist: true,
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  /// Apple Music 式三键：左随机 / 中播放 / 右加入当前播放列表（跟随滚动）。
  Widget _buildHeaderButtons(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: _SideAction(
              icon: Icons.shuffle_rounded,
              label: l10n.shuffle,
              onTap: _playShuffle,
            ),
          ),
          _PlayCircle(onTap: _playAll),
          Expanded(
            child: _SideAction(
              icon: Icons.playlist_add_rounded,
              label: l10n.addToCurrentQueue,
              onTap: _addToQueue,
            ),
          ),
        ],
      ),
    );
  }
}

class _SideAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SideAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return PressableScale(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onSurface, size: 26),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: onSurface),
          ),
        ],
      ),
    );
  }
}

/// 中央大播放圆钮（Apple Music 详情页风格）。
class _PlayCircle extends StatelessWidget {
  final VoidCallback onTap;

  const _PlayCircle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 58,
        height: 58,
        decoration: const BoxDecoration(
          color: AppTheme.appleMusicRed,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: 34,
        ),
      ),
    );
  }
}
