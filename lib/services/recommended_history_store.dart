import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 「最近推荐过」记录：每日推荐的**跨天冷却**依据
/// （`docs/每日推荐探索配额与冷却技术方案.md` §3.3）。
///
/// 只记 `songId → 推荐日序号`：冷却窗口内不再重复推荐，窗口外自动裁剪。
/// 纯本地、不上报；未 [initialize] 时 [coolingDownIds] 恒为空（退化为无冷却）。
class RecommendedHistoryStore {
  RecommendedHistoryStore({this.cooldownDays = defaultCooldownDays});

  static const String _prefsKey = 'recommended_history_v1';

  /// 冷却窗口（天）：**当天**推荐过的不冷却（同日重算不会整批换歌），
  /// 前 `cooldownDays - 1` 天推荐过的冷却——实际语义为「隔一天可再推」。
  static const int defaultCooldownDays = 2;

  final int cooldownDays;

  final Map<String, int> _dayBySong = {};
  SharedPreferences? _prefs;

  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// 已登记（且在冷却窗口内）的歌曲数，供诊断与测试用。
  int get trackedCount => _dayBySong.length;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_prefsKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _dayBySong
          ..clear()
          ..addAll(decoded.map((k, v) => MapEntry(k, (v as num).toInt())));
      } catch (_) {
        // 数据损坏时忽略，从空记录开始。
        _dayBySong.clear();
      }
    }
    _initialized = true;
  }

  /// 仍在冷却窗口内的歌曲 id 集合。
  Set<String> coolingDownIds({required DateTime now}) {
    if (_dayBySong.isEmpty) return const {};
    final today = _dayIndex(now);
    final result = <String>{};
    _dayBySong.forEach((id, day) {
      final diff = today - day;
      // diff == 0：当天已推荐 → 不冷却（同日重算可复用）。
      if (diff > 0 && diff < cooldownDays) result.add(id);
    });
    return result;
  }

  /// 登记一批「已推荐」歌曲（覆盖当日记号）并裁剪过期条目。
  void markRecommended(Iterable<String> songIds, {required DateTime now}) {
    final today = _dayIndex(now);
    for (final id in songIds) {
      _dayBySong[id] = today;
    }
    _dayBySong.removeWhere((_, day) => today - day >= cooldownDays);
    _persist();
  }

  void _persist() {
    // 未初始化（单测 / 初始化失败）时仅保留内存记录。
    _prefs?.setString(_prefsKey, jsonEncode(_dayBySong)).ignore();
  }

  /// 本地日序号（自 1970-01-01 起的天数）。
  ///
  /// 用 UTC 构造同一日历日的零点，避免夏令时导致跨天差值不足 24h 而算错一天。
  static int _dayIndex(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}
