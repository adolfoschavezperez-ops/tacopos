import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/cash/cash_session_timing.dart';
import '../../core/reports/cash_schedule_report.dart';
import '../../core/reports/cash_schedule_report_excel.dart';
import '../../core/theme/brand_colors.dart';
import '../../models/cash_session.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/binary_exporter.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';

class CashStatusDashboardPanel extends StatefulWidget {
  const CashStatusDashboardPanel({
    super.key,
    required this.repository,
    required this.branchId,
  });

  final TacoPosRepository repository;
  final String branchId;

  @override
  State<CashStatusDashboardPanel> createState() =>
      _CashStatusDashboardPanelState();
}

class _CashStatusDashboardPanelState extends State<CashStatusDashboardPanel> {
  late Stream<List<CashSession>> _stream;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _stream = widget.repository.watchCashSessions();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant CashStatusDashboardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.branchId != widget.branchId) {
      _stream = widget.repository.watchCashSessions();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CashSession>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingPanel(message: 'Consultando estado de caja...');
        }
        if (snapshot.hasError) {
          return const GlassPanel(
            child: Text('No se pudo consultar el estado actual de caja.'),
          );
        }
        final sessions = snapshot.data ?? const <CashSession>[];
        final open = sessions.where((session) => session.isOpen).firstOrNull;
        if (open != null) return _openPanel(open);
        final closed = [...sessions]
          ..sort((a, b) {
            final aDate =
                a.closedAt ?? a.openedAt ?? a.createdAt ?? DateTime(0);
            final bDate =
                b.closedAt ?? b.openedAt ?? b.createdAt ?? DateTime(0);
            return bDate.compareTo(aDate);
          });
        return _closedPanel(closed.firstOrNull);
      },
    );
  }

  Widget _openPanel(CashSession session) {
    final openedAt = reliableCashSessionOpenedAt(session);
    final opening = openedAt == null
        ? 'Apertura no registrada'
        : formatCashLocalTime(openedAt);
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      borderColor: BrandColors.success.withValues(alpha: 0.42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_open_outlined, color: BrandColors.success),
              SizedBox(width: 9),
              Text(
                'Caja abierta',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 28,
            runSpacing: 12,
            children: [
              _CashStatusDatum(
                label: 'Día operativo',
                value: formatBusinessDate(session.businessDate),
              ),
              _CashStatusDatum(label: 'Hora de apertura', value: opening),
              _CashStatusDatum(
                label: 'Abrió',
                value: _employeeLabel(session.openedByEmployeeName),
              ),
              _CashStatusDatum(
                label: 'Tiempo abierta',
                value: formatCashDuration(
                  cashSessionDuration(session, now: DateTime.now()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _closedPanel(CashSession? session) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_outline, color: BrandColors.textMuted),
              SizedBox(width: 9),
              Text(
                'Caja cerrada',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (session == null)
            const Text(
              'No hay sesiones de caja registradas para esta sucursal.',
              style: TextStyle(color: BrandColors.textMuted),
            )
          else
            Wrap(
              spacing: 28,
              runSpacing: 12,
              children: [
                _CashStatusDatum(
                  label: 'Último día operativo',
                  value: formatBusinessDate(session.businessDate),
                ),
                _CashStatusDatum(
                  label: 'Apertura',
                  value: reliableCashSessionOpenedAt(session) == null
                      ? 'Apertura no registrada'
                      : formatCashLocalTime(
                          reliableCashSessionOpenedAt(session),
                        ),
                ),
                _CashStatusDatum(
                  label: 'Abrió',
                  value: _employeeLabel(session.openedByEmployeeName),
                ),
                _CashStatusDatum(
                  label: 'Corte realizado',
                  value: reliableCashSessionClosedAt(session) == null
                      ? 'Cierre no registrado'
                      : formatCashLocalTime(
                          reliableCashSessionClosedAt(session),
                        ),
                ),
                _CashStatusDatum(
                  label: 'Cerró',
                  value: _employeeLabel(session.closedByEmployeeName ?? ''),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CashStatusDatum extends StatelessWidget {
  const _CashStatusDatum({required this.label, required this.value});

  final String label;
  final String value;

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
              color: BrandColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class CashScheduleReportView extends StatefulWidget {
  const CashScheduleReportView({
    super.key,
    required this.repository,
    required this.branchId,
  });

  final TacoPosRepository repository;
  final String branchId;

  @override
  State<CashScheduleReportView> createState() => _CashScheduleReportViewState();
}

class _CashScheduleReportViewState extends State<CashScheduleReportView> {
  late DateTime _weekStart;
  late Future<CashScheduleReport> _future;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _weekStart = startOfCashScheduleWeek(DateTime.now());
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant CashScheduleReportView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchId != widget.branchId ||
        oldWidget.repository != widget.repository) {
      _future = _load();
    }
  }

  String get _startBusinessDate => businessDateKey(_weekStart);
  String get _endBusinessDate =>
      businessDateKey(_weekStart.add(const Duration(days: 6)));

  Future<CashScheduleReport> _load({bool forceRefresh = false}) async {
    final load = await widget.repository.getCashScheduleSessions(
      startBusinessDate: _startBusinessDate,
      endBusinessDate: _endBusinessDate,
      forceRefresh: forceRefresh,
    );
    return buildCashScheduleReport(
      weekStart: _weekStart,
      sessions: load.sessions,
    );
  }

  void _setWeek(DateTime weekStart, {bool forceRefresh = false}) {
    setState(() {
      _weekStart = startOfCashScheduleWeek(weekStart);
      _future = _load(forceRefresh: forceRefresh);
    });
  }

  Future<void> _pickWeek() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _weekStart,
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      helpText: 'Selecciona una fecha de la semana',
    );
    if (picked != null && mounted) _setWeek(picked);
  }

  Future<void> _export(CashScheduleReport report) async {
    if (_exporting || !kIsWeb) return;
    setState(() => _exporting = true);
    try {
      await Future<void>.delayed(Duration.zero);
      final session = AppSession.instance;
      final bytes = buildCashScheduleWorkbook(
        report: report,
        restaurantName: session.currentRestaurantName,
        branchName: session.currentBranchName,
      );
      final message = await exportBinaryFile(
        fileName:
            'Horarios_Caja_${_fileToken(session.currentBranchName)}_'
            '${_startBusinessDate}_$_endBusinessDate.xlsx',
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (mounted) showAppSnackBar(context, message);
    } catch (error) {
      if (mounted) {
        showAppSnackBar(
          context,
          'No se pudo exportar el reporte: $error',
          type: AppSnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CashScheduleReport>(
      future: _future,
      builder: (context, snapshot) {
        final report = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(report),
            const SizedBox(height: 14),
            if (snapshot.hasError)
              const EmptyState(
                icon: Icons.error_outline,
                title: 'No se pudo cargar el reporte',
                message: 'Revisa la conexión e intenta actualizar nuevamente.',
              )
            else if (report == null)
              const LoadingPanel(
                message: 'Cargando horarios de apertura y cierre...',
              )
            else ...[
              _CashScheduleSummaryPanel(summary: report.summary),
              const SizedBox(height: 14),
              _CashScheduleTable(report: report),
            ],
          ],
        );
      },
    );
  }

  Widget _toolbar(CashScheduleReport? report) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.access_time_outlined,
                color: BrandColors.accentYellow,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  cashScheduleWeekLabel(_weekStart),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: report == null || _exporting
                    ? null
                    : () => _export(report),
                icon: _exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(_exporting ? 'Generando...' : 'Exportar a Excel'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    _setWeek(_weekStart.subtract(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_left),
                label: const Text('Semana anterior'),
              ),
              OutlinedButton.icon(
                onPressed: _pickWeek,
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Seleccionar semana'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _setWeek(_weekStart.add(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_right),
                label: const Text('Semana siguiente'),
              ),
              TextButton.icon(
                onPressed: () => _setWeek(DateTime.now()),
                icon: const Icon(Icons.today_outlined),
                label: const Text('Semana actual'),
              ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: () => _setWeek(_weekStart, forceRefresh: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CashScheduleSummaryPanel extends StatelessWidget {
  const _CashScheduleSummaryPanel({required this.summary});

  final CashScheduleSummary summary;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('Días con apertura', '${summary.daysWithOpening}'),
      ('Días sin operación', '${summary.daysWithoutOperation}'),
      ('Apertura promedio', summary.averageOpeningLabel),
      ('Cierre promedio', summary.averageClosingLabel),
      ('Duración promedio', summary.averageDurationLabel),
      ('Pendientes de cierre', '${summary.pendingSessions}'),
    ];
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 14,
            children: metrics
                .map(
                  (metric) => SizedBox(
                    width: 175,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metric.$1,
                          style: const TextStyle(
                            color: BrandColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          metric.$2,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          if (summary.incompleteSessions > 0) ...[
            const SizedBox(height: 12),
            Text(
              '${summary.incompleteSessions} '
              '${summary.incompleteSessions == 1 ? 'sesión fue excluida' : 'sesiones fueron excluidas'} '
              'de los promedios por información incompleta.',
              style: const TextStyle(
                color: BrandColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CashScheduleTable extends StatelessWidget {
  const _CashScheduleTable({required this.report});

  final CashScheduleReport report;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 46,
          dataRowMinHeight: 48,
          dataRowMaxHeight: 72,
          horizontalMargin: 12,
          columnSpacing: 20,
          columns: const [
            DataColumn(label: Text('Día')),
            DataColumn(label: Text('Fecha operativa')),
            DataColumn(label: Text('Hora de apertura')),
            DataColumn(label: Text('Abrió')),
            DataColumn(label: Text('Hora del corte/cierre')),
            DataColumn(label: Text('Cerró')),
            DataColumn(label: Text('Duración')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Observaciones')),
            DataColumn(label: Text('Detalle')),
          ],
          rows: report.days.map((day) => _row(context, day)).toList(),
        ),
      ),
    );
  }

  DataRow _row(BuildContext context, CashScheduleDay day) {
    final session = day.singleSession;
    final multiple = day.hasMultipleSessions;
    final noOperation = !day.hasOperation;
    final opening = noOperation
        ? 'Sin apertura'
        : multiple
        ? '${day.sessions.length} sesiones'
        : cashScheduleOpeningLabel(session!);
    final closing = noOperation
        ? 'Sin cierre'
        : multiple
        ? '${day.sessions.length} sesiones'
        : cashScheduleClosingLabel(session!);
    final duration = session == null
        ? '—'
        : formatCashDuration(cashSessionDuration(session, now: DateTime.now()));
    final status = noOperation
        ? 'Sin operación'
        : multiple
        ? '${day.sessions.length} sesiones'
        : cashScheduleStatusLabel(session!);
    return DataRow(
      cells: [
        DataCell(Text(day.weekdayName)),
        DataCell(Text(formatBusinessDate(day.businessDate))),
        DataCell(Text(opening)),
        DataCell(
          Text(
            session == null
                ? '—'
                : _employeeLabel(session.openedByEmployeeName),
          ),
        ),
        DataCell(Text(closing)),
        DataCell(
          Text(
            session == null
                ? '—'
                : _employeeLabel(session.closedByEmployeeName ?? ''),
          ),
        ),
        DataCell(Text(duration)),
        DataCell(Text(status)),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 270),
            child: Text(cashScheduleObservation(day)),
          ),
        ),
        DataCell(
          IconButton(
            tooltip: 'Ver detalle',
            onPressed: noOperation
                ? null
                : () => _showCashScheduleDetail(context, day),
            icon: const Icon(Icons.visibility_outlined),
          ),
        ),
      ],
    );
  }
}

Future<void> _showCashScheduleDetail(
  BuildContext context,
  CashScheduleDay day,
) {
  final validDurations = day.sessions
      .map((session) => cashSessionDuration(session, now: DateTime.now()))
      .whereType<Duration>()
      .toList();
  final accumulatedDuration = validDurations.isEmpty
      ? null
      : validDurations.fold<Duration>(
          Duration.zero,
          (total, value) => total + value,
        );
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.point_of_sale_outlined,
                    color: BrandColors.accentYellow,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${day.weekdayName} ${formatBusinessDate(day.businessDate)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (day.hasMultipleSessions) ...[
                const SizedBox(height: 10),
                Text(
                  'Se encontraron varias sesiones de caja para el mismo día '
                  'operativo. Duración acumulada: '
                  '${formatCashDuration(accumulatedDuration)}.',
                  style: const TextStyle(
                    color: BrandColors.accentOrange,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Expanded(
                child: ListView.separated(
                  itemCount: day.sessions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _CashSessionDetail(
                    session: day.sessions[index],
                    index: day.sessions.length > 1 ? index + 1 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CashSessionDetail extends StatelessWidget {
  const _CashSessionDetail({required this.session, this.index});

  final CashSession session;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final duration = cashSessionDuration(session, now: DateTime.now());
    final fields = <(String, String)>[
      ('Día operativo', formatBusinessDate(session.businessDate)),
      ('Sucursal', session.branchName),
      ('Hora real de apertura', cashScheduleOpeningLabel(session)),
      (
        'Fecha calendario de apertura',
        formatCashLocalDate(
          reliableCashSessionOpenedAt(session) ??
              estimatedHistoricalCashSessionOpenedAt(session),
        ),
      ),
      ('Empleado que abrió', _employeeLabel(session.openedByEmployeeName)),
      ('Hora real de cierre', cashScheduleClosingLabel(session)),
      (
        'Fecha calendario de cierre',
        formatCashLocalDate(reliableCashSessionClosedAt(session)),
      ),
      (
        'Empleado que cerró',
        _employeeLabel(session.closedByEmployeeName ?? ''),
      ),
      ('Duración', formatCashDuration(duration)),
      ('Efectivo inicial', _money(session.openingCashAmount)),
      ('Efectivo contado', _money(session.countedCashAmount)),
      ('Terminal reportada', _money(session.terminalReportedAmount)),
      ('Faltante / sobrante', _signedMoney(session.netDifference)),
      ('Estatus', cashScheduleStatusLabel(session)),
      ('cashSessionId', _shortId(session.id)),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: BrandColors.glassBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (index != null) ...[
            Text(
              'Sesión $index',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: fields
                .map(
                  (field) => SizedBox(
                    width: 225,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          field.$1,
                          style: const TextStyle(
                            color: BrandColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          field.$2,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

String _employeeLabel(String value) {
  final clean = value.trim();
  return clean.isEmpty ? 'No registrado' : clean;
}

String _money(double value) => '\$${value.toStringAsFixed(2)}';

String _signedMoney(double value) {
  if (value.abs() < 0.005) return '\$0.00';
  final prefix = value > 0 ? '+' : '-';
  return '$prefix\$${value.abs().toStringAsFixed(2)}';
}

String _shortId(String value) {
  final clean = value.trim();
  return clean.length <= 8 ? clean : clean.substring(0, 8);
}

String _fileToken(String value) {
  final token = value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return token.isEmpty ? 'Sucursal' : token;
}
