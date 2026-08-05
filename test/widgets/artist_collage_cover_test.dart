import 'package:flutter_test/flutter_test.dart';
import 'package:luobo/widgets/artist_collage_cover.dart';
import '../test_helpers.dart';

void main() {
  // 拼贴布局按专辑张数自适应（1/2/3/≥4），各分支渲染不得抛布局异常。
  // AlbumArtwork 无服务端配置时走占位图，不触发网络。
  for (final count in [1, 2, 3, 4]) {
    testWidgets('$count 张专辑封面渲染不抛错', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          child: ArtistCollageCover(
            coverArtIds: List.generate(count, (i) => 'cover_$i'),
            size: 100,
            placeholderName: '周杰伦',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  group('PlaceholderArtworkDetector', () {
    setUp(() => PlaceholderArtworkDetector.reset());

    test('同一 hash 出现在 ≥3 个不同专辑 id 判定占位（全库共用占位图）', () {
      expect(PlaceholderArtworkDetector.isPlaceholder('h_ph', 'al_1'), isFalse);
      expect(PlaceholderArtworkDetector.isPlaceholder('h_ph', 'al_2'), isFalse);
      expect(PlaceholderArtworkDetector.isPlaceholder('h_ph', 'al_3'), isTrue);
      expect(PlaceholderArtworkDetector.isPlaceholder('h_ph', 'al_4'), isTrue);
    });

    test('同一专辑反复渲染（GridView 重建/来回滑动）不累加，真封面永不误判', () {
      for (var i = 0; i < 10; i++) {
        expect(
          PlaceholderArtworkDetector.isPlaceholder('real_hash', 'al_real'),
          isFalse,
        );
      }
    });

    test('多张真封面 hash 各自唯一，互不干扰', () {
      expect(PlaceholderArtworkDetector.isPlaceholder('h1', 'al_1'), isFalse);
      expect(PlaceholderArtworkDetector.isPlaceholder('h2', 'al_2'), isFalse);
      expect(PlaceholderArtworkDetector.isPlaceholder('h3', 'al_3'), isFalse);
      // 重建：同 id 同 hash 不累加
      expect(PlaceholderArtworkDetector.isPlaceholder('h1', 'al_1'), isFalse);
    });
  });
}
