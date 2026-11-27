import 'package:flutter/material.dart';

import '../auth/backoffice_auth_service.dart';
import '../auth/backoffice_session.dart';
import '../auth/login_page.dart';
import '../core/design/backoffice_theme.dart';
import '../core/env/backoffice_env.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/dashboard/dashboard_repository.dart';
import '../features/placeholders/module_stub_page.dart';
import '../features/sales/sale_detail_page.dart';
import '../features/sales/sales_list_page.dart';
import '../features/sales/sales_repository.dart';
import '../navigation/app_shell.dart';
import '../navigation/backoffice_route.dart';
import '../navigation/backoffice_router.dart';

class BackofficeV2App extends StatefulWidget {
  const BackofficeV2App({super.key, required this.config});

  final BackofficeConfig config;

  @override
  State<BackofficeV2App> createState() => _BackofficeV2AppState();
}

class _BackofficeV2AppState extends State<BackofficeV2App> {
  late final BackofficeSession _session;
  late final BackofficeV2AuthService _authService;
  late final DashboardRepository _dashboardRepository;
  late final SalesRepository _salesRepository;
  late final BackofficeRouterDelegate _routerDelegate;
  final BackofficeRouteParser _routeParser = const BackofficeRouteParser();
  bool _restoringSession = true;

  @override
  void initState() {
    super.initState();
    _session = BackofficeSession(config: widget.config);
    _authService = BackofficeV2AuthService(config: widget.config);
    _dashboardRepository = DashboardRepository();
    _salesRepository = SalesRepository();
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
          await _authService.signOut();
          _session.signOut();
        },
        child: _buildSection(route, onNavigate),
      ),
    );
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final result = await _authService.restoreSessionIfSignedIn(
      restaurantId: widget.config.defaultRestaurantId,
    );
    if (!mounted) return;
    if (result != null) {
      _session.signIn(
        employee: result.employee,
        restaurantId: result.restaurantId,
        restaurantName: result.restaurantName,
        branches: result.branches,
      );
    }
    setState(() => _restoringSession = false);
  }

  @override
  void dispose() {
    _routerDelegate.dispose();
    _session.dispose();
    super.dispose();
  }

  Widget _buildSection(
    BackofficeRoute route,
    ValueChanged<BackofficeRoute> onNavigate,
  ) {
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
      BackofficeSection.cash => const ModuleStubPage(
        section: BackofficeSection.cash,
        targetPhase: 'Fase 3',
        description:
            'Cortes de caja, retiros y auditoría de diferencias acotada por sucursal.',
        plannedCapabilities: [
          'Consulta de cortes por fecha operativa sin lecturas globales.',
          'Auditoría de diferencias multi-tenant segura (reemplazo de collectionGroup sin filtro).',
          'Autorización y trazabilidad de retiros de efectivo.',
        ],
      ),
      BackofficeSection.purchases => const ModuleStubPage(
        section: BackofficeSection.purchases,
        targetPhase: 'Fase 4',
        description:
            'Proveedores, compras, cuentas por pagar (CXP), pagos y kardex.',
        plannedCapabilities: [
          'Paginación real en servidor mediante cursores (reemplazo de LocalPage).',
          'Estado de cuenta por proveedor y vencimientos CXP.',
          'Exportación completa independiente de la página visible.',
        ],
      ),
      BackofficeSection.inventory => const ModuleStubPage(
        section: BackofficeSection.inventory,
        targetPhase: 'Fase 3',
        description:
            'Control de cocina, mermas, recetas y existencias por sucursal.',
        plannedCapabilities: [
          'Sesiones de apertura/cierre de cocina.',
          'Rendimiento y costo unitario por receta.',
        ],
      ),
      BackofficeSection.finance => const ModuleStubPage(
        section: BackofficeSection.finance,
        targetPhase: 'Fase 4',
        description:
            'Dashboard financiero consolidado, flujo de efectivo y comparativo semanal.',
        plannedCapabilities: [
          'Comparativo multi-sucursal bajo demanda.',
          'Aportaciones de socios y conciliación de ingresos vs egresos.',
        ],
      ),
      BackofficeSection.reports => const ModuleStubPage(
        section: BackofficeSection.reports,
        targetPhase: 'Fase 4',
        description:
            'Catálogo de 25 reportes operativos, de ventas y auditorías.',
        plannedCapabilities: [
          'Migración progresiva con fórmulas canónicas intactas.',
          'Exportaciones CSV y Excel optimizadas.',
        ],
      ),
      BackofficeSection.employees => const ModuleStubPage(
        section: BackofficeSection.employees,
        targetPhase: 'Fase 5',
        description: 'Catálogo de empleados, roles y permisos por sucursal.',
        plannedCapabilities: [
          'Administración de accesos multi-sucursal y authUsers.',
        ],
      ),
      BackofficeSection.audit => const ModuleStubPage(
        section: BackofficeSection.audit,
        targetPhase: 'Fase 5',
        description: 'Bitácora de actividad (activityLog) y auditorías de integridad.',
        plannedCapabilities: [
          'Consulta acotada y paginada por fecha y sucursal.',
        ],
      ),
      BackofficeSection.settings => const ModuleStubPage(
        section: BackofficeSection.settings,
        targetPhase: 'Fase 5',
        description:
            'Catálogos de productos, categorías, mesas, plataformas y políticas.',
        plannedCapabilities: [
          'Configuración multi-tenant y preferencias de sucursal.',
        ],
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
