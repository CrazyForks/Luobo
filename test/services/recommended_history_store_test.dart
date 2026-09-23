import 'package:flutter_test/flutter_test.dart';
import 'package:luobo/services/recommended_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final day1 = DateTime(2026, 9, 23, 10);

  group('RecommendedHistoryStore', () {
    test('同日不冷却、次日冷却、隔一天可再推', () async {
      SharedPreferences.setMockInitialValues({});
      final store = RecommendedHistoryStore();
      await store.initialize();

      store.markRecommended(['a', 'b'], now: day1);

      // 当天（含同日稍后重算）不算冷却，避免「点个收藏换掉整批歌」。
      expect(store.coolingDownIds(now: day1), isEmpty);
      expect(
        store.coolingDownIds(now: day1.add(const Duration(hours: 6))),
        isEmpty,
      );

      // 次日冷却。
      expect(
        store.coolingDownIds(now: day1.add(const Duration(days: 1))),
        {'a', 'b'},
      );

      // 隔一天（cooldownDays=2）可再推。
      expect(
        store.coolingDownIds(now: day1.add(const Duration(days: 2))),
        isEmpty,
      );
    });

    test('跨天按日历天判定（不受时区/DST 偏移影响）', () async {
      SharedPreferences.setMockInitialValues({});
      final store = RecommendedHistoryStore();
      await store.initialize();

      // 只隔 1.5 小时但跨了日历天 → 必须算作 1 天。
      store.markRecommended(['a'], now: DateTime(2026, 3, 8, 23, 30));
      expect(store.coolingDownIds(now: DateTime(2026, 3, 9, 1)), {'a'});
    });

    test('超出冷却窗口的条目在登记时被裁剪', () async {
      SharedPreferences.setMockInitialValues({});
      final store = RecommendedHistoryStore();
      await store.initialize();

      store.markRecommended(['old'], now: day1);
      expect(store.trackedCount, 1);

      // 窗口外再登记一批 → 旧条目被裁掉。
      store.markRecommended(['new'], now: day1.add(const Duration(days: 5)));
      expect(store.trackedCount, 1);
      expect(
        store.coolingDownIds(now: day1.add(const Duration(days: 6))),
        {'new'},
      );
    });

    test('持久化往返：新实例能读回冷却记录', () async {
      SharedPreferences.setMockInitialValues({});
      final first = RecommendedHistoryStore();
      await first.initialize();
      first.markRecommended(['a'], now: day1);
      // 落盘是 fire-and-forget，等一轮微任务。
      await Future<void>.delayed(Duration.zero);

      final second = RecommendedHistoryStore();
      await second.initialize();
      expect(second.isInitialized, isTrue);
      expect(
        second.coolingDownIds(now: day1.add(const Duration(days: 1))),
        {'a'},
      );
    });

    test('数据损坏时从空记录开始，不抛异常', () async {
      SharedPreferences.setMockInitialValues({
        'recommended_history_v1': 'not-json',
      });
      final store = RecommendedHistoryStore();
      await store.initialize();
      expect(store.trackedCount, 0);
      expect(store.coolingDownIds(now: day1), isEmpty);
    });

    test('未初始化时无记录可冷却，登记不抛异常（仅内存）', () {
      final store = RecommendedHistoryStore();
      expect(store.isInitialized, isFalse);
      expect(
        store.coolingDownIds(now: day1.add(const Duration(days: 1))),
        isEmpty,
      );
      store.markRecommended(['a'], now: day1); // 无 prefs 时不得抛异常
      expect(store.trackedCount, 1);
    });
  });
}
