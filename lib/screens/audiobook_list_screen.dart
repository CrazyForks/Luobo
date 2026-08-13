import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../services/audiobook_progress_store.dart';
import '../services/subsonic_service.dart';
import '../utils/duration_format.dart';
import '../widgets/continue_listening_card.dart';
import '../widgets/load_error_view.dart';
import 'audiobook_detail_screen.dart';

/// 有声书列表页（道理鱼）。
///
/// 设计见 docs/有声书接入技术方案.md §7.2：AppBar「有声书」+ 下拉刷新 +
/// 错误态/空态（复用 RadioScreen 三态模式）；顶部「继续收听」banner
/// （recent(limit:1)，排除已听完的书）。封面占位图兜底（API 无封面字段）。
class AudiobookListScreen extends StatefulWidget {
  const AudiobookListScreen({super.key});

  @override
  State<AudiobookListScreen> createState() => _AudiobookListScreenState();
}

class _AudiobookListScreenState extends State<AudiobookListScreen> {
  List<Audiobook> _books = [];
  bool _isLoading = true;
  String? _error;
  AudiobookProgress? _recent;
  String? _serverKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final subsonicService =
          Provider.of<SubsonicService>(context, listen: false);
      final books = await subsonicService.getAudiobooks();
      _recent = await _loadRecentProgress(subsonicService);
      if (mounted) {
        setState(() {
          _books = books;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<AudiobookProgress?> _loadRecentProgress(
    SubsonicService subsonicService,
  ) async {
    final config = subsonicService.config;
    if (config == null) return null;
    final serverKey = AudiobookProgressStore.computeServerKey(
      serverUrl: config.serverUrl,
      localUrl: config.localUrl,
      username: config.username,
    );
    _serverKey = serverKey;
    // 共享单例：与播放器/详情页共用同一内存缓存（M001）。
    final store = AudiobookProgressStore.instance;
    await store.ensureLoaded(serverKey);
    final recent = store.recent(serverKey, limit: 1);
    return recent.isEmpty ? null : recent.first;
  }

  void _openBook(Audiobook book) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AudiobookDetailScreen(
          book: book,
          serverKey: _serverKey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.audiobooks)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(isDark, l10n),
      ),
    );
  }

  Widget _buildBody(bool isDark, AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return LoadErrorView(
        title: l10n.failedToLoadAudiobooks,
        message: _error,
        retryLabel: l10n.retry,
        onRetry: _load,
      );
    }

    if (_books.isEmpty) {
      return EmptyStateView(
        icon: CupertinoIcons.book,
        message: l10n.noSongsFound,
        isDark: isDark,
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (_recent != null) _buildContinueBanner(isDark, l10n),
        const SizedBox(height: 8),
        ..._books.map((book) => _buildBookTile(isDark, book)),
        const SizedBox(height: 32),
      ],
    );
  }

  /// 「继续收听」banner：点击进入详情页并定位到进度章节（不直接开播，
  /// 避免误触打断当前播放，符合大厂惯例）。
  Widget _buildContinueBanner(bool isDark, AppLocalizations l10n) {
    final progress = _recent!;
    final book = _books
        .where((b) => b.id == progress.audiobookId)
        .firstOrNull;
    if (book == null) return const SizedBox.shrink();

    // 副标题定位到具体章节+分钟（"第 X 章 · 已播至 mm:ss"），不能只显示系列名。
    final detail = progress.completed
        ? l10n.finished
        : (progress.positionMs > 0
            ? '${l10n.chapterX(progress.chapterOrder)} · '
                '${l10n.playedTo(formatDurationMs(progress.positionMs))}'
            : null);

    return ContinueListeningCard(
      title: l10n.continueListening,
      subtitle: book.title,
      detail: detail,
      onTap: () => _openBook(book),
    );
  }

  Widget _buildBookTile(bool isDark, Audiobook book) {
    final l10n = AppLocalizations.of(context)!;
    final subtitle = [
      if (book.narrator != null && book.narrator!.isNotEmpty) book.narrator!,
      l10n.chapterCount(book.episodeCount),
      if (formatDuration(book.totalDurationSeconds).isNotEmpty)
        formatDuration(book.totalDurationSeconds),
    ].join(' · ');

    return ListTile(
      leading: _CoverPlaceholder(
        isDark: isDark,
        radius: 8,
        child: Icon(
          CupertinoIcons.book_fill,
          size: 24,
          color: isDark ? Colors.white70 : Colors.black54,
        ),
      ),
      title: Text(
        book.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
      onTap: () => _openBook(book),
    );
  }
}

/// 有声书封面占位图（API 无封面字段，§3）。
class _CoverPlaceholder extends StatelessWidget {
  final bool isDark;
  final double radius;
  final Widget child;

  const _CoverPlaceholder({
    required this.isDark,
    required this.radius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Apple 风格：列表封面约 64-72dp、圆角约 8dp（§5.2 队列项细节）。
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF3A3A3C), const Color(0xFF1C1C1E)]
              : [const Color(0xFFE5E5EA), const Color(0xFFD1D1D6)],
        ),
      ),
      child: Center(child: child),
    );
  }
}
