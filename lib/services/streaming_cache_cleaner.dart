import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'diagnostics/diagnostics.dart';

/// Periodically prunes the streaming audio cache (`musly_stream_*.tmp` files
/// in the temporary directory) so the total size stays under [maxBytes].
/// Oldest files (by last-modified time) are deleted first.
class StreamingCacheCleaner {
  static const int _defaultMaxBytes = 2 * 1024 * 1024 * 1024; // 2 GB
  static const String _filePrefix = 'musly_stream_';

  final int _maxBytes;

  StreamingCacheCleaner({int maxBytes = _defaultMaxBytes})
      : _maxBytes = maxBytes;

  /// Scan the temp directory and remove oldest cached streams until the
  /// total size is ≤ [_maxBytes].  Call this after each song finishes so
  /// the cache never grows unbounded.
  Future<void> prune() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final entries = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains(_filePrefix))
          .toList();

      if (entries.isEmpty) return;

      // Sort oldest-first
      entries
          .sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

      var totalSize = entries.fold<int>(0, (s, f) => s + (f.lengthSync()));
      var deletedBytes = 0;
      var deletedCount = 0;
      for (final file in entries) {
        if (totalSize <= _maxBytes) break;
        final size = file.lengthSync();
        file.deleteSync();
        totalSize -= size;
        deletedBytes += size;
        deletedCount++;
      }
      if (deletedCount > 0) {
        DiagnosticsService.instance.record(
          EventType.cachePrune,
          LogLevel.info,
          {
            'deletedCount': deletedCount,
            'deletedBytes': deletedBytes,
            'remainingBytes': totalSize,
          },
        );
      }
    } catch (e) {
      debugPrint('[StreamingCache] Prune error: $e');
      Log.e('StreamingCache', 'prune error', error: e);
    }
  }
}
