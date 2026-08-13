import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/server_config.dart';
import '../providers/auth_provider.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import '../utils/navigation_helper.dart';
import '../widgets/server_profile_card.dart';
import '../widgets/server_qr_dialog.dart';
import '../widgets/settings_sub_page.dart';
import 'server_form_screen.dart';

/// 设置内「已保存配置」独立二级页。
///
/// 与登录网关页共用 [ServerProfileCard]；本页卡片额外提供 二维码 / 编辑 /
/// 删除 三个操作（删除带二次确认）。编辑/添加成功后 pop 回本页并刷新列表。
class SavedProfilesScreen extends StatefulWidget {
  const SavedProfilesScreen({super.key});

  @override
  State<SavedProfilesScreen> createState() => _SavedProfilesScreenState();
}

class _SavedProfilesScreenState extends State<SavedProfilesScreen> {
  Future<List<ServerConfig>>? _profilesFuture;
  bool _loaded = false;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _reload();
    }
  }

  void _reload() {
    _profilesFuture = Provider.of<AuthProvider>(
      context,
      listen: false,
    ).getSavedProfiles();
  }

  String _label(ServerConfig profile) {
    if (profile.name?.isNotEmpty == true) return profile.name!;
    return '${profile.username}@'
        '${Uri.tryParse(profile.serverUrl)?.host ?? profile.serverUrl}';
  }

  Future<void> _openAddServer() async {
    await NavigationHelper.push(context, const ServerFormScreen());
    if (mounted) setState(_reload);
  }

  Future<void> _openEdit(ServerConfig profile) async {
    // 编辑保存成功后表单会 pop(true)，据此刷新列表。
    final changed = await NavigationHelper.push(
      context,
      ServerFormScreen(initialConfig: profile),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _deleteProfile(ServerConfig profile) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteProfileTitle),
        content: Text(l10n.deleteProfileConfirm(_label(profile))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.delete,
              style: const TextStyle(color: Color(0xFFFF3B30)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await Provider.of<AuthProvider>(context, listen: false)
        .deleteProfile(profile);
    if (mounted) setState(_reload);
  }

  Future<void> _onProfileTap(ServerConfig profile) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isActive = authProvider.config?.serverUrl == profile.serverUrl &&
        authProvider.config?.username == profile.username;

    if (isActive) {
      await _openEdit(profile);
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.switchProfile),
        content: Text(l10n.switchProfileConfirmation(_label(profile))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 切换会走 _verifyConnection（网络等待可能数秒）：阻塞式进度框防止
    // 重复点击，失败时给出提示。
    BuildContext? dialogCtx;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogCtx = ctx;
        return const _ConnectingDialog();
      },
    );
    try {
      final playerProvider = Provider.of<PlayerProvider>(context, listen: false);
      await playerProvider.stop();
      await authProvider.switchProfile(profile);
    } catch (e) {
      // switchProfile 内部 configure 等无兜底，异常会逃逸：关框后给出与
      // 正常失败路径一致的提示，避免静默无反馈。
      debugPrint('[SavedProfiles] switchProfile threw: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              authProvider.error ?? l10n.failedToConnectToServer,
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    } finally {
      // 用弹窗自身的 context 关闭（挂在弹窗所在 Navigator 上），不依赖页面
      // mounted / Navigator.of(context) 的解析结果——切换成功触发页面重建或
      // 导航时序变化时也能可靠关闭，避免「连接中」弹窗残留。
      final ctx = dialogCtx;
      if (ctx != null && ctx.mounted) {
        Navigator.of(ctx).pop();
      }
    }
    if (!mounted) return;

    // 切换失败时 switchProfile 已回滚旧配置：比对目标是否生效，未生效则
    // 提示并停留在当前页（成功时根路由已换成 MainScreen）。
    final applied = authProvider.config?.serverUrl == profile.serverUrl &&
        authProvider.config?.username == profile.username;
    if (!applied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authProvider.error ?? l10n.failedToConnectToServer,
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // 成功：pop 回设置页避免叠层。
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsSubPage(
      title: l10n.sectionSavedProfiles,
      body: FutureBuilder<List<ServerConfig>>(
        future: _profilesFuture,
        builder: (context, snap) {
          // 读盘异常：展示错误 + 重试，避免永久 spinner。
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.failedToLoadProfiles,
                    style: TextStyle(
                      fontSize: 14,
                      color: _isDark
                          ? AppTheme.darkSecondaryText
                          : AppTheme.lightSecondaryText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => setState(_reload),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            );
          }
          // 数据未就绪时避免闪现空态。
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profiles = snap.data!;
          if (profiles.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.cloud,
                      size: 56,
                      color: _isDark
                          ? AppTheme.darkSecondaryText
                          : AppTheme.lightSecondaryText,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.noSavedProfiles,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: _isDark
                            ? AppTheme.darkSecondaryText
                            : AppTheme.lightSecondaryText,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 200,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: _openAddServer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(23),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          l10n.addServer,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final authProvider = Provider.of<AuthProvider>(context);
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              for (final profile in profiles) ...[
                ServerProfileCard(
                  profile: profile,
                  isActive: authProvider.config?.serverUrl ==
                          profile.serverUrl &&
                      authProvider.config?.username == profile.username,
                  onTap: () => _onProfileTap(profile),
                  onQr: () => showDialog(
                    context: context,
                    builder: (_) => ServerQrDialog(config: profile),
                  ),
                  onEdit: () => _openEdit(profile),
                  onDelete: () => _deleteProfile(profile),
                ),
                const SizedBox(height: 12),
              ],
              AddServerCard(onTap: _openAddServer),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

/// 切换服务器时的阻塞式进度框（不可点穿，防重复切换）。
class _ConnectingDialog extends StatelessWidget {
  const _ConnectingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Text(AppLocalizations.of(context)!.connecting),
          ],
        ),
      ),
    );
  }
}
