import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

import '../../models/cash_session.dart';
import '../cash/cash_session_timing.dart';
import 'cash_schedule_report.dart';

List<int> buildCashScheduleWorkbook({
  required CashScheduleReport report,
  required String restaurantName,
  required String branchName,
}) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'Horarios de caja');
  final detail = excel['Horarios de caja'];
  final detailRows = _writeScheduleSheet(detail, report);
  _writeSummarySheet(
    excel['Resumen semanal'],
    report,
    restaurantName: restaurantName,
    branchName: branchName,
  );
  excel.setDefaultSheet('Horarios de caja');
  final bytes = excel.encode();
  if (bytes == null) {
    throw StateError('No se pudo generar el archivo Excel.');
  }
  return _addScheduleSheetControls(bytes, lastRow: detailRows);
}

int _writeScheduleSheet(Sheet sheet, CashScheduleReport report) {
  const headers = [
    'Día',
    'Fecha operativa',
    'Fecha/hora de apertura',
    'Hora de apertura',
    'Abrió',
    'Fecha/hora de cierre',
    'Hora del corte',
    'Cerró',
    'Duración minutos',
    'Duración visible',
    'Estado',
    'Observaciones',
    'cashSessionId',
  ];
  _appendHeader(sheet, headers);

  for (final day in report.days) {
    if (day.sessions.isEmpty) {
      _appendScheduleRow(
        sheet,
        dayName: day.weekdayName,
        businessDate: day.date,
        session: null,
        observation: 'Sin operación',
      );
      continue;
    }
    for (final session in day.sessions) {
      _appendScheduleRow(
        sheet,
        dayName: day.weekdayName,
        businessDate: day.date,
        session: session,
        observation: day.hasMultipleSessions
            ? 'Se encontraron ${day.sessions.length} sesiones para el mismo '
                  'día operativo.'
            : cashScheduleObservation(day),
      );
    }
  }

  for (var column = 0; column < headers.length; column++) {
    sheet.setColumnAutoFit(column);
  }
  sheet.setColumnWidth(11, 48);
  sheet.setColumnWidth(12, 24);
  return sheet.maxRows;
}

void _appendScheduleRow(
  Sheet sheet, {
  required String dayName,
  required DateTime businessDate,
  required CashSession? session,
  required String observation,
}) {
  final opening = session == null
      ? null
      : reliableCashSessionOpenedAt(session) ??
            estimatedHistoricalCashSessionOpenedAt(session);
  final closing = session == null ? null : reliableCashSessionClosedAt(session);
  final openingLocal = opening == null ? null : mexicoCityDateTime(opening);
  final closingLocal = closing == null ? null : mexicoCityDateTime(closing);
  final duration = session == null
      ? null
      : cashSessionDuration(session, now: DateTime.now());
  final estimated =
      session != null &&
      reliableCashSessionOpenedAt(session) == null &&
      estimatedHistoricalCashSessionOpenedAt(session) != null;
  final rowIndex = sheet.maxRows;
  sheet.appendRow([
    TextCellValue(dayName),
    DateCellValue.fromDateTime(businessDate),
    if (openingLocal == null)
      TextCellValue('')
    else if (estimated)
      TextCellValue(
        '${formatCashLocalDate(opening)} ${formatCashLocalTime(opening)} '
        '(estimada)',
      )
    else
      DateTimeCellValue.fromDateTime(openingLocal),
    openingLocal == null
        ? TextCellValue('')
        : TimeCellValue.fromTimeOfDateTime(openingLocal),
    TextCellValue(
      session == null ? '' : _employeeName(session.openedByEmployeeName),
    ),
    closingLocal == null
        ? TextCellValue('')
        : DateTimeCellValue.fromDateTime(closingLocal),
    closingLocal == null
        ? TextCellValue('')
        : TimeCellValue.fromTimeOfDateTime(closingLocal),
    TextCellValue(
      session == null ? '' : _employeeName(session.closedByEmployeeName ?? ''),
    ),
    duration == null ? TextCellValue('') : IntCellValue(duration.inMinutes),
    TextCellValue(session == null ? '' : formatCashDuration(duration)),
    TextCellValue(
      session == null ? 'Sin operación' : cashScheduleStatusLabel(session),
    ),
    TextCellValue(observation),
    TextCellValue(session?.id ?? ''),
  ]);

  _setFormat(sheet, rowIndex, 1, 'dd/mm/yyyy');
  _setFormat(sheet, rowIndex, 2, 'dd/mm/yyyy hh:mm');
  _setFormat(sheet, rowIndex, 3, 'h:mm AM/PM');
  _setFormat(sheet, rowIndex, 5, 'dd/mm/yyyy hh:mm');
  _setFormat(sheet, rowIndex, 6, 'h:mm AM/PM');
}

void _writeSummarySheet(
  Sheet sheet,
  CashScheduleReport report, {
  required String restaurantName,
  required String branchName,
}) {
  sheet.appendRow([TextCellValue('RESUMEN SEMANAL')]);
  sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
          .cellStyle =
      _titleStyle;
  sheet.setRowHeight(0, 26);
  sheet.appendRow([
    TextCellValue('Restaurante'),
    TextCellValue(restaurantName),
  ]);
  sheet.appendRow([TextCellValue('Sucursal'), TextCellValue(branchName)]);
  sheet.appendRow([
    TextCellValue('Periodo'),
    TextCellValue(
      '${businessDateKey(report.weekStart)} al '
      '${businessDateKey(report.weekEnd)}',
    ),
  ]);
  sheet.appendRow(const []);
  _appendHeader(sheet, const ['Indicador', 'Valor']);
  final summary = report.summary;
  final rows = <(String, Object)>[
    ('Días con apertura', summary.daysWithOpening),
    ('Días sin operación', summary.daysWithoutOperation),
    ('Apertura promedio', summary.averageOpeningLabel),
    ('Cierre promedio', summary.averageClosingLabel),
    ('Duración promedio', summary.averageDurationLabel),
    ('Cajas pendientes', summary.pendingSessions),
    (
      'Sesiones excluidas por información incompleta',
      summary.incompleteSessions,
    ),
  ];
  for (final row in rows) {
    sheet.appendRow([
      TextCellValue(row.$1),
      row.$2 is int
          ? IntCellValue(row.$2 as int)
          : TextCellValue(row.$2.toString()),
    ]);
  }
  sheet.setColumnWidth(0, 44);
  sheet.setColumnWidth(1, 28);
}

void _appendHeader(Sheet sheet, List<String> headers) {
  final rowIndex = sheet.maxRows;
  sheet.appendRow(headers.map(TextCellValue.new).toList());
  for (var column = 0; column < headers.length; column++) {
    sheet
            .cell(
              CellIndex.indexByColumnRow(
                columnIndex: column,
                rowIndex: rowIndex,
              ),
            )
            .cellStyle =
        _headerStyle;
  }
  sheet.setRowHeight(rowIndex, 23);
}

void _setFormat(Sheet sheet, int row, int column, String formatCode) {
  final cell = sheet.cell(
    CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
  );
  if (cell.value is TextCellValue) return;
  cell.cellStyle = CellStyle(
    numberFormat: cell.value is TimeCellValue
        ? CustomTimeNumFormat(formatCode: formatCode)
        : CustomDateTimeNumFormat(formatCode: formatCode),
  );
}

String _employeeName(String value) {
  final clean = value.trim();
  return clean.isEmpty ? 'No registrado' : clean;
}

List<int> _addScheduleSheetControls(List<int> bytes, {required int lastRow}) {
  final source = ZipDecoder().decodeBytes(bytes);
  final target = Archive();
  for (final file in source) {
    if (!file.isFile) {
      target.addFile(file);
      continue;
    }
    var content = List<int>.from(file.content as List<int>);
    if (file.name == 'xl/worksheets/sheet1.xml') {
      var xml = utf8.decode(content);
      const frozenView =
          '<sheetViews><sheetView workbookViewId="0">'
          '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" '
          'state="frozen"/></sheetView></sheetViews>';
      final views = RegExp(r'<sheetViews>.*?</sheetViews>', dotAll: true);
      if (views.hasMatch(xml)) {
        xml = xml.replaceFirst(views, frozenView);
      } else {
        xml = xml.replaceFirst('<sheetFormatPr', '$frozenView<sheetFormatPr');
      }
      final filter = '<autoFilter ref="A1:M$lastRow"/>';
      if (!xml.contains('<autoFilter')) {
        xml = xml.replaceFirst('</sheetData>', '</sheetData>$filter');
      }
      content = utf8.encode(xml);
    }
    target.addFile(ArchiveFile(file.name, content.length, content));
  }
  final encoded = ZipEncoder().encode(target);
  if (encoded == null) {
    throw StateError('No se pudo finalizar el archivo Excel.');
  }
  return encoded;
}

final _titleStyle = CellStyle(
  bold: true,
  fontSize: 16,
  fontColorHex: ExcelColor.fromHexString('#F4B400'),
  backgroundColorHex: ExcelColor.fromHexString('#111111'),
);

final _headerStyle = CellStyle(
  bold: true,
  fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
  backgroundColorHex: ExcelColor.fromHexString('#292929'),
  horizontalAlign: HorizontalAlign.Center,
);
