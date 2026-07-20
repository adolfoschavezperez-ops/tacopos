import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/cash_session.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../models/product.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/csv_exporter.dart';
import '../../utils/formatters.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';
import '../cash/cash_session_screen.dart';
import 'branch_catalog_screen.dart';
import 'cash_admin_screen.dart';
import 'employee_catalog_screen.dart';
import 'kitchen_admin_screen.dart';
import 'order_platform_catalog_screen.dart';
import 'product_catalog_screen.dart';
import 'table_catalog_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late DateTime _startDate;
  late DateTime _endDate;
  late DateTime _hourlyBaseDate;
  _HourlyReportMode _hourlyReportMode = _HourlyReportMode.yesterdayVsLastSales;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = _startDate;
    _hourlyBaseDate = _startDate.subtract(const Duration(days: 1));
  }

  String get _startBusinessDate => DateFormat('yyyy-MM-dd').format(_startDate);
  String get _endBusinessDate => DateFormat('yyyy-MM-dd').format(_endDate);

  String get _rangeLabel {
    if (_startBusinessDate == _endBusinessDate) {
      return _isTodayDate(_startDate) ? 'Hoy' : _startBusinessDate;
    }
    return '$_startBusinessDate a $_endBusinessDate';
  }

  Future<void> _pickStartDate() async {
    final picked = await _pickDate(_startDate);
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _startDate = picked;
      if (_endDate.isBefore(_startDate)) {
        _endDate = _startDate;
      }
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await _pickDate(_endDate);
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _endDate = picked;
      if (_startDate.isAfter(_endDate)) {
        _startDate = _endDate;
      }
    });
  }

  Future<DateTime?> _pickDate(DateTime initialDate) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 2),
    );
  }

  void _resetToday() {
    final now = DateTime.now();
    setState(() {
      _startDate = DateTime(now.year, now.month, now.day);
      _endDate = _startDate;
    });
  }

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();
    final employee = AppSession.instance.employee;

    final canAccessBackoffice =
        employee?.hasAdminAccess == true ||
        employee?.canManageCash == true ||
        employee?.canViewKitchenReports == true ||
        employee?.canAuthorizeCashWithdrawals == true;

    if (!canAccessBackoffice) {
      return BrandedScaffold(
        title: kIsWeb ? 'TacoPOS Backoffice' : 'Socio / Admin',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: kIsWeb
              ? 'No tienes acceso al backoffice.'
              : 'No tienes permiso para ver admin.',
        ),
      );
    }

    return BrandedScaffold(
      title: kIsWeb ? 'TacoPOS Backoffice' : 'Socio / Admin',
      actions: [
        if (employee?.canManageTables == true)
          IconButton(
            tooltip: 'Mesas',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TableCatalogScreen()),
              );
            },
            icon: const Icon(Icons.table_restaurant),
          ),
        if (employee?.canManagePlatforms == true)
          IconButton(
            tooltip: 'Plataformas',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OrderPlatformCatalogScreen(),
                ),
              );
            },
            icon: const Icon(Icons.delivery_dining),
          ),
        if (employee?.canManageProducts == true)
          IconButton(
            tooltip: 'Productos',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProductCatalogScreen()),
              );
            },
            icon: const Icon(Icons.restaurant_menu),
          ),
        if (employee?.canManageCash == true ||
            employee?.hasAdminAccess == true ||
            employee?.canAuthorizeCashWithdrawals == true)
          IconButton(
            tooltip: 'Caja Admin',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CashAdminScreen()),
              );
            },
            icon: const Icon(Icons.point_of_sale_outlined),
          ),
        if (employee?.canViewKitchenReports == true ||
            employee?.canManageKitchenStock == true)
          IconButton(
            tooltip: 'Control de cocina',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const KitchenAdminScreen()),
              );
            },
            icon: const Icon(Icons.soup_kitchen_outlined),
          ),
        if (employee?.canManageEmployees == true)
          IconButton(
            tooltip: 'Empleados',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const EmployeeCatalogScreen(),
                ),
              );
            },
            icon: const Icon(Icons.badge_outlined),
          ),
        if (employee?.hasAdminAccess == true)
          IconButton(
            tooltip: 'Sucursales',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BranchCatalogScreen()),
              );
            },
            icon: const Icon(Icons.storefront_outlined),
          ),
      ],
      body: StreamBuilder<List<PosOrder>>(
        stream: repository.watchAllOrders(),
        builder: (context, ordersSnapshot) {
          if (ordersSnapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudieron cargar ordenes',
              message: '${ordersSnapshot.error}',
            );
          }

          if (ordersSnapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Cargando dashboard...');
          }

          final orders = ordersSnapshot.data ?? [];

          return StreamBuilder<List<Payment>>(
            stream: repository.watchDashboardPayments(
              startDate: _startDate,
              endDate: _endDate,
            ),
            builder: (context, paymentsSnapshot) {
              if (paymentsSnapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudieron cargar pagos',
                  message: '${paymentsSnapshot.error}',
                );
              }
              if (paymentsSnapshot.connectionState == ConnectionState.waiting &&
                  !paymentsSnapshot.hasData) {
                return const LoadingPanel(message: 'Cargando dashboard...');
              }

              final payments = _paymentsInRange(paymentsSnapshot.data ?? []);
              final baseSales = payments.fold<double>(
                0,
                (runningTotal, payment) => runningTotal + payment.baseAmount,
              );
              final cash = _baseByMethod(payments, 'cash');
              final cardBase = _baseByMethod(payments, 'card');
              final cardFeeAbsorbed = payments
                  .where((payment) => payment.method == 'card')
                  .fold<double>(
                    0,
                    (runningTotal, payment) =>
                        runningTotal + payment.cardFeeAbsorbedAmount,
                  );
              final cardCharged = payments
                  .where((payment) => payment.method == 'card')
                  .fold<double>(
                    0,
                    (runningTotal, payment) =>
                        runningTotal + payment.chargedAmount,
                  );
              final cardNetEstimated = cardCharged - cardFeeAbsorbed;
              final employeeConsumption = _baseByMethod(
                payments,
                'employee_consumption',
              );
              final platformPaid = _baseByMethod(payments, 'platform_paid');
              final didiPaid = _platformTotal(payments, 'didi');
              final uberPaid = _platformTotal(payments, 'uber');
              final rappiPaid = _platformTotal(payments, 'rappi');
              final realCharged = payments.fold<double>(
                0,
                (runningTotal, payment) => runningTotal + payment.chargedAmount,
              );
              final ordersInRange = orders
                  .where((order) => _orderTouchesRange(order))
                  .toList();
              final paidOrders = ordersInRange
                  .where(
                    (order) =>
                        order.status == 'paid' && _isInRange(order.paidAt),
                  )
                  .length;
              final openOrders = ordersInRange
                  .where((order) => order.status != 'paid')
                  .length;
              final partialOrders = ordersInRange
                  .where((order) => order.paymentStatus == 'partial')
                  .length;

              return StreamBuilder<List<Product>>(
                stream: repository.watchProducts(),
                builder: (context, productsSnapshot) {
                  if (productsSnapshot.hasError) {
                    return EmptyState(
                      icon: Icons.error_outline,
                      title: 'No se pudieron cargar productos',
                      message: '${productsSnapshot.error}',
                    );
                  }
                  if (productsSnapshot.connectionState ==
                          ConnectionState.waiting &&
                      !productsSnapshot.hasData) {
                    return const LoadingPanel(message: 'Cargando dashboard...');
                  }

                  final products = productsSnapshot.data ?? [];
                  final activeProducts = products
                      .where((product) => product.active)
                      .length;

                  return ListView(
                    padding: const EdgeInsets.all(22),
                    children: [
                      const SectionHeader(
                        title: 'Dashboard',
                        subtitle: 'Operacion por fecha seleccionada.',
                      ),
                      const SizedBox(height: 18),
                      _DashboardDateFilter(
                        label: _rangeLabel,
                        startBusinessDate: _startBusinessDate,
                        endBusinessDate: _endBusinessDate,
                        onPickStart: _pickStartDate,
                        onPickEnd: _pickEndDate,
                        onToday: _resetToday,
                      ),
                      const SizedBox(height: 14),
                      _CashStatusPanel(repository: repository),
                      const SizedBox(height: 14),
                      _HourlySalesComparisonPanel(
                        repository: repository,
                        orders: orders,
                        mode: _hourlyReportMode,
                        baseDate: _hourlyBaseDate,
                        onModeChanged: (mode) =>
                            setState(() => _hourlyReportMode = mode),
                        onBaseDateChanged: (date) =>
                            setState(() => _hourlyBaseDate = date),
                        onRefresh: () => setState(() {}),
                      ),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 900
                              ? 4
                              : constraints.maxWidth >= 560
                              ? 2
                              : 1;
                          return GridView.count(
                            crossAxisCount: columns,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: constraints.maxWidth >= 900
                                ? 1.6
                                : 1.25,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _MetricCard(
                                title: 'Ventas del dia',
                                icon: Icons.payments,
                                money: baseSales,
                                accent: BrandColors.accentYellow,
                              ),
                              _MetricCard(
                                title: 'Efectivo',
                                icon: Icons.attach_money,
                                money: cash,
                                accent: BrandColors.accentOrange,
                              ),
                              _MetricCard(
                                title: 'Tarjeta base',
                                icon: Icons.credit_card,
                                money: cardBase,
                                accent: BrandColors.success,
                              ),
                              _MetricCard(
                                title: 'Comision absorbida',
                                icon: Icons.percent,
                                money: cardFeeAbsorbed,
                                accent: BrandColors.info,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 900
                              ? 4
                              : constraints.maxWidth >= 560
                              ? 2
                              : 1;
                          return GridView.count(
                            crossAxisCount: columns,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: constraints.maxWidth >= 900
                                ? 1.8
                                : 1.35,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _MetricCard(
                                title: 'Total tarjeta',
                                icon: Icons.credit_score,
                                money: cardCharged,
                                accent: BrandColors.accentYellow,
                              ),
                              _MetricCard(
                                title: 'Neto tarjeta',
                                icon: Icons.account_balance_wallet_outlined,
                                money: cardNetEstimated,
                                accent: BrandColors.success,
                              ),
                              _MetricCard(
                                title: 'Consumo empleado',
                                icon: Icons.badge_outlined,
                                money: employeeConsumption,
                                accent: BrandColors.info,
                              ),
                              _MetricCard(
                                title: 'Pagado plataforma',
                                icon: Icons.delivery_dining,
                                money: platformPaid,
                                accent: BrandColors.accentOrange,
                              ),
                              _MetricCard(
                                title: 'Ordenes pagadas',
                                icon: Icons.check_circle_outline,
                                value: '$paidOrders',
                                accent: BrandColors.success,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 900
                              ? 4
                              : constraints.maxWidth >= 560
                              ? 2
                              : 1;
                          return GridView.count(
                            crossAxisCount: columns,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: constraints.maxWidth >= 900
                                ? 1.8
                                : 1.35,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _MetricCard(
                                title: 'Total plataforma',
                                icon: Icons.delivery_dining,
                                money: platformPaid,
                                accent: BrandColors.accentYellow,
                              ),
                              _MetricCard(
                                title: 'DiDi',
                                icon: Icons.two_wheeler,
                                money: didiPaid,
                                accent: BrandColors.info,
                              ),
                              _MetricCard(
                                title: 'Uber',
                                icon: Icons.local_taxi,
                                money: uberPaid,
                                accent: BrandColors.success,
                              ),
                              _MetricCard(
                                title: 'Rappi',
                                icon: Icons.shopping_bag_outlined,
                                money: rappiPaid,
                                accent: BrandColors.accentOrange,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 900
                              ? 2
                              : constraints.maxWidth >= 560
                              ? 2
                              : 1;
                          return GridView.count(
                            crossAxisCount: columns,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: constraints.maxWidth >= 900
                                ? 2.4
                                : 1.45,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _MetricCard(
                                title: 'Total cobrado real',
                                icon: Icons.point_of_sale,
                                money: realCharged,
                                accent: BrandColors.success,
                              ),
                              _MetricCard(
                                title: 'Ordenes abiertas',
                                icon: Icons.receipt_long,
                                value: '$openOrders',
                                accent: BrandColors.accentOrange,
                              ),
                              _MetricCard(
                                title: 'Ordenes parciales',
                                icon: Icons.pie_chart_outline,
                                value: '$partialOrders',
                                accent: BrandColors.info,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      if (!kIsWeb &&
                          (employee?.canManageCash == true ||
                              employee?.canCharge == true)) ...[
                        _AdminLinkPanel(
                          icon: Icons.point_of_sale_outlined,
                          iconColor: BrandColors.accentYellow,
                          title: 'Caja / Corte',
                          subtitle:
                              'Abrir dia, solicitar retiros y cerrar caja operativa.',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CashSessionScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (employee?.hasAdminAccess == true ||
                          employee?.canManageCash == true ||
                          employee?.canAuthorizeCashWithdrawals == true) ...[
                        _AdminLinkPanel(
                          icon: Icons.receipt_long,
                          iconColor: BrandColors.success,
                          title: 'Cortes y retiros',
                          subtitle:
                              'Ver desglose completo y autorizar retiros de efectivo.',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CashAdminScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (employee?.hasAdminAccess == true) ...[
                        _AdminLinkPanel(
                          icon: Icons.storefront_outlined,
                          iconColor: BrandColors.accentYellow,
                          title: 'Sucursales',
                          subtitle:
                              'Crear y editar sucursales del restaurante.',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const BranchCatalogScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (employee?.canViewKitchenReports == true ||
                          employee?.canManageKitchenStock == true) ...[
                        _AdminLinkPanel(
                          icon: Icons.soup_kitchen_outlined,
                          iconColor: BrandColors.info,
                          title: 'Control de cocina',
                          subtitle:
                              'Reporte de consumo, rendimiento e insumos controlados.',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const KitchenAdminScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (employee?.canManageTables == true) ...[
                        _AdminLinkPanel(
                          icon: Icons.table_restaurant,
                          iconColor: BrandColors.accentOrange,
                          title: 'Catalogo de mesas',
                          subtitle:
                              'Ver, agregar, editar y activar mesas fisicas y la entrada Para llevar.',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TableCatalogScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (employee?.canManagePlatforms == true) ...[
                        _AdminLinkPanel(
                          icon: Icons.delivery_dining,
                          iconColor: BrandColors.info,
                          title: 'Catalogo de plataformas',
                          subtitle:
                              'Configura canales para pedidos para llevar: En persona, DiDi, Uber o Rappi.',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const OrderPlatformCatalogScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (employee?.canManageProducts == true) ...[
                        GlassPanel(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: BrandColors.glassHighlight,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.restaurant_menu,
                                  color: BrandColors.accentYellow,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Catalogo de productos',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Ver, agregar, editar y activar productos del menu. $activeProducts activos.',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: BrandColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              GlassButton(
                                icon: Icons.arrow_forward,
                                label: 'Abrir',
                                prominent: true,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ProductCatalogScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (employee?.canManageEmployees == true) ...[
                        GlassPanel(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: BrandColors.glassHighlight,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.badge_outlined,
                                  color: BrandColors.info,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Catalogo de empleados',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Ver, agregar, editar y activar empleados para consumo empleado.',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: BrandColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              GlassButton(
                                icon: Icons.arrow_forward,
                                label: 'Abrir',
                                prominent: true,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const EmployeeCatalogScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      const SectionHeader(
                        title: 'Ordenes recientes',
                        subtitle: 'Ultimos movimientos registrados.',
                      ),
                      const SizedBox(height: 12),
                      if (orders.isEmpty)
                        const GlassPanel(
                          child: Text(
                            'Aun no hay ordenes. Abre una mesa desde Mesero / Caja.',
                            style: TextStyle(color: BrandColors.textMuted),
                          ),
                        )
                      else
                        ...ordersInRange
                            .take(8)
                            .map((order) => _RecentOrderTile(order: order)),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  List<Payment> _paymentsInRange(List<Payment> payments) {
    return payments.where((payment) {
      final businessDate = payment.businessDate;
      if (businessDate != null && businessDate.isNotEmpty) {
        return businessDate.compareTo(_startBusinessDate) >= 0 &&
            businessDate.compareTo(_endBusinessDate) <= 0;
      }
      return _isInRange(payment.createdAt);
    }).toList();
  }

  double _baseByMethod(List<Payment> payments, String method) {
    return payments
        .where((payment) => payment.method == method)
        .fold<double>(
          0,
          (runningTotal, payment) => runningTotal + payment.baseAmount,
        );
  }

  double _platformTotal(List<Payment> payments, String platformId) {
    return payments
        .where(
          (payment) =>
              payment.method == 'platform_paid' &&
              payment.platformId == platformId,
        )
        .fold<double>(
          0,
          (runningTotal, payment) => runningTotal + payment.baseAmount,
        );
  }

  bool _isInRange(DateTime? date) {
    if (date == null) {
      return false;
    }
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(_startDate) && !day.isAfter(_endDate);
  }

  bool _orderTouchesRange(PosOrder order) {
    return _isInRange(order.paidAt) ||
        _isInRange(order.createdAt) ||
        _isInRange(order.updatedAt);
  }

  bool _isTodayDate(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

class _DashboardDateFilter extends StatelessWidget {
  const _DashboardDateFilter({
    required this.label,
    required this.startBusinessDate,
    required this.endBusinessDate,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onToday,
  });

  final String label;
  final String startBusinessDate;
  final String endBusinessDate;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 180),
            child: Text(
              'Viendo: $label',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onPickStart,
            icon: const Icon(Icons.event_outlined),
            label: Text('Inicial: $startBusinessDate'),
          ),
          OutlinedButton.icon(
            onPressed: onPickEnd,
            icon: const Icon(Icons.event_available_outlined),
            label: Text('Final: $endBusinessDate'),
          ),
          TextButton.icon(
            onPressed: onToday,
            icon: const Icon(Icons.today_outlined),
            label: const Text('Hoy'),
          ),
        ],
      ),
    );
  }
}

class _CashStatusPanel extends StatelessWidget {
  const _CashStatusPanel({required this.repository});

  final TacoPosRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CashSession?>(
      stream: repository.watchOpenCashSession(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return GlassPanel(
            borderColor: BrandColors.danger,
            child: Text(
              'No se pudo cargar caja: ${snapshot.error}',
              style: const TextStyle(
                color: BrandColors.danger,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }

        final session = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const GlassPanel(
            child: Text(
              'Verificando estado de caja...',
              style: TextStyle(
                color: BrandColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }

        if (session == null) {
          return const GlassPanel(
            child: Row(
              children: [
                Icon(Icons.lock_outline, color: BrandColors.accentYellow),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Caja cerrada | sin fecha operativa abierta',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          );
        }

        return StreamBuilder<CashSessionTotals>(
          stream: repository.watchCashSessionTotals(session.id),
          builder: (context, totalsSnapshot) {
            if (totalsSnapshot.hasError) {
              return GlassPanel(
                borderColor: BrandColors.danger,
                child: Text(
                  'No se pudieron cargar totales de caja: ${totalsSnapshot.error}',
                  style: const TextStyle(
                    color: BrandColors.danger,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );
            }

            final totals = totalsSnapshot.data ?? const CashSessionTotals();
            return GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: 'Caja abierta',
                    subtitle: 'Fecha operativa ${session.businessDate}',
                    trailing: const Icon(
                      Icons.point_of_sale_outlined,
                      color: BrandColors.success,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 18,
                    runSpacing: 10,
                    children: [
                      _TinyMoney(
                        label: 'Efectivo',
                        value: totals.expectedCashAmount,
                      ),
                      _TinyMoney(
                        label: 'Tarjeta',
                        value: totals.expectedCardChargedAmount,
                      ),
                      _TinyMoney(
                        label: 'Comision absorbida',
                        value: totals.expectedCardFeeAbsorbedAmount,
                      ),
                      _TinyMoney(
                        label: 'Neto tarjeta',
                        value: totals.estimatedCardNetAmount,
                      ),
                      _TinyMoney(
                        label: 'Plataforma',
                        value: totals.expectedPlatformAmount,
                      ),
                      _TinyMoney(
                        label: 'Consumo empleado',
                        value: totals.expectedEmployeeConsumptionAmount,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _TinyMoney extends StatelessWidget {
  const _TinyMoney({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 130),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: BrandColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          MoneyText(
            value: value,
            style: const TextStyle(
              color: BrandColors.accentYellow,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminLinkPanel extends StatelessWidget {
  const _AdminLinkPanel({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: BrandColors.glassHighlight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: BrandColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GlassButton(
            icon: Icons.arrow_forward,
            label: 'Abrir',
            prominent: true,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

enum _HourlyReportMode { yesterdayVsLastSales, selectedVsPreviousWeek }

class _HourlySalesComparisonPanel extends StatelessWidget {
  const _HourlySalesComparisonPanel({
    required this.repository,
    required this.orders,
    required this.mode,
    required this.baseDate,
    required this.onModeChanged,
    required this.onBaseDateChanged,
    required this.onRefresh,
  });

  final TacoPosRepository repository;
  final List<PosOrder> orders;
  final _HourlyReportMode mode;
  final DateTime baseDate;
  final ValueChanged<_HourlyReportMode> onModeChanged;
  final ValueChanged<DateTime> onBaseDateChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final range = _queryRange();
    return StreamBuilder<List<Payment>>(
      stream: repository.watchDashboardPayments(
        startDate: range.start,
        endDate: range.end,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Hourly sales report failed: ${snapshot.error}');
          return GlassPanel(
            borderColor: BrandColors.danger,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _toolbar(context),
                const SizedBox(height: 12),
                const Text('No se pudo cargar el reporte. Intenta nuevamente.'),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const LoadingPanel(message: 'Cargando ventas por hora...');
        }

        final payments = snapshot.data ?? const <Payment>[];
        final orderById = {for (final order in orders) order.id: order};
        final report = _buildReport(payments, orderById);
        return GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _toolbar(context),
              const SizedBox(height: 14),
              if (report == null)
                const Text(
                  'No se encontro un dia anterior con ventas para comparar.',
                  style: TextStyle(
                    color: BrandColors.textMuted,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else ...[
                _HourlySummary(report: report),
                const SizedBox(height: 14),
                _HourlyBars(report: report),
                const SizedBox(height: 14),
                _HourlyTable(report: report),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _toolbar(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const SizedBox(
          width: 260,
          child: SectionHeader(
            title: 'Ventas por hora',
            subtitle: 'Comparativos de venta cobrada.',
          ),
        ),
        SizedBox(
          width: 340,
          child: DropdownButtonFormField<_HourlyReportMode>(
            initialValue: mode,
            decoration: const InputDecoration(labelText: 'Reporte'),
            items: const [
              DropdownMenuItem(
                value: _HourlyReportMode.yesterdayVsLastSales,
                child: Text('Ventas por hora: ayer vs ultimo dia con ventas'),
              ),
              DropdownMenuItem(
                value: _HourlyReportMode.selectedVsPreviousWeek,
                child: Text('Ventas por hora: semana anterior'),
              ),
            ],
            onChanged: (value) {
              if (value != null) onModeChanged(value);
            },
          ),
        ),
        if (mode == _HourlyReportMode.selectedVsPreviousWeek)
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: baseDate,
                firstDate: DateTime(2024),
                lastDate: DateTime(DateTime.now().year + 2),
              );
              if (picked != null) onBaseDateChanged(_startOfDay(picked));
            },
            icon: const Icon(Icons.event_outlined),
            label: Text('Base: ${_dateLabel(baseDate)}'),
          ),
        FilledButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Actualizar'),
        ),
      ],
    );
  }

  _DateRange _queryRange() {
    final yesterday = _startOfDay(
      DateTime.now(),
    ).subtract(const Duration(days: 1));
    if (mode == _HourlyReportMode.yesterdayVsLastSales) {
      return _DateRange(
        start: yesterday.subtract(const Duration(days: 30)),
        end: yesterday,
      );
    }
    final cleanBase = _startOfDay(baseDate);
    final compare = cleanBase.subtract(const Duration(days: 7));
    return _DateRange(
      start: compare.isBefore(cleanBase) ? compare : cleanBase,
      end: compare.isAfter(cleanBase) ? compare : cleanBase,
    );
  }

  _HourlyComparisonReport? _buildReport(
    List<Payment> payments,
    Map<String, PosOrder> orderById,
  ) {
    final activePayments = payments.where((payment) {
      if (!payment.isActive) return false;
      final order = orderById[payment.orderId];
      if (order == null) return true;
      return !_isOrderCancelled(order);
    }).toList();

    final aDate = mode == _HourlyReportMode.yesterdayVsLastSales
        ? _startOfDay(DateTime.now()).subtract(const Duration(days: 1))
        : _startOfDay(baseDate);
    final DateTime? bDate = mode == _HourlyReportMode.yesterdayVsLastSales
        ? _lastSalesDateBefore(activePayments, aDate)
        : aDate.subtract(const Duration(days: 7));
    if (bDate == null) return null;

    final a = _hourlySalesForDate(activePayments, orderById, aDate);
    final b = _hourlySalesForDate(activePayments, orderById, bDate);
    final rows = List.generate(24, (hour) {
      final aHour = a.hours[hour] ?? const _HourlyBucket();
      final bHour = b.hours[hour] ?? const _HourlyBucket();
      return _HourlyComparisonRow(hour: hour, a: aHour, b: bHour);
    });
    return _HourlyComparisonReport(
      mode: mode,
      aDate: aDate,
      bDate: bDate,
      aLabel: mode == _HourlyReportMode.yesterdayVsLastSales
          ? 'Ayer'
          : 'Dia seleccionado',
      bLabel: mode == _HourlyReportMode.yesterdayVsLastSales
          ? 'Ultimo dia con ventas'
          : 'Semana anterior',
      rows: rows,
    );
  }

  DateTime? _lastSalesDateBefore(List<Payment> payments, DateTime aDate) {
    for (var offset = 1; offset <= 30; offset++) {
      final candidate = aDate.subtract(Duration(days: offset));
      final total = payments
          .where(
            (payment) => _paymentBusinessDate(payment) == _dateKey(candidate),
          )
          .fold<double>(0, (sum, payment) => sum + payment.chargedAmount);
      if (total > 0.01) return candidate;
    }
    return null;
  }

  _DailyHourlySales _hourlySalesForDate(
    List<Payment> payments,
    Map<String, PosOrder> orderById,
    DateTime date,
  ) {
    final businessDate = _dateKey(date);
    final buckets = <int, _MutableHourlyBucket>{};
    for (final payment in payments.where(
      (payment) => _paymentBusinessDate(payment) == businessDate,
    )) {
      final order = orderById[payment.orderId];
      final saleTime = payment.createdAt ?? order?.paidAt ?? order?.createdAt;
      final hour = (saleTime ?? date).hour;
      final bucket = buckets.putIfAbsent(hour, _MutableHourlyBucket.new);
      bucket.sales += payment.chargedAmount;
      if (payment.orderId.trim().isNotEmpty) {
        bucket.orderIds.add(payment.orderId);
      }
    }
    return _DailyHourlySales(
      date: date,
      hours: {
        for (final entry in buckets.entries)
          entry.key: _HourlyBucket(
            sales: entry.value.sales,
            orderCount: entry.value.orderIds.length,
          ),
      },
    );
  }
}

class _HourlySummary extends StatelessWidget {
  const _HourlySummary({required this.report});

  final _HourlyComparisonReport report;

  @override
  Widget build(BuildContext context) {
    final diff = report.totalA - report.totalB;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: constraints.maxWidth >= 900 ? 2.2 : 1.7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _SmallReportCard(
              label: '${report.aLabel} ${_dateLabel(report.aDate)}',
              value: _money(report.totalA),
              color: BrandColors.accentYellow,
            ),
            _SmallReportCard(
              label: '${report.bLabel} ${_dateLabel(report.bDate)}',
              value: _money(report.totalB),
              color: BrandColors.info,
            ),
            _SmallReportCard(
              label: 'Diferencia total',
              value:
                  '${_money(diff)} (${_percentLabel(report.totalA, report.totalB)})',
              color: diff >= 0 ? BrandColors.success : BrandColors.danger,
            ),
            _SmallReportCard(
              label: 'Mejor hora ${report.aLabel.toLowerCase()}',
              value: report.bestA == null
                  ? 'Sin ventas'
                  : '${_hourRange(report.bestA!.hour)} ${_money(report.bestA!.a.sales)}',
              color: BrandColors.accentYellow,
            ),
            _SmallReportCard(
              label: report.mode == _HourlyReportMode.yesterdayVsLastSales
                  ? 'Hora mas baja de ayer'
                  : 'Mejor hora semana anterior',
              value: report.mode == _HourlyReportMode.yesterdayVsLastSales
                  ? report.lowestA == null
                        ? 'Sin ventas'
                        : '${_hourRange(report.lowestA!.hour)} ${_money(report.lowestA!.a.sales)}'
                  : report.bestB == null
                  ? 'Sin ventas'
                  : '${_hourRange(report.bestB!.hour)} ${_money(report.bestB!.b.sales)}',
              color: BrandColors.textMuted,
            ),
          ],
        );
      },
    );
  }
}

class _SmallReportCard extends StatelessWidget {
  const _SmallReportCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: BrandColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _HourlyBars extends StatelessWidget {
  const _HourlyBars({required this.report});

  final _HourlyComparisonReport report;

  @override
  Widget build(BuildContext context) {
    final maxSales = report.rows.fold<double>(
      0,
      (max, row) => [
        max,
        row.a.sales,
        row.b.sales,
      ].reduce((value, element) => value > element ? value : element),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          children: const [
            _Legend(color: BrandColors.accentYellow, label: 'Dia A'),
            _Legend(color: BrandColors.info, label: 'Dia B'),
          ],
        ),
        const SizedBox(height: 10),
        ...report.rows
            .where((row) => row.a.sales > 0 || row.b.sales > 0)
            .map((row) => _HourlyBarRow(row: row, maxSales: maxSales)),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: BrandColors.textMuted)),
      ],
    );
  }
}

class _HourlyBarRow extends StatelessWidget {
  const _HourlyBarRow({required this.row, required this.maxSales});

  final _HourlyComparisonRow row;
  final double maxSales;

  @override
  Widget build(BuildContext context) {
    final aFactor = maxSales <= 0 ? 0.0 : row.a.sales / maxSales;
    final bFactor = maxSales <= 0 ? 0.0 : row.b.sales / maxSales;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              _hourRange(row.hour),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                _Bar(value: aFactor, color: BrandColors.accentYellow),
                const SizedBox(height: 3),
                _Bar(value: bFactor, color: BrandColors.info),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(
              _money(row.a.sales),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: (constraints.maxWidth * value).clamp(
              2,
              constraints.maxWidth,
            ),
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      },
    );
  }
}

class _HourlyTable extends StatelessWidget {
  const _HourlyTable({required this.report});

  final _HourlyComparisonReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () => _export(context),
            icon: const Icon(Icons.download_outlined),
            label: const Text('CSV'),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              const DataColumn(label: Text('Hora')),
              DataColumn(label: Text('${report.aLabel} venta')),
              DataColumn(label: Text('${report.bLabel} venta')),
              const DataColumn(label: Text('Dif \$')),
              const DataColumn(label: Text('Dif %')),
              DataColumn(label: Text('Ordenes ${report.aLabel}')),
              DataColumn(label: Text('Ordenes ${report.bLabel}')),
            ],
            rows: report.rows
                .map(
                  (row) => DataRow(
                    cells: [
                      DataCell(Text(_hourRange(row.hour))),
                      DataCell(Text(_money(row.a.sales))),
                      DataCell(Text(_money(row.b.sales))),
                      DataCell(
                        Text(
                          _money(row.diff),
                          style: TextStyle(color: _diffColor(row.diff)),
                        ),
                      ),
                      DataCell(
                        Text(
                          _percentLabel(row.a.sales, row.b.sales),
                          style: TextStyle(color: _diffColor(row.diff)),
                        ),
                      ),
                      DataCell(Text('${row.a.orderCount}')),
                      DataCell(Text('${row.b.orderCount}')),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context) async {
    final csv = [
      'Reporte,Fecha A,Fecha B,Hora,Venta A,Venta B,Diferencia,Diferencia %,Ordenes A,Ordenes B',
      ...report.rows.map(
        (row) =>
            '"${report.title}","${_dateKey(report.aDate)}","${_dateKey(report.bDate)}","${_hourRange(row.hour)}",${row.a.sales},${row.b.sales},${row.diff},"${_percentLabel(row.a.sales, row.b.sales)}",${row.a.orderCount},${row.b.orderCount}',
      ),
    ].join('\n');
    final message = await exportCsvFile(
      fileName: 'ventas-por-hora-comparativo.csv',
      content: csv,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DateRange {
  const _DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class _DailyHourlySales {
  const _DailyHourlySales({required this.date, required this.hours});

  final DateTime date;
  final Map<int, _HourlyBucket> hours;
}

class _MutableHourlyBucket {
  double sales = 0;
  final Set<String> orderIds = {};
}

class _HourlyBucket {
  const _HourlyBucket({this.sales = 0, this.orderCount = 0});

  final double sales;
  final int orderCount;
}

class _HourlyComparisonRow {
  const _HourlyComparisonRow({
    required this.hour,
    required this.a,
    required this.b,
  });

  final int hour;
  final _HourlyBucket a;
  final _HourlyBucket b;

  double get diff => a.sales - b.sales;
}

class _HourlyComparisonReport {
  const _HourlyComparisonReport({
    required this.mode,
    required this.aDate,
    required this.bDate,
    required this.aLabel,
    required this.bLabel,
    required this.rows,
  });

  final _HourlyReportMode mode;
  final DateTime aDate;
  final DateTime bDate;
  final String aLabel;
  final String bLabel;
  final List<_HourlyComparisonRow> rows;

  String get title => mode == _HourlyReportMode.yesterdayVsLastSales
      ? 'Ventas por hora: ayer vs ultimo dia con ventas'
      : 'Ventas por hora: semana anterior';
  double get totalA => rows.fold(0, (sum, row) => sum + row.a.sales);
  double get totalB => rows.fold(0, (sum, row) => sum + row.b.sales);
  _HourlyComparisonRow? get bestA => _best(rows, (row) => row.a.sales);
  _HourlyComparisonRow? get bestB => _best(rows, (row) => row.b.sales);
  _HourlyComparisonRow? get lowestA {
    final nonZero = rows.where((row) => row.a.sales > 0).toList();
    if (nonZero.isEmpty) return null;
    nonZero.sort((a, b) => a.a.sales.compareTo(b.a.sales));
    return nonZero.first;
  }

  static _HourlyComparisonRow? _best(
    List<_HourlyComparisonRow> rows,
    double Function(_HourlyComparisonRow row) selector,
  ) {
    final nonZero = rows.where((row) => selector(row) > 0).toList();
    if (nonZero.isEmpty) return null;
    nonZero.sort((a, b) => selector(b).compareTo(selector(a)));
    return nonZero.first;
  }
}

bool _isOrderCancelled(PosOrder order) {
  final status = order.status.toLowerCase().trim();
  return status == 'cancelled' ||
      status == 'canceled' ||
      status == 'voided' ||
      order.cancelledAt != null ||
      order.canceledAt != null;
}

String _paymentBusinessDate(Payment payment) {
  final businessDate = payment.businessDate?.trim();
  if (businessDate != null && businessDate.isNotEmpty) return businessDate;
  return _dateKey(payment.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
}

DateTime _startOfDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

String _dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

String _dateLabel(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

String _hourRange(int hour) {
  final start = hour.toString().padLeft(2, '0');
  return '$start:00 - $start:59';
}

String _money(double value) {
  final sign = value < 0 ? '-' : '';
  return '$sign\$${value.abs().toStringAsFixed(2)}';
}

String _percentLabel(double a, double b) {
  if (b.abs() <= 0.01) {
    if (a.abs() <= 0.01) return '0.0%';
    return '+100.0%';
  }
  final value = ((a - b) / b) * 100;
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(1)}%';
}

Color _diffColor(double diff) {
  if (diff > 0.01) return BrandColors.success;
  if (diff < -0.01) return BrandColors.danger;
  return BrandColors.textMuted;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.icon,
    required this.accent,
    this.value,
    this.money,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final String? value;
  final double? money;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 28),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: BrandColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (money != null)
            MoneyText(
              value: money!,
              style: TextStyle(
                color: accent,
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            )
          else
            Text(
              value ?? '0',
              style: TextStyle(
                color: accent,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentOrderTile extends StatelessWidget {
  const _RecentOrderTile({required this.order});

  final PosOrder order;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: EdgeInsets.zero,
        accent: BrandColors.accentOrange,
        child: ListTile(
          leading: const Icon(
            Icons.receipt_long,
            color: BrandColors.accentOrange,
          ),
          title: Text(
            order.displayName,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            '${formatOrderStatus(order.status)} | ${formatKitchenStatus(order.kitchenStatus)}',
          ),
          trailing: MoneyText(
            value: order.total,
            style: const TextStyle(
              color: BrandColors.accentYellow,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
