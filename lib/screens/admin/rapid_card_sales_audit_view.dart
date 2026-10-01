import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/reports/rapid_card_sales_audit.dart';
import '../../core/reports/report_data_bundle.dart';
import '../../core/theme/brand_colors.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/csv_exporter.dart';
import '../../widgets/glass.dart';

class RapidCardSalesAuditView extends StatefulWidget {
  const RapidCardSalesAuditView({
    super.key,
    required this.reportData,
    required this.startBusinessDate,
    required this.endBusinessDate,
  });

  final ReportDataBundle reportData;
  final String startBusinessDate;
  final String endBusinessDate;

  @override
  State<RapidCardSalesAuditView> createState() =>
      _RapidCardSalesAuditViewState();
}

class _RapidCardSalesAuditViewState extends State<RapidCardSalesAuditView> {
  final _queryController = TextEditingController();
  String _employee = 'all';
  String _maxSeconds = '60';
  RapidCardAuditTimingBasis _basis = RapidCardAuditTimingBasis.orderCreated;
  bool _onlyKitchenCompleteBeforePayment = true;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allRows = buildRapidCardSalesAudit(
      orders: widget.reportData.orders,
      itemsByOrder: widget.reportData.itemsByOrder,
      paymentsByOrder: widget.reportData.paymentsByOrder,
    );
    final employees = allRows
        .map((row) => row.cashierName)
        .toSet()
        .toList()
      ..sort();

    if (_employee != 'all' && !employees.contains(_employee)) {
      _employee = 'all';
    }

    final filtered = _filteredRows(allRows);
    final threshold = int.tryParse(_maxSeconds);
    final rapidRows = threshold == null
        ? allRows
        : allRows
            .where((row) => row.matchesSeconds(threshold, basis: _basis))
            .toList(growable: false);
    final strongRows = rapidRows
        .where((row) => row.kitchenCompleteBeforePayment)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _queryController,
                      decoration: const InputDecoration(
                        labelText: 'Buscar folio, mesa, cajero o producto',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                      value: _employee,
                      decoration: const InputDecoration(labelText: 'Cajero'),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('Todos'),
                        ),
                        ...employees.map(
                          (employee) => DropdownMenuItem(
                            value: employee,
                            child: Text(employee),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _employee = value ?? 'all'),
                    ),
                  ),
                  SizedBox(
                    width: 230,
                    child: DropdownButtonFormField<RapidCardAuditTimingBasis>(
                      value: _basis,
                      decoration: const InputDecoration(labelText: 'Medir desde'),
                      items: RapidCardAuditTimingBasis.values
                          .map(
                            (basis) => DropdownMenuItem(
                              value: basis,
                              child: Text(_basisLabel(basis)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _basis = value);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<String>(
                      value: _maxSeconds,
                      decoration: const InputDecoration(labelText: 'Ventana'),
                      items: const [
                        DropdownMenuItem(value: '30', child: Text('≤ 30 s')),
                        DropdownMenuItem(value: '60', child: Text('≤ 60 s')),
                        DropdownMenuItem(value: '120', child: Text('≤ 2 min')),
                        DropdownMenuItem(value: '180', child: Text('≤ 3 min')),
                        DropdownMenuItem(value: '300', child: Text('≤ 5 min')),
                        DropdownMenuItem(value: 'all', child: Text('Todas')),
                      ],
                      onChanged: (value) =>
                          setState(() => _maxSeconds = value ?? '60'),
                    ),
                  ),
                  FilterChip(
                    selected: _onlyKitchenCompleteBeforePayment,
                    label: const Text('Solo cocina lista antes del cobro'),
                    onSelected: (value) => setState(
                      () => _onlyKitchenCompleteBeforePayment = value,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: filtered.isEmpty ? null : () => _export(filtered),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('CSV'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Este reporte detecta patrones temporales; no determina por sí solo la causa. '
                'Por defecto muestra pagos con tarjeta cuya orden fue creada y cobrada en 60 segundos o menos, '
                'con todos los productos de cocina marcados listos antes del cobro.',
                style: TextStyle(
                  color: BrandColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              label: 'Pagos tarjeta',
              value: '${allRows.length}',
              detail:
                  '${widget.startBusinessDate} a ${widget.endBusinessDate}',
            ),
            _MetricCard(
              label: _maxSeconds == 'all'
                  ? 'Dentro del filtro'
                  : '${_windowLabel(_maxSeconds)} · ${_basisLabel(_basis)}',
              value: '${rapidRows.length}',
              detail: _money(
                rapidRows.fold<double>(
                  0,
                  (sum, row) => sum + row.cardAmount,
                ),
              ),
            ),
            _MetricCard(
              label: 'Cocina completa antes del cobro',
              value:
                  '${allRows.where((row) => row.kitchenCompleteBeforePayment).length}',
              detail: 'Todos los productos de cocina con readyAt previo al pago',
            ),
            _MetricCard(
              label: 'Coincidencia temporal fuerte',
              value: '${strongRows.length}',
              detail: _maxSeconds == 'all'
                  ? 'Cocina completa dentro del filtro'
                  : '${_windowLabel(_maxSeconds)} y cocina completa',
              emphasize: strongRows.isNotEmpty,
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          const GlassPanel(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No hay operaciones que coincidan con los filtros.',
                  style: TextStyle(
                    color: BrandColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          )
        else
          GlassPanel(
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 20,
                headingRowHeight: 52,
                dataRowMinHeight: 52,
                dataRowMaxHeight: 92,
                columns: const [
                  DataColumn(label: Text('Fecha / hora pago')),
                  DataColumn(label: Text('Folio')),
                  DataColumn(label: Text('Mesa / pedido')),
                  DataColumn(label: Text('Cajero')),
                  DataColumn(label: Text('Tarjeta')),
                  DataColumn(label: Text('Orden creada')),
                  DataColumn(label: Text('Último producto capturado')),
                  DataColumn(label: Text('Enviado a cocina')),
                  DataColumn(label: Text('Último listo')),
                  DataColumn(label: Text('Pago tarjeta')),
                  DataColumn(label: Text('Orden → pago')),
                  DataColumn(label: Text('Último producto → pago')),
                  DataColumn(label: Text('Cocina → pago')),
                  DataColumn(label: Text('Listo → pago')),
                  DataColumn(label: Text('Cocina listos')),
                  DataColumn(label: Text('Productos')),
                ],
                rows: filtered.map(_dataRow).toList(growable: false),
              ),
            ),
          ),
      ],
    );
  }

  List<RapidCardSaleAuditRow> _filteredRows(
    List<RapidCardSaleAuditRow> rows,
  ) {
    final query = _queryController.text.trim().toLowerCase();
    final maxSeconds = int.tryParse(_maxSeconds);

    final filtered = rows.where((row) {
      if (_employee != 'all' && row.cashierName != _employee) return false;
      if (maxSeconds != null &&
          !row.matchesSeconds(maxSeconds, basis: _basis)) {
        return false;
      }
      if (_onlyKitchenCompleteBeforePayment &&
          !row.kitchenCompleteBeforePayment) {
        return false;
      }
      if (query.isNotEmpty) {
        final haystack = [
          row.folio,
          row.orderLabel,
          row.cashierName,
          row.productsLabel,
          row.order.id,
          row.payment.id,
        ].join(' ').toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      final aSeconds = a.secondsFor(_basis);
      final bSeconds = b.secondsFor(_basis);
      if (aSeconds != null && bSeconds != null) {
        final bySeconds = aSeconds.compareTo(bSeconds);
        if (bySeconds != 0) return bySeconds;
      } else if (aSeconds != null) {
        return -1;
      } else if (bSeconds != null) {
        return 1;
      }
      final aPaid = a.paymentAt;
      final bPaid = b.paymentAt;
      if (aPaid != null && bPaid != null) return bPaid.compareTo(aPaid);
      return a.folio.compareTo(b.folio);
    });
    return filtered;
  }

  DataRow _dataRow(RapidCardSaleAuditRow row) {
    return DataRow(
      color: WidgetStateProperty.resolveWith((states) {
        if (row.isStrongRapidKitchenMatch) {
          return BrandColors.danger.withValues(alpha: 0.10);
        }
        if (row.isRapidOrderToCard60) {
          return BrandColors.accentYellow.withValues(alpha: 0.07);
        }
        return null;
      }),
      cells: [
        DataCell(Text(_dateTime(row.paymentAt))),
        DataCell(SelectableText(row.folio)),
        DataCell(Text(row.orderLabel)),
        DataCell(Text(row.cashierName)),
        DataCell(
          Text(
            _money(row.cardAmount),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        DataCell(Text(_time(row.orderCreatedAt))),
        DataCell(Text(_time(row.lastItemCreatedAt))),
        DataCell(Text(_time(row.sentToKitchenAt))),
        DataCell(
          Text(
            _time(row.lastReadyAt),
            style: TextStyle(
              fontWeight: row.kitchenCompleteBeforePayment
                  ? FontWeight.w900
                  : FontWeight.w600,
              color: row.kitchenCompleteBeforePayment
                  ? BrandColors.success
                  : null,
            ),
          ),
        ),
        DataCell(Text(_time(row.paymentAt))),
        DataCell(Text(_duration(row.orderToPayment))),
        DataCell(Text(_duration(row.lastItemToPayment))),
        DataCell(Text(_duration(row.kitchenSendToPayment))),
        DataCell(Text(_signedDuration(row.lastReadyToPayment))),
        DataCell(
          Text(
            '${row.readyKitchenItems}/${row.kitchenItemCount}',
            style: TextStyle(
              color: row.kitchenCompleteBeforePayment
                  ? BrandColors.success
                  : null,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              row.productsLabel,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _export(List<RapidCardSaleAuditRow> rows) async {
    const headers = [
      'fechaHoraPago',
      'folio',
      'orderId',
      'paymentId',
      'mesaPedido',
      'cajero',
      'cardAmount',
      'chargedAmount',
      'cardFeeAmount',
      'orderCreatedAt',
      'firstItemCreatedAt',
      'lastItemCreatedAt',
      'sentToKitchenAt',
      'firstReadyAt',
      'lastReadyAt',
      'paymentAt',
      'orderToPaymentSeconds',
      'lastItemToPaymentSeconds',
      'kitchenSendToPaymentSeconds',
      'lastReadyToPaymentSeconds',
      'readyKitchenItems',
      'kitchenItemCount',
      'kitchenCompleteBeforePayment',
      'products',
    ];

    final data = <List<String>>[
      headers,
      ...rows.map(
        (row) => [
          _iso(row.paymentAt),
          row.folio,
          row.order.id,
          row.payment.id,
          row.orderLabel,
          row.cashierName,
          row.cardAmount.toStringAsFixed(2),
          row.chargedAmount.toStringAsFixed(2),
          row.cardFeeAmount.toStringAsFixed(2),
          _iso(row.orderCreatedAt),
          _iso(row.firstItemCreatedAt),
          _iso(row.lastItemCreatedAt),
          _iso(row.sentToKitchenAt),
          _iso(row.firstReadyAt),
          _iso(row.lastReadyAt),
          _iso(row.paymentAt),
          row.orderToPayment?.inSeconds.toString() ?? '',
          row.lastItemToPayment?.inSeconds.toString() ?? '',
          row.kitchenSendToPayment?.inSeconds.toString() ?? '',
          row.lastReadyToPayment?.inSeconds.toString() ?? '',
          '${row.readyKitchenItems}',
          '${row.kitchenItemCount}',
          row.kitchenCompleteBeforePayment ? 'true' : 'false',
          row.productsLabel,
        ],
      ),
    ];

    final csv = data
        .map((row) => row.map(_csvCell).join(','))
        .join('\r\n');
    final message = await exportCsvFile(
      fileName:
          'tacopos-auditoria-tarjeta-rapida-${widget.startBusinessDate}-${widget.endBusinessDate}.csv',
      content: csv,
    );
    if (!mounted) return;
    showAppSnackBar(
      context,
      message,
      type: AppSnackBarType.success,
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final String detail;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: GlassPanel(
        padding: const EdgeInsets.all(14),
        borderColor: emphasize
            ? BrandColors.danger.withValues(alpha: 0.55)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: BrandColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: emphasize ? BrandColors.danger : BrandColors.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              detail,
              style: const TextStyle(
                color: BrandColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _basisLabel(RapidCardAuditTimingBasis basis) {
  return switch (basis) {
    RapidCardAuditTimingBasis.orderCreated => 'Orden creada',
    RapidCardAuditTimingBasis.lastItemCaptured => 'Último producto capturado',
    RapidCardAuditTimingBasis.sentToKitchen => 'Envío a cocina',
    RapidCardAuditTimingBasis.lastReady => 'Último producto listo',
  };
}

String _windowLabel(String value) {
  return switch (value) {
    '30' => '≤ 30 s',
    '60' => '≤ 60 s',
    '120' => '≤ 2 min',
    '180' => '≤ 3 min',
    '300' => '≤ 5 min',
    _ => 'Todas',
  };
}

String _dateTime(DateTime? value) {
  if (value == null) return '-';
  return DateFormat('dd/MM/yyyy HH:mm:ss').format(value);
}

String _time(DateTime? value) {
  if (value == null) return '-';
  return DateFormat('HH:mm:ss').format(value);
}

String _duration(Duration? value) {
  if (value == null) return '-';
  final seconds = value.inSeconds;
  if (seconds < 0) return '-';
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  return '${minutes}m ${remaining}s';
}

String _signedDuration(Duration? value) {
  if (value == null) return '-';
  final seconds = value.inSeconds;
  final sign = seconds < 0 ? '-' : '';
  final absolute = seconds.abs();
  if (absolute < 60) return '$sign${absolute}s';
  final minutes = absolute ~/ 60;
  final remaining = absolute % 60;
  return '$sign${minutes}m ${remaining}s';
}

String _money(double value) {
  return NumberFormat.currency(
    locale: 'es_MX',
    symbol: r'$',
    decimalDigits: 2,
  ).format(value);
}

String _iso(DateTime? value) => value?.toIso8601String() ?? '';

String _csvCell(String value) {
  final escaped = value.replaceAll('"', '""');
  if (escaped.contains(',') ||
      escaped.contains('"') ||
      escaped.contains('\n') ||
      escaped.contains('\r')) {
    return '"$escaped"';
  }
  return escaped;
}
