import 'package:flutter_test/flutter_test.dart';
import 'package:luobo/models/server_config.dart';
import 'package:luobo/services/storage_service.dart';
import 'package:luobo/services/subsonic_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SubsonicService', () {
    late SubsonicService service;

    setUp(() {
      service = SubsonicService();
    });

    test('should initialize without configuration', () {
      expect(service.isConfigured, false);
      expect(service.config, isNull);
    });

    test('should configure with ServerConfig', () {
      final config = ServerConfig(
        serverUrl: 'https://demo.navidrome.org',
        username: 'demo',
        password: 'demo',
      );

      service.configure(config);

      expect(service.isConfigured, true);
      expect(service.config, isNotNull);
      expect(service.config?.serverUrl, config.serverUrl);
    });

    test('should build cover art URL', () {
      final config = ServerConfig(
        serverUrl: 'https://demo.navidrome.org',
        username: 'demo',
        password: 'demo',
      );

      service.configure(config);

      final url = service.getCoverArtUrl('art123', size: 300);

      expect(url, contains('https://demo.navidrome.org/rest/getCoverArt'));
      expect(url, contains('id=art123'));
      expect(url, contains('size=300'));
    });

    test('should return empty URL when coverArt is null', () {
      final config = ServerConfig(
        serverUrl: 'https://demo.navidrome.org',
        username: 'demo',
        password: 'demo',
      );

      service.configure(config);

      final url = service.getCoverArtUrl(null);
      expect(url, '');
    });

    test('should build stream URL', () {
      final config = ServerConfig(
        serverUrl: 'https://demo.navidrome.org',
        username: 'demo',
        password: 'demo',
      );

      service.configure(config);

      final url = service.getStreamUrl('song123');

      expect(url, contains('https://demo.navidrome.org/rest/stream'));
      expect(url, contains('id=song123'));
    });

    test('should include maxBitRate in stream URL when specified', () {
      final config = ServerConfig(
        serverUrl: 'https://demo.navidrome.org',
        username: 'demo',
        password: 'demo',
      );

      service.configure(config);

      final url = service.getStreamUrl('song123', maxBitRate: 320);

      expect(url, contains('maxBitRate=320'));
    });

    test('should throw when not configured', () {
      expect(() => service.getCoverArtUrl('art123'), returnsNormally);
      expect(() => service.getStreamUrl('song123'), throwsException);
    });

    group('resolveActiveUrl', () {
      // Port 1 on loopback refuses connections instantly on every platform, so
      // the LAN probe fails fast without hitting a real server.
      const probeUrl = 'http://127.0.0.1:1';
      const remoteUrl = 'https://demo.navidrome.org';

      test('persists last active URL when no local URL configured', () async {
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        final svc = SubsonicService(storageService: storage);
        svc.configure(ServerConfig(
          serverUrl: remoteUrl,
          username: 'demo',
          password: 'demo',
        ));

        await svc.resolveActiveUrl();

        expect(svc.activeBaseUrl, remoteUrl);
        expect(await storage.getLastActiveBaseUrl(), remoteUrl);
      });

      test('skips LAN probe when last session ended on remote', () async {
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        await storage.saveLastActiveBaseUrl(remoteUrl);
        final svc = SubsonicService(storageService: storage);
        svc.configure(ServerConfig(
          serverUrl: remoteUrl,
          localUrl: probeUrl,
          username: 'demo',
          password: 'demo',
        ));

        await svc.resolveActiveUrl();

        // Remote used immediately; the background probe (unreachable port)
        // must not switch the active URL.
        expect(svc.activeBaseUrl, remoteUrl);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(svc.activeBaseUrl, remoteUrl);
      });

      test('falls back to remote and persists when LAN probe fails', () async {
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        final svc = SubsonicService(storageService: storage);
        svc.configure(ServerConfig(
          serverUrl: remoteUrl,
          localUrl: probeUrl,
          username: 'demo',
          password: 'demo',
        ));

        await svc.resolveActiveUrl();

        expect(svc.activeBaseUrl, remoteUrl);
        expect(await storage.getLastActiveBaseUrl(), remoteUrl);
      });
    });
  });
}