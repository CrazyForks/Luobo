import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:luobo/models/song.dart';
import 'package:luobo/providers/library_provider.dart';
import 'package:luobo/providers/player_provider.dart';
import 'package:luobo/services/subsonic_service.dart';
import 'package:luobo/services/storage_service.dart';
import 'package:luobo/services/upnp_service.dart';
import 'package:luobo/services/audio_handler.dart';
import 'package:luobo/services/jukebox_service.dart';
import 'package:luobo/services/transcoding_service.dart';
import 'package:luobo/widgets/song_tile.dart';
import '../test_helpers.dart';
import '../bootstrap.dart';

void main() {
  initializeTestEnvironment();
  group('SongTile', () {
    late SubsonicService subsonicService;
    late PlayerProvider playerProvider;

    setUp(() {
      subsonicService = SubsonicService();
      subsonicService = SubsonicService();
      playerProvider = PlayerProvider(
        subsonicService,
        StorageService(),
        FakeCastService(),
        UpnpService(),
        MuslyAudioHandler(),
        JukeboxService(),
        TranscodingService(),
      );
    });

    tearDown(() {
      playerProvider.dispose();
    });

    testWidgets('should display song information', (tester) async {
      final song = Song(
        id: '1',
        title: 'Test Song',
        artist: 'Test Artist',
        album: 'Test Album',
        duration: 180,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SubsonicService>.value(value: subsonicService),
            ChangeNotifierProvider<LibraryProvider>(
              create: (_) => LibraryProvider(subsonicService),
            ),
            ChangeNotifierProvider<PlayerProvider>.value(value: playerProvider),
          ],
          child: MaterialApp(
            home: Scaffold(body: SongTile(song: song, showArtist: true)),
          ),
        ),
      );

      expect(find.text('Test Song'), findsOneWidget);
      expect(find.text('Test Artist'), findsOneWidget);
    });

    testWidgets('should show duration when enabled', (tester) async {
      final song = Song(
        id: '1',
        title: 'Test Song',
        artist: 'Test Artist',
        duration: 180,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SubsonicService>.value(value: subsonicService),
            ChangeNotifierProvider<LibraryProvider>(
              create: (_) => LibraryProvider(subsonicService),
            ),
            ChangeNotifierProvider<PlayerProvider>.value(value: playerProvider),
          ],
          child: MaterialApp(
            home: Scaffold(body: SongTile(song: song, showDuration: true)),
          ),
        ),
      );

      expect(find.text('3:00'), findsOneWidget);
    });

    testWidgets('should show album when enabled', (tester) async {
      final song = Song(
        id: '1',
        title: 'Test Song',
        artist: 'Test Artist',
        album: 'Test Album',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SubsonicService>.value(value: subsonicService),
            ChangeNotifierProvider<LibraryProvider>(
              create: (_) => LibraryProvider(subsonicService),
            ),
            ChangeNotifierProvider<PlayerProvider>.value(value: playerProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SongTile(song: song, showArtist: true, showAlbum: true),
            ),
          ),
        ),
      );

      expect(find.textContaining('Test Artist'), findsOneWidget);
      expect(find.textContaining('Test Album'), findsOneWidget);
    });
  });
}
