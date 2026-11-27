import 'package:flutter/material.dart';

import '../../../models/purchase_models.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../features/dashboard/dashboard_repository.dart';
import '../../widgets/charts/donut_chart.dart';
import '../../widgets/charts/revenue_area_chart.dart';
import '../../widgets/empty_error_state.dart';
import '../../widgets/saas_card.dart';
import '../../widgets/status_pill.dart';
import 'purchases_analytics.dart';
import 'purchases_repository.dart';

enum TrendGranularity { daily, weekly, monthly }

class PurchasesDashboardTab extends StatefulWidget {
  const PurchasesDashboardTab({
    super.key,
    required this.data,
    required this.isMobile,
    required this.onOpenPurchase,
  });

  final PurchasesDashboardData data;
  final bool isMobile;
  final ValueChanged<SupplierPurchase> onOpenPurchase;

  @override
  State<PurchasesDashboardTab> createState() => _PurchasesDashboardTabState();
}

class _PurchasesDashboardTabState extends State<PurchasesDashboardTab> {
  TrendGranularity _granularity = TrendGranularity.daily;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final m = widget.data.metrics;

    final trendPoints = switch (_granularity) {
      TrendGranularity.daily => m.dailyTrend,
      TrendGranularity.weekly => m.weeklyTrend,
      TrendGranularity.monthly => m.monthlyTrend,
    };

    final chartSeries = trendPoints
        .map(
          (p) => DailyRevenuePoint(
            businessDate: p.label,
            netSales: p.amount,
            ordersCount: p.count,
          ),
        )
        .toList(growable: false);

    final palette = [
      tokens.brandAccent,
      tokens.info,
      tokens.success,
      tokens.warning,
      tokens.brandAmber,
    ];
    final categoryEntries = m.byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final categorySlices = [
      for (var i = 0; i < categoryEntries.length; i++)
        DonutSlice(
          label: categoryEntries[i].key,
          amount: categoryEntries[i].value,
          color: palette[i % palette.length],
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _KpiWrap(
          isMobile: widget.isMobile,
          items: [
            (
              'Compras del periodo',
              BackofficeSalesAdapter.formatMoney(m.totalAmount),
              '${m.variationPct >= 0 ? '+' : ''}${m.variationPct.toStringAsFixed(1)}% vs periodo ant. (${BackofficeSalesAdapter.formatMoney(m.previousTotalAmount)})',
              tokens.brandAccent,
            ),
            (
              'Compras pagadas',
              BackofficeSalesAdapter.formatMoney(m.paidAmount),
              '${m.purchasesCount} operación(es) en periodo',
              tokens.success,
            ),
            (
              'Pendiente de pago',
              BackofficeSalesAdapter.formatMoney(m.pendingAmount),
              'Saldo de compras del periodo',
              m.pendingAmount > 0 ? tokens.warning : tokens.success,
            ),
            (
              'Alertas de precio',
              '${m.priceAlerts.length}',
              'Insumos con alza >= 8%',
              m.priceAlerts.isNotEmpty ? tokens.danger : tokens.success,
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoCols = constraints.maxWidth >= 960;
            final trendCard = SaasCard(
              title: 'Evolución de compras',
              subtitle: 'Importe comprado por periodo',
              trailing: SegmentedButton<TrendGranularity>(
                segments: const [
                  ButtonSegment(
                    value: TrendGranularity.daily,
                    label: Text('Diario'),
                  ),
                  ButtonSegment(
                    value: TrendGranularity.weekly,
                    label: Text('Semanal'),
                  ),
                  ButtonSegment(
                    value: TrendGranularity.monthly,
                    label: Text('Mensual'),
                  ),
                ],
                selected: {_granularity},
                onSelectionChanged: (s) =>
                    setState(() => _granularity = s.first),
              ),
              child: SizedBox(
                height: 240,
                child: chartSeries.isEmpty
                    ? Center(
                        child: Text(
                          'Sin compras en el periodo.',
                          style: TextStyle(color: tokens.textSecondary),
                        ),
                      )
                    : RevenueAreaChart(series: chartSeries),
              ),
            );

            final catCard = SaasCard(
              title: 'Compras por categoría',
              subtitle: 'Distribución por tipo de insumo',
              child: PaymentDonutChart(
                slices: categorySlices,
                totalAmount: m.totalAmount,
                centerLabel: 'Total comprado',
              ),
            );

            if (!twoCols) {
              return Column(
                children: [
                  trendCard,
                  const SizedBox(height: 16),
                  catCard,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: trendCard),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: catCard),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoCols = constraints.maxWidth >= 900;
            final topSup = SaasCard(
              title: 'Principales proveedores',
              subtitle: 'Participación sobre el total del periodo',
              padding: EdgeInsets.zero,
              child: m.supplierReports.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Sin proveedores en el periodo.'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: m.supplierReports.take(5).length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: tokens.border),
                      itemBuilder: (context, i) {
                        final s = m.supplierReports[i];
                        return ListTile(
                          title: Text(
                            s.supplierName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          subtitle: Text(
                            '${s.operationsCount} compra(s) · ${s.sharePct.toStringAsFixed(1)}% del total',
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.textSecondary,
                            ),
                          ),
                          trailing: Text(
                            BackofficeSalesAdapter.formatMoney(s.totalAmount),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        );
                      },
                    ),
            );

            final topItems = SaasCard(
              title: 'Principales insumos comprados',
              subtitle: 'Costo promedio ponderado por unidad',
              padding: EdgeInsets.zero,
              child: m.itemReports.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Sin insumos registrados en el periodo.'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: m.itemReports.take(5).length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: tokens.border),
                      itemBuilder: (context, i) {
                        final r = m.itemReports[i];
                        return ListTile(
                          title: Text(
                            '${r.itemName} (${r.unit})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          subtitle: Text(
                            '${r.totalQuantity.toStringAsFixed(2)} ${r.unit} · Prom: ${BackofficeSalesAdapter.formatMoney(r.weightedAvgCost)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.textSecondary,
                            ),
                          ),
                          trailing: Text(
                            BackofficeSalesAdapter.formatMoney(r.totalAmount),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        );
                      },
                    ),
            );

            if (!twoCols) {
              return Column(
                children: [
                  topSup,
                  const SizedBox(height: 16),
                  topItems,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: topSup),
                const SizedBox(width: 16),
                Expanded(child: topItems),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoCols = constraints.maxWidth >= 900;
            final branchCard = SaasCard(
              title: 'Compras por sucursal',
              subtitle: 'Distribución operativa',
              child: m.byBranch.isEmpty
                  ? const Text('Sin datos por sucursal.')
                  : Column(
                      children: m.byBranch.entries
                          .map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      e.key,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    BackofficeSalesAdapter.formatMoney(e.value),
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
            );

            final alertsCard = SaasCard(
              title: 'Alertas de incrementos de precio',
              subtitle: 'Variación reciente >= 8% frente al registro anterior',
              child: m.priceAlerts.isEmpty
                  ? Text(
                      'Sin incrementos abruptos detectados en este periodo.',
                      style: TextStyle(color: tokens.textSecondary),
                    )
                  : Column(
                      children: m.priceAlerts
                          .take(5)
                          .map(
                            (a) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${a.itemName} (${a.unit})',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          '${a.supplierName} · ${BackofficeSalesAdapter.formatMoney(a.previousUnitCost)} → ${BackofficeSalesAdapter.formatMoney(a.latestUnitCost)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: tokens.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  StatusPill(
                                    label: '+${a.increasePct.toStringAsFixed(1)}%',
                                    tone: StatusTone.danger,
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
            );

            if (!twoCols) {
              return Column(
                children: [
                  branchCard,
                  const SizedBox(height: 16),
                  alertsCard,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: branchCard),
                const SizedBox(width: 16),
                Expanded(child: alertsCard),
              ],
            );
          },
        ),
      ],
    );
  }
}

class PurchasesHistoryTab extends StatelessWidget {
  const PurchasesHistoryTab({
    super.key,
    required this.purchases,
    required this.branchNames,
    required this.isMobile,
    required this.searchQuery,
    required this.statusFilter,
    required this.canCreate,
    required this.canExport,
    required this.exporting,
    required this.exportProgress,
    required this.hasPrevPage,
    required this.hasNextPage,
    required this.pageLabel,
    required this.onStatusChanged,
    required this.onCreatePurchase,
    required this.onExport,
    required this.onCancelExport,
    required this.onPrevPage,
    required this.onNextPage,
    required this.onSelectPurchase,
  });

  final List<SupplierPurchase> purchases;
  final Map<String, String> branchNames;
  final bool isMobile;
  final String searchQuery;
  final String? statusFilter;
  final bool canCreate;
  final bool canExport;
  final bool exporting;
  final int exportProgress;
  final bool hasPrevPage;
  final bool hasNextPage;
  final String pageLabel;
  final ValueChanged<String?> onStatusChanged;
  final VoidCallback onCreatePurchase;
  final VoidCallback onExport;
  final VoidCallback onCancelExport;
  final VoidCallback onPrevPage;
  final VoidCallback onNextPage;
  final ValueChanged<SupplierPurchase> onSelectPurchase;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final q = searchQuery.trim().toLowerCase();
    final filtered = q.isEmpty
        ? purchases
        : purchases
              .where(
                (p) =>
                    p.folio.toLowerCase().contains(q) ||
                    p.supplierName.toLowerCase().contains(q) ||
                    p.notes.toLowerCase().contains(q),
              )
              .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('Todas'),
              selected: statusFilter == null,
              onSelected: (_) => onStatusChanged(null),
            ),
            ChoiceChip(
              label: const Text('Pendientes'),
              selected: statusFilter == 'pending',
              onSelected: (_) => onStatusChanged('pending'),
            ),
            ChoiceChip(
              label: const Text('Parciales'),
              selected: statusFilter == 'partial',
              onSelected: (_) => onStatusChanged('partial'),
            ),
            ChoiceChip(
              label: const Text('Pagadas'),
              selected: statusFilter == 'paid',
              onSelected: (_) => onStatusChanged('paid'),
            ),
            if (canCreate)
              FilledButton.icon(
                onPressed: onCreatePurchase,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Registrar compra'),
              ),
            if (canExport) ...[
              OutlinedButton.icon(
                onPressed: exporting ? null : onExport,
                icon: const Icon(Icons.download_outlined, size: 16),
                label: Text(
                  exporting
                      ? 'Exportando ($exportProgress)...'
                      : 'Exportar CSV',
                ),
              ),
              if (exporting)
                TextButton(
                  onPressed: onCancelExport,
                  child: const Text('Cancelar'),
                ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          const SaasEmptyState(
            icon: Icons.shopping_bag_outlined,
            title: 'Sin compras registradas',
            message: 'No hay compras que coincidan con los filtros actuales.',
          )
        else
          SaasCard(
            title: 'Historial de compras',
            subtitle: 'Toca un documento para ver partidas, pagos y detalle.',
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (isMobile)
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: tokens.border),
                    itemBuilder: (context, i) {
                      final p = filtered[i];
                      return InkWell(
                        onTap: () => onSelectPurchase(p),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${p.folio} · ${p.supplierName}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                  purchaseStatusPill(p.status),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${branchNames[p.branchId] ?? p.branchName} · ${p.businessDate ?? ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: tokens.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Total: ${BackofficeSalesAdapter.formatMoney(p.total)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (p.hasBalance)
                                    Text(
                                      'Saldo: ${BackofficeSalesAdapter.formatMoney(p.balance)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: tokens.warning,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      showCheckboxColumn: false,
                      columns: const [
                        DataColumn(label: Text('Folio')),
                        DataColumn(label: Text('Fecha')),
                        DataColumn(label: Text('Proveedor')),
                        DataColumn(label: Text('Sucursal')),
                        DataColumn(label: Text('Documento')),
                        DataColumn(label: Text('Estado')),
                        DataColumn(label: Text('Total'), numeric: true),
                        DataColumn(label: Text('Pagado'), numeric: true),
                        DataColumn(label: Text('Saldo'), numeric: true),
                      ],
                      rows: filtered
                          .map(
                            (p) => DataRow(
                              onSelectChanged: (_) => onSelectPurchase(p),
                              cells: [
                                DataCell(
                                  Text(
                                    p.folio,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                DataCell(Text(p.businessDate ?? '')),
                                DataCell(Text(p.supplierName)),
                                DataCell(
                                  Text(branchNames[p.branchId] ?? p.branchName),
                                ),
                                DataCell(Text(documentTypeLabel(p.documentType))),
                                DataCell(purchaseStatusPill(p.status)),
                                DataCell(
                                  Text(
                                    BackofficeSalesAdapter.formatMoney(p.total),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    BackofficeSalesAdapter.formatMoney(
                                      p.paidTotal,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    BackofficeSalesAdapter.formatMoney(
                                      p.balance,
                                    ),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: p.hasBalance
                                          ? tokens.warning
                                          : tokens.success,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Text(
                        pageLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: hasPrevPage ? onPrevPage : null,
                        child: const Text('Anterior'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: hasNextPage ? onNextPage : null,
                        child: const Text('Siguiente'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class SupplierReportTab extends StatelessWidget {
  const SupplierReportTab({
    super.key,
    required this.reports,
    required this.isMobile,
    required this.onOpenPurchase,
    required this.onExport,
  });

  final List<SupplierReportSummary> reports;
  final bool isMobile;
  final ValueChanged<SupplierPurchase> onOpenPurchase;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    if (reports.isEmpty) {
      return const SaasEmptyState(
        icon: Icons.storefront_outlined,
        title: 'Sin compras por proveedor',
        message: 'No hay operaciones en el periodo seleccionado.',
      );
    }

    return SaasCard(
      title: 'Reporte de compras por proveedor',
      subtitle: 'Participación, comparativo entre periodos y documentos origen.',
      trailing: OutlinedButton.icon(
        onPressed: onExport,
        icon: const Icon(Icons.download_outlined, size: 16),
        label: const Text('Exportar CSV'),
      ),
      padding: EdgeInsets.zero,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: reports.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
        itemBuilder: (context, i) {
          final r = reports[i];
          return ExpansionTile(
            title: Text(
              r.supplierName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            subtitle: Text(
              '${r.operationsCount} compra(s) · ${r.sharePct.toStringAsFixed(1)}% participación · Var: ${r.variationPct >= 0 ? '+' : ''}${r.variationPct.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 12, color: tokens.textSecondary),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  BackofficeSalesAdapter.formatMoney(r.totalAmount),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (r.pendingBalance > 0)
                  Text(
                    'Saldo: ${BackofficeSalesAdapter.formatMoney(r.pendingBalance)}',
                    style: TextStyle(fontSize: 11.5, color: tokens.warning),
                  ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.suppliedItems.isNotEmpty) ...[
                      Text(
                        'Insumos suministrados: ${r.suppliedItems.join(', ')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: r.purchases
                          .take(8)
                          .map(
                            (p) => ActionChip(
                              label: Text(
                                '${p.folio} · ${BackofficeSalesAdapter.formatMoney(p.total)}',
                              ),
                              onPressed: () => onOpenPurchase(p),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ItemReportTab extends StatelessWidget {
  const ItemReportTab({
    super.key,
    required this.reports,
    required this.isMobile,
    required this.onExport,
  });

  final List<ItemPurchaseReportRow> reports;
  final bool isMobile;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    if (reports.isEmpty) {
      return const SaasEmptyState(
        icon: Icons.category_outlined,
        title: 'Sin insumos comprados',
        message: 'No hay partidas de compra en el periodo seleccionado.',
      );
    }

    return SaasCard(
      title: 'Reporte de compras por insumo',
      subtitle:
          'Agrupado por insumo y unidad de medida (sin mezclar unidades incompatibles).',
      trailing: OutlinedButton.icon(
        onPressed: onExport,
        icon: const Icon(Icons.download_outlined, size: 16),
        label: const Text('Exportar CSV'),
      ),
      padding: EdgeInsets.zero,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: reports.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
        itemBuilder: (context, i) {
          final r = reports[i];
          return ExpansionTile(
            title: Text(
              '${r.itemName} (${r.unit})',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            subtitle: Text(
              '${r.category} · Cant: ${r.totalQuantity.toStringAsFixed(2)} ${r.unit} · Prom. pond: ${BackofficeSalesAdapter.formatMoney(r.weightedAvgCost)}',
              style: TextStyle(fontSize: 12, color: tokens.textSecondary),
            ),
            trailing: Text(
              BackofficeSalesAdapter.formatMoney(r.totalAmount),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: [
                        Text(
                          'Último: ${BackofficeSalesAdapter.formatMoney(r.lastUnitCost)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'Mín: ${BackofficeSalesAdapter.formatMoney(r.minUnitCost)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'Máx: ${BackofficeSalesAdapter.formatMoney(r.maxUnitCost)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'Var. periodo: ${r.variationPct >= 0 ? '+' : ''}${r.variationPct.toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    if (r.supplierComparison.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Comparativo entre proveedores:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: tokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...r.supplierComparison.map(
                        (s) => Text(
                          '• ${s.supplierName}: ${s.totalQty.toStringAsFixed(2)} ${r.unit} · Prom ${BackofficeSalesAdapter.formatMoney(s.weightedAvgCost)} (Último ${BackofficeSalesAdapter.formatMoney(s.lastUnitCost)})',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SuppliersCatalogTab extends StatelessWidget {
  const SuppliersCatalogTab({
    super.key,
    required this.suppliers,
    required this.balances,
    required this.canManage,
    required this.isMobile,
    required this.onCreateOrEdit,
  });

  final List<Supplier> suppliers;
  final Map<String, double> balances;
  final bool canManage;
  final bool isMobile;
  final ValueChanged<Supplier?> onCreateOrEdit;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return SaasCard(
      title: 'Catálogo de proveedores',
      subtitle: '${suppliers.length} proveedor(es) registrado(s)',
      trailing: canManage
          ? FilledButton.icon(
              onPressed: () => onCreateOrEdit(null),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Nuevo proveedor'),
            )
          : null,
      padding: suppliers.isEmpty ? const EdgeInsets.all(20) : EdgeInsets.zero,
      child: suppliers.isEmpty
          ? const Text('No hay proveedores registrados.')
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: suppliers.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: tokens.border),
              itemBuilder: (context, i) {
                final s = suppliers[i];
                final bal = balances[s.id] ?? 0.0;
                return ListTile(
                  onTap: canManage ? () => onCreateOrEdit(s) : null,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.commercialName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      StatusPill(
                        label: s.active ? 'Activo' : 'Inactivo',
                        tone: s.active
                            ? StatusTone.success
                            : StatusTone.neutral,
                      ),
                    ],
                  ),
                  subtitle: Text(
                    'Crédito: ${s.creditDays} días · Día pago: ${s.paymentWeekdayName}${s.phone.isNotEmpty ? ' · Tel: ${s.phone}' : ''}',
                    style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                  ),
                  trailing: bal > 0
                      ? Text(
                          BackofficeSalesAdapter.formatMoney(bal),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: tokens.warning,
                          ),
                        )
                      : null,
                );
              },
            ),
    );
  }
}

class AccountsPayableTab extends StatelessWidget {
  const AccountsPayableTab({
    super.key,
    required this.summary,
    required this.payments,
    required this.branchNames,
    required this.canPay,
    required this.canCancelPayment,
    required this.isMobile,
    required this.onPayPurchase,
    required this.onCancelPayment,
    required this.onSelectPurchase,
    required this.onExport,
  });

  final AccountsPayableSummary summary;
  final List<SupplierPayment> payments;
  final Map<String, String> branchNames;
  final bool canPay;
  final bool canCancelPayment;
  final bool isMobile;
  final ValueChanged<SupplierPurchase> onPayPurchase;
  final ValueChanged<SupplierPayment> onCancelPayment;
  final ValueChanged<SupplierPurchase> onSelectPurchase;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _KpiWrap(
          isMobile: isMobile,
          items: [
            (
              'Total por pagar',
              BackofficeSalesAdapter.formatMoney(summary.totalPending),
              '${summary.openPurchases.length} documento(s) con saldo',
              tokens.brandAccent,
            ),
            (
              'Cuentas vencidas',
              BackofficeSalesAdapter.formatMoney(summary.overdueAmount),
              'Requieren atención prioritaria',
              summary.overdueAmount > 0 ? tokens.danger : tokens.success,
            ),
            (
              'Próximos vencimientos (7 días)',
              BackofficeSalesAdapter.formatMoney(summary.dueSoonAmount),
              'Por vencer esta semana',
              tokens.warning,
            ),
            (
              'Conciliación CXP',
              summary.reconciliationMismatches.isEmpty
                  ? 'Exacta'
                  : '${summary.reconciliationMismatches.length} alerta(s)',
              'Total - Pagado = Saldo',
              summary.reconciliationMismatches.isEmpty
                  ? tokens.success
                  : tokens.danger,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SaasCard(
          title: 'Antigüedad de saldos',
          subtitle: 'Distribución por vencimiento',
          child: Wrap(
            spacing: 24,
            runSpacing: 12,
            children: summary.agingBuckets
                .map(
                  (b) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${BackofficeSalesAdapter.formatMoney(b.amount)} (${b.count})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                )
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: 16),
        SaasCard(
          title: 'Documentos pendientes de pago',
          subtitle: 'Registra abonos parciales o liquidación total',
          trailing: OutlinedButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('Exportar CXP'),
          ),
          padding: summary.openPurchases.isEmpty
              ? const EdgeInsets.all(20)
              : EdgeInsets.zero,
          child: summary.openPurchases.isEmpty
              ? const Text('No hay cuentas por pagar pendientes.')
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: summary.openPurchases.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: tokens.border),
                  itemBuilder: (context, i) {
                    final p = summary.openPurchases[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => onSelectPurchase(p),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${p.folio} · ${p.supplierName}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${branchNames[p.branchId] ?? p.branchName} · Total: ${BackofficeSalesAdapter.formatMoney(p.total)} · Saldo: ${BackofficeSalesAdapter.formatMoney(p.balance)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: tokens.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (canPay)
                            FilledButton.tonal(
                              onPressed: () => onPayPurchase(p),
                              child: const Text('Registrar pago'),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 16),
        SaasCard(
          title: 'Historial de pagos a proveedores',
          subtitle: '${payments.length} movimiento(s) en el periodo',
          padding: payments.isEmpty
              ? const EdgeInsets.all(20)
              : EdgeInsets.zero,
          child: payments.isEmpty
              ? const Text('Sin pagos registrados en el periodo.')
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: payments.take(15).length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: tokens.border),
                  itemBuilder: (context, i) {
                    final pay = payments[i];
                    return ListTile(
                      title: Text(
                        '${pay.purchaseFolio} · ${pay.supplierName}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                      subtitle: Text(
                        '${pay.businessDate ?? ''} · ${pay.fundingSourceName}${pay.reference.isNotEmpty ? ' · Ref: ${pay.reference}' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textSecondary,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            BackofficeSalesAdapter.formatMoney(pay.amount),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: pay.isCancelled
                                  ? tokens.danger
                                  : tokens.success,
                              decoration: pay.isCancelled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          if (canCancelPayment && pay.isActive) ...[
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Cancelar pago',
                              onPressed: () => onCancelPayment(pay),
                              icon: Icon(
                                Icons.cancel_outlined,
                                size: 18,
                                color: tokens.danger,
                              ),
                            ),
                          ],
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

class EfficiencyAndBudgetsTab extends StatefulWidget {
  const EfficiencyAndBudgetsTab({
    super.key,
    required this.data,
    required this.isMobile,
  });

  final PurchasesDashboardData data;
  final bool isMobile;

  @override
  State<EfficiencyAndBudgetsTab> createState() =>
      _EfficiencyAndBudgetsTabState();
}

class _EfficiencyAndBudgetsTabState extends State<EfficiencyAndBudgetsTab> {
  String _selectedCategory = 'Todas';
  final TextEditingController _targetPer100Ctrl = TextEditingController();
  final Map<String, double> _weeklyTargets = {};

  @override
  void dispose() {
    _targetPer100Ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final m = widget.data.metrics;
    final categories = ['Todas', ...m.byCategory.keys];
    if (!categories.contains(_selectedCategory)) {
      _selectedCategory = 'Todas';
    }

    final currentCatPurchases = _selectedCategory == 'Todas'
        ? m.totalAmount
        : (m.byCategory[_selectedCategory] ?? 0.0);
    final targetVal = double.tryParse(_targetPer100Ctrl.text.trim());

    final efficiency = PurchasesAnalytics.computeEfficiency(
      label: _selectedCategory,
      purchasesAmount: currentCatPurchases,
      netSalesAmount: widget.data.currentNetSales,
      previousPurchasesAmount: m.previousTotalAmount,
      previousNetSalesAmount: widget.data.previousNetSales,
      targetPer100Sales: targetVal,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaasCard(
          title: 'Eficiencia de compras vs ventas',
          subtitle:
              'Indicador administrativo: Compras de categoría / Ventas netas × 100. No representa costo de mercancía vendida ni margen de utilidad.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String>(
                    value: _selectedCategory,
                    items: categories
                        .map(
                          (c) => DropdownMenuItem(value: c, child: Text(c)),
                        )
                        .toList(growable: false),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedCategory = v);
                    },
                  ),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _targetPer100Ctrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Meta opcional (\$/\$100 venta)',
                        hintText: 'Ej. 36',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _KpiWrap(
                isMobile: widget.isMobile,
                items: [
                  (
                    'Compras por cada \$100 de venta',
                    '\$${efficiency.costPer100Sales.toStringAsFixed(2)}',
                    'Periodo ant.: \$${efficiency.previousCostPer100Sales.toStringAsFixed(2)}',
                    tokens.brandAccent,
                  ),
                  (
                    'Compras ($_selectedCategory)',
                    BackofficeSalesAdapter.formatMoney(
                      efficiency.purchasesAmount,
                    ),
                    'Ventas netas: ${BackofficeSalesAdapter.formatMoney(efficiency.netSalesAmount)}',
                    tokens.info,
                  ),
                  (
                    'Desviación vs meta',
                    efficiency.deviationPer100Sales == null
                        ? 'Sin meta configurada'
                        : '${efficiency.deviationPer100Sales! >= 0 ? '+' : ''}\$${efficiency.deviationPer100Sales!.toStringAsFixed(2)}',
                    efficiency.targetPer100Sales != null
                        ? 'Meta: \$${efficiency.targetPer100Sales!.toStringAsFixed(2)} / \$100'
                        : 'Configura una meta para evaluar desviación',
                    efficiency.deviationPer100Sales != null &&
                            efficiency.deviationPer100Sales! > 0
                        ? tokens.danger
                        : tokens.success,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SaasCard(
          title: 'Presupuestos semanales por insumo',
          subtitle:
              'Indicador administrativo de cantidad objetivo vs comprada (no bloquea ventas en POS).',
          padding: m.itemReports.isEmpty
              ? const EdgeInsets.all(20)
              : EdgeInsets.zero,
          child: m.itemReports.isEmpty
              ? const Text('Sin insumos comprados en el periodo.')
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: m.itemReports.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: tokens.border),
                  itemBuilder: (context, i) {
                    final r = m.itemReports[i];
                    final targetQty = _weeklyTargets[r.itemKey];
                    final eval = targetQty != null && targetQty > 0
                        ? PurchasesAnalytics.evaluateWeeklyBudget(
                            itemReport: r,
                            targetWeeklyQty: targetQty,
                          )
                        : null;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${r.itemName} (${r.unit})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Comprado: ${r.totalQuantity.toStringAsFixed(2)} ${r.unit} · Gasto: ${BackofficeSalesAdapter.formatMoney(r.totalAmount)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: tokens.textSecondary,
                                  ),
                                ),
                                if (eval != null)
                                  Text(
                                    'Meta: ${eval.targetWeeklyQty.toStringAsFixed(2)} ${eval.unit} · Dif: ${eval.differenceQty >= 0 ? '+' : ''}${eval.differenceQty.toStringAsFixed(2)} ${eval.unit}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: eval.isExceeded
                                          ? tokens.danger
                                          : tokens.success,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Meta (${r.unit})',
                                isDense: true,
                              ),
                              onChanged: (v) {
                                final parsed = double.tryParse(v.trim());
                                setState(() {
                                  if (parsed == null || parsed <= 0) {
                                    _weeklyTargets.remove(r.itemKey);
                                  } else {
                                    _weeklyTargets[r.itemKey] = parsed;
                                  }
                                });
                              },
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
  }
}

class _KpiWrap extends StatelessWidget {
  const _KpiWrap({required this.items, required this.isMobile});

  final List<(String, String, String, Color)> items;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 960
            ? (items.length >= 4 ? 4 : items.length)
            : constraints.maxWidth >= 540
            ? 2
            : 1;
        final width = (constraints.maxWidth - (12 * (cols - 1))) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: SaasCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: tokens.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.$2,
                          style: TextStyle(
                            fontSize: isMobile ? 19 : 21,
                            fontWeight: FontWeight.w700,
                            color: item.$4,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.$3,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

StatusPill purchaseStatusPill(String status) {
  return switch (status.trim().toLowerCase()) {
    'paid' => const StatusPill(label: 'Pagada', tone: StatusTone.success),
    'partial' => const StatusPill(label: 'Parcial', tone: StatusTone.info),
    'cancelled' => const StatusPill(label: 'Cancelada', tone: StatusTone.danger),
    _ => const StatusPill(label: 'Pendiente', tone: StatusTone.warning),
  };
}

String documentTypeLabel(String type) {
  return switch (type.trim().toLowerCase()) {
    'invoice' => 'Factura',
    'ticket' => 'Ticket',
    'remission' => 'Remisión',
    _ => 'Nota',
  };
}

class PurchaseItemsCatalogTab extends StatelessWidget {
  const PurchaseItemsCatalogTab({
    super.key,
    required this.items,
    required this.canManage,
    required this.onCreateOrEdit,
  });

  final List<PurchaseItem> items;
  final bool canManage;
  final ValueChanged<PurchaseItem?> onCreateOrEdit;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return SaasCard(
      title: 'Catálogo de insumos de compra',
      subtitle: '${items.length} insumo(s) registrado(s)',
      trailing: canManage
          ? FilledButton.icon(
              onPressed: () => onCreateOrEdit(null),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Nuevo insumo'),
            )
          : null,
      padding: items.isEmpty ? const EdgeInsets.all(20) : EdgeInsets.zero,
      child: items.isEmpty
          ? const Text('No hay insumos de compra registrados.')
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: tokens.border),
              itemBuilder: (context, i) {
                final item = items[i];
                return ListTile(
                  onTap: canManage ? () => onCreateOrEdit(item) : null,
                  title: Text(
                    '${item.name} (${item.unit})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${item.category}${item.defaultSupplierName != null && item.defaultSupplierName!.isNotEmpty ? ' · Proveedor: ${item.defaultSupplierName}' : ''}',
                    style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                  ),
                  trailing: StatusPill(
                    label: item.active ? 'Activo' : 'Inactivo',
                    tone: item.active ? StatusTone.success : StatusTone.neutral,
                  ),
                );
              },
            ),
    );
  }
}

class SupplierStatementTab extends StatefulWidget {
  const SupplierStatementTab({
    super.key,
    required this.suppliers,
    required this.purchases,
    required this.payments,
    required this.isMobile,
    required this.onExport,
  });

  final List<Supplier> suppliers;
  final List<SupplierPurchase> purchases;
  final List<SupplierPayment> payments;
  final bool isMobile;
  final ValueChanged<SupplierStatementSummary> onExport;

  @override
  State<SupplierStatementTab> createState() => _SupplierStatementTabState();
}

class _SupplierStatementTabState extends State<SupplierStatementTab> {
  String? _selectedSupplierId;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    if (widget.suppliers.isEmpty) {
      return const SaasEmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Sin proveedores',
        message: 'Registra al menos un proveedor para consultar su estado de cuenta.',
      );
    }
    _selectedSupplierId ??= widget.suppliers.first.id;
    final statement = PurchasesAnalytics.buildSupplierStatement(
      supplierId: _selectedSupplierId!,
      purchases: widget.purchases,
      payments: widget.payments,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaasCard(
          title: 'Estado de cuenta por proveedor',
          subtitle: 'Movimientos cronológicos de cargos, abonos y saldo acumulado.',
          trailing: OutlinedButton.icon(
            onPressed: () => widget.onExport(statement),
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('Exportar CSV'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<String>(
                value: _selectedSupplierId,
                items: widget.suppliers
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(s.commercialName),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedSupplierId = v);
                },
              ),
              const SizedBox(height: 14),
              _KpiWrap(
                isMobile: widget.isMobile,
                items: [
                  (
                    'Saldo inicial',
                    BackofficeSalesAdapter.formatMoney(statement.openingBalance),
                    'Inicio del periodo',
                    tokens.textSecondary,
                  ),
                  (
                    'Total cargos',
                    BackofficeSalesAdapter.formatMoney(statement.totalCharges),
                    'Compras activas',
                    tokens.brandAccent,
                  ),
                  (
                    'Total abonos',
                    BackofficeSalesAdapter.formatMoney(statement.totalPayments),
                    'Pagos aplicados',
                    tokens.success,
                  ),
                  (
                    'Saldo final',
                    BackofficeSalesAdapter.formatMoney(statement.closingBalance),
                    'Por pagar al cierre',
                    statement.closingBalance > 0.01
                        ? tokens.warning
                        : tokens.success,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SaasCard(
          title: 'Movimientos cronológicos (${statement.rows.length})',
          padding: statement.rows.isEmpty
              ? const EdgeInsets.all(20)
              : EdgeInsets.zero,
          child: statement.rows.isEmpty
              ? const Text('Sin movimientos en el periodo seleccionado.')
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: statement.rows.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: tokens.border),
                  itemBuilder: (context, i) {
                    final row = statement.rows[i];
                    final isCharge = row.type == 'charge';
                    return ListTile(
                      title: Text(
                        '${row.folio} · ${row.notes}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                      subtitle: Text(
                        BackofficeSalesAdapter.formatDateTime(row.date),
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
                            isCharge
                                ? '+${BackofficeSalesAdapter.formatMoney(row.charge)}'
                                : '-${BackofficeSalesAdapter.formatMoney(row.credit)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isCharge
                                  ? tokens.brandAccent
                                  : tokens.success,
                            ),
                          ),
                          Text(
                            'Saldo: ${BackofficeSalesAdapter.formatMoney(row.balance)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: tokens.textSecondary,
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
  }
}

class PurchaseKardexTab extends StatefulWidget {
  const PurchaseKardexTab({
    super.key,
    required this.entries,
    required this.branchNames,
    required this.onExport,
  });

  final List<PurchaseKardexEntry> entries;
  final Map<String, String> branchNames;
  final ValueChanged<List<PurchaseKardexEntry>> onExport;

  @override
  State<PurchaseKardexTab> createState() => _PurchaseKardexTabState();
}

class _PurchaseKardexTabState extends State<PurchaseKardexTab> {
  String _selectedItem = 'Todos';

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final items = [
      'Todos',
      ...{for (final e in widget.entries) e.itemName},
    ];
    if (!items.contains(_selectedItem)) _selectedItem = 'Todos';

    final filtered = _selectedItem == 'Todos'
        ? widget.entries
        : widget.entries
              .where((e) => e.itemName == _selectedItem)
              .toList(growable: false);

    return SaasCard(
      title: 'Kardex cronológico de compras',
      subtitle: '${filtered.length} entrada(s) registrada(s)',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<String>(
            value: _selectedItem,
            items: items
                .map((i) => DropdownMenuItem(value: i, child: Text(i)))
                .toList(growable: false),
            onChanged: (v) {
              if (v != null) setState(() => _selectedItem = v);
            },
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => widget.onExport(filtered),
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('Exportar CSV'),
          ),
        ],
      ),
      padding: filtered.isEmpty ? const EdgeInsets.all(20) : EdgeInsets.zero,
      child: filtered.isEmpty
          ? const Text('Sin movimientos de kardex en el periodo.')
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: tokens.border),
              itemBuilder: (context, i) {
                final e = filtered[i];
                return ListTile(
                  title: Text(
                    '${e.itemName} · ${e.quantity.toStringAsFixed(2)} ${e.unit}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  subtitle: Text(
                    '${e.dateLabel} · ${e.folio} · ${e.supplierName} · ${widget.branchNames[e.branchId] ?? e.branchId}',
                    style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        BackofficeSalesAdapter.formatMoney(e.lineTotal),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${BackofficeSalesAdapter.formatMoney(e.unitCost)}/${e.unit}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
