import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/reports/sales_discrepancy_audit.dart';
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
import 'authorization_admin_screen.dart';
import 'branch_catalog_screen.dart';
import 'discount_admin_screen.dart';
import 'employee_catalog_screen.dart';
import 'finance_admin_screen.dart';
import 'kitchen_admin_screen.dart';
import 'live_operations_screen.dart';
import 'order_platform_catalog_screen.dart';
import 'operation_reset_screen.dart';
import 'product_category_catalog_screen.dart';
import 'product_catalog_screen.dart';
import 'purchase_admin_screen.dart';
import 'table_catalog_screen.dart';

enum _BackofficeSection {
  dashboard,
  live,
  sales,
  reports,
  authorizations,
  cash,
  kitchen,
  purchases,
  finance,
  settings,
}

enum _ReportKind {
  products,
  hourly,
  hourlyYesterdayLastSales,
  hourlyPreviousWeek,
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
  productStockOuts,
  salesDiscrepancyAudit,
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
  bool _navCollapsed = false;
  bool _reportsExpanded = false;

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
                      reportKind: _reportKind,
                      onSectionChanged: (value) =>
                          setState(() => _section = value),
                      onReportSelected: (value) => setState(() {
                        _section = _BackofficeSection.reports;
                        _reportKind = value;
                      }),
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
                    reportKind: _reportKind,
                    collapsed: _navCollapsed,
                    reportsExpanded: _reportsExpanded,
                    onSectionChanged: (value) =>
                        setState(() => _section = value),
                    onReportSelected: (value) => setState(() {
                      _section = _BackofficeSection.reports;
                      _reportKind = value;
                      _reportsExpanded = true;
                    }),
                    onReportsExpansionChanged: (value) =>
                        setState(() => _reportsExpanded = value),
                    onToggleCollapsed: () =>
                        setState(() => _navCollapsed = !_navCollapsed),
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
    required this.reportKind,
    required this.collapsed,
    required this.reportsExpanded,
    required this.onSectionChanged,
    required this.onReportSelected,
    required this.onReportsExpansionChanged,
    required this.onToggleCollapsed,
  });

  final _BackofficeSection section;
  final Employee? employee;
  final _ReportKind reportKind;
  final bool collapsed;
  final bool reportsExpanded;
  final ValueChanged<_BackofficeSection> onSectionChanged;
  final ValueChanged<_ReportKind> onReportSelected;
  final ValueChanged<bool> onReportsExpansionChanged;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final items = _navItems(employee);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: collapsed ? 72 : 268,
      padding: EdgeInsets.all(collapsed ? 10 : 18),
      child: GlassPanel(
        padding: EdgeInsets.all(collapsed ? 8 : 14),
        borderRadius: collapsed ? 18 : 26,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SideNavHeader(
              collapsed: collapsed,
              onToggleCollapsed: onToggleCollapsed,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final item in items)
                      _SideNavEntry(
                        item: item,
                        collapsed: collapsed,
                        selected: item.section == section,
                        selectedReport: reportKind,
                        reportsExpanded: reportsExpanded,
                        onSectionChanged: onSectionChanged,
                        onReportSelected: onReportSelected,
                        onReportsExpansionChanged: onReportsExpansionChanged,
                      ),
                  ],
                ),
              ),
            ),
            if (!collapsed) ...[
              const SizedBox(height: 10),
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
            ] else
              IconButton(
                tooltip: 'Salir',
                onPressed: AppSession.instance.signOut,
                icon: const Icon(Icons.logout),
              ),
          ],
        ),
      ),
    );
  }
}

class _SideNavHeader extends StatelessWidget {
  const _SideNavHeader({
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final toggle = IconButton(
      tooltip: collapsed ? 'Expandir menu' : 'Minimizar menu',
      onPressed: onToggleCollapsed,
      icon: Icon(
        collapsed
            ? Icons.keyboard_double_arrow_right
            : Icons.keyboard_double_arrow_left,
      ),
    );
    if (collapsed) {
      return SizedBox(
        height: 86,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: Image.asset(
                'assets/branding/logo_los_padrinos.png',
                fit: BoxFit.contain,
              ),
            ),
            toggle,
          ],
        ),
      );
    }
    return SizedBox(
      height: 52,
      child: Row(
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
          toggle,
        ],
      ),
    );
  }
}

class _SideNavEntry extends StatelessWidget {
  const _SideNavEntry({
    required this.item,
    required this.collapsed,
    required this.selected,
    required this.selectedReport,
    required this.reportsExpanded,
    required this.onSectionChanged,
    required this.onReportSelected,
    required this.onReportsExpansionChanged,
  });

  final _NavItem item;
  final bool collapsed;
  final bool selected;
  final _ReportKind selectedReport;
  final bool reportsExpanded;
  final ValueChanged<_BackofficeSection> onSectionChanged;
  final ValueChanged<_ReportKind> onReportSelected;
  final ValueChanged<bool> onReportsExpansionChanged;

  @override
  Widget build(BuildContext context) {
    final hasChildren = item.children.isNotEmpty;
    if (collapsed && hasChildren) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: PopupMenuButton<_ReportKind>(
          tooltip: item.label,
          position: PopupMenuPosition.over,
          onSelected: onReportSelected,
          itemBuilder: (context) => item.children
              .map(
                (child) => PopupMenuItem(
                  value: child.reportKind!,
                  child: Row(
                    children: [
                      Icon(child.icon, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(child.label)),
                    ],
                  ),
                ),
              )
              .toList(),
          child: _NavButtonSurface(
            icon: item.icon,
            label: item.label,
            collapsed: true,
            selected: selected,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        children: [
          _NavButton(
            item: item,
            collapsed: collapsed,
            selected: selected,
            expanded: hasChildren && reportsExpanded,
            onTap: () {
              if (hasChildren) {
                onSectionChanged(item.section);
                onReportsExpansionChanged(!reportsExpanded);
              } else {
                onSectionChanged(item.section);
              }
            },
          ),
          if (!collapsed && hasChildren)
            AnimatedSize(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: reportsExpanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 5, left: 10),
                      child: Column(
                        children: item.children
                            .map(
                              (child) => Padding(
                                padding: const EdgeInsets.only(bottom: 5),
                                child: _NavButton(
                                  item: child,
                                  dense: true,
                                  collapsed: false,
                                  selected:
                                      child.reportKind == selectedReport &&
                                      selected,
                                  onTap: () =>
                                      onReportSelected(child.reportKind!),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar({
    required this.section,
    required this.employee,
    required this.reportKind,
    required this.onSectionChanged,
    required this.onReportSelected,
  });

  final _BackofficeSection section;
  final Employee? employee;
  final _ReportKind reportKind;
  final ValueChanged<_BackofficeSection> onSectionChanged;
  final ValueChanged<_ReportKind> onReportSelected;

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
                    child: item.children.isEmpty
                        ? ChoiceChip(
                            selected: item.section == section,
                            avatar: Icon(item.icon, size: 18),
                            label: Text(item.label),
                            onSelected: (_) => onSectionChanged(item.section),
                          )
                        : PopupMenuButton<_ReportKind>(
                            tooltip: 'Reportes',
                            onSelected: onReportSelected,
                            itemBuilder: (context) => item.children
                                .map(
                                  (child) => PopupMenuItem(
                                    value: child.reportKind!,
                                    child: Text(child.label),
                                  ),
                                )
                                .toList(),
                            child: ChoiceChip(
                              selected: item.section == section,
                              avatar: Icon(item.icon, size: 18),
                              label: Text(
                                section == item.section
                                    ? _reportTitle(reportKind)
                                    : item.label,
                              ),
                              onSelected: (_) => onSectionChanged(item.section),
                            ),
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
    required this.collapsed,
    required this.onTap,
    this.dense = false,
    this.expanded = false,
  });

  final _NavItem item;
  final bool selected;
  final bool collapsed;
  final bool dense;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: _NavButtonSurface(
        icon: item.icon,
        label: item.label,
        collapsed: collapsed,
        selected: selected,
        dense: dense,
        hasChildren: item.children.isNotEmpty,
        expanded: expanded,
      ),
    );
    return Tooltip(message: item.label, child: button);
  }
}

class _NavButtonSurface extends StatelessWidget {
  const _NavButtonSurface({
    required this.icon,
    required this.label,
    required this.collapsed,
    required this.selected,
    this.dense = false,
    this.hasChildren = false,
    this.expanded = false,
  });

  final IconData icon;
  final String label;
  final bool collapsed;
  final bool selected;
  final bool dense;
  final bool hasChildren;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: dense ? 38 : 44,
        decoration: BoxDecoration(
          color: selected
              ? BrandColors.accentYellow.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? BrandColors.accentYellow : Colors.transparent,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            size: dense ? 18 : 22,
            color: selected ? BrandColors.accentYellow : null,
          ),
        ),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: dense ? 38 : 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: selected
            ? BrandColors.accentYellow.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? BrandColors.accentYellow : Colors.transparent,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 30,
            child: Center(
              child: Icon(
                icon,
                size: dense ? 18 : 22,
                color: selected ? BrandColors.accentYellow : null,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: dense ? 13 : null,
                fontWeight: FontWeight.w800,
                color: selected ? BrandColors.accentYellow : null,
              ),
            ),
          ),
          if (hasChildren) ...[
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 160),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: selected ? BrandColors.accentYellow : null,
              ),
            ),
          ],
        ],
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
    if (section == _BackofficeSection.authorizations) {
      return withBranchHeader(const AuthorizationAdminScreen());
    }
    if (section == _BackofficeSection.kitchen) {
      return withBranchHeader(const KitchenAdminScreen());
    }
    if (section == _BackofficeSection.purchases) {
      return withBranchHeader(const PurchaseAdminScreen());
    }
    if (section == _BackofficeSection.finance) {
      return withBranchHeader(const FinanceAdminScreen());
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
            if (paymentsSnapshot.connectionState == ConnectionState.waiting &&
                !paymentsSnapshot.hasData) {
              return const LoadingPanel(message: 'Cargando reportes...');
            }
            final payments = _paymentsInRange(paymentsSnapshot.data ?? []);
            final activePayments = payments
                .where(_isDashboardActivePayment)
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
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: KeyedSubtree(
                    key: ValueKey('${section.name}-${reportKind.name}'),
                    child: switch (section) {
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
                        orders:
                            reportKind ==
                                    _ReportKind.hourlyYesterdayLastSales ||
                                reportKind == _ReportKind.hourlyPreviousWeek
                            ? allOrders
                            : orders,
                        payments: reportKind == _ReportKind.cancelledPayments
                            ? payments
                            : activePayments,
                        reportKind: reportKind,
                        startBusinessDate: startBusinessDate,
                        endBusinessDate: endBusinessDate,
                      ),
                      _BackofficeSection.authorizations =>
                        const SizedBox.shrink(),
                      _BackofficeSection.live => const SizedBox.shrink(),
                      _BackofficeSection.cash => const SizedBox.shrink(),
                      _BackofficeSection.kitchen => const SizedBox.shrink(),
                      _BackofficeSection.purchases => const SizedBox.shrink(),
                      _BackofficeSection.finance => const SizedBox.shrink(),
                      _BackofficeSection.settings => const SizedBox.shrink(),
                    },
                  ),
                ),
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
    final totalSales = _sum(payments, _dashboardCollectedAmount);
    final collected = totalSales;
    final cash = _sum(
      payments.where((payment) => payment.method == 'cash'),
      _dashboardCollectedAmount,
    );
    final card = _sum(
      payments.where((payment) => payment.method == 'card'),
      _dashboardCollectedAmount,
    );
    final cardFee = _dashboardCardCommission(card);
    final cardNet = card - cardFee;
    final platform = _sum(
      payments.where((payment) => payment.method == 'platform_paid'),
      _dashboardCollectedAmount,
    );
    final employeeConsumption = _sum(
      payments.where((payment) => payment.method == 'employee_consumption'),
      _dashboardCollectedAmount,
    );
    final takeoutOrders = orders.where((order) => order.orderType == 'takeout');
    final servedTables = orders
        .where(
          (order) => order.orderType != 'takeout' && order.tableId.isNotEmpty,
        )
        .map((order) => order.tableId)
        .toSet()
        .length;
    final avgTicket = paidOrders.isEmpty ? 0.0 : totalSales / paidOrders.length;
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
              value: _money(totalSales),
              detail: '${paidOrders.length} ordenes pagadas',
              icon: Icons.trending_up,
            ),
            ExecutiveKpiCard(
              title: 'Cobrado real',
              value: _money(collected),
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
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const LoadingPanel(message: 'Cargando dashboard...');
            }
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

class _ReportsSection extends StatefulWidget {
  const _ReportsSection({
    required this.repository,
    required this.orders,
    required this.payments,
    required this.reportKind,
    required this.startBusinessDate,
    required this.endBusinessDate,
  });

  final TacoPosRepository repository;
  final List<PosOrder> orders;
  final List<Payment> payments;
  final _ReportKind reportKind;
  final String startBusinessDate;
  final String endBusinessDate;

  @override
  State<_ReportsSection> createState() => _ReportsSectionState();
}

class _ReportsSectionState extends State<_ReportsSection> {
  String _stockOutBranchId = '';
  String _stockOutCategory = '';
  String _stockOutProduct = '';
  String _stockOutStatus = 'all';
  late DateTime _hourlyBaseDate;
  late String _hourlySyncedBusinessDate;

  @override
  void initState() {
    super.initState();
    _hourlySyncedBusinessDate = widget.endBusinessDate;
    _hourlyBaseDate =
        _parseBusinessDate(_hourlySyncedBusinessDate) ??
        _startOfDay(DateTime.now());
  }

  @override
  void didUpdateWidget(covariant _ReportsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endBusinessDate != widget.endBusinessDate) {
      _hourlySyncedBusinessDate = widget.endBusinessDate;
      _hourlyBaseDate =
          _parseBusinessDate(_hourlySyncedBusinessDate) ?? _hourlyBaseDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reportKind == _ReportKind.productStockOuts) {
      return _buildProductStockOutReport(context);
    }
    if (widget.reportKind == _ReportKind.salesDiscrepancyAudit) {
      return _buildSalesDiscrepancyAuditReport(context);
    }
    if (widget.reportKind == _ReportKind.hourlyYesterdayLastSales ||
        widget.reportKind == _ReportKind.hourlyPreviousWeek) {
      return _buildHourlyComparisonReport(context);
    }
    return FutureBuilder<List<List<String>>>(
      future: _reportRows(
        widget.repository,
        widget.orders,
        widget.payments,
        widget.reportKind,
        widget.startBusinessDate,
        widget.endBusinessDate,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _reportToolbar(
                rows: const [],
                headers: _reportHeaders(widget.reportKind),
              ),
              const SizedBox(height: 14),
              const LoadingPanel(message: 'Cargando reporte...'),
            ],
          );
        }
        final rows = snapshot.data ?? const <List<String>>[];
        final headers = _reportHeaders(widget.reportKind);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _reportToolbar(rows: rows, headers: headers),
            const SizedBox(height: 14),
            _ReportTable(headers: headers, rows: rows),
          ],
        );
      },
    );
  }

  Widget _reportToolbar({
    required List<List<String>> rows,
    required List<String> headers,
    List<Widget> extraChildren = const [],
  }) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _reportTitle(widget.reportKind),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
          if (extraChildren.isNotEmpty)
            Flexible(
              flex: 2,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: extraChildren,
              ),
            ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: rows.isEmpty
                ? null
                : () => _copyCsv(context, headers, rows),
            icon: const Icon(Icons.download_outlined),
            label: const Text('CSV'),
          ),
        ],
      ),
    );
  }

  Widget _buildHourlyComparisonReport(BuildContext context) {
    final mode = widget.reportKind == _ReportKind.hourlyYesterdayLastSales
        ? _HourlyComparisonMode.yesterdayVsLastSales
        : _HourlyComparisonMode.previousWeek;
    final range = _hourlyQueryRange(mode, _hourlyBaseDate);
    return StreamBuilder<List<Payment>>(
      stream: widget.repository.watchDashboardPayments(
        startDate: range.start,
        endDate: range.end,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _reportToolbar(rows: const [], headers: _hourlyCsvHeaders),
              const SizedBox(height: 14),
              const LoadingPanel(message: 'Cargando ventas por hora...'),
            ],
          );
        }
        if (snapshot.hasError) {
          debugPrint('Hourly comparison report failed: ${snapshot.error}');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _reportToolbar(rows: const [], headers: _hourlyCsvHeaders),
              const SizedBox(height: 14),
              const _FriendlyError(
                message: 'No se pudo cargar el reporte. Intenta nuevamente.',
              ),
            ],
          );
        }
        if (!snapshot.hasData) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _reportToolbar(rows: const [], headers: _hourlyCsvHeaders),
              const SizedBox(height: 14),
              const LoadingPanel(message: 'Cargando ventas por hora...'),
            ],
          );
        }
        final report = _buildHourlyComparison(
          mode: mode,
          payments: snapshot.data ?? const <Payment>[],
          orders: widget.orders,
          baseDate: _hourlyBaseDate,
        );
        final rows = report?.csvRows ?? const <List<String>>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _reportToolbar(
              rows: rows,
              headers: _hourlyCsvHeaders,
              extraChildren: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _hourlyBaseDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime(DateTime.now().year + 2),
                    );
                    if (picked != null && mounted) {
                      setState(() {
                        _hourlyBaseDate = _startOfDay(picked);
                        _hourlySyncedBusinessDate =
                            _businessDateFor(_hourlyBaseDate) ??
                            _hourlySyncedBusinessDate;
                      });
                    }
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    mode == _HourlyComparisonMode.yesterdayVsLastSales
                        ? 'Fecha seleccionada: ${_dateText(_hourlyBaseDate)}'
                        : 'Fecha base: ${_dateText(_hourlyBaseDate)}',
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualizar'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (report == null)
              const EmptyState(
                icon: Icons.query_stats_outlined,
                title: 'Sin comparativo',
                message:
                    'No se encontro un dia anterior con ventas para comparar.',
              )
            else ...[
              _HourlyComparisonSummary(report: report),
              const SizedBox(height: 14),
              _HourlyComparisonChart(report: report),
              const SizedBox(height: 14),
              _HourlyComparisonTable(report: report),
            ],
          ],
        );
      },
    );
  }

  Widget _buildProductStockOutReport(BuildContext context) {
    return StreamBuilder<List<ProductStockOutRow>>(
      stream: widget.repository.watchProductStockOutReport(
        startBusinessDate: widget.startBusinessDate,
        endBusinessDate: widget.endBusinessDate,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _reportToolbar(rows: const [], headers: _stockOutCsvHeaders),
              const SizedBox(height: 14),
              const LoadingPanel(message: 'Cargando productos agotados...'),
            ],
          );
        }
        final allRows = snapshot.data ?? const <ProductStockOutRow>[];
        final branches = _stockOutOptions(
          allRows.map((row) => MapEntry(row.branchId, row.branchName)),
        );
        final categories = _stockOutTextOptions(
          allRows.map((row) => row.categoryName),
        );
        final products = _stockOutTextOptions(
          allRows.map((row) => row.productName),
        );
        final rows = allRows.where((row) {
          if (_stockOutBranchId.isNotEmpty &&
              row.branchId != _stockOutBranchId) {
            return false;
          }
          if (_stockOutCategory.isNotEmpty &&
              row.categoryName != _stockOutCategory) {
            return false;
          }
          if (_stockOutProduct.isNotEmpty &&
              row.productName != _stockOutProduct) {
            return false;
          }
          if (_stockOutStatus == 'active' && !row.isActive) return false;
          if (_stockOutStatus == 'cleared' && !row.isCleared) return false;
          return true;
        }).toList();
        final headers = _reportHeaders(_ReportKind.productStockOuts);
        final tableRows = rows.map(_stockOutReportRow).toList();
        final activeCount = rows.where((row) => row.isActive).length;
        final clearedCount = rows.where((row) => row.isCleared).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _reportToolbar(
              rows: rows.map(_stockOutCsvRow).toList(),
              headers: _stockOutCsvHeaders,
              extraChildren: [
                _SmallMetric('Total registros', '${rows.length}'),
                _SmallMetric('Agotados activos', '$activeCount'),
                _SmallMetric('Liberados', '$clearedCount'),
              ],
            ),
            const SizedBox(height: 10),
            GlassPanel(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _StockOutDropdown(
                    label: 'Sucursal',
                    value: _stockOutBranchId,
                    options: branches,
                    onChanged: (value) =>
                        setState(() => _stockOutBranchId = value ?? ''),
                  ),
                  _StockOutDropdown(
                    label: 'Categoria',
                    value: _stockOutCategory,
                    options: categories,
                    onChanged: (value) =>
                        setState(() => _stockOutCategory = value ?? ''),
                  ),
                  _StockOutDropdown(
                    label: 'Producto',
                    value: _stockOutProduct,
                    options: products,
                    onChanged: (value) =>
                        setState(() => _stockOutProduct = value ?? ''),
                  ),
                  _StockOutDropdown(
                    label: 'Estado',
                    value: _stockOutStatus,
                    options: const {
                      'all': 'Todos',
                      'active': 'Activos',
                      'cleared': 'Liberados',
                    },
                    onChanged: (value) =>
                        setState(() => _stockOutStatus = value ?? 'all'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (snapshot.connectionState == ConnectionState.waiting)
              const LoadingPanel(message: 'Cargando productos agotados...')
            else
              _ReportTable(headers: headers, rows: tableRows),
          ],
        );
      },
    );
  }

  Widget _buildSalesDiscrepancyAuditReport(BuildContext context) {
    return _SalesDiscrepancyAuditReport(
      repository: widget.repository,
      orders: widget.orders,
      startBusinessDate: widget.startBusinessDate,
      endBusinessDate: widget.endBusinessDate,
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
          'Reiniciar operacion',
          'Limpia ventas, ordenes, pagos de clientes, caja, cocina, gastos y sesiones activas. Conserva compras, proveedores y socios.',
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
      if (employee?.hasAdminAccess == true)
        _SettingsLink(
          'Descuentos',
          'Promocion general e historial de descuentos.',
          Icons.percent_outlined,
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DiscountAdminScreen()),
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

class _SmallMetric extends StatelessWidget {
  const _SmallMetric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: BrandColors.glassFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BrandColors.glassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: BrandColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

const _salesAuditHeaders = [
  'Fecha',
  'Folio',
  'Mesa / Para llevar',
  'Cliente',
  'Estado orden',
  'Total articulos bruto',
  'Descuento %',
  r'Descuento $',
  'Tipo descuento',
  'Pago monetario',
  'Total liquidado',
  'Total orden',
  'paidTotal',
  'pendingTotal',
  'Recibido',
  'Cambio',
  'Diferencia real',
  'Tipo discrepancia',
  'Accion',
];

const _salesAuditDiscrepancyTypes = {
  'all': 'Todos',
  'items_order': 'Items/descuento vs total orden',
  'discount_inconsistent': 'Descuento inconsistente',
  'payments_order': 'Liquidacion vs total bruto',
  'cash_net': 'Recibido menos cambio vs pago monetario',
  'paid_total': 'paidTotal vs total liquidado',
  'pending_total': 'pendingTotal incorrecto',
  'duplicate_payment': 'Pago duplicado',
  'paid_incomplete': 'Orden pagada incompleta',
  'cancelled_active_payments': 'Orden cancelada con pagos',
  'state_inconsistent': 'Estado inconsistente',
  'negative_total': 'Total negativo',
  'other': 'Otros',
};

const _salesAuditOrderStatuses = {
  'all': 'Todos',
  'paid': 'Pagadas',
  'open': 'Abiertas',
  'cancelled': 'Canceladas',
  'partial': 'Parciales',
};

class _SalesDiscrepancyAuditReport extends StatefulWidget {
  const _SalesDiscrepancyAuditReport({
    required this.repository,
    required this.orders,
    required this.startBusinessDate,
    required this.endBusinessDate,
  });

  final TacoPosRepository repository;
  final List<PosOrder> orders;
  final String startBusinessDate;
  final String endBusinessDate;

  @override
  State<_SalesDiscrepancyAuditReport> createState() =>
      _SalesDiscrepancyAuditReportState();
}

class _SalesDiscrepancyAuditReportState
    extends State<_SalesDiscrepancyAuditReport> {
  final _queryController = TextEditingController();
  bool _onlyDiscrepancies = true;
  String _discrepancyType = 'all';
  String _orderStatus = 'all';
  late Future<List<_SalesAuditRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadRows();
  }

  @override
  void didUpdateWidget(covariant _SalesDiscrepancyAuditReport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orders != widget.orders ||
        oldWidget.startBusinessDate != widget.startBusinessDate ||
        oldWidget.endBusinessDate != widget.endBusinessDate) {
      _future = _loadRows();
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<List<_SalesAuditRow>> _loadRows() async {
    final rows = <_SalesAuditRow>[];
    for (final order in widget.orders) {
      try {
        final items = await widget.repository.getOrderItemsOnce(order.id);
        final payments = await widget.repository.getOrderPaymentsOnce(order.id);
        rows.add(_buildSalesAuditRow(order, items, payments));
      } catch (error) {
        debugPrint('Sales discrepancy audit failed for ${order.id}: $error');
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_SalesAuditRow>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _auditToolbar(const []),
              const SizedBox(height: 14),
              const LoadingPanel(message: 'Auditando ventas...'),
            ],
          );
        }
        if (snapshot.hasError) {
          debugPrint('Sales discrepancy audit failed: ${snapshot.error}');
          return const _FriendlyError(
            message: 'No se pudo cargar la auditoria de ventas.',
          );
        }
        final allRows = snapshot.data ?? const <_SalesAuditRow>[];
        final rows = _filteredRows(allRows);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _auditToolbar(rows),
            const SizedBox(height: 14),
            _SalesAuditSummary(rows: allRows, reviewedCount: allRows.length),
            const SizedBox(height: 14),
            if (rows.isEmpty)
              EmptyState(
                icon: Icons.rule_folder_outlined,
                title: _onlyDiscrepancies
                    ? 'Sin discrepancias'
                    : 'Sin ventas para mostrar',
                message:
                    'Ajusta los filtros o amplia el rango para revisar mas ordenes.',
              )
            else
              _SalesAuditTable(
                rows: rows,
                onOpen: (row) => _openAuditDetail(row),
              ),
          ],
        );
      },
    );
  }

  Widget _auditToolbar(List<_SalesAuditRow> rows) {
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: _queryController,
              decoration: const InputDecoration(
                labelText: 'Folio / cliente / mesa',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          _StockOutDropdown(
            label: 'Sucursal',
            value: AppSession.instance.currentBranchId,
            options: {
              AppSession.instance.currentBranchId:
                  AppSession.instance.currentBranchName,
            },
            onChanged: (_) {},
          ),
          _StockOutDropdown(
            label: 'Tipo',
            value: _discrepancyType,
            options: _salesAuditDiscrepancyTypes,
            onChanged: (value) =>
                setState(() => _discrepancyType = value ?? 'all'),
          ),
          _StockOutDropdown(
            label: 'Estado orden',
            value: _orderStatus,
            options: _salesAuditOrderStatuses,
            onChanged: (value) => setState(() => _orderStatus = value ?? 'all'),
          ),
          FilterChip(
            selected: _onlyDiscrepancies,
            label: const Text('Solo con discrepancias'),
            onSelected: (value) => setState(() => _onlyDiscrepancies = value),
          ),
          FilledButton.icon(
            onPressed: () => setState(() => _future = _loadRows()),
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar'),
          ),
          FilledButton.icon(
            onPressed: rows.isEmpty
                ? null
                : () => _copyCsv(context, _salesAuditCsvHeaders, [
                    for (final row in rows) row.csvRow,
                  ]),
            icon: const Icon(Icons.download_outlined),
            label: const Text('CSV'),
          ),
        ],
      ),
    );
  }

  List<_SalesAuditRow> _filteredRows(List<_SalesAuditRow> rows) {
    final query = _queryController.text.trim().toLowerCase();
    return rows.where((row) {
      if (_onlyDiscrepancies && !row.hasDiscrepancy) return false;
      if (_discrepancyType != 'all' &&
          !row.discrepancyCodes.contains(_discrepancyType)) {
        return false;
      }
      if (_orderStatus != 'all' &&
          row.order.status.trim().toLowerCase() != _orderStatus &&
          row.order.paymentStatus.trim().toLowerCase() != _orderStatus) {
        return false;
      }
      if (query.isEmpty) return true;
      return [
        _shortId(row.order.id),
        row.order.id,
        row.order.displayName,
        row.order.customerName ?? '',
      ].any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  void _openAuditDetail(_SalesAuditRow row) {
    showDialog<void>(
      context: context,
      builder: (_) => _SalesAuditDetailDialog(
        row: row,
        onOpenSale: () {
          Navigator.pop(context);
          _openSaleDetail(context, widget.repository, row.order);
        },
      ),
    );
  }
}

class _SalesAuditSummary extends StatelessWidget {
  const _SalesAuditSummary({required this.rows, required this.reviewedCount});

  final List<_SalesAuditRow> rows;
  final int reviewedCount;

  @override
  Widget build(BuildContext context) {
    final discrepant = rows.where((row) => row.hasDiscrepancy).toList();
    final correctCount = reviewedCount - discrepant.length;
    final integrityPercent = reviewedCount == 0
        ? '0.0%'
        : '${((correctCount / reviewedCount) * 100).toStringAsFixed(1)}%';
    final dates =
        discrepant
            .map((row) => _businessDateFor(row.order.createdAt))
            .whereType<String>()
            .toList()
          ..sort();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _SmallMetric('Ordenes revisadas', '$reviewedCount'),
        _SmallMetric('Ordenes correctas', '$correctCount'),
        _SmallMetric('Ordenes con discrepancia', '${discrepant.length}'),
        _SmallMetric('Integridad', integrityPercent),
        _SmallMetric(
          'Dif. items vs orden',
          _money(rows.fold(0, (sum, row) => sum + row.diffItemsOrder)),
        ),
        _SmallMetric(
          'Dif. liquidacion',
          _money(rows.fold(0, (sum, row) => sum + row.diffPaymentsOrder)),
        ),
        _SmallMetric(
          'Efectivo inconsistente',
          '${rows.where((row) => row.cashPaymentMismatchCount > 0).length}',
        ),
        _SmallMetric('Primera fecha', dates.isEmpty ? '-' : dates.first),
        _SmallMetric('Ultima fecha', dates.isEmpty ? '-' : dates.last),
      ],
    );
  }
}

class _SalesAuditTable extends StatefulWidget {
  const _SalesAuditTable({required this.rows, required this.onOpen});

  final List<_SalesAuditRow> rows;
  final ValueChanged<_SalesAuditRow> onOpen;

  @override
  State<_SalesAuditTable> createState() => _SalesAuditTableState();
}

class _SalesAuditTableState extends State<_SalesAuditTable> {
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  Widget build(BuildContext context) {
    final sortedRows = [...widget.rows];
    final sortColumnIndex = _sortColumnIndex;
    if (sortColumnIndex != null) {
      sortedRows.sort((a, b) {
        final result = _compareReportCells(
          a.tableCells[sortColumnIndex],
          b.tableCells[sortColumnIndex],
        );
        return _sortAscending ? result : -result;
      });
    }
    return GlassPanel(
      padding: const EdgeInsets.all(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 640),
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              sortColumnIndex: _sortColumnIndex,
              sortAscending: _sortAscending,
              headingRowHeight: 42,
              dataRowMinHeight: 38,
              dataRowMaxHeight: 50,
              horizontalMargin: 14,
              columnSpacing: 22,
              columns: _salesAuditHeaders.asMap().entries.map((entry) {
                return DataColumn(
                  label: Text(entry.value),
                  onSort: entry.key == _salesAuditHeaders.length - 1
                      ? null
                      : (columnIndex, ascending) {
                          setState(() {
                            _sortColumnIndex = columnIndex;
                            _sortAscending = ascending;
                          });
                        },
                );
              }).toList(),
              rows: sortedRows.map((row) {
                return DataRow(
                  cells: [
                    for (final cell in row.tableCells) DataCell(Text(cell)),
                    DataCell(
                      TextButton.icon(
                        onPressed: () => widget.onOpen(row),
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Detalle'),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _SalesAuditDetailDialog extends StatelessWidget {
  const _SalesAuditDetailDialog({required this.row, required this.onOpenSale});

  final _SalesAuditRow row;
  final VoidCallback onOpenSale;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SectionHeader(
                      title: 'Auditoria ${_shortId(row.order.id)}',
                      subtitle:
                          '${_dateTimeText(row.order.createdAt)} | ${row.order.branchName}',
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GlassPanel(
                child: Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  children: [
                    _InfoText('OrderId', row.order.id),
                    _InfoText('Folio', _shortId(row.order.id)),
                    _InfoText('Sucursal', row.order.branchName),
                    _InfoText('Mesa / pedido', row.order.displayName),
                    _InfoText('Cliente', row.order.customerName ?? '-'),
                    _InfoText('Estado', row.order.status),
                    _InfoText('Pago', row.order.paymentStatus),
                    _InfoText('Cocina', row.order.kitchenStatus),
                    _InfoText('Audit mode', row.auditModeLabel),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GlassPanel(
                child: Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  children: [
                    _InfoText('Items activos', '${row.activeItemCount}'),
                    _InfoText('Items cancelados', '${row.cancelledItemCount}'),
                    _InfoText(
                      'Total articulos bruto',
                      _money(row.itemsSubtotal),
                    ),
                    _InfoText(
                      'Descuento monetario',
                      _money(row.explicitDiscount),
                    ),
                    _InfoText('Descuento %', row.discountPercentText),
                    _InfoText('Tipo descuento', row.discountTypeLabel),
                    _InfoText('Nombre descuento', row.discountName),
                    _InfoText('Motivo descuento', row.discountReason),
                    _InfoText('Beneficiario', row.discountBeneficiary),
                    _InfoText('Autorizo', row.discountAuthorizedBy),
                    _InfoText(
                      'Pago monetario',
                      _money(row.paymentsAppliedTotal),
                    ),
                    _InfoText('Total liquidado', _money(row.settledTotal)),
                    _InfoText(
                      'Total neto calculado',
                      _money(row.expectedOrderTotal),
                    ),
                    _InfoText('Total orden', _money(row.order.total)),
                    _InfoText('paidTotal', _money(row.order.paidTotal)),
                    _InfoText('pendingTotal', _money(row.order.pendingTotal)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _DetailTable(
                title: 'Origen del descuento',
                headers: const [
                  'Campo Firestore',
                  'Valor crudo',
                  'Tipo',
                  'Porcentaje',
                  'Importe',
                  'Tipo desc.',
                  'Nombre',
                  'Motivo',
                  'Beneficiario',
                  'Autorizo',
                  'Fecha',
                  'Usado',
                  'Detalle',
                ],
                rows: row.discountSources.isEmpty
                    ? const [
                        [
                          'Sin campos de descuento',
                          r'$0.00',
                          '-',
                          '-',
                          r'$0.00',
                          'Sin descuento',
                          '-',
                          '-',
                          '-',
                          '-',
                          '-',
                          'No',
                          '-',
                        ],
                      ]
                    : row.discountSources
                          .map(
                            (source) => [
                              source.field,
                              source.originalValue.toStringAsFixed(2),
                              source.kind,
                              source.normalizedPercent == null
                                  ? '-'
                                  : '${(source.normalizedPercent! * 100).toStringAsFixed(2)}%',
                              _money(source.monetaryAmount),
                              source.discountTypeLabel,
                              source.discountName.isEmpty
                                  ? '-'
                                  : source.discountName,
                              source.discountReason.isEmpty
                                  ? '-'
                                  : source.discountReason,
                              source.discountBeneficiary.isEmpty
                                  ? '-'
                                  : source.discountBeneficiary,
                              source.discountAuthorizedBy.isEmpty
                                  ? '-'
                                  : source.discountAuthorizedBy,
                              source.appliedAt == null
                                  ? '-'
                                  : _dateTimeText(source.appliedAt),
                              source.used ? 'Si' : 'No',
                              [source.interpretation, source.metadata]
                                  .where((text) => text.trim().isNotEmpty)
                                  .join(' | '),
                            ],
                          )
                          .toList(),
              ),
              const SizedBox(height: 12),
              _DetailTable(
                title: 'Items',
                headers: const [
                  'Producto',
                  'Cantidad',
                  'UnitPrice',
                  'Total',
                  'Status',
                  'Kitchen',
                  'CancelStatus',
                  'Activo',
                ],
                rows: row.items.map((item) {
                  return [
                    item.productName,
                    '${item.qty}',
                    _money(item.unitPrice),
                    _money(item.qty * item.unitPrice),
                    item.status,
                    item.kitchenStatus,
                    item.cancelStatus,
                    item.isCancelled ? 'No' : 'Si',
                  ];
                }).toList(),
              ),
              const SizedBox(height: 12),
              _DetailTable(
                title: 'Pagos',
                headers: const [
                  'PaymentId',
                  'Metodo',
                  'Status',
                  'Amount',
                  'Pago monetario',
                  'Base',
                  'Cobrado',
                  'Recibido',
                  'Cambio',
                  'Discount',
                  'Discount %',
                  'Discount type',
                  'Recargo',
                  'Comision',
                  'Hora',
                  'Usuario',
                ],
                rows: row.payments.map((payment) {
                  return [
                    payment.id,
                    _paymentMethodLabel(payment.method),
                    payment.status,
                    _money(payment.amount),
                    _money(salesAuditMoneyPaymentAmount(payment)),
                    _money(payment.baseAmount),
                    _money(payment.chargedAmount),
                    payment.cashReceivedAmount == null
                        ? '-'
                        : _money(payment.cashReceivedAmount!),
                    payment.cashChangeAmount == null
                        ? '-'
                        : _money(payment.cashChangeAmount!),
                    _money(payment.discountAmount),
                    payment.appliedDiscountPercent <= 0
                        ? '-'
                        : '${(payment.appliedDiscountPercent > 1 ? payment.appliedDiscountPercent : payment.appliedDiscountPercent * 100).toStringAsFixed(2)}%',
                    payment.appliedDiscountType ??
                        payment.appliedDiscountName ??
                        '-',
                    _money(payment.surchargeAmount),
                    _money(payment.cardFeeAbsorbedAmount),
                    _dateTimeText(payment.createdAt),
                    payment.employeeName ?? payment.createdBy ?? '-',
                  ];
                }).toList(),
              ),
              const SizedBox(height: 12),
              _DetailTable(
                title: 'Validaciones',
                headers: const ['Resultado', 'Validacion', 'Detalle'],
                rows: row.validations.map((validation) {
                  return [
                    validation.passed ? 'Correcta' : 'Discrepancia',
                    validation.label,
                    validation.detail.isEmpty ? '-' : validation.detail,
                  ];
                }).toList(),
              ),
              const SizedBox(height: 12),
              GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Diagnostico',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    ...row.diagnostics.map((text) => Text('- $text')),
                    const SizedBox(height: 10),
                    Text('Formula items: ${row.itemsFormula}'),
                    Text('Formula pagos: ${row.paymentsFormula}'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onOpenSale,
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Ver venta'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SalesAuditRow {
  const _SalesAuditRow({
    required this.order,
    required this.items,
    required this.payments,
    required this.activeItemCount,
    required this.cancelledItemCount,
    required this.itemsSubtotal,
    required this.explicitDiscount,
    required this.expectedOrderTotal,
    required this.paymentsAppliedTotal,
    required this.settledTotal,
    required this.receivedTotal,
    required this.changeTotal,
    required this.diffItemsOrder,
    required this.diffPaymentsOrder,
    required this.diffPaidTotal,
    required this.diffPendingTotal,
    required this.cashPaymentMismatchCount,
    required this.discrepancyCodes,
    required this.diagnostics,
    required this.discountFields,
    required this.discountSources,
    required this.discountPercentNormalized,
    required this.discountTypeLabel,
    required this.discountName,
    required this.discountReason,
    required this.discountBeneficiary,
    required this.discountAuthorizedBy,
    required this.discountSourceFields,
    required this.validations,
    required this.auditMode,
  });

  final PosOrder order;
  final List<OrderItem> items;
  final List<Payment> payments;
  final int activeItemCount;
  final int cancelledItemCount;
  final double itemsSubtotal;
  final double explicitDiscount;
  final double expectedOrderTotal;
  final double paymentsAppliedTotal;
  final double settledTotal;
  final double receivedTotal;
  final double changeTotal;
  final double diffItemsOrder;
  final double diffPaymentsOrder;
  final double diffPaidTotal;
  final double diffPendingTotal;
  final int cashPaymentMismatchCount;
  final List<String> discrepancyCodes;
  final List<String> diagnostics;
  final Map<String, double> discountFields;
  final List<SalesAuditDiscountSource> discountSources;
  final double? discountPercentNormalized;
  final String discountTypeLabel;
  final String discountName;
  final String discountReason;
  final String discountBeneficiary;
  final String discountAuthorizedBy;
  final String discountSourceFields;
  final List<SalesAuditValidation> validations;
  final SalesAuditMode auditMode;

  bool get hasDiscrepancy => discrepancyCodes.isNotEmpty;
  double get primaryDifference {
    if (diffItemsOrder.abs() > salesAuditMoneyTolerance) return diffItemsOrder;
    if (diffPaymentsOrder.abs() > salesAuditMoneyTolerance) {
      return diffPaymentsOrder;
    }
    if (diffPaidTotal.abs() > salesAuditMoneyTolerance) return diffPaidTotal;
    if (diffPendingTotal.abs() > salesAuditMoneyTolerance) {
      return diffPendingTotal;
    }
    return 0;
  }

  String get auditModeLabel => switch (auditMode) {
    SalesAuditMode.paid => 'pagada',
    SalesAuditMode.partial => 'parcial',
    SalesAuditMode.cancelled => 'cancelada',
    SalesAuditMode.pending => 'pendiente',
  };

  String get discrepancyLabel => hasDiscrepancy
      ? discrepancyCodes
            .map((code) => _salesAuditDiscrepancyTypes[code] ?? code)
            .join(' | ')
      : 'Sin discrepancias';

  String get discountPercentText => discountPercentNormalized == null
      ? '-'
      : '${(discountPercentNormalized! * 100).toStringAsFixed(2)}%';

  List<String> get tableCells => [
    _businessDateFor(order.createdAt ?? order.paidAt) ?? '-',
    _shortId(order.id),
    order.displayName,
    order.customerName ?? '-',
    '${order.status} / ${order.paymentStatus}',
    _money(itemsSubtotal),
    discountPercentText,
    _money(explicitDiscount),
    discountTypeLabel,
    _money(paymentsAppliedTotal),
    _money(settledTotal),
    _money(order.total),
    _money(order.paidTotal),
    _money(order.pendingTotal),
    _money(receivedTotal),
    _money(changeTotal),
    _money(primaryDifference),
    discrepancyLabel,
  ];

  List<String> get csvRow => [
    _businessDateFor(order.createdAt ?? order.paidAt) ?? '-',
    _shortId(order.id),
    order.id,
    order.status,
    order.paymentStatus,
    _money(itemsSubtotal),
    discountPercentText,
    _money(explicitDiscount),
    discountTypeLabel,
    discountName.isEmpty ? '-' : discountName,
    discountReason.isEmpty ? '-' : discountReason,
    discountBeneficiary.isEmpty ? '-' : discountBeneficiary,
    discountAuthorizedBy.isEmpty ? '-' : discountAuthorizedBy,
    _money(paymentsAppliedTotal),
    _money(settledTotal),
    _money(order.total),
    _money(order.paidTotal),
    _money(order.pendingTotal),
    _money(receivedTotal),
    _money(changeTotal),
    _money(primaryDifference),
    discrepancyLabel,
    discountSourceFields.isEmpty ? '-' : discountSourceFields,
    discountSources.isEmpty
        ? '-'
        : discountSources
              .map(
                (source) =>
                    '${source.used ? '*' : ''}${source.field}: raw=${source.originalValue.toStringAsFixed(2)} amount=${_money(source.monetaryAmount)} type=${source.discountTypeLabel}',
              )
              .join(' | '),
    diagnostics.join(' | '),
  ];

  String get itemsFormula =>
      'totalArticulosBruto (${_money(itemsSubtotal)}) - descuentoMonetario (${_money(explicitDiscount)}) = totalNetoCalculado (${_money(expectedOrderTotal)})';
  String get paymentsFormula =>
      'pagoMonetario (${_money(paymentsAppliedTotal)}) + descuentoMonetario (${_money(explicitDiscount)}) = totalLiquidado (${_money(settledTotal)})';
}

const _salesAuditCsvHeaders = [
  'fecha',
  'folio',
  'orderId',
  'estado orden',
  'estado pago',
  'total articulos bruto',
  'discountPercent',
  'descuento monetario valido',
  'discountType',
  'discountName',
  'discountReason',
  'discountBeneficiary',
  'discountAuthorizedBy',
  'pago monetario',
  'total liquidado',
  'total orden',
  'paidTotal',
  'pendingTotal',
  'recibido',
  'cambio',
  'diferencia',
  'tipos de discrepancia',
  'campos fuente usados',
  'interpretacion descuentos',
  'validaciones fallidas',
];

_SalesAuditRow _buildSalesAuditRow(
  PosOrder order,
  List<OrderItem> items,
  List<Payment> payments,
) {
  final audit = auditSalesIntegrity(order, items, payments);
  return _SalesAuditRow(
    order: order,
    items: items,
    payments: payments,
    activeItemCount: audit.activeItems.length,
    cancelledItemCount: audit.cancelledItems.length,
    itemsSubtotal: audit.grossItemsTotal,
    explicitDiscount: audit.monetaryDiscountApplied,
    expectedOrderTotal: audit.netCustomerDue,
    paymentsAppliedTotal: audit.moneyPaymentsApplied,
    settledTotal: audit.settledTotal,
    receivedTotal: audit.receivedTotal,
    changeTotal: audit.changeTotal,
    diffItemsOrder: audit.diffItemsOrder,
    diffPaymentsOrder: audit.diffSettlement,
    diffPaidTotal: audit.diffPaidTotal,
    diffPendingTotal: audit.diffPendingTotal,
    cashPaymentMismatchCount: audit.cashPaymentMismatchCount,
    discrepancyCodes: audit.failedCodes,
    diagnostics: audit.diagnostics,
    discountFields: audit.discountFields,
    discountSources: audit.discountSources,
    discountPercentNormalized: audit.discountPercentNormalized,
    discountTypeLabel: audit.discountTypeLabel,
    discountName: audit.discountName,
    discountReason: audit.discountReason,
    discountBeneficiary: audit.discountBeneficiary,
    discountAuthorizedBy: audit.discountAuthorizedBy,
    discountSourceFields: audit.discountSourceFields,
    validations: audit.validations,
    auditMode: audit.auditMode,
  );
}

class _StockOutDropdown extends StatelessWidget {
  const _StockOutDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = options.containsKey(value) ? value : '';
    return SizedBox(
      width: 210,
      child: DropdownButtonFormField<String>(
        initialValue: safeValue,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: '', child: Text('Todos')),
          ...options.entries
              .where((entry) => entry.key.isNotEmpty)
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              ),
        ],
        onChanged: onChanged,
      ),
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

class _ReportTable extends StatefulWidget {
  const _ReportTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;

  @override
  State<_ReportTable> createState() => _ReportTableState();
}

class _ReportTableState extends State<_ReportTable> {
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return const EmptyState(
        icon: Icons.analytics_outlined,
        title: 'Sin datos',
        message: 'No hay informacion para el reporte seleccionado.',
      );
    }
    final sortedRows = [...widget.rows];
    final sortColumnIndex = _sortColumnIndex;
    if (sortColumnIndex != null) {
      sortedRows.sort((a, b) {
        final result = _compareReportCells(
          sortColumnIndex < a.length ? a[sortColumnIndex] : '',
          sortColumnIndex < b.length ? b[sortColumnIndex] : '',
        );
        return _sortAscending ? result : -result;
      });
    }
    return GlassPanel(
      padding: const EdgeInsets.all(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 640),
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              sortColumnIndex: _sortColumnIndex,
              sortAscending: _sortAscending,
              headingRowHeight: 42,
              dataRowMinHeight: 38,
              dataRowMaxHeight: 46,
              horizontalMargin: 14,
              columnSpacing: 22,
              columns: widget.headers
                  .asMap()
                  .entries
                  .map(
                    (entry) => DataColumn(
                      label: Text(entry.value),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortColumnIndex = columnIndex;
                          _sortAscending = ascending;
                        });
                      },
                    ),
                  )
                  .toList(),
              rows: sortedRows
                  .map(
                    (row) => DataRow(
                      cells: widget.headers
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
        ),
      ),
    );
  }
}

int _compareReportCells(String a, String b) {
  final aDate = _tryParseReportDate(a);
  final bDate = _tryParseReportDate(b);
  if (aDate != null && bDate != null) return aDate.compareTo(bDate);

  final aNumber = _tryParseReportNumber(a);
  final bNumber = _tryParseReportNumber(b);
  if (aNumber != null && bNumber != null) return aNumber.compareTo(bNumber);

  return a.toLowerCase().trim().compareTo(b.toLowerCase().trim());
}

DateTime? _tryParseReportDate(String value) {
  final clean = value.trim();
  if (clean.isEmpty || clean == '-') return null;
  final formats = [
    'yyyy-MM-dd HH:mm',
    'yyyy-MM-dd',
    'dd/MM/yyyy HH:mm',
    'dd/MM/yyyy',
    'dd/MM',
  ];
  for (final pattern in formats) {
    try {
      final parsed = DateFormat(pattern).parseStrict(clean);
      if (pattern == 'dd/MM') {
        final now = DateTime.now();
        return DateTime(now.year, parsed.month, parsed.day);
      }
      return parsed;
    } on FormatException {
      continue;
    }
  }
  return null;
}

double? _tryParseReportNumber(String value) {
  final clean = value
      .replaceAll(RegExp(r'[\$,%%]'), '')
      .replaceAll(',', '')
      .trim();
  if (clean.isEmpty || clean == '-') return null;
  return double.tryParse(clean);
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
  const _NavItem(
    this.section,
    this.icon,
    this.label, {
    this.reportKind,
    this.children = const [],
  });

  final _BackofficeSection section;
  final IconData icon;
  final String label;
  final _ReportKind? reportKind;
  final List<_NavItem> children;
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
  const _ItemsSummary({required this.totalQty, required this.products});
  const _ItemsSummary.empty() : totalQty = 0, products = const [];

  final int totalQty;
  final List<_ProductSalesRow> products;

  List<_BarRow> get topProducts => products
      .take(5)
      .map((row) => _BarRow(row.productName, row.value, '${row.qty} vendidos'))
      .toList();
}

class _ProductSalesAccumulator {
  _ProductSalesAccumulator({
    required this.productName,
    required this.categoryName,
  });

  final String productName;
  final String categoryName;
  int qty = 0;
  double value = 0;

  void add({required int qty, required double value}) {
    this.qty += qty;
    this.value += value;
  }

  _ProductSalesRow toRow() {
    return _ProductSalesRow(
      productName: productName,
      categoryName: categoryName,
      qty: qty,
      value: value,
    );
  }
}

class _ProductSalesRow {
  const _ProductSalesRow({
    required this.productName,
    required this.categoryName,
    required this.qty,
    required this.value,
  });

  final String productName;
  final String categoryName;
  final int qty;
  final double value;

  double get averagePrice => qty <= 0 ? 0 : value / qty;
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
      _NavItem(
        _BackofficeSection.reports,
        Icons.analytics_outlined,
        'Reportes',
        children: _reportNavItems(employee),
      ),
    if (_canUseBackoffice(employee))
      const _NavItem(
        _BackofficeSection.authorizations,
        Icons.verified_user_outlined,
        'Autorizaciones',
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
    if (kIsWeb &&
        (employee?.hasAdminAccess == true ||
            employee?.canViewPurchases == true ||
            employee?.canManageSuppliers == true ||
            employee?.canRegisterPurchases == true ||
            employee?.canPaySuppliers == true ||
            employee?.canViewAccountsPayable == true ||
            employee?.canViewPurchaseReports == true))
      const _NavItem(
        _BackofficeSection.purchases,
        Icons.local_shipping_outlined,
        'Compras',
      ),
    if (kIsWeb &&
        (employee?.hasAdminAccess == true ||
            employee?.canViewPurchases == true ||
            employee?.canPaySuppliers == true ||
            employee?.canViewAccountsPayable == true ||
            employee?.canViewPurchaseReports == true))
      const _NavItem(
        _BackofficeSection.finance,
        Icons.account_balance_wallet_outlined,
        'Finanzas',
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

List<_NavItem> _reportNavItems(Employee? employee) {
  final canKitchen =
      employee?.hasAdminAccess == true ||
      employee?.canViewKitchenReports == true;
  return [
    const _NavItem(
      _BackofficeSection.reports,
      Icons.inventory_2_outlined,
      'Ventas por articulo',
      reportKind: _ReportKind.products,
    ),
    const _NavItem(
      _BackofficeSection.reports,
      Icons.schedule_outlined,
      'Ventas por hora',
      reportKind: _ReportKind.hourly,
    ),
    const _NavItem(
      _BackofficeSection.reports,
      Icons.compare_arrows_outlined,
      'Dia seleccionado vs ultimo dia con ventas',
      reportKind: _ReportKind.hourlyYesterdayLastSales,
    ),
    const _NavItem(
      _BackofficeSection.reports,
      Icons.stacked_line_chart_outlined,
      'Comparacion contra semana anterior',
      reportKind: _ReportKind.hourlyPreviousWeek,
    ),
    const _NavItem(
      _BackofficeSection.reports,
      Icons.calendar_month_outlined,
      'Ventas por fecha',
      reportKind: _ReportKind.dates,
    ),
    const _NavItem(
      _BackofficeSection.reports,
      Icons.storefront_outlined,
      'Ventas por plataforma',
      reportKind: _ReportKind.platform,
    ),
    const _NavItem(
      _BackofficeSection.reports,
      Icons.payments_outlined,
      'Metodos de pago',
      reportKind: _ReportKind.paymentMethod,
    ),
    const _NavItem(
      _BackofficeSection.reports,
      Icons.badge_outlined,
      'Ventas por empleado',
      reportKind: _ReportKind.employee,
    ),
    const _NavItem(
      _BackofficeSection.reports,
      Icons.point_of_sale_outlined,
      'Cortes de caja',
      reportKind: _ReportKind.cashHistory,
    ),
    const _NavItem(
      _BackofficeSection.reports,
      Icons.request_quote_outlined,
      'Gastos / retiros',
      reportKind: _ReportKind.withdrawals,
    ),
    const _NavItem(
      _BackofficeSection.reports,
      Icons.cancel_outlined,
      'Cancelaciones',
      reportKind: _ReportKind.cancellations,
    ),
    const _NavItem(
      _BackofficeSection.reports,
      Icons.money_off_csred_outlined,
      'Pagos cancelados',
      reportKind: _ReportKind.cancelledPayments,
    ),
    const _NavItem(
      _BackofficeSection.reports,
      Icons.rule_folder_outlined,
      'Auditoria de discrepancias de ventas',
      reportKind: _ReportKind.salesDiscrepancyAudit,
    ),
    if (canKitchen) ...const [
      _NavItem(
        _BackofficeSection.reports,
        Icons.warning_amber_outlined,
        'Mermas por insumo',
        reportKind: _ReportKind.kitchenWaste,
      ),
      _NavItem(
        _BackofficeSection.reports,
        Icons.sync_alt_outlined,
        'Entradas y salidas de insumos',
        reportKind: _ReportKind.kitchenInventory,
      ),
      _NavItem(
        _BackofficeSection.reports,
        Icons.soup_kitchen_outlined,
        'Rendimiento de cocina',
        reportKind: _ReportKind.kitchenYield,
      ),
      _NavItem(
        _BackofficeSection.reports,
        Icons.production_quantity_limits_outlined,
        'Productos agotados',
        reportKind: _ReportKind.productStockOuts,
      ),
    ],
  ];
}

bool _canUseBackoffice(Employee? employee) {
  return employee?.hasAdminAccess == true ||
      employee?.canManageCash == true ||
      employee?.canViewKitchenReports == true ||
      employee?.canAuthorizeCashWithdrawals == true ||
      employee?.canViewLiveOperations == true ||
      (kIsWeb &&
          (employee?.canViewPurchases == true ||
              employee?.canManageSuppliers == true ||
              employee?.canRegisterPurchases == true ||
              employee?.canPaySuppliers == true ||
              employee?.canViewAccountsPayable == true ||
              employee?.canViewPurchaseReports == true));
}

String _sectionTitle(_BackofficeSection section) {
  return switch (section) {
    _BackofficeSection.dashboard => 'Dashboard',
    _BackofficeSection.live => 'Visor operativo',
    _BackofficeSection.sales => 'Ventas',
    _BackofficeSection.reports => 'Reportes',
    _BackofficeSection.authorizations => 'Autorizaciones',
    _BackofficeSection.cash => 'Caja',
    _BackofficeSection.kitchen => 'Control de cocina',
    _BackofficeSection.purchases => 'Compras',
    _BackofficeSection.finance => 'Finanzas',
    _BackofficeSection.settings => 'Configuracion',
  };
}

String _reportTitle(_ReportKind kind) {
  return switch (kind) {
    _ReportKind.products => 'Ventas por articulo',
    _ReportKind.hourly => 'Ventas por hora',
    _ReportKind.hourlyYesterdayLastSales =>
      'Ventas por hora: dia seleccionado vs ultimo dia con ventas',
    _ReportKind.hourlyPreviousWeek => 'Ventas por hora: semana anterior',
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
    _ReportKind.productStockOuts => 'Productos agotados',
    _ReportKind.salesDiscrepancyAudit => 'Auditoria de discrepancias de ventas',
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
    _ReportKind.hourlyYesterdayLastSales => _hourlyCsvHeaders,
    _ReportKind.hourlyPreviousWeek => _hourlyCsvHeaders,
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
    _ReportKind.productStockOuts => [
      'Fecha operativa',
      'Hora agotado',
      'Sucursal',
      'Categoria',
      'Producto',
      'Marco',
      'Estado',
      'Hora liberado',
      'Motivo liberacion',
    ],
    _ReportKind.salesDiscrepancyAudit => _salesAuditHeaders,
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
      final totalSales = summary.products.fold<double>(
        0,
        (total, row) => total + row.value,
      );
      return summary.products.map((row) {
        final percent = totalSales <= 0 ? 0 : (row.value / totalSales) * 100;
        return [
          row.productName,
          row.categoryName,
          '${row.qty} vendidos',
          _money(row.value),
          _money(row.averagePrice),
          '${percent.toStringAsFixed(1)}%',
        ];
      }).toList();
    case _ReportKind.hourly:
      return _salesByHour(payments)
          .map((row) => [row.label, '-', '-', row.displayValue, '-', '-'])
          .toList();
    case _ReportKind.hourlyYesterdayLastSales:
    case _ReportKind.hourlyPreviousWeek:
      return const [];
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
    case _ReportKind.productStockOuts:
      final rows = await repository
          .watchProductStockOutReport(
            startBusinessDate: startBusinessDate,
            endBusinessDate: endBusinessDate,
          )
          .first;
      return rows.map(_stockOutReportRow).toList();
    case _ReportKind.salesDiscrepancyAudit:
      return const [];
  }
}

List<String> _stockOutReportRow(ProductStockOutRow row) {
  return [
    row.businessDate,
    row.soldOutTimeLabel.isEmpty
        ? _timeText(row.soldOutAt)
        : row.soldOutTimeLabel,
    row.branchName,
    row.categoryName,
    row.productName,
    row.soldOutByEmployeeName,
    _stockOutStatusText(row),
    _timeText(row.clearedAt),
    _stockOutClearedReason(row.clearedReason),
  ];
}

const _stockOutCsvHeaders = [
  'businessDate',
  'soldOutTimeLabel',
  'branchName',
  'categoryName',
  'productName',
  'soldOutByEmployeeName',
  'status',
  'clearedAt',
  'clearedReason',
];

List<String> _stockOutCsvRow(ProductStockOutRow row) {
  return [
    row.businessDate,
    row.soldOutTimeLabel.isEmpty
        ? _timeText(row.soldOutAt)
        : row.soldOutTimeLabel,
    row.branchName,
    row.categoryName,
    row.productName,
    row.soldOutByEmployeeName,
    row.status,
    _dateTimeText(row.clearedAt),
    row.clearedReason,
  ];
}

Map<String, String> _stockOutOptions(
  Iterable<MapEntry<String, String>> values,
) {
  final result = <String, String>{};
  for (final entry in values) {
    final key = entry.key.trim();
    final value = entry.value.trim();
    if (key.isNotEmpty) {
      result[key] = value.isEmpty ? key : value;
    }
  }
  return Map.fromEntries(
    result.entries.toList()..sort((a, b) => a.value.compareTo(b.value)),
  );
}

Map<String, String> _stockOutTextOptions(Iterable<String> values) {
  final result = <String>{};
  for (final value in values) {
    final clean = value.trim();
    if (clean.isNotEmpty) result.add(clean);
  }
  final sorted = result.toList()..sort();
  return {for (final value in sorted) value: value};
}

String _stockOutStatusText(ProductStockOutRow row) {
  if (row.isActive) return 'Agotado activo';
  if (row.clearedReason == 'kitchen_closed') {
    return 'Liberado por cierre de cocina';
  }
  if (row.clearedReason == 'manual') return 'Liberado manualmente';
  return 'Liberado';
}

String _stockOutClearedReason(String reason) {
  return switch (reason) {
    'kitchen_closed' => 'Cierre de cocina',
    'manual' => 'Manual',
    '' => '-',
    _ => reason,
  };
}

String _timeText(DateTime? value) {
  if (value == null) return '-';
  return DateFormat('HH:mm').format(value);
}

Future<_ItemsSummary> _itemsSummary(
  TacoPosRepository repository,
  List<PosOrder> orders,
) async {
  final products = <String, _ProductSalesAccumulator>{};
  var totalQty = 0;
  for (final order in orders.where((order) => order.status != 'cancelled')) {
    final items = await repository.getOrderItemsOnce(order.id);
    for (final item in items.where((item) => !item.isCancelled)) {
      final productName = _reportValue(item.productName, fallback: 'Producto');
      final categoryName = _reportValue(item.category);
      final key = item.productId.trim().isNotEmpty
          ? 'id:${item.productId.trim()}'
          : 'legacy:${productName.toLowerCase()}|${categoryName.toLowerCase()}';
      final accumulator = products.putIfAbsent(
        key,
        () => _ProductSalesAccumulator(
          productName: productName,
          categoryName: categoryName,
        ),
      );
      accumulator.add(qty: item.qty, value: item.total);
      totalQty += item.qty;
    }
  }
  final rows = products.values.map((product) => product.toRow()).toList()
    ..sort((a, b) {
      final salesCompare = b.value.compareTo(a.value);
      if (salesCompare != 0) return salesCompare;
      final qtyCompare = b.qty.compareTo(a.qty);
      if (qtyCompare != 0) return qtyCompare;
      return a.productName.compareTo(b.productName);
    });
  return _ItemsSummary(totalQty: totalQty, products: rows);
}

List<_BarRow> _salesByHour(List<Payment> payments) {
  final totals = <int, double>{};
  for (final payment in payments) {
    final hour = payment.createdAt?.hour;
    if (hour == null) continue;
    totals[hour] = (totals[hour] ?? 0) + _dashboardCollectedAmount(payment);
  }
  return totals.entries.map((entry) {
    return _BarRow(
      '${entry.key.toString().padLeft(2, '0')}:00',
      entry.value,
      _money(entry.value),
    );
  }).toList()..sort((a, b) => a.label.compareTo(b.label));
}

const _hourlyCsvHeaders = [
  'Reporte',
  'Fecha seleccionada',
  'Ultimo dia con ventas',
  'Hora',
  'Venta fecha seleccionada',
  'Venta ultimo dia con ventas',
  'Diferencia \$',
  'Diferencia %',
  'Ordenes fecha seleccionada',
  'Ordenes ultimo dia con ventas',
];

enum _HourlyComparisonMode { yesterdayVsLastSales, previousWeek }

class _DateRange {
  const _DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class _HourlyBucket {
  const _HourlyBucket({this.sales = 0, this.orderCount = 0});

  final double sales;
  final int orderCount;
}

class _MutableHourlyBucket {
  double sales = 0;
  final Set<String> orderIds = {};
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

  final _HourlyComparisonMode mode;
  final DateTime aDate;
  final DateTime bDate;
  final String aLabel;
  final String bLabel;
  final List<_HourlyComparisonRow> rows;

  String get title => mode == _HourlyComparisonMode.yesterdayVsLastSales
      ? 'Ventas por hora: dia seleccionado vs ultimo dia con ventas'
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

  List<List<String>> get csvRows {
    return rows
        .map(
          (row) => [
            title,
            _businessDateFor(aDate) ?? '',
            _businessDateFor(bDate) ?? '',
            _hourRange(row.hour),
            row.a.sales.toStringAsFixed(2),
            row.b.sales.toStringAsFixed(2),
            row.diff.toStringAsFixed(2),
            _percentLabel(row.a.sales, row.b.sales),
            '${row.a.orderCount}',
            '${row.b.orderCount}',
          ],
        )
        .toList();
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

class _HourlyComparisonSummary extends StatelessWidget {
  const _HourlyComparisonSummary({required this.report});

  final _HourlyComparisonReport report;

  @override
  Widget build(BuildContext context) {
    final diff = report.totalA - report.totalB;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _SmallMetric(
          '${report.aLabel} ${_dateText(report.aDate)}',
          _money(report.totalA),
        ),
        _SmallMetric(
          '${report.bLabel} ${_dateText(report.bDate)}',
          _money(report.totalB),
        ),
        _SmallMetric(
          'Diferencia total',
          '${_money(diff)} ${_percentLabel(report.totalA, report.totalB)}',
        ),
        _SmallMetric(
          'Mejor hora ${report.aLabel.toLowerCase()}',
          report.bestA == null
              ? 'Sin ventas'
              : '${_hourRange(report.bestA!.hour)} ${_money(report.bestA!.a.sales)}',
        ),
        _SmallMetric(
          report.mode == _HourlyComparisonMode.yesterdayVsLastSales
              ? 'Hora mas baja del dia seleccionado'
              : 'Mejor hora semana anterior',
          report.mode == _HourlyComparisonMode.yesterdayVsLastSales
              ? report.lowestA == null
                    ? 'Sin ventas'
                    : '${_hourRange(report.lowestA!.hour)} ${_money(report.lowestA!.a.sales)}'
              : report.bestB == null
              ? 'Sin ventas'
              : '${_hourRange(report.bestB!.hour)} ${_money(report.bestB!.b.sales)}',
        ),
      ],
    );
  }
}

class _HourlyComparisonChart extends StatelessWidget {
  const _HourlyComparisonChart({required this.report});

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
    final visibleRows = report.rows
        .where((row) => row.a.sales > 0 || row.b.sales > 0)
        .toList();
    if (visibleRows.isEmpty) {
      return const GlassPanel(
        child: Text(
          'Sin ventas por hora para graficar.',
          style: TextStyle(color: BrandColors.textMuted),
        ),
      );
    }
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            children: const [
              _HourlyLegend(color: BrandColors.accentYellow, label: 'Dia A'),
              _HourlyLegend(color: BrandColors.info, label: 'Dia B'),
            ],
          ),
          const SizedBox(height: 12),
          ...visibleRows.map(
            (row) => _HourlyComparisonBar(row: row, maxSales: maxSales),
          ),
        ],
      ),
    );
  }
}

class _HourlyLegend extends StatelessWidget {
  const _HourlyLegend({required this.color, required this.label});

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

class _HourlyComparisonBar extends StatelessWidget {
  const _HourlyComparisonBar({required this.row, required this.maxSales});

  final _HourlyComparisonRow row;
  final double maxSales;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(
              _hourRange(row.hour),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                _HourlyBar(
                  value: maxSales <= 0 ? 0 : row.a.sales / maxSales,
                  color: BrandColors.accentYellow,
                ),
                const SizedBox(height: 3),
                _HourlyBar(
                  value: maxSales <= 0 ? 0 : row.b.sales / maxSales,
                  color: BrandColors.info,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 84,
            child: Text(
              _money(row.diff),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _diffColor(row.diff),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HourlyBar extends StatelessWidget {
  const _HourlyBar({required this.value, required this.color});

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

class _HourlyComparisonTable extends StatelessWidget {
  const _HourlyComparisonTable({required this.report});

  final _HourlyComparisonReport report;

  @override
  Widget build(BuildContext context) {
    return _ReportTable(
      headers: [
        'Hora',
        '${report.aLabel} venta',
        '${report.bLabel} venta',
        'Diferencia \$',
        'Diferencia %',
        'Ordenes ${report.aLabel}',
        'Ordenes ${report.bLabel}',
      ],
      rows: report.rows
          .map(
            (row) => [
              _hourRange(row.hour),
              _money(row.a.sales),
              _money(row.b.sales),
              _money(row.diff),
              _percentLabel(row.a.sales, row.b.sales),
              '${row.a.orderCount}',
              '${row.b.orderCount}',
            ],
          )
          .toList(),
    );
  }
}

_DateRange _hourlyQueryRange(_HourlyComparisonMode mode, DateTime baseDate) {
  final cleanBase = _startOfDay(baseDate);
  if (mode == _HourlyComparisonMode.yesterdayVsLastSales) {
    return _DateRange(
      start: cleanBase.subtract(const Duration(days: 30)),
      end: cleanBase,
    );
  }
  final compare = cleanBase.subtract(const Duration(days: 7));
  return _DateRange(
    start: compare.isBefore(cleanBase) ? compare : cleanBase,
    end: compare.isAfter(cleanBase) ? compare : cleanBase,
  );
}

_HourlyComparisonReport? _buildHourlyComparison({
  required _HourlyComparisonMode mode,
  required List<Payment> payments,
  required List<PosOrder> orders,
  required DateTime baseDate,
}) {
  final orderById = {for (final order in orders) order.id: order};
  final activePayments = payments.where((payment) {
    if (!_isDashboardActivePayment(payment)) return false;
    final order = orderById[payment.orderId];
    if (order == null) return true;
    return !_isCancelledOrder(order);
  }).toList();
  final aDate = _startOfDay(baseDate);
  final bDate = mode == _HourlyComparisonMode.yesterdayVsLastSales
      ? _lastSalesDateBefore(activePayments, aDate)
      : aDate.subtract(const Duration(days: 7));
  if (bDate == null) return null;
  final aBuckets = _hourlyBucketsForDate(activePayments, orderById, aDate);
  final bBuckets = _hourlyBucketsForDate(activePayments, orderById, bDate);
  return _HourlyComparisonReport(
    mode: mode,
    aDate: aDate,
    bDate: bDate,
    aLabel: 'Dia seleccionado',
    bLabel: mode == _HourlyComparisonMode.yesterdayVsLastSales
        ? 'Ultimo dia con ventas'
        : 'Semana anterior',
    rows: List.generate(
      24,
      (hour) => _HourlyComparisonRow(
        hour: hour,
        a: aBuckets[hour] ?? const _HourlyBucket(),
        b: bBuckets[hour] ?? const _HourlyBucket(),
      ),
    ),
  );
}

DateTime? _lastSalesDateBefore(List<Payment> payments, DateTime date) {
  for (var offset = 1; offset <= 30; offset++) {
    final candidate = date.subtract(Duration(days: offset));
    final key = _businessDateFor(candidate);
    final total = payments
        .where((payment) => _paymentBusinessDate(payment) == key)
        .fold<double>(
          0,
          (sum, payment) => sum + _dashboardCollectedAmount(payment),
        );
    if (total > 0.01) return candidate;
  }
  return null;
}

Map<int, _HourlyBucket> _hourlyBucketsForDate(
  List<Payment> payments,
  Map<String, PosOrder> orderById,
  DateTime date,
) {
  final key = _businessDateFor(date);
  final buckets = <int, _MutableHourlyBucket>{};
  for (final payment in payments.where(
    (payment) => _paymentBusinessDate(payment) == key,
  )) {
    final order = orderById[payment.orderId];
    final saleDate = payment.createdAt ?? order?.paidAt ?? order?.createdAt;
    final hour = (saleDate ?? date).hour;
    final bucket = buckets.putIfAbsent(hour, _MutableHourlyBucket.new);
    bucket.sales += _dashboardCollectedAmount(payment);
    if (payment.orderId.trim().isNotEmpty) {
      bucket.orderIds.add(payment.orderId);
    }
  }
  return {
    for (final entry in buckets.entries)
      entry.key: _HourlyBucket(
        sales: entry.value.sales,
        orderCount: entry.value.orderIds.length,
      ),
  };
}

bool _isCancelledOrder(PosOrder order) {
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
  return _businessDateFor(payment.createdAt) ?? '';
}

DateTime _startOfDay(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

String _dateText(DateTime date) {
  return DateFormat('dd/MM/yyyy').format(date);
}

DateTime? _parseBusinessDate(String value) {
  try {
    return _startOfDay(DateFormat('yyyy-MM-dd').parseStrict(value));
  } on FormatException {
    return null;
  }
}

String _hourRange(int hour) {
  final text = hour.toString().padLeft(2, '0');
  return '$text:00 - $text:59';
}

String _percentLabel(double a, double b) {
  if (b.abs() <= 0.01) {
    if (a.abs() <= 0.01) return '0.0%';
    return '+100.0%';
  }
  final percent = ((a - b) / b) * 100;
  final sign = percent > 0 ? '+' : '';
  return '$sign${percent.toStringAsFixed(1)}%';
}

Color _diffColor(double diff) {
  if (diff > 0.01) return BrandColors.success;
  if (diff < -0.01) return BrandColors.danger;
  return BrandColors.textMuted;
}

List<_BarRow> _salesByMethod(List<Payment> payments) {
  final totals = <String, double>{};
  for (final payment in payments) {
    final label = _paymentMethodLabel(payment.method);
    totals[label] = (totals[label] ?? 0) + _dashboardCollectedAmount(payment);
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
    totals[label] = (totals[label] ?? 0) + _dashboardCollectedAmount(payment);
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

const double _dashboardCardCommissionFactor = 0.035 * 1.16;

bool _isDashboardActivePayment(Payment payment) {
  return isActivePayment(payment) && _dashboardCollectedAmount(payment) > 0;
}

double _dashboardCollectedAmount(Payment payment) {
  if (payment.baseAmount > 0) return payment.baseAmount;
  if (payment.chargedAmount > 0) return payment.chargedAmount;
  return 0;
}

double _dashboardCardCommission(double grossCardAmount) {
  return grossCardAmount * _dashboardCardCommissionFactor;
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

String _reportValue(String value, {String fallback = '-'}) {
  final clean = value.trim();
  return clean.isEmpty ? fallback : clean;
}

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
