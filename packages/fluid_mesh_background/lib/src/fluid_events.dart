/// Optional observability hook for this package.
///
/// The package never logs anywhere by itself — it only reports structured
/// events here. Wire it to your own logging/diagnostics system if you want
/// visibility into which render path is active:
///
/// ```dart
/// FluidBackgroundEvents.onEvent = (event, payload) {
///   myDiagnostics.record(event, payload);
/// };
/// ```
///
/// Emitted events:
///
/// | event | payload | when |
/// |---|---|---|
/// | `shaderReady` | `{available: true}` | the fragment shader loaded |
/// | `shaderUnavailable` | `{available: false, error: String}` | shader missing/unsupported → the fallback painter is used |
/// | `paletteExtract` | `{key, cacheHit, elapsedMs?}` | a palette was read from cache or extracted |
/// | `paletteEvict` | `{evicted, cacheSize}` | the palette cache dropped its oldest entry |
///
/// **Why this exists**: frame-jank reports usually only carry the route, so on a
/// page that can render two different ways you cannot tell which path was slow.
/// These events make the active path attributable.
class FluidBackgroundEvents {
  FluidBackgroundEvents._();

  /// Receives every event emitted by this package. Null by default (no-op).
  static void Function(String event, Map<String, Object?> payload)? onEvent;

  /// Emits an event to [onEvent], if set.
  static void emit(String event, Map<String, Object?> payload) {
    onEvent?.call(event, payload);
  }
}
