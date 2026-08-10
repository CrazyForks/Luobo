import 'package:flutter/material.dart';
import '../models/server_config.dart';
import 'server_form_screen.dart';
import 'server_gateway_screen.dart';

/// 登录入口（兼容旧调用点语义，实现已拆分到新文件）：
///
/// - [LoginScreen()]：登录网关页（第 1 步，我的服务器卡片列表 + 添加入口）
///   —— 首次启动由 `AuthWrapper`（main.dart）挂载为根路由。
/// - [LoginScreen(initialConfig:)]：直接进连接表单页（第 2 步，编辑模式），
///   预填已有配置，保存后 pop 回来源页。
///
/// 旧实现保留在 `login_screen_v1.dart`（一行回退：改回 import 即可）。
class LoginScreen extends StatelessWidget {
  final ServerConfig? initialConfig;

  const LoginScreen({super.key, this.initialConfig});

  @override
  Widget build(BuildContext context) {
    if (initialConfig != null) {
      return ServerFormScreen(initialConfig: initialConfig);
    }
    return const ServerGatewayScreen();
  }
}
