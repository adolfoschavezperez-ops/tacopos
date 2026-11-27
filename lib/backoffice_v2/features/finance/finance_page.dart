import 'package:flutter/material.dart';

import '../../../core/expenses/expense_policy.dart';
import '../../../models/purchase_models.dart';
import '../../../utils/csv_exporter.dart';
import '../../auth/backoffice_session.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../widgets/empty_error_state.dart';
import '../../widgets/skeleton_loader.dart';
import 'finance_analytics.dart';
import 'finance_repository.dart';
import 'finance_views.dart';

enum _FinanceTab {
  dashboard('Dashboard'),
  incomeStatement('Estado de resultados'),
  expenses('Gastos y políticas'),
  profitability('Rentabilidad'),
  breakEven('Equilibrio y metas'),
  partners('Socios');

  const _FinanceTab(this.label);
  final String label;
}

class FinancePage extends StatefulWidget {
  const FinancePage({
    super.key,
    required this.session,
    required this.repository,
    required this.onOpenSaleDetail,
  });

  final BackofficeSession session;
  final FinanceRepository repository;
  final ValueChanged<String> onOpenSaleDetail;

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  _FinanceTab _tab = _FinanceTab.dashboard;
  FinancePeriodPreset _preset = FinancePeriodPreset.weekly;
  late DateTime _startDate;
  late DateTime _endDate;
  Future<FinanceDashboardBundle>? _future;
  String? _lastBranchId;
  String _lastRestaurantId = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _endDate = today;
    _startDate = today.subtract(const Duration(days: 6));
    _lastBranchId = widget.session.selectedBranchId;
    _lastRestaurantId = widget.session.restaurantId;
    widget.session.addListener(_handleSessionChanged);
    _load();
  }

  @override
  void dispose() {
    widget.session.removeListener(_handleSessionChanged);
    super.dispose();
  }

  void _handleSessionChanged() {
    if (_lastBranchId != widget.session.selectedBranchId ||
        _lastRestaurantId != widget.session.restaurantId) {
      _lastBranchId = widget.session.selectedBranchId;
      _lastRestaurantId = widget.session.restaurantId;
      _load();
    }
  }

  void _load() {
    setState(() {
      _future = widget.repository.loadFinanceDashboard(
        restaurantId: widget.session.restaurantId,
        startDate: _startDate,
        endDate: _endDate,
        branchId: widget.session.selectedBranchId,
      );
    });
  }

  void _applyPreset(FinancePeriodPreset preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _preset = preset;
      switch (preset) {
        case FinancePeriodPreset.daily:
          _startDate = today;
          _endDate = today;
        case FinancePeriodPreset.weekly:
          _startDate = today.subtract(const Duration(days: 6));
          _endDate = today;
        case FinancePeriodPreset.monthly:
          _startDate = DateTime(today.year, today.month, 1);
          _endDate = today;
        case FinancePeriodPreset.quarterly:
          final qMonth = ((today.month - 1) ~/ 3) * 3 + 1;
          _startDate = DateTime(today.year, qMonth, 1);
          _endDate = today;
        case FinancePeriodPreset.annual:
          _startDate = DateTime(today.year, 1, 1);
          _endDate = today;
        case FinancePeriodPreset.custom:
          break;
      }
    });
    if (preset != FinancePeriodPreset.custom) {
      _load();
    } else {
      _pickCustomRange();
    }
  }

  Future<void> _pickCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (range == null) return;
    setState(() {
      _preset = FinancePeriodPreset.custom;
      _startDate = range.start;
      _endDate = range.end;
    });
    _load();
  }

  Future<void> _exportIncomeStatementCsv(FinanceDashboardBundle bundle) async {
    final s = bundle.summary;
    final buf = StringBuffer()
      ..writeln('Concepto,Importe')
      ..writeln('Ventas brutas,${s.grossSales.toStringAsFixed(2)}')
      ..writeln('Descuentos,${s.discounts.toStringAsFixed(2)}')
      ..writeln('Consumo empleados,${s.employeeFreeMeals.toStringAsFixed(2)}')
      ..writeln('Ventas netas,${s.netSales.toStringAsFixed(2)}')
      ..writeln('Costo de venta teorico,${s.estimatedCogs.toStringAsFixed(2)}')
      ..writeln('Utilidad bruta,${s.grossProfit.toStringAsFixed(2)}')
      ..writeln(
        'Gastos operativos,${s.operatingExpensesPaid.toStringAsFixed(2)}',
      )
      ..writeln(
        'Utilidad operativa contable,${s.operatingProfitAccounting.toStringAsFixed(2)}',
      )
      ..writeln(
        'Resultado operativo flujo,${s.operatingResultFlow.toStringAsFixed(2)}',
      );
    final msg = await exportCsvFile(
      fileName:
          'estado_resultados_${BackofficeSalesAdapter.formatBusinessDate(_startDate)}.csv',
      content: buf.toString(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _exportExpensesCsv(FinanceDashboardBundle bundle) async {
    final buf = StringBuffer()
      ..writeln('Fecha,Sucursal,Concepto,Origen,Monto');
    for (final w in bundle.withdrawals.where(isFinanceOperatingExpense)) {
      buf.writeln(
        '${w.businessDate},"${w.branchName}","${w.reason.replaceAll('"', '""')}",'
        '${w.isHistorical ? 'Historico' : 'Caja'},${w.amount.toStringAsFixed(2)}',
      );
    }
    final msg = await exportCsvFile(
      fileName:
          'gastos_${BackofficeSalesAdapter.formatBusinessDate(_startDate)}.csv',
      content: buf.toString(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _exportProfitabilityCsv(FinanceDashboardBundle bundle) async {
    final buf = StringBuffer()
      ..writeln(
        'Producto,Categoria,Unidades,PrecioProm,IngresoNeto,CostoUnitario,UtilidadBruta,MargenPct,NotaCosto',
      );
    for (final r in bundle.productProfitability) {
      buf.writeln(
        '"${r.productName.replaceAll('"', '""')}","${r.categoryName}",'
        '${r.unitsSold.toStringAsFixed(0)},${r.avgRealPrice.toStringAsFixed(2)},'
        '${r.netRevenue.toStringAsFixed(2)},'
        '${r.theoreticalUnitCost?.toStringAsFixed(2) ?? 'N/D'},'
        '${r.estimatedGrossProfit?.toStringAsFixed(2) ?? 'N/D'},'
        '${r.marginPercent?.toStringAsFixed(1) ?? 'N/D'},"${r.costNote}"',
      );
    }
    final msg = await exportCsvFile(
      fileName:
          'rentabilidad_productos_${BackofficeSalesAdapter.formatBusinessDate(_startDate)}.csv',
      content: buf.toString(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _openPartnerDialog(Partner? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final pctCtrl = TextEditingController(
      text: (existing?.ownershipPercent ?? 50.0).toStringAsFixed(1),
    );
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Nuevo socio' : 'Editar socio'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre del socio'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pctCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Participación (%)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    await widget.repository.savePartner(
      restaurantId: widget.session.restaurantId,
      partnerId: existing?.id,
      name: nameCtrl.text,
      ownershipPercent: double.tryParse(pctCtrl.text.trim()) ?? 0.0,
      phone: phoneCtrl.text,
    );
    if (mounted) _load();
  }

  Future<void> _openContributionDialog(FinanceDashboardBundle bundle) async {
    if (bundle.partners.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero registra al menos un socio.')),
      );
      return;
    }
    var partnerId = bundle.partners.first.id;
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    var method = 'transfer';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Registrar aportación de socio'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: partnerId,
                  decoration: const InputDecoration(labelText: 'Socio'),
                  items: bundle.partners
                      .map(
                        (p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(p.name),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (v) {
                    if (v != null) setS(() => partnerId = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Monto (\$)'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(labelText: 'Método'),
                  items: const [
                    DropdownMenuItem(
                      value: 'transfer',
                      child: Text('Transferencia'),
                    ),
                    DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                    DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
                  ],
                  onChanged: (v) {
                    if (v != null) setS(() => method = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notas'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
    if (amount <= 0) return;
    final partner = bundle.partners.firstWhere((p) => p.id == partnerId);
    final branchId = widget.session.selectedBranchId ??
        (widget.session.branches.isNotEmpty
            ? widget.session.branches.first.id
            : '');
    final emp = widget.session.employee;
    await widget.repository.registerPartnerContribution(
      restaurantId: widget.session.restaurantId,
      branchId: branchId,
      partnerId: partner.id,
      partnerName: partner.name,
      businessDate: BackofficeSalesAdapter.formatBusinessDate(DateTime.now()),
      amount: amount,
      method: method,
      notes: notesCtrl.text,
      employeeId: emp?.id ?? '',
      employeeName: emp?.name ?? 'Admin',
    );
    if (mounted) _load();
  }

  Future<void> _openPolicyDialog(ExpensePolicy? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final codeCtrl = TextEditingController(text: existing?.code ?? '');
    final maxTxCtrl = TextEditingController(
      text: (existing?.maxAmountPerTransaction ?? 500.0).toStringAsFixed(0),
    );
    final maxPerCtrl = TextEditingController(
      text: (existing?.maxAmountPerPeriod ?? 2000.0).toStringAsFixed(0),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          existing == null ? 'Nueva política de gasto' : 'Editar política',
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(labelText: 'Código'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: maxTxCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tope por transacción (\$)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: maxPerCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tope por periodo (\$)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    final emp = widget.session.employee;
    final policy = (existing ??
            ExpensePolicy(
              id: '',
              restaurantId: widget.session.restaurantId,
              branchId: widget.session.selectedBranchId ?? '',
              name: nameCtrl.text.trim(),
              code: codeCtrl.text.trim(),
            ))
        .copyWith(
          name: nameCtrl.text.trim(),
          code: codeCtrl.text.trim(),
          maxAmountPerTransaction:
              double.tryParse(maxTxCtrl.text.trim()) ?? 500.0,
          maxAmountPerPeriod:
              double.tryParse(maxPerCtrl.text.trim()) ?? 2000.0,
        );
    await widget.repository.saveExpensePolicy(
      restaurantId: widget.session.restaurantId,
      policy: policy,
      employeeId: emp?.id ?? '',
      employeeName: emp?.name ?? 'Admin',
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final branchNames = {
      for (final b in widget.session.branches) b.id: b.name,
    };
    final perms = widget.session.permissions;
    final totalDays = _endDate.difference(_startDate).inDays + 1;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Finanzas, Costos y Rentabilidad',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Estado de resultados, gastos, rentabilidad por producto, punto de equilibrio y socios.',
                style: TextStyle(fontSize: 13, color: tokens.textSecondary),
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final p in FinancePeriodPreset.values)
                      ChoiceChip(
                        label: Text(p.label),
                        selected: _preset == p,
                        onSelected: (_) => _applyPreset(p),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.date_range_rounded, size: 16),
                      label: Text(
                        '${BackofficeSalesAdapter.formatBusinessDate(_startDate)} — ${BackofficeSalesAdapter.formatBusinessDate(_endDate)}',
                      ),
                      onPressed: _pickCustomRange,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _FinanceTab.values
                    .map(
                      (t) => ChoiceChip(
                        label: Text(t.label),
                        selected: _tab == t,
                        onSelected: (_) => setState(() => _tab = t),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 18),
              FutureBuilder<FinanceDashboardBundle>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Column(
                      children: [
                        TableSkeleton(rows: 4),
                        SizedBox(height: 16),
                        TableSkeleton(rows: 6),
                      ],
                    );
                  }
                  if (snapshot.hasError) {
                    return SaasErrorState(
                      title: 'No pudimos cargar el módulo financiero',
                      message:
                          'Verifica tu conexión o permisos e intenta nuevamente.',
                      onRetry: _load,
                    );
                  }
                  final bundle = snapshot.data;
                  if (bundle == null) return const SizedBox.shrink();

                  final activeBranchId = widget.session.selectedBranchId ??
                      (widget.session.branches.isNotEmpty
                          ? widget.session.branches.first.id
                          : 'all');
                  final emp = widget.session.employee;

                  return switch (_tab) {
                    _FinanceTab.dashboard => FinanceDashboardTab(
                      bundle: bundle,
                      isMobile: isMobile,
                    ),
                    _FinanceTab.incomeStatement => IncomeStatementTab(
                      bundle: bundle,
                      onExportCsv: () => _exportIncomeStatementCsv(bundle),
                      onOpenSaleDetail: widget.onOpenSaleDetail,
                    ),
                    _FinanceTab.expenses => ExpensesAndPoliciesTab(
                      bundle: bundle,
                      branchNames: branchNames,
                      canManagePolicies: perms.canManageExpensePolicies,
                      onExportCsv: () => _exportExpensesCsv(bundle),
                      onTogglePoliciesEnabled: (v) async {
                        final cur = bundle.expensePolicySettings;
                        await widget.repository.saveExpensePolicySettings(
                          restaurantId: widget.session.restaurantId,
                          settings: ExpensePolicySettings(
                            expensePoliciesEnabled: v,
                            expensePolicyMode: v
                                ? (cur.expensePolicyMode == ExpensePolicyMode.off
                                      ? ExpensePolicyMode.live
                                      : cur.expensePolicyMode)
                                : ExpensePolicyMode.off,
                            manualApprovalCutoffEnabled:
                                cur.manualApprovalCutoffEnabled,
                            manualApprovalCutoffTime:
                                cur.manualApprovalCutoffTime,
                            defaultReceiptRequired: cur.defaultReceiptRequired,
                          ),
                          employeeId: emp?.id ?? '',
                          employeeName: emp?.name ?? 'Admin',
                        );
                        if (mounted) _load();
                      },
                      onChangePolicyMode: (m) async {
                        final cur = bundle.expensePolicySettings;
                        await widget.repository.saveExpensePolicySettings(
                          restaurantId: widget.session.restaurantId,
                          settings: ExpensePolicySettings(
                            expensePoliciesEnabled:
                                m != ExpensePolicyMode.off,
                            expensePolicyMode: m,
                            manualApprovalCutoffEnabled:
                                cur.manualApprovalCutoffEnabled,
                            manualApprovalCutoffTime:
                                cur.manualApprovalCutoffTime,
                            defaultReceiptRequired: cur.defaultReceiptRequired,
                          ),
                          employeeId: emp?.id ?? '',
                          employeeName: emp?.name ?? 'Admin',
                        );
                        if (mounted) _load();
                      },
                      onSavePolicy: _openPolicyDialog,
                      onTogglePolicyActive: (p, active) async {
                        await widget.repository.saveExpensePolicy(
                          restaurantId: widget.session.restaurantId,
                          policy: p.copyWith(active: active),
                          employeeId: emp?.id ?? '',
                          employeeName: emp?.name ?? 'Admin',
                        );
                        if (mounted) _load();
                      },
                    ),
                    _FinanceTab.profitability => ProductProfitabilityTab(
                      rows: bundle.productProfitability,
                      onExportCsv: () => _exportProfitabilityCsv(bundle),
                    ),
                    _FinanceTab.breakEven => BreakEvenAndEfficiencyTab(
                      bundle: bundle,
                      elapsedDays: totalDays,
                      totalDays: totalDays,
                      canManageBudgets: perms.canManageFinanceBudgets,
                      onSaveTarget: (key, pct) async {
                        final messenger = ScaffoldMessenger.of(context);
                        await widget.repository.saveEfficiencyTarget(
                          restaurantId: widget.session.restaurantId,
                          branchId: activeBranchId,
                          categoryKey: key,
                          targetPer100Sales: pct,
                          employeeId: emp?.id ?? '',
                          employeeName: emp?.name ?? 'Admin',
                        );
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Meta guardada en DEV.'),
                            ),
                          );
                          _load();
                        }
                      },
                      onSaveBudget: (type, amount) async {
                        final messenger = ScaffoldMessenger.of(context);
                        await widget.repository.saveFinanceBudget(
                          restaurantId: widget.session.restaurantId,
                          branchId: activeBranchId,
                          budgetType: type,
                          amount: amount,
                          periodLabel: _preset.label,
                          employeeId: emp?.id ?? '',
                          employeeName: emp?.name ?? 'Admin',
                        );
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Presupuesto guardado en DEV.'),
                            ),
                          );
                          _load();
                        }
                      },
                    ),
                    _FinanceTab.partners => PartnersFinanceTab(
                      bundle: bundle,
                      canManagePartners: perms.canManagePartners,
                      onCreateOrEditPartner: _openPartnerDialog,
                      onRegisterContribution: () =>
                          _openContributionDialog(bundle),
                    ),
                  };
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
