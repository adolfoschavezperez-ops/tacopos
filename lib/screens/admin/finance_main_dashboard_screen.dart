import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/reports/finance_dashboard.dart';
import '../../core/reports/finance_dashboard_excel.dart';
import '../../core/theme/brand_colors.dart';
import '../../models/branch.dart';
import '../../models/cash_withdrawal_request.dart';
import '../../models/purchase_models.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/binary_exporter.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_panel.dart';

class FinanceMainDashboardScreen extends StatefulWidget {
  const FinanceMainDashboardScreen({super.key});

  @override
  State<FinanceMainDashboardScreen> createState() =>
      _FinanceMainDashboardScreenState();
}

class _FinanceMainDashboardScreenState
    extends State<FinanceMainDashboardScreen> {
  final TacoPosRepository _repository = TacoPosRepository();
  late DateTime _startDate;
  late DateTime _endDate;
  Future<FinanceDashboardBundle>? _future;
  bool _refreshing = false;
  bool _exporting = false;

  String get _startBusinessDate => DateFormat('yyyy-MM-dd').format(_startDate);
  String get _endBusinessDate => DateFormat('yyyy-MM-dd').format(_endDate);
  bool get _hasAccess =>
      kIsWeb && canViewFinanceDashboard(AppSession.instance.employee);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month);
    _endDate = DateTime(now.year, now.month, now.day);
    AppSession.instance.addListener(_onSessionChanged);
    if (_hasAccess) _future = _fetch();
  }

  @override
  void dispose() {
    AppSession.instance.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {
      _future = _hasAccess ? _fetch() : null;
    });
  }

  Future<FinanceDashboardBundle> _fetch({bool forceRefresh = false}) {
    return _repository.getFinanceDashboardBundle(
      startBusinessDate: _startBusinessDate,
      endBusinessDate: _endBusinessDate,
      forceRefresh: forceRefresh,
    );
  }

  void _reload() {
    setState(() => _future = _fetch());
  }

  Future<void> _refresh() async {
    if (_refreshing || !_hasAccess) return;
    setState(() => _refreshing = true);
    _repository.invalidateFinanceDashboardCache(
      branchId: AppSession.instance.currentBranchId,
      startBusinessDate: _startBusinessDate,
      endBusinessDate: _endBusinessDate,
    );
    final future = _fetch(forceRefresh: true);
    setState(() => _future = future);
    try {
      await future;
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      helpText: 'Periodo operativo',
      saveText: 'Aplicar',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startDate = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day);
      _future = _fetch();
    });
  }

  void _setPreset(_DatePreset preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      switch (preset) {
        case _DatePreset.today:
          _startDate = today;
          _endDate = today;
        case _DatePreset.week:
          _startDate = today.subtract(Duration(days: today.weekday - 1));
          _endDate = today;
        case _DatePreset.month:
          _startDate = DateTime(today.year, today.month);
          _endDate = today;
      }
      _future = _fetch();
    });
  }

  void _returnToBackoffice() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _export(FinanceDashboardBundle bundle) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await Future<void>.delayed(Duration.zero);
      final session = AppSession.instance;
      final bytes = buildFinanceDashboardWorkbook(
        bundle: bundle,
        restaurantName: session.currentRestaurantName,
        branchName: session.currentBranchName,
      );
      final branch = _fileToken(session.currentBranchName);
      final message = await exportBinaryFile(
        fileName:
            'Reporte_Financiero_${branch}_${_startBusinessDate}_$_endBusinessDate.xlsx',
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (mounted) showAppSnackBar(context, message);
    } catch (error) {
      if (mounted) {
        showAppSnackBar(
          context,
          'No se pudo exportar: $error',
          type: AppSnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showPeriodSummary(FinanceDashboardBundle bundle) {
    return showDialog<void>(
      context: context,
      builder: (context) => _FinancePeriodSummaryDialog(
        bundle: bundle,
        restaurantName: AppSession.instance.currentRestaurantName,
        branchName: AppSession.instance.currentBranchName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAccess) {
      return const Scaffold(
        backgroundColor: _FinanceColors.background,
        body: SafeArea(
          child: EmptyState(
            icon: Icons.lock_outline,
            title: 'Sin permiso',
            message:
                'No tienes permiso para consultar el dashboard financiero.',
          ),
        ),
      );
    }
    final future = _future ??= _fetch();
    return Scaffold(
      backgroundColor: _FinanceColors.background,
      body: SafeArea(
        child: FutureBuilder<FinanceDashboardBundle>(
          future: future,
          builder: (context, snapshot) {
            return LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: EdgeInsets.all(constraints.maxWidth < 900 ? 12 : 18),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1880),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DashboardHeader(
                            startDate: _startDate,
                            endDate: _endDate,
                            exporting: _exporting,
                            bundle: snapshot.data,
                            onBack: _returnToBackoffice,
                            onPickRange: _pickRange,
                            onPreset: _setPreset,
                            onExport: snapshot.data == null
                                ? null
                                : () => _export(snapshot.data!),
                            onSummary: snapshot.data == null
                                ? null
                                : () => _showPeriodSummary(snapshot.data!),
                          ),
                          const SizedBox(height: 14),
                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              !snapshot.hasData)
                            const SizedBox(
                              height: 420,
                              child: LoadingPanel(
                                message: 'Cargando dashboard financiero...',
                              ),
                            )
                          else if (snapshot.hasError)
                            _LoadError(error: snapshot.error, onRetry: _reload)
                          else if (snapshot.data case final bundle?)
                            FinanceDashboardContent(
                              bundle: bundle,
                              repository: _repository,
                              refreshing: _refreshing,
                              onRefresh: _refresh,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.startDate,
    required this.endDate,
    required this.exporting,
    required this.bundle,
    required this.onBack,
    required this.onPickRange,
    required this.onPreset,
    required this.onExport,
    required this.onSummary,
  });

  final DateTime startDate;
  final DateTime endDate;
  final bool exporting;
  final FinanceDashboardBundle? bundle;
  final VoidCallback onBack;
  final VoidCallback onPickRange;
  final ValueChanged<_DatePreset> onPreset;
  final VoidCallback? onExport;
  final VoidCallback? onSummary;

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 345,
          child: Row(
            children: [
              Tooltip(
                message: 'Regresar al menu principal',
                child: InkWell(
                  onTap: onBack,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(
                      AppConstants.logoAsset,
                      width: 46,
                      height: 46,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'REPORTE FINANCIERO',
                      style: TextStyle(
                        color: _FinanceColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${session.currentRestaurantName.toUpperCase()} · ${session.currentBranchName.toUpperCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _FinanceColors.amber,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 520),
          padding: const EdgeInsets.all(8),
          decoration: _panelDecoration(),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: onPickRange,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: Text(
                  '${DateFormat('dd/MM/yyyy').format(startDate)} - ${DateFormat('dd/MM/yyyy').format(endDate)}',
                ),
              ),
              _PresetButton(
                label: 'Hoy',
                onTap: () => onPreset(_DatePreset.today),
              ),
              _PresetButton(
                label: 'Semana',
                onTap: () => onPreset(_DatePreset.week),
              ),
              _PresetButton(
                label: 'Mes',
                onTap: () => onPreset(_DatePreset.month),
              ),
              if (session.accessibleBranches.length > 1)
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<Branch>(
                    initialValue: session.selectedBranch,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Sucursal',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: session.accessibleBranches
                        .map(
                          (branch) => DropdownMenuItem(
                            value: branch,
                            child: Text(
                              branch.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (branch) {
                      if (branch != null) session.selectBranch(branch);
                    },
                  ),
                ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: onSummary,
          icon: const Icon(Icons.summarize_outlined, size: 18),
          label: const Text('Resumen del periodo'),
        ),
        FilledButton.icon(
          onPressed: exporting ? null : onExport,
          icon: exporting
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
          label: Text(exporting ? 'Generando...' : 'Exportar a Excel'),
        ),
      ],
    );
  }
}

class FinanceDashboardContent extends StatelessWidget {
  const FinanceDashboardContent({
    super.key,
    required this.bundle,
    required this.repository,
    required this.refreshing,
    required this.onRefresh,
  });

  final FinanceDashboardBundle bundle;
  final TacoPosRepository? repository;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 1420;
        final main = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _KpiGrid(bundle: bundle),
            const SizedBox(height: 12),
            _DetailGrid(bundle: bundle, repository: repository),
            const SizedBox(height: 12),
            _TablesGrid(bundle: bundle, repository: repository),
          ],
        );
        final summaries = _SummaryColumn(
          bundle: bundle,
          refreshing: refreshing,
          onRefresh: onRefresh,
        );
        if (sideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: main),
              const SizedBox(width: 12),
              SizedBox(width: 292, child: summaries),
            ],
          );
        }
        return Column(children: [main, const SizedBox(height: 12), summaries]);
      },
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.bundle});

  final FinanceDashboardBundle bundle;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _KpiData(
        'VENTA',
        bundle.netSales,
        'venta neta del periodo',
        Icons.query_stats_outlined,
        _FinanceColors.green,
        () => _showSalesDialog(context, bundle),
      ),
      _KpiData(
        'INGRESO REAL',
        bundle.realCollected,
        'cortes cerrados',
        Icons.paid_outlined,
        _FinanceColors.lightGreen,
        () => _showDailyCashCutDetailDialog(context, bundle),
      ),
      _KpiData(
        'GASTOS',
        bundle.paidExpenses,
        '${bundle.pendingExpenses.length} pendientes',
        Icons.shopping_cart_outlined,
        _FinanceColors.amber,
        () => _showExpensesDialog(context, bundle),
      ),
      _KpiData(
        'FACTURAS PROVEEDOR',
        bundle.supplierInvoicesTotal,
        '${bundle.purchases.length} documentos',
        Icons.storefront_outlined,
        _FinanceColors.blue,
        () => _showSupplierDialog(context, bundle, repository: null),
      ),
      _KpiData(
        'PAGADO',
        bundle.supplierPaidTotal,
        'pagos a proveedores',
        Icons.credit_card_outlined,
        _FinanceColors.violet,
        () => _showSupplierPaymentsDialog(context, bundle),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1050
            ? 5
            : constraints.maxWidth >= 700
            ? 3
            : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 112,
          ),
          itemBuilder: (context, index) => _KpiCard(data: cards[index]),
        );
      },
    );
  }
}

class _KpiData {
  const _KpiData(
    this.title,
    this.value,
    this.caption,
    this.icon,
    this.color,
    this.onTap,
  );

  final String title;
  final double value;
  final String caption;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _KpiCard extends StatefulWidget {
  const _KpiCard({required this.data});

  final _KpiData data;

  @override
  State<_KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<_KpiCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: 'Ver detalle de ${data.title.toLowerCase()}',
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          scale: _hovered ? 1.015 : 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: data.onTap,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: _panelDecoration(
                  borderColor: data.color.withValues(alpha: 0.32),
                ),
                child: Row(
                  children: [
                    Container(width: 3, height: 70, color: data.color),
                    const SizedBox(width: 11),
                    Icon(data.icon, color: data.color, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: data.color,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _money(data.value),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _FinanceColors.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            data.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _FinanceColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.bundle, required this.repository});

  final FinanceDashboardBundle bundle;
  final TacoPosRepository? repository;

  @override
  Widget build(BuildContext context) {
    final salesBreakdown = buildReconciledBreakdown<String>(
      entries: [
        FinanceBreakdownEntry(
          label: 'Venta neta sin descuento',
          amount: bundle.salesWithoutDiscount,
          source: 'without_discount',
        ),
        FinanceBreakdownEntry(
          label: 'Venta neta de documentos con descuento',
          amount: bundle.salesWithDiscount,
          source: 'with_discount',
        ),
      ],
      expectedTotal: bundle.netSales,
      visibleLimit: 2,
      sortDescending: false,
    );
    final collectionsBreakdown = buildReconciledBreakdown<String>(
      entries: [
        FinanceBreakdownEntry(
          label: 'Efectivo',
          amount: bundle.cashCollected,
          source: 'cash',
        ),
        FinanceBreakdownEntry(
          label: 'Tarjeta neta',
          amount: bundle.cardCollected,
          source: 'card',
        ),
        FinanceBreakdownEntry(
          label: 'Otros métodos',
          amount: bundle.platformCollected + bundle.otherCollected,
          source: 'other',
        ),
      ],
      expectedTotal: bundle.realCollected,
      visibleLimit: 3,
      sortDescending: false,
    );
    final expenseEntries = financeExpenseBreakdownEntries(bundle);
    final supplierInvoiceEntries = financeSupplierInvoiceBreakdownEntries(
      bundle,
    );
    final expensesBreakdown =
        buildReconciledBreakdown<FinanceExpenseConceptGroup>(
          entries: expenseEntries,
          expectedTotal: bundle.paidExpenses,
          visibleLimit: expenseEntries.length,
        );
    final supplierInvoicesBreakdown =
        buildReconciledBreakdown<FinanceSupplierRow>(
          entries: supplierInvoiceEntries,
          expectedTotal: bundle.supplierInvoicesTotal,
          visibleLimit: supplierInvoiceEntries.length,
        );
    final supplierPaymentsBreakdown = buildReconciledBreakdown<String>(
      entries: bundle.supplierPaymentsByMethod.entries
          .map(
            (entry) => FinanceBreakdownEntry(
              label: financeSupplierPaymentMethodLabel(entry.key),
              amount: entry.value,
              source: entry.key,
            ),
          )
          .toList(),
      expectedTotal: bundle.supplierPaidTotal,
      visibleLimit: 3,
    );
    final salesValid =
        salesBreakdown.isValid &&
        (bundle.grossSales - bundle.discounts - bundle.netSales).abs() <=
            financeMoneyTolerance;
    logFinanceDashboardReconciliation('sales', salesBreakdown);
    logFinanceDashboardReconciliation('collected', collectionsBreakdown);
    logFinanceDashboardReconciliation('expenses', expensesBreakdown);
    logFinanceDashboardReconciliation(
      'supplierInvoices',
      supplierInvoicesBreakdown,
    );
    logFinanceDashboardReconciliation(
      'supplierPayments',
      supplierPaymentsBreakdown,
    );
    final cards = [
      _DetailCard(
        title: 'DETALLE DE VENTA',
        accent: _FinanceColors.green,
        lines: [
          const _DetailLineData.section('VENTA BRUTA MENOS DESCUENTOS'),
          _DetailLineData.value('Venta bruta', bundle.grossSales),
          _DetailLineData.value('Descuentos aplicados', -bundle.discounts),
          _DetailLineData.total('Total venta neta', bundle.netSales),
          const _DetailLineData.section('COMPOSICION DE VENTA NETA'),
          _DetailLineData.value(
            'Venta neta sin descuento',
            bundle.salesWithoutDiscount,
          ),
          _DetailLineData.value(
            'Venta neta de documentos con descuento',
            bundle.salesWithDiscount,
          ),
          _DetailLineData.total('Total venta neta', bundle.netSales),
          if (!salesValid) const _DetailLineData.warning(),
        ],
        note: 'Selecciona una cifra para ver las ventas relacionadas.',
        onTap: () => _showSalesDialog(context, bundle),
      ),
      _DetailCard(
        title: 'DETALLE DE COBROS (CAJA)',
        accent: _FinanceColors.lightGreen,
        lines: [
          const _DetailLineData.section('INGRESO REAL DE CORTES CERRADOS'),
          ...collectionsBreakdown.visibleEntries.map(
            (entry) => _DetailLineData.value(
              entry.label,
              entry.amount,
              onTap: entry.source == 'other'
                  ? () => _showOtherCustomerPaymentMethods(
                      context,
                      bundle,
                      entry.amount,
                    )
                  : null,
            ),
          ),
          _DetailLineData.total('Total ingreso real', bundle.realCollected),
          const _DetailLineData.section('COMPARACION CONTRA ESPERADO'),
          _DetailLineData.value(
            'Monetario esperado bruto',
            bundle.expectedMonetaryGrossIncome,
          ),
          _DetailLineData.value(
            'Monetario esperado neto',
            bundle.expectedMonetaryIncome,
          ),
          const _DetailLineData.section('AJUSTES DE CAJA'),
          _DetailLineData.value('Comisiones de tarjeta', bundle.cardFees),
          _DetailLineData.value('Faltantes en cortes', bundle.cashShortages),
          _DetailLineData.value('Sobrantes en cortes', bundle.cashOverages),
          if (!collectionsBreakdown.isValid) const _DetailLineData.warning(),
        ],
        note:
            'El fondo inicial no forma parte del ingreso real. Tarjeta se muestra neta de comisiones.',
        onTap: () => _showDailyCashCutDetailDialog(context, bundle),
      ),
      _DetailCard(
        title: 'DETALLE DE GASTOS',
        accent: _FinanceColors.amber,
        lines: [
          ...expensesBreakdown.visibleEntries.map(
            (entry) => _DetailLineData.value(
              entry.label,
              entry.amount,
              onTap: () => _showExpenseGroupDetail(context, entry.source),
            ),
          ),
          _DetailLineData.total('Total gastos', bundle.paidExpenses),
          if (!expensesBreakdown.isValid) const _DetailLineData.warning(),
        ],
        note: 'Solo incluye gastos pagados del periodo.',
        onTap: () => _showExpensesDialog(context, bundle),
      ),
      _DetailCard(
        title: 'DETALLE DE FACTURAS DE PROVEEDOR',
        accent: _FinanceColors.blue,
        lines: [
          ...supplierInvoicesBreakdown.visibleEntries.map(
            (entry) => _DetailLineData.value(
              entry.label,
              entry.amount,
              onTap: repository == null
                  ? null
                  : () => _showSupplierRowDetail(
                      context,
                      entry.source,
                      repository!,
                    ),
            ),
          ),
          _DetailLineData.total(
            'Total facturado',
            bundle.supplierInvoicesTotal,
          ),
          if (!supplierInvoicesBreakdown.isValid)
            const _DetailLineData.warning(),
        ],
        note: 'Selecciona un proveedor para consultar sus documentos.',
        onTap: () =>
            _showSupplierDialog(context, bundle, repository: repository),
      ),
      _DetailCard(
        title: 'DETALLE DE PAGOS A PROVEEDORES',
        accent: _FinanceColors.violet,
        lines: [
          ...supplierPaymentsBreakdown.visibleEntries.map(
            (entry) => _DetailLineData.value(entry.label, entry.amount),
          ),
          if (supplierPaymentsBreakdown.hasOther)
            _DetailLineData.value(
              'Otros métodos',
              supplierPaymentsBreakdown.otherTotal,
              onTap: () => _showOtherSupplierPaymentMethods(
                context,
                bundle,
                supplierPaymentsBreakdown,
              ),
            ),
          _DetailLineData.total('Total pagado', bundle.supplierPaidTotal),
          if (!supplierPaymentsBreakdown.isValid)
            const _DetailLineData.warning(),
        ],
        note: 'Selecciona una cifra para consultar los pagos relacionados.',
        onTap: () => _showSupplierPaymentsDialog(context, bundle),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1350
            ? 5
            : width >= 1050
            ? 3
            : width >= 700
            ? 2
            : 1;
        final cardWidth = (width - (10 * (columns - 1))) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }
}

class _MetricLineData {
  const _MetricLineData(this.label, this.value);

  final String label;
  final double value;
}

enum _DetailLineKind { value, section, total, warning }

class _DetailLineData {
  const _DetailLineData.value(this.label, this.value, {this.onTap})
    : kind = _DetailLineKind.value;

  const _DetailLineData.section(this.label)
    : value = null,
      onTap = null,
      kind = _DetailLineKind.section;

  const _DetailLineData.total(this.label, this.value)
    : onTap = null,
      kind = _DetailLineKind.total;

  const _DetailLineData.warning()
    : label = 'No fue posible conciliar este bloque.',
      value = null,
      onTap = null,
      kind = _DetailLineKind.warning;

  final String label;
  final double? value;
  final VoidCallback? onTap;
  final _DetailLineKind kind;
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.title,
    required this.accent,
    required this.lines,
    required this.note,
    required this.onTap,
  });

  final String title;
  final Color accent;
  final List<_DetailLineData> lines;
  final String note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelTitle(title: title, color: accent),
          const Divider(height: 14, color: _FinanceColors.border),
          if (lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Center(
                child: Text(
                  'Sin movimientos en este periodo.',
                  style: TextStyle(color: _FinanceColors.muted),
                ),
              ),
            )
          else
            ..._separatedDetailLines(lines, accent),
          const Divider(height: 8, color: _FinanceColors.border),
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _FinanceColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new, size: 14, color: accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.line, required this.accent});

  final _DetailLineData line;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (line.kind == _DetailLineKind.section) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          line.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: accent.withValues(alpha: 0.9),
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    if (line.kind == _DetailLineKind.warning) {
      return Text(
        line.label,
        maxLines: 2,
        style: const TextStyle(
          color: _FinanceColors.red,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    final isTotal = line.kind == _DetailLineKind.total;
    final content = Container(
      padding: isTotal
          ? const EdgeInsets.only(top: 6)
          : const EdgeInsets.symmetric(vertical: 1),
      decoration: isTotal
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: _FinanceColors.border)),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              line.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: line.onTap == null ? null : accent,
                fontSize: 11,
                fontWeight: isTotal ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _money(line.value ?? 0),
            style: TextStyle(
              color: isTotal ? accent : _FinanceColors.text,
              fontSize: 11,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
          if (line.onTap != null) ...[
            const SizedBox(width: 3),
            Icon(Icons.chevron_right, color: accent, size: 14),
          ],
        ],
      ),
    );
    if (line.onTap == null) return content;
    return InkWell(
      key: ValueKey('finance-detail-line-${line.label}'),
      onTap: line.onTap,
      child: content,
    );
  }
}

List<Widget> _separatedDetailLines(List<_DetailLineData> lines, Color accent) {
  final widgets = <Widget>[];
  for (var index = 0; index < lines.length; index++) {
    if (index > 0) widgets.add(const SizedBox(height: 4));
    widgets.add(_DetailLine(line: lines[index], accent: accent));
  }
  return widgets;
}

class _SummaryColumn extends StatelessWidget {
  const _SummaryColumn({
    required this.bundle,
    required this.refreshing,
    required this.onRefresh,
  });

  final FinanceDashboardBundle bundle;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelTitle(title: 'RESUMEN', color: _FinanceColors.amber),
          const SizedBox(height: 10),
          _SummaryCard(
            title: '1. RESUMEN GENERAL',
            tooltip:
                'Resultado considerando el total facturado por proveedores, sin importar cuanto se ha pagado.',
            lines: [
              _MetricLineData('Ingreso real', bundle.realCollected),
              _MetricLineData('Gastos', -bundle.paidExpenses),
              _MetricLineData(
                'Facturas proveedor',
                -bundle.supplierInvoicesTotal,
              ),
            ],
            total: bundle.generalResult,
            formula:
                '${_money(bundle.realCollected)} - ${_money(bundle.paidExpenses)} - ${_money(bundle.supplierInvoicesTotal)}',
          ),
          const SizedBox(height: 10),
          _SummaryCard(
            title: '2. RESUMEN DE COBROS',
            tooltip:
                'Flujo de dinero realmente cobrado menos gastos y pagos a proveedores.',
            lines: [
              _MetricLineData('Cobrado real', bundle.realCollected),
              _MetricLineData('Gastos', -bundle.paidExpenses),
              _MetricLineData(
                'Pagado a proveedores',
                -bundle.supplierPaidTotal,
              ),
            ],
            total: bundle.collectionsResult,
            formula:
                '${_money(bundle.realCollected)} - ${_money(bundle.paidExpenses)} - ${_money(bundle.supplierPaidTotal)}',
          ),
          const SizedBox(height: 10),
          _SummaryCard(
            title: '3. RESUMEN FINAL',
            tooltip:
                'Resultado disponible despues de considerar tambien los saldos pendientes con proveedores.',
            lines: [
              _MetricLineData('Cobrado real', bundle.realCollected),
              _MetricLineData('Gastos', -bundle.paidExpenses),
              _MetricLineData(
                'Pagado a proveedores',
                -bundle.supplierPaidTotal,
              ),
              _MetricLineData(
                'Facturas pendientes',
                -bundle.pendingSupplierInvoices,
              ),
            ],
            total: bundle.finalResult,
            accentColor: financeFinalResultColor(bundle.finalResult),
            formula:
                '${_money(bundle.realCollected)} - ${_money(bundle.paidExpenses)} - ${_money(bundle.supplierPaidTotal)} - ${_money(bundle.pendingSupplierInvoices)}',
          ),
          const SizedBox(height: 18),
          Text(
            'Ultima actualizacion: ${DateFormat('dd/MM/yyyy HH:mm').format(bundle.loadedAt)}',
            style: const TextStyle(color: _FinanceColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 5),
          Text(
            bundle.fromCache
                ? 'Cache vigente · ${bundle.loadMilliseconds} ms'
                : 'Carga consultada · ${bundle.loadMilliseconds} ms',
            style: const TextStyle(color: _FinanceColors.muted, fontSize: 10),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: refreshing ? null : onRefresh,
            icon: refreshing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
            label: Text(refreshing ? 'Actualizando...' : 'Actualizar datos'),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.tooltip,
    required this.lines,
    required this.total,
    required this.formula,
    this.accentColor,
  });

  final String title;
  final String tooltip;
  final List<_MetricLineData> lines;
  final double total;
  final String formula;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final totalColor = financeFinalResultColor(total);
    return Tooltip(
      message: tooltip,
      child: Container(
        key: ValueKey('finance-summary-card-$title'),
        padding: const EdgeInsets.all(12),
        decoration: _panelDecoration(
          fill: _FinanceColors.panelHigh,
          borderColor: accentColor,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                color: accentColor ?? _FinanceColors.amber,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        line.label,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    Text(
                      _money(line.value.abs()),
                      style: TextStyle(
                        color: line.value < 0
                            ? _FinanceColors.amber
                            : _FinanceColors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(color: _FinanceColors.border),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total',
                    style: TextStyle(
                      color: _FinanceColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  _money(total),
                  key: ValueKey('finance-summary-total-$title'),
                  style: TextStyle(
                    color: totalColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              formula,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _FinanceColors.muted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _TablesGrid extends StatelessWidget {
  const _TablesGrid({required this.bundle, required this.repository});

  final FinanceDashboardBundle bundle;
  final TacoPosRepository? repository;

  @override
  Widget build(BuildContext context) {
    final panels = <Widget>[
      _salesTable(context),
      _collectionsTable(context),
      _expensesTable(context),
      _supplierInvoicesTable(context),
      _supplierPaymentsTable(context),
      _supplierAccumulatedTable(context),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: panels.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 330,
          ),
          itemBuilder: (context, index) => panels[index],
        );
      },
    );
  }

  Widget _salesTable(BuildContext context) {
    final rows = bundle.salesByDay
        .map(
          (row) => _TableRowData(
            sortValues: [
              row.businessDate,
              row.grossSales,
              row.salesWithoutDiscount,
              row.salesWithDiscount,
              row.discounts,
              row.netSales,
              row.documents,
            ],
            cells: [
              Text(_displayDate(row.businessDate)),
              Text(_money(row.grossSales)),
              Text(_money(row.salesWithoutDiscount)),
              Text(_money(row.salesWithDiscount)),
              Text(_money(row.discounts)),
              Text(_money(row.netSales)),
              Text('${row.documents}'),
            ],
            onTap: () => _showSalesDialog(
              context,
              bundle,
              businessDate: row.businessDate,
            ),
          ),
        )
        .toList();
    rows.add(
      _TableRowData(
        isTotal: true,
        sortValues: const ['', 0, 0, 0, 0, 0, 0],
        cells: [
          _totalText('TOTAL'),
          _totalText(_money(bundle.grossSales)),
          _totalText(_money(bundle.salesWithoutDiscount)),
          _totalText(_money(bundle.salesWithDiscount)),
          _totalText(_money(bundle.discounts)),
          _totalText(_money(bundle.netSales)),
          _totalText('${bundle.salesOrders.length}'),
        ],
      ),
    );
    return _FinanceTable(
      title: 'DETALLE DE VENTAS',
      accent: _FinanceColors.green,
      columns: const [
        'Fecha operativa',
        'Venta bruta',
        'Sin descuento',
        'Con descuento',
        'Descuento',
        'Venta neta',
        'Documentos',
      ],
      rows: rows,
      emptyMessage: 'No hay ventas en este periodo.',
    );
  }

  Widget _collectionsTable(BuildContext context) {
    final dailyDetails = bundle.cashCutDailyDetails;
    final total = bundle.cashCutPeriodTotal;
    final rows = dailyDetails
        .map(
          (row) => _TableRowData(
            sortValues: [
              row.businessDate,
              row.cashCounted,
              row.cashExpensesPaid,
              row.cashOperationalBeforeExpenses,
              row.cardGrossReceived,
              row.cardFees,
              row.cardReceived,
              row.otherReceived,
              row.shortage,
              row.overage,
              row.actualIncome,
            ],
            cells: [
              Text(_displayDate(row.businessDate)),
              Text(_money(row.cashCounted)),
              Text(_money(row.cashExpensesPaid)),
              Text(_money(row.cashOperationalBeforeExpenses)),
              Text(_money(row.cardGrossReceived)),
              Text(_money(row.cardFees)),
              Text(_money(row.cardReceived)),
              Text(_money(row.otherReceived)),
              Text(_money(row.shortage)),
              Text(_money(row.overage)),
              Text(_money(row.actualIncome)),
            ],
            onTap: () => _showDailyCashCutDetailDialog(
              context,
              bundle,
              businessDate: row.businessDate,
            ),
          ),
        )
        .toList();
    rows.add(
      _TableRowData(
        isTotal: true,
        sortValues: const ['', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        cells: [
          _totalText('TOTAL'),
          _totalText(_money(total.cashCounted)),
          _totalText(_money(total.cashExpensesPaid)),
          _totalText(_money(total.cashOperationalBeforeExpenses)),
          _totalText(_money(total.cardGrossReceived)),
          _totalText(_money(total.cardFees)),
          _totalText(_money(total.cardReceived)),
          _totalText(_money(total.otherReceived)),
          _totalText(_money(total.shortage)),
          _totalText(_money(total.overage)),
          _totalText(_money(total.actualIncome)),
        ],
      ),
    );
    return _FinanceTable(
      title: 'DETALLE DE INGRESOS REALES (CORTES)',
      accent: _FinanceColors.lightGreen,
      columns: const [
        'Fecha operativa',
        'Efectivo contado',
        'Gastos caja',
        'Efectivo antes gastos',
        'Tarjeta bruta',
        'Comision',
        'Tarjeta neta',
        'Plataforma / otros',
        'Faltante',
        'Sobrante',
        'Ingreso real',
      ],
      rows: rows,
      emptyMessage: 'No hay cortes cerrados en este periodo.',
    );
  }

  Widget _expensesTable(BuildContext context) {
    final rows = bundle.expenses.map((row) {
      final status = financeExpenseStatus(row);
      return _TableRowData(
        sortValues: [
          row.businessDate,
          row.reason,
          row.amount,
          status.index,
          row.requestedByEmployeeName,
          '',
        ],
        cells: [
          Text(_displayDate(row.businessDate)),
          Text(row.reason),
          Text(_money(row.amount)),
          _StatusChip(
            label: financeExpenseStatusLabel(status),
            status: status == FinanceExpenseStatus.paid
                ? _StatusKind.success
                : status == FinanceExpenseStatus.pending
                ? _StatusKind.pending
                : _StatusKind.cancelled,
          ),
          Text(row.requestedByEmployeeName),
          const Icon(Icons.visibility_outlined, size: 17),
        ],
        onTap: () => _showExpenseDetail(context, row),
      );
    }).toList();
    rows.add(
      _TableRowData(
        isTotal: true,
        sortValues: const ['', '', 0, 0, '', ''],
        cells: [
          _totalText('TOTAL PAGADO'),
          _totalText(''),
          _totalText(_money(bundle.paidExpenses)),
          _totalText(''),
          _totalText(''),
          _totalText(''),
        ],
      ),
    );
    return _FinanceTable(
      title: 'DETALLE DE GASTOS',
      accent: _FinanceColors.amber,
      columns: const [
        'Fecha operativa',
        'Concepto',
        'Monto',
        'Estatus',
        'Registro',
        'Detalle',
      ],
      rows: rows,
      emptyMessage: 'No hay gastos en este periodo.',
    );
  }

  Widget _supplierInvoicesTable(BuildContext context) {
    final rows = bundle.supplierRows
        .map(
          (row) => _TableRowData(
            sortValues: [
              row.supplierName,
              row.purchases
                  .map((purchase) => purchase.notes)
                  .where((note) => note.trim().isNotEmpty)
                  .join(', '),
              row.documents,
              row.invoiced,
              row.paidOnInvoices,
              row.balance,
              financeSupplierRowStatus(row),
            ],
            cells: [
              Text(row.supplierName),
              Text(
                row.purchases
                    .map((purchase) => purchase.notes)
                    .where((note) => note.trim().isNotEmpty)
                    .join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text('${row.documents}'),
              Text(_money(row.invoiced)),
              Text(_money(row.paidOnInvoices)),
              Text(_money(row.balance)),
              _StatusChip(
                label: financeSupplierRowStatus(row),
                status: financeSupplierRowStatus(row) == 'Vencida'
                    ? _StatusKind.cancelled
                    : row.balance <= financeMoneyTolerance
                    ? _StatusKind.success
                    : row.paidOnInvoices > financeMoneyTolerance
                    ? _StatusKind.pending
                    : _StatusKind.neutral,
              ),
            ],
            onTap: () => repository == null
                ? _showSupplierDialog(context, bundle, repository: null)
                : _showSupplierRowDetail(context, row, repository!),
          ),
        )
        .toList();
    rows.add(
      _TableRowData(
        isTotal: true,
        sortValues: const ['', '', 0, 0, 0, 0, ''],
        cells: [
          _totalText('TOTAL'),
          _totalText(''),
          _totalText('${bundle.purchases.length}'),
          _totalText(_money(bundle.supplierInvoicesTotal)),
          _totalText(''),
          _totalText(_money(bundle.pendingSupplierInvoices)),
          _totalText(''),
        ],
      ),
    );
    return _FinanceTable(
      title: 'DETALLE DE FACTURAS POR PROVEEDOR',
      accent: _FinanceColors.blue,
      columns: const [
        'Proveedor',
        'Concepto / nota',
        'Documentos',
        'Facturado',
        'Pagado',
        'Pendiente',
        'Estatus',
      ],
      rows: rows,
      emptyMessage: 'No hay facturas de proveedor.',
    );
  }

  Widget _supplierPaymentsTable(BuildContext context) {
    final rows = bundle.supplierPayments
        .map(
          (row) => _TableRowData(
            sortValues: [
              financeSupplierPaymentBusinessDate(row),
              row.supplierName,
              row.method,
              row.purchaseFolio,
              row.amount,
              row.createdByEmployeeName,
              row.status,
            ],
            cells: [
              Text(_displayDate(financeSupplierPaymentBusinessDate(row))),
              Text(row.supplierName),
              Text(financeSupplierPaymentMethodLabel(row.method)),
              Text(row.purchaseFolio),
              Text(_money(row.amount)),
              Text(row.createdByEmployeeName),
              _StatusChip(label: 'Activo', status: _StatusKind.success),
            ],
            onTap: () => _showSupplierPaymentDetail(context, row),
          ),
        )
        .toList();
    rows.add(
      _TableRowData(
        isTotal: true,
        sortValues: const ['', '', '', '', 0, '', ''],
        cells: [
          _totalText('TOTAL'),
          _totalText(''),
          _totalText(''),
          _totalText(''),
          _totalText(_money(bundle.supplierPaidTotal)),
          _totalText(''),
          _totalText(''),
        ],
      ),
    );
    return _FinanceTable(
      title: 'DETALLE DE PAGOS A PROVEEDORES',
      accent: _FinanceColors.violet,
      columns: const [
        'Fecha',
        'Proveedor',
        'Forma de pago',
        'Documento',
        'Monto',
        'Registro',
        'Estatus',
      ],
      rows: rows,
      emptyMessage: 'No hay pagos a proveedores.',
    );
  }

  Widget _supplierAccumulatedTable(BuildContext context) {
    final suppliers = [...bundle.supplierRows]
      ..sort((a, b) => b.paidInPeriod.compareTo(a.paidInPeriod));
    final rows = suppliers
        .map(
          (row) => _TableRowData(
            sortValues: [
              row.supplierName,
              row.invoiced,
              row.paidInPeriod,
              row.balance,
            ],
            cells: [
              Text(row.supplierName),
              Text(_money(row.invoiced)),
              Text(_money(row.paidInPeriod)),
              Text(_money(row.balance)),
            ],
            onTap: () => repository == null
                ? _showSupplierDialog(context, bundle, repository: null)
                : _showSupplierRowDetail(context, row, repository!),
          ),
        )
        .toList();
    rows.add(
      _TableRowData(
        isTotal: true,
        sortValues: const ['', 0, 0, 0],
        cells: [
          _totalText('TOTAL'),
          _totalText(_money(bundle.supplierInvoicesTotal)),
          _totalText(_money(bundle.supplierPaidTotal)),
          _totalText(_money(bundle.pendingSupplierInvoices)),
        ],
      ),
    );
    return _FinanceTable(
      title: 'DETALLE DE PAGOS POR PROVEEDOR (ACUMULADO)',
      accent: _FinanceColors.violet,
      columns: const [
        'Proveedor',
        'Total facturado',
        'Total pagado',
        'Saldo pendiente',
      ],
      rows: rows,
      emptyMessage: 'No hay movimientos de proveedores.',
    );
  }
}

class _FinanceTable extends StatefulWidget {
  const _FinanceTable({
    required this.title,
    required this.accent,
    required this.columns,
    required this.rows,
    required this.emptyMessage,
  });

  final String title;
  final Color accent;
  final List<String> columns;
  final List<_TableRowData> rows;
  final String emptyMessage;

  @override
  State<_FinanceTable> createState() => _FinanceTableState();
}

class _FinanceTableState extends State<_FinanceTable> {
  final ScrollController _horizontalController = ScrollController();
  int _sortColumn = 0;
  bool _ascending = false;

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = [...widget.rows];
    final hasData = rows.any((row) => !row.isTotal);
    rows.sort((a, b) {
      if (a.isTotal != b.isTotal) return a.isTotal ? 1 : -1;
      final result = _compare(
        a.sortValues[_sortColumn],
        b.sortValues[_sortColumn],
      );
      return _ascending ? result : -result;
    });
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelTitle(title: widget.title, color: widget.accent),
          const SizedBox(height: 8),
          Expanded(
            child: !hasData
                ? Center(
                    child: Text(
                      widget.emptyMessage,
                      style: const TextStyle(color: _FinanceColors.muted),
                    ),
                  )
                : Scrollbar(
                    controller: _horizontalController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _horizontalController,
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          sortColumnIndex: _sortColumn,
                          sortAscending: _ascending,
                          headingRowHeight: 38,
                          dataRowMinHeight: 38,
                          dataRowMaxHeight: 44,
                          columnSpacing: 22,
                          headingTextStyle: const TextStyle(
                            color: _FinanceColors.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                          dataTextStyle: const TextStyle(
                            color: _FinanceColors.text,
                            fontSize: 11,
                          ),
                          columns: [
                            for (
                              var index = 0;
                              index < widget.columns.length;
                              index++
                            )
                              DataColumn(
                                label: Text(widget.columns[index]),
                                onSort: (_, ascending) {
                                  setState(() {
                                    _sortColumn = index;
                                    _ascending = ascending;
                                  });
                                },
                              ),
                          ],
                          rows: rows
                              .map(
                                (row) => DataRow(
                                  color: row.isTotal
                                      ? WidgetStatePropertyAll(
                                          widget.accent.withValues(alpha: 0.08),
                                        )
                                      : null,
                                  onSelectChanged: row.onTap == null
                                      ? null
                                      : (_) => row.onTap!(),
                                  cells: row.cells
                                      .map((cell) => DataCell(cell))
                                      .toList(),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TableRowData {
  const _TableRowData({
    required this.sortValues,
    required this.cells,
    this.onTap,
    this.isTotal = false,
  });

  final List<Object?> sortValues;
  final List<Widget> cells;
  final VoidCallback? onTap;
  final bool isTotal;
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(onPressed: onTap, child: Text(label));
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.status});

  final String label;
  final _StatusKind status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      _StatusKind.success => _FinanceColors.green,
      _StatusKind.pending => _FinanceColors.amber,
      _StatusKind.cancelled => _FinanceColors.red,
      _StatusKind.neutral => _FinanceColors.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 420,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: BrandColors.danger, size: 42),
          const SizedBox(height: 12),
          const Text(
            'No se pudieron cargar los datos.',
            style: TextStyle(
              color: _FinanceColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _FinanceColors.muted),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

Future<void> _showSalesDialog(
  BuildContext context,
  FinanceDashboardBundle bundle, {
  String? businessDate,
}) {
  final rows = bundle.salesOrders
      .where((row) => businessDate == null || row.businessDate == businessDate)
      .map(
        (row) => _DialogRow(
          '${_displayDate(row.businessDate)} · Orden ${row.order.id}',
          'Bruta ${_money(row.grossSales)} · Descuento ${_money(row.discountTotal)} · Neta ${_money(row.netSales)}',
        ),
      )
      .toList();
  return _showRowsDialog(context, 'Detalle de ventas', rows);
}

Future<void> _showPaymentsDialog(
  BuildContext context,
  FinanceDashboardBundle bundle, {
  String? businessDate,
}) {
  final rows = bundle.customerPayments
      .where((row) => businessDate == null || row.businessDate == businessDate)
      .map(
        (row) => _DialogRow(
          '${_displayDate(row.businessDate)} · ${financePaymentMethodLabel(row.payment.method)}',
          'Orden ${row.order.id} · ${_money(row.amount)} · ${row.payment.employeeName ?? row.payment.createdBy ?? 'Sin registro'}',
        ),
      )
      .toList();
  return _showRowsDialog(context, 'Detalle de cobros', rows);
}

Future<void> _showDailyCashCutDetailDialog(
  BuildContext context,
  FinanceDashboardBundle bundle, {
  String? businessDate,
}) {
  final days = bundle.cashCutDailyDetails
      .where((row) => businessDate == null || row.businessDate == businessDate)
      .toList(growable: false);
  final total = buildFinanceCashCutPeriodTotal(days);
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.paid_outlined,
                    color: _FinanceColors.lightGreen,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      businessDate == null
                          ? 'Ingreso real por dia'
                          : 'Ingreso real del dia',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                businessDate == null
                    ? 'Periodo ${_displayDate(bundle.key.startBusinessDate)} al ${_displayDate(bundle.key.endBusinessDate)}'
                    : _displayDate(businessDate),
                style: const TextStyle(
                  color: _FinanceColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: days.isEmpty
                    ? const Center(
                        child: Text(
                          'No hay cortes cerrados en el periodo seleccionado.',
                        ),
                      )
                    : ListView.separated(
                        itemCount: days.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _DailyCashCutCard(day: days[index], bundle: bundle),
                      ),
              ),
              if (days.isNotEmpty) ...[
                const SizedBox(height: 10),
                _DailyCashCutTotal(total: total, dashboardTotal: bundle),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _showOtherCustomerPaymentMethods(
  BuildContext context,
  FinanceDashboardBundle bundle,
  double subtotal,
) {
  final rows = bundle.customerPayments
      .where(
        (row) => !const {
          'cash',
          'card',
          'employee_consumption',
        }.contains(row.payment.method.trim().toLowerCase()),
      )
      .map(
        (row) => _DialogRow(
          '${_displayDate(row.businessDate)} · ${financePaymentMethodLabel(row.payment.method)}',
          'Orden ${row.order.id} · ${_money(row.amount)}',
        ),
      )
      .toList();
  return _showReconciledRowsDialog(
    context,
    title: 'Otros métodos de cobro',
    bundle: bundle,
    rows: rows,
    subtotal: subtotal,
  );
}

Future<void> _showExpensesDialog(
  BuildContext context,
  FinanceDashboardBundle bundle,
) {
  return _showRowsDialog(
    context,
    'Detalle de gastos',
    bundle.approvedExpenses
        .map(
          (row) => _DialogRow(
            '${_displayDate(row.businessDate)} · ${row.reason}',
            '${_money(row.amount)} · ${financeExpenseStatusLabel(financeExpenseStatus(row))} · ${row.requestedByEmployeeName}',
          ),
        )
        .toList(),
  );
}

Future<void> _showExpenseDetail(
  BuildContext context,
  CashWithdrawalRequest row,
) {
  return _showRowsDialog(context, 'Detalle del gasto', [
    _DialogRow('Concepto', row.reason),
    _DialogRow('Fecha operativa', _displayDate(row.businessDate)),
    _DialogRow('Monto', _money(row.amount)),
    _DialogRow('Estatus', financeExpenseStatusLabel(financeExpenseStatus(row))),
    _DialogRow('Registro', row.requestedByEmployeeName),
  ]);
}

Future<void> _showExpenseGroupDetail(
  BuildContext context,
  FinanceExpenseConceptGroup group,
) {
  return _showRowsDialog(
    context,
    'Detalle de ${group.label}',
    group.movements
        .map(
          (row) => _DialogRow(
            '${_displayDate(row.businessDate)} · ${row.reason}',
            '${_money(row.amount)} · ${financeExpenseStatusLabel(financeExpenseStatus(row))} · ${row.requestedByEmployeeName}',
            onTap: () => _showExpenseDetail(context, row),
          ),
        )
        .toList(),
    subtotal: group.amount,
  );
}

Future<void> _showSupplierDialog(
  BuildContext context,
  FinanceDashboardBundle bundle, {
  required TacoPosRepository? repository,
}) {
  return _showRowsDialog(
    context,
    'Facturas por proveedor',
    bundle.supplierRows
        .map(
          (row) => _DialogRow(
            row.supplierName,
            '${row.documents} documentos · Facturado ${_money(row.invoiced)} · Pendiente ${_money(row.balance)}',
            onTap: repository == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    _showSupplierRowDetail(context, row, repository);
                  },
          ),
        )
        .toList(),
  );
}

Future<void> _showSupplierRowDetail(
  BuildContext context,
  FinanceSupplierRow row,
  TacoPosRepository repository,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: FutureBuilder<List<List<SupplierPurchaseItem>>>(
            future: Future.wait(
              row.purchases.map(
                (purchase) =>
                    repository.getSupplierPurchaseItemsOnce(purchase.id),
              ),
            ),
            builder: (context, snapshot) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.supplierName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.separated(
                      itemCount: row.purchases.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final purchase = row.purchases[index];
                        final items =
                            snapshot.data != null &&
                                snapshot.data!.length > index
                            ? snapshot.data![index]
                            : const <SupplierPurchaseItem>[];
                        final itemNames = items
                            .map((item) => item.purchaseItemName)
                            .join(', ');
                        return ListTile(
                          title: Text(
                            '${_displayDate(financePurchaseBusinessDate(purchase))} · ${purchase.folio.isEmpty ? purchase.documentType : purchase.folio}',
                          ),
                          subtitle: Text(
                            '${purchase.notes.isEmpty ? 'Sin nota' : purchase.notes}\n'
                            '${itemNames.isEmpty ? (snapshot.connectionState == ConnectionState.waiting ? 'Cargando articulos...' : 'Sin articulos') : itemNames}\n'
                            'Pagado ${_money(purchase.paidTotal)} · Pendiente ${_money(financePurchaseBalance(purchase))}'
                            '${purchase.dueDate == null ? '' : ' · Vence ${DateFormat('dd/MM/yyyy').format(purchase.dueDate!)}'}',
                          ),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _money(purchase.total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                financePurchaseStatus(purchase),
                                style: const TextStyle(
                                  color: _FinanceColors.muted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

Future<void> _showSupplierPaymentsDialog(
  BuildContext context,
  FinanceDashboardBundle bundle,
) {
  return _showRowsDialog(
    context,
    'Pagos a proveedores',
    bundle.supplierPayments
        .map(
          (row) => _DialogRow(
            '${_displayDate(financeSupplierPaymentBusinessDate(row))} · ${row.supplierName}',
            '${financeSupplierPaymentMethodLabel(row.method)} · ${_money(row.amount)} · ${row.purchaseFolio}',
          ),
        )
        .toList(),
  );
}

Future<void> _showOtherSupplierPaymentMethods(
  BuildContext context,
  FinanceDashboardBundle bundle,
  FinanceReconciledBreakdown<String> breakdown,
) {
  final hiddenMethods = breakdown.hiddenEntries
      .map((entry) => entry.source)
      .toSet();
  return _showReconciledRowsDialog(
    context,
    title: 'Otros métodos de pago',
    bundle: bundle,
    rows: bundle.supplierPayments
        .where((row) => hiddenMethods.contains(row.method.trim().toLowerCase()))
        .map(
          (row) => _DialogRow(
            '${_displayDate(financeSupplierPaymentBusinessDate(row))} · ${row.supplierName}',
            '${financeSupplierPaymentMethodLabel(row.method)} · ${_money(row.amount)} · ${row.purchaseFolio}',
          ),
        )
        .toList(),
    subtotal: breakdown.otherTotal,
  );
}

Future<void> _showSupplierPaymentDetail(
  BuildContext context,
  SupplierPayment row,
) {
  return _showRowsDialog(context, 'Detalle del pago a proveedor', [
    _DialogRow('Fecha', _displayDate(financeSupplierPaymentBusinessDate(row))),
    _DialogRow('Proveedor', row.supplierName),
    _DialogRow('Forma de pago', financeSupplierPaymentMethodLabel(row.method)),
    _DialogRow('Documento relacionado', row.purchaseFolio),
    _DialogRow('Importe', _money(row.amount)),
    _DialogRow('Comentario', row.notes.isEmpty ? 'Sin comentario' : row.notes),
    _DialogRow('Registro', row.createdByEmployeeName),
    _DialogRow('Estatus', row.status),
  ]);
}

Future<void> _showReconciledRowsDialog(
  BuildContext context, {
  required String title,
  required FinanceDashboardBundle bundle,
  required List<_DialogRow> rows,
  required double subtotal,
}) {
  final branchName = AppSession.instance.currentBranchName.trim();
  return _showRowsDialog(
    context,
    title,
    rows,
    contextLabel:
        'Periodo ${_displayDate(bundle.key.startBusinessDate)} al ${_displayDate(bundle.key.endBusinessDate)} · '
        'Sucursal ${branchName.isEmpty ? bundle.key.branchId : branchName}',
    subtotal: subtotal,
  );
}

Future<void> _showRowsDialog(
  BuildContext context,
  String title,
  List<_DialogRow> rows, {
  String? contextLabel,
  double? subtotal,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              if (contextLabel != null) ...[
                Text(
                  contextLabel,
                  style: const TextStyle(
                    color: _FinanceColors.muted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Expanded(
                child: rows.isEmpty
                    ? const Center(
                        child: Text('No hay registros en este periodo.'),
                      )
                    : ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return ListTile(
                            title: Text(row.title),
                            subtitle: Text(row.subtitle),
                            trailing: row.onTap == null
                                ? null
                                : const Icon(Icons.chevron_right),
                            onTap: row.onTap,
                          );
                        },
                      ),
              ),
              if (subtotal != null) ...[
                const Divider(),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Subtotal',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      _money(subtotal),
                      style: const TextStyle(
                        color: _FinanceColors.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _FinancePeriodSummaryDialog extends StatefulWidget {
  const _FinancePeriodSummaryDialog({
    required this.bundle,
    required this.restaurantName,
    required this.branchName,
  });

  final FinanceDashboardBundle bundle;
  final String restaurantName;
  final String branchName;

  @override
  State<_FinancePeriodSummaryDialog> createState() =>
      _FinancePeriodSummaryDialogState();
}

class _FinancePeriodSummaryDialogState
    extends State<_FinancePeriodSummaryDialog> {
  final _summaryKey = GlobalKey();
  late final DateTime _generatedAt;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _generatedAt = DateTime.now();
  }

  Future<void> _copySummary() async {
    final text = financeWhatsappSummaryText(
      bundle: widget.bundle,
      restaurantName: widget.restaurantName,
      branchName: widget.branchName,
      generatedAt: _generatedAt,
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showAppSnackBar(context, 'Resumen copiado.');
  }

  Future<void> _downloadImage() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _summaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('No se pudo preparar el resumen para imagen.');
      }
      final image = await boundary.toImage(pixelRatio: 2.6);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('No se pudo generar el PNG.');
      }
      final bytes = data.buffer.asUint8List();
      await exportBinaryFile(
        fileName: financeSummaryImageFileName(
          bundle: widget.bundle,
          branchName: widget.branchName,
        ),
        bytes: bytes,
        mimeType: 'image/png',
      );
      if (mounted) showAppSnackBar(context, 'Imagen descargada.');
    } catch (error) {
      if (mounted) {
        showAppSnackBar(
          context,
          'No se pudo descargar la imagen: $error',
          type: AppSnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _FinanceColors.background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 900),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Center(
                  child: RepaintBoundary(
                    key: _summaryKey,
                    child: _FinanceShareSummary(
                      bundle: widget.bundle,
                      restaurantName: widget.restaurantName,
                      branchName: widget.branchName,
                      generatedAt: _generatedAt,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: _FinanceColors.border),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _copySummary,
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Copiar resumen'),
                  ),
                  FilledButton.icon(
                    onPressed: _downloading ? null : _downloadImage,
                    icon: _downloading
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.image_outlined, size: 18),
                    label: Text(
                      _downloading ? 'Generando...' : 'Descargar imagen',
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinanceShareSummary extends StatelessWidget {
  const _FinanceShareSummary({
    required this.bundle,
    required this.restaurantName,
    required this.branchName,
    required this.generatedAt,
  });

  final FinanceDashboardBundle bundle;
  final String restaurantName;
  final String branchName;
  final DateTime generatedAt;

  @override
  Widget build(BuildContext context) {
    final title = financePeriodSummaryTitle(bundle.key).toUpperCase();
    final period =
        '${_displayDate(bundle.key.startBusinessDate)} - ${_displayDate(bundle.key.endBusinessDate)}';
    final otherIncome = bundle.platformCollected + bundle.otherCollected;
    final ticketAverage = bundle.salesOrders.isEmpty
        ? 0.0
        : bundle.netSales / bundle.salesOrders.length;
    return Container(
      width: 520,
      color: _FinanceColors.background,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Image.asset(AppConstants.logoAsset, width: 54, height: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurantName.toUpperCase(),
                      style: const TextStyle(
                        color: _FinanceColors.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      branchName.toUpperCase(),
                      style: const TextStyle(
                        color: _FinanceColors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: _FinanceColors.text,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$period\nGenerado: ${DateFormat('dd/MM/yyyy HH:mm').format(generatedAt)}',
            style: const TextStyle(
              color: _FinanceColors.muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          _ShareSection(
            title: 'VENTAS',
            rows: [
              _ShareRow('Venta bruta', bundle.grossSales),
              _ShareRow('Descuentos', -bundle.discounts),
              _ShareRow('Venta neta', bundle.netSales, strong: true),
              _ShareRow.count('Ordenes', bundle.salesOrders.length),
              _ShareRow('Ticket promedio', ticketAverage),
            ],
          ),
          _ShareSection(
            title: 'INGRESOS REALES',
            rows: [
              _ShareRow('Efectivo', bundle.cashCollected),
              _ShareRow('Tarjeta neta', bundle.cardCollected),
              if (otherIncome.abs() > 0.005)
                _ShareRow('Otros / plataforma', otherIncome),
              _ShareRow(
                'Total ingreso real',
                bundle.realCollected,
                strong: true,
              ),
              _ShareRow('Tarjeta bruta', bundle.cardGrossCollected),
              _ShareRow('Comisiones de tarjeta', bundle.cardFees),
            ],
          ),
          _ShareSection(
            title: 'AJUSTES DE CAJA',
            rows: [
              _ShareRow(
                'Monetario esperado bruto',
                bundle.expectedMonetaryGrossIncome,
              ),
              _ShareRow('Comision tarjeta', bundle.cardFees),
              _ShareRow(
                'Monetario esperado neto',
                bundle.expectedMonetaryIncome,
              ),
              _ShareRow('Faltantes', bundle.cashShortages),
              _ShareRow('Sobrantes', bundle.cashOverages),
            ],
          ),
          _ShareSection(
            title: 'GASTOS',
            rows: [
              for (final entry in financeExpenseBreakdownEntries(bundle))
                _ShareRow(entry.label, entry.amount),
              _ShareRow('TOTAL GASTOS', bundle.paidExpenses, strong: true),
            ],
          ),
          _ShareSection(
            title: 'FACTURAS DE PROVEEDORES',
            rows: [
              for (final entry in financeSupplierInvoiceBreakdownEntries(
                bundle,
              ))
                _ShareRow(entry.label, entry.amount),
              _ShareRow(
                'TOTAL FACTURADO',
                bundle.supplierInvoicesTotal,
                strong: true,
              ),
            ],
          ),
          _ShareSection(
            title: 'PAGOS A PROVEEDORES',
            rows: [
              for (final entry in _supplierPaymentRows(bundle))
                _ShareRow(entry.key, entry.value),
              _ShareRow('Total pagado', bundle.supplierPaidTotal, strong: true),
            ],
          ),
          _ShareSection(
            title: 'FACTURAS PENDIENTES',
            rows: [_ShareRow('Pendiente', bundle.pendingSupplierInvoices)],
          ),
          _ShareFinalSection(bundle: bundle),
        ],
      ),
    );
  }
}

class _ShareFinalSection extends StatelessWidget {
  const _ShareFinalSection({required this.bundle});

  final FinanceDashboardBundle bundle;

  @override
  Widget build(BuildContext context) {
    final accentColor = financeFinalResultColor(bundle.finalResult);
    return Container(
      key: const ValueKey('finance-share-final-section'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _FinanceColors.panelHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'RESUMEN FINAL',
            style: TextStyle(
              color: accentColor,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          _ShareValueLine(label: 'Ingreso real', value: bundle.realCollected),
          _ShareValueLine(label: 'Gastos', value: -bundle.paidExpenses),
          _ShareValueLine(
            label: 'Pagado a proveedores',
            value: -bundle.supplierPaidTotal,
          ),
          _ShareValueLine(
            label: 'Facturas pendientes',
            value: bundle.pendingSupplierInvoices,
          ),
          const Divider(color: _FinanceColors.border),
          _ShareValueLine(
            label: 'RESULTADO',
            value: bundle.finalResult,
            strong: true,
            valueColor: accentColor,
          ),
        ],
      ),
    );
  }
}

class _ShareSection extends StatelessWidget {
  const _ShareSection({required this.title, required this.rows});

  final String title;
  final List<_ShareRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _FinanceColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _FinanceColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _FinanceColors.amber,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          if (rows.isEmpty)
            const Text(
              'Sin movimientos',
              style: TextStyle(color: _FinanceColors.muted, fontSize: 11),
            )
          else
            for (final row in rows)
              _ShareValueLine(
                label: row.label,
                value: row.value,
                textValue: row.textValue,
                strong: row.strong,
              ),
        ],
      ),
    );
  }
}

class _ShareRow {
  const _ShareRow(this.label, this.value, {this.strong = false})
    : textValue = null;

  const _ShareRow.count(this.label, int value)
    : value = 0,
      textValue = '$value',
      strong = false;

  final String label;
  final double value;
  final String? textValue;
  final bool strong;
}

class _ShareValueLine extends StatelessWidget {
  const _ShareValueLine({
    required this.label,
    required this.value,
    this.textValue,
    this.strong = false,
    this.valueColor,
  });

  final String label;
  final double value;
  final String? textValue;
  final bool strong;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final color = strong ? _FinanceColors.text : _FinanceColors.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            textValue ?? _money(value),
            key: ValueKey('finance-share-value-$label'),
            style: TextStyle(
              color:
                  valueColor ??
                  (strong ? _FinanceColors.lightGreen : _FinanceColors.text),
              fontSize: 12,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

@visibleForTesting
Color financeFinalResultColor(double value) {
  if (value > financeMoneyTolerance) return _FinanceColors.green;
  if (value < -financeMoneyTolerance) return _FinanceColors.red;
  return _FinanceColors.muted;
}

@visibleForTesting
Widget financeShareSummaryForTest({
  required FinanceDashboardBundle bundle,
  required String restaurantName,
  required String branchName,
  required DateTime generatedAt,
}) {
  return _FinanceShareSummary(
    bundle: bundle,
    restaurantName: restaurantName,
    branchName: branchName,
    generatedAt: generatedAt,
  );
}

List<MapEntry<String, double>> _supplierPaymentRows(
  FinanceDashboardBundle bundle,
) {
  final rows = bundle.supplierPaymentsByMethod.entries
      .map(
        (entry) =>
            MapEntry(financeSupplierPaymentMethodLabel(entry.key), entry.value),
      )
      .where((entry) => entry.value.abs() > 0.005)
      .toList();
  rows.sort((a, b) {
    final byAmount = b.value.compareTo(a.value);
    if (byAmount != 0) return byAmount;
    return a.key.toLowerCase().compareTo(b.key.toLowerCase());
  });
  return rows;
}

class _DailyCashCutCard extends StatelessWidget {
  const _DailyCashCutCard({required this.day, required this.bundle});

  final FinanceCashCutDailyDetail day;
  final FinanceDashboardBundle bundle;

  @override
  Widget build(BuildContext context) {
    final users = day.closedByNames.isEmpty
        ? 'Sin usuario de cierre'
        : day.closedByNames.join(', ');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _FinanceColors.panelHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _FinanceColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _displayDate(day.businessDate),
                  style: const TextStyle(
                    color: _FinanceColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${day.cutCount} ${day.cutCount == 1 ? 'corte' : 'cortes'} · $users',
                  style: const TextStyle(
                    color: _FinanceColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                _CashCutMetric(
                  'Efectivo contado',
                  day.cashCounted,
                  helper: 'Sin fondo inicial',
                ),
                _CashCutMetric(
                  'Gastos pagados desde caja',
                  day.cashExpensesPaid,
                ),
                _CashCutMetric(
                  'Efectivo antes de gastos',
                  day.cashOperationalBeforeExpenses,
                  accent: _FinanceColors.lightGreen,
                ),
                _CashCutMetric('Tarjeta bruta', day.cardGrossReceived),
                _CashCutMetric('Comision tarjeta', day.cardFees),
                _CashCutMetric(
                  'Tarjeta neta',
                  day.cardReceived,
                  helper: 'Despues de comision',
                ),
                _CashCutMetric('Otros monetarios', day.otherReceived),
                _CashCutMetric(
                  'Ingreso real del dia',
                  day.actualIncome,
                  accent: _FinanceColors.lightGreen,
                ),
                _CashCutMetric(
                  'Monetario esperado neto',
                  day.expectedMonetaryIncome,
                ),
                _CashCutMetric(
                  'Faltante',
                  day.shortage,
                  accent: day.shortage > 0
                      ? _FinanceColors.red
                      : _FinanceColors.muted,
                ),
                _CashCutMetric(
                  'Sobrante',
                  day.overage,
                  accent: day.overage > 0
                      ? _FinanceColors.green
                      : _FinanceColors.muted,
                ),
              ],
            ),
            if (day.cuts.length > 1) ...[
              const SizedBox(height: 8),
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  iconColor: _FinanceColors.lightGreen,
                  collapsedIconColor: _FinanceColors.muted,
                  title: const Text(
                    'Ver cortes del dia',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  children: [
                    for (final cut in day.cuts)
                      _CashCutLine(
                        title:
                            'Corte ${cut.session.id} · ${cut.session.closedByEmployeeName ?? cut.session.openedByEmployeeName}',
                        subtitle:
                            'Efectivo contado ${_money(cut.cashCountedLessOpening)} · Gastos caja ${_money(cut.approvedWithdrawals)} · '
                            'Efectivo antes gastos ${_money(cut.cashOperationalBeforeExpenses)} - Tarjeta bruta ${_money(cut.cardGrossReceived)} - Comision ${_money(cut.cardFeeAbsorbed)} - Tarjeta neta ${_money(cut.cardReceived)}',
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _showPaymentsDialog(
                  context,
                  bundle,
                  businessDate: day.businessDate,
                ),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('Ver cobros del dia'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyCashCutTotal extends StatelessWidget {
  const _DailyCashCutTotal({required this.total, required this.dashboardTotal});

  final FinanceCashCutDailyDetail total;
  final FinanceDashboardBundle dashboardTotal;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _FinanceColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _FinanceColors.lightGreen.withValues(alpha: 0.55),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'TOTAL DEL PERIODO',
              style: TextStyle(
                color: _FinanceColors.lightGreen,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                _CashCutMetric('Efectivo contado', total.cashCounted),
                _CashCutMetric('Gastos desde caja', total.cashExpensesPaid),
                _CashCutMetric(
                  'Efectivo antes de gastos',
                  total.cashOperationalBeforeExpenses,
                ),
                _CashCutMetric('Tarjeta bruta', total.cardGrossReceived),
                _CashCutMetric('Comision tarjeta', total.cardFees),
                _CashCutMetric(
                  'Tarjeta neta',
                  total.cardReceived,
                  helper: 'Despues de comision',
                ),
                _CashCutMetric('Otros', total.otherReceived),
                _CashCutMetric(
                  'Ingreso real',
                  total.actualIncome,
                  accent: _FinanceColors.lightGreen,
                ),
                _CashCutMetric('Faltantes', total.shortage),
                _CashCutMetric('Sobrantes', total.overage),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Coincide con dashboard: ${_money(dashboardTotal.realCollected)}',
              style: const TextStyle(
                color: _FinanceColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CashCutMetric extends StatelessWidget {
  const _CashCutMetric(
    this.label,
    this.value, {
    this.helper,
    this.accent = _FinanceColors.text,
  });

  final String label;
  final double value;
  final String? helper;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _FinanceColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _money(value),
            style: TextStyle(
              color: accent,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (helper != null)
            Text(
              helper!,
              style: const TextStyle(color: _FinanceColors.muted, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class _CashCutLine extends StatelessWidget {
  const _CashCutLine({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

class _DialogRow {
  const _DialogRow(this.title, this.subtitle, {this.onTap});

  final String title;
  final String subtitle;
  final VoidCallback? onTap;
}

enum _DatePreset { today, week, month }

enum _StatusKind { success, pending, cancelled, neutral }

class _FinanceColors {
  const _FinanceColors._();

  static const background = Color(0xFF090A0B);
  static const panel = Color(0xFF111315);
  static const panelHigh = Color(0xFF151719);
  static const border = Color(0xFF2B2E31);
  static const text = Color(0xFFF3F3F3);
  static const muted = Color(0xFFA2A6AA);
  static const amber = Color(0xFFE9A91A);
  static const green = Color(0xFF55B845);
  static const lightGreen = Color(0xFF77C85E);
  static const blue = Color(0xFF5799DB);
  static const violet = Color(0xFF9A63D8);
  static const red = Color(0xFFE36565);
}

BoxDecoration _panelDecoration({Color? fill, Color? borderColor}) {
  return BoxDecoration(
    color: fill ?? _FinanceColors.panel,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: borderColor ?? _FinanceColors.border),
  );
}

String _money(double value) {
  return NumberFormat.currency(
    locale: 'es_MX',
    symbol: r'$',
    decimalDigits: 2,
  ).format(value);
}

String _displayDate(String businessDate) {
  final parsed = DateTime.tryParse(businessDate);
  return parsed == null
      ? businessDate
      : DateFormat('dd/MM/yyyy').format(parsed);
}

String _fileToken(String value) {
  final clean = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  return clean.replaceAll(RegExp(r'^_+|_+$'), '').isEmpty ? 'Sucursal' : clean;
}

Widget _totalText(String value) {
  return Text(
    value,
    style: const TextStyle(
      color: _FinanceColors.text,
      fontWeight: FontWeight.w800,
      fontSize: 11,
    ),
  );
}

int _compare(Object? a, Object? b) {
  if (a is num && b is num) return a.compareTo(b);
  return (a?.toString() ?? '').compareTo(b?.toString() ?? '');
}

String financeSupplierRowStatus(FinanceSupplierRow row) {
  if (row.balance <= financeMoneyTolerance) return 'Pagada';
  final now = DateTime.now();
  if (row.purchases.any(
    (purchase) =>
        financePurchaseBalance(purchase) > financeMoneyTolerance &&
        purchase.dueDate != null &&
        purchase.dueDate!.isBefore(now),
  )) {
    return 'Vencida';
  }
  if (row.paidOnInvoices > financeMoneyTolerance) return 'Parcial';
  return 'Pendiente';
}
