import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luobo/screens/now_playing_screen.dart';
import 'package:luobo/widgets/glass_surface.dart';

import '../bootstrap.dart';
import '../test_helpers.dart';

/// 回归防护：全屏播放页的播放列表（队列）弹层不应铺满整屏。
///
/// 背景：`showGlassBottomSheet`（亮色主题）用纯白 Container 包裹弹层内容；
/// `QueueSheet` 内部的 `DraggableScrollableSheet` 默认 `expand: true` 会把
/// 该 Container 撑满整个屏幕高度，导致弹层上方露出一整块白色色块
/// （暗色主题下为 0xFF1C1C1E 深色色块）。修复后 Container 应只包裹
/// 70% 高的弹层，顶部恢复为半透明遮罩。
void main() {
  initializeTestEnvironment();

  testWidgets('队列弹层外层容器只包裹弹层高度，不铺满全屏', (tester) async {
    await tester.pumpWidget(
      createTestApp(
        child: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showGlassBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => const QueueSheet(),
              ),
              child: const Text('open-queue'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-queue'));
    await tester.pumpAndSettle();

    // showGlassBottomSheet 在亮色主题下用纯白 Container 包裹内容，
    // 该容器是 DraggableScrollableSheet 的祖先。
    final whiteWrapper = find.ancestor(
      of: find.byType(DraggableScrollableSheet),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == Colors.white,
      ),
    );
    expect(
      whiteWrapper,
      findsOneWidget,
      reason: '应存在 showGlassBottomSheet 的白色外层容器',
    );

    final wrapperBox = tester.renderObject(whiteWrapper) as RenderBox;
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      wrapperBox.size.height,
      lessThan(screenHeight * 0.9),
      reason: '外层容器应为弹层高度(≈70% 屏高)，而非整屏高度（否则顶部露出白色色块）',
    );
  });
}
