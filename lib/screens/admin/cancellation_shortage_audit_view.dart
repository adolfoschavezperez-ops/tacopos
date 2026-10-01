import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/reports/cancellation_shortage_audit.dart';
import '../../core/reports/report_data_bundle.dart';
import '../../core/theme/brand_colors.dart';
import '../../models/cash_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/csv_exporter.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';

class CancellationShortageAuditView extends StatefulWidget {
  const CancellationShortageAuditView({
    super.key,
    required this.repository,
    required this.reportData,
    required this.startBusinessDate,
    required this.endBusinessDate,
  });

  final TacoPosRepository repository;
  final ReportDataBundle reportData;
  final String startBusinessDate;
  final String endBusinessDate;

  @override
  State<CancellationShortageAuditView> createState() =>
      _CancellationShortageAuditViewState();
}

class _CancellationShortageAuditViewState
    extends State<CancellationShortageAuditView> {
  final _queryController = TextEditingController();
  final _knownOutflowController = TextEditingController();
  String _employee = 'all';
  String? _reconciliationDate;
  bool _employeeInitialized = false;
  bool _onlyNoPayment = true;
  bool _onlyFullOrder = true;
  bool _onlyKitchen = true;

  late Future<List<CashSession>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _sessionsFuture = _loadSessions();
  }

  @override
  void didUpdateWidget(covariant CancellationShortageAuditView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startBusinessDate != widget.startBusinessDate ||
        oldWidget.endBusinessDate != widget.endBusinessDate) {
      _sessionsFuture = _loadSessions();
      _reconciliationDate = null;
      _employeeInitialized = false;
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _knownOutflowController.dispose();
    super.dispose();
  }

  Future<List<CashSession>> _loadSessions() async {
    final result = await widget.repository.getCashScheduleSessions(
      startBusinessDate: widget.startBusinessDate,
      endBusinessDate: widget.endBusinessDate,
    );
    return result.sessions;
  }

  @override
  Widget build(BuildContext context) {
    final allRows = buildCancellationCashAuditRows(
      orders: widget.reportData.orders,
      itemsByOrder: widget.reportData.itemsByOrder,
      paymentsByOrder: widget.reportData.paymentsByOrder,
    );

    final employeeNames = allRows
        .expand((row) => row.initiatedByNames)
        .where((name) => name.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    if (!_employeeInitialized) {
      final andres = employeeNames.where((name) {
        final clean = name.toLowerCase();
        return clean.contains('andres') || clean.contains('andrés');
      }).toList();
      _employee = andres.isNotEmpty ? andres.first : 'all';
      _employeeInitialized = true;
    }
    if (_employee != 'all' && !employeeNames.contains(_employee)) {
      _employee = 'all';
    }

    return FutureBuilder<List<CashSession>>(
      future: _sessionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingPanel(
            message: 'Cruzando cancelaciones contra cortes...',
          );
        }
        if (snapshot.hasError) {
          return GlassPanel(
            borderColor: BrandColors.danger,
            child: Text(
              'No se pudieron cargar los cortes: ${snapshot.error}',
              style: const TextStyle(
                color: BrandColors.danger,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }

        final sessions = snapshot.data ?? const <CashSession>[];
        final days = buildCancellationCashAuditDays(
          rows: allRows,
          cashSessions: sessions,
        );
        final filteredRows = _filterRows(allRows);
        final selectedDays = _employeeDays(days);
        _ensureReconciliationDate(selectedDays);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _filters(employeeNames),
            const SizedBox(height: 14),
            _summary(selectedDays, filteredRows),
            const SizedBox(height: 14),
            _dailyCorrelationTable(selectedDays),
            const SizedBox(height: 14),
            _reconciliationPanel(selectedDays),
            const SizedBox(height: 14),
            _detailTable(filteredRows, selectedDays),
          ],
        );
      },
    );
  }

  Widget _filters(List<String> employees) {
    return GlassPanel(
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
                width: 230,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('employee-${employees.join('|')}'),
                  initialValue: _employee,
                  decoration: const InputDecoration(
                    labelText: 'Quién inició la cancelación',
                  ),
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
                width: 280,
                child: TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    labelText: 'Buscar folio, mesa, producto o motivo',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              FilterChip(
                selected: _onlyNoPayment,
                label: const Text('Sin pago registrado'),
                onSelected: (value) =>
                    setState(() => _onlyNoPayment = value),
              ),
              FilterChip(
                selected: _onlyFullOrder,
                label: const Text('Orden completa cancelada'),
                onSelected: (value) =>
                    setState(() => _onlyFullOrder = value),
              ),
              FilterChip(
                selected: _onlyKitchen,
                label: const Text('Pasó por cocina'),
                onSelected: (value) =>
                    setState(() => _onlyKitchen = value),
              ),
              FilledButton.icon(
                onPressed: () => _export(_filterRows(
                  buildCancellationCashAuditRows(
                    orders: widget.reportData.orders,
                    itemsByOrder: widget.reportData.itemsByOrder,
                    paymentsByOrder: widget.reportData.paymentsByOrder,
                  ),
                )),
                icon: const Icon(Icons.download_outlined),
                label: const Text('CSV'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '“Inició” usa al solicitante de cancelación cuando la orden ya estaba en cocina; '
            'si fue una cancelación directa usa al usuario que la ejecutó. Así no se pierde '
            'el caso donde caja solicita y cocina solamente autoriza.',
            style: TextStyle(
              color: BrandColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(
    List<CancellationCashAuditDay> days,
    List<CancellationCashAuditRow> filteredRows,
  ) {
    final shortage = days.fold<double>(0, (sum, day) => sum + day.shortage);
    final cancelled = filteredRows.fold<double>(
      0,
      (sum, row) => sum + row.cancelledAmount,
    );
    final noPayment = filteredRows
        .where((row) => row.hasNoPaymentRecord)
        .fold<double>(0, (sum, row) => sum + row.cancelledAmount);
    final strong = filteredRows
        .where((row) => row.strongCashCancellationCandidate)
        .fold<double>(0, (sum, row) => sum + row.cancelledAmount);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _AuditMetric(
          label: 'Faltante de cortes',
          value: _money(shortage),
          detail: '${days.where((day) => day.cashSession != null).length} días con corte',
          accent: BrandColors.danger,
        ),
        _AuditMetric(
          label: 'Cancelado con filtros',
          value: _money(cancelled),
          detail: '${filteredRows.length} órdenes / grupos',
        ),
        _AuditMetric(
          label: 'Cancelado sin pago',
          value: _money(noPayment),
          detail: 'No existe ningún documento de pago',
          accent: BrandColors.accentOrange,
        ),
        _AuditMetric(
          label: 'Candidato fuerte',
          value: _money(strong),
          detail: 'Orden completa + sin pago + pasó por cocina',
          accent: BrandColors.accentYellow,
        ),
      ],
    );
  }

  Widget _dailyCorrelationTable(List<CancellationCashAuditDay> days) {
    final rows = days.where((day) {
      if (day.cashSession == null && day.rows.isEmpty) return false;
      if (_employee == 'all') return true;
      return day.initiatedBy(_employee).isNotEmpty || day.shortage > 0;
    }).toList();

    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Cancelaciones vs faltante del corte',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'La columna “faltante + cancelado sin pago” NO afirma que ese efectivo haya sido cobrado. '
            'Muestra la salida física que cuadraría si esas cancelaciones hubieran sido ventas cobradas '
            'en efectivo pero no registradas.',
            style: TextStyle(
              color: BrandColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 22,
              columns: const [
                DataColumn(label: Text('Fecha')),
                DataColumn(label: Text('Faltante corte')),
                DataColumn(label: Text('Cancelado')),
                DataColumn(label: Text('Sin pago')),
                DataColumn(label: Text('Candidato fuerte')),
                DataColumn(label: Text('Faltante + sin pago')),
                DataColumn(label: Text('Órdenes')),
                DataColumn(label: Text('Sesiones caja')),
              ],
              rows: rows.map((day) {
                final employeeName = _employee == 'all' ? '' : _employee;
                final selected = employeeName.isEmpty
                    ? day.rows
                    : day.initiatedBy(employeeName);
                final cancelled = selected.fold<double>(
                  0,
                  (sum, row) => sum + row.cancelledAmount,
                );
                final noPayment = selected
                    .where((row) => row.hasNoPaymentRecord)
                    .fold<double>(
                      0,
                      (sum, row) => sum + row.cancelledAmount,
                    );
                final strong = selected
                    .where((row) => row.strongCashCancellationCandidate)
                    .fold<double>(
                      0,
                      (sum, row) => sum + row.cancelledAmount,
                    );
                return DataRow(
                  cells: [
                    DataCell(Text(day.businessDate)),
                    DataCell(_moneyCell(day.shortage, danger: day.shortage > 0)),
                    DataCell(_moneyCell(cancelled)),
                    DataCell(_moneyCell(noPayment, warning: noPayment > 0)),
                    DataCell(_moneyCell(strong, warning: strong > 0)),
                    DataCell(
                      _moneyCell(
                        day.shortage + noPayment,
                        warning: day.shortage > 0 && noPayment > 0,
                      ),
                    ),
                    DataCell(Text('${selected.length}')),
                    DataCell(Text('${day.cashSessionCount}')),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reconciliationPanel(List<CancellationCashAuditDay> days) {
    final date = _reconciliationDate;
    final day = date == null
        ? null
        : days.where((entry) => entry.businessDate == date).firstOrNull;
    final knownOutflow = _parseMoney(_knownOutflowController.text);
    final target = day == null || knownOutflow <= 0
        ? 0.0
        : (knownOutflow - day.shortage).clamp(0, double.infinity).toDouble();

    final employeeRows = day == null
        ? const <CancellationCashAuditRow>[]
        : (_employee == 'all' ? day.rows : day.initiatedBy(_employee))
            .where((row) => row.hasNoPaymentRecord)
            .toList();

    final matches = target <= 0
        ? const <CancellationAmountMatch>[]
        : findCancellationAmountMatches(
            rows: employeeRows,
            target: target,
            maxItems: 4,
            maxResults: 6,
            tolerance: 2,
          );

    return GlassPanel(
      borderColor: BrandColors.accentOrange.withValues(alpha: 0.45),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Reconciliar una salida física conocida',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ejemplo: si salieron $500 de la caja sin registrarse y el corte solo quedó con '
            '$285 de faltante, el efectivo compensatorio requerido es $215. Aquí buscamos '
            'cancelaciones sin pago cuyo importe sume ese monto.',
            style: TextStyle(
              color: BrandColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('date-${days.map((d) => d.businessDate).join('|')}'),
                  initialValue: date,
                  decoration: const InputDecoration(labelText: 'Fecha'),
                  items: days
                      .map(
                        (day) => DropdownMenuItem(
                          value: day.businessDate,
                          child: Text(day.businessDate),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _reconciliationDate = value),
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _knownOutflowController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9.,]'),
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Salida no registrada',
                    prefixText: r'$ ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (day != null)
                _InlineValue(
                  label: 'Faltante',
                  value: _money(day.shortage),
                ),
              if (knownOutflow > 0 && day != null)
                _InlineValue(
                  label: 'Compensación requerida',
                  value: _money(target),
                  accent: BrandColors.accentYellow,
                ),
            ],
          ),
          if (knownOutflow > 0 && day != null) ...[
            const SizedBox(height: 14),
            if (matches.isEmpty)
              const Text(
                'No hay combinaciones de hasta 4 cancelaciones sin pago para comparar.',
                style: TextStyle(color: BrandColors.textMuted),
              )
            else
              ...matches.map((match) {
                final close = match.absoluteDifference <= 2;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: close
                          ? BrandColors.accentYellow.withValues(alpha: 0.10)
                          : BrandColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: close
                            ? BrandColors.accentYellow.withValues(alpha: 0.45)
                            : BrandColors.glassBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          close
                              ? Icons.gps_fixed
                              : Icons.calculate_outlined,
                          color: close
                              ? BrandColors.accentYellow
                              : BrandColors.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            match.rows
                                .map((row) => '${row.folio} (${_money(row.cancelledAmount)})')
                                .join(' + '),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_money(match.total)}  Δ ${_signedMoney(match.difference)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: close
                                ? BrandColors.accentYellow
                                : BrandColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }

  Widget _detailTable(
    List<CancellationCashAuditRow> rows,
    List<CancellationCashAuditDay> days,
  ) {
    final shortageByDate = {
      for (final day in days) day.businessDate: day.shortage,
    };

    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Detalle de cancelaciones',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No hay cancelaciones que coincidan con los filtros.',
                  style: TextStyle(color: BrandColors.textMuted),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                dataRowMinHeight: 56,
                dataRowMaxHeight: 98,
                columns: const [
                  DataColumn(label: Text('Fecha')),
                  DataColumn(label: Text('Hora')),
                  DataColumn(label: Text('Folio')),
                  DataColumn(label: Text('Mesa / pedido')),
                  DataColumn(label: Text('Inició cancelación')),
                  DataColumn(label: Text('Aceptó')),
                  DataColumn(label: Text('Importe cancelado')),
                  DataColumn(label: Text('Faltante corte')),
                  DataColumn(label: Text('Faltante + esta cancelación')),
                  DataColumn(label: Text('Pago docs')),
                  DataColumn(label: Text('Cocina')),
                  DataColumn(label: Text('Completa')),
                  DataColumn(label: Text('Motivo')),
                  DataColumn(label: Text('Productos')),
                ],
                rows: rows.map((row) {
                  final shortage = shortageByDate[row.businessDate] ?? 0;
                  return DataRow(
                    color: WidgetStateProperty.resolveWith((states) {
                      if (row.strongCashCancellationCandidate) {
                        return BrandColors.danger.withValues(alpha: 0.08);
                      }
                      return null;
                    }),
                    cells: [
                      DataCell(Text(row.businessDate)),
                      DataCell(Text(_time(row.cancelledAt))),
                      DataCell(SelectableText(row.folio)),
                      DataCell(Text(row.order.displayName)),
                      DataCell(Text(row.initiatedByLabel)),
                      DataCell(Text(row.acceptedByLabel)),
                      DataCell(_moneyCell(
                        row.cancelledAmount,
                        warning: row.hasNoPaymentRecord,
                      )),
                      DataCell(_moneyCell(
                        shortage,
                        danger: shortage > 0,
                      )),
                      DataCell(_moneyCell(
                        shortage + row.cancelledAmount,
                        warning: shortage > 0 && row.hasNoPaymentRecord,
                      )),
                      DataCell(
                        Text(
                          row.hasNoPaymentRecord
                              ? '0'
                              : '${row.payments.length} '
                                  '(${row.activePaymentCount} activos / '
                                  '${row.cancelledPaymentCount} cancelados)',
                        ),
                      ),
                      DataCell(Text(
                        row.hadReadyTimestamp
                            ? 'Tuvo readyAt'
                            : row.hadCookingTimestamp
                                ? 'Entró a preparación'
                                : row.passedThroughKitchen
                                    ? 'Enviada'
                                    : 'No',
                      )),
                      DataCell(Text(row.fullOrderCancelled ? 'Sí' : 'No')),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: Text(
                            row.reasonLabel,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Text(
                            row.productsLabel,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  List<CancellationCashAuditRow> _filterRows(
    List<CancellationCashAuditRow> rows,
  ) {
    final query = _queryController.text.trim().toLowerCase();
    return rows.where((row) {
      if (_employee != 'all' && !row.initiatedBy(_employee)) return false;
      if (_onlyNoPayment && !row.hasNoPaymentRecord) return false;
      if (_onlyFullOrder && !row.fullOrderCancelled) return false;
      if (_onlyKitchen && !row.passedThroughKitchen) return false;
      if (query.isNotEmpty) {
        final haystack = [
          row.businessDate,
          row.folio,
          row.order.displayName,
          row.initiatedByLabel,
          row.acceptedByLabel,
          row.reasonLabel,
          row.productsLabel,
          row.order.id,
        ].join(' ').toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  List<CancellationCashAuditDay> _employeeDays(
    List<CancellationCashAuditDay> days,
  ) {
    final start = widget.startBusinessDate;
    final end = widget.endBusinessDate;
    return days.where((day) {
      if (day.businessDate.compareTo(start) < 0 ||
          day.businessDate.compareTo(end) > 0) {
        return false;
      }
      return true;
    }).toList();
  }

  void _ensureReconciliationDate(List<CancellationCashAuditDay> days) {
    if (days.isEmpty) {
      _reconciliationDate = null;
      return;
    }
    if (_reconciliationDate != null &&
        days.any((day) => day.businessDate == _reconciliationDate)) {
      return;
    }
    final withShortage = days.where((day) => day.shortage > 0).toList();
    _reconciliationDate = withShortage.isNotEmpty
        ? withShortage.first.businessDate
        : days.first.businessDate;
  }

  Future<void> _export(List<CancellationCashAuditRow> rows) async {
    const headers = [
      'businessDate',
      'cancelledAt',
      'folio',
      'orderId',
      'mesaPedido',
      'initiatedBy',
      'acceptedBy',
      'cancelledAmount',
      'cancelledQty',
      'fullOrderCancelled',
      'paymentDocuments',
      'activePayments',
      'cancelledPayments',
      'passedThroughKitchen',
      'hadCookingTimestamp',
      'hadReadyTimestamp',
      'reason',
      'products',
    ];

    final csvRows = <List<String>>[
      headers,
      ...rows.map((row) => [
            row.businessDate,
            row.cancelledAt?.toIso8601String() ?? '',
            row.folio,
            row.order.id,
            row.order.displayName,
            row.initiatedByLabel,
            row.acceptedByLabel,
            row.cancelledAmount.toStringAsFixed(2),
            '${row.cancelledQty}',
            row.fullOrderCancelled ? 'true' : 'false',
            '${row.payments.length}',
            '${row.activePaymentCount}',
            '${row.cancelledPaymentCount}',
            row.passedThroughKitchen ? 'true' : 'false',
            row.hadCookingTimestamp ? 'true' : 'false',
            row.hadReadyTimestamp ? 'true' : 'false',
            row.reasonLabel,
            row.productsLabel,
          ]),
    ];

    final content = csvRows
        .map((row) => row.map(_csvCell).join(','))
        .join('\r\n');
    final message = await exportCsvFile(
      fileName:
          'tacopos-auditoria-cancelaciones-faltantes-${widget.startBusinessDate}-${widget.endBusinessDate}.csv',
      content: content,
    );
    if (!mounted) return;
    showAppSnackBar(
      context,
      message,
      type: AppSnackBarType.success,
    );
  }
}

class _AuditMetric extends StatelessWidget {
  const _AuditMetric({
    required this.label,
    required this.value,
    required this.detail,
    this.accent = BrandColors.textPrimary,
  });

  final String label;
  final String value;
  final String detail;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: GlassPanel(
        padding: const EdgeInsets.all(14),
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
                color: accent,
                fontSize: 24,
                fontWeight: FontWeight.w900,
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

class _InlineValue extends StatelessWidget {
  const _InlineValue({
    required this.label,
    required this.value,
    this.accent = BrandColors.textPrimary,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: BrandColors.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BrandColors.glassBorder),
      ),
      child: Column(
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
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 17,
            ),
          ),
        ],
      ),
    );
  }
}

Widget _moneyCell(
  double value, {
  bool danger = false,
  bool warning = false,
}) {
  final color = danger
      ? BrandColors.danger
      : warning
          ? BrandColors.accentYellow
          : BrandColors.textPrimary;
  return Text(
    _money(value),
    style: TextStyle(color: color, fontWeight: FontWeight.w900),
  );
}

String _money(double value) => NumberFormat.currency(
      locale: 'es_MX',
      symbol: r'$',
      decimalDigits: 2,
    ).format(value);

String _signedMoney(double value) {
  final sign = value > 0 ? '+' : '';
  return '$sign${_money(value)}';
}

String _time(DateTime? value) {
  if (value == null) return '--:--';
  return DateFormat('HH:mm:ss').format(value);
}

double _parseMoney(String value) {
  final clean = value.replaceAll(',', '').replaceAll(r'$', '').trim();
  return double.tryParse(clean) ?? 0;
}

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

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
