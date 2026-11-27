import 'package:flutter/material.dart';

import '../../../core/expenses/expense_policy.dart';
import '../../../core/reports/canonical_sales_summary.dart';
import '../../../models/purchase_models.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../widgets/charts/donut_chart.dart';
import '../../widgets/empty_error_state.dart';
import '../../widgets/kpi_tile.dart';
import '../../widgets/saas_card.dart';
import '../../widgets/status_pill.dart';
import 'finance_analytics.dart';
import 'finance_repository.dart';

class FinanceDashboardTab extends StatelessWidget {
  const FinanceDashboardTab({
    super.key,
    required this.bundle,
    required this.isMobile,
  });

  final FinanceDashboardBundle bundle;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final s = bundle.summary;
    final prev = bundle.previousSummary;
    final tokens = BackofficeTokens.of(context);
    final cols = isMobile ? 1 : (MediaQuery.sizeOf(context).width < 1100 ? 2 : 4);

    final salesDelta = PeriodDelta.compute(s.netSales, prev.netSales);
    final opDelta = PeriodDelta.compute(
      s.operatingResultFlow,
      prev.operatingResultFlow,
    );

    String fmtDelta(PeriodDelta d) {
      final sign = d.delta >= 0 ? '+' : '';
      final pct = d.deltaPercent == null
          ? ''
          : ' (${d.deltaPercent! >= 0 ? '+' : ''}${d.deltaPercent!.toStringAsFixed(1)}%)';
      return '$sign${BackofficeSalesAdapter.formatMoney(d.delta)}$pct vs periodo ant.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: isMobile ? 2.6 : 1.9,
          children: [
            KpiTile(
              label: 'Ventas netas',
              value: BackofficeSalesAdapter.formatMoney(s.netSales),
              subtitle: fmtDelta(salesDelta),
              icon: Icons.point_of_sale_rounded,
            ),
            KpiTile(
              label: 'Ingresos monetarios',
              value: BackofficeSalesAdapter.formatMoney(s.realCollected),
              subtitle:
                  'Efectivo ${BackofficeSalesAdapter.formatMoney(s.cashCollected)} · Tarj/Plat ${BackofficeSalesAdapter.formatMoney(s.cardCollected + s.platformCollected)}',
              icon: Icons.account_balance_wallet_outlined,
            ),
            KpiTile(
              label: 'Costo teórico (COGS)',
              value: s.cogsCoveredRevenue > 0
                  ? BackofficeSalesAdapter.formatMoney(s.estimatedCogs)
                  : 'No disponible',
              subtitle: s.hasCompleteCogs
                  ? 'Cobertura 100% recetas · Compras: ${BackofficeSalesAdapter.formatMoney(s.purchasesTotal)}'
                  : 'Compras periodo: ${BackofficeSalesAdapter.formatMoney(s.purchasesTotal)} (no es COGS)',
              icon: Icons.soup_kitchen_outlined,
            ),
            KpiTile(
              label: 'Resultado operativo (flujo)',
              value: BackofficeSalesAdapter.formatMoney(
                s.operatingResultFlow,
              ),
              subtitle: fmtDelta(opDelta),
              icon: Icons.trending_up_rounded,
            ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: isMobile ? 2 : (MediaQuery.sizeOf(context).width < 1100 ? 2 : 4),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: isMobile ? 1.85 : (MediaQuery.sizeOf(context).width < 1100 ? 2.6 : 2.15),
          children: [
            KpiTile(
              label: 'Ventas brutas',
              value: BackofficeSalesAdapter.formatMoney(s.grossSales),
              subtitle: '${s.ordersCount} órdenes activas',
            ),
            KpiTile(
              label: 'Descuentos y cortesías',
              value: BackofficeSalesAdapter.formatMoney(
                s.discounts + s.employeeFreeMeals,
              ),
              subtitle:
                  'Desc: ${BackofficeSalesAdapter.formatMoney(s.discounts)} · Empl: ${BackofficeSalesAdapter.formatMoney(s.employeeFreeMeals)}',
            ),
            KpiTile(
              label: 'Gastos operativos',
              value: BackofficeSalesAdapter.formatMoney(
                s.operatingExpensesPaid,
              ),
              subtitle:
                  'Nómina: ${BackofficeSalesAdapter.formatMoney(s.payrollExpenses)}',
            ),
            KpiTile(
              label: 'Utilidad bruta est.',
              value: s.hasCompleteCogs
                  ? BackofficeSalesAdapter.formatMoney(s.grossProfit)
                  : (s.hasPartialCogs
                        ? '${BackofficeSalesAdapter.formatMoney(s.coveredGrossProfit)} (Parcial)'
                        : 'No disponible'),
              subtitle: s.profitMarginPercent != null
                  ? 'Margen op.: ${s.profitMarginPercent!.toStringAsFixed(1)}%'
                  : 'Cobertura de costos: ${s.cogsCoveragePercent.toStringAsFixed(0)}%',
            ),
            KpiTile(
              label: 'Comisiones bancarias',
              value: BackofficeSalesAdapter.formatMoney(s.cardFeeAbsorbed),
              subtitle: 'Absorbidas en terminal',
            ),
            KpiTile(
              label: 'Propinas (personal)',
              value: BackofficeSalesAdapter.formatMoney(s.tipsTotal),
              subtitle: 'Separadas de ingresos propios',
            ),
            KpiTile(
              label: 'Flujo de efectivo op.',
              value: BackofficeSalesAdapter.formatMoney(s.operatingCashFlow),
              subtitle:
                  'CXP activa: ${BackofficeSalesAdapter.formatMoney(s.accountsPayableTotal)}',
            ),
            KpiTile(
              label: 'Aportaciones socios',
              value: BackofficeSalesAdapter.formatMoney(
                s.partnerContributionsTotal,
              ),
              subtitle: 'No se contabilizan como venta',
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoCols = constraints.maxWidth >= 860;
            final donut = SaasCard(
              title: 'Distribución de ingresos monetarios',
              subtitle: 'Separación estricta de métodos de cobro',
              child: PaymentDonutChart(
                centerLabel: 'Cobrado',
                totalAmount: s.realCollected,
                slices: [
                  DonutSlice(
                    label: 'Efectivo',
                    amount: s.cashCollected,
                    color: tokens.success,
                  ),
                  DonutSlice(
                    label: 'Tarjeta neta',
                    amount: s.cardCollected,
                    color: tokens.info,
                  ),
                  DonutSlice(
                    label: 'Plataformas',
                    amount: s.platformCollected,
                    color: tokens.brandAccent,
                  ),
                ],
              ),
            );
            final flowCard = SaasCard(
              title: 'Conciliación financiera del periodo',
              subtitle:
                  'Compras realizadas y aportaciones nunca se mezclan con ventas ni COGS.',
              child: Column(
                children: [
                  _ConciliationRow(
                    label: 'Ventas netas (devengadas)',
                    value: BackofficeSalesAdapter.formatMoney(s.netSales),
                  ),
                  _ConciliationRow(
                    label: 'Ingresos monetarios cobrados',
                    value: BackofficeSalesAdapter.formatMoney(
                      s.realCollected,
                    ),
                  ),
                  _ConciliationRow(
                    label: 'Compras registradas en periodo',
                    value: BackofficeSalesAdapter.formatMoney(
                      s.purchasesTotal,
                    ),
                  ),
                  _ConciliationRow(
                    label: 'Pagos a proveedores (de caja/ventas)',
                    value: BackofficeSalesAdapter.formatMoney(
                      s.supplierPaidFromSales,
                    ),
                  ),
                  _ConciliationRow(
                    label: 'Pagos a proveedores (por socios)',
                    value: BackofficeSalesAdapter.formatMoney(
                      s.supplierPaidByPartners,
                    ),
                  ),
                  _ConciliationRow(
                    label: 'Flujo neto con aportaciones',
                    value: BackofficeSalesAdapter.formatMoney(
                      s.cashFlowWithPartners,
                    ),
                    bold: true,
                  ),
                ],
              ),
            );
            if (!twoCols) {
              return Column(
                children: [donut, const SizedBox(height: 16), flowCard],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: donut),
                const SizedBox(width: 16),
                Expanded(child: flowCard),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ConciliationRow extends StatelessWidget {
  const _ConciliationRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: bold ? tokens.textPrimary : tokens.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class IncomeStatementTab extends StatelessWidget {
  const IncomeStatementTab({
    super.key,
    required this.bundle,
    required this.onExportCsv,
    required this.onOpenSaleDetail,
  });

  final FinanceDashboardBundle bundle;
  final VoidCallback onExportCsv;
  final ValueChanged<String> onOpenSaleDetail;

  @override
  Widget build(BuildContext context) {
    final s = bundle.summary;
    final prev = bundle.previousSummary;
    final tokens = BackofficeTokens.of(context);
    final hasCogs = s.cogsCoveredRevenue > 0.01;

    void showDrilldown(String title, List<Widget> children) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          builder: (ctx, ctrl) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    controller: ctrl,
                    children: children.isEmpty
                        ? [const Text('Sin operaciones registradas en el periodo.')]
                        : children,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaasCard(
          title: 'Estado de Resultados Administrativo',
          subtitle: hasCogs
              ? (s.hasCompleteCogs
                    ? 'Cálculo con costo teórico de recetas completo.'
                    : 'Costo de venta parcial: solo incluye productos con receta completa y costo de compra.')
              : 'Costo de venta no disponible (sin recetas teóricas o costos de insumos suficientes).',
          trailing: OutlinedButton.icon(
            onPressed: onExportCsv,
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Exportar CSV'),
          ),
          child: Column(
            children: [
              _StatementLine(
                label: 'Ventas brutas',
                current: s.grossSales,
                previous: prev.grossSales,
                onTap: () => showDrilldown(
                  'Órdenes del periodo (${bundle.orders.length})',
                  bundle.orders
                      .where((o) => !isCanonicalCancelledOrder(o))
                      .take(60)
                      .map(
                        (o) => ListTile(
                          title: Text(
                            '${BackofficeSalesAdapter.resolveFolioLabel(o)} · ${o.businessDate ?? ''}',
                          ),
                          subtitle: Text(o.branchName),
                          trailing: Text(
                            BackofficeSalesAdapter.formatMoney(o.total),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            onOpenSaleDetail(o.id);
                          },
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              _StatementLine(
                label: '(-) Descuentos y consumo de empleados',
                current: -(s.discounts + s.employeeFreeMeals),
                previous: -(prev.discounts + prev.employeeFreeMeals),
              ),
              _StatementLine(
                label: '(=) Ventas netas',
                current: s.netSales,
                previous: prev.netSales,
                emphasized: true,
              ),
              const Divider(height: 20),
              _StatementLine(
                label: '(-) Costo de venta teórico (COGS)',
                current: hasCogs ? -s.estimatedCogs : null,
                previous: null,
                unavailableText: 'No disponible (requiere recetas/compras)',
              ),
              _StatementLine(
                label: s.hasCompleteCogs
                    ? '(=) Utilidad bruta estimada'
                    : '(=) Utilidad bruta parcial (${s.cogsCoveragePercent.toStringAsFixed(0)}% cubierto)',
                current: hasCogs
                    ? (s.hasCompleteCogs ? s.grossProfit : s.coveredGrossProfit)
                    : null,
                previous: null,
                emphasized: true,
                unavailableText: 'No disponible',
              ),
              const Divider(height: 20),
              _StatementLine(
                label: '(-) Gastos operativos aprobados',
                current: -s.operatingExpensesPaid,
                previous: -prev.operatingExpensesPaid,
                onTap: () => showDrilldown(
                  'Gastos operativos del periodo',
                  bundle.withdrawals
                      .where(isFinanceOperatingExpense)
                      .map(
                        (w) => ListTile(
                          title: Text(w.reason),
                          subtitle: Text(
                            '${w.businessDate} · ${w.branchName} · ${w.isHistorical ? 'Histórico' : 'Caja'}',
                          ),
                          trailing: Text(
                            BackofficeSalesAdapter.formatMoney(w.amount),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              _StatementLine(
                label: s.hasCompleteCogs
                    ? '(=) Utilidad operativa contable (estimada)'
                    : '(=) Utilidad operativa contable (requiere COGS 100%)',
                current: s.hasCompleteCogs ? s.operatingProfitAccounting : null,
                previous: null,
                emphasized: true,
                accentColor:
                    s.hasCompleteCogs && s.operatingProfitAccounting >= 0
                        ? tokens.success
                        : tokens.danger,
                unavailableText: 'Parcial · ver referencia de flujo',
              ),
              const Divider(height: 20),
              _StatementLine(
                label: 'Referencia de flujo: Cobrado - Gastos - Compras',
                current: s.operatingResultFlow,
                previous: prev.operatingResultFlow,
                emphasized: true,
                onTap: () => showDrilldown(
                  'Compras registradas (${bundle.purchases.length})',
                  bundle.purchases
                      .where((p) => p.status.toLowerCase() != 'cancelled')
                      .map(
                        (p) => ListTile(
                          title: Text('${p.supplierName} · ${p.folio}'),
                          subtitle: Text(p.businessDate ?? ''),
                          trailing: Text(
                            BackofficeSalesAdapter.formatMoney(p.total),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatementLine extends StatelessWidget {
  const _StatementLine({
    required this.label,
    required this.current,
    required this.previous,
    this.emphasized = false,
    this.accentColor,
    this.unavailableText = 'N/D',
    this.onTap,
  });

  final String label;
  final double? current;
  final double? previous;
  final bool emphasized;
  final Color? accentColor;
  final String unavailableText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final valueText = current == null
        ? unavailableText
        : BackofficeSalesAdapter.formatMoney(current!);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: emphasized ? 14 : 13,
                        fontWeight:
                            emphasized ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 14,
                      color: tokens.brandAccent,
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  valueText,
                  style: TextStyle(
                    fontSize: emphasized ? 14.5 : 13.5,
                    fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
                    color: accentColor,
                  ),
                ),
                if (previous != null)
                  Text(
                    'Ant: ${BackofficeSalesAdapter.formatMoney(previous!)}',
                    style: TextStyle(fontSize: 11, color: tokens.textMuted),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ExpensesAndPoliciesTab extends StatelessWidget {
  const ExpensesAndPoliciesTab({
    super.key,
    required this.bundle,
    required this.branchNames,
    required this.canManagePolicies,
    required this.onExportCsv,
    required this.onTogglePoliciesEnabled,
    required this.onChangePolicyMode,
    required this.onSavePolicy,
    required this.onTogglePolicyActive,
  });

  final FinanceDashboardBundle bundle;
  final Map<String, String> branchNames;
  final bool canManagePolicies;
  final VoidCallback onExportCsv;
  final ValueChanged<bool> onTogglePoliciesEnabled;
  final ValueChanged<ExpensePolicyMode> onChangePolicyMode;
  final ValueChanged<ExpensePolicy?> onSavePolicy;
  final void Function(ExpensePolicy policy, bool active) onTogglePolicyActive;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final s = bundle.summary;
    final operating = bundle.withdrawals
        .where(isFinanceOperatingExpense)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaasCard(
          title: 'Gastos operativos por concepto',
          subtitle:
              'Total pagado: ${BackofficeSalesAdapter.formatMoney(s.operatingExpensesPaid)} · En caja: ${BackofficeSalesAdapter.formatMoney(s.cashDrawerExpenses)} · Históricos: ${BackofficeSalesAdapter.formatMoney(s.historicalExpenses)}',
          trailing: OutlinedButton.icon(
            onPressed: onExportCsv,
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Exportar CSV'),
          ),
          child: s.expensesByConcept.isEmpty
              ? const Text('Sin gastos operativos aprobados en este periodo.')
              : Column(
                  children: s.expensesByConcept
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${e.concept} (${e.count})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                BackofficeSalesAdapter.formatMoney(
                                  e.totalAmount,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
        const SizedBox(height: 16),
        SaasCard(
          title: 'Historial de gastos (${operating.length})',
          subtitle: 'Distingue movimientos de caja vs registros históricos.',
          padding: EdgeInsets.zero,
          child: operating.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No hay movimientos en el rango seleccionado.'),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: operating.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: tokens.border),
                  itemBuilder: (context, i) {
                    final w = operating[i];
                    return ListTile(
                      title: Text(
                        w.reason,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${w.businessDate} · ${branchNames[w.branchId] ?? w.branchName} · Solicitó: ${w.requestedByEmployeeName}',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textSecondary,
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            BackofficeSalesAdapter.formatMoney(w.amount),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          StatusPill(
                            label: w.isHistorical ? 'Histórico' : 'Caja',
                            tone: w.isHistorical
                                ? StatusTone.info
                                : StatusTone.neutral,
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 16),
        SaasCard(
          title: 'Políticas de gastos',
          subtitle:
              'Reglas de auto-aprobación, topes por periodo y comprobantes.',
          trailing: canManagePolicies
              ? FilledButton.icon(
                  onPressed: () => onSavePolicy(null),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Nueva política'),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Habilitar evaluación de políticas'),
                value: bundle.expensePolicySettings.expensePoliciesEnabled,
                onChanged: canManagePolicies ? onTogglePoliciesEnabled : null,
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Modo: '),
                  for (final m in ExpensePolicyMode.values)
                    ChoiceChip(
                      label: Text(m.name.toUpperCase()),
                      selected:
                          bundle.expensePolicySettings.expensePolicyMode == m,
                      onSelected: canManagePolicies
                          ? (_) => onChangePolicyMode(m)
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (bundle.expensePolicies.isEmpty)
                const Text('No hay políticas registradas.')
              else
                ...bundle.expensePolicies.map(
                  (p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: canManagePolicies ? () => onSavePolicy(p) : null,
                    title: Text(
                      '${p.name} (${p.code})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Máx/tx: ${BackofficeSalesAdapter.formatMoney(p.maxAmountPerTransaction)} · Máx/per: ${BackofficeSalesAdapter.formatMoney(p.maxAmountPerPeriod)} · ${p.frequencyType.name}',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textSecondary,
                      ),
                    ),
                    trailing: Switch(
                      value: p.active,
                      onChanged: canManagePolicies
                          ? (v) => onTogglePolicyActive(p, v)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class ProductProfitabilityTab extends StatefulWidget {
  const ProductProfitabilityTab({
    super.key,
    required this.rows,
    required this.onExportCsv,
  });

  final List<ProductProfitabilityRow> rows;
  final VoidCallback onExportCsv;

  @override
  State<ProductProfitabilityTab> createState() =>
      _ProductProfitabilityTabState();
}

class _ProductProfitabilityTabState extends State<ProductProfitabilityTab> {
  bool _onlyMissing = false;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final filtered = _onlyMissing
        ? widget.rows.where((r) => !r.hasCost).toList(growable: false)
        : widget.rows;

    if (widget.rows.isEmpty) {
      return const SaasEmptyState(
        icon: Icons.pie_chart_outline_rounded,
        title: 'Sin ventas de productos en el periodo',
        message: 'No hay partidas vendidas para evaluar rentabilidad.',
      );
    }

    return SaasCard(
      title: 'Rentabilidad por producto',
      subtitle:
          'Los productos sin receta completa o sin costo de compra se marcan como "Costo no disponible", nunca en cero.',
      trailing: Wrap(
        spacing: 8,
        children: [
          FilterChip(
            label: const Text('Solo sin costo'),
            selected: _onlyMissing,
            onSelected: (v) => setState(() => _onlyMissing = v),
          ),
          OutlinedButton.icon(
            onPressed: widget.onExportCsv,
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('CSV'),
          ),
        ],
      ),
      padding: EdgeInsets.zero,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
        itemBuilder: (context, i) {
          final r = filtered[i];
          return ListTile(
            title: Text(
              r.productName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${r.unitsSold.toStringAsFixed(0)} uds · Prom: ${BackofficeSalesAdapter.formatMoney(r.avgRealPrice)} · Part. venta: ${r.salesSharePercent.toStringAsFixed(1)}% · ${r.costNote}',
              style: TextStyle(fontSize: 12, color: tokens.textSecondary),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  BackofficeSalesAdapter.formatMoney(r.netRevenue),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (r.hasCost && r.estimatedGrossProfit != null)
                  Text(
                    'Util: ${BackofficeSalesAdapter.formatMoney(r.estimatedGrossProfit!)} (${r.marginPercent?.toStringAsFixed(1) ?? '0'}%)',
                    style: TextStyle(fontSize: 11.5, color: tokens.success),
                  )
                else
                  StatusPill(
                    label: 'Costo N/D',
                    tone: StatusTone.warning,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class BreakEvenAndEfficiencyTab extends StatefulWidget {
  const BreakEvenAndEfficiencyTab({
    super.key,
    required this.bundle,
    required this.elapsedDays,
    required this.totalDays,
    required this.canManageBudgets,
    required this.onSaveTarget,
    required this.onSaveBudget,
  });

  final FinanceDashboardBundle bundle;
  final int elapsedDays;
  final int totalDays;
  final bool canManageBudgets;
  final void Function(String key, double targetPct) onSaveTarget;
  final void Function(String budgetType, double amount) onSaveBudget;

  @override
  State<BreakEvenAndEfficiencyTab> createState() =>
      _BreakEvenAndEfficiencyTabState();
}

class _BreakEvenAndEfficiencyTabState extends State<BreakEvenAndEfficiencyTab> {
  BreakEvenHorizon _horizon = BreakEvenHorizon.monthly;
  late TextEditingController _fixedCtrl;
  late TextEditingController _varRatioCtrl;

  @override
  void initState() {
    super.initState();
    final s = widget.bundle.summary;
    final defaultFixed = widget.bundle.expenseBudgetAmount ??
        (s.operatingExpensesPaid > 0 ? s.operatingExpensesPaid : 15000.0);
    final defaultVarPct = s.netSales > 0 && s.estimatedCogs > 0
        ? ((s.estimatedCogs / s.netSales) * 100.0).clamp(5.0, 90.0)
        : 35.0;
    _fixedCtrl = TextEditingController(text: defaultFixed.toStringAsFixed(0));
    _varRatioCtrl = TextEditingController(
      text: defaultVarPct.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _fixedCtrl.dispose();
    _varRatioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final fixed = double.tryParse(_fixedCtrl.text.trim()) ?? 0.0;
    final varRatio =
        ((double.tryParse(_varRatioCtrl.text.trim()) ?? 35.0) / 100.0);
    final be = BreakEvenAnalysis.compute(
      horizon: _horizon,
      fixedCosts: fixed,
      variableCostRatio: varRatio,
      accumulatedSales: widget.bundle.summary.netSales,
      elapsedDays: widget.elapsedDays,
      totalDaysInPeriod: widget.totalDays,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaasCard(
          title: 'Punto de equilibrio configurable',
          subtitle:
              'Supuestos explícitos: Venta equilibrio = Gastos fijos / (1 - % Costo variable).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final h in BreakEvenHorizon.values)
                    ChoiceChip(
                      label: Text(h.label),
                      selected: _horizon == h,
                      onSelected: (_) => setState(() => _horizon = h),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _fixedCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Gastos fijos del periodo (\$)',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _varRatioCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Costo variable (%)',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _MiniStat(
                    label: 'Margen de contribución',
                    value:
                        '${(be.contributionMarginRatio * 100).toStringAsFixed(1)}%',
                  ),
                  _MiniStat(
                    label: 'Equilibrio (${_horizon.label})',
                    value: be.breakEvenSales == null
                        ? 'N/D'
                        : BackofficeSalesAdapter.formatMoney(
                            be.breakEvenSales!,
                          ),
                  ),
                  _MiniStat(
                    label: 'Venta acumulada',
                    value: BackofficeSalesAdapter.formatMoney(
                      be.accumulatedSales,
                    ),
                  ),
                  _MiniStat(
                    label: be.isReached ? 'Superávit' : 'Faltante al equilibrio',
                    value: be.gapToBreakEven == null
                        ? 'N/D'
                        : BackofficeSalesAdapter.formatMoney(
                            be.gapToBreakEven!.abs(),
                          ),
                    color: be.isReached ? tokens.success : tokens.warning,
                  ),
                  _MiniStat(
                    label: 'Proyección de cierre',
                    value: BackofficeSalesAdapter.formatMoney(
                      be.projectedEndSales,
                    ),
                  ),
                  _MiniStat(
                    label: 'Venta diaria necesaria',
                    value: be.requiredDailySalesRemaining == null
                        ? 'N/D'
                        : BackofficeSalesAdapter.formatMoney(
                            be.requiredDailySalesRemaining!,
                          ),
                  ),
                ],
              ),
              if (widget.canManageBudgets) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        widget.onSaveBudget('expense_budget', fixed),
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Guardar presupuesto fijo en DEV'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SaasCard(
          title: 'Comparativos de eficiencia y metas persistentes (DEV)',
          subtitle:
              'Diferencia compras de abastecimiento vs costo de venta teórico.',
          padding: EdgeInsets.zero,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.bundle.efficiencyMetrics.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: tokens.border),
            itemBuilder: (context, i) {
              final m = widget.bundle.efficiencyMetrics[i];
              return ListTile(
                title: Text(
                  m.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${m.note} · Meta: ${m.targetPercent.toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                ),
                trailing: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusPill(
                      label: m.actualPercent == null
                          ? 'N/D'
                          : '${m.actualPercent!.toStringAsFixed(1)}%',
                      tone: m.isOverTarget
                          ? StatusTone.danger
                          : StatusTone.success,
                    ),
                    if (widget.canManageBudgets)
                      IconButton(
                        tooltip: 'Editar meta',
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        onPressed: () async {
                          final ctrl = TextEditingController(
                            text: m.targetPercent.toStringAsFixed(1),
                          );
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text('Meta: ${m.label}'),
                              content: TextField(
                                controller: ctrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Meta (% sobre venta)',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(false),
                                  child: const Text('Cancelar'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(true),
                                  child: const Text('Guardar'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            final val = double.tryParse(ctrl.text.trim());
                            if (val != null && val > 0) {
                              widget.onSaveTarget(m.key, val);
                            }
                          }
                        },
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: tokens.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class PartnersFinanceTab extends StatelessWidget {
  const PartnersFinanceTab({
    super.key,
    required this.bundle,
    required this.canManagePartners,
    required this.onCreateOrEditPartner,
    required this.onRegisterContribution,
  });

  final FinanceDashboardBundle bundle;
  final bool canManagePartners;
  final ValueChanged<Partner?> onCreateOrEditPartner;
  final VoidCallback onRegisterContribution;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final ps = bundle.partnerSummary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaasCard(
          title: 'Finanzas de socios y propuesta de utilidad distribuible',
          subtitle:
              'Cálculo informativo basado en flujo operativo (${BackofficeSalesAdapter.formatMoney(ps.distributableBase)}). No ejecuta distribuciones automáticas.',
          trailing: canManagePartners
              ? Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onRegisterContribution,
                      icon: const Icon(Icons.add_card_rounded, size: 16),
                      label: const Text('Aportación'),
                    ),
                    FilledButton.icon(
                      onPressed: () => onCreateOrEditPartner(null),
                      icon: const Icon(Icons.person_add_alt_1, size: 16),
                      label: const Text('Nuevo socio'),
                    ),
                  ],
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Total aportado en el periodo (deduplicado): ${BackofficeSalesAdapter.formatMoney(ps.totalContributed)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (ps.proposals.isEmpty)
                const Text('No hay socios registrados.')
              else
                ...ps.proposals.map(
                  (item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: canManagePartners
                        ? () => onCreateOrEditPartner(item.partner)
                        : null,
                    title: Text(
                      '${item.partner.name} · ${item.partner.ownershipPercent.toStringAsFixed(1)}%',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Aportación periodo: ${BackofficeSalesAdapter.formatMoney(item.contributedInPeriod)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textSecondary,
                      ),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          BackofficeSalesAdapter.formatMoney(
                            item.proposedShareAmount,
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: tokens.success,
                          ),
                        ),
                        Text(
                          'Propuesta',
                          style: TextStyle(
                            fontSize: 11,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
