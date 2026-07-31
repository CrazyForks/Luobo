import 'package:shared_preferences/shared_preferences.dart';

/// Toggles for image and music caching. BPM caching is intentionally
/// always enabled (it consumes negligible space in SharedPreferences).
class CacheSettingsService {
  static const String _keyImageCacheEnabled = 'cache_images_enabled';
  static const String _keyMusicCacheEnabled = 'cache_music_enabled';

  static final CacheSettingsService _instance =
      CacheSettingsService._internal();
  factory CacheSettingsService() => _instance;
  CacheSettingsService._internal();

  SharedPreferences? _prefs;

  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> setImageCacheEnabled(bool enabled) async {
    await initialize();
    await _prefs!.setBool(_keyImageCacheEnabled, enabled);
  }

  bool getImageCacheEnabled() {
    return _prefs?.getBool(_keyImageCacheEnabled) ?? true;
  }

  Future<void> setMusicCacheEnabled(bool enabled) async {
    await initialize();
    await _prefs!.setBool(_keyMusicCacheEnabled, enabled);
  }

  bool getMusicCacheEnabled() {
    return _prefs?.getBool(_keyMusicCacheEnabled) ?? true;
  }
}
