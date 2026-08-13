import 'package:flutter_test/flutter_test.dart';
import 'package:luobo/models/audiobook.dart';
import 'package:luobo/models/audiobook_chapter.dart';

/// 道理鱼有声书模型解析单测（设计 §12-1）：
/// 用 §3 实测形状构造 JSON → 列表/章节解析 + 字段缺失容错。
void main() {
  group('Audiobook', () {
    test('从完整 JSON 解析列表项', () {
      final json = {
        'id': 'abk_1',
        'title': '鬼吹灯',
        'baseTitle': '鬼吹灯',
        'slug': 'guichuideng',
        'status': 'PUBLISHED',
        'isSerializing': false,
        'narrators': ['张三'],
        'narratorDisplayName': '张三',
        'categories': [],
        'tags': [],
        'episodeCount': 120,
        'totalDurationSeconds': 360000,
        'lastEpisodePublishedAt': '2026-08-01T00:00:00Z',
        'updatedAt': '2026-08-01T00:00:00Z',
        'playCount': 42,
        'sourcePath': '/Music2/guichuideng',
      };

      final book = Audiobook.fromJson(json);

      expect(book.id, 'abk_1');
      expect(book.title, '鬼吹灯');
      expect(book.narrator, '张三');
      expect(book.episodeCount, 120);
      expect(book.totalDurationSeconds, 360000);
      expect(book.sourcePath, '/Music2/guichuideng');
      expect(book.status, 'PUBLISHED');
      expect(book.playCount, 42);
    });

    test('narratorDisplayName 为 null 时回退 narrators[0]', () {
      final json = {
        'id': 'abk_2',
        'title': '三体',
        'episodeCount': 50,
        'narrators': ['李四'],
      };

      final book = Audiobook.fromJson(json);

      expect(book.narrator, '李四');
    });

    test('字段缺失时容错（id/title 为空串，narrator 为 null）', () {
      final book = Audiobook.fromJson({'episodeCount': '7'});

      expect(book.id, '');
      expect(book.title, '');
      expect(book.narrator, isNull);
      // 服务端 XML→JSON 直转可能输出字符串数字 → 宽容解析
      expect(book.episodeCount, 7);
    });

    test('toJson 往返一致（可空字段不输出）', () {
      final book = Audiobook.fromJson({
        'id': 'abk_3',
        'title': '今古奇观',
        'episodeCount': 10,
      });

      final roundTripped = Audiobook.fromJson(book.toJson());

      expect(roundTripped.id, book.id);
      expect(roundTripped.title, book.title);
      expect(roundTripped.episodeCount, book.episodeCount);
    });
  });

  group('AudiobookChapter', () {
    test('从完整 JSON 解析章节', () {
      final json = {
        'id': 'abe_101',
        'title': '第一章 风起',
        'order': 1,
        'durationSeconds': 1800,
        'audioPath': '/Music2/guichuideng/ch1.m4a',
        'audioUrl': 'http://example/api/stream?token=x',
        'publishedAt': '2026-08-01T00:00:00Z',
        'isPreview': false,
      };

      final chapter = AudiobookChapter.fromJson(json);

      expect(chapter.id, 'abe_101');
      expect(chapter.title, '第一章 风起');
      expect(chapter.order, 1);
      expect(chapter.durationSeconds, 1800);
      expect(chapter.isPreview, false);
    });

    test('字段缺失时容错', () {
      final chapter = AudiobookChapter.fromJson({'id': 'abe_1'});

      expect(chapter.id, 'abe_1');
      expect(chapter.title, '');
      expect(chapter.order, 0);
      expect(chapter.durationSeconds, isNull);
      expect(chapter.isPreview, isNull);
    });
  });

  group('AudiobookChapterPage', () {
    test('保存 chapters 与 total', () {
      final page = AudiobookChapterPage(
        chapters: [AudiobookChapter(id: 'abe_1', title: 'a', order: 1)],
        total: 120,
      );

      expect(page.chapters.length, 1);
      expect(page.total, 120);
    });
  });
}
