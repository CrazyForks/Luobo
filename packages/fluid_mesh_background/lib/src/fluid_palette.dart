import 'package:flutter/widgets.dart';
import 'package:palette_generator/palette_generator.dart';

import 'fluid_events.dart';

/// Extracts the 4 colours that drive a fluid background from a cover image.
///
/// Results are cached (LRU, [cacheLimit] entries) so the same image is only
/// analysed once. Both [colorsFor] and [cached] are safe to call from a build
/// method — [cached] is synchronous and returns `null` on a miss.
///
/// Events (for the host app's own logging/observability) are reported through
/// [FluidBackgroundEvents.onEvent]; this class emits `paletteExtract` and
/// `paletteEvict`.
class FluidPalette {
  FluidPalette._();

  /// The shared instance. The cache lives here, so use this rather than
  /// constructing your own.
  static final FluidPalette instance = FluidPalette._();

  /// Maximum number of cached palettes; the oldest entry is evicted beyond it.
  static const int cacheLimit = 24;

  /// Colours used when there is no image, or extraction fails.
  static const List<Color> defaultColors = [
    Color(0xFF1B1035),
    Color(0xFF0E1A38),
    Color(0xFF0B1A2B),
    Color(0xFF170D2E),
  ];

  final Map<String, List<Color>> _cache = <String, List<Color>>{};

  /// A stable cache key for [provider].
  ///
  /// Prefers an explicit [cacheKey]; otherwise falls back to the image URL for
  /// [NetworkImage] (which covers `CachedNetworkImageProvider` subclasses that
  /// expose `url`), and finally to `provider.toString()`.
  static String? keyFor(ImageProvider? provider, {String? cacheKey}) {
    if (cacheKey != null && cacheKey.isNotEmpty) return cacheKey;
    if (provider == null) return null;
    if (provider is NetworkImage) return provider.url;
    return provider.toString();
  }

  /// Synchronously reads a cached palette, or `null` if not extracted yet.
  List<Color>? cached(String? key) {
    if (key == null || key.isEmpty) return null;
    return _cache[key];
  }

  /// Returns the 4 colours for [provider].
  ///
  /// Falls back to [defaultColors] when [provider] is null or extraction fails.
  Future<List<Color>> colorsFor(
    ImageProvider? provider, {
    String? cacheKey,
  }) async {
    final key = keyFor(provider, cacheKey: cacheKey);
    if (provider == null || key == null) return defaultColors;

    final hit = _cache[key];
    if (hit != null) {
      _emit('paletteExtract', {'key': key, 'cacheHit': true});
      return hit;
    }

    final stopwatch = Stopwatch()..start();
    try {
      final generator = await PaletteGenerator.fromImageProvider(
        provider,
        size: const Size(112, 112),
        maximumColorCount: 8,
      );
      final colors = _select(generator);
      _cache[key] = colors;
      _evictIfNeeded();

      stopwatch.stop();
      _emit('paletteExtract', {
        'key': key,
        'cacheHit': false,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });
      return colors;
    } catch (_) {
      return defaultColors;
    }
  }

  /// Picks 4 colours out of [generator].
  ///
  /// The order below is a deliberate **look** decision, not an accident: the
  /// vibrant swatches carry the colour identity of the artwork while the darker
  /// ones give the field its depth. It also avoids a common failure mode —
  /// a mostly-black cover would otherwise extract as pure black.
  List<Color> _select(PaletteGenerator generator) {
    final candidates = [
      generator.vibrantColor,
      generator.darkVibrantColor,
      generator.mutedColor,
      generator.darkMutedColor,
      generator.lightVibrantColor,
      generator.lightMutedColor,
    ].whereType<PaletteColor>().map((swatch) => swatch.color).toList();

    final colors = candidates.isNotEmpty
        ? candidates
        : generator.colors.take(6).toList();

    // The shader takes exactly 4 colours; pad with the last one when the
    // artwork yields fewer usable swatches.
    while (colors.length < 4) {
      colors.add(colors.isNotEmpty ? colors.last : defaultColors.first);
    }

    return [
      colors[0].withValues(alpha: 1.0),
      colors[1 % colors.length].withValues(alpha: 1.0),
      colors[2 % colors.length].withValues(alpha: 1.0),
      colors[3 % colors.length].withValues(alpha: 1.0),
    ];
  }

  void _evictIfNeeded() {
    if (_cache.length <= cacheLimit) return;
    final evicted = _cache.keys.first;
    _cache.remove(evicted);
    _emit('paletteEvict', {'evicted': evicted, 'cacheSize': _cache.length});
  }
}

/// Forwarded to [FluidBackgroundEvents] without importing the widget here.
void _emit(String event, Map<String, Object?> payload) {
  FluidBackgroundEvents.emit(event, payload);
}
