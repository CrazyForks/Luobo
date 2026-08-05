import 'package:flutter_test/flutter_test.dart';
import 'package:luobo/services/playback_context_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('record：置顶 + 去重 + coverArts 上限 4', () async {
    SharedPreferences.setMockInitialValues({});
    final tracker = PlaybackContextTracker();
    await tracker.initialize();

    await tracker.record(
      kind: 'playlist',
      id: 'p1',
      name: '歌单 A',
      coverArts: ['c1', 'c2', 'c3', 'c4', 'c5'], // 超出应裁剪为 4
    );
    await tracker.record(kind: 'starred', id: 'starred', name: '收藏');

    expect(tracker.items.length, 2);
    expect(tracker.items.first.kind, 'starred');
    expect(tracker.items.last.coverArts.length, 4);

    // 重复播放 p1 → 置顶且不新增条目
    await tracker.record(kind: 'playlist', id: 'p1', name: '歌单 A');
    expect(tracker.items.length, 2);
    expect(tracker.items.first.id, 'p1');
  });

  test('record：上限裁剪', () async {
    SharedPreferences.setMockInitialValues({});
    final tracker = PlaybackContextTracker();
    await tracker.initialize();

    for (var i = 0; i < 15; i++) {
      await tracker.record(kind: 'playlist', id: 'p$i', name: 'P$i');
    }
    expect(tracker.items.length, PlaybackContextTracker.maxEntries);
    expect(tracker.items.first.id, 'p14'); // 最新在最前
  });

  test('initialize：从持久化恢复', () async {
    SharedPreferences.setMockInitialValues({});
    final t1 = PlaybackContextTracker();
    await t1.initialize();
    await t1.record(kind: 'playlist', id: 'p1', name: '歌单 A');
    await t1.record(kind: 'starred', id: 'starred', name: '收藏');

    final t2 = PlaybackContextTracker();
    await t2.initialize();
    expect(t2.items.length, 2);
    expect(t2.items.first.kind, 'starred');
    expect(t2.items.first.name, '收藏');
  });
}
