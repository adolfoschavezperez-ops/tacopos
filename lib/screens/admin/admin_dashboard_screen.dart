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
import '../../utils/formatters.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';
import '../cash/cash_session_screen.dart';
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

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = _startDate;
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
        employee?.canViewAdmin == true ||
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
            employee?.canViewAdmin == true ||
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

              final payments = _paymentsInRange(paymentsSnapshot.data ?? []);
              final baseSales = payments.fold<double>(
                0,
                (runningTotal, payment) => runningTotal + payment.baseAmount,
              );
              final cash = _baseByMethod(payments, 'cash');
              final cardBase = _baseByMethod(payments, 'card');
              final cardSurcharge = payments
                  .where((payment) => payment.method == 'card')
                  .fold<double>(
                    0,
                    (runningTotal, payment) =>
                        runningTotal + payment.surchargeAmount,
                  );
              final cardCharged = payments
                  .where((payment) => payment.method == 'card')
                  .fold<double>(
                    0,
                    (runningTotal, payment) =>
                        runningTotal + payment.chargedAmount,
                  );
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
                                title: 'Comision tarjeta',
                                icon: Icons.percent,
                                money: cardSurcharge,
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
                      if (employee?.canViewAdmin == true ||
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
                        label: 'Comision',
                        value: totals.expectedCardSurchargeAmount,
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
