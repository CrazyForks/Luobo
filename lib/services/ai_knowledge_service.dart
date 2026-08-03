import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import 'ai_playlist_service.dart';
import 'song_knowledge_cache.dart';

/// Global singleton that owns the AI knowledge-base generation task state.
///
/// State is split into two layers so it survives UI navigation and process
/// restarts:
/// - Live state (isGenerating / processed / total): kept in memory, dies with
///   the process — which is correct because the task itself dies with it.
/// - Persistent state (cachedCount / totalSongs / lastUpdate): read from disk
///   (song_knowledge.json + progress.json), so a cold start always shows the
///   real indexed count and lets the user resume via incremental update.
class AiKnowledgeService extends ChangeNotifier {
  AiKnowledgeService._();

  static AiKnowledgeService? _instance;
  static AiKnowledgeService get instance =>
      _instance ??= AiKnowledgeService._();

  static const String _progressFileName = 'knowledge_progress.json';

  final AiPlaylistService _playlistService = AiPlaylistService();
  final SongKnowledgeCache _cache = SongKnowledgeCache();

  // ── Live state (memory only) ────────────────────────────────────────
  bool _isGenerating = false;
  int _processed = 0;
  int _total = 0;

  // ── Persistent state (from disk) ────────────────────────────────────
  int _cachedCount = 0;
  int _totalSongs = 0;
  DateTime? _lastUpdate;

  bool get isGenerating => _isGenerating;
  int get processed => _processed;
  int get total => _total;
  int get cachedCount => _cachedCount;
  int get totalSongs => _totalSongs;
  DateTime? get lastUpdate => _lastUpdate;

  double get progress => _total == 0 ? 0 : _processed / _total;

  /// Loads persistent state from disk. Safe to call multiple times
  /// (idempotent); call once on first use, typically from the UI initState.
  Future<void> initialize({int totalSongs = 0}) async {
    // Skip reloading while a generation is running: the shared cache is
    // being mutated by the task and a disk snapshot would clobber it.
    if (_isGenerating) {
      if (totalSongs > 0) _totalSongs = totalSongs;
      notifyListeners();
      return;
    }
    await _cache.initialize();
    if (totalSongs > 0) _totalSongs = totalSongs;
    _cachedCount = _cache.getAllTags().length;
    _lastUpdate = _cache.getLastUpdateTime();
    await _loadProgress();
    notifyListeners();
  }

  /// Starts (or resumes) knowledge-base generation for the given library.
  /// Idempotent: no-op if a generation is already running.
  Future<void> start(List<Song> allSongs) async {
    if (_isGenerating) return;
    // Share the cache instance with the generation task so it computes
    // incremental work from the same loaded state (no full re-run / data
    // overwrite) and the indexed count stays live during generation.
    _playlistService.attachCache(_cache);
    _totalSongs = allSongs.length;

    setGenerating(true, processed: 0, total: 0);
    try {
      final processed = await _playlistService.generateKnowledge(
        allSongs: allSongs,
        onProgress: (done, total) {
          _processed = done;
          _total = total;
          _syncFromDisk();
          notifyListeners();
        },
      );
      _processed = processed;
      _syncFromDisk();
    } catch (e) {
      // Never let an unexpected generation error escape to the UI layer.
      debugPrint('[AiKnowledgeService] Generation failed: $e');
      _playlistService.lastFailureReason = '生成异常：$e';
    } finally {
      _isGenerating = false;
      await _saveProgress();
      notifyListeners();
    }
  }

  /// Cancels an ongoing generation.
  void cancel() {
    _playlistService.cancel();
    // A user-initiated cancel is not a failure.
    _playlistService.lastFailureReason = null;
    _isGenerating = false;
    notifyListeners();
  }

  /// Human-readable reason for the most recent aborted generation, or null
  /// if the last run completed/succeeded.
  String? get lastFailureReason => _playlistService.lastFailureReason;

  /// Returns the knowledge cache for export/import operations.
  SongKnowledgeCache get cache => _cache;

  void setGenerating(bool value, {int processed = 0, int total = 0}) {
    _isGenerating = value;
    _processed = processed;
    _total = total;
    notifyListeners();
  }

  // ── Private helpers ────────────────────────────────────────────────

  /// Reads the indexed count and last-update from the shared cache instance.
  /// The cache is attached to the playlist service, so it reflects the
  /// latest batches written by the running generation task.
  void _syncFromDisk() {
    final tags = _cache.getAllTags();
    _cachedCount = tags.length;
    _lastUpdate = _cache.getLastUpdateTime();
  }

  Future<void> _loadProgress() async {
    try {
      final file = await _getProgressFile();
      if (!await file.exists()) return;
      final decoded =
          json.decode(await file.readAsString()) as Map<String, dynamic>;
      _processed = decoded['processed'] as int? ?? 0;
      _total = decoded['total'] as int? ?? 0;
      final lastUpdate = decoded['lastUpdate'] as String?;
      if (lastUpdate != null) {
        _lastUpdate = DateTime.tryParse(lastUpdate) ?? _lastUpdate;
      }
    } catch (e) {
      debugPrint('[AiKnowledgeService] Failed to load progress: $e');
    }
  }

  Future<void> _saveProgress() async {
    try {
      final file = await _getProgressFile();
      await file.writeAsString(json.encode({
        'processed': _processed,
        'total': _total,
        'cachedCount': _cachedCount,
        'lastUpdate': _lastUpdate?.toIso8601String(),
        'isGenerating': _isGenerating,
      }));
    } catch (e) {
      debugPrint('[AiKnowledgeService] Failed to save progress: $e');
    }
  }

  Future<File> _getProgressFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_progressFileName');
  }
}
