import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/purchase_models.dart';
import '../../../utils/csv_exporter.dart';
import '../../auth/backoffice_session.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../widgets/empty_error_state.dart';
import '../../widgets/filter_bar.dart';
import '../../widgets/skeleton_loader.dart';
import 'purchases_analytics.dart';
import 'purchases_repository.dart';
import 'purchases_views.dart';

enum _PurchasesTab {
  dashboard('Dashboard'),
  history('Historial'),
  bySupplier('Por proveedor'),
  byItem('Por insumo'),
  items('Insumos'),
  suppliers('Proveedores'),
  payables('Cuentas por pagar'),
  statement('Estado de cuenta'),
  kardex('Kardex'),
  efficiency('Eficiencia');

  const _PurchasesTab(this.label);
  final String label;
}

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({
    super.key,
    required this.session,
    required this.repository,
  });

  final BackofficeSession session;
  final PurchasesRepository repository;

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  DatePreset _preset = DatePreset.last7Days;
  late DateTime _startDate;
  late DateTime _endDate;
  _PurchasesTab _tab = _PurchasesTab.dashboard;
  String? _statusFilter;
  final TextEditingController _searchController = TextEditingController();

  Future<PurchasesDashboardData>? _dashboardFuture;
  Future<PurchasesCursorPage>? _pageFuture;
  final List<DocumentSnapshot<Map<String, dynamic>>?> _cursorStack = [null];
  int _pageIndex = 0;

  String? _lastBranchId;
  bool _exporting = false;
  bool _exportCancelRequested = false;
  int _exportProgress = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _endDate = DateTime(now.year, now.month, now.day);
    _startDate = _endDate.subtract(const Duration(days: 6));
    _lastBranchId = widget.session.selectedBranchId;
    widget.session.addListener(_onSessionChanged);
    _loadAll();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (_lastBranchId != widget.session.selectedBranchId) {
      _lastBranchId = widget.session.selectedBranchId;
      _resetAndLoad();
    }
  }

  void _applyPreset(DatePreset preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _preset = preset;
      switch (preset) {
        case DatePreset.today:
          _startDate = today;
          _endDate = today;
        case DatePreset.last7Days:
          _startDate = today.subtract(const Duration(days: 6));
          _endDate = today;
        case DatePreset.last30Days:
          _startDate = today.subtract(const Duration(days: 29));
          _endDate = today;
        case DatePreset.last90Days:
          _startDate = today.subtract(const Duration(days: 89));
          _endDate = today;
        case DatePreset.monthToDate:
          _startDate = DateTime(today.year, today.month, 1);
          _endDate = today;
        case DatePreset.custom:
          break;
      }
      _resetAndLoad();
    });
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked == null) return;
    setState(() {
      _preset = DatePreset.custom;
      _startDate = picked.start;
      _endDate = picked.end;
      _resetAndLoad();
    });
  }

  void _resetAndLoad() {
    _cursorStack
      ..clear()
      ..add(null);
    _pageIndex = 0;
    _loadAll();
  }

  void _loadAll() {
    final branchNames = {
      for (final b in widget.session.branches) b.id: b.name,
    };
    final spanDays = _endDate.difference(_startDate).inDays + 1;
    final prevEnd = _startDate.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(Duration(days: spanDays - 1));

    setState(() {
      _dashboardFuture = widget.repository.loadDashboard(
        restaurantId: widget.session.restaurantId,
        startBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_startDate),
        endBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_endDate),
        prevStartBusinessDate: BackofficeSalesAdapter.formatBusinessDate(
          prevStart,
        ),
        prevEndBusinessDate: BackofficeSalesAdapter.formatBusinessDate(prevEnd),
        branchId: widget.session.selectedBranchId,
        branchNames: branchNames,
      );
      _loadPage();
    });
  }

  void _loadPage() {
    _pageFuture = widget.repository.fetchPurchasesPage(
      restaurantId: widget.session.restaurantId,
      startBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_startDate),
      endBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_endDate),
      branchId: widget.session.selectedBranchId,
      statusFilter: _statusFilter,
      startAfter: _cursorStack[_pageIndex],
      pageSize: 20,
    );
  }

  Future<void> _exportPurchasesCsv(Map<String, String> branchNames) async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _exportCancelRequested = false;
      _exportProgress = 0;
    });
    try {
      final all = await widget.repository.exportAllPurchasesInRange(
        restaurantId: widget.session.restaurantId,
        startBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_startDate),
        endBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_endDate),
        branchId: widget.session.selectedBranchId,
        statusFilter: _statusFilter,
        onProgress: (loadedCount) {
          if (mounted) setState(() => _exportProgress = loadedCount);
        },
        isCancelled: () => _exportCancelRequested || !mounted,
      );
      if (_exportCancelRequested) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exportación cancelada.')),
        );
        return;
      }
      final buf = StringBuffer()
        ..writeln(
          'Folio,Fecha,Proveedor,Sucursal,Documento,Estado,Total,Pagado,Saldo',
        );
      for (final p in all) {
        final sup = p.supplierName.replaceAll('"', '""');
        final br = (branchNames[p.branchId] ?? p.branchName)
            .replaceAll('"', '""');
        buf.writeln(
          '"${p.folio}",${p.businessDate ?? ''},"$sup","$br",${documentTypeLabel(p.documentType)},${p.status},${p.total.toStringAsFixed(2)},${p.paidTotal.toStringAsFixed(2)},${p.balance.toStringAsFixed(2)}',
        );
      }
      final msg = await exportCsvFile(
        fileName:
            'compras_${BackofficeSalesAdapter.formatBusinessDate(_startDate)}_${BackofficeSalesAdapter.formatBusinessDate(_endDate)}.csv',
        content: buf.toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$msg (${all.length} compras)')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportCancelRequested = false;
        });
      }
    }
  }

  Future<void> _exportSuppliersCsv(List<SupplierReportSummary> reports) async {
    final buf = StringBuffer()
      ..writeln('Proveedor,Operaciones,Total,PeriodoAnterior,ParticipacionPct,SaldoPendiente');
    for (final r in reports) {
      buf.writeln(
        '"${r.supplierName.replaceAll('"', '""')}",${r.operationsCount},${r.totalAmount.toStringAsFixed(2)},${r.previousTotalAmount.toStringAsFixed(2)},${r.sharePct.toStringAsFixed(2)},${r.pendingBalance.toStringAsFixed(2)}',
      );
    }
    final msg = await exportCsvFile(
      fileName: 'compras_por_proveedor.csv',
      content: buf.toString(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _exportItemsCsv(List<ItemPurchaseReportRow> reports) async {
    final buf = StringBuffer()
      ..writeln('Insumo,Categoria,Unidad,Cantidad,Total,CostoPromedioPonderado,UltimoPrecio,Min,Max');
    for (final r in reports) {
      buf.writeln(
        '"${r.itemName.replaceAll('"', '""')}","${r.category}","${r.unit}",${r.totalQuantity.toStringAsFixed(2)},${r.totalAmount.toStringAsFixed(2)},${r.weightedAvgCost.toStringAsFixed(2)},${r.lastUnitCost.toStringAsFixed(2)},${r.minUnitCost.toStringAsFixed(2)},${r.maxUnitCost.toStringAsFixed(2)}',
      );
    }
    final msg = await exportCsvFile(
      fileName: 'compras_por_insumo.csv',
      content: buf.toString(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _exportPayablesCsv(AccountsPayableSummary summary) async {
    final buf = StringBuffer()
      ..writeln('Folio,Proveedor,Fecha,Total,Pagado,SaldoPendiente');
    for (final p in summary.openPurchases) {
      buf.writeln(
        '"${p.folio}","${p.supplierName.replaceAll('"', '""')}",${p.businessDate ?? ''},${p.total.toStringAsFixed(2)},${p.paidTotal.toStringAsFixed(2)},${p.balance.toStringAsFixed(2)}',
      );
    }
    final msg = await exportCsvFile(
      fileName: 'cuentas_por_pagar.csv',
      content: buf.toString(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openPurchaseDetail(SupplierPurchase purchase) async {
    final detail = await widget.repository.loadPurchaseDetail(
      restaurantId: widget.session.restaurantId,
      purchaseId: purchase.id,
    );
    if (!mounted || detail == null) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${detail.purchase.folio} · ${detail.purchase.supplierName}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fecha: ${detail.purchase.businessDate ?? ''} · ${documentTypeLabel(detail.purchase.documentType)} · Estado: ${detail.purchase.status}',
                ),
                const SizedBox(height: 6),
                Text(
                  'Total: ${BackofficeSalesAdapter.formatMoney(detail.purchase.total)} · Pagado: ${BackofficeSalesAdapter.formatMoney(detail.purchase.paidTotal)} · Saldo: ${BackofficeSalesAdapter.formatMoney(detail.purchase.balance)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (detail.purchase.createdByEmployeeName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Responsable: ${detail.purchase.createdByEmployeeName}'),
                ],
                if (detail.purchase.notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Observaciones: ${detail.purchase.notes}'),
                ],
                const Divider(height: 20),
                const Text(
                  'Partidas',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                if (detail.items.isEmpty)
                  const Text('Sin desglose de partidas.')
                else
                  ...detail.items.map(
                    (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• ${i.purchaseItemName}: ${i.quantity.toStringAsFixed(2)} ${i.unit} × ${BackofficeSalesAdapter.formatMoney(i.unitCostCalculated)} = ${BackofficeSalesAdapter.formatMoney(i.lineTotal)}',
                      ),
                    ),
                  ),
                const Divider(height: 20),
                const Text(
                  'Pagos asociados',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                if (detail.payments.isEmpty)
                  const Text('Sin pagos registrados.')
                else
                  ...detail.payments.map(
                    (pay) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• ${pay.businessDate ?? ''}: ${BackofficeSalesAdapter.formatMoney(pay.amount)} (${pay.fundingSourceName})',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (widget.session.permissions.canCancelSupplierPayments &&
              !detail.purchase.isCancelled)
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _promptCancelPurchase(detail.purchase);
              },
              child: const Text('Cancelar compra'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreatePurchaseDialog(PurchasesDashboardData data) async {
    if (data.suppliers.isEmpty || data.catalogItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Necesitas al menos un proveedor y un insumo activo.'),
        ),
      );
      return;
    }
    var selectedSupplier = data.suppliers.first;
    var selectedItem = data.catalogItems.first;
    final folioCtrl = TextEditingController(
      text: 'C-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
    );
    final qtyCtrl = TextEditingController(text: '10');
    final totalCtrl = TextEditingController(text: '1000');
    final lineDiscCtrl = TextEditingController(text: '0');
    final genDiscCtrl = TextEditingController(text: '0');
    final notesCtrl = TextEditingController();
    final lines = <({PurchaseItem item, double quantity, double lineTotal})>[];
    var paidNow = false;
    var docType = 'note';
    var submitting = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Registrar compra'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Supplier>(
                    initialValue: selectedSupplier,
                    decoration: const InputDecoration(labelText: 'Proveedor'),
                    items: data.suppliers
                        .where((s) => s.active)
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(s.commercialName),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedSupplier = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<PurchaseItem>(
                    initialValue: selectedItem,
                    decoration: const InputDecoration(labelText: 'Insumo'),
                    items: data.catalogItems
                        .where((i) => i.active)
                        .map(
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text('${i.name} (${i.unit})'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedItem = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: folioCtrl,
                    decoration: const InputDecoration(labelText: 'Folio'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: docType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de documento',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'note', child: Text('Nota')),
                      DropdownMenuItem(value: 'invoice', child: Text('Factura')),
                      DropdownMenuItem(value: 'ticket', child: Text('Ticket')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => docType = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qtyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Cantidad (${selectedItem.unit})',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: totalCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Importe bruto',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 78,
                        child: TextField(
                          controller: lineDiscCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Desc %',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final q = double.tryParse(qtyCtrl.text.trim()) ?? 0;
                        final t = double.tryParse(totalCtrl.text.trim()) ?? 0;
                        final dPct =
                            (double.tryParse(lineDiscCtrl.text.trim()) ?? 0)
                                .clamp(0.0, 99.0);
                        if (q <= 0 || t <= 0) return;
                        final netLine = t * (1.0 - dPct / 100.0);
                        setDialogState(() {
                          lines.add((
                            item: selectedItem,
                            quantity: q,
                            lineTotal: netLine,
                          ));
                        });
                      },
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Agregar partida'),
                    ),
                  ),
                  if (lines.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...lines.asMap().entries.map(
                      (e) => Row(
                        children: [
                          Expanded(
                            child: Text(
                              '• ${e.value.item.name}: ${e.value.quantity.toStringAsFixed(2)} ${e.value.item.unit} = ${BackofficeSalesAdapter.formatMoney(e.value.lineTotal)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () =>
                                setDialogState(() => lines.removeAt(e.key)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: genDiscCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Descuento general % (opcional)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones',
                    ),
                  ),
                  CheckboxListTile(
                    value: paidNow,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Marcar como pagada al momento'),
                    onChanged: (v) =>
                        setDialogState(() => paidNow = v ?? false),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (folioCtrl.text.trim().isEmpty) return;
                      final effectiveLines = List.of(lines);
                      if (effectiveLines.isEmpty) {
                        final qty = double.tryParse(qtyCtrl.text.trim()) ?? 0;
                        final tot = double.tryParse(totalCtrl.text.trim()) ?? 0;
                        final dPct =
                            (double.tryParse(lineDiscCtrl.text.trim()) ?? 0)
                                .clamp(0.0, 99.0);
                        if (qty <= 0 || tot <= 0) return;
                        effectiveLines.add((
                          item: selectedItem,
                          quantity: qty,
                          lineTotal: tot * (1.0 - dPct / 100.0),
                        ));
                      }
                      final genPct =
                          (double.tryParse(genDiscCtrl.text.trim()) ?? 0).clamp(
                            0.0,
                            99.0,
                          );
                      final discountedLines = effectiveLines
                          .map(
                            (l) => (
                              item: l.item,
                              quantity: l.quantity,
                              lineTotal: l.lineTotal * (1.0 - genPct / 100.0),
                            ),
                          )
                          .toList(growable: false);

                      setDialogState(() => submitting = true);
                      final br = widget.session.branches.firstWhere(
                        (b) => b.id == widget.session.selectedBranchId,
                        orElse: () => widget.session.branches.first,
                      );
                      final now = DateTime.now();
                      await widget.repository.createMultiLinePurchase(
                        restaurantId: widget.session.restaurantId,
                        restaurantName: widget.session.restaurantName,
                        branchId: br.id,
                        branchName: br.name,
                        supplier: selectedSupplier,
                        folio: folioCtrl.text,
                        documentType: docType,
                        purchaseDate: now,
                        dueDate: selectedSupplier.creditDays > 0
                            ? now.add(
                                Duration(days: selectedSupplier.creditDays),
                              )
                            : now,
                        lines: discountedLines,
                        markPaidImmediately: paidNow,
                        paymentMethod: 'transfer',
                        notes: notesCtrl.text,
                        employeeId: widget.session.employee?.id ?? '',
                        employeeName: widget.session.employee?.name ?? '',
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    },
              child: Text(submitting ? 'Guardando...' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) _resetAndLoad();
  }

  Future<void> _openSupplierDialog(Supplier? existing) async {
    final nameCtrl = TextEditingController(text: existing?.commercialName ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final creditCtrl = TextEditingController(
      text: (existing?.creditDays ?? 0).toString(),
    );
    var active = existing?.active ?? true;
    var submitting = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Nuevo proveedor' : 'Editar proveedor'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre comercial',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: creditCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Días de crédito',
                  ),
                ),
                SwitchListTile(
                  value: active,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Proveedor activo'),
                  onChanged: (v) => setDialogState(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      setDialogState(() => submitting = true);
                      await widget.repository.saveSupplier(
                        restaurantId: widget.session.restaurantId,
                        supplierId: existing?.id,
                        commercialName: nameCtrl.text,
                        phone: phoneCtrl.text,
                        active: active,
                        preferredPaymentMethod:
                            existing?.preferredPaymentMethod ?? 'both',
                        creditDays: int.tryParse(creditCtrl.text.trim()) ?? 0,
                        paymentWeekday: existing?.paymentWeekday ?? 'none',
                        paymentWeekdayName:
                            existing?.paymentWeekdayName ?? 'Sin día fijo',
                        employeeId: widget.session.employee?.id ?? '',
                        employeeName: widget.session.employee?.name ?? '',
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    },
              child: Text(submitting ? 'Guardando...' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) _resetAndLoad();
  }

  Future<void> _openPayPurchaseDialog(SupplierPurchase purchase) async {
    final amountCtrl = TextEditingController(
      text: purchase.balance.toStringAsFixed(2),
    );
    final refCtrl = TextEditingController();
    var method = 'transfer';
    var submitting = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Registrar pago · ${purchase.folio}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saldo pendiente: ${BackofficeSalesAdapter.formatMoney(purchase.balance)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Monto a pagar'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(labelText: 'Forma de pago'),
                  items: const [
                    DropdownMenuItem(
                      value: 'transfer',
                      child: Text('Transferencia'),
                    ),
                    DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                    DropdownMenuItem(
                      value: 'partner_contribution',
                      child: Text('Aportación de socios'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => method = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: refCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Referencia / Folio de pago',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final amount =
                          double.tryParse(amountCtrl.text.trim()) ?? 0;
                      if (amount <= 0 || amount > purchase.balance + 0.01) {
                        return;
                      }
                      setDialogState(() => submitting = true);
                      await widget.repository.registerPayment(
                        restaurantId: widget.session.restaurantId,
                        restaurantName: widget.session.restaurantName,
                        purchase: purchase,
                        amount: amount,
                        method: method,
                        reference: refCtrl.text,
                        notes: '',
                        employeeId: widget.session.employee?.id ?? '',
                        employeeName: widget.session.employee?.name ?? '',
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    },
              child: Text(submitting ? 'Aplicando...' : 'Aplicar pago'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) _resetAndLoad();
  }

  Future<String?> _promptReasonDialog(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Motivo de cancelación (obligatorio)',
            ),
            onChanged: (_) => setDialogState(() {}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: ctrl.text.trim().isNotEmpty
                  ? () => Navigator.of(ctx).pop(ctrl.text.trim())
                  : null,
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptCancelPurchase(SupplierPurchase purchase) async {
    final reason = await _promptReasonDialog(
      'Cancelar compra ${purchase.folio}',
    );
    if (reason == null) return;
    try {
      await widget.repository.cancelSupplierPurchase(
        restaurantId: widget.session.restaurantId,
        purchase: purchase,
        reason: reason,
        employeeId: widget.session.employee?.id ?? '',
        employeeName: widget.session.employee?.name ?? '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compra cancelada correctamente.')),
      );
      _resetAndLoad();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  Future<void> _promptCancelPayment(SupplierPayment payment) async {
    final reason = await _promptReasonDialog(
      'Cancelar pago de ${payment.purchaseFolio}',
    );
    if (reason == null) return;
    try {
      await widget.repository.cancelSupplierPayment(
        restaurantId: widget.session.restaurantId,
        payment: payment,
        reason: reason,
        employeeId: widget.session.employee?.id ?? '',
        employeeName: widget.session.employee?.name ?? '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pago cancelado y saldo recalculado.')),
      );
      _resetAndLoad();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  Future<void> _openPurchaseItemDialog(
    PurchaseItem? existing,
    List<Supplier> suppliers,
  ) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final catCtrl = TextEditingController(text: existing?.category ?? 'Carnes');
    final unitCtrl = TextEditingController(text: existing?.unit ?? 'kg');
    var active = existing?.active ?? true;
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? 'Nuevo insumo de compra' : 'Editar insumo',
          ),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: catCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Categoría',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: unitCtrl,
                        decoration: const InputDecoration(labelText: 'Unidad'),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  value: active,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Insumo activo'),
                  onChanged: (v) => setDialogState(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      setDialogState(() => saving = true);
                      await widget.repository.savePurchaseItem(
                        restaurantId: widget.session.restaurantId,
                        itemId: existing?.id,
                        name: nameCtrl.text,
                        category: catCtrl.text,
                        unit: unitCtrl.text,
                        active: active,
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    },
              child: Text(saving ? 'Guardando...' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) _resetAndLoad();
  }

  Future<void> _exportStatementCsv(SupplierStatementSummary s) async {
    final buf = StringBuffer()
      ..writeln('Fecha,Folio,Tipo,Descripcion,Cargo,Abono,SaldoAcumulado');
    for (final r in s.rows) {
      buf.writeln(
        '${BackofficeSalesAdapter.formatBusinessDate(r.date)},"${r.folio}",${r.type},"${r.notes.replaceAll('"', '""')}",${r.charge.toStringAsFixed(2)},${r.credit.toStringAsFixed(2)},${r.balance.toStringAsFixed(2)}',
      );
    }
    final msg = await exportCsvFile(
      fileName: 'estado_cuenta_${s.supplierId}.csv',
      content: buf.toString(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _exportKardexCsv(List<PurchaseKardexEntry> entries) async {
    final buf = StringBuffer()
      ..writeln('Fecha,Folio,Proveedor,Insumo,Unidad,Cantidad,CostoUnitario,Total');
    for (final e in entries) {
      buf.writeln(
        '${e.dateLabel},"${e.folio}","${e.supplierName.replaceAll('"', '""')}","${e.itemName.replaceAll('"', '""')}","${e.unit}",${e.quantity.toStringAsFixed(2)},${e.unitCost.toStringAsFixed(2)},${e.lineTotal.toStringAsFixed(2)}',
      );
    }
    final msg = await exportCsvFile(
      fileName: 'kardex_compras.csv',
      content: buf.toString(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final branchNames = {
      for (final b in widget.session.branches) b.id: b.name,
    };

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Compras, Proveedores y CXP',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Control integral de abastecimiento, costos históricos por insumo, cuentas por pagar y eficiencia.',
                style: TextStyle(fontSize: 13, color: tokens.textSecondary),
              ),
              const SizedBox(height: 16),
              SaasFilterBar(
                activePreset: _preset,
                startDateLabel: BackofficeSalesAdapter.formatBusinessDate(
                  _startDate,
                ),
                endDateLabel: BackofficeSalesAdapter.formatBusinessDate(_endDate),
                onPresetSelected: _applyPreset,
                onPickCustomRange: _pickCustomRange,
                searchController: _tab == _PurchasesTab.history
                    ? _searchController
                    : null,
                searchHint: 'Buscar folio o proveedor...',
                onSearchSubmitted: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Wrap(
                  spacing: 8,
                  children: _PurchasesTab.values
                      .map(
                        (t) => ChoiceChip(
                          label: Text(t.label),
                          selected: _tab == t,
                          onSelected: (_) => setState(() => _tab = t),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 18),
              FutureBuilder<PurchasesDashboardData>(
                future: _dashboardFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const TableSkeleton(rows: 6);
                  }
                  if (snapshot.hasError) {
                    return SaasErrorState(
                      title: 'Error al cargar compras',
                      message:
                          'No se pudieron consultar los registros de compras y proveedores.',
                      onRetry: _resetAndLoad,
                    );
                  }
                  final data = snapshot.data;
                  if (data == null) {
                    return const SaasEmptyState(
                      icon: Icons.shopping_bag_outlined,
                      title: 'Sin información disponible',
                      message: 'Intenta cambiar el rango de fechas.',
                    );
                  }

                  final balancesBySup = {
                    for (final b in data.accountsPayable.balancesBySupplier)
                      b.supplierId: b.pendingAmount,
                  };

                  return switch (_tab) {
                    _PurchasesTab.dashboard => PurchasesDashboardTab(
                      data: data,
                      isMobile: isMobile,
                      onOpenPurchase: _openPurchaseDetail,
                    ),
                    _PurchasesTab.history => FutureBuilder<PurchasesCursorPage>(
                      future: _pageFuture,
                      builder: (context, pageSnap) {
                        if (pageSnap.connectionState ==
                            ConnectionState.waiting) {
                          return const TableSkeleton(rows: 6);
                        }
                        final page = pageSnap.data;
                        return PurchasesHistoryTab(
                          purchases: page?.purchases ?? const [],
                          branchNames: branchNames,
                          isMobile: isMobile,
                          searchQuery: _searchController.text,
                          statusFilter: _statusFilter,
                          canCreate:
                              widget.session.permissions.canRegisterPurchases,
                          canExport: widget.session.permissions.canExportData,
                          exporting: _exporting,
                          exportProgress: _exportProgress,
                          hasPrevPage: _pageIndex > 0,
                          hasNextPage: page?.hasNext == true,
                          pageLabel: 'Página ${_pageIndex + 1}',
                          onStatusChanged: (st) {
                            _statusFilter = st;
                            _cursorStack
                              ..clear()
                              ..add(null);
                            _pageIndex = 0;
                            setState(_loadPage);
                          },
                          onCreatePurchase: () =>
                              _openCreatePurchaseDialog(data),
                          onExport: () => _exportPurchasesCsv(branchNames),
                          onCancelExport: () =>
                              setState(() => _exportCancelRequested = true),
                          onPrevPage: () {
                            if (_pageIndex > 0) {
                              _pageIndex -= 1;
                              setState(_loadPage);
                            }
                          },
                          onNextPage: () {
                            final last = page?.lastDocument;
                            if (last == null) return;
                            if (_cursorStack.length <= _pageIndex + 1) {
                              _cursorStack.add(last);
                            }
                            _pageIndex += 1;
                            setState(_loadPage);
                          },
                          onSelectPurchase: _openPurchaseDetail,
                        );
                      },
                    ),
                    _PurchasesTab.bySupplier => SupplierReportTab(
                      reports: data.metrics.supplierReports,
                      isMobile: isMobile,
                      onOpenPurchase: _openPurchaseDetail,
                      onExport: () =>
                          _exportSuppliersCsv(data.metrics.supplierReports),
                    ),
                    _PurchasesTab.byItem => ItemReportTab(
                      reports: data.metrics.itemReports,
                      isMobile: isMobile,
                      onExport: () => _exportItemsCsv(data.metrics.itemReports),
                    ),
                    _PurchasesTab.items => PurchaseItemsCatalogTab(
                      items: data.catalogItems,
                      canManage: widget.session.permissions.canManageSuppliers,
                      onCreateOrEdit: (item) =>
                          _openPurchaseItemDialog(item, data.suppliers),
                    ),
                    _PurchasesTab.suppliers => SuppliersCatalogTab(
                      suppliers: data.suppliers,
                      balances: balancesBySup,
                      canManage: widget.session.permissions.canManageSuppliers,
                      isMobile: isMobile,
                      onCreateOrEdit: _openSupplierDialog,
                    ),
                    _PurchasesTab.payables => AccountsPayableTab(
                      summary: data.accountsPayable,
                      payments: data.payments,
                      branchNames: branchNames,
                      canPay: widget.session.permissions.canPaySuppliers,
                      canCancelPayment:
                          widget.session.permissions.canCancelSupplierPayments,
                      isMobile: isMobile,
                      onPayPurchase: _openPayPurchaseDialog,
                      onCancelPayment: _promptCancelPayment,
                      onSelectPurchase: _openPurchaseDetail,
                      onExport: () => _exportPayablesCsv(data.accountsPayable),
                    ),
                    _PurchasesTab.statement => SupplierStatementTab(
                      suppliers: data.suppliers,
                      purchases: data.currentPurchases,
                      payments: data.payments,
                      isMobile: isMobile,
                      onExport: _exportStatementCsv,
                    ),
                    _PurchasesTab.kardex => PurchaseKardexTab(
                      entries: PurchasesAnalytics.buildKardex(
                        purchases: data.currentPurchases,
                        itemsByPurchase: data.currentItemsByPurchase,
                      ),
                      branchNames: branchNames,
                      onExport: _exportKardexCsv,
                    ),
                    _PurchasesTab.efficiency => EfficiencyAndBudgetsTab(
                      data: data,
                      isMobile: isMobile,
                    ),
                  };
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
