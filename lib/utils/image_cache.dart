import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
          await precacheImage(CachedNetworkImageProvider(url), context);
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
      await precacheImage(CachedNetworkImageProvider(imageUrl), context);
    } catch (_) {
      
    }
  }
}