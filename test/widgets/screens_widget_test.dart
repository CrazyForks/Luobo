import 'package:flutter_test/flutter_test.dart';
import 'package:luobo/screens/all_songs_screen.dart';
import 'package:luobo/screens/library_screen.dart';
import 'package:luobo/screens/playlists_screen.dart';
import 'package:luobo/screens/settings_screen.dart';

import '../test_helpers.dart';
import '../bootstrap.dart';

void main() {
  initializeTestEnvironment();
  group('Screen Widget Tests', () {
    testWidgets('LibraryScreen builds without exception', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestApp(child: const LibraryScreen()));
      await tester.pump();
      expect(find.byType(LibraryScreen), findsOneWidget);
    });

    testWidgets('AllSongsScreen builds without exception', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestApp(child: const AllSongsScreen()));
      await tester.pump();
      expect(find.byType(AllSongsScreen), findsOneWidget);
    });

    testWidgets('PlaylistsScreen builds without exception', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestApp(child: const PlaylistsScreen()));
      await tester.pump();
      expect(find.byType(PlaylistsScreen), findsOneWidget);
    });

    testWidgets('SettingsScreen builds without exception', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestApp(child: const SettingsScreen()));
      await tester.pump();
      // SettingsPlaybackTab 的 initState 会惰性创建 PlayerProvider，
      // 其 _restoreQueueState 埋点触发 DiagnosticsService 200ms 节流定时器；
      // 推进假时钟让其走完，避免测试结束时残留 pending timer。
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });
}
