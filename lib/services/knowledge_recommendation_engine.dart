import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 知识图谱内容层推荐引擎（纯 Dart，可单测）。
///
/// 输入：songId → 逗号分隔的 AI 标签串（来自 [SongKnowledgeCache.getAllTags]）。
/// 提供：倒排索引、歌-歌 Jaccard 相似度（一跳邻居）、用户标签偏好向量、
/// 内容分（用户偏好 × 歌曲标签的余弦相似度）。
///
/// 对应设计文档 `docs/首页重构技术方案.md` §4.2。
class KnowledgeRecommendationEngine extends ChangeNotifier {
  Map<String, Set<String>> _songTags = {};
  Map<String, Set<String>> _tagSongs = {};
  Map<String, double> _userTagPref = {};
  bool _prefNormalized = false;

  /// 是否已构建索引（有歌有标签）。
  bool get hasIndex => _songTags.isNotEmpty;

  /// 有标签的歌数量。
  int get songCount => _songTags.length;

  /// 标签种类数。
  int get tagCount => _tagSongs.length;

  /// 重建索引。知识库导入 / 生成完成后调用（§4.8 时序第 3 点）。
  void rebuild(Map<String, String> tagsBySongId) {
    _songTags = {};
    _tagSongs = {};
    for (final entry in tagsBySongId.entries) {
      final tags = parseTags(entry.value);
      if (tags.isEmpty) continue;
      _songTags[entry.key] = tags;
      for (final tag in tags) {
        _tagSongs.putIfAbsent(tag, () => {}).add(entry.key);
      }
    }
    _invalidatePref();
    notifyListeners();
  }

  /// 解析逗号分隔标签串，去空、去重。
  static Set<String> parseTags(String raw) {
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  /// 某首歌的标签集合；无标签返回 null。
  Set<String>? tagsOf(String songId) => _songTags[songId];

  /// 拥有某标签的全部歌。
  Set<String> songsWithTag(String tag) => _tagSongs[tag] ?? const {};

  /// 两个标签集合的 Jaccard 相似度 |A∩B| / |A∪B|。
  double jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    return union == 0 ? 0 : intersection / union;
  }

  /// 与 [songId] 最相似的其他歌（一跳邻居），按相似度降序。
  List<String> findSimilar(
    String songId, {
    int limit = 20,
    double minSimilarity = 0.25,
    Set<String>? exclude,
  }) {
    final base = _songTags[songId];
    if (base == null || base.isEmpty) return const [];
    final ex = exclude ?? const {};
    final scored = <MapEntry<String, double>>[];
    for (final entry in _songTags.entries) {
      if (entry.key == songId || ex.contains(entry.key)) continue;
      final sim = jaccard(base, entry.value);
      if (sim >= minSimilarity) scored.add(MapEntry(entry.key, sim));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).map((e) => e.key).toList();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 用户标签偏好向量
  // ──────────────────────────────────────────────────────────────────────────

  /// 把某首歌的行为权重累加到它的标签上（增量更新，§4.8 时序第 2 点）。
  void addUserPref(String songId, double weight) {
    final tags = _songTags[songId];
    if (tags == null || tags.isEmpty || weight == 0) return;
    for (final tag in tags) {
      _userTagPref[tag] = (_userTagPref[tag] ?? 0) + weight;
    }
    _prefNormalized = false;
  }

  /// 清空用户标签偏好向量。
  void clearUserPref() {
    _userTagPref = {};
    _prefNormalized = true;
  }

  /// 归一化偏好向量到 [0,1]（除以最大值）。调用 contentScore 前自动触发。
  void normalizeUserPref() {
    if (_userTagPref.isEmpty) {
      _prefNormalized = true;
      return;
    }
    final maxPref = _userTagPref.values.reduce(math.max);
    if (maxPref <= 0) {
      _userTagPref = {};
      _prefNormalized = true;
      return;
    }
    _userTagPref = _userTagPref.map(
      (tag, v) => MapEntry(tag, (v / maxPref).clamp(0.0, 1.0)),
    );
    _prefNormalized = true;
  }

  /// 用户标签偏好向量（只读，已归一化）。
  Map<String, double> get userTagPref {
    if (!_prefNormalized) normalizeUserPref();
    return Map.unmodifiable(_userTagPref);
  }

  /// 内容分：用户偏好向量与歌曲标签向量的余弦相似度（0..1）。
  ///
  /// 偏好向量为归一化后的 userTagPref，歌曲标签向量为二值；分母 |pref|
  /// 对全库恒定，故等价于点积排序，且天然在 [0,1]。
  double contentScore(Set<String> tags) {
    if (!_prefNormalized) normalizeUserPref();
    if (_userTagPref.isEmpty || tags.isEmpty) return 0;
    var dot = 0.0;
    for (final tag in tags) {
      dot += _userTagPref[tag] ?? 0;
    }
    final prefNorm =
        math.sqrt(_userTagPref.values.fold(0.0, (sum, v) => sum + v * v));
    if (prefNorm <= 0) return 0;
    return (dot / prefNorm).clamp(0.0, 1.0);
  }

  /// 偏好最高的前 [n] 个标签。
  List<String> topPrefTags(int n) {
    final sorted = userTagPref.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(n).map((e) => e.key).toList();
  }

  /// 探索兜底：偏好前 [topTags] 个标签的代表歌（未在 [exclude] 中），
  /// 每标签最多 [perTag] 首。用户无偏好时返回空。
  List<String> representativeSongs({
    int topTags = 5,
    int perTag = 4,
    Set<String>? exclude,
  }) {
    final ex = exclude ?? const {};
    final result = <String>[];
    final seen = <String>{};
    for (final tag in topPrefTags(topTags)) {
      for (final songId in songsWithTag(tag)) {
        if (ex.contains(songId) || !seen.add(songId)) continue;
        result.add(songId);
        if (result.length >= topTags * perTag) break;
      }
      if (result.length >= topTags * perTag) break;
    }
    return result;
  }

  void _invalidatePref() {
    _prefNormalized = false;
  }
}
