import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../../models/purchase_models.dart';
import 'finance_dashboard.dart';

List<int> buildFinanceDashboardWorkbook({
  required FinanceDashboardBundle bundle,
  required String restaurantName,
  required String branchName,
  DateTime? generatedAt,
}) {
  final generated = generatedAt ?? DateTime.now();
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'Resumen');
  _summarySheet(
    excel['Resumen'],
    bundle,
    restaurantName,
    branchName,
    generated,
  );
  _salesSheet(excel['Ventas'], bundle);
  _collectionsSheet(excel['Cobros'], bundle);
  _expensesSheet(excel['Gastos'], bundle);
  _purchasesSheet(excel['Facturas proveedor'], bundle);
  _supplierPaymentsSheet(excel['Pagos proveedores'], bundle);
  _supplierAccumulatedSheet(excel['Acumulado proveedor'], bundle);
  excel.setDefaultSheet('Resumen');
  final bytes = excel.encode();
  if (bytes == null) {
    throw StateError('No se pudo generar el archivo Excel.');
  }
  return bytes;
}

void _summarySheet(
  Sheet sheet,
  FinanceDashboardBundle bundle,
  String restaurantName,
  String branchName,
  DateTime generatedAt,
) {
  _title(sheet, 'REPORTE FINANCIERO');
  _textRows(sheet, [
    ['Restaurante', restaurantName],
    ['Sucursal', branchName],
    [
      'Periodo operativo',
      '${bundle.key.startBusinessDate} al ${bundle.key.endBusinessDate}',
    ],
    ['Fecha de generacion', DateFormat('dd/MM/yyyy HH:mm').format(generatedAt)],
  ]);
  sheet.appendRow(const []);
  _header(sheet, ['Indicador', 'Importe']);
  _moneyRows(sheet, [
    ('Venta', bundle.netSales),
    ('Ingreso real de cortes', bundle.realCollected),
    ('Tarjeta bruta de cortes', bundle.cardGrossCollected),
    ('Comision tarjeta', bundle.cardFees),
    ('Tarjeta neta de cortes', bundle.cardCollected),
    ('Monetario esperado bruto', bundle.expectedMonetaryGrossIncome),
    ('Monetario esperado neto', bundle.expectedMonetaryIncome),
    ('Faltantes de cortes', bundle.cashShortages),
    ('Sobrantes de cortes', bundle.cashOverages),
    ('Gastos', bundle.paidExpenses),
    ('Facturas proveedor', bundle.supplierInvoicesTotal),
    ('Pagado', bundle.supplierPaidTotal),
    ('Facturas pendientes', bundle.pendingSupplierInvoices),
    ('Resumen general', bundle.generalResult),
    ('Resumen de cobros', bundle.collectionsResult),
    ('Resultado operativo', bundle.operatingResult),
    ('Aportacion de socios', bundle.partnerContributions),
    ('Diferencia por conciliar', bundle.reconciliationDifference),
  ]);
  _widths(sheet, [28, 24]);
}

void _salesSheet(Sheet sheet, FinanceDashboardBundle bundle) {
  _title(sheet, 'VENTAS');
  _header(sheet, [
    'Fecha operativa',
    'Orden',
    'Venta si no hubiera descuento',
    'Venta sin descuento',
    'Venta con descuento',
    'Descuento aplicado',
    'Venta neta',
  ]);
  for (final row in bundle.salesOrders) {
    _append(
      sheet,
      [
        row.businessDate,
        row.order.id,
        row.grossSales,
        row.hasExplicitDiscount ? 0 : row.netSales,
        row.hasExplicitDiscount ? row.netSales : 0,
        row.discountTotal,
        row.netSales,
      ],
      moneyColumns: const {2, 3, 4, 5, 6},
    );
  }
  _append(
    sheet,
    [
      'TOTAL',
      bundle.salesOrders.length,
      bundle.grossSales,
      bundle.salesWithoutDiscount,
      bundle.salesWithDiscount,
      bundle.discounts,
      bundle.netSales,
    ],
    moneyColumns: const {2, 3, 4, 5, 6},
    total: true,
  );
  _widths(sheet, [18, 24, 28, 23, 23, 22, 20]);
}

void _collectionsSheet(Sheet sheet, FinanceDashboardBundle bundle) {
  _title(sheet, 'INGRESOS REALES DE CORTES');
  _header(sheet, [
    'Fecha operativa',
    'Corte',
    'Efectivo real',
    'Tarjeta bruta',
    'Comision tarjeta',
    'Tarjeta neta',
    'Plataforma / otros',
    'Ingreso real',
    'Monetario esperado bruto',
    'Monetario esperado neto',
    'Faltante',
    'Sobrante',
    'Fondo inicial',
    'Retiros aprobados',
    'Cerro',
    'Estatus',
  ]);
  for (final row in bundle.cashCutSummaries) {
    _append(
      sheet,
      [
        row.businessDate,
        row.session.id,
        row.cashReceived,
        row.cardGrossReceived,
        row.cardFeeAbsorbed,
        row.cardReceived,
        row.platformReceived + row.otherReceived,
        row.actualReceived,
        row.expectedMonetaryGrossIncome,
        row.expectedMonetaryIncome,
        row.shortage,
        row.overage,
        row.openingFloat,
        row.approvedWithdrawals,
        row.session.closedByEmployeeName ?? '',
        row.session.status,
      ],
      moneyColumns: const {2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12},
    );
  }
  _append(
    sheet,
    [
      'TOTAL',
      bundle.cashCutSummaries.length,
      bundle.cashCollected,
      bundle.cardGrossCollected,
      bundle.cardFees,
      bundle.cardCollected,
      bundle.platformCollected + bundle.otherCollected,
      bundle.realCollected,
      bundle.expectedMonetaryGrossIncome,
      bundle.expectedMonetaryIncome,
      bundle.cashShortages,
      bundle.cashOverages,
      '',
      '',
      '',
      '',
    ],
    moneyColumns: const {2, 3, 4, 5, 6, 7, 8, 9, 10},
    total: true,
  );
  _widths(sheet, [
    18,
    24,
    18,
    18,
    18,
    18,
    22,
    18,
    24,
    24,
    18,
    18,
    18,
    18,
    24,
    16,
  ]);
}

void _expensesSheet(Sheet sheet, FinanceDashboardBundle bundle) {
  _title(sheet, 'GASTOS');
  _header(sheet, [
    'Fecha operativa',
    'Concepto',
    'Monto',
    'Estatus',
    'Registro',
    'Sucursal',
  ]);
  for (final row in bundle.expenses) {
    _append(
      sheet,
      [
        row.businessDate,
        row.reason,
        row.amount,
        financeExpenseStatusLabel(financeExpenseStatus(row)),
        row.requestedByEmployeeName,
        row.branchName,
      ],
      moneyColumns: const {2},
    );
  }
  _append(
    sheet,
    ['TOTAL PAGADO', '', bundle.paidExpenses, '', '', ''],
    moneyColumns: const {2},
    total: true,
  );
  _widths(sheet, [18, 40, 18, 18, 24, 22]);
}

void _purchasesSheet(Sheet sheet, FinanceDashboardBundle bundle) {
  _title(sheet, 'FACTURAS DE PROVEEDOR');
  _header(sheet, [
    'Fecha operativa',
    'Proveedor',
    'Documento',
    'Concepto / nota',
    'Vencimiento',
    'Total facturado',
    'Total pagado',
    'Saldo pendiente',
    'Estatus',
    'Registro',
  ]);
  for (final row in bundle.purchases) {
    _append(
      sheet,
      [
        financePurchaseBusinessDate(row),
        row.supplierName,
        row.folio,
        row.notes,
        row.dueDate == null
            ? ''
            : DateFormat('dd/MM/yyyy').format(row.dueDate!),
        row.total,
        row.paidTotal,
        financePurchaseBalance(row),
        financePurchaseStatus(row),
        row.createdByEmployeeName,
      ],
      moneyColumns: const {5, 6, 7},
    );
  }
  _append(
    sheet,
    [
      'TOTAL',
      '',
      '',
      '',
      '',
      bundle.supplierInvoicesTotal,
      '',
      bundle.pendingSupplierInvoices,
      '',
      '',
    ],
    moneyColumns: const {5, 7},
    total: true,
  );
  _widths(sheet, [18, 28, 20, 40, 18, 20, 20, 20, 18, 24]);
}

void _supplierPaymentsSheet(Sheet sheet, FinanceDashboardBundle bundle) {
  _title(sheet, 'PAGOS A PROVEEDORES');
  _header(sheet, [
    'Fecha operativa',
    'Proveedor',
    'Forma de pago',
    'Documento relacionado',
    'Monto',
    'Comentario',
    'Registro',
    'Estatus',
  ]);
  for (final row in bundle.supplierPayments) {
    _append(
      sheet,
      [
        financeSupplierPaymentBusinessDate(row),
        row.supplierName,
        financeSupplierPaymentMethodLabel(row.method),
        row.purchaseFolio,
        row.amount,
        row.notes,
        row.createdByEmployeeName,
        row.status,
      ],
      moneyColumns: const {4},
    );
  }
  _append(
    sheet,
    ['TOTAL', '', '', '', bundle.supplierPaidTotal, '', '', ''],
    moneyColumns: const {4},
    total: true,
  );
  _widths(sheet, [18, 28, 22, 24, 18, 40, 24, 16]);
}

void _supplierAccumulatedSheet(Sheet sheet, FinanceDashboardBundle bundle) {
  _title(sheet, 'ACUMULADO POR PROVEEDOR');
  _header(sheet, [
    'Proveedor',
    'Documentos',
    'Total facturado',
    'Total pagado en facturas',
    'Pagado en el periodo',
    'Saldo pendiente',
  ]);
  final rows = [...bundle.supplierRows]
    ..sort((a, b) => b.paidInPeriod.compareTo(a.paidInPeriod));
  for (final row in rows) {
    _append(
      sheet,
      [
        row.supplierName,
        row.documents,
        row.invoiced,
        row.paidOnInvoices,
        row.paidInPeriod,
        row.balance,
      ],
      moneyColumns: const {2, 3, 4, 5},
    );
  }
  _append(
    sheet,
    [
      'TOTAL',
      bundle.purchases.length,
      bundle.supplierInvoicesTotal,
      '',
      bundle.supplierPaidTotal,
      bundle.pendingSupplierInvoices,
    ],
    moneyColumns: const {2, 4, 5},
    total: true,
  );
  _widths(sheet, [30, 16, 20, 24, 22, 20]);
}

void _title(Sheet sheet, String title) {
  sheet.appendRow([TextCellValue(title)]);
  sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
      .cellStyle = CellStyle(
    bold: true,
    fontSize: 16,
    fontColorHex: ExcelColor.fromHexString('#F4B400'),
    backgroundColorHex: ExcelColor.fromHexString('#111111'),
  );
  sheet.setRowHeight(0, 26);
}

void _header(Sheet sheet, List<String> values) {
  final rowIndex = sheet.maxRows;
  sheet.appendRow(values.map(TextCellValue.new).toList());
  for (var column = 0; column < values.length; column++) {
    sheet
        .cell(
          CellIndex.indexByColumnRow(columnIndex: column, rowIndex: rowIndex),
        )
        .cellStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#292929'),
      horizontalAlign: HorizontalAlign.Center,
    );
  }
  sheet.setRowHeight(rowIndex, 22);
}

void _textRows(Sheet sheet, List<List<String>> rows) {
  for (final row in rows) {
    sheet.appendRow(row.map(TextCellValue.new).toList());
  }
}

void _moneyRows(Sheet sheet, List<(String, double)> rows) {
  for (final row in rows) {
    _append(sheet, [row.$1, row.$2], moneyColumns: const {1});
  }
}

void _append(
  Sheet sheet,
  List<Object?> values, {
  Set<int> moneyColumns = const {},
  bool total = false,
}) {
  final rowIndex = sheet.maxRows;
  sheet.appendRow(values.map(_cellValue).toList());
  for (var column = 0; column < values.length; column++) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: column, rowIndex: rowIndex),
    );
    if (moneyColumns.contains(column)) {
      cell.cellStyle = CellStyle(
        bold: total,
        numberFormat: const CustomNumericNumFormat(
          formatCode: r'$#,##0.00;[Red]-$#,##0.00',
        ),
      );
    } else if (total) {
      cell.cellStyle = CellStyle(bold: true);
    }
  }
}

CellValue _cellValue(Object? value) {
  return switch (value) {
    int number => IntCellValue(number),
    num number => DoubleCellValue(number.toDouble()),
    _ => TextCellValue(value?.toString() ?? ''),
  };
}

void _widths(Sheet sheet, List<double> widths) {
  for (var index = 0; index < widths.length; index++) {
    sheet.setColumnWidth(index, widths[index]);
  }
}

String financeExpenseStatusLabel(FinanceExpenseStatus status) {
  return switch (status) {
    FinanceExpenseStatus.paid => 'Pagado',
    FinanceExpenseStatus.pending => 'Pendiente',
    FinanceExpenseStatus.cancelled => 'Cancelado',
  };
}

String financePurchaseStatus(SupplierPurchase purchase) {
  if (purchase.isCancelled) return 'Cancelada';
  if (financePurchaseBalance(purchase) <= financeMoneyTolerance) {
    return 'Pagada';
  }
  if (purchase.dueDate != null && purchase.dueDate!.isBefore(DateTime.now())) {
    return 'Vencida';
  }
  return purchase.paidTotal > financeMoneyTolerance ? 'Parcial' : 'Pendiente';
}
