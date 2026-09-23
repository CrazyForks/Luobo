import 'json_coerce.dart';

/// 道理鱼有声书（列表项）。来自 GET /api/library/audiobooks。
///
/// API 无封面字段 → UI 用占位图兜底（见设计 §3/§6）。
class Audiobook {
  final String id; // abk_
  final String title;
  final String? narrator; // narratorDisplayName（可 null）
  final int episodeCount; // 章节总数
  final int? totalDurationSeconds;
  final String? sourcePath; // /Music2/...
  final String? status; // PUBLISHED
  final String? slug;
  final int? playCount;
  final List<String> categories; // 端上类型判断用（§7.4，可为空）
  final List<String> tags; // 与 categories 同源（§7.4 类型判断第二信号）

  Audiobook({
    required this.id,
    required this.title,
    this.narrator,
    this.episodeCount = 0,
    this.totalDurationSeconds,
    this.sourcePath,
    this.status,
    this.slug,
    this.playCount,
    this.categories = const [],
    this.tags = const [],
  });

  factory Audiobook.fromJson(Map<String, dynamic> json) {
    // narratorDisplayName 可能为 null；fallback 到 narrators[0]。
    String? narrator = json['narratorDisplayName']?.toString();
    if (narrator == null || narrator.isEmpty) {
      final narrators = json['narrators'];
      if (narrators is List && narrators.isNotEmpty) {
        narrator = narrators.first.toString();
      }
    }
    return Audiobook(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? json['baseTitle']?.toString() ?? '',
      narrator: narrator,
      episodeCount: jsonInt(json['episodeCount']) ?? 0,
      totalDurationSeconds: jsonInt(json['totalDurationSeconds']),
      sourcePath: json['sourcePath']?.toString(),
      status: json['status']?.toString(),
      slug: json['slug']?.toString(),
      playCount: jsonInt(json['playCount']),
      categories: _stringList(json['categories']),
      tags: _stringList(json['tags']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      if (narrator != null) 'narrator': narrator,
      'episodeCount': episodeCount,
      if (totalDurationSeconds != null)
        'totalDurationSeconds': totalDurationSeconds,
      if (sourcePath != null) 'sourcePath': sourcePath,
      if (status != null) 'status': status,
      if (slug != null) 'slug': slug,
      if (playCount != null) 'playCount': playCount,
      if (categories.isNotEmpty) 'categories': categories,
      if (tags.isNotEmpty) 'tags': tags,
    };
  }

  /// 复用共享 jsonList（P3 修复）：附带 daoliyu 单元素列表输出为 Map 的兼容守卫；
  /// 只取字符串元素（Map/其他类型丢弃，避免 toString 出 "{0: xx}" 脏数据）。
  static List<String> _stringList(dynamic value) {
    return [
      for (final e in jsonList(value))
        if (e is String && e.isNotEmpty) e,
    ];
  }
}
