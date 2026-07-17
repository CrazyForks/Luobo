import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/cupertino.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/player_provider.dart';
import '../services/subsonic_service.dart';
import '../services/offline_service.dart';
import '../models/lyrics.dart';
import '../models/song.dart';
import '../widgets/album_artwork.dart' show isLocalFilePath;

class CarModeScreen extends StatefulWidget {
  const CarModeScreen({super.key});

  @override
  State<CarModeScreen> createState() => _CarModeScreenState();
}

class _CarModeScreenState extends State<CarModeScreen> {
  SyncedLyrics? _lyrics;
  bool _lyricsLoading = true;
  String? _currentSongId;

  // Drag-to-dismiss state
  double _dragOffset = 0.0;
  bool _isDragging = false;
  static const double _dismissThreshold = 150.0;
  static const double _maxDragDistance = 400.0;

  double get _morphProgress =>
      (_dragOffset / _maxDragDistance).clamp(0.0, 1.0);
  double get _scale => 1.0 - (_morphProgress * 0.15);
  double get _borderRadius => _morphProgress * 32.0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLyricsForCurrentSong();
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _loadLyricsForCurrentSong() async {
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final song = player.currentSong;
    if (song == null) return;
    if (_currentSongId == song.id) return;
    _currentSongId = song.id;

    setState(() {
      _lyricsLoading = true;
      _lyrics = null;
    });

    try {
      final subsonicService =
          Provider.of<SubsonicService>(context, listen: false);
      final offlineService = OfflineService();
      final cached = await offlineService.getLocalLyrics(song.id);
      final syncedData = cached?['lyricsList'] as Map<String, dynamic>? ??
          await subsonicService.getLyricsBySongId(song.id);

      if (!mounted) return;

      if (syncedData != null) {
        final structuredLyrics = syncedData['structuredLyrics'];
        if (structuredLyrics is List && structuredLyrics.isNotEmpty) {
          final syncedEntry =
              structuredLyrics.cast<Map<String, dynamic>>().firstWhere(
                    (l) => l['synced'] == true,
                    orElse: () => <String, dynamic>{},
                  );
          final lines = syncedEntry['line'] as List?;
          if (lines != null && lines.isNotEmpty) {
            final parsedLines = lines
                .map<LyricLine>((line) {
                  final start = line['start'] as int? ?? 0;
                  return LyricLine(
                    timestamp: Duration(milliseconds: start),
                    text: line['value']?.toString() ?? '',
                  );
                })
                .where((l) => l.text.isNotEmpty)
                .toList();
            if (parsedLines.isNotEmpty) {
              setState(() {
                _lyrics = SyncedLyrics(lines: parsedLines);
                _lyricsLoading = false;
              });
              return;
            }
          }
        }
      }

      final plainData = cached?['lyrics'] as Map<String, dynamic>? ??
          await subsonicService.getLyrics(
            artist: song.artist,
            title: song.title,
            id: song.id,
          );

      if (!mounted) return;

      if (plainData != null) {
        final value = plainData['value']?.toString();
        if (value != null && value.isNotEmpty) {
          if (value.contains('[') && value.contains(':')) {
            setState(() {
              _lyrics = SyncedLyrics.fromLrc(value);
              _lyricsLoading = false;
            });
          } else {
            setState(() {
              _lyrics = SyncedLyrics.fromPlainText(value);
              _lyricsLoading = false;
            });
          }
          return;
        }
      }

      setState(() => _lyricsLoading = false);
    } catch (_) {
      if (mounted) setState(() => _lyricsLoading = false);
    }
  }

  String? _getCoverArtUrl(BuildContext context, Song? song) {
    if (song == null) return null;
    if (isLocalFilePath(song.coverArt)) return song.coverArt;
    final subsonic = Provider.of<SubsonicService>(context, listen: false);
    return subsonic.getCoverArtUrl(song.coverArt, size: 600);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          onVerticalDragStart: (_) {
            _isDragging = true;
          },
          onVerticalDragUpdate: (details) {
            if (!_isDragging) return;
            setState(() {
              _dragOffset = (_dragOffset + details.delta.dy).clamp(
                0.0,
                double.infinity,
              );
            });
          },
          onVerticalDragEnd: (details) {
            if (!_isDragging) return;
            _isDragging = false;
            final velocity = details.primaryVelocity ?? 0;
            if (_dragOffset > _dismissThreshold || velocity > 800) {
              setState(() {
                _dragOffset = MediaQuery.of(context).size.height;
              });
              Future.delayed(const Duration(milliseconds: 250), () {
                if (mounted) Navigator.pop(context);
              });
            } else {
              setState(() {
                _dragOffset = 0.0;
              });
            }
          },
          child: AnimatedOpacity(
            duration: _isDragging
                ? Duration.zero
                : const Duration(milliseconds: 250),
            opacity: (1.0 - _morphProgress).clamp(0.0, 1.0),
            child: AnimatedContainer(
            duration: _isDragging
                ? Duration.zero
                : const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            transform: Matrix4.identity()
              ..translate(0.0, _dragOffset),
            transformAlignment: Alignment.topCenter,
            child: Transform.scale(
              scale: _scale,
              alignment: Alignment.center,
              child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(_borderRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              bottom: false,
              child: Consumer<PlayerProvider>(
              builder: (context, player, _) {
                final song = player.currentSong;
                final coverUrl = _getCoverArtUrl(context, song);

                // Reload lyrics if song changed
                if (song != null && song.id != _currentSongId) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _loadLyricsForCurrentSong();
                  });
                }

                return Column(
                  children: [
                    // Top: close button
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                    // Song title + artist
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        song?.title ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        song?.artist ?? '',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Album cover (small)
                    if (coverUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: coverUrl,
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            width: 120,
                            height: 120,
                            color: Colors.grey[900],
                          ),
                          errorWidget: (_, __, ___) => Container(
                            width: 120,
                            height: 120,
                            color: Colors.grey[900],
                            child: const Icon(
                              CupertinoIcons.music_note,
                              color: Colors.white54,
                              size: 40,
                            ),
                          ),
                        ),
                      ),
                    // Lyrics area (expanded, shows 3 real lines)
                    Expanded(
                      child: _CarModeLyrics(
                        player: player,
                        lyrics: _lyrics,
                        isLoading: _lyricsLoading,
                      ),
                    ),
                    // Playback controls with progress ring
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).padding.bottom + 20,
                      ),
                      child: _CarModeControls(player: player),
                    ),
                  ],
                );
              },
            ),
            ),
          ),
          ),
          ),
          ),
        ),
      ),
    );
  }
}

class _CarModeLyrics extends StatelessWidget {
  final PlayerProvider player;
  final SyncedLyrics? lyrics;
  final bool isLoading;

  const _CarModeLyrics({
    required this.player,
    required this.lyrics,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white38),
      );
    }

    if (lyrics == null || lyrics!.isEmpty) {
      return const Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 20,
          ),
        ),
      );
    }

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final currentIndex = lyrics!.getCurrentLineIndex(position);
        final lines = lyrics!.lines;

        final prevLine = currentIndex > 0 ? lines[currentIndex - 1].text : '';
        final currentLine =
            currentIndex >= 0 ? lines[currentIndex].text : '';
        final nextLine = currentIndex >= 0 && currentIndex < lines.length - 1
            ? lines[currentIndex + 1].text
            : '';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Previous line
              Text(
                prevLine,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 27,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              // Current line (highlighted)
              Text(
                currentLine,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              // Next line
              Text(
                nextLine,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 27,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CarModeControls extends StatelessWidget {
  final PlayerProvider player;

  const _CarModeControls({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = player.duration;
        final progress = duration.inMilliseconds > 0
            ? (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0)
            : 0.0;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Previous
            IconButton(
              onPressed: player.skipPrevious,
              iconSize: 40,
              icon: const Icon(
                CupertinoIcons.backward_fill,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 32),
            // Play/Pause with progress ring
            GestureDetector(
              onTap: player.togglePlayPause,
              child: SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background ring
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                        value: 1.0,
                        strokeWidth: 3,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    // Progress ring
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 3,
                        color: Colors.white,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    // Play/Pause icon
                    Icon(
                      player.isPlaying
                          ? CupertinoIcons.pause_fill
                          : CupertinoIcons.play_fill,
                      color: Colors.white,
                      size: 32,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 32),
            // Next
            IconButton(
              onPressed: player.hasNext ? player.skipNext : null,
              iconSize: 40,
              icon: Icon(
                CupertinoIcons.forward_fill,
                color: player.hasNext
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ],
        );
      },
    );
  }
}
