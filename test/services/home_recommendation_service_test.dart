import 'package:flutter_test/flutter_test.dart';
import 'package:luobo/models/song.dart';
import 'package:luobo/services/home_recommendation_service.dart';
import 'package:luobo/services/recommendation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song _song(
  String id, {
  String? artist,
  String? albumId,
  String? genre,
}) =>
    Song(
      id: id,
      title: 'Song $id',
      artist: artist,
      albumId: albumId,
      genre: genre,
    );

Map<String, String> _tagsFor(Iterable<Song> songs, String tag) => {
      for (final s in songs) s.id: tag,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecommendationService behavior;
  late HomeRecommendationService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    behavior = RecommendationService();
    await behavior.initialize();
    service = HomeRecommendationService(behavior: behavior);
  });

  Future<void> play(Song song, {bool completed = true}) =>
      behavior.trackSongPlay(song, completed: completed);

  group('HomeRecommendationService', () {
    test('refreshUserPref 从行为与收藏构建标签偏好', () async {
      service.rebuildKnowledge({'a': '摇滚,深夜', 'b': '摇滚,治愈'});
      await play(_song('a', artist: 'X', albumId: 'al1'));
      await behavior.trackStarred(_song('b', artist: 'Y'), true);
      service.refreshUserPref();

      final pref = service.engine.userTagPref;
      expect(pref, isNotEmpty);
      expect(pref['摇滚'], greaterThan(0.0)); // a 播放 + b 收藏都含摇滚
      expect(pref['深夜'], greaterThan(0.0));
      expect(pref['治愈'], greaterThan(0.0));
    });

    test('分层：每日推荐熟悉优先 + 未听过补足，探索发现只推未听过的', () async {
      final heard = List.generate(
          15, (i) => _song('h$i', artist: 'A${i % 3}', albumId: 'al$i'));
      final unheard = List.generate(
          10, (i) => _song('u$i', artist: 'B$i', albumId: 'bl$i'));
      for (final s in heard) {
        await play(s);
      }
      service.rebuildKnowledge(_tagsFor([...heard, ...unheard], '摇滚,深夜'));
      service.refreshUserPref();

      final all = [...heard, ...unheard];
      final daily = service.dailyRecommendation(allSongs: all);
      final discover = service.discoverSongs(allSongs: all);

      expect(daily, isNotEmpty);
      // 熟悉优先：融合分（行为 0.7 权重）让听过的歌排在未听过之前。
      expect(daily.first.id.startsWith('h'), isTrue);
      // 去重上限卡满后由未听过的歌补足：听过的只占 6 首（3 歌手×≤2），
      // 未听过的 10 首全部进池。
      expect(daily.length, 16);
      expect(daily.any((s) => s.id.startsWith('u')), isTrue);
      expect(discover, isNotEmpty);
      expect(discover.every((s) => s.id.startsWith('u')), isTrue);
    });

    test('去重：同一歌手≤2 首、同一专辑≤1 首', () async {
      // 30 首全部来自歌手 X，其中每 3 首共享一个专辑。
      final songs = List.generate(
        30,
        (i) => _song('h$i', artist: 'X', albumId: 'al${i ~/ 3}'),
      );
      for (final s in songs) {
        await play(s);
      }
      service.rebuildKnowledge(_tagsFor(songs, '摇滚,深夜'));
      service.refreshUserPref();

      final daily = service.dailyRecommendation(allSongs: songs, limit: 30);

      final artistX = daily.where((s) => s.artist == 'X').length;
      expect(artistX, lessThanOrEqualTo(2));

      final albumIds = daily.map((s) => s.albumId).toSet();
      expect(albumIds.length, daily.length); // 每专辑 ≤1
    });

    test('跨模块全局去重：generateFeed 各模块两两不重叠', () async {
      final songs = List.generate(
          40, (i) => _song('h$i', artist: 'A${i % 5}', albumId: 'al$i'));
      for (final s in songs) {
        await play(s);
      }
      service.rebuildKnowledge(_tagsFor(songs, '摇滚,深夜'));
      service.refreshUserPref();

      final feed = service.generateFeed(allSongs: songs);
      final allIds = [
        ...feed.daily.map((s) => s.id),
        ...feed.commuteMix.map((s) => s.id),
        ...feed.studyMix.map((s) => s.id),
        ...feed.sleepMix.map((s) => s.id),
        ...feed.discover.map((s) => s.id),
      ];
      expect(allIds.toSet().length, allIds.length);
    });

    test('场景 Mix：只含匹配场景标签的歌', () async {
      final commute =
          List.generate(8, (i) => _song('c$i', artist: 'A', albumId: 'al$i'));
      final sleep =
          List.generate(8, (i) => _song('s$i', artist: 'B', albumId: 'bl$i'));
      final other =
          List.generate(8, (i) => _song('o$i', artist: 'C', albumId: 'cl$i'));
      for (final s in [...commute, ...sleep, ...other]) {
        await play(s);
      }
      service.rebuildKnowledge({
        ..._tagsFor(commute, '摇滚,高能量,快节奏'),
        ..._tagsFor(sleep, '治愈,舒缓,慢'),
        ..._tagsFor(other, '流行,快乐'),
      });
      service.refreshUserPref();

      final commuteMix = service.sceneMix(SceneMix.commute,
          allSongs: [...commute, ...sleep, ...other]);
      final sleepMix = service
          .sceneMix(SceneMix.sleep, allSongs: [...commute, ...sleep, ...other]);

      expect(commuteMix, isNotEmpty);
      expect(commuteMix.every((s) => s.id.startsWith('c')), isTrue);
      expect(sleepMix, isNotEmpty);
      expect(sleepMix.every((s) => s.id.startsWith('s')), isTrue);
    });

    test('每日推荐当日固定：同日返回同一批，次日重新生成', () async {
      final songs =
          List.generate(15, (i) => _song('h$i', artist: 'A', albumId: 'al$i'));
      for (final s in songs) {
        await play(s);
      }
      service.rebuildKnowledge(_tagsFor(songs, '摇滚,深夜'));
      service.refreshUserPref();

      final now = DateTime(2026, 8, 4, 10);
      final first = service.dailyRecommendation(allSongs: songs, now: now);
      final second = service.dailyRecommendation(allSongs: songs, now: now);
      expect(second, same(first));

      final nextDay = service.dailyRecommendation(
        allSongs: songs,
        now: now.add(const Duration(days: 1)),
      );
      expect(nextDay, isNot(same(first)));
    });

    test('探索发现按日固定：同日返回同一批，次日重新生成', () async {
      final heard = List.generate(
          12, (i) => _song('h$i', artist: 'A${i % 3}', albumId: 'al$i'));
      final unheard = List.generate(
          10, (i) => _song('u$i', artist: 'B$i', albumId: 'bl$i'));
      for (final s in heard) {
        await play(s);
      }
      service.rebuildKnowledge(_tagsFor([...heard, ...unheard], '摇滚,深夜'));
      service.refreshUserPref();

      final all = [...heard, ...unheard];
      final now = DateTime(2026, 8, 4, 10); // 周二
      final first = service.discoverSongs(allSongs: all, now: now);
      final second = service.discoverSongs(
          allSongs: all, now: now.add(const Duration(hours: 3)));
      expect(second, same(first));

      // 次日重新生成
      final nextDay = service.discoverSongs(
        allSongs: all,
        now: now.add(const Duration(days: 1)),
      );
      expect(nextDay, isNot(same(first)));
    });

    test('favoritesMix：你的最爱 = 熟悉层按行为分降序', () async {
      final songs = List.generate(
          15, (i) => _song('h$i', artist: 'A${i % 3}', albumId: 'al$i'));
      // 只给前 5 首完整播放（完成度满分），后 10 首跳过一次。
      for (final s in songs.take(5)) {
        await play(s, completed: true);
      }
      for (final s in songs.skip(5)) {
        await behavior.trackSkip(s);
      }
      service.rebuildKnowledge(_tagsFor(songs, '摇滚,深夜'));
      service.refreshUserPref();

      final favorites = service.favoritesMix(allSongs: songs, limit: 10);
      expect(favorites, isNotEmpty);
      // 行为分最高的前 5 首应排在前面。
      final topIds = songs.take(5).map((s) => s.id).toSet();
      expect(topIds.contains(favorites.first.id), isTrue);
      // 每专辑 ≤1（去重生效）。
      expect(favorites.map((s) => s.albumId).toSet().length, favorites.length);
    });

    test('退化：无图谱时 α=1，纯行为排序', () async {
      final songs = List.generate(
          15, (i) => _song('h$i', artist: 'A${i % 3}', albumId: 'al$i'));
      for (final s in songs) {
        await play(s);
      }
      // 不 rebuildKnowledge → 无图谱
      service.refreshUserPref();

      final daily = service.dailyRecommendation(allSongs: songs);
      expect(daily, isNotEmpty);
      // 无图谱时行为分主导，日推全是听过的歌
      expect(daily.every((s) => s.id.startsWith('h')), isTrue);
    });

    test('退化：无行为时 α=0，内容分主导且不崩溃', () async {
      final songs = List.generate(
          20, (i) => _song('u$i', artist: 'B$i', albumId: 'bl$i'));
      service.rebuildKnowledge(_tagsFor(songs, '摇滚,深夜'));
      service.refreshUserPref();

      final daily = service.dailyRecommendation(allSongs: songs);
      final discover = service.discoverSongs(allSongs: songs);

      expect(daily, isNotEmpty);
      expect(discover, isNotEmpty);
    });

    test('完全冷启动：无行为且无图谱时仍返回非空、不崩溃', () {
      final songs = List.generate(
          30, (i) => _song('u$i', artist: 'B$i', albumId: 'bl$i'));
      final daily = service.dailyRecommendation(allSongs: songs);
      expect(daily.length, 30);
      final feed = service.generateFeed(allSongs: songs);
      expect(feed.isEmpty, isFalse);
    });

    test('知识库重建后使每日缓存失效', () async {
      final songs =
          List.generate(15, (i) => _song('h$i', artist: 'A', albumId: 'al$i'));
      for (final s in songs) {
        await play(s);
      }
      final now = DateTime(2026, 8, 4, 10);
      service.rebuildKnowledge(_tagsFor(songs, '摇滚,深夜'));
      service.refreshUserPref();

      final before = service.dailyRecommendation(allSongs: songs, now: now);
      service.rebuildKnowledge(_tagsFor(songs, '流行,快乐'));
      final after = service.dailyRecommendation(allSongs: songs, now: now);
      expect(after, isNot(same(before)));
    });
  });
}
