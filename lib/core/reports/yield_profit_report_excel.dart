import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import 'yield_profit_report.dart';

List<int> buildYieldProfitWorkbook({
  required YieldProfitReportBundle bundle,
  required String restaurantName,
  required String branchName,
  DateTime? generatedAt,
}) {
  final generated = generatedAt ?? DateTime.now();
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'Resumen');
  _summary(excel['Resumen'], bundle, restaurantName, branchName, generated);
  _products(excel['Productos'], bundle);
  _ingredients(excel['Ingredientes'], bundle);
  _recipes(excel['Recetas'], bundle);
  _yields(excel['Rendimientos'], bundle);
  _purchases(excel['Compras utilizadas'], bundle);
  _productsWithoutRecipe(excel['Productos sin receta'], bundle);
  _ingredientsWithoutCost(excel['Ingredientes sin costo'], bundle);
  excel.setDefaultSheet('Resumen');
  final bytes = excel.encode();
  if (bytes == null) throw StateError('No se pudo generar el archivo Excel.');
  return _addSheetControls(bytes, excel.tables.keys.length);
}

void _summary(
  Sheet sheet,
  YieldProfitReportBundle bundle,
  String restaurant,
  String branch,
  DateTime generated,
) {
  _header(sheet, ['RENDIMIENTO TEORICO Y UTILIDAD', 'Valor']);
  _rows(sheet, [
    ['Restaurante', restaurant],
    ['Sucursal', branch],
    [
      'Periodo operativo',
      '${bundle.key.startBusinessDate} al ${bundle.key.endBusinessDate}',
    ],
    ['Fecha de generacion', DateFormat('dd/MM/yyyy HH:mm').format(generated)],
    [
      'Aviso',
      'Resultados estimados; no representan inventario, consumo o merma real.',
    ],
    ['Venta neta', bundle.report.netSales],
    ['Costo teorico de ingredientes', bundle.report.theoreticalIngredientCost],
    ['Utilidad bruta teorica', bundle.report.theoreticalGrossProfit],
    ['Margen bruto teorico %', bundle.report.theoreticalGrossMarginPercent],
    ['Kg crudos estimados', bundle.report.rawEstimatedKilograms],
    ['Productos sin receta', bundle.report.productsWithoutRecipe],
    ['Ingredientes sin costo', bundle.report.ingredientsWithoutCost],
    [
      'Recetas pendientes de validacion',
      bundle.report.recipesPendingValidation,
    ],
  ]);
  _widths(sheet, [38, 72]);
}

void _products(Sheet sheet, YieldProfitReportBundle bundle) {
  _header(sheet, [
    'Producto',
    'Categoria',
    'Unidades',
    'Venta bruta',
    'Descuento asignado',
    'Venta neta',
    'Costo unitario teorico',
    'Costo teorico total',
    'Utilidad bruta teorica',
    'Margen bruto %',
    'Estado receta',
  ]);
  for (final row in bundle.report.products) {
    _rows(sheet, [
      [
        row.productName,
        row.categoryName,
        row.unitsSold,
        row.grossSales,
        row.discountAllocated,
        row.netSales,
        row.unitCost ?? '',
        row.totalCost ?? '',
        row.grossProfit ?? '',
        row.grossMarginPercent ?? '',
        !row.hasRecipe
            ? 'Sin receta'
            : row.hasCompleteCost
            ? row.recipe!.needsInternalValidation
                  ? 'Pendiente de validacion'
                  : 'Validada'
            : 'Costo incompleto: ${row.missingCostIngredients.join(', ')}',
      ],
    ]);
  }
  _widths(sheet, [30, 22, 12, 18, 20, 18, 24, 22, 24, 18, 38]);
}

void _ingredients(Sheet sheet, YieldProfitReportBundle bundle) {
  _header(sheet, [
    'Ingrediente',
    'Unidad compra',
    'Rendimiento %',
    'Reduccion estimada %',
    'Cantidad cocida teorica',
    'Cantidad cruda estimada',
    'Costo promedio base',
    'Costo teorico consumido',
    'Compras del periodo',
    'Diferencia estimada',
    'Estado',
  ]);
  for (final row in bundle.report.ingredients) {
    _rows(sheet, [
      [
        row.stockItemName,
        row.purchaseUnit,
        row.profile?.cookingYieldPercent ?? '',
        row.profile?.estimatedReductionPercent ?? '',
        row.cookedQuantity,
        row.rawEstimatedQuantity,
        row.cost?.costPerBaseUnit ?? '',
        row.theoreticalConsumedCost ?? '',
        row.purchasedInPeriod,
        row.estimatedDifference,
        row.cost == null ? 'Sin costo registrado' : row.cost!.source,
      ],
    ]);
  }
  _widths(sheet, [28, 18, 18, 24, 26, 26, 22, 24, 22, 22, 34]);
}

void _recipes(Sheet sheet, YieldProfitReportBundle bundle) {
  _header(sheet, [
    'Producto',
    'Ingrediente',
    'Cantidad',
    'Unidad',
    'Etapa',
    'Cantidad base',
    'Version',
    'Estimada',
    'Pendiente validacion',
    'Notas',
  ]);
  for (final recipe in bundle.recipes) {
    for (final ingredient in recipe.ingredients) {
      _rows(sheet, [
        [
          recipe.productName,
          ingredient.stockItemName,
          ingredient.quantity,
          ingredient.unit,
          ingredient.inputStage,
          ingredient.baseQuantity,
          recipe.version,
          recipe.isEstimated ? 'Si' : 'No',
          recipe.needsInternalValidation ? 'Si' : 'No',
          recipe.notes,
        ],
      ]);
    }
  }
  _widths(sheet, [30, 28, 14, 14, 20, 18, 12, 14, 22, 46]);
}

void _yields(Sheet sheet, YieldProfitReportBundle bundle) {
  _header(sheet, [
    'Ingrediente',
    'Rendimiento %',
    'Tacos por kg (30 g)',
    'Gringas por kg (60 g)',
    'Reduccion estimada %',
    'Fuente',
    'Estimado',
    'Pendiente validacion',
  ]);
  for (final profile in bundle.profiles) {
    _rows(sheet, [
      [
        profile.stockItemName,
        profile.cookingYieldPercent,
        theoreticalUnitsPerRawKg(
          cookingYieldRate: profile.cookingYieldRate,
          cookedPortionGrams: 30,
        ),
        theoreticalUnitsPerRawKg(
          cookingYieldRate: profile.cookingYieldRate,
          cookedPortionGrams: 60,
        ),
        profile.estimatedReductionPercent,
        profile.sourceLabel,
        profile.isEstimated ? 'Si' : 'No',
        profile.needsInternalValidation ? 'Si' : 'No',
      ],
    ]);
  }
  _widths(sheet, [28, 18, 22, 24, 24, 52, 14, 22]);
}

void _purchases(Sheet sheet, YieldProfitReportBundle bundle) {
  _header(sheet, [
    'Compra',
    'Fecha',
    'Proveedor',
    'Ingrediente',
    'Cantidad',
    'Unidad',
    'Costo unitario final',
    'Costo final',
    'Cantidad base',
  ]);
  for (final line in bundle.purchaseLines) {
    _rows(sheet, [
      [
        line.purchaseId,
        DateFormat('dd/MM/yyyy').format(line.purchaseDate),
        line.supplierName,
        line.stockItemName,
        line.quantity,
        line.unit,
        line.unitCost,
        line.finalCost,
        line.baseQuantity,
      ],
    ]);
  }
  _widths(sheet, [26, 16, 26, 28, 14, 14, 22, 18, 18]);
}

void _productsWithoutRecipe(Sheet sheet, YieldProfitReportBundle bundle) {
  _header(sheet, ['Producto', 'Categoria', 'Unidades vendidas', 'Venta neta']);
  for (final row in bundle.report.products.where((row) => !row.hasRecipe)) {
    _rows(sheet, [
      [row.productName, row.categoryName, row.unitsSold, row.netSales],
    ]);
  }
  _widths(sheet, [32, 24, 20, 20]);
}

void _ingredientsWithoutCost(Sheet sheet, YieldProfitReportBundle bundle) {
  _header(sheet, ['Ingrediente', 'Productos relacionados', 'Estado']);
  for (final row in bundle.report.ingredients.where(
    (row) => row.cost == null,
  )) {
    _rows(sheet, [
      [
        row.stockItemName,
        row.usages.map((usage) => usage.productName).toSet().join(', '),
        'Sin costo registrado',
      ],
    ]);
  }
  _widths(sheet, [30, 56, 26]);
}

void _header(Sheet sheet, List<String> values) {
  sheet.appendRow(values.map(TextCellValue.new).toList());
  for (var index = 0; index < values.length; index++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: index, rowIndex: 0))
        .cellStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#292929'),
    );
  }
}

void _rows(Sheet sheet, List<List<Object>> rows) {
  for (final row in rows) {
    sheet.appendRow(row.map(_cell).toList());
  }
}

CellValue _cell(Object value) {
  if (value is int) return IntCellValue(value);
  if (value is double) return DoubleCellValue(value);
  return TextCellValue(value.toString());
}

void _widths(Sheet sheet, List<double> widths) {
  for (var index = 0; index < widths.length; index++) {
    sheet.setColumnWidth(index, widths[index]);
  }
}

List<int> _addSheetControls(List<int> bytes, int sheetCount) {
  final source = ZipDecoder().decodeBytes(bytes);
  final target = Archive();
  for (final file in source) {
    if (!file.isFile) {
      target.addFile(file);
      continue;
    }
    var content = List<int>.from(file.content as List<int>);
    final match = RegExp(
      r'xl/worksheets/sheet(\d+)\.xml',
    ).firstMatch(file.name);
    if (match != null && int.parse(match.group(1)!) <= sheetCount) {
      var xml = utf8.decode(content);
      const frozen =
          '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" '
          'topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
          '</sheetView></sheetViews>';
      final views = RegExp(r'<sheetViews>.*?</sheetViews>', dotAll: true);
      xml = views.hasMatch(xml)
          ? xml.replaceFirst(views, frozen)
          : xml.replaceFirst('<sheetFormatPr', '$frozen<sheetFormatPr');
      final dimension =
          RegExp(r'<dimension ref="([^"]+)"').firstMatch(xml)?.group(1) ?? 'A1';
      if (!xml.contains('<autoFilter')) {
        xml = xml.replaceFirst(
          '</sheetData>',
          '</sheetData><autoFilter ref="$dimension"/>',
        );
      }
      content = utf8.encode(xml);
    }
    target.addFile(ArchiveFile(file.name, content.length, content));
  }
  final encoded = ZipEncoder().encode(target);
  if (encoded == null) throw StateError('No se pudo finalizar el Excel.');
  return encoded;
}
