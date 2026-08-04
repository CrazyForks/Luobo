import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../services/subsonic_service.dart';
import '../theme/app_theme.dart';
import '../utils/image_cache.dart';
import '../utils/navigation_helper.dart';
import '../l10n/app_localizations.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import 'playlist_screen.dart';

class LibrarySearchDelegate extends SearchDelegate<String> {
  final LibraryProvider libraryProvider;
  final bool isDark;

  LibrarySearchDelegate({
    required this.libraryProvider,
    required this.isDark,
    String? searchFieldLabel,
  }) : super(
          searchFieldLabel: searchFieldLabel ?? 'Search in Library...',
          searchFieldStyle: TextStyle(
            color: isDark ? Colors.white : Colors.black,
          ),
        );

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppTheme.darkBackground : Colors.white,
        elevation: 0.5,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.search,
              size: 64,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.searchYourLibrary,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black45,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }
    return _buildSearchResults(context);
  }

  Widget _buildSearchResults(BuildContext context) {
    final lowerQuery = query.toLowerCase();

    // Search across all locally cached library data — playlists, artists,
    // albums, and songs — mirroring LibraryProvider._searchLocal.
    final matchingPlaylists = libraryProvider.playlists
        .where((p) => p.name.toLowerCase().contains(lowerQuery))
        .take(20)
        .toList();

    final matchingArtists = libraryProvider.artists
        .where((a) => a.name.toLowerCase().contains(lowerQuery))
        .take(20)
        .toList();

    final matchingAlbums = libraryProvider.cachedAllAlbums
        .where((a) =>
            a.name.toLowerCase().contains(lowerQuery) ||
            (a.artist?.toLowerCase().contains(lowerQuery) ?? false))
        .take(20)
        .toList();

    final matchingSongs = libraryProvider.cachedAllSongs
        .where((s) =>
            s.title.toLowerCase().contains(lowerQuery) ||
            (s.artist?.toLowerCase().contains(lowerQuery) ?? false) ||
            (s.album?.toLowerCase().contains(lowerQuery) ?? false))
        .take(50)
        .toList();

    final totalMatches = matchingPlaylists.length +
        matchingArtists.length +
        matchingAlbums.length +
        matchingSongs.length;

    if (totalMatches == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.search,
              size: 64,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.noPlaylistsFound,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black45,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    final l10n = AppLocalizations.of(context)!;
    return ListView(
      children: [
        if (matchingPlaylists.isNotEmpty) ...[
          _SectionHeader(title: l10n.playlists),
          ...matchingPlaylists.map(
            (p) => ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: AppTheme.appleMusicRed.withValues(alpha: 0.2),
                ),
                child: const Icon(
                  CupertinoIcons.music_note_list,
                  color: AppTheme.appleMusicRed,
                ),
              ),
              title: Text(p.name),
              subtitle: Text(l10n.songsCount(p.songCount ?? 0)),
              onTap: () {
                close(context, '');
                NavigationHelper.push(
                  context,
                  PlaylistScreen(
                    playlistId: p.id,
                    playlistName: p.name,
                  ),
                );
              },
            ),
          ),
        ],
        if (matchingArtists.isNotEmpty) ...[
          _SectionHeader(title: l10n.artists),
          ...matchingArtists.map(
            (a) => ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.appleMusicRed.withValues(alpha: 0.15),
                ),
                child: const Icon(
                  CupertinoIcons.mic_fill,
                  color: AppTheme.appleMusicRed,
                  size: 22,
                ),
              ),
              title: Text(a.name),
              subtitle: Text(l10n.albumsCount(a.albumCount ?? 0)),
              onTap: () {
                close(context, '');
                NavigationHelper.push(
                  context,
                  ArtistScreen(artistId: a.id),
                );
              },
            ),
          ),
        ],
        if (matchingAlbums.isNotEmpty) ...[
          _SectionHeader(title: l10n.albums),
          ...matchingAlbums.map(
            (a) => ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                ),
                child: _albumThumbnail(context, a.coverArt, size: 48),
              ),
              title: Text(a.name),
              subtitle: Text(a.artist ?? ''),
              onTap: () {
                close(context, '');
                NavigationHelper.push(
                  context,
                  AlbumScreen(albumId: a.id),
                );
              },
            ),
          ),
        ],
        if (matchingSongs.isNotEmpty) ...[
          _SectionHeader(title: l10n.songs),
          ...matchingSongs.map(
            (s) => ListTile(
              leading: _albumThumbnail(context, s.coverArt, size: 48),
              title: Text(s.title),
              subtitle: Text(
                '${s.artist ?? l10n.unknownArtist}${s.album != null ? ' \u2022 ${s.album}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                close(context, '');
                final player = Provider.of<PlayerProvider>(
                  context,
                  listen: false,
                );
                player.playSong(s, playlist: matchingSongs);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _albumThumbnail(BuildContext context, String? coverArt,
      {double size = 48}) {
    if (coverArt == null || coverArt.isEmpty) {
      return Icon(
        CupertinoIcons.music_albums,
        size: size,
        color: Colors.grey,
      );
    }
    final url = Provider.of<SubsonicService>(context, listen: false)
        .getCoverArtUrl(coverArt, size: kCoverArtRequestSize);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: url.isNotEmpty
          ? Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(CupertinoIcons.music_albums,
                  size: size, color: Colors.grey),
            )
          : Icon(CupertinoIcons.music_albums, size: size, color: Colors.grey),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
    );
  }
}
