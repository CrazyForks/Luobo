import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

/// Service that searches NetEase Cloud Music for lyrics as a fallback source.
/// Particularly useful for Chinese songs where LRCLIB coverage is limited.
class NeteaseLyricsService {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://music.163.com/api',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Referer': 'https://music.163.com/',
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
      },
      contentType: 'application/x-www-form-urlencoded',
    ),
  );

  /// Searches for a song on NetEase and returns lyrics in a format compatible
  /// with the Subsonic structured-lyrics response.
  ///
  /// Returns `null` when no match is found.
  Future<Map<String, dynamic>?> searchLyrics({
    required String artist,
    required String title,
    int? durationSeconds,
  }) async {
    try {
      // Step 1: Search for the song
      final songId = await _searchSong(artist: artist, title: title);
      if (songId == null) return null;

      // Step 2: Fetch lyrics by song ID
      return await _fetchLyrics(songId);
    } catch (e) {
      debugPrint('[NetEase] Unexpected error: $e');
      return null;
    }
  }

  /// Searches for a song and returns the best matching song ID.
  Future<int?> _searchSong({
    required String artist,
    required String title,
  }) async {
    try {
      final response = await _dio.post(
        '/search/get',
        data: 's=${Uri.encodeComponent('$artist $title')}&type=1&limit=5&offset=0',
      );

      if (response.statusCode != 200 || response.data == null) return null;

      final data = response.data is String
          ? json.decode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      final result = data['result'] as Map<String, dynamic>?;
      if (result == null) return null;

      final songs = result['songs'] as List?;
      if (songs == null || songs.isEmpty) return null;

      // Try to find a match by artist name
      final normalizedArtist = artist.toLowerCase().trim();
      for (final song in songs) {
        final artists = song['artists'] as List?;
        if (artists != null) {
          for (final ar in artists) {
            final name = (ar['name'] as String?)?.toLowerCase().trim() ?? '';
            if (name == normalizedArtist || name.contains(normalizedArtist)) {
              return song['id'] as int?;
            }
          }
        }
      }

      // If no exact artist match, return the first result
      return songs.first['id'] as int?;
    } on DioException catch (e) {
      debugPrint('[NetEase] Search error: ${e.message}');
      return null;
    }
  }

  /// Fetches lyrics for a given song ID.
  Future<Map<String, dynamic>?> _fetchLyrics(int songId) async {
    try {
      final response = await _dio.get(
        '/song/lyric',
        queryParameters: {
          'id': songId,
          'lv': 1,
          'tv': 1,
        },
      );

      if (response.statusCode != 200 || response.data == null) return null;

      final data = response.data is String
          ? json.decode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      // Try synced lyrics first
      final lrc = data['lrc'] as Map<String, dynamic>?;
      final lrcText = lrc?['lyric'] as String?;

      if (lrcText != null && lrcText.isNotEmpty && lrcText.contains('[')) {
        // Filter out metadata lines like [ti:xxx] [ar:xxx]
        final cleaned = _cleanLrcMetadata(lrcText);
        if (cleaned.isNotEmpty) {
          return _buildStructuredLyrics(cleaned);
        }
      }

      // Fallback: return as plain text if no synced lyrics
      if (lrcText != null && lrcText.trim().isNotEmpty) {
        return {'value': lrcText.trim()};
      }

      return null;
    } on DioException catch (e) {
      debugPrint('[NetEase] Lyrics fetch error: ${e.message}');
      return null;
    }
  }

  /// Removes LRC metadata tags (e.g. [ti:xxx], [ar:xxx], [al:xxx]).
  String _cleanLrcMetadata(String lrcText) {
    final lines = LineSplitter.split(lrcText).where((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return false;
      // Skip metadata tags
      if (RegExp(r'^\[(ti|ar|al|by|offset|re|ve):').hasMatch(trimmed)) {
        return false;
      }
      return true;
    });
    return lines.join('\n');
  }

  /// Converts an LRC string into the Subsonic structured-lyrics format.
  Map<String, dynamic> _buildStructuredLyrics(String lrcText) {
    final lines = <Map<String, dynamic>>[];
    for (final raw in LineSplitter.split(lrcText)) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      // Parse [mm:ss.xx] or [mm:ss.xxx] tags
      final match =
          RegExp(r'\[(\d+):(\d{2})\.(\d{2,3})\](.*)').firstMatch(line);
      if (match == null) continue;

      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final fracStr = match.group(3)!;
      final text = match.group(4)!.trim();
      if (text.isEmpty) continue;

      // Normalise fractional seconds to milliseconds
      final fracMs =
          fracStr.length == 2 ? int.parse(fracStr) * 10 : int.parse(fracStr);

      final startMs = (minutes * 60 + seconds) * 1000 + fracMs.clamp(0, 999);

      lines.add({
        'start': startMs,
        'value': text,
      });
    }

    if (lines.isEmpty) {
      return {'value': lrcText};
    }

    return {
      'structuredLyrics': [
        {
          'synced': true,
          'line': lines,
        },
      ],
    };
  }
}
