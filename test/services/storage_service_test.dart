import 'package:flutter_test/flutter_test.dart';
import 'package:luobo/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('StorageService', () {
    late StorageService storageService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storageService = StorageService();
    });

    test('saveDiscordRpcEnabled saves value', () async {
      await storageService.saveDiscordRpcEnabled(true);
      expect(await storageService.getDiscordRpcEnabled(), true);
    });

    test('getDiscordRpcEnabled returns true by default', () async {
      expect(await storageService.getDiscordRpcEnabled(), true);
    });

    test('saveDiscordRpcEnabled updates value', () async {
      await storageService.saveDiscordRpcEnabled(true);
      expect(await storageService.getDiscordRpcEnabled(), true);
      await storageService.saveDiscordRpcEnabled(false);
      expect(await storageService.getDiscordRpcEnabled(), false);
    });

    test('last active base URL roundtrip', () async {
      expect(await storageService.getLastActiveBaseUrl(), isNull);
      await storageService.saveLastActiveBaseUrl('https://remote.example');
      expect(
        await storageService.getLastActiveBaseUrl(),
        'https://remote.example',
      );
      await storageService.saveLastActiveBaseUrl('http://192.168.1.10:4533');
      expect(
        await storageService.getLastActiveBaseUrl(),
        'http://192.168.1.10:4533',
      );
    });
  });
}
