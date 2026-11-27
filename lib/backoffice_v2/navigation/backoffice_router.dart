import 'package:flutter/material.dart';

import '../auth/backoffice_session.dart';
import 'backoffice_route.dart';

class BackofficeRouteParser extends RouteInformationParser<BackofficeRoute> {
  const BackofficeRouteParser();

  @override
  Future<BackofficeRoute> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    return BackofficeRoute.parse(routeInformation.uri.path);
  }

  @override
  RouteInformation restoreRouteInformation(BackofficeRoute configuration) {
    return RouteInformation(uri: Uri.parse(configuration.location));
  }
}

class BackofficeRouterDelegate extends RouterDelegate<BackofficeRoute>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<BackofficeRoute> {
  BackofficeRouterDelegate({
    required this.session,
    required this.loginBuilder,
    required this.shellBuilder,
  }) : navigatorKey = GlobalKey<NavigatorState>() {
    session.addListener(_onSessionChanged);
  }

  final BackofficeSession session;
  final Widget Function(BuildContext context) loginBuilder;
  final Widget Function(
    BuildContext context,
    BackofficeRoute route,
    ValueChanged<BackofficeRoute> onNavigate,
  )
  shellBuilder;

  @override
  final GlobalKey<NavigatorState> navigatorKey;

  BackofficeRoute _requestedRoute = const BackofficeRoute.section(
    BackofficeSection.dashboard,
  );

  void _onSessionChanged() {
    notifyListeners();
  }

  @override
  BackofficeRoute get currentConfiguration {
    if (!session.isAuthenticated) {
      return const BackofficeRoute.login();
    }
    if (_requestedRoute.isLogin) {
      return const BackofficeRoute.section(BackofficeSection.dashboard);
    }
    return _requestedRoute;
  }

  void navigate(BackofficeRoute route) {
    if (_requestedRoute == route) return;
    _requestedRoute = route;
    notifyListeners();
  }

  @override
  Future<void> setNewRoutePath(BackofficeRoute configuration) async {
    if (!configuration.isLogin) {
      _requestedRoute = configuration;
    }
  }

  @override
  Widget build(BuildContext context) {
    final effective = currentConfiguration;

    return Navigator(
      key: navigatorKey,
      pages: [
        if (effective.isLogin)
          MaterialPage<void>(
            key: const ValueKey('login'),
            child: loginBuilder(context),
          )
        else
          MaterialPage<void>(
            key: const ValueKey('shell'),
            child: shellBuilder(context, effective, navigate),
          ),
      ],
      onDidRemovePage: (page) {},
    );
  }

  @override
  void dispose() {
    session.removeListener(_onSessionChanged);
    super.dispose();
  }
}
