import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/reports/predictive_consumption_audit.dart';
import '../../core/theme/brand_colors.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/csv_exporter.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';

class PredictiveConsumptionAuditView extends StatefulWidget {
  const PredictiveConsumptionAuditView({
    super.key,
    required this.repository,
    this.onExit,
  });

  final TacoPosRepository repository;
  final VoidCallback? onExit;

  @override
  State<PredictiveConsumptionAuditView> createState() =>
      _PredictiveConsumptionAuditViewState();
}

class _PredictiveConsumptionAuditViewState
    extends State<PredictiveConsumptionAuditView> {
  DateTime _investigationStart = DateTime(2026, 9, 28);
  late Future<PredictiveConsumptionAudit> _future;
  String _ingredientFilter = 'all';
  bool _onlyInvestigation = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = widget.repository.getPredictiveConsumptionAudit(
      investigationStart: _dateKey(_investigationStart),
      forceRefresh: true,
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  Future<void> _pickInvestigationStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _investigationStart,
      firstDate: DateTime(2026, 7, 1),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _investigationStart = picked;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PredictiveConsumptionAudit>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              GlassPanel(
                borderColor: BrandColors.danger,
                child: Text(
                  'No se pudo construir la auditoría predictiva: ${snapshot.error}',
                  style: const TextStyle(
                    color: BrandColors.danger,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const LoadingPanel(
            message:
                'Reconstruyendo meses de compras, ventas, cancelaciones y cortes...',
          );
        }

        final audit = snapshot.data!;
        final models = audit.models.where((model) {
          if (_ingredientFilter == 'all') return true;
          return model.definition.key == _ingredientFilter;
        }).toList();

        final recentCycles = <({PredictiveIngredientModel model, PredictiveConsumptionCycle cycle})>[];
        for (final model in models) {
          for (final cycle in model.cycles) {
            if (_onlyInvestigation && !cycle.isInvestigationPeriod) continue;
            recentCycles.add((model: model, cycle: cycle));
          }
        }
        recentCycles.sort(
          (a, b) => b.cycle.anomalyScore.compareTo(a.cycle.anomalyScore),
        );

        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 30),
          children: [
            _header(audit),
            const SizedBox(height: 14),
            _scopeNotice(audit),
            const SizedBox(height: 14),
            _summary(audit),
            const SizedBox(height: 14),
            _globalAnomalies(recentCycles),
            const SizedBox(height: 14),
            _modelQuality(models),
            const SizedBox(height: 14),
            ...models.expand(
              (model) => [
                _ingredientCard(model),
                const SizedBox(height: 14),
              ],
            ),
            _methodology(audit),
          ],
        );
      },
    );
  }

  Widget _header(PredictiveConsumptionAudit audit) {
    final ingredientOptions = <String, String>{
      'all': 'Todos los insumos',
      for (final model in audit.models)
        model.definition.key: model.definition.name,
    };

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 14,
            runSpacing: 12,
            children: [
              const SizedBox(
                width: 650,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Inteligencia de consumo · compras vs ventas',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Modelo robusto de reposición para Noe / Omar. Aprende porciones empíricas, '
                      'detecta ciclos atípicos y separa lo que podrían explicar cancelaciones que tocaron cocina.',
                      style: TextStyle(
                        color: BrandColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (widget.onExit != null)
                    OutlinedButton.icon(
                      onPressed: widget.onExit,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Volver al Backoffice'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _pickInvestigationStart,
                    icon: const Icon(Icons.flag_outlined),
                    label: Text(
                      'Investigar desde ${DateFormat('dd/MM/yyyy').format(_investigationStart)}',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Recalcular'),
                  ),
                  FilledButton.icon(
                    onPressed: audit.models.isEmpty ? null : () => _export(audit),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('CSV técnico'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(ingredientOptions.keys.join('|')),
                  initialValue: ingredientOptions.containsKey(_ingredientFilter)
                      ? _ingredientFilter
                      : 'all',
                  decoration: const InputDecoration(labelText: 'Insumo'),
                  items: ingredientOptions.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(
                    () => _ingredientFilter = value ?? 'all',
                  ),
                ),
              ),
              FilterChip(
                selected: _onlyInvestigation,
                label: const Text('Tablas: solo periodo investigado'),
                onSelected: (value) =>
                    setState(() => _onlyInvestigation = value),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scopeNotice(PredictiveConsumptionAudit audit) {
    final suppliers = audit.detectedSupplierNames.isEmpty
        ? 'No detectados'
        : audit.detectedSupplierNames.join(', ');
    return GlassPanel(
      borderColor: BrandColors.info.withValues(alpha: 0.40),
      padding: const EdgeInsets.all(14),
      child: Text(
        'Histórico analizado: ${audit.historyStart} → ${audit.historyEnd}. '
        'Proveedores detectados: $suppliers. '
        'La línea del ${audit.investigationStart} no entrena el patrón normal cuando existe '
        'histórico suficiente anterior: se usa como periodo de investigación.',
        style: const TextStyle(
          color: BrandColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _summary(PredictiveConsumptionAudit audit) {
    final high = audit.highAnomalyCycles;
    final recentExcessKg = audit.recentPositiveResidualWeightGrams / 1000;
    final highConfidence = audit.models
        .where((model) => model.confidence == 'Alta')
        .length;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _Metric(
          label: 'Modelos aprendidos',
          value: '${audit.models.length}',
          detail: '$highConfidence con confianza alta',
        ),
        _Metric(
          label: 'Compras objetivo',
          value: '${audit.purchaseLinesLoaded}',
          detail: 'Líneas Noe / Omar reconocidas',
        ),
        _Metric(
          label: 'Ventas usadas',
          value: '${audit.paidSaleLinesLoaded}',
          detail: 'Líneas pagadas/servidas registradas',
        ),
        _Metric(
          label: 'Canceladas en cocina',
          value: '${audit.cancelledKitchenLinesLoaded}',
          detail: 'Se calculan aparte, no como venta',
          accent: BrandColors.accentOrange,
        ),
        _Metric(
          label: 'Ciclos recientes altos',
          value: '$high',
          detail: 'Índice técnico ≥ 70',
          accent: high > 0 ? BrandColors.danger : BrandColors.success,
        ),
        _Metric(
          label: 'Exceso reciente no explicado',
          value: '${recentExcessKg.toStringAsFixed(2)} kg',
          detail: 'Solo residuos positivos en insumos por peso',
          accent:
              recentExcessKg > 0.5 ? BrandColors.danger : BrandColors.textPrimary,
        ),
      ],
    );
  }

  Widget _globalAnomalies(
    List<({PredictiveIngredientModel model, PredictiveConsumptionCycle cycle})>
        rows,
  ) {
    final visible = rows
        .where((entry) => entry.cycle.anomalyScore >= 35)
        .take(30)
        .toList();
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Radar de discrepancias',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text(
            'Ordenado por señal estadística. “Alto” no significa robo: significa que la compra '
            'se aleja del patrón histórico aprendido y amerita revisar inventario, merma, cancelaciones o ventas no registradas.',
            style: TextStyle(
              color: BrandColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No hay ciclos con señal material en el filtro actual.',
                  style: TextStyle(color: BrandColors.textMuted),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                dataRowMinHeight: 54,
                dataRowMaxHeight: 92,
                columns: const [
                  DataColumn(label: Text('Insumo')),
                  DataColumn(label: Text('Compra / ciclo')),
                  DataColumn(label: Text('Comprado')),
                  DataColumn(label: Text('Esperado ventas')),
                  DataColumn(label: Text('+ cancelaciones cocina')),
                  DataColumn(label: Text('Rango esperado 95%')),
                  DataColumn(label: Text('Residual final')),
                  DataColumn(label: Text('Equiv. unidades')),
                  DataColumn(label: Text('Residual %')),
                  DataColumn(label: Text('Z robusto')),
                  DataColumn(label: Text('Índice')),
                  DataColumn(label: Text('Faltante caja')),
                  DataColumn(label: Text('Lectura')),
                ],
                rows: visible.map((entry) {
                  final model = entry.model;
                  final cycle = entry.cycle;
                  return DataRow(
                    color: WidgetStateProperty.resolveWith((states) {
                      if (cycle.isHighAnomaly) {
                        return BrandColors.danger.withValues(alpha: 0.08);
                      }
                      if (cycle.isMediumAnomaly) {
                        return BrandColors.accentYellow.withValues(alpha: 0.06);
                      }
                      return null;
                    }),
                    cells: [
                      DataCell(Text(model.definition.name)),
                      DataCell(
                        Text(
                          '${cycle.purchaseDate}\n'
                          '${cycle.startBusinessDate} → ${cycle.endBusinessDate}',
                        ),
                      ),
                      DataCell(Text(_base(cycle.purchasedBase, model))),
                      DataCell(Text(_base(cycle.predictedPaidBase, model))),
                      DataCell(
                        Text(
                          _base(cycle.cancelledKitchenExplainedBase, model),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${_base(cycle.expectedLowBase, model)} – '
                          '${_base(cycle.expectedHighBase, model)}',
                        ),
                      ),
                      DataCell(
                        Text(
                          _signedBase(cycle.residualOperationalBase, model),
                          style: TextStyle(
                            color: cycle.residualOperationalBase > 0
                                ? BrandColors.danger
                                : BrandColors.success,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      DataCell(Text(_equivalentUnits(cycle, model))),
                      DataCell(Text(_percent(cycle.residualPercent * 100))),
                      DataCell(Text(cycle.robustZ.toStringAsFixed(2))),
                      DataCell(_score(cycle.anomalyScore)),
                      DataCell(Text(_money(cycle.shortageAmount))),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 430),
                          child: Text(
                            cycle.evidence,
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

  Widget _modelQuality(List<PredictiveIngredientModel> models) {
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Calidad del modelo',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Insumo')),
                DataColumn(label: Text('Proveedor')),
                DataColumn(label: Text('Ciclos entrenamiento')),
                DataColumn(label: Text('Alineación aprendida')),
                DataColumn(label: Text('R²')),
                DataColumn(label: Text('Error normalizado')),
                DataColumn(label: Text('Confianza')),
                DataColumn(label: Text('Base no explicada / día')),
              ],
              rows: models.map((model) {
                return DataRow(
                  cells: [
                    DataCell(Text(model.definition.name)),
                    DataCell(Text(model.supplierNames.join(', '))),
                    DataCell(Text('${model.trainingCycleCount}')),
                    DataCell(Text(_alignment(model.alignment))),
                    DataCell(Text(model.rSquared.toStringAsFixed(2))),
                    DataCell(Text(_percent(model.normalizedMae * 100))),
                    DataCell(_confidence(model.confidence)),
                    DataCell(Text(_base(model.baselineDailyBase, model))),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ingredientCard(PredictiveIngredientModel model) {
    final cycles = model.cycles
        .where((cycle) => !_onlyInvestigation || cycle.isInvestigationPeriod)
        .toList();
    return GlassPanel(
      borderColor: model.recentHighAnomalies > 0
          ? BrandColors.danger.withValues(alpha: 0.38)
          : null,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                model.definition.name,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  _pill('Confianza ${model.confidence}'),
                  _pill('${model.purchaseDayCount} días de compra'),
                  _pill(_alignment(model.alignment)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            model.baselineMode,
            style: const TextStyle(
              color: BrandColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Inline(
                label: 'Comprado histórico',
                value: _base(model.totalPurchasedBase, model),
              ),
              _Inline(
                label: 'Predicho por ventas',
                value: _base(model.totalPredictedPaidBase, model),
              ),
              _Inline(
                label: 'Explicable por cancelaciones cocina',
                value: _base(
                  model.totalCancelledKitchenExplainedBase,
                  model,
                ),
                accent: BrandColors.accentOrange,
              ),
              _Inline(
                label: 'Residual histórico',
                value: _signedBase(
                  model.totalResidualOperationalBase,
                  model,
                ),
              ),
              _Inline(
                label: 'Residual desde investigación',
                value: _signedBase(
                  model.recentResidualOperationalBase,
                  model,
                ),
                accent: model.recentResidualOperationalBase > 0
                    ? BrandColors.danger
                    : BrandColors.success,
              ),
              _Inline(
                label: 'Equivalente no explicado',
                value: _equivalentRecentUnits(model),
                accent: model.recentResidualOperationalBase > 0
                    ? BrandColors.danger
                    : BrandColors.success,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _coefficientTable(model),
          const SizedBox(height: 14),
          _cycleTable(model, cycles),
        ],
      ),
    );
  }

  Widget _coefficientTable(PredictiveIngredientModel model) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Consumo empírico aprendido por producto',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        Text(
          model.isWeight
              ? 'El modelo infiere gramos de compra cruda por unidad vendida. '
                  'En carnes también estima gramos cocidos usando el rendimiento configurado/semilla.'
              : 'El coeficiente representa unidades de compra por producto vendido.',
          style: const TextStyle(
            color: BrandColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (model.coefficients.isEmpty)
          const Text(
            'Sin coeficientes estables para mostrar.',
            style: TextStyle(color: BrandColors.textMuted),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                const DataColumn(label: Text('Producto')),
                DataColumn(
                  label: Text(
                    model.isWeight ? 'Crudo g / unidad' : 'Consumo / unidad',
                  ),
                ),
                if (model.isWeight)
                  const DataColumn(label: Text('Cocido estimado g / unidad')),
                const DataColumn(label: Text('Unidades entrenamiento')),
                const DataColumn(label: Text('Peso estadístico')),
                const DataColumn(label: Text('Plausibilidad')),
              ],
              rows: model.coefficients.map((coefficient) {
                return DataRow(
                  cells: [
                    DataCell(Text(coefficient.productName)),
                    DataCell(
                      Text(coefficient.rawBasePerUnit.toStringAsFixed(1)),
                    ),
                    if (model.isWeight)
                      DataCell(
                        Text(
                          coefficient.cookedBasePerUnit == null ||
                                  coefficient.cookedBasePerUnit!.isNaN
                              ? '-'
                              : coefficient.cookedBasePerUnit!
                                  .toStringAsFixed(1),
                        ),
                      ),
                    DataCell(
                      Text(coefficient.unitsInTraining.toStringAsFixed(0)),
                    ),
                    DataCell(
                      Text(
                        _percent(coefficient.shareOfTrainingUnits * 100),
                      ),
                    ),
                    DataCell(Text(coefficient.plausibility)),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _cycleTable(
    PredictiveIngredientModel model,
    List<PredictiveConsumptionCycle> cycles,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Ciclos de reposición',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        if (cycles.isEmpty)
          const Text(
            'Sin ciclos en el periodo seleccionado.',
            style: TextStyle(color: BrandColors.textMuted),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              dataRowMinHeight: 52,
              dataRowMaxHeight: 88,
              columns: const [
                DataColumn(label: Text('Compra')),
                DataColumn(label: Text('Ventas asociadas')),
                DataColumn(label: Text('Comprado')),
                DataColumn(label: Text('Esperado')),
                DataColumn(label: Text('Cancelaciones cocina')),
                DataColumn(label: Text('Rango esperado 95%')),
                DataColumn(label: Text('Residual')),
                DataColumn(label: Text('Equiv. unidades')),
                DataColumn(label: Text('Z')),
                DataColumn(label: Text('Índice')),
                DataColumn(label: Text('Faltante caja')),
                DataColumn(label: Text('Unidades venta')),
                DataColumn(label: Text('Unidades canceladas')),
              ],
              rows: cycles.map((cycle) {
                return DataRow(
                  color: WidgetStateProperty.resolveWith((states) {
                    if (cycle.isHighAnomaly) {
                      return BrandColors.danger.withValues(alpha: 0.07);
                    }
                    return null;
                  }),
                  cells: [
                    DataCell(Text(cycle.purchaseDate)),
                    DataCell(
                      Text(
                        '${cycle.startBusinessDate} → '
                        '${cycle.endBusinessDate} (${cycle.days}d)',
                      ),
                    ),
                    DataCell(Text(_base(cycle.purchasedBase, model))),
                    DataCell(Text(_base(cycle.predictedPaidBase, model))),
                    DataCell(
                      Text(
                        _base(
                          cycle.cancelledKitchenExplainedBase,
                          model,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${_base(cycle.expectedLowBase, model)} – '
                        '${_base(cycle.expectedHighBase, model)}',
                      ),
                    ),
                    DataCell(
                      Text(
                        _signedBase(
                          cycle.residualOperationalBase,
                          model,
                        ),
                        style: TextStyle(
                          color: cycle.residualOperationalBase > 0
                              ? BrandColors.danger
                              : BrandColors.success,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    DataCell(Text(_equivalentUnits(cycle, model))),
                    DataCell(Text(cycle.robustZ.toStringAsFixed(2))),
                    DataCell(_score(cycle.anomalyScore)),
                    DataCell(Text(_money(cycle.shortageAmount))),
                    DataCell(Text(cycle.paidUnits.toStringAsFixed(0))),
                    DataCell(
                      Text(cycle.cancelledKitchenUnits.toStringAsFixed(0)),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _methodology(PredictiveConsumptionAudit audit) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cómo leerlo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          ...audit.notes.map(
            (note) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '• $note',
                style: const TextStyle(
                  color: BrandColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(PredictiveConsumptionAudit audit) async {
    const headers = [
      'section',
      'ingredient',
      'supplier',
      'baseUnit',
      'confidence',
      'alignment',
      'historyStart',
      'historyEnd',
      'investigationStart',
      'purchaseDate',
      'cycleStart',
      'cycleEnd',
      'purchasedBase',
      'predictedPaidBase',
      'residualPaidBase',
      'cancelledKitchenExplainedBase',
      'predictedOperationalBase',
      'expectedLowBase',
      'expectedHighBase',
      'residualOperationalBase',
      'residualPercent',
      'robustZ',
      'anomalyScore',
      'cashShortage',
      'product',
      'rawBasePerUnit',
      'cookedBasePerUnit',
      'trainingUnits',
      'plausibility',
      'evidence',
    ];

    final rows = <List<String>>[headers];
    for (final model in audit.models) {
      for (final coefficient in model.coefficients) {
        rows.add([
          'coefficient',
          model.definition.name,
          model.supplierNames.join(' | '),
          model.baseUnitLabel,
          model.confidence,
          _alignment(model.alignment),
          audit.historyStart,
          audit.historyEnd,
          audit.investigationStart,
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          coefficient.productName,
          coefficient.rawBasePerUnit.toStringAsFixed(4),
          coefficient.cookedBasePerUnit?.toStringAsFixed(4) ?? '',
          coefficient.unitsInTraining.toStringAsFixed(2),
          coefficient.plausibility,
          '',
        ]);
      }
      for (final cycle in model.cycles) {
        rows.add([
          'cycle',
          model.definition.name,
          model.supplierNames.join(' | '),
          model.baseUnitLabel,
          model.confidence,
          _alignment(model.alignment),
          audit.historyStart,
          audit.historyEnd,
          audit.investigationStart,
          cycle.purchaseDate,
          cycle.startBusinessDate,
          cycle.endBusinessDate,
          cycle.purchasedBase.toStringAsFixed(4),
          cycle.predictedPaidBase.toStringAsFixed(4),
          cycle.residualPaidBase.toStringAsFixed(4),
          cycle.cancelledKitchenExplainedBase.toStringAsFixed(4),
          cycle.predictedOperationalBase.toStringAsFixed(4),
          cycle.expectedLowBase.toStringAsFixed(4),
          cycle.expectedHighBase.toStringAsFixed(4),
          cycle.residualOperationalBase.toStringAsFixed(4),
          cycle.residualPercent.toStringAsFixed(6),
          cycle.robustZ.toStringAsFixed(4),
          cycle.anomalyScore.toStringAsFixed(2),
          cycle.shortageAmount.toStringAsFixed(2),
          '',
          '',
          '',
          '',
          '',
          cycle.evidence,
        ]);
      }
    }

    final csv = rows
        .map((row) => row.map(_csvCell).join(','))
        .join('\r\n');
    final message = await exportCsvFile(
      fileName:
          'tacopos-inteligencia-consumo-${audit.historyStart}-${audit.historyEnd}.csv',
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

class _Metric extends StatelessWidget {
  const _Metric({
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
      width: 240,
      child: GlassPanel(
        padding: const EdgeInsets.all(13),
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
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: accent,
                fontSize: 23,
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

class _Inline extends StatelessWidget {
  const _Inline({
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
      constraints: const BoxConstraints(minWidth: 175),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: BrandColors.surfaceSoft,
        borderRadius: BorderRadius.circular(10),
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
            ),
          ),
        ],
      ),
    );
  }
}

Widget _pill(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: BrandColors.surfaceSoft,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: BrandColors.glassBorder),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: BrandColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

Widget _score(double value) {
  final color = value >= 70
      ? BrandColors.danger
      : value >= 45
          ? BrandColors.accentYellow
          : BrandColors.success;
  return Text(
    value.toStringAsFixed(0),
    style: TextStyle(color: color, fontWeight: FontWeight.w900),
  );
}

Widget _confidence(String value) {
  final color = value == 'Alta'
      ? BrandColors.success
      : value == 'Media'
          ? BrandColors.accentYellow
          : BrandColors.danger;
  return Text(
    value,
    style: TextStyle(color: color, fontWeight: FontWeight.w900),
  );
}

String _alignment(PredictiveAlignment value) {
  return switch (value) {
    PredictiveAlignment.forwardSupply => 'Compra abastece ciclo siguiente',
    PredictiveAlignment.replenishment => 'Compra repone consumo previo',
  };
}

String _base(double value, PredictiveIngredientModel model) {
  if (model.unitFamily == 'weight') {
    if (value.abs() >= 1000) {
      return '${(value / 1000).toStringAsFixed(2)} kg';
    }
    return '${value.toStringAsFixed(0)} g';
  }
  if (model.unitFamily == 'volume') {
    if (value.abs() >= 1000) {
      return '${(value / 1000).toStringAsFixed(2)} L';
    }
    return '${value.toStringAsFixed(0)} ml';
  }
  return '${value.toStringAsFixed(2)} ${model.baseUnitLabel}';
}

String _signedBase(double value, PredictiveIngredientModel model) {
  final sign = value > 0 ? '+' : '';
  return '$sign${_base(value, model)}';
}

String _equivalentUnits(
  PredictiveConsumptionCycle cycle,
  PredictiveIngredientModel model,
) {
  final perUnit = model.learnedRawPerSaleWeighted;
  if (perUnit <= 0) return '-';
  final value = cycle.residualOperationalBase / perUnit;
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(1)} equiv. estadístico';
}

String _equivalentRecentUnits(PredictiveIngredientModel model) {
  final perUnit = model.learnedRawPerSaleWeighted;
  if (perUnit <= 0) return 'No disponible';
  final value = model.recentResidualOperationalBase / perUnit;
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(1)} equiv. estadístico';
}

String _money(double value) => NumberFormat.currency(
      locale: 'es_MX',
      symbol: r'$',
      decimalDigits: 2,
    ).format(value);

String _percent(double value) => '${value.toStringAsFixed(1)}%';

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

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
