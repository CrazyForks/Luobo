import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/server_config.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

enum _LoginErrorType {
  ssl,
  credentials,
  notFound,
  timeout,
  connection,
  format,
  generic,
}

/// 连接表单页（登录第 2 步）：分组卡片 + 填充式无边框输入。
///
/// 三种进入方式：
/// - 登录网关页「＋ 添加服务器」→ [initialConfig] 为空，标题「添加服务器」
/// - 设置「已保存配置」二级页编辑 → [initialConfig] 非空，标题「编辑服务器」
/// - `LoginScreen(initialConfig:)` 兼容入口（旧调用点保留）
///
/// 服务器类型默认「自动检测」：按 subsonic 通道登录（Subsonic/Jellyfin/
/// 道理鱼均接受该通道），成功后展示以 ping 自报的 serverType 为准
/// （`ServerFamilyInfo.of` 兜底显示），不新增网络行为。
class ServerFormScreen extends StatefulWidget {
  final ServerConfig? initialConfig;

  const ServerFormScreen({super.key, this.initialConfig});

  @override
  State<ServerFormScreen> createState() => _ServerFormScreenState();
}

class _ServerFormScreenState extends State<ServerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _localServerController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _profileNameController = TextEditingController();
  final _serverFocusNode = FocusNode();
  final _localServerFocusNode = FocusNode();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _useLegacyAuth = false;
  bool _allowSelfSignedCertificates = false;
  bool _obscurePassword = true;
  bool _showAdvancedOptions = false;

  /// 'auto' | 'subsonic' | 'jellyfin' | 'daoliyu'（'youtube' 仅防御性保留，
  /// 兼容历史 profile，UI 上不可选）。
  String _serverFamily = 'auto';

  String? _customCertificatePath;
  String? _customCertificateName;
  String? _clientCertificatePath;
  String? _clientCertificateName;
  final _clientCertPasswordController = TextEditingController();
  bool _obscureClientCertPassword = true;

  String? _loginError;

  bool get _isEdit => widget.initialConfig != null;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
    _serverController.addListener(_clearError);
    _localServerController.addListener(_clearError);
    _usernameController.addListener(_clearError);
    _passwordController.addListener(_clearError);
    _profileNameController.addListener(_clearError);
    _prefillFromConfig(widget.initialConfig);
  }

  @override
  void dispose() {
    _serverController.removeListener(_clearError);
    _localServerController.removeListener(_clearError);
    _usernameController.removeListener(_clearError);
    _passwordController.removeListener(_clearError);
    _profileNameController.removeListener(_clearError);
    _serverController.dispose();
    _localServerController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _profileNameController.dispose();
    _clientCertPasswordController.dispose();
    _serverFocusNode.dispose();
    _localServerFocusNode.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  /// 预填已有配置（编辑模式）。
  void _prefillFromConfig(ServerConfig? config) {
    if (config == null) return;
    _serverController.text =
        config.serverUrl == 'local' ? '' : config.serverUrl;
    _localServerController.text = config.localUrl ?? '';
    _usernameController.text = config.username;
    _passwordController.text = config.password;
    _profileNameController.text = config.name ?? '';
    _serverFamily = _normalizeFamily(config.serverFamily);
    // 道理鱼只认明文 p=，从已存 profile 恢复表单时同样强制。
    _useLegacyAuth = config.useLegacyAuth || config.serverFamily == 'daoliyu';
    _allowSelfSignedCertificates = config.allowSelfSignedCertificates;
    _customCertificatePath = config.customCertificatePath;
    if (config.customCertificatePath != null) {
      _customCertificateName =
          config.customCertificatePath!.split(Platform.pathSeparator).last;
    }
    _clientCertificatePath = config.clientCertificatePath;
    if (config.clientCertificatePath != null) {
      _clientCertificateName =
          config.clientCertificatePath!.split(Platform.pathSeparator).last;
    }
    _clientCertPasswordController.text = config.clientCertificatePassword ?? '';
  }

  /// 历史 profile 可能带 'youtube' 等家族，保留原值防御性处理；
  /// 未知/空家族归为「自动检测」。
  String _normalizeFamily(String family) {
    const known = {'subsonic', 'jellyfin', 'daoliyu', 'youtube'};
    return known.contains(family) ? family : 'auto';
  }

  void _clearError() {
    if (_loginError != null && mounted) {
      setState(() => _loginError = null);
    }
  }

  // ── 登录 ────────────────────────────────────────────────────────────

  Future<void> _login() async {
    // 保持 'auto' 原值传给 login()：按 subsonic 通道登录（Jellyfin 的
    // subsonic 兼容端点同样接受密码认证），并把 'auto' 落盘——下次编辑仍显示
    // 「自动检测」，与用户选择一致（未知家族在下游均按 subsonic 处理）。
    final effectiveFamily = _serverFamily;

    // YouTube Music requires no credentials — skip form validation
    if (effectiveFamily != 'youtube') {
      if (!_formKey.currentState!.validate()) return;
    }

    setState(() => _loginError = null);

    var serverUrl =
        effectiveFamily == 'youtube'
            ? 'https://music.youtube.com'
            : _serverController.text.trim();
    final localUrl = _localServerController.text.trim();

    // 两字段皆空已由服务器地址字段 validator（pleaseEnterServerUrl）拦截，
    // 无需在此重复处理（旧 login_screen 的硬编码中文兜底为不可达分支，已移除）。

    // 仅填局域网地址时，把它同时作为主地址（见旧 login_screen.dart 注释：
    // 保证 LAN-only 配置的「不转码」规则生效，且重存 profile 时两字段一致）。
    final isLanOnly = effectiveFamily != 'youtube' &&
        localUrl.isNotEmpty &&
        (serverUrl.isEmpty || localUrl == serverUrl);
    if (isLanOnly && serverUrl.isEmpty) {
      serverUrl = localUrl;
    }

    if (effectiveFamily != 'youtube' &&
        serverUrl.isNotEmpty &&
        !serverUrl.startsWith('http://') &&
        !serverUrl.startsWith('https://')) {
      setState(
        () => _loginError = AppLocalizations.of(context)!.serverUrlMustStartWith,
      );
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final profileName = _profileNameController.text.trim();
    final effectiveLocalUrl =
        (localUrl.isNotEmpty && (localUrl != serverUrl || isLanOnly))
            ? localUrl
            : null;

    bool success = false;
    try {
      success = await authProvider.login(
        serverUrl: serverUrl,
        localUrl: effectiveLocalUrl,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        useLegacyAuth: _useLegacyAuth,
        allowSelfSignedCertificates: _allowSelfSignedCertificates,
        customCertificatePath: _customCertificatePath,
        clientCertificatePath: _clientCertificatePath,
        clientCertificatePassword: _clientCertPasswordController.text.isEmpty
            ? null
            : _clientCertPasswordController.text,
        profileName: profileName.isEmpty ? null : profileName,
        serverFamily: effectiveFamily,
      );
    } catch (e) {
      // login() 内部已兜底返回 false，此处防御异常，避免卡 loading。
      debugPrint('[Login] login() threw: $e');
      success = false;
    }

    if (!mounted) return;

    if (success) {
      // 先取 root messenger，pop 后再显示——避免 SnackBar 因 context 随
      // pop 销毁而被吞。
      final messenger = ScaffoldMessenger.of(context);
      // 统一 pop 回来源页（设置二级页 / 网关），带回 true 触发列表刷新：
      // - 设置二级页新增：回列表并刷新，不再被 popUntil 甩回首页；
      // - 网关（根）场景：pop 后 AuthWrapper 已按 state 换成 MainScreen，
      //   与 popUntil(isFirst) 效果一致。
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.connectedSuccessfully),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(
        () => _loginError = authProvider.error ??
            AppLocalizations.of(context)!.failedToConnectToServer,
      );
    }
  }

  // ── 证书选择（与旧登录页一致） ───────────────────────────────────────

  Future<void> _pickClientCertificate() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['p12', 'pfx', 'pem'],
        dialogTitle: AppLocalizations.of(context)!.selectClientCertificate,
      );
      if (result != null && result.files.single.path != null && mounted) {
        setState(() {
          _clientCertificatePath = result.files.single.path;
          _clientCertificateName = result.files.single.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!
                  .failedToSelectClientCert(e.toString()),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickCertificateFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pem', 'crt', 'cer', 'p12', 'pfx', 'der'],
        dialogTitle: AppLocalizations.of(context)!.selectCertificate,
      );

      if (result != null && result.files.single.path != null && mounted) {
        setState(() {
          _customCertificatePath = result.files.single.path;
          _customCertificateName = result.files.single.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              )!
                  .failedToSelectCertificate(e.toString()),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── 服务器类型底部弹层 ──────────────────────────────────────────────

  String get _serverFamilyLabel {
    final l10n = AppLocalizations.of(context)!;
    return switch (_serverFamily) {
      'subsonic' => l10n.serverTypeSubsonic,
      'jellyfin' => l10n.serverTypeJellyfin,
      'daoliyu' => l10n.serverTypeDaoliyu,
      // 历史 youtube profile 防御性保留（与 ServerFamilyInfo 文案一致）。
      'youtube' => 'YouTube Music',
      _ => l10n.serverTypeAuto,
    };
  }

  Future<void> _showServerTypeSheet() async {
    final l10n = AppLocalizations.of(context)!;
    final options = [
      (
        family: 'auto',
        label: l10n.serverTypeAuto,
        subtitle: l10n.serverTypeAutoSubtitle,
        icon: CupertinoIcons.sparkles,
        color: Theme.of(context).colorScheme.primary,
      ),
      (
        family: 'subsonic',
        label: l10n.serverTypeSubsonic,
        subtitle: null,
        icon: CupertinoIcons.music_note,
        color: const Color(0xFF6366F1),
      ),
      (
        family: 'jellyfin',
        label: l10n.serverTypeJellyfin,
        subtitle: null,
        icon: CupertinoIcons.tv,
        color: const Color(0xFFA970FF),
      ),
      (
        family: 'daoliyu',
        label: l10n.serverTypeDaoliyu,
        subtitle: null,
        icon: CupertinoIcons.music_note_list,
        color: const Color(0xFF34C759),
      ),
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  l10n.selectServerType,
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              for (final opt in options)
                ListTile(
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: opt.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(opt.icon, color: opt.color, size: 18),
                  ),
                  title: Text(opt.label, style: const TextStyle(fontSize: 16)),
                  subtitle: opt.subtitle != null
                      ? Text(
                          opt.subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppTheme.darkSecondaryText
                                : AppTheme.lightSecondaryText,
                          ),
                        )
                      : null,
                  trailing: _serverFamily == opt.family
                      ? Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: Theme.of(sheetContext).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(opt.family),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected != null && mounted) {
      setState(() {
        _serverFamily = selected;
        // 道理鱼只认明文 p=，选中即强制 legacy 认证（开关同步禁用）。
        _useLegacyAuth = selected == 'daoliyu';
      });
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isLoading =
        Provider.of<AuthProvider>(context).state == AuthState.authenticating;

    return Scaffold(
      // 与搜索页一致：窗口不随键盘缩放（resize 在此设备上会留下「键盘上方
      // 空白带 + 内容被顶起」）。底部字段可见性改由滚动区键盘高度留白 +
      // 输入框 scrollPadding 保证。
      resizeToAvoidBottomInset: false,
      backgroundColor: _isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        title: Text(_isEdit ? l10n.editServer : l10n.addServer),
        centerTitle: false,
        backgroundColor:
            _isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: GestureDetector(
        // 点击空白区域收起键盘（输入框等子级点击优先命中，不受影响）。
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          // Android 15+ 强制 edge-to-edge：键盘弹出时 MediaQuery.viewPadding 会
          // 镜像键盘高度，底部 SafeArea 若再避让会造成「键盘上方空白带 + 内容
          // 被顶起」。键盘弹出时禁用底部避让（Scaffold 已按 viewInsets 缩放 body），
          // 收起时恢复以避开系统导航条。
          bottom: MediaQuery.viewInsetsOf(context).bottom == 0,
          child: SingleChildScrollView(
            // 拖动页面时顺带收起键盘。
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              // 底部按键盘高度留白：窗口不缩放，靠滚动把内容抬到键盘上方。
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Align(
              // 内容顶部对齐：键盘弹出时输入框自动滚动到键盘上方，
              // 不再因垂直居中在键盘与内容之间留下空白。
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    _groupTitle(l10n.formSectionConnection),
                    const SizedBox(height: 8),
                    _groupCard([
                      _urlField(
                        controller: _serverController,
                        focusNode: _serverFocusNode,
                        label: l10n.serverUrl,
                        hint: l10n.serverUrlHint,
                        icon: CupertinoIcons.globe,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) =>
                            _localServerFocusNode.requestFocus(),
                        validator: (value) {
                          final url = (value ?? '').trim();
                          if (url.isEmpty &&
                              _localServerController.text.trim().isEmpty) {
                            return l10n.pleaseEnterServerUrl;
                          }
                          if (url.isNotEmpty && !url.startsWith('http://') &&
                              !url.startsWith('https://')) {
                            return l10n.invalidUrlFormat;
                          }
                          return null;
                        },
                      ),
                      _urlField(
                        controller: _localServerController,
                        focusNode: _localServerFocusNode,
                        label: l10n.lanUrl,
                        hint: l10n.lanUrlHint,
                        icon: CupertinoIcons.wifi,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) =>
                            _usernameFocusNode.requestFocus(),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final url = value.trim();
                          if (!url.startsWith('http://') &&
                              !url.startsWith('https://')) {
                            return l10n.invalidUrlFormat;
                          }
                          return null;
                        },
                      ),
                      _serverTypeTile(),
                    ]),
                    const SizedBox(height: 24),
                    _groupTitle(l10n.formSectionAccount),
                    const SizedBox(height: 8),
                    _groupCard([
                      _urlField(
                        controller: _usernameController,
                        focusNode: _usernameFocusNode,
                        label: l10n.username,
                        icon: CupertinoIcons.person,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) =>
                            _passwordFocusNode.requestFocus(),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return l10n.pleaseEnterUsername;
                          }
                          return null;
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: TextFormField(
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!isLoading) _login();
                          },
                          scrollPadding: EdgeInsets.only(
                            bottom: MediaQuery.viewInsetsOf(context).bottom +
                                16,
                          ),
                        decoration: _filledDecoration(
                          label: l10n.password,
                          icon: CupertinoIcons.lock,
                          suffix: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? CupertinoIcons.eye
                                  : CupertinoIcons.eye_slash,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return l10n.pleaseEnterPassword;
                            }
                            return null;
                          },
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _advancedExpander(theme),
                    if (_showAdvancedOptions) ...[
                      const SizedBox(height: 16),
                      _groupCard(_advancedChildren(theme, l10n)),
                    ],
                    const SizedBox(height: 24),
                    _buildErrorCard(theme),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.appleMusicRed,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          elevation: 0,
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                l10n.connect,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  // ── 分组卡片 / 字段 ────────────────────────────────────────────────

  Widget _groupTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: _isDark ? AppTheme.darkSecondaryText : AppTheme.lightSecondaryText,
        letterSpacing: 0.2,
      ),
    );
  }

  /// iOS inset-grouped 风格分组卡：白 / darkSurface、圆角 16、无阴影。
  /// 用 Material 而非 Container 作卡体，保证内部 ListTile 的 ink 水波
  /// 有 Material 祖先可绘制（Container+ClipRRect 会导致水波被 DecoratedBox
  /// 遮住并触发框架断言）。
  Widget _groupCard(List<Widget> children) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }

  /// 高级选项区行间分隔线：通栏无缩进（该区为纯文本行/区块，无左对齐图标）。
  Widget _advancedDivider() {
    return Container(
      height: 0.5,
      color: _isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
    );
  }

  /// 填充式无边框输入框（Apple Music 风），圆角 12、底色浅灰/深灰。
  InputDecoration _filledDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: _isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _urlField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    String? hint,
    bool autocorrect = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onFieldSubmitted,
    FormFieldValidator<String>? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        autocorrect: autocorrect,
        textInputAction: textInputAction,
        onFieldSubmitted: onFieldSubmitted,
        // resize:false 下键盘不挤压窗口：聚焦时把字段滚到键盘上方，
        // 默认 scrollPadding(20) 只会滚到屏幕底、被键盘盖住。
        scrollPadding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        decoration: _filledDecoration(label: label, hint: hint, icon: icon),
        validator: validator,
      ),
    );
  }

  Widget _serverTypeTile() {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.dns_rounded,
          color: Theme.of(context).colorScheme.primary,
          size: 18,
        ),
      ),
      title: Text(l10n.serverType, style: const TextStyle(fontSize: 16)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _serverFamilyLabel,
            style: TextStyle(
              fontSize: 13,
              color:
                  _isDark
                      ? AppTheme.darkSecondaryText
                      : AppTheme.lightSecondaryText,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            CupertinoIcons.chevron_right,
            size: 16,
            color:
                _isDark
                    ? AppTheme.darkSecondaryText
                    : AppTheme.lightSecondaryText,
          ),
        ],
      ),
      onTap: _showServerTypeSheet,
    );
  }

  // ── 高级选项 ────────────────────────────────────────────────────────

  Widget _advancedExpander(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: () {
        setState(() => _showAdvancedOptions = !_showAdvancedOptions);
      },
      child: Row(
        children: [
          Icon(
            _showAdvancedOptions
                ? CupertinoIcons.chevron_down
                : CupertinoIcons.chevron_right,
            size: 18,
            color: theme.textTheme.bodyMedium?.color,
          ),
          const SizedBox(width: 8),
          Text(
            l10n.advancedOptions,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _advancedChildren(ThemeData theme, AppLocalizations l10n) {
    return [
      _switchRow(
        title: l10n.legacyAuthentication,
        subtitle: l10n.legacyAuthSubtitle,
        value: _useLegacyAuth,
        onChanged: _serverFamily == 'daoliyu' ? null : (v) => setState(() => _useLegacyAuth = v),
      ),
      _advancedDivider(),
      _switchRow(
        title: l10n.allowSelfSignedCerts,
        subtitle: l10n.allowSelfSignedSubtitle,
        value: _allowSelfSignedCertificates,
        onChanged: (v) => setState(() => _allowSelfSignedCertificates = v),
      ),
      _advancedDivider(),
      _certSection(
        title: l10n.customTlsCertificate,
        subtitle: l10n.customCertificateSubtitle,
        fileName: _customCertificateName,
        onPick: _pickCertificateFile,
        onClear: () => setState(() {
          _customCertificatePath = null;
          _customCertificateName = null;
        }),
        selectLabel: l10n.selectCertificateFile,
        icon: CupertinoIcons.doc_fill,
      ),
      _advancedDivider(),
      _clientCertSection(theme, l10n),
      _advancedDivider(),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextFormField(
          controller: _profileNameController,
          autocorrect: false,
          scrollPadding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          decoration: _filledDecoration(
            label: l10n.profileNameLabel,
            hint: l10n.profileNameHint,
            icon: CupertinoIcons.tag,
          ),
        ),
      ),
    ];
  }

  Widget _switchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: _isDark
                        ? AppTheme.darkSecondaryText
                        : AppTheme.lightSecondaryText,
                  ),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeTrackColor: AppTheme.appleMusicRed,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  /// 自定义 TLS 证书 / 客户端证书共用的「标题 + 说明 + 选择文件」区块。
  Widget _certSection({
    required String title,
    required String subtitle,
    required String? fileName,
    required VoidCallback onPick,
    required VoidCallback onClear,
    required String selectLabel,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: _isDark
                  ? AppTheme.darkSecondaryText
                  : AppTheme.lightSecondaryText,
            ),
          ),
          const SizedBox(height: 12),
          if (fileName != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isDark ? const Color(0xFF3C3C3E) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isDark
                      ? AppTheme.darkDivider
                      : AppTheme.lightDivider,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: AppTheme.appleMusicRed),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      fileName,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      size: 20,
                    ),
                    onPressed: onClear,
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onPick,
                icon: Icon(icon),
                label: Text(selectLabel),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.appleMusicRed,
                  side: BorderSide(
                    color: AppTheme.appleMusicRed.withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _clientCertSection(ThemeData theme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.clientCertificate,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.clientCertificateSubtitle,
            style: TextStyle(
              fontSize: 12,
              color: _isDark
                  ? AppTheme.darkSecondaryText
                  : AppTheme.lightSecondaryText,
            ),
          ),
          const SizedBox(height: 12),
          if (_clientCertificateName != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isDark ? const Color(0xFF3C3C3E) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isDark
                      ? AppTheme.darkDivider
                      : AppTheme.lightDivider,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.security_rounded,
                    size: 20,
                    color: AppTheme.appleMusicRed,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _clientCertificateName!,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _clientCertificatePath = null;
                        _clientCertificateName = null;
                        _clientCertPasswordController.clear();
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _clientCertPasswordController,
              obscureText: _obscureClientCertPassword,
              // 与其它输入框一致：resize:false 下聚焦时滚到键盘上方。
              scrollPadding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
              ),
              decoration: InputDecoration(
                hintText: l10n.clientCertPassword,
                prefixIcon: const Icon(CupertinoIcons.lock, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureClientCertPassword
                        ? CupertinoIcons.eye
                        : CupertinoIcons.eye_slash,
                    size: 20,
                  ),
                  onPressed: () => setState(() {
                    _obscureClientCertPassword =
                        !_obscureClientCertPassword;
                  }),
                ),
                isDense: true,
                filled: true,
                fillColor: _isDark
                    ? const Color(0xFF1C1C1E)
                    : const Color(0xFFF2F2F7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickClientCertificate,
                icon: const Icon(Icons.security_rounded),
                label: Text(l10n.selectClientCertificate),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.appleMusicRed,
                  side: BorderSide(
                    color: AppTheme.appleMusicRed.withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── 错误卡（沿用旧登录页的分类提示） ─────────────────────────────────

  _LoginErrorType _categoriseError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('ssl') ||
        lower.contains('certificate') ||
        lower.contains('handshake') ||
        lower.contains('tls')) {
      return _LoginErrorType.ssl;
    }
    if (lower.contains('invalid username') ||
        lower.contains('wrong password') ||
        lower.contains('unauthorized') ||
        lower.contains('401')) {
      return _LoginErrorType.credentials;
    }
    if (lower.contains('not found') ||
        lower.contains('404') ||
        lower.contains('url path')) {
      return _LoginErrorType.notFound;
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return _LoginErrorType.timeout;
    }
    if (lower.contains('cannot connect') ||
        lower.contains('connection refused') ||
        lower.contains('network') ||
        lower.contains('socket')) {
      return _LoginErrorType.connection;
    }
    if (lower.contains('url format') || lower.contains('http')) {
      return _LoginErrorType.format;
    }
    return _LoginErrorType.generic;
  }

  Widget _buildErrorCard(ThemeData theme) {
    final error = _loginError;
    if (error == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;

    final type = _categoriseError(error);

    IconData icon;
    Color color;
    String? hint;

    switch (type) {
      case _LoginErrorType.ssl:
        icon = CupertinoIcons.lock_slash;
        color = const Color(0xFFFF9500);
        if (!_allowSelfSignedCertificates) {
          hint = l10n.enableSelfSignedCertsHint;
        }
      case _LoginErrorType.credentials:
        icon = CupertinoIcons.person_badge_minus;
        color = AppTheme.appleMusicRed;
        hint = l10n.checkCredentialsHint;
      case _LoginErrorType.notFound:
        icon = CupertinoIcons.question_circle;
        color = const Color(0xFFFF9500);
        hint = l10n.verifyServerUrlHint;
      case _LoginErrorType.timeout:
        icon = CupertinoIcons.timer;
        color = const Color(0xFFFF9500);
        hint = l10n.serverTimeoutHint;
      case _LoginErrorType.connection:
        icon = CupertinoIcons.wifi_slash;
        color = const Color(0xFFFF9500);
        hint = null;
      case _LoginErrorType.format:
        icon = CupertinoIcons.link;
        color = const Color(0xFFFF9500);
        hint = l10n.serverUrlMustStartWith;
      case _LoginErrorType.generic:
        icon = CupertinoIcons.exclamationmark_triangle;
        color = AppTheme.appleMusicRed;
        hint = null;
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: SelectableText(
                    error,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: color.withValues(alpha: 0.7),
                  ),
                  tooltip: l10n.copyError,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: error));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.errorCopiedToClipboard),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                        width: 260,
                      ),
                    );
                  },
                ),
              ],
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
            if (type == _LoginErrorType.ssl &&
                !_allowSelfSignedCertificates) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _allowSelfSignedCertificates = true;
                      _loginError = null;
                    });
                  },
                  child: Text(
                    Platform.isIOS || Platform.isAndroid
                        ? l10n.tapToEnableSelfSignedCerts
                        : l10n.clickToEnableSelfSignedCerts,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: color,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
