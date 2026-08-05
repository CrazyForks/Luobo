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
  ///
  /// [dwellMs]：页面驻留时长（pop 后实测）；
  /// [transitionMs]：转场动画实际耗时（动画完成时实测，掉帧会拖长，
  ///   如进入全屏页配置 400ms 动画，卡顿时 >400ms）；
  /// [dragOffset]/[velocity]：手势触发式返回（如下拉隐藏）的滑动参数。
  static void transition({
    required String from,
    required String to,
    int? dwellMs,
    int? transitionMs,
    double? dragOffset,
    double? velocity,
  }) {
    DiagnosticsService.instance.record(
      EventType.navTransition,
      LogLevel.info,
      {
        'from': from,
        'to': to,
        if (dwellMs != null) 'dwellMs': dwellMs,
        if (transitionMs != null) 'transitionMs': transitionMs,
        if (dragOffset != null) 'dragOffset': dragOffset.round(),
        if (velocity != null) 'velocity': velocity.round(),
      },
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
