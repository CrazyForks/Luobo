import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_mesh_background/fluid_mesh_background.dart';
import 'package:luobo/services/diagnostics/diagnostics.dart';
import 'package:luobo/widgets/mix_grid_section.dart';

import '../test_helpers.dart';

void main() {
  group('MixGridSection（为你制作）', () {
    testWidgets('4 张卡用流体背景，整段只占一个 Ticker（Scope 共享时钟）',
        (tester) async {
      final cards = ['通勤活力', '专注学习', '睡前放松', '你的最爱']
          .map((title) => MixCardData(title: title, useFluidGradient: true))
          .toList();

      await tester.pumpWidget(
        createTestApp(
          // 首页里这段本来就在 CustomScrollView 内，测试里给个可滚动容器，
          // 避免默认 800×600 测试视口把 4 张卡挤成 RenderFlex overflow。
          child: SingleChildScrollView(
            child: MixGridSection(title: '为你制作', cards: cards),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(FluidBackground), findsNWidgets(4));
      expect(tester.binding.transientCallbackCount, 1,
          reason: '4 张卡应共享 Scope 的 1 个时钟');

      // 埋点：本段的背景模式被记录（A/B 时用来归属 frame.jank）
      final modeEvent = DiagnosticsService.instance.ring.lastWhere(
        (e) =>
            e.type == EventType.animActive &&
            e.payload['anim'] == 'mixCardFluidBackground',
      );
      expect(modeEvent.payload['cards'], 4);
      expect(modeEvent.payload['clock'], 'monotonic');

      // 让 DiagnosticsService 的通知节流 Timer 落地，否则测试结束会报
      // 「A Timer is still pending」。
      await tester.pump(
        DiagnosticsService.notifyThrottle + const Duration(milliseconds: 50),
      );
    });

    testWidgets('流体包事件可接到诊断系统（shaderReady / paletteExtract）',
        (tester) async {
      final received = <String>[];
      FluidBackgroundEvents.onEvent = (event, payload) {
        received.add(event);
      };
      addTearDown(() => FluidBackgroundEvents.onEvent = null);

      final cards = [
        const MixCardData(title: '通勤活力', useFluidGradient: true),
      ];
      await tester.pumpWidget(
        createTestApp(
          child: SingleChildScrollView(
            child: MixGridSection(title: '为你制作', cards: cards),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // 至少收到渲染路径事件（shaderReady 或 shaderUnavailable 二选一）
      expect(
        received.any(
          (e) => e == 'shaderReady' || e == 'shaderUnavailable',
        ),
        isTrue,
        reason: '实际收到: $received',
      );

      await tester.pump(
        DiagnosticsService.notifyThrottle + const Duration(milliseconds: 50),
      );
    });
  });
}
