import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lpinyin/lpinyin.dart';
import '../models/song.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../providers/providers.dart';
import '../services/subsonic_service.dart';
import '../services/local_music_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_surface.dart';
import '../widgets/pressable_scale.dart';
import '../utils/navigation_helper.dart';
import '../utils/image_cache.dart';
import 'album_screen.dart';
import 'package:luobo/screens/playlist_screen.dart';
import 'favorites_screen.dart';
import 'liked_albums_screen.dart';
import 'playlists_screen.dart';
import 'ai_playlist_screen.dart';
import 'settings_screen.dart';
import 'library_search_delegate.dart';
import 'artist_screen.dart';
import 'radio_screen.dart';
import 'all_songs_screen.dart';
import '../l10n/app_localizations.dart';
import '../widgets/album_artwork.dart' show isLocalFilePath;

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _selectedFilter = 'Artists';
  double _swipeDelta = 0;

  // Artists tab scrubber
  final ScrollController _artistsScrollController = ScrollController();
  String? _selectedLetter;
  Map<String, int> _letterIndexMap = {};

  @override
  void dispose() {
    _artistsScrollController.dispose();
    super.dispose();
  }

  // Reuse generated cover URLs across rebuilds (stable per server+coverArt+size).
  static final Map<String, String> _coverUrlCache = {};

  static String _coverUrl(SubsonicService service, String coverArt) {
    final key = '${service.activeBaseUrl}_${coverArt}_$kCoverArtRequestSize';
    return _coverUrlCache.putIfAbsent(
      key,
      () => service.getCoverArtUrl(coverArt, size: kCoverArtRequestSize),
    );
  }

  /// First letter grouping for the Artists tab index. Uses pinyin for
  /// Chinese characters so 周杰伦 → Z, 韩红 → H, etc. ASCII A-Z stay as
  /// themselves. Everything else (numbers, symbols) goes to '#'.
  static String _firstLetter(String name) {
    if (name.isEmpty) return '#';
    final first = name[0];
    final code = first.codeUnitAt(0);
    // ASCII A-Z / a-z
    if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)) {
      return first.toUpperCase();
    }
    // Chinese → pinyin first letter (getShortPinyin returns lowercase)
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(first)) {
      try {
        final py = PinyinHelper.getShortPinyin(first);
        if (py.isNotEmpty) {
          final letter = py[0].toUpperCase();
          if (letter.codeUnitAt(0) >= 0x41 && letter.codeUnitAt(0) <= 0x5A) {
            return letter;
          }
        }
      } catch (_) {}
    }
    return '#';
  }

  List<String> _getFilters(BuildContext context) {
    final libraryProvider =
        Provider.of<LibraryProvider>(context, listen: false);
    if (libraryProvider.isLocalOnlyMode) {
      return ['Artists', 'Albums', 'Songs', 'Faves', 'Genres', 'Years'];
    }
    return ['Artists', 'Albums', 'Songs', 'Faves'];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: GestureDetector(
        onHorizontalDragUpdate: (details) {
          _swipeDelta += details.delta.dx;
        },
        onHorizontalDragEnd: (details) {
          final filters = _getFilters(context);
          final idx = filters.indexOf(_selectedFilter);
          final velocity = details.primaryVelocity ?? 0;
          final distance = _swipeDelta.abs();
          _swipeDelta = 0;
          // Require both enough distance AND speed to avoid accidental triggers
          if (distance < 30 || velocity.abs() < 300) return;
          if (velocity < 0 && idx < filters.length - 1) {
            setState(() => _selectedFilter = filters[idx + 1]);
          } else if (velocity > 0 && idx > 0) {
            setState(() => _selectedFilter = filters[idx - 1]);
          }
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              floating: true,
              expandedHeight: 60,
              title: Text(
                AppLocalizations.of(context)!.yourLibrary,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    CupertinoIcons.refresh,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  onPressed: () {
                    final libraryProvider = Provider.of<LibraryProvider>(
                      context,
                      listen: false,
                    );
                    libraryProvider.refresh();
                  },
                ),
                IconButton(
                  icon: Icon(
                    CupertinoIcons.search,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  onPressed: () => _showLibrarySearch(context),
                ),
                IconButton(
                  icon: Icon(
                    CupertinoIcons.plus,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  onPressed: () => _showAddPlaylistMenu(context),
                ),
                IconButton(
                  icon: Icon(
                    CupertinoIcons.gear,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  onPressed: () => _showSettings(context),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Builder(
                builder: (context) {
                  final l10n = AppLocalizations.of(context)!;
                  final filters = _getFilters(context);
                  final filterLabels = {
                    'Faves': l10n.faves,
                    'Albums': l10n.filterAlbums,
                    'Artists': l10n.filterArtists,
                    'Songs': l10n.songs,
                    'Genres': l10n.genres,
                    'Years': l10n.years,
                  };
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: filters.map((filter) {
                        final isSelected = _selectedFilter == filter;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(filterLabels[filter]!),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _selectedFilter = selected ? filter : 'Faves';
                              });
                            },
                            backgroundColor: isDark
                                ? const Color(0xFF282828)
                                : Colors.grey[200],
                            selectedColor: isDark ? Colors.white : Colors.black,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? (isDark ? Colors.black : Colors.white)
                                  : (isDark ? Colors.white : Colors.black),
                              fontWeight: FontWeight.w500,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            side: BorderSide.none,
                            showCheckmark: false,
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Column(
                  key: ValueKey(_selectedFilter),
                  children: [
                    if (_selectedFilter == 'Faves') ...[
                      // Playlists folder
                      _SpotifyLibraryTile(
                        icon: CupertinoIcons.list_bullet,
                        iconColor: const Color(0xFF3B82F6),
                        title: AppLocalizations.of(context)!.playlists,
                        subtitle: AppLocalizations.of(context)!.yourPlaylists,
                        isGradient: false,
                        onTap: () =>
                            _navigate(context, const PlaylistsScreen()),
                      ),
                      // Liked Songs folder
                      _SpotifyLibraryTile(
                        icon: CupertinoIcons.heart_fill,
                        iconColor: const Color(0xFF8B5CF6),
                        title: AppLocalizations.of(context)!.likedSongs,
                        subtitle: AppLocalizations.of(context)!.playlist,
                        isGradient: true,
                        onTap: () =>
                            _navigate(context, const FavoritesScreen()),
                      ),
                      // All Songs folder
                      _SpotifyLibraryTile(
                        icon: CupertinoIcons.music_note_list,
                        iconColor: const Color(0xFF34C759),
                        title: AppLocalizations.of(context)!.songs,
                        subtitle: AppLocalizations.of(context)!.songs,
                        isGradient: false,
                        onTap: () => _navigate(context, const AllSongsScreen()),
                      ),
                      // Liked Albums folder
                      _SpotifyLibraryTile(
                        icon: CupertinoIcons.star_fill,
                        iconColor: const Color(0xFFFF9500),
                        title: AppLocalizations.of(context)!.likedAlbums,
                        subtitle: AppLocalizations.of(context)!.albums,
                        isGradient: false,
                        onTap: () =>
                            _navigate(context, const LikedAlbumsScreen()),
                      ),
                      // Radio Stations folder
                      _SpotifyLibraryTile(
                        icon: CupertinoIcons.antenna_radiowaves_left_right,
                        iconColor: const Color(0xFF34C759),
                        title: AppLocalizations.of(context)!.radioStations,
                        subtitle: AppLocalizations.of(context)!.internetRadio,
                        isGradient: false,
                        onTap: () => _navigate(context, const RadioScreen()),
                      ),
                    ],
                  ],
                ), // Column (AnimatedSwitcher child)
              ), // AnimatedSwitcher
            ), // SliverToBoxAdapter
            Consumer<LibraryProvider>(
              builder: (context, libraryProvider, _) {
                final items = _getFilteredItems(context, libraryProvider);

                if (items.isEmpty && _selectedFilter != 'Artists') {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _LibraryEmptyState(
                      isLocalMode: libraryProvider.isLocalOnlyMode,
                    ),
                  );
                }

                // Artists tab: chip waterfall grouped by pinyin first letter,
                // with a right-edge scrubber for quick navigation.
                if (_selectedFilter == 'Artists') {
                  final artists = libraryProvider.artists.toList()
                    ..sort((a, b) => a.name.compareTo(b.name));
                  if (artists.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: _LibraryEmptyState(
                        isLocalMode: libraryProvider.isLocalOnlyMode,
                      ),
                    );
                  }
                  final isDark =
                      Theme.of(context).brightness == Brightness.dark;
                  // Song counts per artist come from LibraryProvider (computed
                  // once per library change, not per rebuild).
                  final artistSongCounts = libraryProvider.artistSongCounts;
                  final groups = <String, List<Artist>>{};
                  for (final a in artists) {
                    final letter = _firstLetter(a.name);
                    groups.putIfAbsent(letter, () => []).add(a);
                  }
                  final letters = groups.keys.toList()..sort();
                  final l10n = AppLocalizations.of(context)!;
                  _letterIndexMap = {};
                  double offset = 0;
                  const headerH = 30.0;
                  const chipRowH = 36.0;
                  for (final letter in letters) {
                    _letterIndexMap[letter] = offset.round();
                    offset += headerH;
                    final rows = (groups[letter]!.length / 3).ceil();
                    offset += rows * chipRowH + 8;
                  }
                  return SliverFillRemaining(
                    hasScrollBody: true,
                    child: Stack(
                      children: [
                        ListView(
                          controller: _artistsScrollController,
                          padding: const EdgeInsets.only(bottom: 80),
                          children: [
                            for (final letter in letters) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text(
                                  letter,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? AppTheme.darkSecondaryText
                                        : AppTheme.lightSecondaryText,
                                  ),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 28, 8),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: groups[letter]!.map((a) {
                                    return GestureDetector(
                                      onTap: () => _openItem(
                                        context,
                                        _LibraryItem(
                                          type: 'Artist',
                                          id: a.id,
                                          name: a.name,
                                          subtitle: '',
                                        ),
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white10
                                              : Colors.black
                                                  .withValues(alpha: 0.06),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              a.name,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black87,
                                              ),
                                            ),
                                            Builder(builder: (ctx) {
                                              final songCount =
                                                  artistSongCounts[a.id];
                                              if (songCount == null ||
                                                  songCount == 0) {
                                                return const SizedBox.shrink();
                                              }
                                              return Text(
                                                l10n.songsCount(songCount),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isDark
                                                      ? Colors.white60
                                                      : Colors.black45,
                                                ),
                                              );
                                            }),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: _ArtistScrubber(
                            letters: letters,
                            selectedLetter: _selectedLetter,
                            onLetterDown: (letter) {
                              final idx = _letterIndexMap[letter];
                              if (idx != null &&
                                  _artistsScrollController.hasClients) {
                                _artistsScrollController.jumpTo(
                                  idx.toDouble().clamp(
                                        0.0,
                                        _artistsScrollController
                                            .position.maxScrollExtent,
                                      ),
                                );
                              }
                              setState(() => _selectedLetter = letter);
                            },
                            onLetterUp: () =>
                                setState(() => _selectedLetter = null),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (items.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _LibraryEmptyState(
                      isLocalMode: libraryProvider.isLocalOnlyMode,
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = items[index];
                    return _buildLibraryItem(context, item);
                  }, childCount: items.length),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 150)),
          ],
        ), // CustomScrollView
      ), // GestureDetector
    ); // Scaffold
  }

  List<_LibraryItem> _getFilteredItems(
    BuildContext context,
    LibraryProvider provider,
  ) {
    final l10n = AppLocalizations.of(context)!;
    List<_LibraryItem> items = [];

    // Faves tab: show Playlists and Recent Albums
    if (_selectedFilter == 'Faves') {
      // Add playlists
      items.addAll(
        provider.playlists.map(
          (p) => _LibraryItem(
            type: 'Playlist',
            id: p.id,
            name: p.name,
            subtitle: l10n.songsCount(p.songCount ?? 0),
            coverArt: p.coverArt,
          ),
        ),
      );
      // Add recent albums (limited to 10)
      final recent = provider.isLocalOnlyMode
          ? provider.cachedAllAlbums.take(10).toList()
          : provider.recentAlbums.take(10).toList();
      items.addAll(
        recent.map(
          (a) => _LibraryItem(
            type: 'Album',
            id: a.id,
            name: a.name,
            subtitle:
                a.artistParticipants != null && a.artistParticipants!.isNotEmpty
                    ? a.artistParticipants!.map((r) => r.name).join(', ')
                    : (a.artist ?? ''),
            coverArt: a.coverArt,
          ),
        ),
      );
    }

    // Albums tab: show all albums
    if (_selectedFilter == 'Albums') {
      final albums = provider.isLocalOnlyMode
          ? provider.cachedAllAlbums
          : (provider.cachedAllAlbums.isNotEmpty
              ? provider.cachedAllAlbums
              : provider.recentAlbums);
      items.addAll(
        albums.map(
          (a) => _LibraryItem(
            type: 'Album',
            id: a.id,
            name: a.name,
            subtitle: () {
              final artistStr = a.artistParticipants != null &&
                      a.artistParticipants!.isNotEmpty
                  ? a.artistParticipants!.map((r) => r.name).join(', ')
                  : (a.artist ?? '');
              if (a.year != null && artistStr.isNotEmpty) {
                return '$artistStr • ${a.year}';
              }
              return artistStr.isNotEmpty
                  ? artistStr
                  : (a.year?.toString() ?? '');
            }(),
            coverArt: a.coverArt,
          ),
        ),
      );
    }

    if (_selectedFilter == 'Artists') {
      items.addAll(
        provider.artists.map(
          (a) => _LibraryItem(
            type: 'Artist',
            id: a.id,
            name: a.name,
            subtitle: l10n.albumsCount(a.albumCount ?? 0),
            coverArt: a.coverArt,
          ),
        ),
      );
    }

    if (_selectedFilter == 'Songs') {
      items.addAll(
        provider.cachedAllSongs.map(
          (s) => _LibraryItem(
            type: 'Song',
            id: s.id,
            name: s.title,
            subtitle: s.artist ?? '',
            coverArt: s.coverArt,
          ),
        ),
      );
    }

    if (_selectedFilter == 'Genres') {
      final genreMap = <String, List<Song>>{};
      for (final s in provider.cachedAllSongs) {
        final g = (s.genre ?? 'Unknown').trim();
        if (g.isEmpty) continue;
        genreMap.putIfAbsent(g, () => []).add(s);
      }
      final sortedGenres = genreMap.keys.toList()..sort();
      items.addAll(
        sortedGenres.map(
          (g) => _LibraryItem(
            type: 'Genre',
            id: 'genre_$g',
            name: g,
            subtitle: l10n.songsCount(genreMap[g]!.length),
            coverArt: genreMap[g]!
                    .firstWhere(
                      (s) => s.coverArt != null,
                      orElse: () => genreMap[g]!.first,
                    )
                    .coverArt ??
                '',
          ),
        ),
      );
    }

    if (_selectedFilter == 'Years') {
      final yearMap = <int, List<Album>>{};
      for (final a in provider.cachedAllAlbums) {
        if (a.year != null) {
          yearMap.putIfAbsent(a.year!, () => []).add(a);
        }
      }
      final sortedYears = yearMap.keys.toList()..sort((a, b) => b.compareTo(a));
      items.addAll(
        sortedYears.map(
          (y) => _LibraryItem(
            type: 'Year',
            id: 'year_$y',
            name: y.toString(),
            subtitle: l10n.albumsCount(yearMap[y]!.length),
            coverArt: yearMap[y]!
                    .firstWhere(
                      (a) => a.coverArt != null,
                      orElse: () => yearMap[y]!.first,
                    )
                    .coverArt ??
                '',
          ),
        ),
      );
    }

    return items;
  }

  Widget _buildLibraryItem(BuildContext context, _LibraryItem item) {
    // Alphabetical section header (Artists tab).
    if (item.type == 'SectionHeader') {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          item.name,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark
                ? AppTheme.darkSecondaryText
                : AppTheme.lightSecondaryText,
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    // Artist rows: text-only (icons all grey placeholders).
    if (item.type == 'Artist') {
      return InkWell(
        onTap: () => _openItem(context, item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // All other item types: standard artwork + text layout.
    final subsonicService = Provider.of<SubsonicService>(
      context,
      listen: false,
    );
    final coverArtUrl = item.coverArt != null
        ? (isLocalFilePath(item.coverArt)
            ? item.coverArt!
            : _coverUrl(subsonicService, item.coverArt!))
        : null;

    final String typeLabel = switch (item.type) {
      'Playlist' => l10n.filterPlaylists,
      'Album' => l10n.filterAlbums,
      'Song' => l10n.songs,
      _ => item.type,
    };

    final Widget artwork = ClipRRect(
      borderRadius: BorderRadius.circular(item.type == 'Artist' ? 28 : 4),
      child: SizedBox(
        width: 56,
        height: 56,
        child: coverArtUrl != null
            ? (isLocalFilePath(coverArtUrl)
                ? Image.file(
                    File(coverArtUrl),
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) =>
                        _buildPlaceholder(item.type, isDark),
                  )
                : CachedNetworkImage(
                    cacheManager: coverCacheManager,
                    imageUrl: coverArtUrl,
                    fit: BoxFit.cover,
                    placeholder: (ctx, url) =>
                        Container(color: Colors.grey[800]),
                    errorWidget: (ctx, url, err) =>
                        _buildPlaceholder(item.type, isDark),
                  ))
            : _buildPlaceholder(item.type, isDark),
      ),
    );

    return PressableScale(
      onTap: () => _openItem(context, item),
      child: InkWell(
        onTap: () => _openItem(context, item),
        onLongPress: item.type == 'Playlist'
            ? () => _showDeletePlaylistDialog(context, item)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              artwork,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$typeLabel • ${item.subtitle}',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(String type, bool isDark) {
    IconData icon;
    switch (type) {
      case 'Playlist':
        icon = Icons.queue_music;
        break;
      case 'Album':
        icon = Icons.album;
        break;
      case 'Artist':
        icon = Icons.person;
        break;
      case 'Song':
        icon = Icons.music_note;
        break;
      case 'Genre':
        icon = Icons.local_offer;
        break;
      case 'Year':
        icon = Icons.calendar_today;
        break;
      default:
        icon = Icons.music_note;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF2C2C2E), const Color(0xFF1C1C1E)]
              : [const Color(0xFFF2F2F7), const Color(0xFFE5E5EA)],
        ),
        borderRadius: BorderRadius.circular(type == 'Artist' ? 28 : 4),
      ),
      child: Center(
        child: Icon(
          icon,
          size: 24,
          color: isDark ? Colors.white24 : Colors.black12,
        ),
      ),
    );
  }

  void _openItem(BuildContext context, _LibraryItem item) {
    switch (item.type) {
      case 'Playlist':
        NavigationHelper.push(
          context,
          PlaylistScreen(playlistId: item.id, playlistName: item.name),
        );
        break;
      case 'Album':
        NavigationHelper.push(context, AlbumScreen(albumId: item.id));
        break;
      case 'Artist':
        NavigationHelper.push(context, ArtistScreen(artistId: item.id));
        break;
      case 'Song':
        final libraryProvider = Provider.of<LibraryProvider>(
          context,
          listen: false,
        );
        final playerProvider = Provider.of<PlayerProvider>(
          context,
          listen: false,
        );
        final songs = libraryProvider.cachedAllSongs;
        final index = songs.indexWhere((s) => s.id == item.id);
        if (index >= 0) {
          playerProvider.playSong(
            songs[index],
            playlist: songs,
            startIndex: index,
          );
        }
        break;
      case 'Genre':
        final genreName = item.name;
        final libraryProvider = Provider.of<LibraryProvider>(
          context,
          listen: false,
        );
        final songs = libraryProvider.cachedAllSongs
            .where((s) => s.genre == genreName)
            .toList();
        if (songs.isNotEmpty) {
          final playerProvider = Provider.of<PlayerProvider>(
            context,
            listen: false,
          );
          playerProvider.playSong(songs.first, playlist: songs, startIndex: 0);
        }
        break;
      case 'Year':
        final yearStr = item.name;
        final libraryProvider = Provider.of<LibraryProvider>(
          context,
          listen: false,
        );
        final albums = libraryProvider.cachedAllAlbums
            .where((a) => a.year?.toString() == yearStr)
            .toList();
        if (albums.isNotEmpty) {
          NavigationHelper.push(context, AlbumScreen(albumId: albums.first.id));
        }
        break;
    }
  }

  void _navigate(BuildContext context, Widget screen) {
    NavigationHelper.push(context, screen);
  }

  void _showDeletePlaylistDialog(BuildContext context, _LibraryItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deletePlaylist),
        content: Text(
          AppLocalizations.of(context)!.deletePlaylistConfirmation(item.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final libraryProvider = Provider.of<LibraryProvider>(
                context,
                listen: false,
              );
              try {
                await libraryProvider.deletePlaylist(item.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(
                          context,
                        )!
                            .playlistDeleted(item.name),
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context)!.errorDeletingPlaylist(e),
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );
  }

  void _showAddPlaylistMenu(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final outerContext = context;
    showGlassBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(
                CupertinoIcons.music_note_list,
                color: isDark ? Colors.white : Colors.black,
              ),
              title: Text(
                '新建歌单',
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
              subtitle: Text(
                '手动创建一个空白歌单',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                // Wait for bottom sheet dismiss animation to complete
                await Future.delayed(const Duration(milliseconds: 300));
                if (outerContext.mounted) {
                  _showCreatePlaylistDialog(outerContext);
                }
              },
            ),
            ListTile(
              leading: Icon(
                Icons.auto_awesome,
                color: isDark ? Colors.white : Colors.black,
              ),
              title: Text(
                'AI 智能生成',
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
              subtitle: Text(
                '根据听歌习惯、场景或描述自动生成歌单',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await Future.delayed(const Duration(milliseconds: 300));
                if (outerContext.mounted) {
                  Navigator.push(
                    outerContext,
                    MaterialPageRoute(builder: (_) => const AiPlaylistScreen()),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreatePlaylistDialog(BuildContext context) async {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    // Capture provider from outer context before entering dialog
    final libraryProvider =
        Provider.of<LibraryProvider>(context, listen: false);

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.newPlaylist),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: l10n.playlistName,
              filled: true,
              fillColor:
                  isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                final name = controller.text.trim();
                Navigator.pop(dialogContext);
                try {
                  await libraryProvider.createPlaylist(name);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.playlistCreated(name)),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.errorCreatingPlaylist(e)),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              }
            },
            child: Text(l10n.create),
          ),
        ],
      ),
    );
  }

  void _showLibrarySearch(BuildContext context) {
    final libraryProvider = Provider.of<LibraryProvider>(
      context,
      listen: false,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showSearch(
      context: context,
      delegate: LibrarySearchDelegate(
        libraryProvider: libraryProvider,
        isDark: isDark,
        searchFieldLabel: AppLocalizations.of(context)!.searchInLibrary,
      ),
    );
  }

  void _showSettings(BuildContext context) {
    NavigationHelper.push(context, const SettingsScreen());
  }
}

class _LibraryEmptyState extends StatelessWidget {
  final bool isLocalMode;

  const _LibraryEmptyState({required this.isLocalMode});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_music_outlined,
            size: 64,
            color: isDark ? Colors.white24 : Colors.black26,
          ),
          const SizedBox(height: 16),
          Text(
            isLocalMode ? l10n.localLibraryEmpty : l10n.libraryEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isLocalMode
                ? l10n.localLibraryEmptySubtitle
                : l10n.libraryEmptySubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          if (isLocalMode) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                final localService = Provider.of<LocalMusicService>(
                  context,
                  listen: false,
                );
                if (!localService.isScanning) {
                  localService.scanForMusic();
                }
              },
              icon: const Icon(Icons.refresh),
              label: Text(l10n.scanForMusic),
              style: ElevatedButton.styleFrom(
                foregroundColor: isDark ? Colors.black : Colors.white,
                backgroundColor: isDark ? Colors.white : Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Right-edge letter scrubber for the Artists tab.
class _ArtistScrubber extends StatelessWidget {
  final List<String> letters;
  final String? selectedLetter;
  final ValueChanged<String> onLetterDown;
  final VoidCallback onLetterUp;

  const _ArtistScrubber({
    required this.letters,
    required this.selectedLetter,
    required this.onLetterDown,
    required this.onLetterUp,
  });

  @override
  Widget build(BuildContext context) {
    if (letters.length <= 1) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      onVerticalDragDown: (d) =>
          _onPos(d.localPosition, context.size?.height ?? 1),
      onVerticalDragUpdate: (d) =>
          _onPos(d.localPosition, context.size?.height ?? 1),
      onVerticalDragEnd: (_) => onLetterUp(),
      onLongPressMoveUpdate: (d) =>
          _onPos(d.localPosition, context.size?.height ?? 1),
      child: Container(
        width: 28,
        padding: const EdgeInsets.only(right: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: letters.map((l) {
            final isSelected = l == selectedLetter;
            return Expanded(
              child: Center(
                child: Text(
                  l,
                  style: TextStyle(
                    fontSize: isSelected ? 12 : 10,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? AppTheme.appleMusicRed
                        : (isDark ? Colors.white54 : Colors.black45),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _onPos(Offset local, double height) {
    final fraction = (local.dy / height).clamp(0.0, 1.0);
    final idx =
        (fraction * letters.length).floor().clamp(0, letters.length - 1);
    onLetterDown(letters[idx]);
  }
}

class _LibraryItem {
  final String type;
  final String id;
  final String name;
  final String subtitle;
  final String? coverArt;

  _LibraryItem({
    required this.type,
    required this.id,
    required this.name,
    required this.subtitle,
    this.coverArt,
  });
}

class _SpotifyLibraryTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isGradient;
  final VoidCallback? onTap;

  const _SpotifyLibraryTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.isGradient = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: isGradient
                    ? LinearGradient(
                        colors: [iconColor.withValues(alpha: 0.8), iconColor],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isGradient ? null : iconColor.withValues(alpha: 0.15),
              ),
              child: Icon(
                icon,
                color: isGradient ? Colors.white : iconColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
