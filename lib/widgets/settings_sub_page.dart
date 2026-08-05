import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 设置二级页薄壳：AppBar（返回键）+ 现有 tab 身体。
/// 各设置 tab 组件（SettingsPlaybackTab 等）保持 ListView 身体不变，由本壳
/// 提供页面框架；通过 NavigationHelper.push 进入。
class SettingsSubPage extends StatelessWidget {
  const SettingsSubPage({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        title: Text(title),
        centerTitle: false,
        backgroundColor:
            isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: body,
    );
  }
}
