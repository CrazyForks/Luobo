import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/artist_ref.dart';
import '../models/song.dart';
import '../utils/navigation_helper.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../services/jukebox_service.dart';
import '../services/player_ui_settings_service.dart';
import '../services/subsonic_service.dart';
import '../services/offline_service.dart';
import '../services/transcoding_service.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import 'album_artwork.dart';
import 'animated_equalizer.dart';
import 'dolby_atmos_badge.dart';
import 'glass_surface.dart';
import 'multi_artist_widget.dart';
import 'pressable_scale.dart';
import '../screens/album_screen.dart';
import '../screens/artist_screen.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final List<Song>? playlist;
  final int? index;
  final bool showArtwork;
  final bool showArtist;
  final bool showAlbum;
  final bool showDuration;
  final bool showTrackNumber;
  final int titleMaxLines;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const SongTile({
    super.key,
    required this.song,
    this.playlist,
    this.index,
    this.showArtwork = true,
    this.showArtist = true,
    this.showAlbum = false,
    this.showDuration = true,
    this.showTrackNumber = false,
    this.titleMaxLines = 1,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Selector<PlayerProvider, String?>(
      selector: (_, provider) => provider.currentSong?.id,
      builder: (context, currentSongId, _) {
        final isCurrentSong = currentSongId == song.id;

        return PressableScale(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: _buildLeading(context, isCurrentSong),
            title: Text(
              song.title,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: isCurrentSong
                    ? Theme.of(context).colorScheme.primary
                    : null,
                fontWeight:
                    isCurrentSong ? FontWeight.w600 : FontWeight.normal,
              ),
              maxLines: titleMaxLines,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle:
                showArtist || showAlbum ? _buildSubtitleWidget(theme) : null,
            trailing: _buildTrailing(context),
            onTap: onTap ?? () => _playSong(context),
            onLongPress: onLongPress ?? () => _showOptions(context),
          ),
        );
      },
    );
  }

  Widget? _buildLeading(BuildContext context, bool isCurrentSong) {
    if (showTrackNumber && !showArtwork) {
      return SizedBox(
        width: 30,
        child: Center(
          child: isCurrentSong
              ? Selector<PlayerProvider, bool>(
                  selector: (ctx, p) => p.isPlaying,
                  builder: (ctx, isPlaying, __) => AnimatedEqualizer(
                    color: Theme.of(context).colorScheme.primary,
                    isPlaying: isPlaying,
                  ),
                )
              : Text(
                  '${song.track ?? index ?? 1}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.lightSecondaryText,
                      ),
                ),
        ),
      );
    }

    if (showArtwork) {
      return ValueListenableBuilder<double>(
        valueListenable: PlayerUiSettingsService().albumArtCornerRadiusNotifier,
        builder: (context, radius, _) {
          return Stack(
            children: [
              AlbumArtwork(
                coverArt: song.coverArt,
                size: 50,
                preserveAspectRatio: true,
              ),
              if (isCurrentSong)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(radius),
                    ),
                    child: Center(
                      child: Selector<PlayerProvider, bool>(
                        selector: (ctx, p) => p.isPlaying,
                        builder: (ctx, isPlaying, __) => AnimatedEqualizer(
                          color: Colors.white,
                          isPlaying: isPlaying,
                        ),
                      ),
                    ),
                  ),
                ),
              // Quality tag (original file info / actual transcode state)
              // overlaid on the artwork corner — takes no layout space.
              _buildQualityTag(context, isCurrentSong) ??
                  const SizedBox.shrink(),
            ],
          );
        },
      );
    }

    return null;
  }

  Widget _buildSubtitleWidget(ThemeData theme) {
    if (showArtist) {
      if (showAlbum && song.album != null) {
        // Merge artist + album into a single line. Shrink the font when it
        // doesn't fit instead of hard-splitting the width between the two.
        final artistLabel = _artistLabel();
        final fullText = '$artistLabel \u2022 ${song.album}';
        final baseStyle = theme.textTheme.bodySmall ??
            const TextStyle(fontSize: 12);
        final baseSize = baseStyle.fontSize ?? 12;
        return LayoutBuilder(
          builder: (context, constraints) {
            var size = baseSize;
            while (size > 10 &&
                _textWidth(fullText, baseStyle, size) > constraints.maxWidth) {
              size -= 1;
            }
            return Text(
              fullText,
              style: baseStyle.copyWith(fontSize: size),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        );
      }
      return MultiArtistWidget(
        artists: song.artistParticipants,
        artistFallback: song.artist,
        artistIdFallback: song.artistId,
        style: theme.textTheme.bodySmall,
      );
    }

    return Text(
      song.album ?? '',
      style: theme.textTheme.bodySmall,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _artistLabel() {
    final participants = song.artistParticipants;
    if (participants != null && participants.isNotEmpty) {
      return participants.map((a) => a.name).join(', ');
    }
    return song.artist ?? '';
  }

  static double _textWidth(String text, TextStyle base, double fontSize) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: base.copyWith(fontSize: fontSize)),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  /// Tiny quality tag overlaid on the artwork's bottom-right corner, e.g.
  /// "FLAC·964" (original file info) or "Opus·192" in orange when the
  /// current song's actual stream is transcoded. Takes no layout space.
  Widget? _buildQualityTag(BuildContext context, bool isCurrentSong) {
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final isTranscoded = isCurrentSong && player.isActiveStreamTranscoded;
    final transcodeBitrate = player.activeStreamBitrate;
    final transcodeFormat = player.activeStreamFormat;

    final format = isTranscoded
        ? TranscodeFormat.getLabel(transcodeFormat ?? '')
        : (song.suffix?.toUpperCase() ?? '');
    final bitrate = isTranscoded ? transcodeBitrate : song.bitRate;

    final parts = <String>[];
    if (format.isNotEmpty && format != 'Original') parts.add(format);
    if (bitrate != null && bitrate > 0) parts.add('$bitrate');
    if (parts.isEmpty) return null;
    final label = parts.join('·');

    final l10n = AppLocalizations.of(context)!;
    final network =
        Provider.of<TranscodingService>(context, listen: false)
            .currentConnectionType ==
        ConnectionType.wifi
            ? l10n.networkWifi
            : l10n.networkMobile;
    final tooltip = isTranscoded
        ? l10n.transcodedTo(
            TranscodeFormat.getLabel(transcodeFormat ?? ''),
            transcodeBitrate ?? 0,
            network,
          )
        : l10n.noTranscoding;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: BoxDecoration(
            color: (isTranscoded ? const Color(0xFFE65100) : Colors.black)
                .withValues(alpha: 0.65),
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(2)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 7,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrailing(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (song.starred == true)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              CupertinoIcons.heart_fill,
              size: 14,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.7),
            ),
          ),
        if (song.hasDolbyAtmos == true)
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: DolbyAtmosBadge(),
          ),
        if (showDuration)
          Text(
            song.formattedDuration,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.more_horiz),
          iconSize: 20,
          color: Theme.of(context).textTheme.bodySmall?.color,
          onPressed: () => _showOptions(context),
        ),
      ],
    );
  }

  void _playSong(BuildContext context) {
    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);
    playerProvider.playSong(song, playlist: playlist, startIndex: index);
  }

  void _showOptions(BuildContext context) {
    showGlassBottomSheet(
      context: context,
      builder: (context) => _SongOptionsSheet(song: song),
    );
  }
}

class _SongOptionsSheet extends StatefulWidget {
  final Song song;

  const _SongOptionsSheet({required this.song});

  @override
  State<_SongOptionsSheet> createState() => _SongOptionsSheetState();
}

class _SongOptionsSheetState extends State<_SongOptionsSheet> {
  late bool _isStarred;
  bool _isDownloaded = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  final _offlineService = OfflineService();

  @override
  void initState() {
    super.initState();
    _isStarred = widget.song.starred ?? false;
    _checkDownloadStatus();
  }

  void _checkDownloadStatus() {
    _isDownloaded = _offlineService.isSongDownloaded(widget.song.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  AlbumArtwork(coverArt: widget.song.coverArt, size: 60),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.song.title,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.song.artist != null)
                          Text(
                            widget.song.artist!,
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Compact audio quality info, shown directly in the sheet so no
            // navigation / sheet-stacking is needed.
            const SizedBox(height: 16),
            _QualityInfo(song: widget.song),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _OptionTile(
                      icon: _isStarred
                          ? CupertinoIcons.heart_fill
                          : CupertinoIcons.heart,
                      title: _isStarred
                          ? l10n.removeFromLikedSongs
                          : l10n.addToLikedSongs,
                      iconColor: _isStarred
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      onTap: () async {
                        await _toggleFavorite(context);
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                    _OptionTile(
                      icon: Icons.play_arrow_rounded,
                      title: l10n.playNext,
                      onTap: () {
                        playerProvider.addToQueueNext(widget.song);
                        Navigator.pop(context);
                      },
                    ),
                    _OptionTile(
                      icon: Icons.queue_music_rounded,
                      title: l10n.addToQueue,
                      onTap: () {
                        playerProvider.addToQueue(widget.song);
                        Navigator.pop(context);
                      },
                    ),
                    Builder(
                      builder: (context) {
                        final jukebox = Provider.of<JukeboxService>(
                          context,
                          listen: false,
                        );
                        final subsonic = Provider.of<SubsonicService>(
                          context,
                          listen: false,
                        );
                        if (!jukebox.enabled) return const SizedBox.shrink();
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _OptionTile(
                              icon: Icons.speaker_rounded,
                              title: AppLocalizations.of(
                                context,
                              )!
                                  .playOnJukebox,
                              onTap: () {
                                Navigator.pop(context);
                                jukebox.setQueue(
                                    subsonic,
                                    [
                                      widget.song,
                                    ],
                                    startIndex: 0);
                              },
                            ),
                            _OptionTile(
                              icon: Icons.queue_rounded,
                              title: AppLocalizations.of(
                                context,
                              )!
                                  .addToJukeboxQueue,
                              onTap: () {
                                Navigator.pop(context);
                                jukebox.addToQueue(subsonic, [widget.song]);
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    _OptionTile(
                      icon: Icons.playlist_add_rounded,
                      title: AppLocalizations.of(context)!.addToPlaylist,
                      onTap: () {
                        Navigator.pop(context);
                        _showPlaylistPicker(context, widget.song);
                      },
                    ),
                    _OptionTile(
                      icon: Icons.album_rounded,
                      title: l10n.goToAlbum,
                      onTap: () {
                        Navigator.pop(context);
                        if (widget.song.albumId != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  AlbumScreen(albumId: widget.song.albumId!),
                            ),
                          );
                        }
                      },
                    ),
                    _OptionTile(
                      icon: Icons.person_rounded,
                      title: l10n.goToArtist,
                      onTap: () {
                        final nav = Navigator.of(context);
                        nav.pop();
                        _navigateToArtist(nav);
                      },
                    ),
                    _buildRatingTile(context),
                    _buildDownloadTile(context),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadTile(BuildContext context) {
    final isOffline = Provider.of<AuthProvider>(context, listen: false).state ==
        AuthState.offlineMode;

    if (_isDownloading) {
      return ListTile(
        leading: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            value: _downloadProgress > 0 ? _downloadProgress : null,
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          AppLocalizations.of(
            context,
          )!
              .downloading((_downloadProgress * 100).toInt()),
        ),
      );
    }

    if (_isDownloaded) {
      return _OptionTile(
        icon: Icons.download_done_rounded,
        title: AppLocalizations.of(context)!.downloaded,
        iconColor: Colors.green,
        onTap: () async {
          final l10n = AppLocalizations.of(context)!;
          final messenger = ScaffoldMessenger.of(context);
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(AppLocalizations.of(context)!.removeDownload),
              content: Text(
                AppLocalizations.of(context)!.removeDownloadConfirm,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(AppLocalizations.of(context)!.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(AppLocalizations.of(context)!.remove),
                ),
              ],
            ),
          );
          if (confirm == true) {
            await _offlineService.deleteSong(widget.song.id);
            if (mounted) {
              setState(() {
                _isDownloaded = false;
              });
              messenger.showSnackBar(
                SnackBar(
                  content: Text(l10n.downloadRemoved),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        },
      );
    }

    if (isOffline) return const SizedBox.shrink();

    return _OptionTile(
      icon: Icons.download_rounded,
      title: AppLocalizations.of(context)!.download,
      onTap: () => _downloadSong(context),
    );
  }

  Future<void> _downloadSong(BuildContext context) async {
    final subsonicService = Provider.of<SubsonicService>(
      context,
      listen: false,
    );
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      final success = await _offlineService.downloadSong(
        widget.song,
        subsonicService,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _isDownloaded = success;
        });

        if (success) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.downloadedTitle(widget.song.title)),
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.downloadFailed),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.downloadError(e)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildRatingTile(BuildContext context) {
    final rating = widget.song.userRating ?? 0;
    final l10n = AppLocalizations.of(context)!;
    return _OptionTile(
      icon: Icons.star_rounded,
      title: rating > 0
          ? l10n.rateSongWithRating(rating)
          : l10n.rateSong,
      iconColor: rating > 0 ? Colors.amber : null,
      onTap: () => _showRatingDialog(context),
    );
  }

  Future<void> _showRatingDialog(BuildContext context) async {
    final currentRating = widget.song.userRating ?? 0;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.rateSong),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.song.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starValue = index + 1;
                return Flexible(
                  child: IconButton(
                    icon: Icon(
                      starValue <= currentRating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: Colors.amber,
                      size: 32,
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _setRating(context, starValue);
                    },
                  ),
                );
              }),
            ),
            if (currentRating > 0) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _setRating(context, 0);
                },
                child: Text(AppLocalizations.of(ctx)!.removeRating),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
        ],
      ),
    );
  }

  Future<void> _setRating(BuildContext context, int rating) async {
    final subsonicService = Provider.of<SubsonicService>(
      context,
      listen: false,
    );
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    try {
      await subsonicService.setRating(widget.song.id, rating);

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              rating > 0
                  ? l10n.songRated(rating)
                  : l10n.ratingRemoved,
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.failedToSetRating(e)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _toggleFavorite(BuildContext context) async {
    final subsonicService = Provider.of<SubsonicService>(
      context,
      listen: false,
    );
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    try {
      if (_isStarred) {
        await subsonicService.unstar(id: widget.song.id);
        setState(() {
          _isStarred = false;
        });
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.removedFromLikedSongs),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        await subsonicService.star(id: widget.song.id);
        setState(() {
          _isStarred = true;
        });
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.addedToLikedSongs),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('${l10n.error}: ${e.toString()}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _navigateToArtist(NavigatorState nav) {
    final participants = widget.song.artistParticipants;

    if (participants != null && participants.length > 1) {
      final ctx = NavigationHelper.navigatorKey.currentContext;
      if (ctx == null) return;
      showGlassBottomSheet(
        context: ctx,
        builder: (sheetCtx) => ArtistsBottomSheet(
          artists: participants,
          onArtistTap: (artist) {
            Navigator.pop(sheetCtx);
            _pushArtist(nav, artist);
          },
        ),
      );
      return;
    }

    final single = participants?.firstOrNull;
    if (single != null) {
      _pushArtist(nav, single);
      return;
    }

    final artistId = widget.song.artistId;
    if (artistId != null && artistId.isNotEmpty) {
      nav.push(
        MaterialPageRoute(builder: (_) => ArtistScreen(artistId: artistId)),
      );
    }
  }

  void _pushArtist(NavigatorState nav, ArtistRef artist) {
    if (artist.id.isNotEmpty) {
      nav.push(
        MaterialPageRoute(builder: (_) => ArtistScreen(artistId: artist.id)),
      );
    }
  }

  void _showPlaylistPicker(BuildContext context, Song song) {
    final libraryProvider = Provider.of<LibraryProvider>(
      context,
      listen: false,
    );

    showGlassBottomSheet(
      context: context,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppTheme.darkSurface
              : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Text(
                    AppLocalizations.of(context)!.addToPlaylist,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (libraryProvider.playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(AppLocalizations.of(context)!.noPlaylists),
              )
            else
              ...libraryProvider.playlists.map(
                (playlist) => ListTile(
                  leading: const Icon(Icons.queue_music_rounded),
                  title: Text(playlist.name),
                  subtitle: Text(
                    AppLocalizations.of(
                      context,
                    )!
                        .songsCount(playlist.songCount ?? 0),
                  ),
                  onTap: () async {
                    Navigator.pop(context);

                    final subsonicService = Provider.of<SubsonicService>(
                      context,
                      listen: false,
                    );
                    final l10n = AppLocalizations.of(context)!;
                    final messenger = ScaffoldMessenger.of(context);

                    try {
                      debugPrint(
                        'Attempting to add song ${song.id} (${song.title}) to playlist ${playlist.id} (${playlist.name})',
                      );

                      await subsonicService.updatePlaylist(
                        playlistId: playlist.id,
                        songIdsToAdd: [song.id],
                      );

                      debugPrint('Successfully added song to playlist via API');

                      await libraryProvider.loadPlaylists();

                      debugPrint('Playlists refreshed');

                      messenger.showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l10n.addedToPlaylist(
                                    song.title,
                                    playlist.name,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          duration: const Duration(seconds: 2),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } catch (e) {
                      debugPrint('Error adding song to playlist: $e');
                      messenger.showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(Icons.error, color: Colors.white),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(l10n.errorAddingToPlaylist(e)),
                              ),
                            ],
                          ),
                          duration: const Duration(seconds: 3),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Compact quality info shown inline in the song options sheet — no
/// navigation or stacking. Displays original file info plus the actual
/// transcode state of the current stream, or the settings-implied state
/// for songs that aren't currently playing.
class _QualityInfo extends StatelessWidget {
  final Song song;

  const _QualityInfo({required this.song});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final transcoding = Provider.of<TranscodingService>(context);

    // Original file info
    final format = song.suffix?.toUpperCase() ?? '';
    final bitrate = song.bitRate;
    final size = song.formattedSize;

    final fileParts = <String>[];
    if (format.isNotEmpty) fileParts.add(format);
    if (bitrate != null && bitrate > 0) fileParts.add('$bitrate kbps');
    if (size.isNotEmpty) fileParts.add(size);
    final fileInfo = fileParts.join(' · ');
    final sampleInfo = song.formattedSampleRate;
    final depthInfo = song.bitDepth != null ? '${song.bitDepth} bit' : '';

    // Transcode status — actual for the current stream, settings-implied
    // otherwise.
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final isCurrent =
        player.currentSong?.id == song.id && !player.isPlayingRadio;
    final network =
        transcoding.currentConnectionType == ConnectionType.wifi
            ? l10n.networkWifi
            : l10n.networkMobile;
    String statusLabel;
    Color? statusColor;
    IconData statusIcon;
    if (isCurrent && player.isActiveStreamTranscoded) {
      statusLabel = l10n.transcodedTo(
        TranscodeFormat.getLabel(player.activeStreamFormat ?? ''),
        player.activeStreamBitrate ?? 0,
        network,
      );
      statusColor = isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
      statusIcon = Icons.speed_rounded;
    } else if (!isCurrent && transcoding.getCurrentBitrate() != null) {
      final wouldTranscode = l10n.transcodedTo(
        TranscodeFormat.getLabel(transcoding.getCurrentFormat() ?? ''),
        transcoding.getCurrentBitrate() ?? 0,
        network,
      );
      statusLabel = '${l10n.streamWillTranscode}：$wouldTranscode';
      statusIcon = Icons.speed_rounded;
    } else {
      statusLabel = l10n.noTranscoding;
      statusIcon = Icons.verified_rounded;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fileInfo.isNotEmpty)
            Text(
              fileInfo,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (sampleInfo.isNotEmpty || depthInfo.isNotEmpty)
            Text(
              [sampleInfo, depthInfo].where((s) => s.isNotEmpty).join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(statusIcon, size: 14, color: statusColor),
              const SizedBox(width: 4),
              Text(
                statusLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: statusColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? iconColor;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: iconColor ?? Theme.of(context).colorScheme.primary,
      ),
      title: Text(title),
      onTap: onTap,
    );
  }
}
