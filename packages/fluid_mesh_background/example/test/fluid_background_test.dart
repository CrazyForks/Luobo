import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_mesh_background/fluid_mesh_background.dart';

const List<Color> _colors = [
  Color(0xFF112233),
  Color(0xFF445566),
  Color(0xFF778899),
  Color(0xFF0A0A0A),
];

/// Renders the fluid mesh shader offscreen to RGBA pixels.
///
/// Goes through the same [FluidBackgroundStyle.applyUniforms] the painter uses,
/// so uniform indices cannot drift between production and tests.
Future<Uint8List> _render({
  required ui.FragmentProgram program,
  required int size,
  required double realSeconds,
  required double seed,
  List<Color> colors = _colors,
}) async {
  const style = FluidBackgroundStyle.standard;
  final shader = program.fragmentShader();
  style.applyUniforms(
    shader,
    width: size.toDouble(),
    height: size.toDouble(),
    shaderTime: style.meshTimeFor(realSeconds),
    seed: seed,
    colors: colors,
  );

  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..shader = shader,
  );
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  shader.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Share of pixels that differ noticeably between two renders.
double _diffRatio(Uint8List a, Uint8List b, int size) {
  var changed = 0;
  for (var p = 0; p < size * size; p++) {
    if ((a[p * 4] - b[p * 4]).abs() > 2) changed++;
  }
  return changed / (size * size);
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// A host that owns a [FluidClock] so the clock itself can be tested.
class _ClockHost extends StatefulWidget {
  const _ClockHost({required this.onReady});

  final void Function(FluidClock) onReady;

  @override
  State<_ClockHost> createState() => _ClockHostState();
}

class _ClockHostState extends State<_ClockHost>
    with SingleTickerProviderStateMixin {
  late final FluidClock clock = FluidClock(this);

  @override
  void initState() {
    super.initState();
    widget.onReady(clock);
    clock.start();
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  group('FluidPalette', () {
    test('no image → default colours, and nothing is cached', () async {
      final palette = FluidPalette.instance;
      expect(await palette.colorsFor(null), FluidPalette.defaultColors);
      expect(palette.cached(null), isNull);
      expect(palette.cached(''), isNull);
      expect(FluidPalette.keyFor(null), isNull);
    });

    test('keyFor prefers an explicit key, then the NetworkImage url', () {
      const image = NetworkImage('https://example.test/a.jpg');
      expect(FluidPalette.keyFor(image), 'https://example.test/a.jpg');
      expect(FluidPalette.keyFor(image, cacheKey: 'explicit'), 'explicit');
      expect(FluidPalette.keyFor(null, cacheKey: 'explicit'), 'explicit');
    });

    test('default colours have exactly 4 entries (the shader contract)', () {
      expect(FluidPalette.defaultColors.length, 4);
    });
  });

  group('FluidClock (monotonic — the prerequisite for noise animation)', () {
    testWidgets('advances, freezes on stop, and resumes instead of resetting',
        (tester) async {
      late FluidClock clock;
      await tester.pumpWidget(_ClockHost(onReady: (c) => clock = c));
      await tester.pump(); // first tick (elapsed == 0)
      await tester.pump(const Duration(seconds: 3));

      final running = clock.value;
      expect(running, greaterThan(0));

      clock.stop();
      final stopped = clock.value;
      await tester.pump(const Duration(seconds: 5));
      expect(clock.value, stopped, reason: 'a stopped clock must not advance');

      clock.start();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(clock.value, greaterThan(stopped),
          reason: 'resuming must continue, not jump back to 0');
    });
  });

  group('fallback geometry (regression: the wrap point must not jump)', () {
    test('blob centres are 2π-periodic', () {
      const twoPi = 2 * math.pi;
      for (var i = 0; i < 3; i++) {
        for (final t in <double>[0, 0.7, 2.3, 5.1]) {
          final at0 = FluidBackground.blobAlignmentFor(i, t);
          final atCycle = FluidBackground.blobAlignmentFor(i, t + twoPi);
          expect(atCycle.x, closeTo(at0.x, 1e-9), reason: 'blob $i @ t=$t');
          expect(atCycle.y, closeTo(at0.y, 1e-9), reason: 'blob $i @ t=$t');
        }
      }
    });

    test('radius breathing is 2π-periodic', () {
      const twoPi = 2 * math.pi;
      for (var i = 0; i < 3; i++) {
        for (final t in <double>[0, 0.7, 2.3, 5.1]) {
          expect(
            FluidBackground.blobRadiusFactorFor(i, t + twoPi),
            closeTo(FluidBackground.blobRadiusFactorFor(i, t), 1e-9),
            reason: 'blob $i @ t=$t',
          );
        }
      }
    });

    // Quantifies the step that crosses the wrap point against a normal step.
    // Non-integer harmonics (e.g. cos(p * 0.8)) blow this up — that is the
    // "the animation has a definite end point" bug.
    test('the step across the wrap equals a normal step', () {
      const dt = 0.01;
      const twoPi = 2 * math.pi;

      double step(int i, double from, double to) {
        final a = FluidBackground.blobAlignmentFor(i, from);
        final b = FluidBackground.blobAlignmentFor(i, to);
        return math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
      }

      for (var i = 0; i < 3; i++) {
        final beforeWrap = step(i, twoPi - 2 * dt, twoPi - dt);
        final acrossWrap = step(i, twoPi - dt, 0);
        expect(acrossWrap, closeTo(beforeWrap, beforeWrap * 0.02),
            reason: 'blob $i must not jump across the wrap');
      }
    });
  });

  group('fluid mesh shader', () {
    // 必须用普通 test() 而非 testWidgets：toImage 是真实异步，fake-async 的
    // testWidgets 环境里永远不会完成（会挂死整个测试进程）。
    test('renders a continuous field: opaque, varied, and flowing', () async {
      const size = 64;
      final a = await _render(program: await _program(),
          size: size,
          realSeconds: 0,
          seed: 0);
      final b = await _render(program: await _program(),
          size: size,
          realSeconds: 20,
          seed: 0);

      // ① fully opaque — the background must not have holes
      for (var p = 0; p < size * size; p++) {
        expect(a[p * 4 + 3], 255, reason: 'pixel $p must be opaque');
      }

      // ② spatially varied — a flat colour would mean the noise is not working
      int redAt(Uint8List d, int x, int y) => d[(y * size + x) * 4];
      final samples = {
        redAt(a, 2, 2),
        redAt(a, size - 3, 2),
        redAt(a, 2, size - 3),
        redAt(a, size - 3, size - 3),
        redAt(a, size ~/ 2, size ~/ 2),
      };
      expect(samples.length, greaterThan(2), reason: 'expected variety: $samples');

      // ③ large change over time — it is flowing, not static
      expect(_diffRatio(a, b, size), greaterThan(0.3),
          reason: 'expected a large change after 20 s');
    });

    test('different seeds give clearly different patterns', () async {
      const size = 64;
      final program = await _program();
      final s0 = await _render(program: program,
          size: size,
          realSeconds: 0,
          seed: FluidBackground.seedForIndex(0));
      final s1 = await _render(program: program,
          size: size,
          realSeconds: 0,
          seed: FluidBackground.seedForIndex(1));

      expect(_diffRatio(s0, s1, size), greaterThan(0.4),
          reason: 'neighbouring items must not share one pattern');
    });

    test('seeds spread both the direction and the noise region', () {
      final seeds = List.generate(4, FluidBackground.seedForIndex);
      for (var i = 1; i < seeds.length; i++) {
        expect(seeds[i] - seeds[i - 1], closeTo(math.pi / 4, 1e-9),
            reason: 'direction step must be 45°');
        expect((seeds[i] - seeds[i - 1]) * 37, greaterThan(20),
            reason: 'noise regions must be far apart');
      }
    });

    test('flow speed is below 1× (i.e. slower than the raw shader rate)', () {
      const style = FluidBackgroundStyle.standard;
      expect(style.speed, lessThan(1));
      expect(style.meshTimeFor(10), lessThan(10));
      expect(style.meshTimeFor(10), closeTo(10 * style.speed, 1e-9));
    });
  });

  group('FluidBackground widget', () {
    testWidgets('renders with explicit colours and keeps animating',
        (tester) async {
      await tester.pumpWidget(_host(const SizedBox(
        width: 150,
        height: 150,
        child: FluidBackground(colors: _colors, borderRadius: 12),
      )));
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('useShader=false takes the fallback path', (tester) async {
      await tester.pumpWidget(_host(const SizedBox(
        width: 150,
        height: 150,
        child: FluidBackground(colors: _colors, useShader: false),
      )));
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('TickerMode stops the clock, and resumes it', (tester) async {
      Widget build({required bool enabled}) => _host(TickerMode(
            enabled: enabled,
            child: const SizedBox(
              width: 150,
              height: 150,
              child: FluidBackground(colors: _colors, useShader: false),
            ),
          ));

      await tester.pumpWidget(build(enabled: false));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0,
          reason: 'a hidden widget must not produce frames');

      await tester.pumpWidget(build(enabled: true));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0),
          reason: 'it must resume when visible again');
    });
  });

  group('FluidBackgroundScope (shared clock)', () {
    Widget twoBackgrounds({bool scoped = true}) {
      const content = Column(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: FluidBackground(colors: _colors, useShader: false),
          ),
          SizedBox(
            width: 120,
            height: 120,
            child: FluidBackground(colors: _colors, useShader: false),
          ),
        ],
      );
      return _host(scoped
          ? const FluidBackgroundScope(child: content)
          : content);
    }

    testWidgets('scoped: several instances share one ticker', (tester) async {
      await tester.pumpWidget(twoBackgrounds());
      expect(tester.takeException(), isNull);
      expect(find.byType(FluidBackground), findsNWidgets(2));
      expect(tester.binding.transientCallbackCount, 1);
    });

    testWidgets('unscoped: each instance creates its own (why the scope exists)',
        (tester) async {
      await tester.pumpWidget(twoBackgrounds(scoped: false));
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 2);
    });

    testWidgets('the scope stops the clock when TickerMode is off',
        (tester) async {
      await tester.pumpWidget(_host(const TickerMode(
        enabled: false,
        child: FluidBackgroundScope(
          child: SizedBox(
            width: 120,
            height: 120,
            child: FluidBackground(colors: _colors, useShader: false),
          ),
        ),
      )));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}

/// Loads the shader bundled by the package.
///
/// Throws when the environment has no fragment-shader support; the widget itself
/// degrades to the fallback painter in that case.
Future<ui.FragmentProgram> _program() =>
    ui.FragmentProgram.fromAsset(FluidBackground.shaderAsset);
