import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Shared disk-cache manager for cover art. `DefaultCacheManager` only keeps
/// 200 files, which thrashes on a large library (every scroll evicts older
/// covers). This manager keeps ~1000 covers and a 60-day staleness window.
final CacheManager coverCacheManager = CacheManager(
  Config(
    'coverCache',
    stalePeriod: const Duration(days: 60),
    maxNrOfCacheObjects: 1000,
  ),
);

class ImageCacheConfig {
  static void configure() {
    // Large enough to hold several screens of covers in memory so fast
    // scrolling doesn't repeatedly re-decode images from disk.
    PaintingBinding.instance.imageCache.maximumSize = 300;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 150 << 20;
  }
}

class ImagePreloader {

  static Future<void> preloadImages(
    BuildContext context,
    List<String> imageUrls,
  ) async {
    for (final url in imageUrls) {
      if (url.isNotEmpty) {
        try {
          await precacheImage(CachedNetworkImageProvider(url, cacheManager: coverCacheManager), context);
        } catch (_) {
          
        }
      }
    }
  }

  static Future<void> preloadImage(
    BuildContext context,
    String imageUrl,
  ) async {
    if (imageUrl.isEmpty) return;

    try {
      await precacheImage(CachedNetworkImageProvider(imageUrl, cacheManager: coverCacheManager), context);
    } catch (_) {
      
    }
  }
}