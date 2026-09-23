import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A shared "flow clock": a **monotonically increasing number of seconds that
/// never wraps around**.
///
/// Why not `AnimationController.repeat()` (whose value cycles 0→1):
///
/// - **Noise-based animation** (the shader's `uTime`) jumps on wrap-around —
///   noise is not a periodic function, so rewinding time snaps the picture.
/// - Periodic animation can reuse this clock too: just make the math
///   `2π`-periodic and the wrap point becomes seamless.
///
/// [stop] remembers the current seconds and [start] resumes from there (it does
/// **not** restart at 0), so hiding the widget and showing it again never
/// produces a jump.
///
/// You normally don't construct this yourself: wrap a subtree in
/// [FluidBackgroundScope] to share one clock, or pass nothing at all and
/// [FluidBackground] will create its own.
class FluidClock extends ValueNotifier<double> {
  /// Creates a clock driven by [vsync].
  FluidClock(TickerProvider vsync) : super(0) {
    _ticker = vsync.createTicker(_onTick);
  }

  late final Ticker _ticker;

  /// Seconds accumulated up to the last [stop] (a restarted [Ticker] reports
  /// `elapsed` starting from zero again).
  double _accumulated = 0;

  /// Whether the clock is currently advancing.
  bool get isRunning => _ticker.isActive;

  void _onTick(Duration elapsed) {
    value = _accumulated +
        elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  }

  /// Starts advancing. No-op if already running.
  void start() {
    if (!_ticker.isActive) _ticker.start();
  }

  /// Stops advancing, **remembering** the current value so [start] resumes.
  void stop() {
    if (!_ticker.isActive) return;
    _accumulated = value;
    _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
