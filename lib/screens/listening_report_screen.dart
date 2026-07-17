import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../services/recommendation_service.dart';
import '../theme/app_theme.dart';

class ListeningReportScreen extends StatelessWidget {
  const ListeningReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final recService = Provider.of<RecommendationService>(context);
    final profiles = recService.profiles;

    if (profiles.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('听歌报告')),
        body: const Center(
          child: Text('还没有听歌数据，多听几首再来看吧'),
        ),
      );
    }

    final report = _buildReport(profiles);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('听歌报告'), elevation: 0),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _OverviewSection(report: report),
          const SizedBox(height: 24),
          _CompletionRateCard(report: report),
          const SizedBox(height: 24),
          if (report.timePeriodInsights.isNotEmpty) ...[
            _TimePeriodInsights(report: report),
            const SizedBox(height: 24),
          ],
          _RankingSection(title: '最常听的歌', items: report.topSongs),
          const SizedBox(height: 24),
          _RankingSection(title: '最常听的歌手', items: report.topArtists),
          const SizedBox(height: 24),
          if (report.mostSkipped.isNotEmpty) ...[
            _RankingSection(title: '最常跳过的歌', items: report.mostSkipped, isSkipList: true),
            const SizedBox(height: 24),
          ],
          if (report.singleLoopKings.isNotEmpty) ...[
            _RankingSection(title: '你的单曲循环', items: report.singleLoopKings),
            const SizedBox(height: 24),
          ],
          if (report.genreDistribution.isNotEmpty) ...[
            _GenreDistribution(genres: report.genreDistribution),
            const SizedBox(height: 24),
          ],
          if (report.newDiscoveries.isNotEmpty) ...[
            _InsightCard(title: '新发现', subtitle: '以前没怎么听，最近突然爱上的歌', items: report.newDiscoveries),
            const SizedBox(height: 24),
          ],
          if (report.oldFriends.isNotEmpty) ...[
            _InsightCard(title: '老朋友', subtitle: '一直陪伴你的歌手', items: report.oldFriends),
            const SizedBox(height: 24),
          ],
          if (report.weekendInsight != null) ...[
            _WeekendVsWeekdayCard(insight: report.weekendInsight!),
            const SizedBox(height: 24),
          ],
          if (report.energyCurve.isNotEmpty) ...[
            _EnergyCurveCard(curve: report.energyCurve),
            const SizedBox(height: 24),
          ],
          if (report.songDroughtWarning != null) ...[
            _DroughtWarningCard(warning: report.songDroughtWarning!),
            const SizedBox(height: 24),
          ],
          if (report.longestLoop != null) ...[
            _LongestLoopCard(loop: report.longestLoop!),
            const SizedBox(height: 24),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  _ReportData _buildReport(Map<String, SongProfile> profiles) {
    int totalPlays = 0;
    int totalDuration = 0;
    int totalSkips = 0;
    int totalCompleted = 0;
    final Set<String> uniqueArtists = {};
    final Map<String, int> artistPlayCounts = {};
    final Map<String, double> genrePlays = {};

    for (final p in profiles.values) {
      totalPlays += p.playCount;
      totalDuration += p.totalListenTime;
      totalSkips += p.skipCount;
      totalCompleted += p.completedPlays;
      if (p.artist != null) {
        uniqueArtists.add(p.artist!);
        artistPlayCounts[p.artist!] = (artistPlayCounts[p.artist!] ?? 0) + p.playCount;
      }
      if (p.genre != null && p.genre!.isNotEmpty) {
        final normalizedGenre = _normalizeGenre(p.genre!);
        genrePlays[normalizedGenre] = (genrePlays[normalizedGenre] ?? 0) + p.playCount;
      }
    }

    final sortedSongs = profiles.values.toList()..sort((a, b) => b.playCount.compareTo(a.playCount));
    final topSongs = sortedSongs.take(10).map((p) => _RankItem(title: p.title, subtitle: p.artist ?? '', count: p.playCount, suffix: '次')).toList();

    final sortedArtists = artistPlayCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topArtists = sortedArtists.take(10).map((e) => _RankItem(title: e.key, subtitle: '', count: e.value, suffix: '次')).toList();

    final skippable = profiles.values.where((p) => p.playCount + p.skipCount >= 3 && p.skipRate > 0.4).toList()..sort((a, b) => b.skipCount.compareTo(a.skipCount));
    final mostSkipped = skippable.take(10).map((p) => _RankItem(title: p.title, subtitle: p.artist ?? '', count: p.skipCount, suffix: '次跳过')).toList();

    final loopable = profiles.values.where((p) => p.playCount >= 5 && p.completionRate > 0.8).toList()..sort((a, b) => b.playCount.compareTo(a.playCount));
    final singleLoopKings = loopable.take(5).map((p) => _RankItem(title: p.title, subtitle: p.artist ?? '', count: p.playCount, suffix: '次完整播放')).toList();

    final totalGenrePlays = genrePlays.values.fold(0.0, (sum, v) => sum + v);
    final sortedGenres = genrePlays.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final genreDistribution = sortedGenres.take(6).map((e) {
      final percent = totalGenrePlays > 0 ? (e.value / totalGenrePlays * 100) : 0.0;
      return _GenreItem(name: e.key, percent: percent);
    }).toList();

    final completionRate = totalPlays > 0 ? totalCompleted / totalPlays : 0.0;

    return _ReportData(
      totalPlays: totalPlays,
      totalMinutes: totalDuration ~/ 60,
      uniqueSongs: profiles.length,
      uniqueArtists: uniqueArtists.length,
      completionRate: completionRate,
      totalSkips: totalSkips,
      topSongs: topSongs,
      topArtists: topArtists,
      mostSkipped: mostSkipped,
      singleLoopKings: singleLoopKings,
      genreDistribution: genreDistribution,
      timePeriodInsights: _buildTimePeriodInsights(profiles),
      newDiscoveries: _buildNewDiscoveries(profiles),
      oldFriends: _buildOldFriends(profiles),
      weekendInsight: _buildWeekendInsight(profiles),
      energyCurve: _buildEnergyCurve(profiles),
      songDroughtWarning: _buildDroughtWarning(profiles),
      longestLoop: _buildLongestLoop(profiles),
    );
  }

  /// Normalize genre names: case-insensitive + common Chinese/English/French mappings
  String _normalizeGenre(String genre) {
    final lower = genre.toLowerCase().trim();
    const mapping = {
      // 流行
      'pop': '流行',
      'cpop': '流行',
      'c-pop': '流行',
      '流行': '流行',
      '流行音乐': '流行',
      '国语流行': '流行',
      '华语流行': '流行',
      // 摇滚
      'rock': '摇滚',
      'rock & roll': '摇滚',
      'rock and roll': '摇滚',
      'rock&roll': '摇滚',
      '摇滚': '摇滚',
      '摇滚乐': '摇滚',
      // 流行摇滚
      'pop rock': '流行摇滚',
      'pop-rock': '流行摇滚',
      // 说唱
      'hip-hop': '说唱',
      'hip hop': '说唱',
      'hiphop': '说唱',
      '说唱': '说唱',
      '嘻哈': '说唱',
      'rap': '说唱',
      // R&B
      'r&b': 'R&B',
      'rnb': 'R&B',
      // 爵士
      'jazz': '爵士',
      '爵士': '爵士',
      '爵士乐': '爵士',
      // 古典
      'classical': '古典',
      '古典': '古典',
      '古典音乐': '古典',
      // 电子
      'electronic': '电子',
      'electro': '电子',
      '电子': '电子',
      '电子音乐': '电子',
      // 民谣
      'folk': '民谣',
      '民谣': '民谣',
      // 金属
      'metal': '金属',
      '金属': '金属',
      // 蓝调
      'blues': '蓝调',
      '蓝调': '蓝调',
      // 乡村
      'country': '乡村',
      '乡村': '乡村',
      // 雷鬼
      'reggae': '雷鬼',
      '雷鬼': '雷鬼',
      // 朋克
      'punk': '朋克',
      '朋克': '朋克',
      // 灵魂乐
      'soul': '灵魂乐',
      '灵魂乐': '灵魂乐',
      // 独立
      'indie': '独立',
      '独立': '独立',
      '独立音乐': '独立',
      // 另类
      'alternative': '另类',
      '另类': '另类',
      // 世界音乐
      'world': '世界音乐',
      'world music': '世界音乐',
      'asie': '世界音乐',
      'azië': '世界音乐',
      'musiques du monde': '世界音乐',
      // 原声带
      'soundtrack': '原声带',
      'ost': '原声带',
      'bandes originales de films': '原声带',
      '原声': '原声带',
      '原声带': '原声带',
      '影视原声': '原声带',
      // 其他
      'other': '其他',
      '其他': '其他',
    };
    return mapping[lower] ?? genre;
  }

  List<_TimePeriodInsight> _buildTimePeriodInsights(Map<String, SongProfile> profiles) {
    final Map<String, Map<String, int>> periodArtists = {'深夜': {}, '早晨': {}, '白天': {}, '晚上': {}};
    final Map<String, Map<String, int>> periodGenres = {'深夜': {}, '早晨': {}, '白天': {}, '晚上': {}};

    for (final p in profiles.values) {
      for (final entry in p.hourlyPlays.entries) {
        final hour = entry.key;
        final count = entry.value;
        final period = hour >= 22 || hour < 5 ? '深夜' : hour < 9 ? '早晨' : hour < 18 ? '白天' : '晚上';
        if (p.artist != null) periodArtists[period]![p.artist!] = (periodArtists[period]![p.artist!] ?? 0) + count;
        if (p.genre != null && p.genre!.isNotEmpty) {
          final ng = _normalizeGenre(p.genre!);
          periodGenres[period]![ng] = (periodGenres[period]![ng] ?? 0) + count;
        }
      }
    }

    final insights = <_TimePeriodInsight>[];
    for (final period in periodArtists.keys) {
      final artists = periodArtists[period]!;
      final genres = periodGenres[period]!;
      if (artists.isEmpty && genres.isEmpty) continue;
      String? topArtist;
      String? topGenre;
      int totalInPeriod = 0;
      if (artists.isNotEmpty) {
        final sorted = artists.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        topArtist = sorted.first.key;
        totalInPeriod = artists.values.fold(0, (s, v) => s + v);
      }
      if (genres.isNotEmpty) {
        final sorted = genres.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        topGenre = sorted.first.key;
      }
      if (totalInPeriod >= 3) {
        insights.add(_TimePeriodInsight(period: period, topArtist: topArtist, topGenre: topGenre, playCount: totalInPeriod));
      }
    }
    insights.sort((a, b) => b.playCount.compareTo(a.playCount));
    return insights;
  }

  List<String> _buildNewDiscoveries(Map<String, SongProfile> profiles) {
    // "新发现"：过去30天几乎没听过，但最近7天突然频繁播放的歌
    final now = DateTime.now();
    final recentCutoff = now.subtract(const Duration(days: 7));

    final discoveries = <_RankItem>[];
    for (final p in profiles.values) {
      if (!p.lastPlayed.isAfter(recentCutoff)) continue;
      // 判断标准：总播放不超过5次（说明以前没怎么听），但最近活跃
      // 且 playCount >= 3（最近确实在反复听）
      if (p.playCount >= 3 && p.playCount <= 8) {
        discoveries.add(_RankItem(
          title: '${p.title} - ${p.artist ?? ""}',
          subtitle: '',
          count: p.playCount,
          suffix: '次',
        ));
      }
    }
    discoveries.sort((a, b) => b.count.compareTo(a.count));
    return discoveries.take(5).map((e) => e.title).toList();
  }

  List<String> _buildOldFriends(Map<String, SongProfile> profiles) {
    final Map<String, int> artistTotalPlays = {};
    for (final p in profiles.values) {
      if (p.artist == null) continue;
      artistTotalPlays[p.artist!] = (artistTotalPlays[p.artist!] ?? 0) + p.playCount;
    }
    final friends = artistTotalPlays.entries.where((e) => e.value >= 10).toList()..sort((a, b) => b.value.compareTo(a.value));
    return friends.take(5).map((e) => e.key).toList();
  }

  _WeekendVsWeekday? _buildWeekendInsight(Map<String, SongProfile> profiles) {
    final Map<String, int> weekdayArtists = {};
    final Map<String, int> weekendArtists = {};
    int weekdayPlays = 0;
    int weekendPlays = 0;

    for (final p in profiles.values) {
      final dow = p.lastPlayed.weekday;
      final isWeekend = dow == 6 || dow == 7;
      if (isWeekend) {
        weekendPlays += p.playCount;
        if (p.artist != null) weekendArtists[p.artist!] = (weekendArtists[p.artist!] ?? 0) + p.playCount;
      } else {
        weekdayPlays += p.playCount;
        if (p.artist != null) weekdayArtists[p.artist!] = (weekdayArtists[p.artist!] ?? 0) + p.playCount;
      }
    }
    if (weekdayPlays == 0 && weekendPlays == 0) return null;

    String? topWeekday = weekdayArtists.isNotEmpty ? (weekdayArtists.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key : null;
    String? topWeekend = weekendArtists.isNotEmpty ? (weekendArtists.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key : null;

    return _WeekendVsWeekday(weekdayPlays: weekdayPlays, weekendPlays: weekendPlays, topWeekdayArtist: topWeekday, topWeekendArtist: topWeekend);
  }

  List<_EnergyCurvePoint> _buildEnergyCurve(Map<String, SongProfile> profiles) {
    final Map<String, List<int>> periodDurations = {'早晨': [], '白天': [], '晚上': [], '深夜': []};
    for (final p in profiles.values) {
      if (p.duration == null || p.duration! <= 0) continue;
      for (final entry in p.hourlyPlays.entries) {
        final hour = entry.key;
        final period = hour >= 5 && hour < 9 ? '早晨' : hour >= 9 && hour < 18 ? '白天' : hour >= 18 && hour < 22 ? '晚上' : '深夜';
        for (int i = 0; i < entry.value; i++) periodDurations[period]!.add(p.duration!);
      }
    }
    final points = <_EnergyCurvePoint>[];
    for (final period in ['早晨', '白天', '晚上', '深夜']) {
      final durations = periodDurations[period]!;
      if (durations.isEmpty) continue;
      final avg = durations.reduce((a, b) => a + b) / durations.length;
      final energy = ((360 - avg.clamp(120, 360)) / 240 * 100).clamp(0, 100);
      points.add(_EnergyCurvePoint(period: period, energy: energy.toDouble()));
    }
    return points;
  }

  _DroughtWarning? _buildDroughtWarning(Map<String, SongProfile> profiles) {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final recent = profiles.values.where((p) => p.lastPlayed.isAfter(weekAgo)).toList()..sort((a, b) => b.playCount.compareTo(a.playCount));
    if (recent.length <= 10) return null;
    final totalPlays = recent.fold(0, (sum, p) => sum + p.playCount);
    final top10Plays = recent.take(10).fold(0, (sum, p) => sum + p.playCount);
    final concentration = totalPlays > 0 ? top10Plays / totalPlays : 0.0;
    if (concentration > 0.8) return _DroughtWarning(concentration: concentration, repeatSongs: 10, totalSongs: recent.length);
    return null;
  }

  _LongestLoop? _buildLongestLoop(Map<String, SongProfile> profiles) {
    if (profiles.isEmpty) return null;
    final sorted = profiles.values.toList()..sort((a, b) => b.playCount.compareTo(a.playCount));
    final top = sorted.first;
    if (top.playCount < 5) return null;
    return _LongestLoop(title: top.title, artist: top.artist ?? '', playCount: top.playCount);
  }
}

// ─── Data Models ─────────────────────────────────────────────────────────────

class _ReportData {
  final int totalPlays, totalMinutes, uniqueSongs, uniqueArtists, totalSkips;
  final double completionRate;
  final List<_RankItem> topSongs, topArtists, mostSkipped, singleLoopKings;
  final List<_GenreItem> genreDistribution;
  final List<_TimePeriodInsight> timePeriodInsights;
  final List<String> newDiscoveries, oldFriends;
  final _WeekendVsWeekday? weekendInsight;
  final List<_EnergyCurvePoint> energyCurve;
  final _DroughtWarning? songDroughtWarning;
  final _LongestLoop? longestLoop;

  _ReportData({required this.totalPlays, required this.totalMinutes, required this.uniqueSongs, required this.uniqueArtists, required this.completionRate, required this.totalSkips, required this.topSongs, required this.topArtists, required this.mostSkipped, required this.singleLoopKings, required this.genreDistribution, required this.timePeriodInsights, required this.newDiscoveries, required this.oldFriends, this.weekendInsight, required this.energyCurve, this.songDroughtWarning, this.longestLoop});
}

class _RankItem {
  final String title, subtitle, suffix;
  final int count;
  _RankItem({required this.title, required this.subtitle, required this.count, required this.suffix});
}

class _GenreItem {
  final String name;
  final double percent;
  _GenreItem({required this.name, required this.percent});
}

class _TimePeriodInsight {
  final String period;
  final String? topArtist, topGenre;
  final int playCount;
  _TimePeriodInsight({required this.period, this.topArtist, this.topGenre, required this.playCount});
}

class _WeekendVsWeekday {
  final int weekdayPlays, weekendPlays;
  final String? topWeekdayArtist, topWeekendArtist;
  _WeekendVsWeekday({required this.weekdayPlays, required this.weekendPlays, this.topWeekdayArtist, this.topWeekendArtist});
}

class _EnergyCurvePoint {
  final String period;
  final double energy;
  _EnergyCurvePoint({required this.period, required this.energy});
}

class _DroughtWarning {
  final double concentration;
  final int repeatSongs, totalSongs;
  _DroughtWarning({required this.concentration, required this.repeatSongs, required this.totalSongs});
}

class _LongestLoop {
  final String title, artist;
  final int playCount;
  _LongestLoop({required this.title, required this.artist, required this.playCount});
}

// ─── UI Widgets ──────────────────────────────────────────────────────────────

class _OverviewSection extends StatelessWidget {
  final _ReportData report;
  const _OverviewSection({required this.report});

  @override
  Widget build(BuildContext context) {
    final hours = report.totalMinutes ~/ 60;
    final mins = report.totalMinutes % 60;
    final durationStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(value: durationStr, label: '总时长'),
          _StatItem(value: '${report.totalPlays}', label: '播放次数'),
          _StatItem(value: '${report.uniqueArtists}', label: '位歌手'),
          _StatItem(value: '${report.uniqueSongs}', label: '首歌'),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value, label;
  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
    ]);
  }
}

class _CompletionRateCard extends StatelessWidget {
  final _ReportData report;
  const _CompletionRateCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final percent = (report.completionRate * 100).toStringAsFixed(1);
    final desc = report.completionRate > 0.85 ? '你是认真听歌的人' : report.completionRate > 0.6 ? '偶尔会跳过几首' : '你比较挑剔，很多歌没听完';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('完播率', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(children: [
          Text('$percent%', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(width: 16),
          Expanded(child: Text(desc, style: TextStyle(fontSize: 14, color: Theme.of(context).textTheme.bodySmall?.color))),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: report.completionRate, minHeight: 6, backgroundColor: Colors.grey.withValues(alpha: 0.2), valueColor: AlwaysStoppedAnimation(AppTheme.appleMusicRed)),
        ),
      ]),
    );
  }
}

class _TimePeriodInsights extends StatelessWidget {
  final _ReportData report;
  const _TimePeriodInsights({required this.report});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('时段偏好', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...report.timePeriodInsights.map((insight) {
          final parts = <String>[];
          if (insight.topGenre != null) parts.add(insight.topGenre!);
          if (insight.topArtist != null) parts.add(insight.topArtist!);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              SizedBox(width: 50, child: Text(insight.period, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
              Expanded(child: Text(parts.isNotEmpty ? parts.join(' · ') : '各种音乐', style: TextStyle(fontSize: 14, color: Theme.of(context).textTheme.bodySmall?.color))),
              Text('${insight.playCount}次', style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color)),
            ]),
          );
        }),
      ]),
    );
  }
}

class _RankingSection extends StatelessWidget {
  final String title;
  final List<_RankItem> items;
  final bool isSkipList;
  const _RankingSection({required this.title, required this.items, this.isSkipList = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              SizedBox(width: 24, child: Text('${i + 1}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: i < 3 ? AppTheme.appleMusicRed : Theme.of(context).textTheme.bodySmall?.color))),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title, style: const TextStyle(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (item.subtitle.isNotEmpty) Text(item.subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              Text('${item.count} ${item.suffix}', style: TextStyle(fontSize: 13, color: isSkipList ? Colors.orange : Theme.of(context).textTheme.bodySmall?.color)),
            ]),
          );
        }),
      ]),
    );
  }
}

class _GenreDistribution extends StatelessWidget {
  final List<_GenreItem> genres;
  const _GenreDistribution({required this.genres});

  @override
  Widget build(BuildContext context) {
    final maxPercent = genres.isNotEmpty ? genres.first.percent : 1.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('流派分布', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...genres.map((genre) {
          final barWidth = maxPercent > 0 ? genre.percent / maxPercent : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(genre.name, style: const TextStyle(fontSize: 13)),
                Text('${genre.percent.toStringAsFixed(1)}%', style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
              ]),
              const SizedBox(height: 4),
              FractionallySizedBox(
                widthFactor: barWidth.clamp(0.0, 1.0),
                child: Container(height: 6, decoration: BoxDecoration(gradient: LinearGradient(colors: [AppTheme.appleMusicRed, AppTheme.appleMusicRed.withValues(alpha: 0.6)]), borderRadius: BorderRadius.circular(3))),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String title, subtitle;
  final List<String> items;
  const _InsightCard({required this.title, required this.subtitle, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color)),
        const SizedBox(height: 12),
        ...items.map((name) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [const Icon(Icons.person_outline, size: 18), const SizedBox(width: 8), Text(name, style: const TextStyle(fontSize: 14))]))),
      ]),
    );
  }
}

class _WeekendVsWeekdayCard extends StatelessWidget {
  final _WeekendVsWeekday insight;
  const _WeekendVsWeekdayCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('周末 vs 工作日', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Column(children: [
            const Text('工作日', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('${insight.weekdayPlays} 次', style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
            if (insight.topWeekdayArtist != null) ...[const SizedBox(height: 4), Text(insight.topWeekdayArtist!, style: const TextStyle(fontSize: 13), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis)],
          ])),
          Container(width: 1, height: 60, color: Colors.grey.withValues(alpha: 0.3)),
          Expanded(child: Column(children: [
            const Text('周末', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('${insight.weekendPlays} 次', style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
            if (insight.topWeekendArtist != null) ...[const SizedBox(height: 4), Text(insight.topWeekendArtist!, style: const TextStyle(fontSize: 13), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis)],
          ])),
        ]),
      ]),
    );
  }
}

class _EnergyCurveCard extends StatelessWidget {
  final List<_EnergyCurvePoint> curve;
  const _EnergyCurveCard({required this.curve});

  @override
  Widget build(BuildContext context) {
    final maxEnergy = curve.fold(0.0, (double m, p) => p.energy > m ? p.energy : m);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('能量曲线', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('短歌=高能量 长歌=低能量', style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color)),
        const SizedBox(height: 16),
        SizedBox(
          height: 100,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: curve.map((point) {
            final barHeight = maxEnergy > 0 ? (point.energy / maxEnergy) * 70 : 0.0;
            return Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('${point.energy.toInt()}', style: TextStyle(fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                height: barHeight.clamp(8.0, 70.0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppTheme.appleMusicRed.withValues(alpha: 0.4),
                      AppTheme.appleMusicRed,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 8),
              Text(point.period, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Theme.of(context).textTheme.bodySmall?.color)),
            ])));
          }).toList()),
        ),
      ]),
    );
  }
}

class _DroughtWarningCard extends StatelessWidget {
  final _DroughtWarning warning;
  const _DroughtWarningCard({required this.warning});

  @override
  Widget build(BuildContext context) {
    final percent = (warning.concentration * 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 32),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('歌荒预警', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('最近 7 天，你 $percent% 的播放集中在 ${warning.repeatSongs} 首歌上。要不要发现点新歌？', style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color)),
        ])),
      ]),
    );
  }
}

class _LongestLoopCard extends StatelessWidget {
  final _LongestLoop loop;
  const _LongestLoopCard({required this.loop});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const Icon(CupertinoIcons.repeat, size: 28),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('最强单曲循环', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${loop.title} - ${loop.artist}', style: const TextStyle(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('累计播放 ${loop.playCount} 次', style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color)),
        ])),
      ]),
    );
  }
}
