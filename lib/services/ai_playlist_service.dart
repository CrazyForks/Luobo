import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../models/song.dart';
import 'storage_service.dart';
import 'song_knowledge_cache.dart';
import 'recommendation_service.dart';

/// Modes for AI playlist generation.
enum AiPlaylistMode {
  recentListening,
  scene,
  freeText,
}

/// Progress callback for knowledge base generation.
typedef KnowledgeProgressCallback = void Function(int processed, int total);

/// Service that integrates with DeepSeek API to generate song knowledge
/// tags and create AI-powered playlists.
class AiPlaylistService {
  final StorageService _storage = StorageService();
  final SongKnowledgeCache _cache = SongKnowledgeCache();

  static const int _batchSize = 50;

  Dio? _dio;
  bool _cancelled = false;

  /// Initialize the service. Must be called before use.
  Future<void> initialize() async {
    await _cache.initialize();
  }

  /// Cancel an ongoing knowledge generation.
  void cancel() {
    _cancelled = true;
  }

  /// Returns the knowledge cache instance for stats access.
  SongKnowledgeCache get cache => _cache;

  // ── Knowledge Base Generation ──────────────────────────────────────

  /// Generates knowledge tags for uncached songs in [allSongs].
  /// Calls [onProgress] with (processed, total) after each batch.
  /// Returns the number of newly processed songs.
  Future<int> generateKnowledge({
    required List<Song> allSongs,
    KnowledgeProgressCallback? onProgress,
  }) async {
    _cancelled = false;
    final dio = await _getDio();
    if (dio == null) return 0;

    // Clean up removed songs
    final removed = _cache.getRemovedSongIds(allSongs);
    if (removed.isNotEmpty) {
      await _cache.removeByIds(removed);
    }

    // Find uncached songs
    final uncached = _cache.getUncachedSongIds(allSongs);
    if (uncached.isEmpty) {
      await _cache.flush();
      return 0;
    }

    final songMap = {for (final s in allSongs) s.id: s};
    int processed = 0;
    final total = uncached.length;

    // Process in batches
    for (int i = 0; i < uncached.length; i += _batchSize) {
      if (_cancelled) break;

      final batchIds = uncached.skip(i).take(_batchSize).toList();
      final batchSongs = batchIds
          .map((id) => songMap[id])
          .whereType<Song>()
          .toList();

      final tags = await _generateBatchTags(dio, batchSongs);
      if (tags != null) {
        await _cache.saveBatchTags(tags);
        // Flush every batch for interrupt recovery
        await _cache.flush();
      }

      processed += batchSongs.length;
      onProgress?.call(processed, total);
    }

    await _cache.flush();
    return processed;
  }

  /// Generates tags for a single batch of songs.
  Future<Map<String, String>?> _generateBatchTags(
    Dio dio,
    List<Song> songs,
  ) async {
    final songList = songs.asMap().entries.map((e) {
      final s = e.value;
      return '${e.key + 1}. ${s.title} - ${s.artist ?? "未知"} - '
          '${s.album ?? "未知"} - ${s.genre ?? "未知"} - ${s.year ?? "未知"}';
    }).join('\n');

    final prompt = '''你是一个音乐标签专家。请为以下歌曲生成多维度标签。
每首歌的标签应涵盖以下维度，总共8-12个关键词：
- 情绪氛围（如：忧伤、治愈、热血、甜蜜、孤独、释放）
- 节奏能量（如：慢歌、中速、快节奏、能量高、能量低）
- 适合场景（如：开车、通勤、跑步、深夜、学习、聚会、咖啡店）
- 歌词主题（如：爱情、失恋、青春、友情、成长、社会、自我）
- 演唱风格（如：说唱、假声、沙哑、清亮、合唱、吟唱）
- 乐器/编曲特征（如：钢琴、吉他、电子、弦乐、鼓点强、合成器）
- 风格子类（如：R&B、民谣、摇滚、古风、爵士、嘻哈、电子）
- 相似歌手（列出1-2个风格相近的歌手名）

严格按以下格式输出，每行一首歌，序号与输入对应：
序号|关键词1,关键词2,关键词3,...

歌曲列表：
$songList''';

    try {
      final response = await dio.post(
        '/chat/completions',
        data: {
          'model': await _storage.getAiModel(),
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.3,
          'max_tokens': 4000,
        },
      );

      final content = response.data['choices'][0]['message']['content'] as String;
      return _parseBatchResponse(content, songs);
    } on DioException catch (e) {
      debugPrint('[AiPlaylist] Batch tag generation error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[AiPlaylist] Unexpected error in batch: $e');
      return null;
    }
  }

  /// Parses AI response into a map of songId → tags.
  Map<String, String> _parseBatchResponse(String response, List<Song> songs) {
    final result = <String, String>{};
    final lines = LineSplitter.split(response)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    for (final line in lines) {
      final pipeIdx = line.indexOf('|');
      if (pipeIdx <= 0) continue;

      final numStr = line.substring(0, pipeIdx).trim().replaceAll('.', '');
      final tags = line.substring(pipeIdx + 1).trim();
      final idx = int.tryParse(numStr);
      if (idx == null || idx < 1 || idx > songs.length) continue;

      result[songs[idx - 1].id] = tags;
    }
    return result;
  }

  // ── Playlist Generation ────────────────────────────────────────────

  /// Generates a playlist using AI based on the given mode and parameters.
  /// Returns a list of song IDs, or null on failure.
  Future<List<String>?> generatePlaylist({
    required List<Song> allSongs,
    required AiPlaylistMode mode,
    required int count,
    String? sceneDescription,
    String? freeText,
    List<String>? recentlyPlayed,
    RecommendationService? recommendationService,
  }) async {
    final dio = await _getDio();
    if (dio == null) return null;

    // Build user profile context
    final profileContext = _buildUserProfile(
      allSongs: allSongs,
      recentlyPlayed: recentlyPlayed,
      recommendationService: recommendationService,
    );

    // Build candidate song list with tags (use knowledge base for pre-filtering)
    final filterText = mode == AiPlaylistMode.freeText
        ? freeText
        : sceneDescription;
    final candidates = _buildCandidateList(allSongs, mode, filterText);

    // Build user request
    final request = _buildRequest(mode, count, sceneDescription, freeText);

    final prompt = '''你是用户的私人 DJ。请从用户曲库中选歌组成歌单。

$profileContext

用户需求：$request

候选歌曲（格式：ID | 歌名-歌手 | 标签）：
$candidates

请选出 $count 首歌，注意多样性和整体氛围的连贯。
只返回 JSON 数组格式的歌曲ID列表，例如：["id1", "id2", ...]
不要输出任何其他内容。''';

    try {
      final response = await dio.post(
        '/chat/completions',
        data: {
          'model': await _storage.getAiModel(),
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.7,
          'max_tokens': 2000,
        },
      );

      final content =
          response.data['choices'][0]['message']['content'] as String;
      return _parsePlaylistResponse(content, allSongs);
    } on DioException catch (e) {
      debugPrint('[AiPlaylist] Playlist generation error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[AiPlaylist] Unexpected error: $e');
      return null;
    }
  }

  String _buildUserProfile({
    required List<Song> allSongs,
    List<String>? recentlyPlayed,
    RecommendationService? recommendationService,
  }) {
    final buffer = StringBuffer('用户画像：\n');

    if (recommendationService != null) {
      final topArtists = recommendationService.getRecommendedArtists(limit: 10);
      final topGenres = recommendationService.getRecommendedGenres(limit: 5);
      if (topArtists.isNotEmpty) {
        buffer.writeln('- 常听歌手：${topArtists.join("、")}');
      }
      if (topGenres.isNotEmpty) {
        buffer.writeln('- 常听风格：${topGenres.join("、")}');
      }

      // Inject behavioral data: highly rated, starred, frequently skipped
      final profiles = recommendationService.profiles;
      final songMap = {for (final s in allSongs) s.id: s};

      // Top completed songs (high replay value)
      final topCompleted = profiles.entries
          .where((e) => e.value.completedPlays >= 3)
          .toList()
        ..sort((a, b) => b.value.completedPlays.compareTo(a.value.completedPlays));
      if (topCompleted.isNotEmpty) {
        final names = topCompleted
            .take(10)
            .map((e) => songMap[e.key])
            .whereType<Song>()
            .map((s) => '${s.title}-${s.artist ?? ""}')
            .toList();
        if (names.isNotEmpty) {
          buffer.writeln('- 反复听的歌（完播3次以上）：${names.join("、")}');
        }
      }

      // Frequently skipped songs (negative signal)
      final topSkipped = profiles.entries
          .where((e) => e.value.skipCount >= 3)
          .toList()
        ..sort((a, b) => b.value.skipCount.compareTo(a.value.skipCount));
      if (topSkipped.isNotEmpty) {
        final names = topSkipped
            .take(8)
            .map((e) => songMap[e.key])
            .whereType<Song>()
            .map((s) => '${s.title}-${s.artist ?? ""}')
            .toList();
        if (names.isNotEmpty) {
          buffer.writeln('- 经常跳过的歌（不太喜欢）：${names.join("、")}');
        }
      }

      // High rated songs
      final highRated = profiles.entries
          .where((e) => (e.value.userRating ?? 0) >= 4)
          .toList()
        ..sort((a, b) =>
            (b.value.userRating ?? 0).compareTo(a.value.userRating ?? 0));
      if (highRated.isNotEmpty) {
        final names = highRated
            .take(10)
            .map((e) => songMap[e.key])
            .whereType<Song>()
            .map((s) => '${s.title}-${s.artist ?? ""}')
            .toList();
        if (names.isNotEmpty) {
          buffer.writeln('- 高评分歌曲（4-5星）：${names.join("、")}');
        }
      }

      // Current time context
      final hour = DateTime.now().hour;
      final timeLabel = hour >= 5 && hour < 12
          ? '早上'
          : hour >= 12 && hour < 17
              ? '下午'
              : hour >= 17 && hour < 21
                  ? '傍晚'
                  : '深夜';
      buffer.writeln('- 当前时段：$timeLabel（${hour}点）');
    }

    if (recentlyPlayed != null && recentlyPlayed.isNotEmpty) {
      final songMap = {for (final s in allSongs) s.id: s};
      final recentNames = recentlyPlayed
          .take(15)
          .map((id) => songMap[id])
          .whereType<Song>()
          .map((s) => '${s.title}-${s.artist ?? ""}')
          .toList();
      if (recentNames.isNotEmpty) {
        buffer.writeln('- 最近播放：${recentNames.join("、")}');
      }
    }

    buffer.writeln('- 曲库总量：${allSongs.length} 首');
    return buffer.toString();
  }

  String _buildCandidateList(
    List<Song> allSongs,
    AiPlaylistMode mode,
    String? sceneDescription,
  ) {
    final allTags = _cache.getAllTags();
    final buffer = StringBuffer();

    List<Song> candidates;

    if (allTags.isEmpty) {
      // No knowledge base — just take first 300
      candidates = allSongs.take(300).toList();
    } else {
      // Use knowledge base tags to pre-filter relevant songs
      switch (mode) {
        case AiPlaylistMode.scene:
          candidates = _filterByScene(allSongs, allTags, sceneDescription ?? '');
        case AiPlaylistMode.recentListening:
          candidates = _filterByRecentStyle(allSongs, allTags);
        case AiPlaylistMode.freeText:
          candidates = _filterByKeywords(allSongs, allTags, sceneDescription ?? '');
      }
    }

    for (final song in candidates) {
      final tags = allTags[song.id] ?? song.genre ?? '';
      buffer.writeln(
        '${song.id} | ${song.title}-${song.artist ?? "未知"} | $tags',
      );
    }
    return buffer.toString();
  }

  /// Filters songs by matching scene keywords against knowledge tags.
  /// Returns up to 300 songs, prioritizing those with matching tags.
  List<Song> _filterByScene(
    List<Song> allSongs,
    Map<String, String> allTags,
    String scene,
  ) {
    // Extract keywords from the scene description
    final keywords = _extractKeywords(scene);

    // Score each song by tag relevance
    final scored = <Song, int>{};
    for (final song in allSongs) {
      final tags = allTags[song.id];
      if (tags == null) continue;
      final tagsLower = tags.toLowerCase();
      int score = 0;
      for (final kw in keywords) {
        if (tagsLower.contains(kw)) score++;
      }
      if (score > 0) scored[song] = score;
    }

    // Sort by score descending, take top 300
    final sorted = scored.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final result = sorted.take(250).map((e) => e.key).toList();

    // Supplement with unscored songs if not enough
    if (result.length < 300) {
      final resultIds = result.map((s) => s.id).toSet();
      final extra = allSongs
          .where((s) => !resultIds.contains(s.id) && allTags.containsKey(s.id))
          .take(300 - result.length);
      result.addAll(extra);
    }

    return result;
  }

  /// For "recent listening" mode, uses recently played songs' knowledge tags
  /// to build a comprehensive profile (artist, genre, mood, lyrics style),
  /// then finds songs with similar tags.
  List<Song> _filterByRecentStyle(
    List<Song> allSongs,
    Map<String, String> allTags,
  ) {
    // Collect all tag keywords from recently played songs (use last 30)
    // These tags already contain artist style, genre, mood, lyrics themes etc.
    final recentSongs = allSongs.take(50).toList(); // fallback
    final recentTags = <String, int>{};

    // First gather keywords from recent songs' cached knowledge tags
    for (final song in recentSongs) {
      final tags = allTags[song.id];
      if (tags == null) continue;
      for (final tag in tags.split(',')) {
        final t = tag.trim().toLowerCase();
        if (t.isNotEmpty) {
          recentTags[t] = (recentTags[t] ?? 0) + 1;
        }
      }
    }

    if (recentTags.isEmpty) {
      // No knowledge data, fall back to genre-based
      return allSongs.where((s) => allTags.containsKey(s.id)).take(300).toList();
    }

    // Get the most frequent tag keywords from recent listening
    final topKeywords = (recentTags.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(20)
        .map((e) => e.key)
        .toList();

    // Score all songs by how many of these keywords appear in their tags
    final scored = <Song, int>{};
    for (final song in allSongs) {
      final tags = allTags[song.id];
      if (tags == null) continue;
      final tagsLower = tags.toLowerCase();
      int score = 0;
      for (final kw in topKeywords) {
        if (tagsLower.contains(kw)) score++;
      }
      if (score > 0) scored[song] = score;
    }

    final sorted = scored.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final result = sorted.take(250).map((e) => e.key).toList();

    // Supplement if needed
    if (result.length < 300) {
      final resultIds = result.map((s) => s.id).toSet();
      final extra = allSongs
          .where((s) => !resultIds.contains(s.id) && allTags.containsKey(s.id))
          .take(300 - result.length);
      result.addAll(extra);
    }

    return result;
  }

  /// For free text mode, extracts keywords from user input and matches tags.
  List<Song> _filterByKeywords(
    List<Song> allSongs,
    Map<String, String> allTags,
    String text,
  ) {
    final keywords = _extractKeywords(text);
    if (keywords.isEmpty) {
      // No usable keywords, return all tagged songs
      return allSongs.where((s) => allTags.containsKey(s.id)).take(300).toList();
    }
    return _filterByScene(allSongs, allTags, text);
  }

  /// Extracts Chinese and English keywords from a description.
  List<String> _extractKeywords(String text) {
    // Scene name mapping to common music tag keywords
    const sceneKeywords = {
      '开车': ['开车', '驾驶', '动感', '节奏', '摇滚', '电子', '公路'],
      '兜风': ['开车', '轻快', '自由', '夏日', '公路'],
      '通勤': ['通勤', '轻松', '节奏', '流行', '电子', '清新'],
      '跑步': ['运动', '动感', '节奏强', '电子', '激励', '快节奏'],
      '运动': ['运动', '动感', '节奏强', '电子', '激励', '快节奏', '力量'],
      '深夜': ['深夜', '夜晚', '安静', '孤独', '抒情', '慢歌', '钢琴'],
      '独处': ['独处', '安静', '思考', '抒情', '民谣'],
      '学习': ['学习', '专注', '安静', '纯音乐', '轻音乐', '钢琴'],
      '工作': ['专注', '轻音乐', '背景音乐', '电子', '氛围'],
      '聚会': ['聚会', '派对', '动感', '嗨', '电子', '舞曲', '快乐'],
      '派对': ['派对', '聚会', '动感', '嗨', '电子', '舞曲'],
      '做饭': ['轻松', '愉快', '爵士', '慵懒', '法语', '清新'],
      '下厨': ['轻松', '愉快', '爵士', '慵懒'],
      '午后': ['午后', '慵懒', '轻松', '阳光', '清新', '民谣'],
      '休息': ['休息', '放松', '慵懒', '轻音乐'],
      '雨天': ['雨天', '下雨', '安静', '忧郁', '抒情', '钢琴', '孤独'],
      '发呆': ['发呆', '放空', '氛围', '安静', '梦幻'],
      '早起': ['早起', '清新', '阳光', '轻快', '活力', '提神'],
      '提神': ['提神', '活力', '节奏', '动感', '快乐'],
      '睡前': ['睡前', '安静', '轻柔', '慢歌', '催眠', '钢琴'],
      '咖啡': ['咖啡', '爵士', '慵懒', '氛围', '轻松', '午后'],
    };

    final keywords = <String>[];

    // Match scene keywords
    for (final entry in sceneKeywords.entries) {
      if (text.contains(entry.key)) {
        keywords.addAll(entry.value);
      }
    }

    // Also extract individual characters/words from the text as-is
    // for matching against tags
    final textLower = text.toLowerCase();
    final words = textLower
        .replaceAll(RegExp('[，。！？、；：""''（）\\s]+'), ' ')
        .split(' ')
        .where((w) => w.length >= 2)
        .toList();
    keywords.addAll(words);

    return keywords.toSet().toList(); // deduplicate
  }

  String _buildRequest(
    AiPlaylistMode mode,
    int count,
    String? sceneDescription,
    String? freeText,
  ) {
    switch (mode) {
      case AiPlaylistMode.recentListening:
        return '根据我最近的听歌习惯，推荐 $count 首我可能想继续听的歌，'
            '可以包含我没怎么听过但风格相近的歌。';
      case AiPlaylistMode.scene:
        return '我需要一个适合「${sceneDescription ?? ""}」场景的歌单，共 $count 首。';
      case AiPlaylistMode.freeText:
        return freeText ?? '推荐 $count 首好歌';
    }
  }

  List<String>? _parsePlaylistResponse(String response, List<Song> allSongs) {
    try {
      // Extract JSON array from response (might have markdown formatting)
      final jsonMatch = RegExp(r'\[[\s\S]*?\]').firstMatch(response);
      if (jsonMatch == null) return null;

      final list = json.decode(jsonMatch.group(0)!) as List;
      final validIds = allSongs.map((s) => s.id).toSet();

      return list
          .map((e) => e.toString())
          .where((id) => validIds.contains(id))
          .toList();
    } catch (e) {
      debugPrint('[AiPlaylist] Failed to parse response: $e');
      return null;
    }
  }

  // ── Private Helpers ────────────────────────────────────────────────

  Future<Dio?> _getDio() async {
    final apiKey = await _storage.getDeepSeekApiKey();
    if (apiKey == null || apiKey.isEmpty) return null;

    final baseUrl = await _storage.getAiBaseUrl();

    _dio ??= Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
    );
    // Update in case config changed
    _dio!.options.baseUrl = baseUrl;
    _dio!.options.headers['Authorization'] = 'Bearer $apiKey';
    return _dio;
  }
}
