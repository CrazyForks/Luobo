import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/update_service.dart';
import '../services/diagnostics/diagnostics.dart';
import '../theme/app_theme.dart';
import '../utils/navigation_helper.dart';
import '../widgets/settings_sub_page.dart';
import 'settings_playback_tab.dart';
import 'settings_streaming_tab.dart';
import 'settings_storage_tab.dart';
import 'settings_server_tab.dart';
import 'settings_display_tab.dart';
import 'settings_ai_playlist_tab.dart';
import 'settings_mechanism_screen.dart';
import 'changelog_screen.dart';

/// 设置根页：单列表分组（对标 Apple Music / 网易云 / QQ 音乐设置页），
/// 替代旧 8 Tab 横滑骨架（旧 `SettingsScreen` 保留未删）。
///
/// 分组：账号与服务器 / 播放与音质 / 下载与存储 / 显示与外观 / AI 智能 / 关于
/// 退出登录已在服务器二级页中，根页不重复。
class SettingsRootScreen extends StatelessWidget {
  const SettingsRootScreen({super.key});

  bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = _isDark(context);
    return Scaffold(
      backgroundColor:
          isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        centerTitle: false,
        backgroundColor:
            isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _section(
            context,
            title: l10n.settingsGroupServer,
            children: [_serverCard(context)],
          ),
          const SizedBox(height: 24),
          _section(
            context,
            title: l10n.settingsGroupPlayback,
            children: [
              _navTile(
                context,
                icon: CupertinoIcons.play_circle,
                title: l10n.settingsPlaybackSettings,
                onTap: () => _openSubPage(
                  context,
                  l10n.settingsPlaybackSettings,
                  const SettingsPlaybackTab(),
                ),
              ),
              _divider(context),
              _navTile(
                context,
                icon: CupertinoIcons.waveform,
                title: l10n.settingsStreamingEntry,
                onTap: () => _openSubPage(
                  context,
                  l10n.settingsStreamingEntry,
                  const SettingsStreamingTab(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _section(
            context,
            title: l10n.settingsGroupStorage,
            children: [
              _navTile(
                context,
                icon: CupertinoIcons.folder,
                title: l10n.settingsStorageEntry,
                onTap: () => _openSubPage(
                  context,
                  l10n.settingsStorageEntry,
                  const SettingsStorageTab(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _section(
            context,
            title: l10n.settingsGroupDisplay,
            children: [
              _navTile(
                context,
                icon: CupertinoIcons.paintbrush,
                title: l10n.settingsDisplayEntry,
                onTap: () => _openSubPage(
                  context,
                  l10n.settingsDisplayEntry,
                  const SettingsDisplayTab(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _section(
            context,
            title: l10n.settingsGroupAi,
            children: [
              _navTile(
                context,
                icon: Icons.auto_awesome,
                title: l10n.settingsAiEntry,
                onTap: () => _openSubPage(
                  context,
                  l10n.settingsAiEntry,
                  const SettingsAiPlaylistTab(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildAboutSection(context),
          const SizedBox(height: 24),
          // 底部 footer：版本号
          Center(
            child: Text(
              'Luobo v${UpdateService.currentVersion}',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppTheme.darkSecondaryText
                    : AppTheme.lightSecondaryText,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── 账号与服务器 ──────────────────────────────────────────────────────

  Widget _serverCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final config = Provider.of<AuthProvider>(context).config;

    final serverType = config?.serverType;
    final serverVersion = config?.serverVersion;
    String serverSubtitle = 'Subsonic API';
    if (serverType != null && serverType.isNotEmpty) {
      serverSubtitle = serverType;
      if (serverVersion != null && serverVersion.isNotEmpty) {
        serverSubtitle += ' $serverVersion';
      }
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _leadingIcon(context, CupertinoIcons.cloud),
      title: Text(
        config == null ? l10n.notConnected : serverSubtitle,
        style: const TextStyle(fontSize: 16),
      ),
      subtitle: config == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((config.serverUrl).isNotEmpty)
                  Text(
                    config.serverUrl,
                    style: _subtitleStyle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if ((config.username).isNotEmpty)
                  Text(config.username, style: _subtitleStyle(context)),
              ],
            ),
      trailing: _chevron(context),
      onTap: () => _openSubPage(
        context,
        l10n.serverManagement,
        const SettingsServerTab(),
      ),
    );
  }

  // ── 关于 ─────────────────────────────────────────────────────────────

  Widget _buildAboutSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _section(
      context,
      title: l10n.tabAbout,
      children: [
        _valueTile(
          context,
          icon: CupertinoIcons.info,
          title: l10n.aboutVersion,
          value: UpdateService.currentVersion,
        ),
        _divider(context),
        _valueTile(
          context,
          icon: CupertinoIcons.device_phone_portrait,
          title: l10n.aboutPlatform,
          value: Theme.of(context).platform.name.toUpperCase(),
        ),
        _divider(context),
        _navTile(
          context,
          icon: CupertinoIcons.doc_text,
          title: l10n.aboutLinkGitHub,
          onTap: () =>
              _openUrl('https://github.com/chengsitom/Luobo'),
        ),
        _divider(context),
        _navTile(
          context,
          icon: CupertinoIcons.arrow_up_circle,
          title: l10n.aboutLinkChangelog,
          onTap: () => NavigationHelper.push(
              context, const ChangelogScreen()),
        ),
        _divider(context),
        _navTile(
          context,
          icon: CupertinoIcons.lightbulb,
          title: l10n.settingsMechanicsEntry,
          onTap: () => NavigationHelper.push(
              context, const SettingsMechanismScreen()),
        ),
        _divider(context),
        _navTile(
          context,
          icon: Icons.monitor_heart_outlined,
          title: l10n.tabDiagnostics,
          onTap: () =>
              NavigationHelper.push(context, const DiagnosticsPage()),
        ),
      ],
    );
  }

  // ── 通用行组件（方案 B：主色淡底 + 单色图标，Apple Music 风格） ───────

  Widget _section(
    BuildContext context, {
    String? title,
    required List<Widget> children,
  }) {
    final isDark = _isDark(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: isDark
                    ? AppTheme.darkSecondaryText
                    : AppTheme.lightSecondaryText,
                letterSpacing: 0.2,
              ),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  Widget _divider(BuildContext context) {
    final isDark = _isDark(context);
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Container(
        height: 0.5,
        color: isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
      ),
    );
  }

  Widget _leadingIcon(BuildContext context, IconData icon, {Color? color}) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: accent, size: 18),
    );
  }

  TextStyle _subtitleStyle(BuildContext context) => TextStyle(
        fontSize: 12,
        color: _isDark(context)
            ? AppTheme.darkSecondaryText
            : AppTheme.lightSecondaryText,
      );

  Widget _chevron(BuildContext context) {
    return Icon(
      CupertinoIcons.chevron_right,
      size: 16,
      color: _isDark(context)
          ? AppTheme.darkSecondaryText
          : AppTheme.lightSecondaryText,
    );
  }

  Widget _navTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _leadingIcon(context, icon),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(fontSize: 13))
          : null,
      trailing: _chevron(context),
      onTap: onTap,
    );
  }

  Widget _valueTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _leadingIcon(context, icon),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      trailing: Text(
        value,
        style: TextStyle(
          fontSize: 16,
          color: _isDark(context)
              ? AppTheme.darkSecondaryText
              : AppTheme.lightSecondaryText,
        ),
      ),
    );
  }

  // ── 动作 ─────────────────────────────────────────────────────────────

  void _openSubPage(BuildContext context, String title, Widget body) {
    NavigationHelper.push(context, SettingsSubPage(title: title, body: body));
  }

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error opening URL: $e');
    }
  }
}
