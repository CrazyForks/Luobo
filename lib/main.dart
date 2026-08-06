import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:safe_device/safe_device.dart';

import 'l10n/app_localizations.dart';
import 'models/server_config.dart';
import 'services/services.dart';
import 'services/audio_handler.dart';
import 'services/transcoding_service.dart';
import 'services/local_music_service.dart';
import 'services/analytics_service.dart';
import 'services/diagnostics/diagnostics.dart';
import 'services/favorite_playlists_service.dart';
import 'services/cover_cache_cleaner.dart';
import 'services/song_knowledge_cache.dart';
import 'widgets/glass_surface.dart';
import 'widgets/privacy_policy_dialog.dart';
import 'providers/providers.dart';
import 'screens/screens.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'theme/theme.dart';
import 'utils/image_cache.dart';

// Global instance for analytics (to be shown after auth)

/// 运行时上报的应用版本，写入诊断导出 meta.json；
/// 与 pubspec.yaml `version` 保持一致，发版时同步更新。
const String kAppVersion = '1.1.9+4';

/// Shows the privacy policy dialog on first launch
Future<void> _showPrivacyPolicyIfNeeded() async {
  if (await PrivacyPolicyDialog.shouldShow()) {
    // Small delay to ensure UI is fully loaded
    await Future.delayed(const Duration(milliseconds: 300));
    if (navigatorKey.currentContext != null) {
      final result = await showDialog<bool>(
        context: navigatorKey.currentContext!,
        builder: (context) => const PrivacyPolicyDialog(),
        barrierDismissible: false,
      );

      // If user declined, mark as accepted anyway to not show again
      // but we could handle this differently if needed
      if (result == false) {
        await PrivacyPolicyDialog.markAccepted();
      }
    }
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Checks if the app is running on an emulator/simulator
Future<bool> _isRunningOnEmulator() async {
  if (kDebugMode) return false;
  if (kIsWeb) return false;
  if (!Platform.isAndroid && !Platform.isIOS) return false;

  return !(await SafeDevice.isRealDevice);
}

/// Widget shown when app is running on emulator
class _EmulatorWarningScreen extends StatelessWidget {
  const _EmulatorWarningScreen();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context)!;
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.block_rounded,
                      size: 80,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 32),
                    Text(
                      l10n.emulatorDetected,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.emulatorNotAllowed,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
                    FilledButton.icon(
                      onPressed: () {
                        // Exit the app
                        exit(0);
                      },
                      icon: const Icon(Icons.exit_to_app),
                      label: Text(l10n.exitApp),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(200, 50),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

void main() async {
  final startupSw = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();

  // ── 诊断系统：尽早初始化（runApp 前），保证启动早期日志不丢 ──
  final diag = DiagnosticsService.instance;
  diag.setAppVersion(kAppVersion); // 导出 meta 携带版本，否则恒为 unknown
  unawaited(diag.init());
  GlobalErrorHandler.install();
  GlobalErrorHandler.contextProvider = () => navigatorKey.currentContext;
  MetricsCollector.instance.start();
  MetricsCollector.milestone(
      'engineInitialized', startupSw.elapsedMilliseconds);

  // 进程退出前 flush 诊断缓冲（崩溃/被杀场景由 GlobalErrorHandler 兜底）
  AppLifecycleListener(onDetach: () => unawaited(diag.disposeAsync()));

  final isEmulator = await _isRunningOnEmulator();
  if (isEmulator) {
    runApp(const _EmulatorWarningScreen());
    return;
  }

  JustAudioMediaKit.ensureInitialized(linux: true, windows: false);

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions();
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  ImageCacheConfig.configure();

  // 封面磁盘缓存字节守护：启动时清理超限的最旧封面（512MB 阈值，见方案 P5）。
  unawaited(CoverCacheCleaner().prune());

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final storageService = StorageService();
  final subsonicService = SubsonicService(storageService: storageService);
  final offlineService = OfflineService();
  final recommendationService = RecommendationService();
  final localMusicService = LocalMusicService();
  final castService = CastService();
  final localeService = LocaleService();
  final upnpService = UpnpService();
  final jukeboxService = JukeboxService();
  final themeService = ThemeService();
  final nowPlayingThemeService = NowPlayingThemeService();
  MetricsCollector.milestone('servicesCreated', startupSw.elapsedMilliseconds);

  BpmAnalyzerService().initialize().catchError((e) {
    debugPrint('Failed to initialize BPM analyzer: $e');
  });
  offlineService.initialize().catchError((e) {
    debugPrint('Failed to initialize offline service: $e');
  });
  recommendationService.initialize().catchError((e) {
    debugPrint('Failed to initialize recommendation service: $e');
  });

  // 新首页推荐编排服务（P3 图谱接入）：注入知识库缓存，行为监听自动接线。
  final songKnowledgeCache = SongKnowledgeCache();
  songKnowledgeCache.initialize().catchError((e) {
    debugPrint('Failed to initialize song knowledge cache: $e');
  });
  final homeRecommendationService = HomeRecommendationService(
    behavior: recommendationService,
    knowledgeCache: songKnowledgeCache,
  );

  // 播放来源追踪：最近播放的歌单/收藏列表（首页「最近播放」混合区）。
  final playbackContextTracker = PlaybackContextTracker();
  playbackContextTracker.initialize().catchError((e) {
    debugPrint('Failed to initialize playback context tracker: $e');
  });
  localMusicService.initialize().catchError((e) {
    debugPrint('Failed to initialize local music service: $e');
  });
  localeService.loadSavedLocale().catchError((e) {
    debugPrint('Failed to load saved locale: $e');
  });
  await themeService.initialize().catchError((e) {
    debugPrint('Failed to initialize theme service: $e');
  });
  jukeboxService.initialize().catchError((e) {
    debugPrint('Failed to initialize jukebox service: $e');
  });
  nowPlayingThemeService.initialize().catchError((e) {
    debugPrint('Failed to initialize now playing theme service: $e');
  });

  // Initialize favorite playlists service
  FavoritePlaylistsService().initialize().catchError((e) {
    debugPrint('Failed to initialize favorite playlists service: $e');
  });

  // Initialize analytics service (privacy-first, anonymous)
  final analyticsService = AnalyticsService();
  analyticsService.initialize().catchError((e) {
    debugPrint('Failed to initialize analytics: $e');
  });

  // Analytics service is initialized and used via AnalyticsNavigatorObserver

  try {
    await PlayerUiSettingsService().initialize();
  } catch (e) {
    debugPrint('Failed to initialize player UI settings: $e');
  }

  // Initialise the audio service BEFORE runApp so the background audio engine
  // is ready and fully decoupled from the Flutter widget lifecycle on iOS.
  final audioHandler = await initAudioService();
  MetricsCollector.milestone('audioEngineReady', startupSw.elapsedMilliseconds);

  // Create TranscodingService instance to share across providers
  final transcodingService = TranscodingService();

  final Widget appWithProviders = MultiProvider(
    providers: [
      Provider<StorageService>.value(value: storageService),
      Provider<SubsonicService>.value(value: subsonicService),
      ChangeNotifierProvider<RecommendationService>.value(
        value: recommendationService,
      ),
      ChangeNotifierProvider<HomeRecommendationService>.value(
        value: homeRecommendationService,
      ),
      ChangeNotifierProvider<PlaybackContextTracker>.value(
        value: playbackContextTracker,
      ),
      ChangeNotifierProvider<TranscodingService>.value(
        value: transcodingService,
      ),
      ChangeNotifierProvider<LocalMusicService>.value(value: localMusicService),
      ChangeNotifierProvider(
        create: (_) => AuthProvider(subsonicService, storageService),
      ),
      ChangeNotifierProvider<CastService>.value(value: castService),
      ChangeNotifierProvider<LocaleService>.value(value: localeService),
      ChangeNotifierProvider<ThemeService>.value(value: themeService),
      ChangeNotifierProvider<NowPlayingThemeService>.value(
        value: nowPlayingThemeService,
      ),
      ChangeNotifierProvider<UpnpService>.value(value: upnpService),
      ChangeNotifierProvider<JukeboxService>.value(value: jukeboxService),
      ChangeNotifierProvider(
        create: (_) => PlayerProvider(
          subsonicService,
          storageService,
          castService,
          upnpService,
          audioHandler,
          jukeboxService,
          transcodingService,
        ),
      ),
      ChangeNotifierProvider(
        create: (_) =>
            LibraryProvider(subsonicService)
              ..recommendationService = recommendationService,
      ),
    ],
    child: const MuslyApp(),
  );

  // 首帧渲染完成后记录冷启动总时长
  WidgetsBinding.instance.addPostFrameCallback((_) {
    MetricsCollector.milestone('firstFrame', startupSw.elapsedMilliseconds);
    Log.i('App', '冷启动完成: ${startupSw.elapsedMilliseconds}ms');
  });

  // guarded zone：捕获未处理异步异常 + 拦截 print 兜底散落日志
  GlobalErrorHandler.runGuarded(() => runApp(appWithProviders));
}

class MuslyApp extends StatelessWidget {
  const MuslyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final localeService = Provider.of<LocaleService>(context);
    final themeService = Provider.of<ThemeService>(context);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final accent = themeService.accentColor.color;

        final ThemeData light;
        final ThemeData dark;

        if (lightDynamic != null && darkDynamic != null) {
          // Override dynamic color scheme with user-selected accent color
          final harmonisedLight = lightDynamic.harmonized().copyWith(
                primary: accent,
                secondary: accent.withAlpha(200),
              );
          final harmonisedDark = darkDynamic.harmonized().copyWith(
                primary: accent,
                secondary: accent.withAlpha(200),
              );
          light = AppTheme.lightThemeFromScheme(harmonisedLight);
          dark = AppTheme.darkThemeFromScheme(harmonisedDark);
        } else {
          light = AppTheme.lightThemeWith(accent);
          dark = AppTheme.darkThemeWith(accent);
        }

        return MaterialApp(
          title: 'Musly',
          debugShowCheckedModeBanner: false,
          theme: light,
          darkTheme: dark,
          themeMode: themeService.themeMode,
          navigatorKey: navigatorKey,
          locale: localeService.currentLocale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AuthWrapper(),
          navigatorObservers: [
            AnalyticsNavigatorObserver(),
            DiagnosticsRouteObserver(),
          ],
        );
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    switch (authProvider.state) {
      case AuthState.unknown:
        return Scaffold(
          body: Center(child: const CircularProgressIndicator()),
        );
      case AuthState.authenticated:
        // Show privacy policy first if needed
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await _showPrivacyPolicyIfNeeded();
        });
        return const MainScreen();
      case AuthState.offlineMode:
        return const MainScreen(isOfflineMode: true);
      case AuthState.serverUnreachable:
        return _ServerUnreachableScreen(
          hasOfflineContent: authProvider.hasOfflineContent,
          onEnterOfflineMode: () => authProvider.enterOfflineMode(),
          onDisconnect: () => authProvider.disconnect(),
        );
      case AuthState.authenticating:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case AuthState.unauthenticated:
      case AuthState.error:
        return const LoginScreen();
    }
  }
}

class _ServerUnreachableScreen extends StatelessWidget {
  final bool hasOfflineContent;
  final VoidCallback onEnterOfflineMode;
  final VoidCallback onDisconnect;

  const _ServerUnreachableScreen({
    required this.hasOfflineContent,
    required this.onEnterOfflineMode,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 72, color: Colors.grey),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context)!.serverUnreachableTitle,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.serverUnreachableSubtitle,
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => authProvider.retryConnection(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(AppLocalizations.of(context)!.retry),
                ),
              ),
              const SizedBox(height: 12),
              _buildSwitchProfileButton(context),
              const SizedBox(height: 12),
              if (hasOfflineContent) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onEnterOfflineMode,
                    icon: const Icon(Icons.offline_pin_rounded),
                    label: Text(AppLocalizations.of(context)!.openOfflineMode),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onDisconnect,
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(AppLocalizations.of(context)!.disconnect),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchProfileButton(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;

    return FutureBuilder<List<ServerConfig>>(
      future: authProvider.getSavedProfiles(),
      builder: (context, snapshot) {
        final profiles = snapshot.data ?? [];
        if (profiles.isEmpty) return const SizedBox.shrink();

        final currentConfig = authProvider.config;
        final otherProfiles = profiles
            .where(
              (p) =>
                  p.serverUrl != currentConfig?.serverUrl ||
                  p.username != currentConfig?.username,
            )
            .toList();

        if (otherProfiles.isEmpty) return const SizedBox.shrink();

        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showSwitchProfileDialog(context, otherProfiles),
            icon: const Icon(Icons.swap_horiz_rounded),
            label: Text(l10n.switchServer),
          ),
        );
      },
    );
  }

  void _showSwitchProfileDialog(
      BuildContext context, List<ServerConfig> profiles) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;

    showGlassBottomSheet(
      context: context,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).brightness == Brightness.dark
              ? AppTheme.darkSurface
              : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).brightness == Brightness.dark
                      ? AppTheme.darkDivider
                      : AppTheme.lightDivider,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.switchServer,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ...profiles.map((profile) {
                final label = profile.name?.isNotEmpty == true
                    ? profile.name!
                    : '${profile.username}@${Uri.tryParse(profile.serverUrl)?.host ?? profile.serverUrl}';
                return ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(label),
                  subtitle: Text(profile.serverUrl,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await authProvider.switchProfile(profile);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
