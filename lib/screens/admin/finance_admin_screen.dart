import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/cash_withdrawal_request.dart';
import '../../models/employee.dart';
import '../../models/payment.dart';
import '../../models/purchase_models.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';

class FinanceAdminScreen extends StatefulWidget {
  const FinanceAdminScreen({super.key});

  @override
  State<FinanceAdminScreen> createState() => _FinanceAdminScreenState();
}

class _FinanceAdminScreenState extends State<FinanceAdminScreen> {
  final _repository = TacoPosRepository();
  late DateTime _startDate;
  late DateTime _endDate;
  String? _supplierId;

  String get _startBusinessDate => DateFormat('yyyy-MM-dd').format(_startDate);
  String get _endBusinessDate => DateFormat('yyyy-MM-dd').format(_endDate);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month, now.day);
    _repository.ensureDefaultPartners().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Estado financiero'),
              Tab(text: 'Flujo de efectivo'),
              Tab(text: 'Aportaciones de socios'),
              Tab(text: 'Pagos a proveedores'),
              Tab(text: 'Reportes'),
            ],
          ),
          Expanded(
            child: StreamBuilder<List<Supplier>>(
              stream: _repository.watchSuppliers(),
              builder: (context, suppliersSnapshot) {
                if (suppliersSnapshot.hasError) {
                  return EmptyState(
                    icon: Icons.error_outline,
                    title: 'No se pudieron cargar proveedores',
                    message: '${suppliersSnapshot.error}',
                  );
                }
                if (!suppliersSnapshot.hasData) {
                  return const LoadingPanel(message: 'Cargando finanzas...');
                }
                return StreamBuilder<List<SupplierPurchase>>(
                  stream: _repository.watchSupplierPurchases(),
                  builder: (context, purchasesSnapshot) {
                    return StreamBuilder<List<SupplierPayment>>(
                      stream: _repository.watchSupplierPayments(),
                      builder: (context, supplierPaymentsSnapshot) {
                        return StreamBuilder<List<PartnerContribution>>(
                          stream: _repository.watchPartnerContributions(),
                          builder: (context, contributionsSnapshot) {
                            return StreamBuilder<List<Partner>>(
                              stream: _repository.watchPartners(),
                              builder: (context, partnersSnapshot) {
                                return StreamBuilder<
                                  List<CashWithdrawalRequest>
                                >(
                                  stream: _repository
                                      .watchCashWithdrawalRequests(
                                        startBusinessDate: _startBusinessDate,
                                        endBusinessDate: _endBusinessDate,
                                        status: 'approved',
                                      ),
                                  builder: (context, withdrawalsSnapshot) {
                                    return StreamBuilder<List<Payment>>(
                                      stream: _repository
                                          .watchDashboardPayments(
                                            startDate: _startDate,
                                            endDate: _endDate,
                                          ),
                                      builder: (context, paymentsSnapshot) {
                                        final data = _FinanceData(
                                          suppliers:
                                              suppliersSnapshot.data ??
                                              const [],
                                          purchases:
                                              purchasesSnapshot.data ??
                                              const [],
                                          supplierPayments:
                                              supplierPaymentsSnapshot.data ??
                                              const [],
                                          contributions:
                                              contributionsSnapshot.data ??
                                              const [],
                                          partners:
                                              partnersSnapshot.data ?? const [],
                                          withdrawals:
                                              withdrawalsSnapshot.data ??
                                              const [],
                                          customerPayments:
                                              paymentsSnapshot.data ?? const [],
                                          startDate: _startDate,
                                          endDate: _endDate,
                                          startBusinessDate: _startBusinessDate,
                                          endBusinessDate: _endBusinessDate,
                                          supplierId: _supplierId,
                                        );
                                        final summary = _FinanceSummary(data);
                                        return Column(
                                          children: [
                                            _FinanceFilters(
                                              suppliers:
                                                  suppliersSnapshot.data ??
                                                  const [],
                                              supplierId: _supplierId,
                                              startDate: _startDate,
                                              endDate: _endDate,
                                              onSupplierChanged: (value) =>
                                                  setState(
                                                    () => _supplierId = value,
                                                  ),
                                              onToday: _today,
                                              onWeek: _week,
                                              onMonth: _month,
                                              onPickStart: () =>
                                                  _pickDate(isStart: true),
                                              onPickEnd: () =>
                                                  _pickDate(isStart: false),
                                            ),
                                            Expanded(
                                              child: TabBarView(
                                                children: [
                                                  _FinancialStateTab(
                                                    summary: summary,
                                                  ),
                                                  _CashFlowTab(
                                                    summary: summary,
                                                  ),
                                                  _PartnerContributionsTab(
                                                    repository: _repository,
                                                    partners: data.partners,
                                                    contributions:
                                                        summary.contributions,
                                                  ),
                                                  _SupplierPaymentsFinanceTab(
                                                    payments: summary
                                                        .supplierPayments,
                                                  ),
                                                  _FinanceReportsTab(
                                                    summary: summary,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      } else {
        _endDate = picked;
        if (_startDate.isAfter(_endDate)) _startDate = _endDate;
      }
    });
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
}

class _FinanceData {
  const _FinanceData({
    required this.suppliers,
    required this.purchases,
    required this.supplierPayments,
    required this.contributions,
    required this.partners,
    required this.withdrawals,
    required this.customerPayments,
    required this.startDate,
    required this.endDate,
    required this.startBusinessDate,
    required this.endBusinessDate,
    required this.supplierId,
  });

  final List<Supplier> suppliers;
  final List<SupplierPurchase> purchases;
  final List<SupplierPayment> supplierPayments;
  final List<PartnerContribution> contributions;
  final List<Partner> partners;
  final List<CashWithdrawalRequest> withdrawals;
  final List<Payment> customerPayments;
  final DateTime startDate;
  final DateTime endDate;
  final String startBusinessDate;
  final String endBusinessDate;
  final String? supplierId;
}

class _FinanceSummary {
  _FinanceSummary(_FinanceData data)
    : customerPayments = data.customerPayments
          .where((payment) => payment.isActive)
          .toList(),
      purchases = data.purchases.where((purchase) {
        if (purchase.status == 'cancelled') return false;
        if (data.supplierId != null && purchase.supplierId != data.supplierId) {
          return false;
        }
        return _dateInRange(
          purchase.purchaseDate,
          data.startDate,
          data.endDate,
        );
      }).toList(),
      supplierPayments = data.supplierPayments.where((payment) {
        if (payment.status != 'active') return false;
        if (data.supplierId != null && payment.supplierId != data.supplierId) {
          return false;
        }
        return _dateInRange(payment.paymentDate, data.startDate, data.endDate);
      }).toList(),
      contributions = data.contributions.where((contribution) {
        if (!contribution.isActive) return false;
        if (data.supplierId != null &&
            contribution.supplierId != data.supplierId) {
          return false;
        }
        return _dateInRange(contribution.date, data.startDate, data.endDate);
      }).toList(),
      withdrawals = data.withdrawals
          .where(
            (request) =>
                request.status == 'approved' &&
                request.businessDate.compareTo(data.startBusinessDate) >= 0 &&
                request.businessDate.compareTo(data.endBusinessDate) <= 0,
          )
          .toList(),
      pendingPurchases = data.purchases.where((purchase) {
        if (purchase.status == 'cancelled' || purchase.balance <= 0.01) {
          return false;
        }
        if (data.supplierId != null && purchase.supplierId != data.supplierId) {
          return false;
        }
        return true;
      }).toList();

  final List<Payment> customerPayments;
  final List<SupplierPurchase> purchases;
  final List<SupplierPayment> supplierPayments;
  final List<PartnerContribution> contributions;
  final List<CashWithdrawalRequest> withdrawals;
  final List<SupplierPurchase> pendingPurchases;

  double get salesCollected =>
      customerPayments.fold(0, (sum, payment) => sum + payment.chargedAmount);
  double get cashCollected => customerPayments
      .where((payment) => payment.method == 'cash')
      .fold(0, (sum, payment) => sum + payment.chargedAmount);
  double get cardCollected => customerPayments
      .where((payment) => payment.method == 'card')
      .fold(0, (sum, payment) => sum + payment.chargedAmount);
  double get platformCollected => customerPayments
      .where((payment) => payment.method == 'platform_paid')
      .fold(0, (sum, payment) => sum + payment.chargedAmount);
  double get employeeConsumption => customerPayments
      .where((payment) => payment.method == 'employee_consumption')
      .fold(0, (sum, payment) => sum + payment.chargedAmount);
  double get registeredPurchases =>
      purchases.fold(0, (sum, purchase) => sum + purchase.total);
  double get supplierPaymentsTotal =>
      supplierPayments.fold(0, (sum, payment) => sum + payment.amount);
  double get pendingPayableBalance =>
      pendingPurchases.fold(0, (sum, purchase) => sum + purchase.balance);
  double get duePurchases => pendingPurchases
      .where((purchase) => !purchase.dueDate.isAfter(DateTime.now()))
      .fold(0, (sum, purchase) => sum + purchase.balance);
  double get businessSupplierPayments => supplierPayments
      .where((payment) => payment.fundingSource.startsWith('business_'))
      .fold(0, (sum, payment) => sum + payment.amount);
  double get partnerSupplierPayments => supplierPayments
      .where((payment) => payment.fundingSource.startsWith('partner_'))
      .fold(0, (sum, payment) => sum + payment.amount);
  double get businessTransfers => supplierPayments
      .where((payment) => payment.fundingSource == 'business_transfer')
      .fold(0, (sum, payment) => sum + payment.amount);
  double get cashWithdrawals =>
      withdrawals.fold(0, (sum, request) => sum + request.amount);
  double get partnerContributions =>
      contributions.fold(0, (sum, contribution) => sum + contribution.amount);
  double get partnerCashContributions => contributions
      .where((contribution) => contribution.method == 'cash')
      .fold(0, (sum, contribution) => sum + contribution.amount);
  double get partnerTransferContributions => contributions
      .where((contribution) => contribution.method == 'transfer')
      .fold(0, (sum, contribution) => sum + contribution.amount);
  double get businessCashFlow =>
      salesCollected - businessSupplierPayments - cashWithdrawals;
  double get cashFlowWithPartners =>
      salesCollected +
      partnerContributions -
      businessSupplierPayments -
      partnerSupplierPayments -
      cashWithdrawals;
  double get estimatedResult =>
      salesCollected - registeredPurchases - cashWithdrawals;
  double get paidResult =>
      salesCollected - businessSupplierPayments - cashWithdrawals;
  double get missingFromSales =>
      (businessSupplierPayments + cashWithdrawals - salesCollected).clamp(
        0,
        double.infinity,
      );
}

class _FinanceFilters extends StatelessWidget {
  const _FinanceFilters({
    required this.suppliers,
    required this.supplierId,
    required this.startDate,
    required this.endDate,
    required this.onSupplierChanged,
    required this.onToday,
    required this.onWeek,
    required this.onMonth,
    required this.onPickStart,
    required this.onPickEnd,
  });

  final List<Supplier> suppliers;
  final String? supplierId;
  final DateTime startDate;
  final DateTime endDate;
  final ValueChanged<String?> onSupplierChanged;
  final VoidCallback onToday;
  final VoidCallback onWeek;
  final VoidCallback onMonth;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: GlassPanel(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                initialValue: supplierId,
                decoration: const InputDecoration(labelText: 'Proveedor'),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('Todos'),
                  ),
                  ...suppliers.map(
                    (supplier) => DropdownMenuItem(
                      value: supplier.id,
                      child: Text(supplier.commercialName),
                    ),
                  ),
                ],
                onChanged: onSupplierChanged,
              ),
            ),
            OutlinedButton.icon(
              onPressed: onPickStart,
              icon: const Icon(Icons.event_outlined),
              label: Text(DateFormat('dd/MM/yyyy').format(startDate)),
            ),
            OutlinedButton.icon(
              onPressed: onPickEnd,
              icon: const Icon(Icons.event_available_outlined),
              label: Text(DateFormat('dd/MM/yyyy').format(endDate)),
            ),
            TextButton(onPressed: onToday, child: const Text('Hoy')),
            TextButton(onPressed: onWeek, child: const Text('Semana')),
            TextButton(onPressed: onMonth, child: const Text('Mes')),
          ],
        ),
      ),
    );
  }
}

class _FinancialStateTab extends StatelessWidget {
  const _FinancialStateTab({required this.summary});

  final _FinanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final alertColor = summary.partnerSupplierPayments > 0
        ? BrandColors.info
        : summary.missingFromSales > 0
        ? BrandColors.danger
        : BrandColors.success;
    final alertText = summary.partnerSupplierPayments > 0
        ? 'Se cubrieron pagos con inversion de socios por ${_money(summary.partnerSupplierPayments)}.'
        : summary.missingFromSales > 0
        ? 'Con la venta actual no alcanza para cubrir los pagos. Faltan ${_money(summary.missingFromSales)}.'
        : 'La venta del periodo cubre los pagos registrados.';
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(14),
          child: Text(
            alertText,
            style: TextStyle(color: alertColor, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 14),
        _KpiGrid(
          items: [
            _Kpi('Ventas cobradas', summary.salesCollected),
            _Kpi('Compras registradas', summary.registeredPurchases),
            _Kpi('Pagos a proveedores', summary.supplierPaymentsTotal),
            _Kpi('Saldo a proveedores', summary.pendingPayableBalance),
            _Kpi('Aportaciones socios', summary.partnerContributions),
            _Kpi('Utilidad estimada', summary.estimatedResult),
          ],
        ),
        const SizedBox(height: 14),
        _ResultSplit(summary: summary),
      ],
    );
  }
}

class _CashFlowTab extends StatelessWidget {
  const _CashFlowTab({required this.summary});

  final _FinanceSummary summary;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _KpiGrid(
          items: [
            _Kpi('Efectivo cobrado', summary.cashCollected),
            _Kpi('Tarjeta cobrada', summary.cardCollected),
            _Kpi('Plataforma cobrada', summary.platformCollected),
            _Kpi('Consumo empleado', summary.employeeConsumption),
            _Kpi('Pagos con venta', summary.businessSupplierPayments),
            _Kpi('Pagos con socios', summary.partnerSupplierPayments),
            _Kpi('Gastos/retiros caja', summary.cashWithdrawals),
            _Kpi('Flujo negocio', summary.businessCashFlow),
            _Kpi('Flujo con socios', summary.cashFlowWithPartners),
          ],
        ),
      ],
    );
  }
}

class _PartnerContributionsTab extends StatelessWidget {
  const _PartnerContributionsTab({
    required this.repository,
    required this.partners,
    required this.contributions,
  });

  final TacoPosRepository repository;
  final List<Partner> partners;
  final List<PartnerContribution> contributions;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _SectionHeader(
          title: 'Socios',
          action: FilledButton.icon(
            onPressed: () => _openPartnerDialog(context),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Socio'),
          ),
        ),
        const SizedBox(height: 10),
        if (partners.isEmpty)
          const EmptyState(
            icon: Icons.groups_outlined,
            title: 'Sin socios',
            message: 'Crea socios para registrar aportaciones.',
          )
        else
          ...partners.map(
            (partner) => _FinanceTile(
              title: partner.name,
              subtitle: _partnerSubtitle(partner),
              amount: partner.ownershipPercent,
              amountSuffix: '%',
              onTap: () => _openPartnerDialog(context, partner),
            ),
          ),
        const SizedBox(height: 20),
        const _SectionHeader(title: 'Aportaciones registradas'),
        const SizedBox(height: 10),
        if (contributions.isEmpty)
          const EmptyState(
            icon: Icons.savings_outlined,
            title: 'Sin aportaciones',
            message: 'Las inversiones de socios apareceran aqui.',
          )
        else
          ...contributions.map(
            (contribution) => _FinanceTile(
              title: contribution.partnerName,
              subtitle:
                  '${_methodLabel(contribution.method)} · ${contribution.supplierName ?? 'Sin proveedor'}'
                  '${contribution.reference.isEmpty ? '' : ' · ${contribution.reference}'}',
              amount: contribution.amount,
            ),
          ),
      ],
    );
  }

  String _partnerSubtitle(Partner partner) {
    final parts = <String>[
      partner.active ? 'Activo' : 'Inactivo',
      if (partner.phone.trim().isNotEmpty) partner.phone.trim(),
      if (partner.linkedEmployeeName.trim().isNotEmpty)
        'Empleado ligado: ${partner.linkedEmployeeName.trim()}',
    ];
    return parts.join(' · ');
  }

  Future<void> _openPartnerDialog(
    BuildContext context, [
    Partner? partner,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PartnerDialog(repository: repository, partner: partner),
    );
    if (!context.mounted || saved != true) return;
    showAppSnackBar(
      context,
      partner == null ? 'Socio creado.' : 'Socio actualizado.',
      type: AppSnackBarType.success,
    );
  }
}

class _SupplierPaymentsFinanceTab extends StatelessWidget {
  const _SupplierPaymentsFinanceTab({required this.payments});

  final List<SupplierPayment> payments;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const _SectionHeader(title: 'Pagos a proveedores'),
        const SizedBox(height: 10),
        if (payments.isEmpty)
          const EmptyState(
            icon: Icons.payments_outlined,
            title: 'Sin pagos',
            message: 'Los pagos a proveedores apareceran aqui.',
          )
        else
          ...payments.map(
            (payment) => _FinanceTile(
              title: payment.supplierName,
              subtitle:
                  '${payment.fundingSourceName} · ${_methodLabel(payment.method)}'
                  '${payment.partnerName == null ? '' : ' · ${payment.partnerName}'}'
                  '${payment.reference.isEmpty ? '' : ' · ${payment.reference}'}',
              amount: payment.amount,
            ),
          ),
      ],
    );
  }
}

class _FinanceReportsTab extends StatelessWidget {
  const _FinanceReportsTab({required this.summary});

  final _FinanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final paymentsByOrigin = _groupPaymentsByOrigin(summary.supplierPayments);
    final purchasesBySupplier = _groupPurchasesBySupplier(summary.purchases);
    final paymentsBySupplier = _groupPaymentsBySupplier(
      summary.supplierPayments,
    );
    final contributionsByPartner = _groupContributionsByPartner(
      summary.contributions,
    );
    final pendingBySupplier = _groupPendingBySupplier(summary.pendingPurchases);
    final cashFlowByDay = _groupCashFlowByDay(summary);
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _ReportGroup(title: 'Compras por proveedor', rows: purchasesBySupplier),
        const SizedBox(height: 16),
        _ReportGroup(title: 'Pagos por proveedor', rows: paymentsBySupplier),
        const SizedBox(height: 16),
        _ReportGroup(
          title: 'Pagos por origen del dinero',
          rows: paymentsByOrigin,
        ),
        const SizedBox(height: 16),
        _ReportGroup(
          title: 'Aportaciones por socio',
          rows: contributionsByPartner,
        ),
        const SizedBox(height: 16),
        _ReportGroup(
          title: 'Saldo pendiente por proveedor',
          rows: pendingBySupplier,
        ),
        const SizedBox(height: 16),
        _ReportGroup(title: 'Flujo de efectivo por dia', rows: cashFlowByDay),
        const SizedBox(height: 16),
        _ReportGroup(
          title: 'Resultado por sucursal',
          rows: {
            'Venta total': summary.salesCollected,
            'Compras registradas': summary.registeredPurchases,
            'Gastos/retiros': summary.cashWithdrawals,
            'Utilidad estimada': summary.estimatedResult,
          },
        ),
      ],
    );
  }
}

class _ResultSplit extends StatelessWidget {
  const _ResultSplit({required this.summary});

  final _FinanceSummary summary;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 18,
        runSpacing: 12,
        children: [
          _MiniMetric('Resultado operativo', summary.estimatedResult),
          _MiniMetric('Flujo negocio', summary.businessCashFlow),
          _MiniMetric('Flujo con socios', summary.cashFlowWithPartners),
          _MiniMetric('Compras no pagadas', summary.pendingPayableBalance),
          _MiniMetric('Compras vencidas', summary.duePurchases),
          _MiniMetric('Transferencias negocio', summary.businessTransfers),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.items});

  final List<_Kpi> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 920
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 4.2 : 2.6,
          children: items
              .map(
                (item) => GlassCard(
                  accent: item.value < 0
                      ? BrandColors.danger
                      : item.value == 0
                      ? BrandColors.textMuted
                      : BrandColors.success,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.label,
                          style: const TextStyle(
                            color: BrandColors.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        MoneyText(
                          value: item.value,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _Kpi {
  const _Kpi(this.label, this.value);

  final String label;
  final double value;
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric(this.label, this.value);

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: BrandColors.textMuted)),
          const SizedBox(height: 4),
          MoneyText(
            value: value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: value < 0 ? BrandColors.danger : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceTile extends StatelessWidget {
  const _FinanceTile({
    required this.title,
    required this.subtitle,
    required this.amount,
    this.amountSuffix,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final double amount;
  final String? amountSuffix;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: ListTile(
          onTap: onTap,
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(subtitle),
          trailing: amountSuffix == null
              ? MoneyText(value: amount)
              : Text(
                  '${amount.toStringAsFixed(2)}$amountSuffix',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _ReportGroup extends StatelessWidget {
  const _ReportGroup({required this.title, required this.rows});

  final String title;
  final Map<String, double> rows;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Text(
              'Sin datos.',
              style: TextStyle(color: BrandColors.textMuted),
            )
          else
            ...rows.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(entry.key)),
                    MoneyText(value: entry.value),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PartnerDialog extends StatefulWidget {
  const _PartnerDialog({required this.repository, this.partner});

  final TacoPosRepository repository;
  final Partner? partner;

  @override
  State<_PartnerDialog> createState() => _PartnerDialogState();
}

class _PartnerDialogState extends State<_PartnerDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _ownershipController;
  late final TextEditingController _phoneController;
  late final TextEditingController _pinController;
  late final TextEditingController _notesController;
  late bool _active;
  List<Employee> _employees = const [];
  String? _linkedEmployeeId;
  bool _employeesLoading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final partner = widget.partner;
    _nameController = TextEditingController(text: partner?.name ?? '');
    _ownershipController = TextEditingController(
      text: partner == null || partner.ownershipPercent <= 0
          ? ''
          : partner.ownershipPercent.toStringAsFixed(2),
    );
    _phoneController = TextEditingController(text: partner?.phone ?? '');
    _pinController = TextEditingController();
    _notesController = TextEditingController(text: partner?.notes ?? '');
    _active = partner?.active ?? true;
    _linkedEmployeeId = partner?.linkedEmployeeId.trim().isEmpty == true
        ? null
        : partner?.linkedEmployeeId.trim();
    _loadEmployees();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ownershipController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedLinkedEmployeeId = _employeeIdInOptions(_linkedEmployeeId)
        ? _linkedEmployeeId
        : null;
    return AlertDialog(
      title: Text(widget.partner == null ? 'Nuevo socio' : 'Editar socio'),
      content: SizedBox(
        width: 440,
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _field(_nameController, 'Nombre', 260),
            _field(_ownershipController, 'Participacion %', 140),
            _field(_phoneController, 'Telefono', 180),
            _field(_pinController, 'Nuevo PIN', 140, obscure: true),
            SizedBox(
              width: 390,
              child: DropdownButtonFormField<String?>(
                initialValue: selectedLinkedEmployeeId,
                decoration: InputDecoration(
                  labelText: 'Empleado ligado del sistema',
                  helperText: _employeesLoading
                      ? 'Cargando empleados...'
                      : 'Opcional',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Sin empleado ligado'),
                  ),
                  ..._employees.map(
                    (employee) => DropdownMenuItem<String?>(
                      value: employee.id,
                      child: Text(employee.name),
                    ),
                  ),
                ],
                onChanged: _employeesLoading
                    ? null
                    : (value) => setState(() => _linkedEmployeeId = value),
              ),
            ),
            SizedBox(
              width: 160,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                title: const Text('Activo'),
                onChanged: (value) => setState(() => _active = value),
              ),
            ),
            _field(_notesController, 'Notas', 390),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando...' : 'Guardar'),
        ),
      ],
    );
  }

  Future<void> _loadEmployees() async {
    try {
      final employees = await widget.repository.getEmployeesOnce();
      if (!mounted) return;
      setState(() {
        _employees = employees;
        if (!_employeeIdInOptions(_linkedEmployeeId)) {
          _linkedEmployeeId = null;
        }
        _employeesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _employees = const [];
        _linkedEmployeeId = null;
        _employeesLoading = false;
      });
    }
  }

  bool _employeeIdInOptions(String? employeeId) {
    if (employeeId == null || employeeId.trim().isEmpty) return false;
    return _employees.any((employee) => employee.id == employeeId.trim());
  }

  Employee? _selectedLinkedEmployee() {
    final employeeId = _linkedEmployeeId?.trim();
    if (employeeId == null || employeeId.isEmpty) return null;
    for (final employee in _employees) {
      if (employee.id == employeeId) return employee;
    }
    return null;
  }

  Widget _field(
    TextEditingController controller,
    String label,
    double width, {
    bool obscure = false,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final linkedEmployee = _selectedLinkedEmployee();
      await widget.repository.savePartner(
        partnerId: widget.partner?.id,
        name: _nameController.text,
        active: _active,
        ownershipPercent: _parse(_ownershipController.text),
        phone: _phoneController.text,
        pin: _pinController.text,
        linkedEmployeeId: linkedEmployee?.id ?? '',
        linkedEmployeeName: linkedEmployee?.name ?? '',
        notes: _notesController.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

Map<String, double> _groupPaymentsByOrigin(List<SupplierPayment> payments) {
  final result = <String, double>{};
  for (final payment in payments) {
    result.update(
      payment.fundingSourceName,
      (value) => value + payment.amount,
      ifAbsent: () => payment.amount,
    );
  }
  return result;
}

Map<String, double> _groupPurchasesBySupplier(
  List<SupplierPurchase> purchases,
) {
  final result = <String, double>{};
  for (final purchase in purchases) {
    result.update(
      purchase.supplierName,
      (value) => value + purchase.total,
      ifAbsent: () => purchase.total,
    );
  }
  return result;
}

Map<String, double> _groupPaymentsBySupplier(List<SupplierPayment> payments) {
  final result = <String, double>{};
  for (final payment in payments) {
    result.update(
      payment.supplierName,
      (value) => value + payment.amount,
      ifAbsent: () => payment.amount,
    );
  }
  return result;
}

Map<String, double> _groupContributionsByPartner(
  List<PartnerContribution> contributions,
) {
  final result = <String, double>{};
  for (final contribution in contributions) {
    result.update(
      contribution.partnerName,
      (value) => value + contribution.amount,
      ifAbsent: () => contribution.amount,
    );
  }
  return result;
}

Map<String, double> _groupCashFlowByDay(_FinanceSummary summary) {
  final result = <String, double>{};
  for (final payment in summary.customerPayments) {
    final date = payment.businessDate ?? _dayKey(payment.createdAt);
    result.update(
      date,
      (value) => value + payment.chargedAmount,
      ifAbsent: () => payment.chargedAmount,
    );
  }
  for (final payment in summary.supplierPayments) {
    final date = _dayKey(payment.paymentDate);
    result.update(
      date,
      (value) => value - payment.amount,
      ifAbsent: () => -payment.amount,
    );
  }
  for (final request in summary.withdrawals) {
    result.update(
      request.businessDate,
      (value) => value - request.amount,
      ifAbsent: () => -request.amount,
    );
  }
  for (final contribution in summary.contributions) {
    final date = _dayKey(contribution.date);
    result.update(
      date,
      (value) => value + contribution.amount,
      ifAbsent: () => contribution.amount,
    );
  }
  return Map.fromEntries(
    result.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

Map<String, double> _groupPendingBySupplier(List<SupplierPurchase> purchases) {
  final result = <String, double>{};
  for (final purchase in purchases) {
    result.update(
      purchase.supplierName,
      (value) => value + purchase.balance,
      ifAbsent: () => purchase.balance,
    );
  }
  return result;
}

String _dayKey(DateTime? date) {
  final value = date ?? DateTime.now();
  return DateFormat('yyyy-MM-dd').format(value);
}

bool _dateInRange(DateTime date, DateTime start, DateTime end) {
  final cleanDate = DateTime(date.year, date.month, date.day);
  final cleanStart = DateTime(start.year, start.month, start.day);
  final cleanEnd = DateTime(end.year, end.month, end.day);
  return !cleanDate.isBefore(cleanStart) && !cleanDate.isAfter(cleanEnd);
}

String _methodLabel(String method) {
  return switch (method) {
    'cash' => 'Efectivo',
    'transfer' => 'Transferencia',
    'card' => 'Tarjeta',
    'platform_paid' => 'Pagado en plataforma',
    'employee_consumption' => 'Consumo empleado',
    _ => method,
  };
}

String _money(double value) => '\$${value.toStringAsFixed(2)}';

double _parse(String value) =>
    double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
