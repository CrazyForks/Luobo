import 'package:flutter/material.dart';

import 'diagnostics_service.dart';
import 'event_types.dart';

/// 路由观察者：记录当前路由（供 frame.jank 等事件携带上下文），
/// 并记录页面切换事件。
class DiagnosticsRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    DiagnosticsService.instance.setCurrentRoute(_name(route));
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    DiagnosticsService.instance
        .setCurrentRoute(previousRoute == null ? 'none' : _name(previousRoute));
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      DiagnosticsService.instance.setCurrentRoute(_name(newRoute));
    }
  }

  /// 记录一次页面切换（由业务侧在 push/pop 前后调用）。
  /// [dwellMs] 为页面驻留时长（pop 后实测），非转场动画耗时。
  static void transition({
    required String from,
    required String to,
    required int dwellMs,
  }) {
    DiagnosticsService.instance.record(
      EventType.navTransition,
      LogLevel.info,
      {'from': from, 'to': to, 'dwellMs': dwellMs},
      sessionId: 'app',
    );
  }

  String _name(Route<dynamic> route) {
    final settings = route.settings;
    if (settings.name != null && settings.name!.isNotEmpty) {
      return settings.name!;
    }
    final clazz = route.runtimeType.toString();
    return clazz.replaceFirst('Route', '');
  }
}
