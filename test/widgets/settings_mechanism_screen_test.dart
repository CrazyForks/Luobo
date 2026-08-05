import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luobo/l10n/app_localizations.dart';
import 'package:luobo/screens/settings_mechanism_screen.dart';

/// 「机制说明」冒烟测试：二级页分组列表渲染、点击进入三级页、
/// 技术细节默认收起、展开后可见。
void main() {
  testWidgets('机制说明：列表渲染 → 详情页 → 技术细节默认收起可展开', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const SettingsMechanismScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // 二级页：分组标题（zh l10n）+ 中文条目
    expect(find.text('首页推荐'), findsOneWidget);
    expect(find.text('每日推荐是怎么算的'), findsOneWidget);

    // 点击进入三级页
    await tester.tap(find.text('每日推荐是怎么算的'));
    await tester.pumpAndSettle();

    // 通俗文案展示
    expect(find.textContaining('每天一套固定的 30 首推荐'), findsOneWidget);

    // 技术细节默认收起
    expect(find.textContaining('dailyRecommendation'), findsNothing);

    // 展开技术细节
    await tester.tap(find.text('技术细节'));
    await tester.pumpAndSettle();
    expect(find.textContaining('dailyRecommendation'), findsOneWidget);
  });
}
