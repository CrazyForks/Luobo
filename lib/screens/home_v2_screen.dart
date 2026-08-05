import 'dart:io';
import 'dart:math';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../services/home_recommendation_service.dart';
import '../services/playback_context_tracker.dart';
import '../services/recommendation_service.dart';
import '../utils/navigation_helper.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/widgets.dart';
import 'ai_playlist_screen.dart';
import 'album_screen.dart';
import 'favorites_screen.dart';
import 'history_screen.dart';
import 'playlist_screen.dart';
import 'settings_screen.dart';
import 'song_list_screen.dart';

/// 新首页（§5.1，Apple Music「现在就听」风格，v2 独立实现）。
///
/// 数据说明：P3 起由 `HomeRecommendationService.generateFeed` 提供
/// （每日推荐 / 3 个场景 Mix / 探索发现，行为×图谱融合 + 全局去重）；
/// 继续播放 / 最近播放 / 你的歌单来自 RecommendationService 与 LibraryProvider。
class HomeV2Screen extends StatefulWidget {
  const HomeV2Screen({super.key});

  @override
  State<HomeV2Screen> createState() => _HomeV2ScreenState();
}

class _HomeV2ScreenState extends State<HomeV2Screen> {
  HomeFeed? _cachedFeed;
  String _lastRandomKey = '';

  bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    final l10n = AppLocalizations.of(context)!;
    if (hour < 12) return l10n.goodMorning;
    if (hour < 17) return l10n.goodAfternoon;
    return l10n.goodEvening;
  }

  String _computeRandomKey(List<Song> songs) =>
      songs.isEmpty ? '' : songs.map((s) => s.id).join('|');

  Future<void> _handleRefresh() async {
    final libraryProvider = Provider.of<LibraryProvider>(
      context,
      listen: false,
    );
    await libraryProvider.refresh();
  }

  void _play(
    BuildContext context,
    Song song,
    List<Song> playlist,
    int index,
  ) {
    Provider.of<PlayerProvider>(context, listen: false).playSong(
      song,
      playlist: playlist,
      startIndex: index,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tokens = HomeV2Tokens.of(context);
    final hPad = _isDesktop ? 32.0 : 16.0;
    final columns = _isDesktop ? 4 : 2;

    return Scaffold(
      backgroundColor: tokens.background,
      body: EasyRefresh.builder(
        header: ClassicHeader(
          dragText: '下拉刷新',
          armedText: '释放刷新',
          readyText: '正在刷新...',
          processingText: '正在刷新...',
          processedText: '刷新完成',
          iconTheme: IconThemeData(
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          showMessage: false,
          triggerOffset: 60,
          position: IndicatorPosition.locator,
        ),
        onRefresh: _handleRefresh,
        childBuilder: (context, physics) => CustomScrollView(
          physics: physics,
          slivers: [
            SliverAppBar(
              pinned: true,
              floating: true,
              expandedHeight: _isDesktop ? 80 : 70,
              backgroundColor: tokens.background,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: EdgeInsets.only(left: hPad, bottom: 14),
                title: Text(
                  _getGreeting(),
                  style: TextStyle(
                    fontSize: _isDesktop ? 28 : 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    Icons.auto_awesome_rounded,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  tooltip: AppLocalizations.of(context)!.aiPlaylist,
                  onPressed: () => NavigationHelper.push(
                    context,
                    const AiPlaylistScreen(),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.settings_rounded,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  tooltip: AppLocalizations.of(context)!.settings,
                  onPressed: () => NavigationHelper.push(
                    context,
                    const SettingsScreen(),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.history_rounded,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  onPressed: () =>
                      NavigationHelper.push(context, const HistoryScreen()),
                ),
                if (_isDesktop) const SizedBox(width: 8),
              ],
            ),
            const HeaderLocator.sliver(),
            SliverToBoxAdapter(
              child: Consumer4<LibraryProvider, RecommendationService,
                  HomeRecommendationService, PlaybackContextTracker>(
                builder: (context, libraryProvider, recommendationService,
                    homeRecommendation, playbackTracker, _) {
                  if (libraryProvider.isLoading &&
                      !libraryProvider.isInitialized) {
                    return Padding(
                      padding: EdgeInsets.only(top: 120),
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  }

                  // P3：候选池用全量曲库（全量同步未完成时回退随机池）。
                  final allSongs = libraryProvider.cachedAllSongs.isNotEmpty
                      ? libraryProvider.cachedAllSongs
                      : libraryProvider.randomSongs;
                  final key = _computeRandomKey(allSongs);

                  if (recommendationService.enabled && key.isNotEmpty) {
                    if (key != _lastRandomKey) {
                      _cachedFeed = homeRecommendation.generateFeed(
                        allSongs: allSongs,
                      );
                      _lastRandomKey = key;
                    }
                  } else {
                    _cachedFeed = null;
                    _lastRandomKey = '';
                  }

                  final feed = _cachedFeed;
                  final daily = feed?.daily ?? const <Song>[];

                  if (allSongs.isEmpty && (feed == null || feed.isEmpty)) {
                    return _buildEmptyState(hPad, isDark);
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      _buildDailyCard(context, daily, libraryProvider, hPad),
                      _buildContinueListening(
                        context,
                        recommendationService,
                        allSongs,
                        libraryProvider,
                        hPad,
                      ),
                      const SizedBox(height: 16),
                      _buildMadeForYou(
                        context,
                        feed,
                        libraryProvider,
                        hPad,
                        columns,
                      ),
                      const SizedBox(height: 16),
                      _buildRecentlyPlayed(
                        context,
                        playbackTracker,
                        libraryProvider,
                        hPad,
                      ),
                      const SizedBox(height: 16),
                      _buildPlaylists(context, libraryProvider, hPad),
                      const SizedBox(height: 16),
                      _buildDiscover(
                        context,
                        feed?.discover ?? const [],
                        libraryProvider,
                        hPad,
                        columns,
                      ),
                      // 视口已排除迷你播放器与底部导航，尾部仅留少量呼吸空间。
                      const SizedBox(height: 32),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 模块构建
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildDailyCard(
    BuildContext context,
    List<Song> daily,
    LibraryProvider libraryProvider,
    double hPad,
  ) {
    if (daily.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    // 每次进入首页从 30 首里随机抽一张有封面的歌展示（封面定期换）。
    final cover = _randomDailyCover(libraryProvider, daily);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: DailyRecommendationCard(
        title: l10n.dailyRecommendation,
        coverArt: cover,
        imageUrl: cover == null ? null : libraryProvider.getCoverArtUrl(cover),
        onTap: () => NavigationHelper.push(
          context,
          SongListScreen(
            title: l10n.dailyRecommendation,
            songs: daily,
            slogans: [
              l10n.dailySlogan1,
              l10n.dailySlogan2,
              l10n.dailySlogan3,
            ],
            imageUrl: cover == null
                ? null
                : libraryProvider.getCoverArtUrl(cover),
          ),
        ),
        onPlayAll: () => _play(context, daily.first, daily, 0),
      ),
    );
  }

  /// 从每日推荐里随机抽一个有封面的歌，返回其封面 ID；无则 null。
  String? _randomDailyCover(LibraryProvider p, List<Song> songs) {
    final covers = songs
        .map((s) => p.effectiveCoverArt(s))
        .where((c) => c != null && c.isNotEmpty)
        .toList();
    if (covers.isEmpty) return null;
    return covers[Random().nextInt(covers.length)];
  }

  Widget _buildContinueListening(
    BuildContext context,
    RecommendationService recommendationService,
    List<Song> allSongs,
    LibraryProvider libraryProvider,
    double hPad,
  ) {
    // 最近播放歌曲优先从全量曲库映射，避免被 50 首随机池漏掉（用户反馈）。
    final pool = libraryProvider.cachedAllSongs.isNotEmpty
        ? libraryProvider.cachedAllSongs
        : allSongs;
    final byId = {for (final s in pool) s.id: s};
    // 多行横滑：2 行 × 每行 5 个 = 10 首，横滑 5 下看全（用户反馈）。
    const rows = 2;
    const perRow = 5;
    final recent = recommendationService.recentlyPlayed
        .map((id) => byId[id])
        .whereType<Song>()
        .take(rows * perRow)
        .toList();
    if (recent.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;

    const cardWidth = 200.0;
    const cardHeight = 72.0;
    const rowSpacing = 10.0;
    const colSpacing = 12.0;
    final gridHeight = rows * cardHeight + (rows - 1) * rowSpacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: SectionHeader(title: l10n.continueListening),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: gridHeight,
          child: GridView.builder(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            scrollDirection: Axis.horizontal,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: rows,
              crossAxisSpacing: rowSpacing,
              mainAxisSpacing: colSpacing,
              childAspectRatio: cardHeight / cardWidth,
            ),
            itemCount: recent.length,
            itemBuilder: (context, index) {
              final song = recent[index];
              return ContinuePlayingCard(
                song: song,
                coverArt: libraryProvider.effectiveCoverArt(song),
                width: cardWidth,
                onTap: () => _play(context, song, recent, index),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMadeForYou(
    BuildContext context,
    HomeFeed? feed,
    LibraryProvider libraryProvider,
    double hPad,
    int columns,
  ) {
    final l10n = AppLocalizations.of(context)!;
    // P3：真实场景 Mix（通勤活力/专注学习/睡前放松，知识图谱标签过滤）+ 你的最爱。
    final commute = feed?.commuteMix ?? const <Song>[];
    final study = feed?.studyMix ?? const <Song>[];
    final sleep = feed?.sleepMix ?? const <Song>[];
    final favorites = feed?.favorites ?? const <Song>[];

    MixCardData mixCard(
      String title,
      List<Song> songs, {
      List<String> slogans = const [],
    }) {
      final coverUrl = _firstCoverUrl(libraryProvider, songs);
      return MixCardData(
        title: title,
        // 2×2 拼贴封面（≤4 张不同封面），避免多个 Mix 撞同一封面。
        coverArts: songs.isEmpty ? null : _collageCovers(libraryProvider, songs),
        disabled: songs.isEmpty,
        onTap: songs.isEmpty
            ? null
            : () => NavigationHelper.push(
                  context,
                  SongListScreen(
                    title: title,
                    songs: songs,
                    slogans: slogans,
                    imageUrl: coverUrl,
                  ),
                ),
      );
    }

    return MixGridSection(
      title: l10n.madeForYou,
      hPad: hPad,
      columns: columns,
      cards: [
        mixCard(
          l10n.commuteMix,
          commute,
          slogans: [l10n.commuteSlogan1, l10n.commuteSlogan2, l10n.commuteSlogan3],
        ),
        mixCard(
          l10n.studyMix,
          study,
          slogans: [l10n.studySlogan1, l10n.studySlogan2, l10n.studySlogan3],
        ),
        mixCard(
          l10n.sleepMix,
          sleep,
          slogans: [l10n.sleepSlogan1, l10n.sleepSlogan2, l10n.sleepSlogan3],
        ),
        mixCard(
          l10n.favoritesMix,
          favorites,
          slogans: [
            l10n.favoritesSlogan1,
            l10n.favoritesSlogan2,
            l10n.favoritesSlogan3,
          ],
        ),
      ],
    );
  }

  /// 取最多 4 张不同封面用于 Mix 拼贴。
  List<String> _collageCovers(LibraryProvider p, List<Song> songs) {
    final seen = <String>{};
    final out = <String>[];
    for (final song in songs.take(10)) {
      final cover = p.effectiveCoverArt(song);
      if (cover != null && cover.isNotEmpty && seen.add(cover)) {
        out.add(cover);
        if (out.length == 4) break;
      }
    }
    return out;
  }

  /// 列表第一首有封面的歌的封面 URL（二级页 hero 取色用）。
  String? _firstCoverUrl(LibraryProvider p, List<Song> songs) {
    for (final song in songs) {
      final cover = p.effectiveCoverArt(song);
      if (cover != null && cover.isNotEmpty) {
        return p.getCoverArtUrl(cover);
      }
    }
    return null;
  }

  Widget _buildRecentlyPlayed(
    BuildContext context,
    PlaybackContextTracker tracker,
    LibraryProvider libraryProvider,
    double hPad,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final collections = tracker.items;
    final albums = libraryProvider.recentAlbums;
    if (collections.isEmpty && albums.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[
      // 最近播放的歌单/收藏（本地记录，最新在前，2×2 拼图封面）。
      for (final item in collections.take(6))
        _CollectionCardV2(
          name: item.name,
          coverArts: item.coverArts,
          size: 150,
          onTap: () {
            if (item.kind == 'starred') {
              NavigationHelper.push(context, const FavoritesScreen());
            } else {
              NavigationHelper.push(
                context,
                PlaylistScreen(playlistId: item.id, playlistName: item.name),
              );
            }
          },
        ),
      // 最近播放的专辑（服务端 recentAlbums 顺序）。
      for (final album in albums.take(10))
        AlbumCard(
          album: album,
          size: 150,
          onTap: () => NavigationHelper.push(
            context,
            AlbumScreen(albumId: album.id),
          ),
        ),
    ];

    return HorizontalScrollSection(
      title: l10n.recentlyPlayed,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      cardSize: 150,
      children: children,
    );
  }

  Widget _buildPlaylists(
    BuildContext context,
    LibraryProvider libraryProvider,
    double hPad,
  ) {
    if (libraryProvider.playlists.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return HorizontalScrollSection(
      title: l10n.yourPlaylists,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      cardSize: 150,
      children: libraryProvider.playlists
          .take(10)
          .map(
            (playlist) => _PlaylistCardV2(
              playlist: playlist,
              size: 150,
              onTap: () => NavigationHelper.push(
                context,
                PlaylistScreen(
                  playlistId: playlist.id,
                  playlistName: playlist.name,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildDiscover(
    BuildContext context,
    List<Song> discover,
    LibraryProvider libraryProvider,
    double hPad,
    int columns,
  ) {
    if (discover.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return MixGridSection(
      title: l10n.discover,
      hPad: hPad,
      columns: columns,
      onSeeAllTap: () => NavigationHelper.push(
        context,
        SongListScreen(
          title: l10n.discover,
          songs: discover,
          slogans: [
            l10n.discoverSlogan1,
            l10n.discoverSlogan2,
            l10n.discoverSlogan3,
          ],
          imageUrl: _firstCoverUrl(libraryProvider, discover),
        ),
      ),
      cards: discover.take(8).map((song) {
        final index = discover.indexOf(song);
        return MixCardData(
          title: song.title,
          subtitle: song.artist,
          coverArt: libraryProvider.effectiveCoverArt(song),
          round: false,
          onTap: () => _play(context, song, discover, index),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyState(double hPad, bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 80),
      child: Column(
        children: [
          Icon(
            Icons.music_note_rounded,
            size: 64,
            color: isDark ? Colors.white24 : Colors.black26,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noContentAvailable,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.tryRefreshing,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Provider.of<LibraryProvider>(
              context,
              listen: false,
            ).refresh(),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.refresh),
          ),
        ],
      ),
    );
  }
}

/// 歌单横滑卡（新首页「你的歌单」模块，§5.1 模块 5）。
class _PlaylistCardV2 extends StatelessWidget {
  final Playlist playlist;
  final double size;
  final VoidCallback onTap;

  const _PlaylistCardV2({
    required this.playlist,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = HomeV2Tokens.of(context);
    return SizedBox(
      width: size,
      child: PressableScale(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AlbumArtwork(coverArt: playlist.coverArt, size: size, borderRadius: 8),
            const SizedBox(height: 8),
            Text(
              playlist.name,
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
              '${playlist.songCount}',
              style: TextStyle(fontSize: 12, color: tokens.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}

/// 最近播放的歌单/收藏卡（§5.1「最近播放」混合区，2×2 拼图封面）。
class _CollectionCardV2 extends StatelessWidget {
  final String name;
  final List<String> coverArts;
  final double size;
  final VoidCallback onTap;

  const _CollectionCardV2({
    required this.name,
    required this.coverArts,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: PressableScale(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: coverArts.isNotEmpty
                  ? CoverCollage(coverArts: coverArts)
                  : AlbumArtwork(coverArt: null, size: size, borderRadius: 8),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
