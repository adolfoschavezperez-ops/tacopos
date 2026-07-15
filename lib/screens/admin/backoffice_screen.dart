import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/cash_session.dart';
import '../../models/cash_withdrawal_request.dart';
import '../../models/branch.dart';
import '../../models/employee.dart';
import '../../models/kitchen_session.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';
import '../../services/app_session.dart';
import '../../services/live_presence_service.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/csv_exporter.dart';
import '../../utils/formatters.dart';
import '../../widgets/backoffice_dashboard_widgets.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import 'cash_admin_screen.dart';
import 'branch_catalog_screen.dart';
import 'employee_catalog_screen.dart';
import 'kitchen_admin_screen.dart';
import 'live_operations_screen.dart';
import 'order_platform_catalog_screen.dart';
import 'operation_reset_screen.dart';
import 'product_category_catalog_screen.dart';
import 'product_catalog_screen.dart';
import 'table_catalog_screen.dart';

enum _BackofficeSection {
  dashboard,
  live,
  sales,
  reports,
  cash,
  kitchen,
  settings,
}

enum _ReportKind {
  products,
  hourly,
  dates,
  kitchenWaste,
  kitchenInventory,
  platform,
  paymentMethod,
  employee,
  cashHistory,
  withdrawals,
  kitchenYield,
  cancellations,
  cancelledPayments,
}

class BackofficeScreen extends StatefulWidget {
  const BackofficeScreen({super.key});

  @override
  State<BackofficeScreen> createState() => _BackofficeScreenState();
}

class _BackofficeScreenState extends State<BackofficeScreen> {
  final _repository = TacoPosRepository();
  late DateTime _startDate;
  late DateTime _endDate;
  _BackofficeSection _section = _BackofficeSection.dashboard;
  _ReportKind _reportKind = _ReportKind.products;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = _startDate;
    LivePresenceService.instance.updateCurrentScreen(
      appMode: 'admin',
      currentScreen: 'Backoffice',
      currentAction: 'Viendo backoffice',
    );
    AppSession.instance.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    AppSession.instance.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  String get _startBusinessDate => DateFormat('yyyy-MM-dd').format(_startDate);
  String get _endBusinessDate => DateFormat('yyyy-MM-dd').format(_endDate);

  Future<void> _pickStartDate() async {
    final picked = await _pickDate(_startDate);
    if (picked == null || !mounted) return;
    setState(() {
      _startDate = picked;
      if (_endDate.isBefore(_startDate)) _endDate = _startDate;
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await _pickDate(_endDate);
    if (picked == null || !mounted) return;
    setState(() {
      _endDate = picked;
      if (_startDate.isAfter(_endDate)) _startDate = _endDate;
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

  void _today() {
    final now = DateTime.now();
    setState(() {
      _startDate = DateTime(now.year, now.month, now.day);
      _endDate = _startDate;
    });
  }

  void _week() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _startDate = today.subtract(Duration(days: today.weekday - 1));
      _endDate = today;
    });
  }

  void _month() {
    final now = DateTime.now();
    setState(() {
      _startDate = DateTime(now.year, now.month);
      _endDate = DateTime(now.year, now.month, now.day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final employee = AppSession.instance.employee;
    if (!_canUseBackoffice(employee)) {
      return Scaffold(
        body: PremiumBackground(
          child: Center(
            child: EmptyState(
              icon: Icons.lock_outline,
              title: 'Sin acceso',
              message: 'No tienes acceso al backoffice.',
            ),
          ),
        ),
      );
    }

    final navItems = _navItems(employee);
    final effectiveSection = navItems.any((item) => item.section == _section)
        ? _section
        : navItems.first.section;
    if (effectiveSection != _section) {
      _section = effectiveSection;
    }

    return Scaffold(
      body: PremiumBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              final body = _BackofficeBody(
                section: effectiveSection,
                reportKind: _reportKind,
                repository: _repository,
                startDate: _startDate,
                endDate: _endDate,
                startBusinessDate: _startBusinessDate,
                endBusinessDate: _endBusinessDate,
                onReportChanged: (value) => setState(() => _reportKind = value),
                onPickStart: _pickStartDate,
                onPickEnd: _pickEndDate,
                onToday: _today,
                onWeek: _week,
                onMonth: _month,
              );

              if (compact) {
                return Column(
                  children: [
                    _MobileTopBar(
                      section: effectiveSection,
                      employee: employee,
                      onSectionChanged: (value) =>
                          setState(() => _section = value),
                    ),
                    Expanded(child: body),
                  ],
                );
              }

              return Row(
                children: [
                  _SideNav(
                    section: effectiveSection,
                    employee: employee,
                    onSectionChanged: (value) =>
                        setState(() => _section = value),
                  ),
                  Expanded(child: body),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.section,
    required this.employee,
    required this.onSectionChanged,
  });

  final _BackofficeSection section;
  final Employee? employee;
  final ValueChanged<_BackofficeSection> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 268,
      padding: const EdgeInsets.all(18),
      child: GlassPanel(
        borderRadius: 26,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Image.asset(
                    'assets/branding/logo_los_padrinos.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'TacoPOS\nBackoffice',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ..._navItems(employee).map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _NavButton(
                  item: item,
                  selected: item.section == section,
                  onTap: () => onSectionChanged(item.section),
                ),
              ),
            ),
            const Spacer(),
            Text(
              employee?.name ?? 'Socio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: AppSession.instance.signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Salir'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar({
    required this.section,
    required this.employee,
    required this.onSectionChanged,
  });

  final _BackofficeSection section;
  final Employee? employee;
  final ValueChanged<_BackofficeSection> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: GlassPanel(
        padding: const EdgeInsets.all(12),
        borderRadius: 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'TacoPOS Backoffice',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: 'Salir',
                  onPressed: AppSession.instance.signOut,
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _navItems(employee).map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: item.section == section,
                      avatar: Icon(item.icon, size: 18),
                      label: Text(item.label),
                      onSelected: (_) => onSectionChanged(item.section),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? BrandColors.accentYellow.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? BrandColors.accentYellow : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(item.icon, color: selected ? BrandColors.accentYellow : null),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected ? BrandColors.accentYellow : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackofficeBody extends StatelessWidget {
  const _BackofficeBody({
    required this.section,
    required this.reportKind,
    required this.repository,
    required this.startDate,
    required this.endDate,
    required this.startBusinessDate,
    required this.endBusinessDate,
    required this.onReportChanged,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onToday,
    required this.onWeek,
    required this.onMonth,
  });

  final _BackofficeSection section;
  final _ReportKind reportKind;
  final TacoPosRepository repository;
  final DateTime startDate;
  final DateTime endDate;
  final String startBusinessDate;
  final String endBusinessDate;
  final ValueChanged<_ReportKind> onReportChanged;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onToday;
  final VoidCallback onWeek;
  final VoidCallback onMonth;

  @override
  Widget build(BuildContext context) {
    Widget withBranchHeader(Widget child) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
            child: _BackofficeBranchSelector(repository: repository),
          ),
          Expanded(child: child),
        ],
      );
    }

    if (section == _BackofficeSection.live) {
      final employee = AppSession.instance.employee;
      if (employee == null) {
        return const EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin sesion',
          message: 'Inicia sesion para ver el visor operativo.',
        );
      }
      return withBranchHeader(LiveOperationsScreen(employee: employee));
    }
    if (section == _BackofficeSection.cash) {
      return withBranchHeader(const CashAdminScreen());
    }
    if (section == _BackofficeSection.kitchen) {
      return withBranchHeader(const KitchenAdminScreen());
    }
    if (section == _BackofficeSection.settings) {
      return withBranchHeader(_SettingsSection(repository: repository));
    }

    return StreamBuilder<List<PosOrder>>(
      stream: repository.watchAllOrders(),
      builder: (context, ordersSnapshot) {
        if (ordersSnapshot.hasError) {
          return _FriendlyError(message: 'No se pudieron cargar ordenes.');
        }
        if (ordersSnapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPanel(message: 'Cargando backoffice...');
        }
        final allOrders = ordersSnapshot.data ?? [];
        final orders = allOrders.where(_orderInRange).toList();
        orders.sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });

        return StreamBuilder<List<Payment>>(
          stream: repository.watchDashboardPayments(
            startDate: startDate,
            endDate: endDate,
          ),
          builder: (context, paymentsSnapshot) {
            if (paymentsSnapshot.hasError) {
              return _FriendlyError(message: 'No se pudieron cargar pagos.');
            }
            final payments = _paymentsInRange(paymentsSnapshot.data ?? []);
            final activePayments = payments
                .where((payment) => payment.isActive)
                .toList();

            return ListView(
              padding: const EdgeInsets.all(22),
              children: [
                _BackofficeBranchSelector(repository: repository),
                const SizedBox(height: 14),
                if (section != _BackofficeSection.dashboard) ...[
                  _HeaderRow(
                    title: _sectionTitle(section),
                    subtitle: 'Informacion filtrada por fecha de reporte.',
                  ),
                  const SizedBox(height: 14),
                  _GlobalFilters(
                    startBusinessDate: startBusinessDate,
                    endBusinessDate: endBusinessDate,
                    onPickStart: onPickStart,
                    onPickEnd: onPickEnd,
                    onToday: onToday,
                    onWeek: onWeek,
                    onMonth: onMonth,
                  ),
                  const SizedBox(height: 18),
                ],
                switch (section) {
                  _BackofficeSection.dashboard => _DashboardSection(
                    repository: repository,
                    orders: orders,
                    payments: activePayments,
                    startBusinessDate: startBusinessDate,
                    endBusinessDate: endBusinessDate,
                    onPickStart: onPickStart,
                    onPickEnd: onPickEnd,
                    onToday: onToday,
                    onWeek: onWeek,
                    onMonth: onMonth,
                  ),
                  _BackofficeSection.sales => _SalesSection(
                    repository: repository,
                    orders: orders,
                    payments: activePayments,
                  ),
                  _BackofficeSection.reports => _ReportsSection(
                    repository: repository,
                    orders: orders,
                    payments: reportKind == _ReportKind.cancelledPayments
                        ? payments
                        : activePayments,
                    reportKind: reportKind,
                    startBusinessDate: startBusinessDate,
                    endBusinessDate: endBusinessDate,
                    onReportChanged: onReportChanged,
                  ),
                  _BackofficeSection.live => const SizedBox.shrink(),
                  _BackofficeSection.cash => const SizedBox.shrink(),
                  _BackofficeSection.kitchen => const SizedBox.shrink(),
                  _BackofficeSection.settings => const SizedBox.shrink(),
                },
              ],
            );
          },
        );
      },
    );
  }

  bool _orderInRange(PosOrder order) {
    final businessDate = _businessDateFor(order.paidAt ?? order.createdAt);
    if (businessDate != null) {
      return businessDate.compareTo(startBusinessDate) >= 0 &&
          businessDate.compareTo(endBusinessDate) <= 0;
    }
    return _dateInRange(order.createdAt) ||
        _dateInRange(order.updatedAt) ||
        _dateInRange(order.paidAt);
  }

  List<Payment> _paymentsInRange(List<Payment> payments) {
    return payments.where((payment) {
      final businessDate = payment.businessDate;
      if (businessDate != null && businessDate.isNotEmpty) {
        return businessDate.compareTo(startBusinessDate) >= 0 &&
            businessDate.compareTo(endBusinessDate) <= 0;
      }
      return _dateInRange(payment.createdAt);
    }).toList();
  }

  bool _dateInRange(DateTime? value) {
    if (value == null) return false;
    final date = DateTime(value.year, value.month, value.day);
    return !date.isBefore(startDate) && !date.isAfter(endDate);
  }
}

class _DashboardSection extends StatelessWidget {
  const _DashboardSection({
    required this.repository,
    required this.orders,
    required this.payments,
    required this.startBusinessDate,
    required this.endBusinessDate,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onToday,
    required this.onWeek,
    required this.onMonth,
  });

  final TacoPosRepository repository;
  final List<PosOrder> orders;
  final List<Payment> payments;
  final String startBusinessDate;
  final String endBusinessDate;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onToday;
  final VoidCallback onWeek;
  final VoidCallback onMonth;

  @override
  Widget build(BuildContext context) {
    final paidOrders = orders.where((order) => order.status == 'paid').toList();
    final openOrders = orders
        .where(
          (order) => !['paid', 'cancelled', 'voided'].contains(order.status),
        )
        .toList();
    final partialOrders = orders
        .where((order) => order.paymentStatus == 'partial')
        .toList();
    final baseSales = _sum(payments, (payment) => payment.baseAmount);
    final charged = _sum(payments, (payment) => payment.chargedAmount);
    final cash = _sum(
      payments.where((payment) => payment.method == 'cash'),
      (payment) => payment.baseAmount,
    );
    final card = _sum(
      payments.where((payment) => payment.method == 'card'),
      (payment) => payment.baseAmount,
    );
    final cardFee = _sum(
      payments.where((payment) => payment.method == 'card'),
      (payment) => payment.cardFeeAbsorbedAmount,
    );
    final cardCharged = _sum(
      payments.where((payment) => payment.method == 'card'),
      (payment) => payment.chargedAmount,
    );
    final cardNet = cardCharged - cardFee;
    final platform = _sum(
      payments.where((payment) => payment.method == 'platform_paid'),
      (payment) => payment.baseAmount,
    );
    final employeeConsumption = _sum(
      payments.where((payment) => payment.method == 'employee_consumption'),
      (payment) => payment.baseAmount,
    );
    final takeoutOrders = orders.where((order) => order.orderType == 'takeout');
    final servedTables = orders
        .where(
          (order) => order.orderType != 'takeout' && order.tableId.isNotEmpty,
        )
        .map((order) => order.tableId)
        .toSet()
        .length;
    final avgTicket = paidOrders.isEmpty ? 0.0 : baseSales / paidOrders.length;
    final attentionDurations = paidOrders
        .map((order) => _durationBetween(order.createdAt, order.paidAt))
        .whereType<Duration>()
        .toList();
    final avgAttention = _averageDuration(attentionDurations);
    final maxAttention = attentionDurations.isEmpty
        ? Duration.zero
        : attentionDurations.reduce((a, b) => a > b ? a : b);
    final slowestOrder =
        paidOrders
            .where((order) => order.createdAt != null && order.paidAt != null)
            .toList()
          ..sort((a, b) {
            final aDuration = _durationBetween(a.createdAt, a.paidAt)!;
            final bDuration = _durationBetween(b.createdAt, b.paidAt)!;
            return bDuration.compareTo(aDuration);
          });
    final paymentMethod = _topLabel(
      payments.map((payment) => _paymentMethodLabel(payment.method)),
    );
    final platformName = _topLabel(
      orders
          .where((order) => order.orderType == 'takeout')
          .map((order) => order.platformName ?? 'En persona'),
    );
    final peakHourRows = _salesByHour(payments);
    final peakHour = peakHourRows.isEmpty ? null : peakHourRows.first;
    final methodRows = _salesByMethod(payments);
    final platformRows = _salesByPlatform(payments);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExecutiveDashboardHeader(
          title: 'Dashboard',
          subtitle:
              'Vista ejecutiva de ventas, operacion, alertas y rendimiento del negocio.',
          dateLabel: startBusinessDate == endBusinessDate
              ? startBusinessDate
              : '$startBusinessDate a $endBusinessDate',
          onPickStart: onPickStart,
          onPickEnd: onPickEnd,
          onToday: onToday,
          onWeek: onWeek,
          onMonth: onMonth,
        ),
        const SizedBox(height: 18),
        _ExecutiveKpiGrid(
          children: [
            ExecutiveKpiCard(
              title: 'Venta total',
              value: _money(baseSales),
              detail: '${paidOrders.length} ordenes pagadas',
              icon: Icons.trending_up,
            ),
            ExecutiveKpiCard(
              title: 'Cobrado real',
              value: _money(charged),
              detail: 'Monto cobrado al cliente',
              icon: Icons.payments_outlined,
              accent: BrandColors.success,
            ),
            ExecutiveKpiCard(
              title: 'Ticket promedio',
              value: _money(avgTicket),
              detail: 'Sobre ordenes pagadas',
              icon: Icons.receipt_long,
              accent: BrandColors.info,
            ),
            ExecutiveKpiCard(
              title: 'Ordenes pagadas',
              value: '${paidOrders.length}',
              detail: '${openOrders.length} abiertas',
              icon: Icons.check_circle_outline,
              accent: BrandColors.accentOrange,
            ),
            ExecutiveKpiCard(
              title: 'Atencion promedio',
              value: _durationText(avgAttention),
              detail: 'Maxima ${_durationText(maxAttention)}',
              icon: Icons.timer_outlined,
            ),
          ],
        ),
        const SizedBox(height: 18),
        DashboardSectionPanel(
          title: 'Metricas financieras y operativas',
          subtitle: 'Indicadores secundarios del rango seleccionado.',
          child: _SecondaryMetricGrid(
            children: [
              SecondaryMetricCard(
                label: 'Efectivo',
                value: _money(cash),
                icon: Icons.attach_money,
              ),
              SecondaryMetricCard(
                label: 'Tarjeta',
                value: _money(card),
                icon: Icons.credit_card,
              ),
              SecondaryMetricCard(
                label: 'Comision absorbida',
                value: _money(cardFee),
                icon: Icons.percent,
              ),
              SecondaryMetricCard(
                label: 'Neto estimado tarjeta',
                value: _money(cardNet),
                icon: Icons.account_balance_wallet_outlined,
              ),
              SecondaryMetricCard(
                label: 'Pagado plataforma',
                value: _money(platform),
                icon: Icons.delivery_dining,
              ),
              SecondaryMetricCard(
                label: 'Consumo empleado',
                value: _money(employeeConsumption),
                icon: Icons.badge_outlined,
              ),
              SecondaryMetricCard(
                label: 'Ordenes abiertas',
                value: '${openOrders.length}',
                icon: Icons.pending_actions,
              ),
              SecondaryMetricCard(
                label: 'Ordenes parciales',
                value: '${partialOrders.length}',
                icon: Icons.call_split,
              ),
              SecondaryMetricCard(
                label: 'Para llevar',
                value: '${takeoutOrders.length}',
                icon: Icons.shopping_bag_outlined,
              ),
              SecondaryMetricCard(
                label: 'Mesas atendidas',
                value: '$servedTables',
                icon: Icons.table_restaurant,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _AlertStrip(repository: repository, orders: orders),
        const SizedBox(height: 18),
        FutureBuilder<_ItemsSummary>(
          future: _itemsSummary(repository, orders),
          builder: (context, snapshot) {
            final summary = snapshot.data ?? const _ItemsSummary.empty();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ChartGrid(
                  children: [
                    ChartPanel(
                      title: 'Ventas por hora',
                      subtitle: 'Ritmo del dia y concentracion de ingresos.',
                      data: _chartData(peakHourRows),
                      type: DashboardChartType.verticalBars,
                    ),
                    ChartPanel(
                      title: 'Metodo de pago',
                      subtitle: 'Distribucion del cobro por canal.',
                      data: _chartData(methodRows),
                      type: DashboardChartType.donut,
                    ),
                    ChartPanel(
                      title: 'Ventas por plataforma',
                      subtitle: 'Peso de mostrador y apps de delivery.',
                      data: _chartData(platformRows),
                      type: DashboardChartType.donut,
                    ),
                    ChartPanel(
                      title: 'Top productos',
                      subtitle: 'Productos con mayor venta del rango.',
                      data: _chartData(summary.topProducts),
                      type: DashboardChartType.horizontalBars,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                DashboardSectionPanel(
                  title: 'Insights ejecutivos',
                  subtitle:
                      'Hallazgos rapidos para leer el dia sin abrir reportes.',
                  child: _InsightGrid(
                    children: [
                      InsightCard(
                        label: 'Hora pico',
                        value: peakHour == null ? 'Sin ventas' : peakHour.label,
                        detail: peakHour?.displayValue,
                        icon: Icons.query_stats,
                      ),
                      InsightCard(
                        label: 'Producto lider',
                        value: summary.topProducts.isEmpty
                            ? 'Sin ventas'
                            : summary.topProducts.first.label,
                        detail: '${summary.totalQty} productos vendidos',
                        icon: Icons.local_fire_department_outlined,
                      ),
                      InsightCard(
                        label: 'Plataforma lider',
                        value: platformName.isEmpty
                            ? 'Sin pedidos'
                            : platformName,
                        icon: Icons.delivery_dining,
                      ),
                      InsightCard(
                        label: 'Metodo lider',
                        value: paymentMethod.isEmpty
                            ? 'Sin pagos'
                            : paymentMethod,
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                      InsightCard(
                        label: 'Orden mas lenta',
                        value: slowestOrder.isEmpty
                            ? 'Sin datos'
                            : slowestOrder.first.displayName,
                        detail: _durationText(maxAttention),
                        icon: Icons.hourglass_bottom,
                      ),
                      InsightCard(
                        label: 'Productos vendidos',
                        value: '${summary.totalQty}',
                        detail: 'Unidades del rango',
                        icon: Icons.restaurant_menu,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AlertStrip extends StatelessWidget {
  const _AlertStrip({required this.repository, required this.orders});

  final TacoPosRepository repository;
  final List<PosOrder> orders;

  @override
  Widget build(BuildContext context) {
    final openTables = orders
        .where(
          (order) => order.orderType != 'takeout' && order.status != 'paid',
        )
        .length;
    final openTakeout = orders
        .where(
          (order) => order.orderType == 'takeout' && order.status != 'paid',
        )
        .length;
    final partial = orders
        .where((order) => order.paymentStatus == 'partial')
        .length;

    return StreamBuilder<List<CashWithdrawalRequest>>(
      stream: repository.watchCashWithdrawalRequests(status: 'pending'),
      builder: (context, withdrawalsSnapshot) {
        return StreamBuilder<CashSession?>(
          stream: repository.watchOpenCashSession(),
          builder: (context, cashSnapshot) {
            return StreamBuilder<KitchenSession?>(
              stream: repository.watchOpenKitchenSession(),
              builder: (context, kitchenSnapshot) {
                final pendingWithdrawals =
                    withdrawalsSnapshot.data?.length ?? 0;
                final alerts = <String>[
                  if (pendingWithdrawals > 0)
                    '$pendingWithdrawals solicitudes de gasto pendientes',
                  if (cashSnapshot.data != null) 'Caja abierta sin cerrar',
                  if (kitchenSnapshot.data != null) 'Cocina abierta sin cerrar',
                  if (openTables > 0) '$openTables mesas abiertas',
                  if (openTakeout > 0)
                    '$openTakeout pedidos para llevar abiertos',
                  if (partial > 0) '$partial cuentas parciales',
                ];
                if (alerts.isEmpty) {
                  alerts.add('Sin alertas criticas en el rango.');
                }
                return AlertPanel(alerts: alerts);
              },
            );
          },
        );
      },
    );
  }
}

class _SalesSection extends StatefulWidget {
  const _SalesSection({
    required this.repository,
    required this.orders,
    required this.payments,
  });

  final TacoPosRepository repository;
  final List<PosOrder> orders;
  final List<Payment> payments;

  @override
  State<_SalesSection> createState() => _SalesSectionState();
}

class _SalesSectionState extends State<_SalesSection> {
  final _searchController = TextEditingController();
  String _orderType = 'all';
  String _status = 'all';
  String _method = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paymentsByOrder = _paymentsByOrder(widget.payments);
    final filtered = widget.orders.where((order) {
      final query = _searchController.text.trim().toLowerCase();
      final payments = paymentsByOrder[order.id] ?? const <Payment>[];
      final methods = payments.map((payment) => payment.method).toSet();
      final matchesQuery =
          query.isEmpty ||
          order.id.toLowerCase().contains(query) ||
          order.displayName.toLowerCase().contains(query) ||
          (order.customerName ?? '').toLowerCase().contains(query) ||
          (order.platformName ?? '').toLowerCase().contains(query);
      final matchesType = _orderType == 'all' || order.orderType == _orderType;
      final matchesStatus =
          _status == 'all' ||
          order.status == _status ||
          order.paymentStatus == _status;
      final matchesMethod = _method == 'all' || methods.contains(_method);
      return matchesQuery && matchesType && matchesStatus && matchesMethod;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Buscar folio, mesa, cliente o plataforma',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              _FilterMenu(
                value: _orderType,
                values: const {
                  'all': 'Todos',
                  'dine_in': 'Mesas',
                  'takeout': 'Para llevar',
                },
                onChanged: (value) => setState(() => _orderType = value),
              ),
              _FilterMenu(
                value: _status,
                values: const {
                  'all': 'Todos',
                  'paid': 'Pagadas',
                  'open': 'Abiertas',
                  'partial': 'Parciales',
                  'cancelled': 'Canceladas',
                },
                onChanged: (value) => setState(() => _status = value),
              ),
              _FilterMenu(
                value: _method,
                values: const {
                  'all': 'Todos',
                  'cash': 'Efectivo',
                  'card': 'Tarjeta',
                  'platform_paid': 'Plataforma',
                  'employee_consumption': 'Consumo empleado',
                },
                onChanged: (value) => setState(() => _method = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...filtered.map(
          (order) => _SaleTile(
            order: order,
            payments: paymentsByOrder[order.id] ?? const [],
            onOpen: () => _openSaleDetail(context, widget.repository, order),
          ),
        ),
        if (filtered.isEmpty)
          const EmptyState(
            icon: Icons.receipt_long,
            title: 'Sin ventas',
            message: 'No hay ordenes con los filtros seleccionados.',
          ),
      ],
    );
  }
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({
    required this.order,
    required this.payments,
    required this.onOpen,
  });

  final PosOrder order;
  final List<Payment> payments;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final methods = payments
        .map((payment) => _paymentMethodLabel(payment.method))
        .toSet()
        .join(', ');
    final attention = _durationBetween(order.createdAt, order.paidAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        accent: order.status == 'paid'
            ? BrandColors.success
            : BrandColors.accentOrange,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final info = Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _InfoText('Folio', _shortId(order.id)),
                _InfoText('Fecha', _dateTimeText(order.createdAt)),
                _InfoText('Origen', order.displayName),
                _InfoText('Plataforma', order.platformName ?? '-'),
                _InfoText('Total', _money(order.total)),
                _InfoText(
                  'Estado',
                  '${formatOrderStatus(order.status)} / ${formatPaymentStatus(order.paymentStatus)}',
                ),
                _InfoText('Pago', methods.isEmpty ? '-' : methods),
                _InfoText(
                  'Atencion',
                  attention == null ? '-' : _durationText(attention),
                ),
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  info,
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Ver detalle'),
                    ),
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: info),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Ver detalle'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReportsSection extends StatelessWidget {
  const _ReportsSection({
    required this.repository,
    required this.orders,
    required this.payments,
    required this.reportKind,
    required this.startBusinessDate,
    required this.endBusinessDate,
    required this.onReportChanged,
  });

  final TacoPosRepository repository;
  final List<PosOrder> orders;
  final List<Payment> payments;
  final _ReportKind reportKind;
  final String startBusinessDate;
  final String endBusinessDate;
  final ValueChanged<_ReportKind> onReportChanged;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<String>>>(
      future: _reportRows(
        repository,
        orders,
        payments,
        reportKind,
        startBusinessDate,
        endBusinessDate,
      ),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <List<String>>[];
        final headers = _reportHeaders(reportKind);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassPanel(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<_ReportKind>(
                    value: reportKind,
                    items: _ReportKind.values
                        .map(
                          (kind) => DropdownMenuItem(
                            value: kind,
                            child: Text(_reportTitle(kind)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) onReportChanged(value);
                    },
                  ),
                  FilledButton.icon(
                    onPressed: rows.isEmpty
                        ? null
                        : () => _copyCsv(context, headers, rows),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Exportar CSV'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _ReportTable(headers: headers, rows: rows),
          ],
        );
      },
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.repository});

  final TacoPosRepository repository;

  @override
  Widget build(BuildContext context) {
    final employee = AppSession.instance.employee;
    final canResetOperation =
        employee?.hasAdminAccess == true ||
        employee?.isSuperAdmin == true ||
        employee?.canViewAdmin == true ||
        employee?.id.toLowerCase().trim() == 'admin' ||
        employee?.name.toLowerCase().trim() == 'admin';
    final links = <_SettingsLink>[
      if (employee?.hasAdminAccess == true)
        _SettingsLink(
          'Sucursales',
          'Catalogo de sucursales del restaurante.',
          Icons.storefront_outlined,
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BranchCatalogScreen()),
          ),
        ),
      if (canResetOperation)
        _SettingsLink(
          'Reiniciar operación',
          'Limpia ventas, órdenes, pagos, caja, cocina, gastos y sesiones activas por sucursal.',
          Icons.restart_alt_outlined,
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OperationResetScreen()),
          ),
        ),
      if (employee?.canManageProducts == true)
        _SettingsLink(
          'Productos',
          'Catalogo, precios, plataformas e insumos ligados.',
          Icons.restaurant_menu,
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProductCatalogScreen()),
          ),
        ),
      if (employee?.canManageProducts == true)
        _SettingsLink(
          'Categorias de productos',
          'Subcatalogo, orden, acentos y productos ligados.',
          Icons.category_outlined,
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ProductCategoryCatalogScreen(),
            ),
          ),
        ),
      if (employee?.canManageTables == true)
        _SettingsLink(
          'Mesas',
          'Mesas fisicas y entrada Para llevar.',
          Icons.table_restaurant,
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TableCatalogScreen()),
          ),
        ),
      if (employee?.canManagePlatforms == true)
        _SettingsLink(
          'Plataformas',
          'Canales de venta para pedidos para llevar.',
          Icons.delivery_dining,
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const OrderPlatformCatalogScreen(),
            ),
          ),
        ),
      if (employee?.canManageEmployees == true ||
          employee?.hasAdminAccess == true)
        _SettingsLink(
          'Empleados / permisos',
          'Usuarios operativos y permisos.',
          Icons.badge_outlined,
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EmployeeCatalogScreen()),
          ),
        ),
      if (employee?.canManageKitchenStock == true)
        _SettingsLink(
          'Insumos de cocina',
          'Catalogo y rendimiento optimo por insumo.',
          Icons.inventory_2_outlined,
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const KitchenAdminScreen()),
          ),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const _HeaderRow(
          title: 'Configuracion',
          subtitle: 'Catalogos separados del dashboard principal.',
        ),
        const SizedBox(height: 18),
        _ResponsiveGrid(
          minItemWidth: 280,
          children: links
              .map(
                (link) => GlassCard(
                  onTap: link.onTap,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(link.icon, color: BrandColors.accentYellow),
                      const SizedBox(height: 12),
                      Text(
                        link.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        link.subtitle,
                        style: const TextStyle(color: BrandColors.textMuted),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _BackofficeBranchSelector extends StatelessWidget {
  const _BackofficeBranchSelector({required this.repository});

  final TacoPosRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Branch>>(
      stream: repository.watchBranches(activeOnly: true),
      builder: (context, snapshot) {
        final branches =
            snapshot.data ?? AppSession.instance.accessibleBranches;
        final allowedIds = AppSession.instance.accessibleBranches
            .map((branch) => branch.id)
            .toSet();
        final visibleBranches = branches
            .where(
              (branch) =>
                  AppSession.instance.employee?.hasAdminAccess == true ||
                  allowedIds.contains(branch.id),
            )
            .toList();
        final selected =
            visibleBranches.any(
              (branch) => branch.id == AppSession.instance.currentBranchId,
            )
            ? AppSession.instance.currentBranchId
            : (visibleBranches.isEmpty ? null : visibleBranches.first.id);

        if (selected != null &&
            selected != AppSession.instance.currentBranchId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final next = visibleBranches
                .where((branch) => branch.id == selected)
                .firstOrNull;
            if (next != null) AppSession.instance.selectBranch(next);
          });
        }

        if (visibleBranches.isEmpty) {
          return GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.storefront_outlined,
                  color: BrandColors.accentYellow,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Sin sucursal seleccionada',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BranchCatalogScreen(),
                      ),
                    );
                  },
                  child: const Text('Ir a Sucursales'),
                ),
              ],
            ),
          );
        }

        return GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.storefront_outlined,
                color: BrandColors.accentYellow,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selected,
                    isExpanded: true,
                    hint: const Text('Sin sucursal seleccionada'),
                    items: visibleBranches
                        .map(
                          (branch) => DropdownMenuItem(
                            value: branch.id,
                            child: Text(
                              '${branch.restaurantName} · ${branch.name}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      final branch = visibleBranches
                          .where((branch) => branch.id == value)
                          .firstOrNull;
                      if (branch != null) {
                        AppSession.instance.selectBranch(branch);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReportTable extends StatelessWidget {
  const _ReportTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.analytics_outlined,
        title: 'Sin datos',
        message: 'No hay informacion para el reporte seleccionado.',
      );
    }
    return GlassPanel(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: headers
              .map((header) => DataColumn(label: Text(header)))
              .toList(),
          rows: rows
              .map(
                (row) => DataRow(
                  cells: headers
                      .asMap()
                      .keys
                      .map(
                        (index) => DataCell(
                          Text(index < row.length ? row[index] : ''),
                        ),
                      )
                      .toList(),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.children, this.minItemWidth = 220});

  final List<Widget> children;
  final double minItemWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minItemWidth).floor().clamp(
          1,
          6,
        );
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: constraints.maxWidth < 600 ? 1.75 : 1.55,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

class _ExecutiveKpiGrid extends StatelessWidget {
  const _ExecutiveKpiGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1220
            ? 5
            : constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: constraints.maxWidth < 560 ? 1.85 : 1.35,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

class _SecondaryMetricGrid extends StatelessWidget {
  const _SecondaryMetricGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 230).floor().clamp(1, 4);
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: constraints.maxWidth < 560 ? 3.2 : 2.65,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

class _ChartGrid extends StatelessWidget {
  const _ChartGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980 ? 2 : 1;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: constraints.maxWidth < 560 ? 0.96 : 1.28,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

class _InsightGrid extends StatelessWidget {
  const _InsightGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 245).floor().clamp(1, 3);
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: constraints.maxWidth < 560 ? 2.1 : 1.72,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SectionHeader(title: title, subtitle: subtitle);
  }
}

class _GlobalFilters extends StatelessWidget {
  const _GlobalFilters({
    required this.startBusinessDate,
    required this.endBusinessDate,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onToday,
    required this.onWeek,
    required this.onMonth,
  });

  final String startBusinessDate;
  final String endBusinessDate;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onToday;
  final VoidCallback onWeek;
  final VoidCallback onMonth;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            startBusinessDate == endBusinessDate
                ? 'Viendo: $startBusinessDate'
                : 'Viendo: $startBusinessDate a $endBusinessDate',
            style: const TextStyle(fontWeight: FontWeight.w900),
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
          TextButton(onPressed: onToday, child: const Text('Hoy')),
          TextButton(onPressed: onWeek, child: const Text('Esta semana')),
          TextButton(onPressed: onMonth, child: const Text('Este mes')),
        ],
      ),
    );
  }
}

class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String value;
  final Map<String, String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      items: values.entries
          .map(
            (entry) =>
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _InfoText extends StatelessWidget {
  const _InfoText(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: BrandColors.textMuted)),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _FriendlyError extends StatelessWidget {
  const _FriendlyError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: Icons.error_outline,
        title: 'No se pudo cargar',
        message: message,
      ),
    );
  }
}

class _SettingsLink {
  const _SettingsLink(this.title, this.subtitle, this.icon, this.onTap);

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _NavItem {
  const _NavItem(this.section, this.icon, this.label);

  final _BackofficeSection section;
  final IconData icon;
  final String label;
}

class _BarRow {
  const _BarRow(this.label, this.value, this.displayValue);

  final String label;
  final double value;
  final String displayValue;
}

List<DashboardChartDatum> _chartData(List<_BarRow> rows) {
  return rows
      .map(
        (row) => DashboardChartDatum(
          label: row.label,
          value: row.value,
          displayValue: row.displayValue,
        ),
      )
      .toList();
}

class _ItemsSummary {
  const _ItemsSummary({required this.totalQty, required this.topProducts});
  const _ItemsSummary.empty() : totalQty = 0, topProducts = const [];

  final int totalQty;
  final List<_BarRow> topProducts;
}

List<_NavItem> _navItems(Employee? employee) {
  return [
    if (employee?.hasAdminAccess == true)
      const _NavItem(
        _BackofficeSection.dashboard,
        Icons.dashboard_outlined,
        'Dashboard',
      ),
    if (employee?.canViewLiveOperations == true ||
        employee?.hasAdminAccess == true)
      const _NavItem(
        _BackofficeSection.live,
        Icons.monitor_heart_outlined,
        'Visor operativo',
      ),
    if (employee?.hasAdminAccess == true)
      const _NavItem(_BackofficeSection.sales, Icons.receipt_long, 'Ventas'),
    if (employee?.hasAdminAccess == true ||
        employee?.canViewKitchenReports == true)
      const _NavItem(
        _BackofficeSection.reports,
        Icons.analytics_outlined,
        'Reportes',
      ),
    if (employee?.canManageCash == true ||
        employee?.canAuthorizeCashWithdrawals == true)
      const _NavItem(
        _BackofficeSection.cash,
        Icons.point_of_sale_outlined,
        'Caja',
      ),
    if (employee?.canViewKitchenReports == true ||
        employee?.canManageKitchenStock == true)
      const _NavItem(
        _BackofficeSection.kitchen,
        Icons.soup_kitchen_outlined,
        'Cocina',
      ),
    if (employee?.hasAdminAccess == true ||
        employee?.canManageProducts == true ||
        employee?.canManageTables == true ||
        employee?.canManagePlatforms == true ||
        employee?.canManageEmployees == true ||
        employee?.canManageKitchenStock == true)
      const _NavItem(
        _BackofficeSection.settings,
        Icons.settings_outlined,
        'Configuracion',
      ),
  ];
}

bool _canUseBackoffice(Employee? employee) {
  return employee?.hasAdminAccess == true ||
      employee?.canManageCash == true ||
      employee?.canViewKitchenReports == true ||
      employee?.canAuthorizeCashWithdrawals == true ||
      employee?.canViewLiveOperations == true;
}

String _sectionTitle(_BackofficeSection section) {
  return switch (section) {
    _BackofficeSection.dashboard => 'Dashboard',
    _BackofficeSection.live => 'Visor operativo',
    _BackofficeSection.sales => 'Ventas',
    _BackofficeSection.reports => 'Reportes',
    _BackofficeSection.cash => 'Caja',
    _BackofficeSection.kitchen => 'Control de cocina',
    _BackofficeSection.settings => 'Configuracion',
  };
}

String _reportTitle(_ReportKind kind) {
  return switch (kind) {
    _ReportKind.products => 'Ventas por articulo',
    _ReportKind.hourly => 'Ventas por hora',
    _ReportKind.dates => 'Ventas por fecha',
    _ReportKind.kitchenWaste => 'Mermas por insumo',
    _ReportKind.kitchenInventory => 'Entradas y salidas de insumos',
    _ReportKind.platform => 'Ventas por plataforma',
    _ReportKind.paymentMethod => 'Ventas por metodo de pago',
    _ReportKind.employee => 'Ventas por empleado',
    _ReportKind.cashHistory => 'Corte de caja historico',
    _ReportKind.withdrawals => 'Gastos / retiros',
    _ReportKind.kitchenYield => 'Rendimiento de cocina',
    _ReportKind.cancellations => 'Cancelaciones de tickets',
    _ReportKind.cancelledPayments => 'Pagos cancelados',
  };
}

List<String> _reportHeaders(_ReportKind kind) {
  return switch (kind) {
    _ReportKind.products => [
      'Producto',
      'Categoria',
      'Cantidad',
      'Venta base',
      'Promedio precio',
      '%',
    ],
    _ReportKind.hourly => [
      'Hora',
      'Ordenes',
      'Productos',
      'Venta total',
      'Ticket promedio',
      'Metodo predominante',
    ],
    _ReportKind.dates => [
      'Dia',
      'Venta total',
      'Ordenes',
      'Ticket promedio',
      'Efectivo',
      'Tarjeta',
      'Plataforma',
      'Consumo empleado',
    ],
    _ReportKind.kitchenWaste => [
      'Insumo',
      'Unidad',
      'Merma',
      'Fecha',
      'Usuario cierre',
      'Notas',
    ],
    _ReportKind.kitchenInventory => [
      'Insumo',
      'Sobrante anterior',
      'Entradas',
      'Disponible',
      'Sobrante final',
      'Merma',
      'Consumo real',
      'Equivalentes',
      'Rendimiento',
    ],
    _ReportKind.platform => [
      'Plataforma',
      'Venta total',
      'Ticket promedio',
      'Productos vendidos',
    ],
    _ReportKind.paymentMethod => [
      'Metodo',
      'Base',
      'Recargo cliente',
      'Comision absorbida',
      'Total cobrado',
      'Neto estimado',
    ],
    _ReportKind.employee => [
      'Empleado',
      'Ordenes',
      'Venta total',
      'Ticket promedio',
      'Tiempo promedio',
    ],
    _ReportKind.cashHistory => [
      'Fecha',
      'Abre',
      'Cierra',
      'Efectivo esperado',
      'Efectivo contado',
      'Tarjeta esperada',
      'Comision absorbida',
      'Neto tarjeta',
      'Terminal',
      'Faltante',
      'Sobrante',
      'Retiros',
    ],
    _ReportKind.withdrawals => [
      'Fecha',
      'Monto',
      'Motivo',
      'Solicito',
      'Autorizo',
      'Estado',
    ],
    _ReportKind.kitchenYield => [
      'Insumo',
      'Optimo',
      'Actual',
      'Promedio',
      'Diferencia',
    ],
    _ReportKind.cancellations => [
      'Fecha',
      'Folio',
      'Mesa / pedido',
      'Importe',
      'Motivo',
      'Solicito',
      'Cocina',
      'Estado',
      'Hora',
    ],
    _ReportKind.cancelledPayments => [
      'Fecha',
      'Folio',
      'Mesa / pedido',
      'Metodo',
      'Base',
      'Cobrado',
      'Motivo',
      'Cancelado por',
      'Hora',
    ],
  };
}

Future<List<List<String>>> _reportRows(
  TacoPosRepository repository,
  List<PosOrder> orders,
  List<Payment> payments,
  _ReportKind kind,
  String startBusinessDate,
  String endBusinessDate,
) async {
  switch (kind) {
    case _ReportKind.products:
      final summary = await _itemsSummary(repository, orders);
      final totalSales = summary.topProducts.fold<double>(
        0,
        (total, row) => total + row.value,
      );
      return summary.topProducts.map((row) {
        final percent = totalSales <= 0 ? 0 : (row.value / totalSales) * 100;
        return [
          row.label,
          '-',
          row.displayValue,
          _money(row.value),
          '-',
          '${percent.toStringAsFixed(1)}%',
        ];
      }).toList();
    case _ReportKind.hourly:
      return _salesByHour(payments)
          .map((row) => [row.label, '-', '-', row.displayValue, '-', '-'])
          .toList();
    case _ReportKind.dates:
      final byDate = <String, List<Payment>>{};
      for (final payment in payments) {
        final key =
            payment.businessDate ?? _businessDateFor(payment.createdAt) ?? '-';
        byDate.putIfAbsent(key, () => []).add(payment);
      }
      return byDate.entries.map((entry) {
        final list = entry.value;
        final total = _sum(list, (payment) => payment.baseAmount);
        final ordersCount = list
            .map((payment) => payment.orderId)
            .toSet()
            .length;
        return [
          entry.key,
          _money(total),
          '$ordersCount',
          _money(ordersCount == 0 ? 0 : total / ordersCount),
          _money(
            _sum(list.where((p) => p.method == 'cash'), (p) => p.baseAmount),
          ),
          _money(
            _sum(list.where((p) => p.method == 'card'), (p) => p.baseAmount),
          ),
          _money(
            _sum(
              list.where((p) => p.method == 'platform_paid'),
              (p) => p.baseAmount,
            ),
          ),
          _money(
            _sum(
              list.where((p) => p.method == 'employee_consumption'),
              (p) => p.baseAmount,
            ),
          ),
        ];
      }).toList();
    case _ReportKind.platform:
      return _salesByPlatform(
        payments,
      ).map((row) => [row.label, row.displayValue, '-', '-']).toList();
    case _ReportKind.kitchenWaste:
      final rows = await repository.kitchenYieldReport(
        startBusinessDate: startBusinessDate,
        endBusinessDate: endBusinessDate,
      );
      return rows
          .where((row) => row.wasteQty > 0)
          .map(
            (row) => [
              row.item.name,
              row.item.unit,
              _qty(row.wasteQty),
              '$startBusinessDate - $endBusinessDate',
              '-',
              row.currentItem?.notes.isNotEmpty == true
                  ? row.currentItem!.notes
                  : '-',
            ],
          )
          .toList();
    case _ReportKind.kitchenInventory:
      final rows = await repository.kitchenYieldReport(
        startBusinessDate: startBusinessDate,
        endBusinessDate: endBusinessDate,
      );
      return rows
          .map(
            (row) => [
              row.item.name,
              _qty(row.previousRemainingQty),
              _qty(row.initialInputQty + row.additionalEntriesQty),
              _qty(row.availableQty),
              _qty(row.finalRemainingQty),
              _qty(row.wasteQty),
              _qty(row.usefulConsumedQty),
              _qty(row.soldQty),
              row.hasConsumption ? _qty(row.currentYield) : 'Sin consumo',
            ],
          )
          .toList();
    case _ReportKind.paymentMethod:
      final byMethod = <String, List<Payment>>{};
      for (final payment in payments) {
        final label = _paymentMethodLabel(payment.method);
        byMethod.putIfAbsent(label, () => []).add(payment);
      }
      return byMethod.entries.map((entry) {
        final list = entry.value;
        final base = _sum(list, (payment) => payment.baseAmount);
        final surcharge = _sum(list, (payment) => payment.surchargeAmount);
        final absorbedFee = _sum(
          list.where((payment) => payment.method == 'card'),
          (payment) => payment.cardFeeAbsorbedAmount,
        );
        final charged = _sum(list, (payment) => payment.chargedAmount);
        final net = charged - absorbedFee;
        return [
          entry.key,
          _money(base),
          _money(surcharge),
          _money(absorbedFee),
          _money(charged),
          _money(net),
        ];
      }).toList();
    case _ReportKind.employee:
      final byEmployee = <String, List<Payment>>{};
      for (final payment in payments) {
        byEmployee
            .putIfAbsent(payment.employeeName ?? 'Sin usuario', () => [])
            .add(payment);
      }
      return byEmployee.entries.map((entry) {
        final total = _sum(entry.value, (payment) => payment.baseAmount);
        final ordersCount = entry.value
            .map((payment) => payment.orderId)
            .toSet()
            .length;
        return [
          entry.key,
          '$ordersCount',
          _money(total),
          _money(ordersCount == 0 ? 0 : total / ordersCount),
          '-',
        ];
      }).toList();
    case _ReportKind.cashHistory:
      final sessions = await repository
          .watchCashSessions(
            startBusinessDate: startBusinessDate,
            endBusinessDate: endBusinessDate,
          )
          .first;
      return sessions
          .map(
            (session) => [
              session.businessDate,
              session.openedByEmployeeName,
              session.closedByEmployeeName ?? '-',
              _money(session.expectedCashAmount),
              _money(session.countedCashAmount),
              _money(session.expectedCardChargedAmount),
              _money(session.expectedCardFeeAbsorbedAmount),
              _money(
                session.expectedCardChargedAmount -
                    session.expectedCardFeeAbsorbedAmount,
              ),
              _money(session.terminalReportedAmount),
              _money(session.shortageAmount),
              _money(session.overAmount),
              _money(session.approvedWithdrawalsTotal),
            ],
          )
          .toList();
    case _ReportKind.withdrawals:
      final requests = await repository
          .watchCashWithdrawalRequests(
            startBusinessDate: startBusinessDate,
            endBusinessDate: endBusinessDate,
          )
          .first;
      return requests
          .map(
            (request) => [
              request.businessDate,
              _money(request.amount),
              request.reason,
              request.requestedByEmployeeName,
              request.authorizedByEmployeeName ?? '-',
              request.status,
            ],
          )
          .toList();
    case _ReportKind.kitchenYield:
      final rows = await repository.kitchenYieldReport(
        startBusinessDate: startBusinessDate,
        endBusinessDate: endBusinessDate,
      );
      return rows
          .map(
            (row) => [
              row.item.name,
              row.optimalYield.toStringAsFixed(1),
              row.currentYield.toStringAsFixed(1),
              row.averageYield.toStringAsFixed(1),
              (row.currentYield - row.optimalYield).toStringAsFixed(1),
            ],
          )
          .toList();
    case _ReportKind.cancellations:
      final rows = <List<String>>[];
      for (final order in orders.where(
        (order) => order.status == 'cancelled',
      )) {
        rows.add([
          _businessDateFor(order.cancelledAt ?? order.updatedAt) ?? '-',
          _shortId(order.id),
          order.displayName,
          _money(order.total),
          order.cancelReason ?? '-',
          order.cancelledByEmployeeName ?? '-',
          '-',
          'Ticket cancelado',
          _dateTimeText(order.cancelledAt),
        ]);
      }
      for (final order in orders) {
        final items = await repository.getOrderItemsOnce(order.id);
        for (final item in items.where(
          (item) =>
              item.isCancelled ||
              item.hasCancellationRequested ||
              item.wasCancellationRejected,
        )) {
          rows.add([
            _businessDateFor(
                  item.cancelledAt ??
                      item.cancelRequestedAt ??
                      item.cancelRejectedAt ??
                      order.updatedAt,
                ) ??
                '-',
            _shortId(order.id),
            '${order.displayName} | ${item.productName} x${item.qty}',
            _money(item.total),
            getItemCancelReason(item).isEmpty ? '-' : getItemCancelReason(item),
            item.cancelRequestedByEmployeeName ??
                item.cancelledByEmployeeName ??
                '-',
            item.cancelAcceptedByEmployeeName ??
                item.cancelRejectedByEmployeeName ??
                '-',
            item.isCancelled
                ? 'Aceptada'
                : item.wasCancellationRejected
                ? 'Rechazada'
                : 'Solicitada',
            _dateTimeText(
              item.cancelledAt ??
                  item.cancelRequestedAt ??
                  item.cancelRejectedAt,
            ),
          ]);
        }
      }
      return rows;
    case _ReportKind.cancelledPayments:
      return payments.where((payment) => payment.isCancelled).map((payment) {
        return [
          payment.businessDate ?? _businessDateFor(payment.cancelledAt) ?? '-',
          _shortId(payment.orderId),
          payment.tableName,
          _paymentMethodLabel(payment.method),
          _money(payment.baseAmount),
          _money(payment.chargedAmount),
          payment.cancelReason ?? '-',
          payment.cancelledByEmployeeName ?? '-',
          _dateTimeText(payment.cancelledAt),
        ];
      }).toList();
  }
}

Future<_ItemsSummary> _itemsSummary(
  TacoPosRepository repository,
  List<PosOrder> orders,
) async {
  final qtyByProduct = <String, int>{};
  final salesByProduct = <String, double>{};
  var totalQty = 0;
  for (final order in orders.where((order) => order.status != 'cancelled')) {
    final items = await repository.getOrderItemsOnce(order.id);
    for (final item in items.where(
      (item) => item.paymentStatus != 'cancelled',
    )) {
      qtyByProduct[item.productName] =
          (qtyByProduct[item.productName] ?? 0) + item.qty;
      salesByProduct[item.productName] =
          (salesByProduct[item.productName] ?? 0) + item.total;
      totalQty += item.qty;
    }
  }
  final rows = salesByProduct.entries.map((entry) {
    final qty = qtyByProduct[entry.key] ?? 0;
    return _BarRow(entry.key, entry.value, '$qty vendidos');
  }).toList()..sort((a, b) => b.value.compareTo(a.value));
  return _ItemsSummary(totalQty: totalQty, topProducts: rows.take(5).toList());
}

List<_BarRow> _salesByHour(List<Payment> payments) {
  final totals = <int, double>{};
  for (final payment in payments) {
    final hour = payment.createdAt?.hour;
    if (hour == null) continue;
    totals[hour] = (totals[hour] ?? 0) + payment.baseAmount;
  }
  return totals.entries.map((entry) {
    return _BarRow(
      '${entry.key.toString().padLeft(2, '0')}:00',
      entry.value,
      _money(entry.value),
    );
  }).toList()..sort((a, b) => a.label.compareTo(b.label));
}

List<_BarRow> _salesByMethod(List<Payment> payments) {
  final totals = <String, double>{};
  for (final payment in payments) {
    final label = _paymentMethodLabel(payment.method);
    totals[label] = (totals[label] ?? 0) + payment.baseAmount;
  }
  return totals.entries
      .map((entry) => _BarRow(entry.key, entry.value, _money(entry.value)))
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
}

List<_BarRow> _salesByPlatform(List<Payment> payments) {
  final totals = <String, double>{};
  for (final payment in payments) {
    final label =
        payment.platformName ??
        (payment.method == 'platform_paid' ? 'Plataforma' : 'En persona');
    totals[label] = (totals[label] ?? 0) + payment.baseAmount;
  }
  return totals.entries
      .map((entry) => _BarRow(entry.key, entry.value, _money(entry.value)))
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
}

void _openSaleDetail(
  BuildContext context,
  TacoPosRepository repository,
  PosOrder order,
) {
  showDialog<void>(
    context: context,
    builder: (_) => _SaleDetailDialog(repository: repository, order: order),
  );
}

class _SaleDetailDialog extends StatelessWidget {
  const _SaleDetailDialog({required this.repository, required this.order});

  final TacoPosRepository repository;
  final PosOrder order;

  Future<_SaleDetailData> _loadDetail() async {
    final items = await repository.getOrderItemsOnce(order.id);
    final payments = await repository.getOrderPaymentsOnce(order.id);
    return _SaleDetailData(items: items, payments: payments);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: FutureBuilder<_SaleDetailData>(
          future: _loadDetail(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const LoadingPanel(message: 'Cargando venta...');
            }
            final items = snapshot.data!.items;
            final payments = snapshot.data!.payments;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SectionHeader(
                          title: 'Venta ${_shortId(order.id)}',
                          subtitle:
                              '${order.displayName} | ${_dateTimeText(order.createdAt)}',
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 14,
                    runSpacing: 10,
                    children: [
                      _InfoText('Folio', _shortId(order.id)),
                      _InfoText('Estado', formatOrderStatus(order.status)),
                      _InfoText(
                        'Pago',
                        formatPaymentStatus(order.paymentStatus),
                      ),
                      _InfoText('Plataforma', order.platformName ?? '-'),
                      _InfoText('Cliente', order.customerName ?? '-'),
                      _InfoText('Total', _money(order.total)),
                      _InfoText(
                        'A cocina',
                        _durationText(
                          _durationBetween(
                            order.createdAt,
                            order.sentToKitchenAt,
                          ),
                        ),
                      ),
                      _InfoText(
                        'Total atencion',
                        _durationText(
                          _durationBetween(order.createdAt, order.paidAt),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _Timeline(order: order, items: items, payments: payments),
                  const SizedBox(height: 18),
                  _DetailTable(
                    title: 'Items',
                    headers: const [
                      'Persona',
                      'Producto',
                      'Cant.',
                      'Unitario',
                      'Total',
                      'Notas',
                      'Cocina',
                      'Insumo',
                    ],
                    rows: items
                        .map(
                          (item) => [
                            item.personName,
                            item.isCancelled
                                ? '~~${item.productName}~~ Cancelado'
                                : item.productName,
                            '${item.qty}',
                            _money(item.unitPrice),
                            _money(item.total),
                            item.isCancelled &&
                                    getItemCancelReason(item).isNotEmpty
                                ? '${item.notes.trim().isEmpty ? '' : '${item.notes} | '}Motivo: ${getItemCancelReason(item)}'
                                : item.notes,
                            formatKitchenStatus(item.kitchenStatus),
                            item.recipeItems.isEmpty
                                ? item.kitchenStockItemName ?? '-'
                                : '${item.recipeItems.first.kitchenStockItemName} x${_qty(item.recipeItems.first.consumptionFactor)} equiv.',
                          ],
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                  _DetailTable(
                    title: 'Pagos',
                    headers: const [
                      'Metodo',
                      'Base',
                      'Recargo',
                      'Comision absorbida',
                      'Cobrado',
                      'Recibido',
                      'Cambio',
                      'Usuario',
                      'Hora',
                    ],
                    rows: payments
                        .map(
                          (payment) => [
                            _paymentMethodLabel(payment.method),
                            _money(payment.baseAmount),
                            _money(payment.surchargeAmount),
                            _money(payment.cardFeeAbsorbedAmount),
                            _money(payment.chargedAmount),
                            payment.cashReceivedAmount == null
                                ? '-'
                                : _money(payment.cashReceivedAmount!),
                            payment.cashChangeAmount == null
                                ? '-'
                                : _money(payment.cashChangeAmount!),
                            payment.employeeName ?? payment.createdBy ?? '-',
                            _dateTimeText(payment.createdAt),
                          ],
                        )
                        .toList(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SaleDetailData {
  const _SaleDetailData({required this.items, required this.payments});

  final List<OrderItem> items;
  final List<Payment> payments;
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.order,
    required this.items,
    required this.payments,
  });

  final PosOrder order;
  final List<OrderItem> items;
  final List<Payment> payments;

  @override
  Widget build(BuildContext context) {
    final firstItem = items
        .map((item) => item.createdAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (min, date) => min == null || date.isBefore(min) ? date : min,
        );
    final firstCooking = items
        .map((item) => item.cookingAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (min, date) => min == null || date.isBefore(min) ? date : min,
        );
    final lastReady = items
        .map((item) => item.readyAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (max, date) => max == null || date.isAfter(max) ? date : max,
        );
    final firstPayment = payments
        .map((payment) => payment.createdAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (min, date) => min == null || date.isBefore(min) ? date : min,
        );
    final rows = [
      ['Orden creada', order.createdAt],
      ['Primer producto agregado', firstItem],
      ['Enviada a cocina', order.sentToKitchenAt],
      ['Cocina empezo', firstCooking],
      ['Cocina lista', lastReady],
      ['Pago registrado', firstPayment],
      ['Orden cerrada', order.paidAt],
    ];
    return GlassPanel(
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        children: rows
            .map(
              (row) => _InfoText(
                row[0] as String,
                _dateTimeText(row[1] as DateTime?),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DetailTable extends StatelessWidget {
  const _DetailTable({
    required this.title,
    required this.headers,
    required this.rows,
  });

  final String title;
  final List<String> headers;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: headers
                  .map((header) => DataColumn(label: Text(header)))
                  .toList(),
              rows: rows.map((row) {
                return DataRow(
                  cells: headers.asMap().keys.map((index) {
                    return DataCell(Text(index < row.length ? row[index] : ''));
                  }).toList(),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, List<Payment>> _paymentsByOrder(List<Payment> payments) {
  final grouped = <String, List<Payment>>{};
  for (final payment in payments) {
    grouped.putIfAbsent(payment.orderId, () => []).add(payment);
  }
  return grouped;
}

double _sum(Iterable<Payment> payments, double Function(Payment) value) {
  return payments.fold<double>(0, (total, payment) => total + value(payment));
}

Duration? _durationBetween(DateTime? start, DateTime? end) {
  if (start == null || end == null) return null;
  final duration = end.difference(start);
  return duration.isNegative ? null : duration;
}

Duration _averageDuration(List<Duration> durations) {
  if (durations.isEmpty) return Duration.zero;
  final totalSeconds = durations.fold<int>(
    0,
    (total, duration) => total + duration.inSeconds,
  );
  return Duration(seconds: totalSeconds ~/ durations.length);
}

String _durationText(Duration? duration) {
  if (duration == null || duration == Duration.zero) return '-';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${duration.inMinutes}m';
}

String _shortId(String id) => id.length <= 6 ? id : id.substring(0, 6);

String _dateTimeText(DateTime? date) {
  if (date == null) return '-';
  return DateFormat('yyyy-MM-dd HH:mm').format(date);
}

String? _businessDateFor(DateTime? date) {
  if (date == null) return null;
  return DateFormat('yyyy-MM-dd').format(date);
}

String _money(double value) => '\$${value.toStringAsFixed(2)}';

String _qty(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}

String _paymentMethodLabel(String method) {
  return formatPaymentMethod(method);
}

String _topLabel(Iterable<String> values) {
  final counts = <String, int>{};
  for (final value in values.where((value) => value.trim().isNotEmpty)) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  if (counts.isEmpty) return '';
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries.first.key;
}

Future<void> _copyCsv(
  BuildContext context,
  List<String> headers,
  List<List<String>> rows,
) async {
  final csvRows = [
    headers,
    ...rows,
  ].map((row) => row.map(_csvCell).join(',')).join('\n');
  final message = await exportCsvFile(
    fileName:
        'tacopos-reporte-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.csv',
    content: csvRows,
  );
  if (!context.mounted) return;
  showAppSnackBar(context, message, type: AppSnackBarType.success);
}

String _csvCell(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}
