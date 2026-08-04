import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_surface.dart';
import '../l10n/app_localizations.dart';

enum SongSortOption {
  titleAsc,
  titleDesc,
  artistAsc,
  artistDesc,
  albumAsc,
  albumDesc,
  recentlyAdded,
}

class AllSongsScreen extends StatefulWidget {
  const AllSongsScreen({super.key});

  @override
  State<AllSongsScreen> createState() => _AllSongsScreenState();
}

class _AllSongsScreenState extends State<AllSongsScreen> {
  List<Song> _songs = [];
  List<Song> _sortedSongs = [];
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();
  SongSortOption _currentSort = SongSortOption.titleAsc;
  LibraryProvider? _libraryProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCachedData());
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _libraryProvider?.removeListener(_onLibraryChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {}

  void _onLibraryChanged() {
    if (!mounted) return;
    final provider = _libraryProvider;
    if (provider == null) return;
    final songs = provider.cachedAllSongs;
    if (songs.length != _songs.length || songs.isEmpty != _songs.isEmpty) {
      setState(() {
        _songs = songs;
        _sortSongs();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCachedData() async {
    final libraryProvider = Provider.of<LibraryProvider>(
      context,
      listen: false,
    );
    _libraryProvider = libraryProvider;
    libraryProvider.addListener(_onLibraryChanged);

    // Returns immediately when the cache is empty; the background sync
    // notifies this screen via _onLibraryChanged when data is ready.
    await libraryProvider.ensureLibraryLoaded();

    if (mounted) {
      setState(() {
        _songs = libraryProvider.cachedAllSongs;
        _sortSongs();
        _isLoading = false;
      });
    }
  }

  void _sortSongs() {
    _sortedSongs = List.from(_songs);
    switch (_currentSort) {
      case SongSortOption.titleAsc:
        _sortedSongs.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case SongSortOption.titleDesc:
        _sortedSongs.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
        break;
      case SongSortOption.artistAsc:
        _sortedSongs.sort(
          (a, b) => (a.artist ?? '').toLowerCase().compareTo(
                (b.artist ?? '').toLowerCase(),
              ),
        );
        break;
      case SongSortOption.artistDesc:
        _sortedSongs.sort(
          (a, b) => (b.artist ?? '').toLowerCase().compareTo(
                (a.artist ?? '').toLowerCase(),
              ),
        );
        break;
      case SongSortOption.albumAsc:
        _sortedSongs.sort(
          (a, b) => (a.album ?? '').toLowerCase().compareTo(
                (b.album ?? '').toLowerCase(),
              ),
        );
        break;
      case SongSortOption.albumDesc:
        _sortedSongs.sort(
          (a, b) => (b.album ?? '').toLowerCase().compareTo(
                (a.album ?? '').toLowerCase(),
              ),
        );
        break;
      case SongSortOption.recentlyAdded:
        _sortedSongs.sort((a, b) {
          final aCreated = a.created;
          final bCreated = b.created;
          if (aCreated == null && bCreated == null) return 0;
          if (aCreated == null) return 1;
          if (bCreated == null) return -1;
          return bCreated.compareTo(aCreated);
        });
        break;
    }
  }

  void _showSortOptions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    showGlassBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.sortBy,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            _buildSortOption(l10n.sortTitleAz, SongSortOption.titleAsc, isDark),
            _buildSortOption(
                l10n.sortTitleZa, SongSortOption.titleDesc, isDark),
            _buildSortOption(
                l10n.sortArtistAz, SongSortOption.artistAsc, isDark),
            _buildSortOption(
                l10n.sortArtistZa, SongSortOption.artistDesc, isDark),
            _buildSortOption(l10n.sortAlbumAz, SongSortOption.albumAsc, isDark),
            _buildSortOption(
                l10n.sortAlbumZa, SongSortOption.albumDesc, isDark),
            _buildSortOption(
              l10n.recentlyAdded,
              SongSortOption.recentlyAdded,
              isDark,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(String title, SongSortOption option, bool isDark) {
    final isSelected = _currentSort == option;
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          color: isSelected
              ? AppTheme.appleMusicRed
              : (isDark ? Colors.white : Colors.black),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing:
          isSelected ? Icon(Icons.check, color: AppTheme.appleMusicRed) : null,
      onTap: () {
        Navigator.pop(context);
        setState(() {
          _currentSort = option;
          _sortSongs();
        });
      },
    );
  }

  void _playAll({bool shuffle = false}) {
    if (_sortedSongs.isEmpty) return;

    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);

    List<Song> playlist = List.from(_sortedSongs);
    if (shuffle) {
      playlist.shuffle();
    }

    playerProvider.playSong(playlist.first, playlist: playlist, startIndex: 0);
  }

  String _getSortLabel() {
    final l10n = AppLocalizations.of(context)!;
    switch (_currentSort) {
      case SongSortOption.titleAsc:
        return l10n.sortTitleAz;
      case SongSortOption.titleDesc:
        return l10n.sortTitleZa;
      case SongSortOption.artistAsc:
        return l10n.sortArtistAz;
      case SongSortOption.artistDesc:
        return l10n.sortArtistZa;
      case SongSortOption.albumAsc:
        return l10n.sortAlbumAz;
      case SongSortOption.albumDesc:
        return l10n.sortAlbumZa;
      case SongSortOption.recentlyAdded:
        return l10n.recentlyAdded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.allSongs),
        actions: [
          if (_sortedSongs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.sort_rounded),
              onPressed: _showSortOptions,
              tooltip: l10n.sortBy,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _songs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.music_note_outlined,
                        size: 64,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.noSongsFound,
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.songsCount(_sortedSongs.length),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                GestureDetector(
                                  onTap: _showSortOptions,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.sort_rounded,
                                        size: 14,
                                        color: AppTheme.appleMusicRed,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _getSortLabel(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.appleMusicRed,
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
                          IconButton(
                            onPressed: () => _playAll(shuffle: true),
                            icon: Icon(
                              Icons.shuffle_rounded,
                              color: isDark ? Colors.white70 : Colors.black54,
                              size: 28,
                            ),
                            tooltip: l10n.shuffle,
                          ),
                          const SizedBox(width: 8),
                          Consumer<PlayerProvider>(
                            builder: (context, playerProvider, _) {
                              final isCurrentPlaylist =
                                  playerProvider.queue.isNotEmpty &&
                                      playerProvider.queue.any(
                                        (song) => _sortedSongs
                                            .any((s) => s.id == song.id),
                                      );
                              final isPlaying =
                                  isCurrentPlaylist && playerProvider.isPlaying;

                              return GestureDetector(
                                onTap: () {
                                  if (isCurrentPlaylist &&
                                      playerProvider.currentSong != null) {
                                    if (playerProvider.isPlaying) {
                                      playerProvider.pause();
                                    } else {
                                      playerProvider.play();
                                    }
                                  } else {
                                    _playAll();
                                  }
                                },
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppTheme.appleMusicRed,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            AppTheme.appleMusicRed.withValues(
                                          alpha: 0.4,
                                        ),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 100),
                        itemCount: _sortedSongs.length,
                        itemBuilder: (context, index) {
                          return SongTile(
                            song: _sortedSongs[index],
                            playlist: _sortedSongs,
                            index: index,
                            showAlbum: true,
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
