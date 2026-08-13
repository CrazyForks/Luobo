import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/player_provider.dart';
import '../services/audiobook_progress_store.dart';
import '../services/subsonic_service.dart';
import '../utils/duration_format.dart';
import '../widgets/continue_listening_card.dart';
import '../widgets/load_error_view.dart';

/// 全局路由观察者：注册进 MaterialApp.navigatorObservers（main.dart），
/// 详情页 RouteAware 订阅它才能在从播放页 pop 回来时收到 didPopNext。
/// C004 修复：页面自建 RouteObserver 不注册到 Navigator 时 didPopNext 永不触发。
final RouteObserver<ModalRoute<void>> audiobookRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// 有声书章节列表页（道理鱼，页码跳转式分页）。
///
/// 设计见 docs/有声书接入技术方案.md §7.3：
/// - 每页 50 章，服务端分页（skip/take），total 来自响应 count；
/// - 页码栏固定底部：‹ 上一页 / 第 X / Y 页 / 下一页 ›，可点页码数字直跳；
/// - 有保存进度的章节行显示「已播至 mm:ss」+ 恢复图标；
/// - 正在播放章节实时高亮（Consumer of PlayerProvider）；
/// - 进入自动定位到已保存章节所在页并短暂高亮；
/// - RouteAware.didPopNext 重读进度（从播放页返回刷新）；
/// - 请求序号 token 防快速翻页竞态（P3）；
/// - skip 越界防抖回退、翻页失败 snackbar 不清空当前页。
class AudiobookDetailScreen extends StatefulWidget {
  final Audiobook book;
  final String? serverKey; // 由列表页传入；null 时自行计算

  const AudiobookDetailScreen({
    super.key,
    required this.book,
    this.serverKey,
  });

  @override
  State<AudiobookDetailScreen> createState() => _AudiobookDetailScreenState();
}

class _AudiobookDetailScreenState extends State<AudiobookDetailScreen>
    with RouteAware {
  static const int _pageSize = 50;

  List<AudiobookChapter> _chapters = [];
  int _totalPages = 0;
  int _currentPage = 0; // 0-based
  bool _isLoading = true;
  bool _isError = false;

  /// 请求序号：每次翻页递增，只接受最新 token 的响应（P3 防竞态）。
  int _requestToken = 0;

  String? _serverKey;
  final AudiobookProgressStore _store = AudiobookProgressStore.instance;
  bool _storeLoaded = false;
  AudiobookProgress? _progress; // 本书已保存的进度（用于"已播至"/恢复图标）

  /// 进入页面时短暂高亮的章节 order（~1.5s 淡出）。
  int? _highlightOrder;
  bool _highlightVisible = false;

  /// 已保存章节所在页（进入时定位用），0-based。
  int? _initialTargetPage;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// C001 修复：必须先 await serverKey 初始化（加载进度），再加载首页——
  /// 否则 _loadFirstPage 读 _progress 时必为 null，定位到保存章节所在页
  /// 的功能 100% 失效。
  Future<void> _init() async {
    await _initServerKey();
    await _loadFirstPage();
  }

  Future<void> _initServerKey() async {
    if (widget.serverKey != null) {
      _serverKey = widget.serverKey;
      await _loadProgress();
      return;
    }
    final subsonicService =
        Provider.of<SubsonicService>(context, listen: false);
    final config = subsonicService.config;
    if (config != null) {
      _serverKey = AudiobookProgressStore.computeServerKey(
        serverUrl: config.serverUrl,
        localUrl: config.localUrl,
        username: config.username,
      );
      await _loadProgress();
    }
  }

  Future<void> _loadProgress() async {
    final serverKey = _serverKey;
    if (serverKey == null) return;
    await _store.ensureLoaded(serverKey);
    _storeLoaded = true;
    if (mounted) {
      setState(() {
        _progress = _store.load(serverKey, widget.book.id);
      });
    }
  }

  Future<void> _loadFirstPage() async {
    // 复审 P2：_init 在 await _initServerKey 之后才调 _loadFirstPage，间隙中
    // 用户可能已 pop 页面 → setState 前必须检查 mounted（与 _loadProgress 一致）。
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _isError = false;
    });

    // 若已有保存进度 → 直接定位到保存章节所在页（§9.3）。
    final savedOrder = _progress?.chapterOrder;
    if (savedOrder != null && savedOrder > 0) {
      final targetPage = (savedOrder - 1) ~/ _pageSize;
      _currentPage = targetPage;
      _initialTargetPage = targetPage;
    }

    await _fetchPage(_currentPage, highlightOrder: savedOrder);
  }

  /// 拉取第 [page] 页（0-based）。带请求序号防竞态。
  ///
  /// 返回 true 表示成功展示该页；false 表示过期响应/失败/回退后仍未成功
  /// （调用方（如 _resumePlayback）据此不继续执行依赖新页内容的后置逻辑）。
  Future<bool> _fetchPage(int page, {int? highlightOrder}) async {
    final token = ++_requestToken;
    setState(() {
      _isLoading = true;
      _isError = false;
    });

    try {
      final subsonicService =
          Provider.of<SubsonicService>(context, listen: false);
      final result = await subsonicService.getAudiobookChapters(
        widget.book.id,
        skip: page * _pageSize,
        take: _pageSize,
      );
      if (!mounted || token != _requestToken) return false; // 过期响应丢弃

      // Bug1 修复：episodes 响应的 count 是**当页返回条数**（实测返回 2 章 →
      // count:2），不是总章节数；总章节数在列表项 episodeCount（实测 120 章）。
      // totalPages 必须用 episodeCount 计算，否则 100+ 章永远只有 1 页。
      final total = widget.book.episodeCount > 0
          ? widget.book.episodeCount
          : result.total;
      final totalPages = total <= 0
          ? (page + 1)
          : (total + _pageSize - 1) ~/ _pageSize;

      // skip 越界（total 变化）→ 防抖回退到合法页。
      // 复审 P3：仅按页码判断会在两种场景漏判——
      // ① episodeCount 缺失（total=当页条数 → totalPages=1）时，保存进度在
      //    page>0 会被误判越界回退到第 0 页（该页本有数据）；此处加
      //    chapters.isEmpty 守卫，非空响应不误回退；
      // ② episodeCount 过期大于真实章数时末页返回 0 章 → 空响应也回退到合法页。
      if (page > 0 &&
          ((total > 0 && page >= totalPages) || result.chapters.isEmpty)) {
        final fallback = totalPages > 1 ? totalPages - 1 : 0;
        return _fetchPage(fallback, highlightOrder: highlightOrder);
      }

      setState(() {
        _chapters = result.chapters;
        _totalPages = totalPages;
        _currentPage = page;
        _isLoading = false;
      });

      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }

      if (highlightOrder != null) {
        _triggerHighlight(highlightOrder);
      }
      return true;
    } catch (e) {
      if (!mounted || token != _requestToken) return false;
      setState(() {
        _isError = true;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.failedToLoadChapters)),
      );
      return false;
    }
  }

  void _triggerHighlight(int order) {
    // 目标行可能不在当前页（例如进度被自愈到其他章节）→ 只高亮当前页内的。
    if (!_chapters.any((c) => c.order == order)) return;
    setState(() {
      _highlightOrder = order;
      _highlightVisible = true;
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _highlightVisible = false);
      }
    });
  }

  Future<void> _goToPage(int page) async {
    if (page < 0 || page >= _totalPages || page == _currentPage) return;
    await _fetchPage(page);
  }

  Future<void> _goPrevPage() => _goToPage(_currentPage - 1);
  Future<void> _goNextPage() => _goToPage(_currentPage + 1);

  /// 页码数字直跳（弹输入对话框）。
  Future<void> _jumpToPageDialog() async {
    final controller = TextEditingController(
      text: (_currentPage + 1).toString(),
    );
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.pageOf(
          _currentPage + 1,
          _totalPages,
        )),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '1 - $_totalPages',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text)),
            child: Text(AppLocalizations.of(context)!.ok),
          ),
        ],
      ),
    );
    if (value != null && value >= 1 && value <= _totalPages) {
      await _goToPage(value - 1);
    }
  }

  /// 点击章节：从 0 播；点击恢复图标：从保存进度续播。
  Future<void> _playChapter(AudiobookChapter chapter,
      {AudiobookProgress? progress}) async {
    final index = _chapters.indexWhere((c) => c.id == chapter.id);
    if (index < 0) return;
    final playerProvider =
        Provider.of<PlayerProvider>(context, listen: false);
    // C006 修复：全量章节拉取失败时 playAudiobookChapter 返回 false，
    // 弹 snackbar 提示（不清当前播放状态）。
    final ok = await playerProvider.playAudiobookChapter(
      widget.book,
      _chapters,
      index,
      resumePositionMs:
          (progress != null && !progress.completed) ? progress.positionMs : null,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context)!.failedToLoadChapters),
        ),
      );
    }
  }

  // ── RouteAware：从播放页返回时重读进度（§7.3 onResume）──────────────
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      audiobookRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    // 播放页 pop 回来 → 重读进度（"已播至"防过期）。
    if (_storeLoaded) {
      final serverKey = _serverKey;
      if (serverKey != null && mounted) {
        setState(() {
          _progress = _store.load(serverKey, widget.book.id);
        });
      }
    }
  }

  @override
  void dispose() {
    audiobookRouteObserver.unsubscribe(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.book.title),
            if (widget.book.narrator != null &&
                widget.book.narrator!.isNotEmpty)
              Text(
                widget.book.narrator!,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Bug2：书顶部展示本书上次听到哪里（固定，不随列表滚动）。
          if (_progress != null && !_progress!.completed)
            _buildContinueBanner(isDark, l10n),
          Expanded(child: _buildBody(isDark, l10n)),
          _buildPaginationBar(isDark, l10n),
        ],
      ),
    );
  }

  /// 本书「继续收听」卡：显示上次听到的章节+进度，点击直接续播。
  Widget _buildContinueBanner(bool isDark, AppLocalizations l10n) {
    final progress = _progress!;
    // 复审 P2：positionMs==0 且未 completed（暂停后立刻退后台会写入 0）时
    // formatDurationMs(0) 返回空串，副标题会显示「已播至 」（空时长）。
    // 与列表页 banner 的 positionMs>0 守卫保持一致——此时只显示章节序。
    final hasPosition = progress.positionMs > 0;

    return ContinueListeningCard(
      title: l10n.continueListening,
      subtitle: hasPosition
          ? '${l10n.chapterX(progress.chapterOrder)} · '
              '${l10n.playedTo(formatDurationMs(progress.positionMs))}'
          : l10n.chapterX(progress.chapterOrder),
      onTap: () => _resumePlayback(progress),
    );
  }

  /// 点击「继续收听」：定位到保存章节所在页，若本章已在当前页则直接续播。
  Future<void> _resumePlayback(AudiobookProgress progress) async {
    final targetPage = (progress.chapterOrder - 1) ~/ _pageSize;
    if (targetPage != _currentPage) {
      // 目标章节在别的页：先翻页，翻页成功后再续播该章节。
      // 复审 P3：不提前改 _currentPage——_fetchPage 失败时页码栏与列表保持
      // 一致（仍为旧页），且不会在旧 _chapters 上误定位。
      final ok = await _fetchPage(targetPage,
          highlightOrder: progress.chapterOrder);
      if (!ok || !mounted) return;
      final index =
          _chapters.indexWhere((c) => c.order == progress.chapterOrder);
      if (index >= 0) {
        await _playChapter(_chapters[index], progress: progress);
      }
      return;
    }
    // 已在保存章节所在页：找到章节行并续播。
    final index =
        _chapters.indexWhere((c) => c.order == progress.chapterOrder);
    if (index >= 0) {
      await _playChapter(_chapters[index], progress: progress);
    }
  }

  Widget _buildBody(bool isDark, AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isError && _chapters.isEmpty) {
      return LoadErrorView(
        title: l10n.failedToLoadChapters,
        retryLabel: l10n.retry,
        onRetry: () {
          _currentPage = _initialTargetPage ?? 0;
          _fetchPage(_currentPage, highlightOrder: _progress?.chapterOrder);
        },
      );
    }

    if (_chapters.isEmpty) {
      return Center(
        child: Text(
          l10n.noSongsFound,
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final isCurrentBook = player.isPlayingAudiobook &&
            player.currentAudiobook?.id == widget.book.id;
        final currentOrder = isCurrentBook ? player.audiobookChapterOrder : null;

        return ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _chapters.length,
          itemBuilder: (context, index) {
            final chapter = _chapters[index];
            return _buildChapterTile(
              isDark,
              chapter,
              isCurrent: currentOrder == chapter.order,
              progress: _progress?.chapterOrder == chapter.order
                  ? _progress
                  : null,
              highlight: _highlightVisible && _highlightOrder == chapter.order,
            );
          },
        );
      },
    );
  }

  Widget _buildChapterTile(
    bool isDark,
    AudiobookChapter chapter, {
    required bool isCurrent,
    required AudiobookProgress? progress,
    required bool highlight,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final accentColor = Theme.of(context).colorScheme.primary;

    // 已完成：显示"已听完"；有进度：显示"已播至 mm:ss"。
    String? subtitle;
    if (progress?.completed == true) {
      subtitle = l10n.finished;
    } else if (progress != null && progress.positionMs > 0) {
      subtitle = l10n.playedTo(_formatMs(progress.positionMs));
    }
    if (chapter.durationSeconds != null && chapter.durationSeconds! > 0) {
      final durationText = _formatSeconds(chapter.durationSeconds!);
      subtitle = subtitle == null ? durationText : '$subtitle · $durationText';
    }

    // Apple §5.2：当前播放项用较亮/半粗标题低调标识，不用红色/等化器/波形
    // 图标制造噪声；序号列保持一致，仅当前项着色+加粗。
    final titleColor = isCurrent
        ? accentColor
        : (isDark ? Colors.white : Colors.black);
    final orderColor = isCurrent
        ? accentColor
        : (isDark ? Colors.white54 : Colors.black45);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: highlight
          ? accentColor.withValues(alpha: 0.12)
          : Colors.transparent,
      child: ListTile(
        leading: SizedBox(
          width: 32,
          child: Center(
            child: Text(
              '${chapter.order}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                color: orderColor,
              ),
            ),
          ),
        ),
        title: Text(
          chapter.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16,
            color: titleColor,
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        subtitle: subtitle != null
            ? Text(subtitle, style: TextStyle(fontSize: 13))
            : null,
        trailing: progress != null && !progress.completed && !isCurrent
            ? IconButton(
                icon: Icon(CupertinoIcons.play_fill, color: accentColor),
                tooltip: l10n.continueListening,
                onPressed: () => _playChapter(chapter, progress: progress),
              )
            : null,
        onTap: () => _playChapter(chapter),
      ),
    );
  }

  /// 页码栏：固定底部，不随列表滚动（§7.3）。
  Widget _buildPaginationBar(bool isDark, AppLocalizations l10n) {
    if (_totalPages <= 0) return const SizedBox.shrink();

    final canPrev = _currentPage > 0;
    final canNext = _currentPage < _totalPages - 1;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(CupertinoIcons.chevron_left),
                onPressed: canPrev && !_isLoading ? _goPrevPage : null,
                tooltip: l10n.previousPage,
              ),
              Expanded(
                child: InkWell(
                  onTap: _totalPages > 1 ? _jumpToPageDialog : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      l10n.pageOf(_currentPage + 1, _totalPages),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.chevron_right),
                onPressed: canNext && !_isLoading ? _goNextPage : null,
                tooltip: l10n.nextPage,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 时长格式化统一走共享工具（R002 修复，移除第 4/5 份副本）。
  String _formatMs(int ms) => formatDurationMs(ms);
  String _formatSeconds(int seconds) => formatDuration(seconds);
}
