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
    };
  }
}
