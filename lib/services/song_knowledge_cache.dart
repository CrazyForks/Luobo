import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';

/// Local cache for AI-generated song knowledge tags.
/// Stores per-song tags in a JSON file under the app documents directory.
class SongKnowledgeCache {
  static const String _fileName = 'song_knowledge.json';
  static const String _metaFileName = 'song_knowledge_meta.json';

  Map<String, String>? _cache;
  DateTime? _lastUpdateTime;

  /// Loads the cache from disk. Must be called before other methods.
  Future<void> initialize() async {
    await _loadCache();
    await _loadMeta();
  }

  /// Whether the cache has been loaded from disk at least once.
  bool get isInitialized => _cache != null;

  /// Returns song IDs from [allSongs] that are not yet cached.
  List<String> getUncachedSongIds(List<Song> allSongs) {
    final cache = _cache ?? {};
    return allSongs
        .where((s) => !cache.containsKey(s.id))
        .map((s) => s.id)
        .toList();
  }

  /// Returns song IDs in cache that no longer exist in [allSongs].
  List<String> getRemovedSongIds(List<Song> allSongs) {
    final cache = _cache ?? {};
    final currentIds = allSongs.map((s) => s.id).toSet();
    return cache.keys.where((id) => !currentIds.contains(id)).toList();
  }

  /// Saves tags for a single song.
  Future<void> saveTags(String songId, String tags) async {
    _cache ??= {};
    _cache![songId] = tags;
  }

  /// Saves tags for multiple songs at once.
  Future<void> saveBatchTags(Map<String, String> batch) async {
    _cache ??= {};
    _cache!.addAll(batch);
  }

  /// Persists the current cache to disk.
  Future<void> flush() async {
    await _saveCache();
    _lastUpdateTime = DateTime.now();
    await _saveMeta();
  }

  /// Removes cached entries for the given song IDs.
  Future<void> removeByIds(List<String> songIds) async {
    if (_cache == null) return;
    for (final id in songIds) {
      _cache!.remove(id);
    }
    await _saveCache();
  }

  /// Returns all cached tags as a map of songId → tags string.
  Map<String, String> getAllTags() {
    return Map.unmodifiable(_cache ?? {});
  }

  /// Returns tags for a specific song, or null if not cached.
  String? getTagsForSong(String songId) {
    return _cache?[songId];
  }

  /// Returns the timestamp of the last update, or null if never updated.
  DateTime? getLastUpdateTime() => _lastUpdateTime;

  /// Returns cache statistics.
  Map<String, dynamic> getCacheStats(int totalSongs) {
    final cached = _cache?.length ?? 0;
    return {
      'cached': cached,
      'total': totalSongs,
      'lastUpdate': _lastUpdateTime?.toIso8601String(),
    };
  }

  /// Clears the entire cache.
  Future<void> clear() async {
    _cache = {};
    _lastUpdateTime = null;
    final file = await _getCacheFile();
    if (await file.exists()) await file.delete();
    final metaFile = await _getMetaFile();
    if (await metaFile.exists()) await metaFile.delete();
  }

  /// Exports the knowledge base as a shareable JSON string.
  /// Includes a small metadata header so recipients (sharing the same NAS
  /// library) can identify what this file is and when it was generated.
  String exportAsJson() {
    final payload = {
      'type': 'luobo_song_knowledge_base',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'songCount': (_cache ?? {}).length,
      'tags': _cache ?? {},
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Imports a previously exported knowledge base JSON string.
  /// Existing entries are merged with (and take precedence over) the
  /// imported ones unless [overwrite] is true.
  /// Returns the number of new/updated entries imported.
  Future<int> importFromJson(String jsonStr, {bool overwrite = false}) async {
    final decoded = json.decode(jsonStr) as Map<String, dynamic>;
    final rawTags = decoded['tags'];
    if (rawTags is! Map) {
      throw const FormatException('无效的知识库文件：缺少 tags 字段');
    }
    final importedTags = rawTags.map(
      (k, v) => MapEntry(k.toString(), v.toString()),
    );

    _cache ??= {};
    int count = 0;
    for (final entry in importedTags.entries) {
      if (overwrite || !_cache!.containsKey(entry.key)) {
        _cache![entry.key] = entry.value;
        count++;
      }
    }
    await flush();
    return count;
  }

  // ── Private ──────────────────────────────────────────────────────────

  Future<File> _getCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<File> _getMetaFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_metaFileName');
  }

  Future<void> _loadCache() async {
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = json.decode(content) as Map<String, dynamic>;
        _cache = decoded.map((k, v) => MapEntry(k, v.toString()));
      } else {
        _cache = {};
      }
    } catch (e) {
      debugPrint('[SongKnowledgeCache] Failed to load cache: $e');
      // Back up a corrupted cache file before discarding it, so the
      // original data can still be inspected/recovered if needed.
      try {
        final file = await _getCacheFile();
        if (await file.exists()) {
          await file.copy('${file.path}.bak');
        }
      } catch (_) {}
      _cache = {};
    }
  }

  Future<void> _saveCache() async {
    try {
      final file = await _getCacheFile();
      // Write to a temp file first, then rename atomically, so a process
      // kill mid-write can never leave a truncated/corrupt cache file.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json.encode(_cache ?? {}));
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('[SongKnowledgeCache] Failed to save cache: $e');
    }
  }

  Future<void> _loadMeta() async {
    try {
      final file = await _getMetaFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = json.decode(content) as Map<String, dynamic>;
        final ts = decoded['lastUpdate'] as String?;
        if (ts != null) _lastUpdateTime = DateTime.tryParse(ts);
      }
    } catch (e) {
      debugPrint('[SongKnowledgeCache] Failed to load meta: $e');
    }
  }

  Future<void> _saveMeta() async {
    try {
      final file = await _getMetaFile();
      await file.writeAsString(json.encode({
        'lastUpdate': _lastUpdateTime?.toIso8601String(),
      }));
    } catch (e) {
      debugPrint('[SongKnowledgeCache] Failed to save meta: $e');
    }
  }
}
