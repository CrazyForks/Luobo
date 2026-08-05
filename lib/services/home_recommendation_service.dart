import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'knowledge_recommendation_engine.dart';
import 'recommendation_service.dart';
import 'song_knowledge_cache.dart';

/// 场景 Mix 类型（§4.7）。
enum SceneMix { commute, study, sleep }

/// 首页一次生成的全部推荐数据（§6 数据契约），各模块已全局去重。
class HomeFeed {
  final List<Song> daily;
  final List<Song> commuteMix;
  final List<Song> studyMix;
  final List<Song> sleepMix;
  final List<Song> favorites;
  final List<Song> discover;

  const HomeFeed({
    required this.daily,
    required this.commuteMix,
    required this.studyMix,
    required this.sleepMix,
    required this.favorites,
    required this.discover,
  });

  bool get isEmpty =>
      daily.isEmpty &&
      commuteMix.isEmpty &&
      studyMix.isEmpty &&
      sleepMix.isEmpty &&
      favorites.isEmpty &&
      discover.isEmpty;
}

/// 首页推荐编排服务（§4.3-4.8）。
///
/// 职责：把「用户行为（[RecommendationService]）」与「知识图谱内容
/// （[KnowledgeRecommendationEngine]）」融合成首页各模块数据：
/// - 融合打分 finalScore = α·行为分 + (1-α)·内容分，α=0.7（§4.4）
/// - 熟悉/探索分层：每日推荐按融合分从全库取（熟悉优先、未听过补足），场景 Mix
///   仍以熟悉层为主，探索发现只推未听过的（§4.5）
/// - 跨模块全局去重 + 同歌手≤2 首 / 同专辑≤1 首（§4.6）
/// - 每日推荐当日固定、探索发现按周固定（§4.8）
/// - 无图谱 / 无行为自动退化（§4.4）
class HomeRecommendationService extends ChangeNotifier {
  HomeRecommendationService({
    required RecommendationService behavior,
    KnowledgeRecommendationEngine? engine,
    SongKnowledgeCache? knowledgeCache,
    Duration prefDebounce = const Duration(milliseconds: 800),
  })  : _behavior = behavior,
        _engine = engine ?? KnowledgeRecommendationEngine(),
        _knowledgeCache = knowledgeCache,
        _prefDebounce = prefDebounce {
    // 行为数据变化（播放/评分/收藏）后防抖重建用户标签偏好向量（§4.8 时序 2）。
    _behavior.addListener(_onBehaviorChanged);
  }

  /// 融合权重 α：行为:内容 = 7:3（已确认，调向 0.5 属二期 §9）。
  static const double alpha = 0.7;

  static const int dailyLimit = 30;
  static const int mixLimit = 20;
  static const int discoverLimit = 20;

  /// 探索层一跳邻居的最小相似度（§8-2 已确认 Jaccard>0.25）。
  static const double discoverMinSimilarity = 0.25;

  /// 无标签歌的兜底：直接把 genre 当伪标签参与内容分（§4.3）。
  static const bool genreFallback = true;

  final RecommendationService _behavior;
  final KnowledgeRecommendationEngine _engine;
  final SongKnowledgeCache? _knowledgeCache;
  final Duration _prefDebounce;

  DateTime? _syncedCacheTime;
  Timer? _prefDebounceTimer;

  /// 知识库版本号：重建后 +1，缓存仅在同一版本内命中
  /// （避免一次性脏标记在多模块间串扰，见 P0 单测暴露的问题）。
  int _knowledgeVersion = 0;
  Map<String, _CacheEntry> _dailyCache = {};
  Map<String, _CacheEntry> _discoverCache = {};

  KnowledgeRecommendationEngine get engine => _engine;

  bool get hasKnowledge => _engine.hasIndex;
  bool get hasBehavior =>
      _behavior.profiles.isNotEmpty || _behavior.starredSongIds.isNotEmpty;

  // ──────────────────────────────────────────────────────────────────────────
  // 数据入口（§4.8 时序）
  // ──────────────────────────────────────────────────────────────────────────

  /// 重建知识图谱索引。知识库导入 / 生成完成后调用。
  void rebuildKnowledge(Map<String, String> tagsBySongId) {
    _engine.rebuild(tagsBySongId);
    _knowledgeVersion++;
    notifyListeners();
  }

  /// 知识库缓存自动同步：缓存未初始化或更新时间未变化则跳过；
  /// `generateFeed` 每次调用前执行，知识库生成/导入后无需额外挂钩。
  void refreshKnowledgeFromCache() {
    final cache = _knowledgeCache;
    if (cache == null || !cache.isInitialized) return;
    final updated = cache.getLastUpdateTime();
    if (updated != null && updated == _syncedCacheTime) return;
    rebuildKnowledge(cache.getAllTags());
    _syncedCacheTime = updated;
  }

  void _onBehaviorChanged() {
    _prefDebounceTimer?.cancel();
    _prefDebounceTimer = Timer(_prefDebounce, refreshUserPref);
  }

  /// 从行为数据重建用户标签偏好向量。播放 / 评分 / 收藏等行为变化后调用。
  void refreshUserPref() {
    _engine.clearUserPref();
    for (final profile in _behavior.profiles.values) {
      final w = _behaviorWeight(profile);
      if (w != 0) _engine.addUserPref(profile.songId, w);
    }
    // 收藏但未播放的歌也贡献偏好（+2.0，与 _behaviorWeight 一致）。
    for (final id in _behavior.starredSongIds) {
      _engine.addUserPref(id, 2.0);
    }
    _engine.normalizeUserPref();
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 打分
  // ──────────────────────────────────────────────────────────────────────────

  double _behaviorScore(Song song) => _behavior.calculateSongScore(song);

  double _contentScore(Song song) {
    final tags = _engine.tagsOf(song.id);
    if (tags != null && tags.isNotEmpty) return _engine.contentScore(tags);
    if (genreFallback) {
      final genre = song.genre;
      if (genre != null && genre.isNotEmpty) return _engine.contentScore({genre});
    }
    return 0;
  }

  double _effectiveAlpha() {
    if (!hasKnowledge) return 1.0; // 无图谱 → 纯行为（§4.4）
    if (!hasBehavior) return 0.0; // 无行为 → 纯内容
    return alpha;
  }

  double _fusionScore(Song song) {
    final a = _effectiveAlpha();
    return a * _behaviorScore(song) + (1 - a) * _contentScore(song);
  }

  bool _isHeard(Song song) => _behavior.profiles.containsKey(song.id);

  /// 熟悉层候选池：只取听过的歌；听过的不足 12 首时用全库补足（冷启动）。
  List<Song> _familiarPool(List<Song> allSongs) {
    final heard = allSongs.where(_isHeard).toList();
    if (heard.length >= 12) return heard;
    return [...heard, ...allSongs.where((s) => !_isHeard(s))];
  }

  /// 按 [score]（默认融合分）降序选歌，应用「同歌手≤2 / 同专辑≤1」上限与
  /// 排除集合，并把选中的歌写入 [exclude]（跨模块全局去重，§4.6）。
  /// 未传入 [exclude] 时使用内部可变集合，不对外暴露。
  List<Song> _selectWithDedup(
    List<Song> candidates, {
    required int limit,
    Set<String>? exclude,
    double Function(Song)? score,
  }) {
    final ex = exclude ?? <String>{};
    final sortScore = score ?? _fusionScore;
    final artistCount = <String, int>{};
    final albumCount = <String, int>{};
    final sorted = [...candidates]
      ..sort((a, b) => sortScore(b).compareTo(sortScore(a)));
    final result = <Song>[];
    for (final song in sorted) {
      if (result.length >= limit) break;
      if (ex.contains(song.id)) continue;
      final artist = song.artist;
      if (artist != null && (artistCount[artist] ?? 0) >= 2) continue;
      final albumId = song.albumId;
      if (albumId != null && (albumCount[albumId] ?? 0) >= 1) continue;
      result.add(song);
      ex.add(song.id);
      if (artist != null) artistCount[artist] = (artistCount[artist] ?? 0) + 1;
      if (albumId != null) albumCount[albumId] = (albumCount[albumId] ?? 0) + 1;
    }
    return result;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 首页各模块（§6 数据契约）
  // ──────────────────────────────────────────────────────────────────────────

  /// 每日推荐：全库按融合分 Top30——行为分让听过的歌优先，去重上限卡满后由
  /// 未听过的歌（内容分）补足，避免熟悉池过小/集中时推不满 30 首；当日固定
  /// （key=日期）。
  List<Song> dailyRecommendation({
    required List<Song> allSongs,
    int limit = dailyLimit,
    DateTime? now,
    Set<String>? exclude,
  }) {
    final day = _dayKey(now ?? DateTime.now());
    final cached = _dailyCache[day];
    if (cached != null && cached.version == _knowledgeVersion) {
      return cached.songs;
    }

    final list = _selectWithDedup(
      allSongs,
      limit: limit,
      exclude: exclude,
    );
    _dailyCache[day] = _CacheEntry(_knowledgeVersion, list);
    return list;
  }

  static const Map<SceneMix, List<String>> _sceneKeywords = {
    SceneMix.commute: ['高能量', '快节奏', '运动', '活力', '兴奋', '劲爆', '燃'],
    SceneMix.study: ['纯音乐', '轻音乐', '舒缓', '安静', '平静', '治愈', '放松'],
    SceneMix.sleep: ['治愈', '舒缓', '慢', '安静', '催眠', '放松', '深夜', '低能量'],
  };

  bool _matchesScene(Song song, List<String> keywords) {
    final tags = _engine.tagsOf(song.id);
    if (tags == null || tags.isEmpty) return false;
    return tags.any((tag) => keywords.any((k) => tag.contains(k)));
  }

  /// 场景 Mix：熟悉层 + 标签过滤（§4.7），不足时全库补足。
  List<Song> sceneMix(
    SceneMix mix, {
    required List<Song> allSongs,
    int limit = mixLimit,
    Set<String>? exclude,
  }) {
    final keywords = _sceneKeywords[mix]!;
    final filtered = _familiarPool(allSongs)
        .where((s) => _matchesScene(s, keywords))
        .toList();
    if (filtered.length < limit) {
      final extra = allSongs
          .where((s) => !filtered.contains(s) && _matchesScene(s, keywords))
          .toList();
      filtered.addAll(extra);
    }
    return _selectWithDedup(filtered, limit: limit, exclude: exclude);
  }

  /// 你的最爱 Mix：熟悉层按「最爱分」（行为权重，收藏/评分/完成度/播放次数）
  /// 降序——不含最近播放惩罚，语义为长期最爱而非近期播放。
  List<Song> favoritesMix({
    required List<Song> allSongs,
    int limit = mixLimit,
    Set<String>? exclude,
  }) {
    final pool = _familiarPool(allSongs).toList()
      ..sort((a, b) => _favoriteScore(b).compareTo(_favoriteScore(a)));
    return _selectWithDedup(
      pool,
      limit: limit,
      exclude: exclude,
      score: _favoriteScore,
    );
  }

  /// 最爱分 = 行为综合权重（[SongProfile] 无则 0）。
  double _favoriteScore(Song song) {
    final profile = _behavior.profiles[song.id];
    if (profile == null) return 0;
    return _behaviorWeight(profile);
  }

  /// 探索发现：未听过的歌，取行为分最高的听过歌为种子做一跳邻居（§4.5），
  /// 不足时用偏好标签代表歌兜底；按周固定（key=周序号）。
  List<Song> discoverSongs({
    required List<Song> allSongs,
    int limit = discoverLimit,
    DateTime? now,
    Set<String>? exclude,
  }) {
    final week = _weekKey(now ?? DateTime.now());
    final cached = _discoverCache[week];
    if (cached != null && cached.version == _knowledgeVersion) {
      return cached.songs;
    }

    final byId = {for (final s in allSongs) s.id: s};
    final ex = exclude ?? <String>{};
    // 探索层只推未听过的歌：邻居/代表歌检索时排除全部已听歌曲。
    final similarExclude = <String>{...ex, ..._behavior.profiles.keys};
    final picked = <String>{};
    final result = <Song>[];

    void addCandidate(String id) {
      if (picked.contains(id) || ex.contains(id)) return;
      final song = byId[id];
      if (song == null || _isHeard(song)) return;
      // 探索层同样受同歌手≤2/同专辑≤1 约束（§4.6）。
      if (song.artist != null &&
          _countIn(result, (s) => s.artist == song.artist) >= 2) {
        return;
      }
      if (song.albumId != null &&
          _countIn(result, (s) => s.albumId == song.albumId) >= 1) {
        return;
      }
      picked.add(id);
      result.add(song);
    }

    final heard = allSongs.where(_isHeard).toList()
      ..sort((a, b) => _behaviorScore(b).compareTo(_behaviorScore(a)));

    for (final seed in heard.take(10)) {
      if (result.length >= limit) break;
      for (final id in _engine.findSimilar(
        seed.id,
        limit: 8,
        minSimilarity: discoverMinSimilarity,
        exclude: similarExclude,
      )) {
        if (result.length >= limit) break;
        addCandidate(id);
      }
    }

    // 无行为（无种子）或种子邻居不足时：偏好标签代表歌 / 内容分兜底。
    if (result.length < limit) {
      final representative = _engine.representativeSongs(
        topTags: 5,
        perTag: 4,
        exclude: similarExclude,
      );
      for (final id in representative) {
        if (result.length >= limit) break;
        addCandidate(id);
      }
    }
    if (result.length < limit) {
      final unheardByContent = allSongs.where((s) {
        return !_isHeard(s) && !picked.contains(s.id) && !ex.contains(s.id);
      }).toList()
        ..sort((a, b) => _contentScore(b).compareTo(_contentScore(a)));
      for (final song in unheardByContent) {
        if (result.length >= limit) break;
        addCandidate(song.id);
      }
    }

    _discoverCache[week] = _CacheEntry(_knowledgeVersion, result);
    return result;
  }

  /// 一次生成首页全部模块（§6），模块间全局去重。
  HomeFeed generateFeed({
    required List<Song> allSongs,
    DateTime? now,
  }) {
    refreshKnowledgeFromCache();
    final used = <String>{};
    final daily = dailyRecommendation(allSongs: allSongs, now: now, exclude: used);
    final commute = sceneMix(SceneMix.commute, allSongs: allSongs, exclude: used);
    final study = sceneMix(SceneMix.study, allSongs: allSongs, exclude: used);
    final sleep = sceneMix(SceneMix.sleep, allSongs: allSongs, exclude: used);
    final favorites = favoritesMix(allSongs: allSongs, exclude: used);
    final discover = discoverSongs(allSongs: allSongs, now: now, exclude: used);
    return HomeFeed(
      daily: daily,
      commuteMix: commute,
      studyMix: study,
      sleepMix: sleep,
      favorites: favorites,
      discover: discover,
    );
  }

  /// 清空每日/每周缓存（行为数据大幅变化或手动刷新时调用）。
  void clearCaches() {
    _dailyCache = {};
    _discoverCache = {};
    notifyListeners();
  }

  @override
  void dispose() {
    _prefDebounceTimer?.cancel();
    _behavior.removeListener(_onBehaviorChanged);
    _engine.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 工具
  // ──────────────────────────────────────────────────────────────────────────

  /// 行为综合权重（§4.2 w(s)）：收藏 +2.0 / 评分 / 完成度 / 播放次数，跳过衰减。
  double _behaviorWeight(SongProfile profile) {
    var w = 0.0;
    if (_behavior.starredSongIds.contains(profile.songId)) w += 2.0;
    if (profile.userRating != null) w += profile.userRating! / 5.0;
    w += profile.completionRate;
    w += math.min(profile.playCount / 10.0, 1.0);
    if (profile.isDisliked) w -= 0.8;
    return w.clamp(0.0, 4.0);
  }

  int _countIn(List<Song> songs, bool Function(Song) test) =>
      songs.where(test).length;

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// ISO 周 key：以周一日期为标识。
  static String _weekKey(DateTime d) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }
}

/// 缓存条目：记录生成时的知识库版本，仅在版本一致时命中。
class _CacheEntry {
  const _CacheEntry(this.version, this.songs);

  final int version;
  final List<Song> songs;
}
