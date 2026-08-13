import 'json_coerce.dart';

/// 道理鱼有声书章节。来自 GET /api/library/audiobooks/{abk_id}/episodes。
///
/// 播放走 Subsonic 层：章节 id（`abe_` 前缀）直接喂 `/rest/stream?id=<abe_>`
/// （明文认证、m4a 直出），不依赖文档中带 token 的 `audioUrl`。
class AudiobookChapter {
  final String id; // abe_
  final String title;
  final int order; // 章节序（1-based，进度记忆按此索引）
  final int? durationSeconds;
  final bool? isPreview;

  AudiobookChapter({
    required this.id,
    required this.title,
    required this.order,
    this.durationSeconds,
    this.isPreview,
  });

  factory AudiobookChapter.fromJson(Map<String, dynamic> json) {
    return AudiobookChapter(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      order: jsonInt(json['order']) ?? 0,
      durationSeconds: jsonInt(json['durationSeconds']),
      isPreview: jsonBool(json['isPreview']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'order': order,
      if (durationSeconds != null) 'durationSeconds': durationSeconds,
      if (isPreview != null) 'isPreview': isPreview,
    };
  }
}

/// 章节列表（服务端分页响应）。`total` = 服务端 `count`，用于计算总页数。
class AudiobookChapterPage {
  final List<AudiobookChapter> chapters;
  final int total;

  AudiobookChapterPage({
    required this.chapters,
    required this.total,
  });
}
