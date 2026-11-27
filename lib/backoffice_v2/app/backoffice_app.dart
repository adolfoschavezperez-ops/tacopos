import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/backoffice_auth_service.dart';
import '../auth/backoffice_session.dart';
import '../auth/login_page.dart';
import '../core/cache/backoffice_cache_scope.dart';
import '../core/design/backoffice_theme.dart';
import '../core/env/backoffice_env.dart';
import '../core/preview/preview_api_client.dart';
import '../features/audit/audit_page.dart';
import '../features/audit/audit_repository.dart';
import '../features/authorizations/authorizations_page.dart';
import '../features/authorizations/authorizations_repository.dart';
import '../features/cash/cash_page.dart';
import '../features/cash/cash_repository.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/dashboard/dashboard_repository.dart';
import '../features/employees/employees_page.dart';
import '../features/employees/employees_repository.dart';
import '../features/finance/finance_page.dart';
import '../features/finance/finance_repository.dart';
import '../features/inventory/inventory_page.dart';
import '../features/inventory/inventory_repository.dart';
import '../features/purchases/purchases_page.dart';
import '../features/purchases/purchases_repository.dart';
import '../features/reports/reports_page.dart';
import '../features/reports/reports_repository.dart';
import '../features/sales/sale_detail_page.dart';
import '../features/sales/sales_list_page.dart';
import '../features/sales/sales_repository.dart';
import '../features/settings/settings_page.dart';
import '../features/settings/settings_repository.dart';
import '../navigation/app_shell.dart';
import '../navigation/backoffice_route.dart';
import '../navigation/backoffice_router.dart';
import '../widgets/empty_error_state.dart';

class BackofficeV2App extends StatefulWidget {
  const BackofficeV2App({super.key, required this.config});

  final BackofficeConfig config;

  @override
  State<BackofficeV2App> createState() => _BackofficeV2AppState();
}

class _BackofficeV2AppState extends State<BackofficeV2App>
    with WidgetsBindingObserver {
  late final BackofficeSession _session;
  late final BackofficeCacheScope _cacheScope;
  late final BackofficeV2AuthService _authService;
  late final DashboardRepository _dashboardRepository;
  late final SalesRepository _salesRepository;
  late final CashRepository _cashRepository;
  late final AuthorizationsRepository _authorizationsRepository;
  late final InventoryRepository _inventoryRepository;
  late final PurchasesRepository _purchasesRepository;
  late final FinanceRepository _financeRepository;
  late final ReportsRepository _reportsRepository;
  late final AuditRepository _auditRepository;
  late final EmployeesRepository _employeesRepository;
  late final SettingsRepository _settingsRepository;
  late final BackofficeRouterDelegate _routerDelegate;
  final BackofficeRouteParser _routeParser = const BackofficeRouteParser();
  StreamSubscription<User?>? _authSub;
  bool _restoringSession = true;
  bool _explicitSignOut = false;
  final SessionRenewalGuard _sessionGuard = SessionRenewalGuard();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = BackofficeSession(config: widget.config);
    _cacheScope = BackofficeCacheScope();
    _session.addListener(_syncCacheScope);
    final previewClient = widget.config.isPreview
        ? PreviewApiClient(baseUrl: widget.config.previewApiUrl)
        : null;
    _authService = BackofficeV2AuthService(
      config: widget.config,
      previewClient: previewClient,
    );
    _dashboardRepository = DashboardRepository(
      cacheScope: _cacheScope,
      previewClient: previewClient,
    );
    _salesRepository = SalesRepository(
      previewClient: previewClient,
      isReadOnly: widget.config.isReadOnly,
    );
    _cashRepository = CashRepository(
      previewClient: previewClient,
      isReadOnly: widget.config.isReadOnly,
    );
    _authorizationsRepository = AuthorizationsRepository();
    _inventoryRepository = InventoryRepository();
    _purchasesRepository = PurchasesRepository(
      previewClient: previewClient,
      isReadOnly: widget.config.isReadOnly,
    );
    _financeRepository = FinanceRepository(
      cacheScope: _cacheScope,
      previewClient: previewClient,
      isReadOnly: widget.config.isReadOnly,
    );
    _reportsRepository = ReportsRepository(cacheScope: _cacheScope);
    _auditRepository = AuditRepository();
    _employeesRepository = EmployeesRepository(
      isReadOnly: widget.config.isReadOnly,
    );
    _settingsRepository = SettingsRepository();
    _routerDelegate = BackofficeRouterDelegate(
      session: _session,
      loginBuilder: (context) => BackofficeLoginPage(
        session: _session,
        authService: _authService,
      ),
      shellBuilder: (context, route, onNavigate) => BackofficeAppShell(
        session: _session,
        currentRoute: route,
        onNavigate: onNavigate,
        onSignOut: () async {
          _explicitSignOut = true;
          _cacheScope.resetSession();
          await _authService.signOut();
          _session.signOut();
        },
        child: _buildSection(route, onNavigate),
      ),
    );
    _restoreSession();
    _authSub = FirebaseAuth.instance.idTokenChanges().listen((user) {
      if (!_restoringSession && user == null && _session.isAuthenticated) {
        final notice = _explicitSignOut
            ? null
            : 'Tu sesión expiró o fue revocada. Inicia sesión nuevamente.';
        _explicitSignOut = false;
        _cacheScope.resetSession();
        _session.signOut(notice: notice);
      }
    });
  }

  void _syncCacheScope() {
    if (!_session.isAuthenticated) {
      _cacheScope.resetSession();
      return;
    }
    final emp = _session.employee;
    final permFp = emp == null
        ? ''
        : '${_session.isSuperAdmin}|${emp.currentPermissionsMap.entries.where((e) => e.value).map((e) => e.key).join(",")}';
    _cacheScope.updateContext(
      userId: emp?.id ?? '',
      restaurantId: _session.restaurantId,
      branchId: _session.selectedBranchId ?? 'all',
      permissionsFingerprint: permFp,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verifyActiveSessionIfNeeded();
    }
  }

  Future<void> _verifyActiveSessionIfNeeded() async {
    if (_restoringSession || !_session.isAuthenticated) return;
    final stillActive = await _sessionGuard.runGuarded(
      () => _authService.verifyActiveSession(
        restaurantId: _session.restaurantId,
      ),
    );
    if (stillActive == null || !mounted || stillActive || !_session.isAuthenticated) {
      return;
    }
    _cacheScope.resetSession();
    _session.signOut(
      notice: 'Tu sesión expiró o fue revocada. Inicia sesión nuevamente.',
    );
  }

  Future<void> _restoreSession() async {
    final result = await _authService.restoreSessionIfSignedIn(
      restaurantId: widget.config.defaultRestaurantId,
    );
    if (!mounted) return;
    if (result != null) {
      _session.signIn(
        employee: result.employee,
        isSuperAdmin: result.isSuperAdmin,
        restaurantId: result.restaurantId,
        restaurantName: result.restaurantName,
        branches: result.branches,
      );
    }
    setState(() => _restoringSession = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_syncCacheScope);
    _authSub?.cancel();
    _routerDelegate.dispose();
    _session.dispose();
    super.dispose();
  }

  Widget _buildSection(
    BackofficeRoute route,
    ValueChanged<BackofficeRoute> onNavigate,
  ) {
    if (!_session.permissions.canViewSection(route.section)) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: SaasEmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Sin permisos para esta sección',
          message:
              'Tu perfil actual no cuenta con autorización para consultar este módulo.',
        ),
      );
    }

    if (route.saleId != null && route.saleId!.isNotEmpty) {
      return SaleDetailPage(
        session: _session,
        repository: _salesRepository,
        orderId: route.saleId!,
        onBack: () =>
            onNavigate(const BackofficeRoute.section(BackofficeSection.sales)),
      );
    }

    return switch (route.section) {
      BackofficeSection.dashboard => DashboardPage(
        session: _session,
        repository: _dashboardRepository,
        onOpenSaleDetail: (id) => onNavigate(BackofficeRoute.saleDetail(id)),
        onOpenAllSales: () =>
            onNavigate(const BackofficeRoute.section(BackofficeSection.sales)),
      ),
      BackofficeSection.sales => SalesListPage(
        session: _session,
        repository: _salesRepository,
        onSelectSale: (id) => onNavigate(BackofficeRoute.saleDetail(id)),
      ),
      BackofficeSection.cash => CashPage(
        session: _session,
        repository: _cashRepository,
        onOpenSaleDetail: (id) => onNavigate(BackofficeRoute.saleDetail(id)),
      ),
      BackofficeSection.authorizations => AuthorizationsPage(
        session: _session,
        repository: _authorizationsRepository,
      ),
      BackofficeSection.purchases => PurchasesPage(
        session: _session,
        repository: _purchasesRepository,
      ),
      BackofficeSection.inventory => InventoryPage(
        session: _session,
        repository: _inventoryRepository,
      ),
      BackofficeSection.finance => FinancePage(
        session: _session,
        repository: _financeRepository,
        onOpenSaleDetail: (id) => onNavigate(BackofficeRoute.saleDetail(id)),
      ),
      BackofficeSection.reports => ReportsPage(
        session: _session,
        repository: _reportsRepository,
        onOpenSaleDetail: (id) => onNavigate(BackofficeRoute.saleDetail(id)),
      ),
      BackofficeSection.employees => EmployeesPage(
        session: _session,
        repository: _employeesRepository,
        onOpenSaleDetail: (id) => onNavigate(BackofficeRoute.saleDetail(id)),
      ),
      BackofficeSection.audit => AuditPage(
        session: _session,
        repository: _auditRepository,
        onOpenSaleDetail: (id) => onNavigate(BackofficeRoute.saleDetail(id)),
      ),
      BackofficeSection.settings => SettingsPage(
        session: _session,
        repository: _settingsRepository,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _session,
      builder: (context, _) {
        if (_restoringSession) {
          return MaterialApp(
            title: 'TacoPOS Backoffice 2.0 (${widget.config.badgeLabel})',
            debugShowCheckedModeBanner: false,
            theme: BackofficeTheme.light(),
            darkTheme: BackofficeTheme.dark(),
            themeMode: _session.themeMode,
            home: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            ),
          );
        }
        return MaterialApp.router(
          title: 'TacoPOS Backoffice 2.0 (${widget.config.badgeLabel})',
          debugShowCheckedModeBanner: false,
          theme: BackofficeTheme.light(),
          darkTheme: BackofficeTheme.dark(),
          themeMode: _session.themeMode,
          routerDelegate: _routerDelegate,
          routeInformationParser: _routeParser,
        );
      },
    );
  }
}
