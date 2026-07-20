import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/kitchen_stock_item.dart';
import '../../models/purchase_models.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/csv_exporter.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';

class PurchaseAdminScreen extends StatefulWidget {
  const PurchaseAdminScreen({super.key});

  @override
  State<PurchaseAdminScreen> createState() => _PurchaseAdminScreenState();
}

class _PurchaseAdminScreenState extends State<PurchaseAdminScreen> {
  final _repository = TacoPosRepository();

  @override
  void initState() {
    super.initState();
    _repository.ensureDefaultPartners().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 8,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Proveedores'),
              Tab(text: 'Insumos'),
              Tab(text: 'Registrar compra'),
              Tab(text: 'Cuentas por pagar'),
              Tab(text: 'Pagos'),
              Tab(text: 'Estado de cuenta'),
              Tab(text: 'Kardex'),
              Tab(text: 'Reportes'),
            ],
          ),
          Expanded(
            child: _PurchaseDataScope(
              repository: _repository,
              builder: (context, data) => TabBarView(
                children: [
                  _SuppliersTab(repository: _repository, data: data),
                  _PurchaseItemsTab(repository: _repository, data: data),
                  _RegisterPurchaseTab(repository: _repository, data: data),
                  _AccountsPayableTab(repository: _repository, data: data),
                  _SupplierPaymentsTab(repository: _repository, data: data),
                  _SupplierStatementTab(repository: _repository, data: data),
                  _PurchaseKardexTab(repository: _repository, data: data),
                  _PurchaseReportsTab(repository: _repository, data: data),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseData {
  const _PurchaseData({
    required this.suppliers,
    required this.partners,
    required this.kitchenStockItems,
    required this.purchases,
    required this.payments,
    required this.contributions,
  });

  final List<Supplier> suppliers;
  final List<Partner> partners;
  final List<KitchenStockItem> kitchenStockItems;
  final List<SupplierPurchase> purchases;
  final List<SupplierPayment> payments;
  final List<PartnerContribution> contributions;
}

class _PurchaseDataScope extends StatelessWidget {
  const _PurchaseDataScope({required this.repository, required this.builder});

  final TacoPosRepository repository;
  final Widget Function(BuildContext context, _PurchaseData data) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Supplier>>(
      stream: repository.watchSuppliers(),
      builder: (context, suppliersSnapshot) {
        if (suppliersSnapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudieron cargar proveedores',
            message: '${suppliersSnapshot.error}',
          );
        }
        if (!suppliersSnapshot.hasData) {
          return const LoadingPanel(message: 'Cargando compras...');
        }
        return StreamBuilder<List<KitchenStockItem>>(
          stream: repository.watchKitchenStockItems(),
          builder: (context, kitchenSnapshot) {
            if (kitchenSnapshot.hasError) {
              return EmptyState(
                icon: Icons.error_outline,
                title: 'No se pudieron cargar insumos',
                message: '${kitchenSnapshot.error}',
              );
            }
            if (!kitchenSnapshot.hasData) {
              return const LoadingPanel(message: 'Cargando insumos...');
            }
            return StreamBuilder<List<Partner>>(
              stream: repository.watchPartners(),
              builder: (context, partnersSnapshot) {
                return StreamBuilder<List<SupplierPurchase>>(
                  stream: repository.watchSupplierPurchases(),
                  builder: (context, purchasesSnapshot) {
                    return StreamBuilder<List<SupplierPayment>>(
                      stream: repository.watchSupplierPayments(),
                      builder: (context, paymentsSnapshot) {
                        return StreamBuilder<List<PartnerContribution>>(
                          stream: repository.watchPartnerContributions(),
                          builder: (context, contributionsSnapshot) {
                            final data = _PurchaseData(
                              suppliers: suppliersSnapshot.data ?? const [],
                              partners: partnersSnapshot.data ?? const [],
                              kitchenStockItems:
                                  kitchenSnapshot.data ?? const [],
                              purchases: purchasesSnapshot.data ?? const [],
                              payments: paymentsSnapshot.data ?? const [],
                              contributions:
                                  contributionsSnapshot.data ?? const [],
                            );
                            return builder(context, data);
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SuppliersTab extends StatefulWidget {
  const _SuppliersTab({required this.repository, required this.data});

  final TacoPosRepository repository;
  final _PurchaseData data;

  @override
  State<_SuppliersTab> createState() => _SuppliersTabState();
}

class _SuppliersTabState extends State<_SuppliersTab> {
  final _searchController = TextEditingController();
  String _status = 'active';
  String _weekday = 'all';
  String _method = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.toLowerCase().trim();
    final suppliers = widget.data.suppliers.where((supplier) {
      if (_status == 'active' && !supplier.active) return false;
      if (_status == 'inactive' && supplier.active) return false;
      if (_weekday != 'all' && supplier.paymentWeekday != _weekday) {
        return false;
      }
      if (_method != 'all' && supplier.preferredPaymentMethod != _method) {
        return false;
      }
      if (query.isNotEmpty &&
          !supplier.commercialName.toLowerCase().contains(query) &&
          !supplier.legalName.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _PurchaseHeader(
          title: 'Proveedores',
          subtitle: 'Catalogo y saldo por proveedor.',
          action: FilledButton.icon(
            onPressed: () => _openSupplierDialog(),
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Proveedor'),
          ),
        ),
        const SizedBox(height: 12),
        _FiltersWrap(
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Buscar proveedor',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            _Dropdown(
              label: 'Estado',
              value: _status,
              values: const {
                'active': 'Activos',
                'inactive': 'Inactivos',
                'all': 'Todos',
              },
              onChanged: (value) => setState(() => _status = value),
            ),
            _Dropdown(
              label: 'Dia pago',
              value: _weekday,
              values: {'all': 'Todos', ..._weekdayLabels},
              onChanged: (value) => setState(() => _weekday = value),
            ),
            _Dropdown(
              label: 'Forma pago',
              value: _method,
              values: const {
                'all': 'Todas',
                'cash': 'Efectivo',
                'transfer': 'Transferencia',
                'both': 'Ambas',
              },
              onChanged: (value) => setState(() => _method = value),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (suppliers.isEmpty)
          const EmptyState(
            icon: Icons.local_shipping_outlined,
            title: 'Sin proveedores',
            message: 'Agrega proveedores para registrar compras.',
          )
        else
          ...suppliers.map((supplier) {
            final purchases = widget.data.purchases.where(
              (purchase) =>
                  purchase.supplierId == supplier.id &&
                  purchase.status != 'cancelled',
            );
            final balance = purchases.fold<double>(
              0,
              (sum, purchase) => sum + purchase.balance,
            );
            final purchased = purchases.fold<double>(
              0,
              (sum, purchase) => sum + purchase.total,
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                accent: supplier.active
                    ? BrandColors.accentYellow
                    : BrandColors.textMuted,
                child: ListTile(
                  title: Text(
                    supplier.commercialName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    'Dia de pago: ${supplier.paymentWeekdayName} · '
                    'Forma: ${_paymentMethodLabel(supplier.preferredPaymentMethod)}',
                  ),
                  trailing: Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Metric(label: 'Compras', value: purchased),
                      _Metric(label: 'Saldo', value: balance),
                      IconButton(
                        tooltip: 'Editar',
                        onPressed: () => _openSupplierDialog(supplier),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Future<void> _openSupplierDialog([Supplier? supplier]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _SupplierDialog(repository: widget.repository, supplier: supplier),
    );
    if (!mounted || saved != true) return;
    showAppSnackBar(
      context,
      supplier == null ? 'Proveedor creado.' : 'Proveedor actualizado.',
      type: AppSnackBarType.success,
    );
  }
}

class _PurchaseItemsTab extends StatelessWidget {
  const _PurchaseItemsTab({required this.repository, required this.data});

  final TacoPosRepository repository;
  final _PurchaseData data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _PurchaseHeader(
          title: 'Insumos',
          subtitle:
              'Catalogo de insumos usados para compras y control de cocina.',
          action: FilledButton.icon(
            onPressed: () => _openDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Insumo'),
          ),
        ),
        const SizedBox(height: 12),
        if (data.kitchenStockItems.isEmpty)
          const EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Sin insumos',
            message: 'Crea insumos como carne, servilletas, gas o bolsas.',
          )
        else
          ...data.kitchenStockItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                accent: item.affectsKitchenPerformance
                    ? BrandColors.success
                    : BrandColors.textMuted,
                child: ListTile(
                  leading: item.active
                      ? null
                      : const Icon(
                          Icons.pause_circle_outline,
                          color: BrandColors.textMuted,
                        ),
                  title: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${_categoryLabel(item.category)} · ${_unitLabel(item.unit)} · '
                    'Afecta rendimiento de cocina: ${item.affectsKitchenPerformance ? 'Si' : 'No'}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Editar',
                    onPressed: () => _openDialog(context, item),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openDialog(
    BuildContext context, [
    KitchenStockItem? item,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PurchaseKitchenStockItemDialog(
        repository: repository,
        item: item,
        suppliers: data.suppliers,
      ),
    );
    if (!context.mounted || saved != true) return;
    showAppSnackBar(
      context,
      item == null ? 'Insumo creado.' : 'Insumo actualizado.',
      type: AppSnackBarType.success,
    );
  }
}

class _RegisterPurchaseTab extends StatefulWidget {
  const _RegisterPurchaseTab({required this.repository, required this.data});

  final TacoPosRepository repository;
  final _PurchaseData data;

  @override
  State<_RegisterPurchaseTab> createState() => _RegisterPurchaseTabState();
}

class _RegisterPurchaseTabState extends State<_RegisterPurchaseTab> {
  final _folioController = TextEditingController();
  final _notesController = TextEditingController();
  String? _supplierId;
  String _documentType = 'note';
  DateTime _purchaseDate = DateTime.now();
  DateTime _dueDate = DateTime.now();
  final _lines = <PurchaseLineInput>[];
  bool _saving = false;

  @override
  void dispose() {
    _folioController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supplier = _supplier();
    final total = _lines.fold<double>(0, (sum, line) => sum + line.total);
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const _PurchaseHeader(
          title: 'Registrar compra',
          subtitle: 'Captura notas, tickets o facturas de proveedor.',
        ),
        const SizedBox(height: 12),
        GlassPanel(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  initialValue: _supplierId,
                  decoration: const InputDecoration(labelText: 'Proveedor'),
                  items: widget.data.suppliers
                      .where((supplier) => supplier.active)
                      .map(
                        (supplier) => DropdownMenuItem(
                          value: supplier.id,
                          child: Text(supplier.commercialName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _supplierId = value;
                    _suggestDueDate();
                  }),
                ),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _folioController,
                  decoration: const InputDecoration(labelText: 'Folio / nota'),
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  initialValue: _documentType,
                  decoration: const InputDecoration(labelText: 'Documento'),
                  items: const [
                    DropdownMenuItem(value: 'note', child: Text('Nota')),
                    DropdownMenuItem(value: 'invoice', child: Text('Factura')),
                    DropdownMenuItem(value: 'ticket', child: Text('Ticket')),
                    DropdownMenuItem(
                      value: 'remision',
                      child: Text('Remision'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _documentType = value ?? 'note'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  'Compra ${DateFormat('dd/MM/yyyy').format(_purchaseDate)}',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickDueDate,
                icon: const Icon(Icons.event_available_outlined),
                label: Text(
                  'Vence ${DateFormat('dd/MM/yyyy').format(_dueDate)}',
                ),
              ),
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notas'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Renglones',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _addLine,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar renglon'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_lines.isEmpty)
                const Text(
                  'Sin renglones.',
                  style: TextStyle(color: BrandColors.textMuted),
                )
              else
                ..._lines.asMap().entries.map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.value.purchaseItemName),
                    subtitle: Text(
                      '${_formatQty(entry.value.quantity)} ${entry.value.unit} x ${_money(entry.value.unitCost)}',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        MoneyText(value: entry.value.total),
                        IconButton(
                          tooltip: 'Quitar',
                          onPressed: () =>
                              setState(() => _lines.removeAt(entry.key)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                ),
              const Divider(),
              Align(
                alignment: Alignment.centerRight,
                child: MoneyText(
                  value: total,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: BrandColors.accentYellow,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _saving || supplier == null ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Guardando...' : 'Guardar compra'),
          ),
        ),
      ],
    );
  }

  Supplier? _supplier() {
    final supplierId = _supplierId;
    if (supplierId == null) return null;
    for (final supplier in widget.data.suppliers) {
      if (supplier.id == supplierId) return supplier;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (picked != null && mounted) {
      setState(() {
        _purchaseDate = picked;
        _suggestDueDate();
      });
    }
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked != null && mounted) {
      setState(() => _dueDate = picked);
    }
  }

  void _suggestDueDate() {
    final supplier = _supplier();
    _dueDate = _purchaseDate.add(Duration(days: supplier?.creditDays ?? 0));
  }

  Future<void> _addLine() async {
    final line = await showDialog<PurchaseLineInput>(
      context: context,
      builder: (_) => _PurchaseLineDialog(items: widget.data.kitchenStockItems),
    );
    if (line != null && mounted) {
      setState(() => _lines.add(line));
    }
  }

  Future<void> _save() async {
    final supplier = _supplier();
    if (supplier == null) return;
    if (_lines.isEmpty) {
      showAppSnackBar(context, 'Agrega al menos un renglon.');
      return;
    }
    setState(() => _saving = true);
    try {
      final purchase = await widget.repository.createSupplierPurchase(
        supplier: supplier,
        purchaseDate: _purchaseDate,
        dueDate: _dueDate,
        folio: _folioController.text,
        documentType: _documentType,
        items: _lines,
        notes: _notesController.text,
      );
      if (!mounted) return;
      setState(() {
        _folioController.clear();
        _notesController.clear();
        _lines.clear();
      });
      showAppSnackBar(
        context,
        'Compra registrada.',
        type: AppSnackBarType.success,
        action: SnackBarAction(
          label: 'Ver detalle',
          onPressed: () => _showPurchaseDetail(
            context,
            repository: widget.repository,
            purchase: purchase,
            payments: widget.data.payments,
            data: widget.data,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _AccountsPayableTab extends StatefulWidget {
  const _AccountsPayableTab({required this.repository, required this.data});

  final TacoPosRepository repository;
  final _PurchaseData data;

  @override
  State<_AccountsPayableTab> createState() => _AccountsPayableTabState();
}

class _AccountsPayableTabState extends State<_AccountsPayableTab> {
  String _status = 'open';

  @override
  Widget build(BuildContext context) {
    final canCancelPurchase = _canCancelSupplierPurchase();
    final purchases =
        widget.data.purchases.where((purchase) {
          if (_status == 'open') return purchase.hasBalance;
          if (_status == 'paid') return purchase.status == 'paid';
          if (_status == 'partial') return purchase.status == 'partial';
          if (_status == 'pending') return purchase.status == 'pending';
          if (_status == 'cancelled') return purchase.isCancelled;
          return true;
        }).toList()..sort((a, b) {
          final aDue = a.dueDate;
          final bDue = b.dueDate;
          if (aDue != null && bDue != null) {
            return aDue.compareTo(bDue);
          }
          if (aDue != null) return -1;
          if (bDue != null) return 1;
          return b.purchaseDate.compareTo(a.purchaseDate);
        });
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _PurchaseHeader(
          title: 'Cuentas por pagar',
          subtitle: 'Compras pendientes, parciales y pagadas.',
          action: _Dropdown(
            label: 'Estado',
            value: _status,
            values: const {
              'open': 'Con saldo',
              'pending': 'Pendientes',
              'partial': 'Parciales',
              'paid': 'Pagadas',
              'cancelled': 'Canceladas',
              'all': 'Todas',
            },
            onChanged: (value) => setState(() => _status = value),
          ),
        ),
        const SizedBox(height: 12),
        if (purchases.isEmpty)
          const EmptyState(
            icon: Icons.assignment_turned_in_outlined,
            title: 'Sin cuentas',
            message: 'No hay cuentas por pagar para este filtro.',
          )
        else
          ...purchases.map(
            (purchase) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onDoubleTap: () => _editPurchaseFromRow(purchase),
                child: GlassCard(
                  accent: _purchaseDueAccent(purchase),
                  child: ListTile(
                    title: Text(
                      purchase.supplierName,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      '${purchase.folio.isEmpty ? 'Sin folio' : purchase.folio} · '
                      'Compra ${_dateLabel(purchase.purchaseDate)} · '
                      'Vence ${_dueDateLabel(purchase.dueDate)} · '
                      '${_dueStatusLabel(purchase)} · '
                      'Estado: ${_purchaseStatusLabel(purchase.status)}',
                    ),
                    trailing: Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (purchase.isCancelled)
                          const Chip(label: Text('Cancelada')),
                        _Metric(label: 'Total', value: purchase.total),
                        _Metric(label: 'Pagado', value: purchase.paidTotal),
                        _Metric(label: 'Saldo', value: purchase.balance),
                        _AccountsPayableActionsMenu(
                          purchase: purchase,
                          canCancelPurchase: canCancelPurchase,
                          onEdit: () => _editPurchaseFromRow(purchase),
                          onChangeDueDate: () => _changeDueDate(purchase),
                          onCancel: () => _cancelPurchase(purchase),
                          onViewDetail: () => _showPurchaseDetail(
                            context,
                            repository: widget.repository,
                            purchase: purchase,
                            payments: widget.data.payments,
                            data: widget.data,
                          ),
                          onPay: purchase.hasBalance
                              ? () => _payPurchase(purchase)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _payPurchase(SupplierPurchase purchase) async {
    final paid = await showDialog<bool>(
      context: context,
      builder: (_) => _SupplierPaymentDialog(
        repository: widget.repository,
        purchase: purchase,
      ),
    );
    if (!mounted || paid != true) return;
    showAppSnackBar(context, 'Pago registrado.', type: AppSnackBarType.success);
  }

  void _editPurchaseFromRow(SupplierPurchase purchase) {
    if (purchase.isCancelled) {
      showAppSnackBar(
        context,
        'No se puede editar una compra cancelada.',
        type: AppSnackBarType.warning,
      );
      return;
    }
    _editPurchase(purchase);
  }

  Future<void> _changeDueDate(SupplierPurchase purchase) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangeDueDateDialog(
        repository: widget.repository,
        purchase: purchase,
      ),
    );
    if (!mounted || changed != true) return;
    showAppSnackBar(
      context,
      'Fecha de vencimiento actualizada.',
      type: AppSnackBarType.success,
    );
  }

  Future<void> _editPurchase(SupplierPurchase purchase) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditSupplierPurchaseDialog(
        repository: widget.repository,
        data: widget.data,
        purchase: purchase,
      ),
    );
    if (!mounted || saved != true) return;
    showAppSnackBar(
      context,
      'Compra actualizada.',
      type: AppSnackBarType.success,
    );
  }

  Future<void> _cancelPurchase(SupplierPurchase purchase) async {
    final activePayments = widget.data.payments
        .where(
          (payment) => payment.purchaseId == purchase.id && payment.isActive,
        )
        .toList();
    if (activePayments.isNotEmpty) {
      showAppSnackBar(
        context,
        'No puedes cancelar esta compra porque ya tiene pagos aplicados. Cancela primero los pagos del proveedor y despues cancela la compra.',
        type: AppSnackBarType.warning,
      );
      return;
    }

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _CancelSupplierPurchaseDialog(),
    );
    if (!mounted || reason == null) return;
    try {
      await widget.repository.cancelSupplierPurchase(
        purchase: purchase,
        reason: reason,
      );
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Compra cancelada.',
        type: AppSnackBarType.success,
      );
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
        type: AppSnackBarType.error,
      );
    }
  }
}

enum _AccountsPayableAction { edit, changeDueDate, cancel, viewDetail, pay }

class _AccountsPayableActionsMenu extends StatelessWidget {
  const _AccountsPayableActionsMenu({
    required this.purchase,
    required this.canCancelPurchase,
    required this.onEdit,
    required this.onChangeDueDate,
    required this.onCancel,
    required this.onViewDetail,
    required this.onPay,
  });

  final SupplierPurchase purchase;
  final bool canCancelPurchase;
  final VoidCallback onEdit;
  final VoidCallback onChangeDueDate;
  final VoidCallback onCancel;
  final VoidCallback onViewDetail;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Acciones',
            style: TextStyle(color: BrandColors.textMuted, fontSize: 11),
          ),
          PopupMenuButton<_AccountsPayableAction>(
            tooltip: 'Acciones',
            icon: const Icon(Icons.more_vert),
            onSelected: (action) {
              switch (action) {
                case _AccountsPayableAction.edit:
                  onEdit();
                case _AccountsPayableAction.changeDueDate:
                  onChangeDueDate();
                case _AccountsPayableAction.cancel:
                  onCancel();
                case _AccountsPayableAction.viewDetail:
                  onViewDetail();
                case _AccountsPayableAction.pay:
                  onPay?.call();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _AccountsPayableAction.edit,
                enabled: !purchase.isCancelled,
                child: const Text('Editar compra'),
              ),
              PopupMenuItem(
                value: _AccountsPayableAction.changeDueDate,
                enabled: !purchase.isCancelled,
                child: const Text('Cambiar fecha de vencimiento'),
              ),
              PopupMenuItem(
                value: _AccountsPayableAction.cancel,
                enabled: !purchase.isCancelled && canCancelPurchase,
                child: const Text('Cancelar compra'),
              ),
              const PopupMenuItem(
                value: _AccountsPayableAction.viewDetail,
                child: Text('Ver detalle'),
              ),
              if (onPay != null) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: _AccountsPayableAction.pay,
                  child: Text('Registrar pago'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SupplierPaymentsTab extends StatefulWidget {
  const _SupplierPaymentsTab({required this.repository, required this.data});

  final TacoPosRepository repository;
  final _PurchaseData data;

  @override
  State<_SupplierPaymentsTab> createState() => _SupplierPaymentsTabState();
}

class _SupplierPaymentsTabState extends State<_SupplierPaymentsTab> {
  String _method = 'all';

  @override
  Widget build(BuildContext context) {
    final payments = widget.data.payments.where((payment) {
      if (_method == 'all') return true;
      return payment.method == _method;
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _PurchaseHeader(
          title: 'Pagos a proveedores',
          subtitle: 'Historial de pagos aplicados.',
          action: _Dropdown(
            label: 'Forma',
            value: _method,
            values: const {
              'all': 'Todos',
              'cash': 'Efectivo',
              'transfer': 'Transferencia',
              'partner_contribution': 'Aportacion de socios',
            },
            onChanged: (value) => setState(() => _method = value),
          ),
        ),
        const SizedBox(height: 12),
        if (payments.isEmpty)
          const EmptyState(
            icon: Icons.payments_outlined,
            title: 'Sin pagos',
            message: 'Los abonos apareceran aqui.',
          )
        else
          ...payments.map(
            (payment) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                accent: payment.isCancelled
                    ? BrandColors.textMuted
                    : BrandColors.success,
                child: ListTile(
                  title: Text(payment.supplierName),
                  subtitle: Text(
                    '${DateFormat('dd/MM/yyyy').format(payment.paymentDate)} · '
                    '${_supplierPaymentMethodLabel(payment)} · ${payment.purchaseFolio}'
                    '${payment.reference.isEmpty ? '' : ' · Ref: ${payment.reference}'}',
                  ),
                  trailing: Wrap(
                    spacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (payment.isCancelled)
                        const Chip(label: Text('Cancelado'))
                      else
                        TextButton(
                          onPressed: () => _cancelSupplierPayment(
                            context,
                            repository: widget.repository,
                            payment: payment,
                          ),
                          child: const Text('Cancelar pago'),
                        ),
                      MoneyText(value: payment.amount),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SupplierStatementTab extends StatefulWidget {
  const _SupplierStatementTab({required this.repository, required this.data});

  final TacoPosRepository repository;
  final _PurchaseData data;

  @override
  State<_SupplierStatementTab> createState() => _SupplierStatementTabState();
}

class _SupplierStatementTabState extends State<_SupplierStatementTab> {
  String _supplierId = '';
  DateTime? _dueStart;
  DateTime? _dueEnd;

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const _PurchaseHeader(
          title: 'Estado de cuenta',
          subtitle: 'Cargos, abonos y saldo acumulado.',
        ),
        const SizedBox(height: 12),
        _FiltersWrap(
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                initialValue: _supplierId,
                decoration: const InputDecoration(labelText: 'Proveedor'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Todos')),
                  ...widget.data.suppliers.map(
                    (supplier) => DropdownMenuItem(
                      value: supplier.id,
                      child: Text(supplier.commercialName),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _supplierId = value ?? ''),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickDueBoundary(start: true),
              icon: const Icon(Icons.event_outlined),
              label: Text('Vencimiento inicial: ${_dueDateLabel(_dueStart)}'),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickDueBoundary(start: false),
              icon: const Icon(Icons.event_available_outlined),
              label: Text('Vencimiento final: ${_dueDateLabel(_dueEnd)}'),
            ),
            _quickButton('Vencidas', _setOverdue),
            _quickButton('Vencen hoy', _setToday),
            _quickButton('Esta semana', _setWeek),
            _quickButton('Este mes', _setMonth),
            TextButton.icon(
              onPressed: () => setState(() {
                _dueStart = null;
                _dueEnd = null;
              }),
              icon: const Icon(Icons.clear),
              label: const Text('Limpiar filtro'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const EmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Sin movimientos',
            message: 'Selecciona proveedor con compras o pagos.',
          )
        else
          _StatementTable(
            rows: rows,
            onViewPurchase: (purchaseId) => _openPurchaseDetail(purchaseId),
            onChangeDueDate: (purchaseId) => _openChangeDueDate(purchaseId),
            onEditPurchase: (purchaseId) => _openEditPurchase(purchaseId),
            onCancelPayment: (paymentId) => _openCancelPayment(paymentId),
          ),
      ],
    );
  }

  List<SupplierStatementRow> _buildRows() {
    final hasDueFilter = _dueStart != null || _dueEnd != null;
    final supplierIds = _supplierId.isEmpty
        ? <String>{
            ...widget.data.purchases.map((purchase) => purchase.supplierId),
            ...widget.data.payments.map((payment) => payment.supplierId),
          }
        : <String>{_supplierId};
    final rows = <SupplierStatementRow>[];
    for (final supplierId in supplierIds) {
      final purchases = widget.data.purchases.where((purchase) {
        if (purchase.supplierId != supplierId) return false;
        if (!hasDueFilter) return true;
        return _dateInRange(purchase.dueDate, _dueStart, _dueEnd);
      }).toList();
      final purchaseIds = purchases.map((purchase) => purchase.id).toSet();
      final payments = widget.data.payments.where((payment) {
        if (payment.supplierId != supplierId) return false;
        if (!hasDueFilter) return true;
        return purchaseIds.contains(payment.purchaseId);
      });
      rows.addAll(
        widget.repository.buildSupplierStatement(
          supplierId: supplierId,
          purchases: purchases,
          payments: payments,
        ),
      );
    }
    if (hasDueFilter) {
      rows.sort((a, b) {
        final byDue = _compareNullableDates(a.dueDate, b.dueDate);
        if (byDue != 0) return byDue;
        final bySupplier = a.supplierName.compareTo(b.supplierName);
        if (bySupplier != 0) return bySupplier;
        return a.date.compareTo(b.date);
      });
    } else {
      rows.sort((a, b) => b.date.compareTo(a.date));
    }
    return rows;
  }

  Widget _quickButton(String label, VoidCallback onPressed) {
    return OutlinedButton(onPressed: onPressed, child: Text(label));
  }

  Future<void> _pickDueBoundary({required bool start}) async {
    final initial = start ? _dueStart : _dueEnd;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _dueStart = picked;
      } else {
        _dueEnd = picked;
      }
    });
  }

  void _setOverdue() {
    final today = _startOfDay(DateTime.now());
    setState(() {
      _dueStart = DateTime(2024);
      _dueEnd = today.subtract(const Duration(days: 1));
    });
  }

  void _setToday() {
    final today = _startOfDay(DateTime.now());
    setState(() {
      _dueStart = today;
      _dueEnd = today;
    });
  }

  void _setWeek() {
    final today = _startOfDay(DateTime.now());
    setState(() {
      _dueStart = today;
      _dueEnd = today.add(const Duration(days: 6));
    });
  }

  void _setMonth() {
    final today = _startOfDay(DateTime.now());
    setState(() {
      _dueStart = today;
      _dueEnd = DateTime(today.year, today.month + 1, 0);
    });
  }

  void _openPurchaseDetail(String purchaseId) {
    final purchase = widget.data.purchases
        .where((purchase) => purchase.id == purchaseId)
        .firstOrNull;
    if (purchase == null) {
      showAppSnackBar(
        context,
        'No se encontro la compra seleccionada.',
        type: AppSnackBarType.error,
      );
      return;
    }
    _showPurchaseDetail(
      context,
      repository: widget.repository,
      purchase: purchase,
      payments: widget.data.payments,
      data: widget.data,
    );
  }

  void _openCancelPayment(String paymentId) {
    final payment = widget.data.payments
        .where((payment) => payment.id == paymentId)
        .firstOrNull;
    if (payment == null) {
      showAppSnackBar(
        context,
        'No se encontro el pago seleccionado.',
        type: AppSnackBarType.error,
      );
      return;
    }
    _cancelSupplierPayment(
      context,
      repository: widget.repository,
      payment: payment,
    );
  }

  Future<void> _openChangeDueDate(String purchaseId) async {
    final purchase = widget.data.purchases
        .where((purchase) => purchase.id == purchaseId)
        .firstOrNull;
    if (purchase == null) {
      showAppSnackBar(
        context,
        'No se encontro la compra seleccionada.',
        type: AppSnackBarType.error,
      );
      return;
    }
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangeDueDateDialog(
        repository: widget.repository,
        purchase: purchase,
      ),
    );
    if (!mounted || changed != true) return;
    showAppSnackBar(
      context,
      'Fecha de vencimiento actualizada.',
      type: AppSnackBarType.success,
    );
  }

  Future<void> _openEditPurchase(String purchaseId) async {
    final purchase = widget.data.purchases
        .where((purchase) => purchase.id == purchaseId)
        .firstOrNull;
    if (purchase == null) {
      showAppSnackBar(
        context,
        'No se encontro la compra seleccionada.',
        type: AppSnackBarType.error,
      );
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditSupplierPurchaseDialog(
        repository: widget.repository,
        data: widget.data,
        purchase: purchase,
      ),
    );
    if (!mounted || saved != true) return;
    showAppSnackBar(
      context,
      'Compra actualizada.',
      type: AppSnackBarType.success,
    );
  }
}

class _PurchaseKardexTab extends StatelessWidget {
  const _PurchaseKardexTab({required this.repository, required this.data});

  final TacoPosRepository repository;
  final _PurchaseData data;

  @override
  Widget build(BuildContext context) {
    final rows = <SupplierStatementRow>[];
    final supplierIds = <String>{
      ...data.purchases.map((purchase) => purchase.supplierId),
      ...data.payments.map((payment) => payment.supplierId),
    };
    for (final supplierId in supplierIds) {
      rows.addAll(
        repository.buildSupplierStatement(
          supplierId: supplierId,
          purchases: data.purchases,
          payments: data.payments,
        ),
      );
    }
    rows.addAll(
      data.contributions.map(
        (contribution) => SupplierStatementRow(
          date: contribution.date,
          type: 'Aportacion de socio',
          folio: contribution.purchaseFolio ?? '',
          charge: 0,
          credit: contribution.amount,
          balance: 0,
          method: contribution.method,
          notes:
              '${contribution.partnerName}${contribution.supplierName == null ? '' : ' · ${contribution.supplierName}'}',
          paymentId: contribution.linkedSupplierPaymentId,
          partnerName: contribution.partnerName,
          reference: contribution.reference,
          supplierName: contribution.supplierName ?? '',
        ),
      ),
    );
    rows.sort((a, b) => b.date.compareTo(a.date));
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const _PurchaseHeader(
          title: 'Kardex de compras y pagos',
          subtitle: 'Historial general de compras, abonos y saldos.',
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const EmptyState(
            icon: Icons.timeline_outlined,
            title: 'Sin movimientos',
            message: 'Las compras y pagos apareceran aqui.',
          )
        else
          _StatementTable(
            rows: rows,
            onCancelPayment: (paymentId) {
              final payment = data.payments
                  .where((payment) => payment.id == paymentId)
                  .firstOrNull;
              if (payment == null) {
                showAppSnackBar(
                  context,
                  'No se encontro el pago seleccionado.',
                  type: AppSnackBarType.error,
                );
                return;
              }
              _cancelSupplierPayment(
                context,
                repository: repository,
                payment: payment,
              );
            },
            onViewPurchase: (purchaseId) {
              final purchase = data.purchases
                  .where((purchase) => purchase.id == purchaseId)
                  .firstOrNull;
              if (purchase == null) {
                showAppSnackBar(
                  context,
                  'No se encontro la compra seleccionada.',
                  type: AppSnackBarType.error,
                );
                return;
              }
              _showPurchaseDetail(
                context,
                repository: repository,
                purchase: purchase,
                payments: data.payments,
                data: data,
              );
            },
          ),
      ],
    );
  }
}

class _PurchaseReportsTab extends StatelessWidget {
  const _PurchaseReportsTab({required this.repository, required this.data});

  final TacoPosRepository repository;
  final _PurchaseData data;

  @override
  Widget build(BuildContext context) {
    final rows = repository.buildPurchasesBySupplierReport(
      suppliers: data.suppliers,
      purchases: data.purchases,
      payments: data.payments,
    );
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _PurchaseHeader(
          title: 'Compras por proveedor',
          subtitle: 'Total comprado, pagado y saldo pendiente.',
          action: OutlinedButton.icon(
            onPressed: rows.isEmpty ? null : () => _export(context, rows),
            icon: const Icon(Icons.download_outlined),
            label: const Text('CSV'),
          ),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const EmptyState(
            icon: Icons.analytics_outlined,
            title: 'Sin reporte',
            message: 'Registra compras para ver el reporte.',
          )
        else
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                accent: row.balance > 0
                    ? BrandColors.accentYellow
                    : BrandColors.success,
                child: ListTile(
                  title: Text(row.supplierName),
                  subtitle: Text(
                    '${row.noteCount} notas · Dia pago: ${row.paymentWeekdayName}',
                  ),
                  trailing: Wrap(
                    spacing: 14,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Metric(label: 'Comprado', value: row.totalPurchased),
                      _Metric(label: 'Pagado', value: row.totalPaid),
                      _Metric(label: 'Saldo', value: row.balance),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        _PurchasesByItemReport(
          repository: repository,
          purchases: data.purchases,
        ),
      ],
    );
  }

  Future<void> _export(
    BuildContext context,
    List<PurchaseSupplierReportRow> rows,
  ) async {
    final csv = [
      'Proveedor,Total comprado,Total pagado,Saldo,Notas,Dia de pago',
      ...rows.map(
        (row) =>
            '"${row.supplierName}",${row.totalPurchased},${row.totalPaid},${row.balance},${row.noteCount},"${row.paymentWeekdayName}"',
      ),
    ].join('\n');
    final message = await exportCsvFile(
      fileName: 'compras-por-proveedor.csv',
      content: csv,
    );
    if (!context.mounted) return;
    showAppSnackBar(context, message, type: AppSnackBarType.success);
  }
}

class _PurchasesByItemReport extends StatelessWidget {
  const _PurchasesByItemReport({
    required this.repository,
    required this.purchases,
  });

  final TacoPosRepository repository;
  final List<SupplierPurchase> purchases;

  @override
  Widget build(BuildContext context) {
    final activePurchases = purchases.where(
      (purchase) => purchase.status != 'cancelled',
    );
    return FutureBuilder<List<SupplierPurchaseItem>>(
      future: repository.getSupplierPurchaseItemsForPurchases(activePurchases),
      builder: (context, snapshot) {
        final itemRows = repository.buildPurchasesByItemReport(
          items: snapshot.data ?? const [],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PurchaseHeader(
              title: 'Compras por insumo',
              subtitle: 'Agrupado por el insumo compartido con cocina.',
              action: OutlinedButton.icon(
                onPressed: itemRows.isEmpty
                    ? null
                    : () => _exportItems(context, itemRows),
                icon: const Icon(Icons.download_outlined),
                label: const Text('CSV'),
              ),
            ),
            const SizedBox(height: 12),
            if (snapshot.connectionState == ConnectionState.waiting)
              const LoadingPanel(message: 'Cargando compras por insumo...')
            else if (snapshot.hasError)
              EmptyState(
                icon: Icons.error_outline,
                title: 'No se pudo cargar el reporte',
                message: '${snapshot.error}',
              )
            else if (itemRows.isEmpty)
              const EmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Sin compras por insumo',
                message: 'Registra compras para ver este reporte.',
              )
            else
              ...itemRows.map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    accent: row.affectsKitchenPerformance
                        ? BrandColors.success
                        : BrandColors.textMuted,
                    child: ListTile(
                      title: Text(
                        row.itemName,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        '${row.noteCount} notas · '
                        'Rendimiento cocina: '
                        '${row.affectsKitchenPerformance ? 'Si' : 'No'}',
                      ),
                      trailing: Wrap(
                        spacing: 14,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _TextMetric(
                            label: 'Cantidad',
                            value: '${_qty(row.quantity)} ${row.unit}',
                          ),
                          _Metric(label: 'Total', value: row.total),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _exportItems(
    BuildContext context,
    List<PurchaseItemReportRow> rows,
  ) async {
    final csv = [
      'Insumo,Cantidad,Unidad,Total,Notas,Afecta rendimiento cocina',
      ...rows.map(
        (row) =>
            '"${row.itemName}",${row.quantity},"${row.unit}",${row.total},${row.noteCount},"${row.affectsKitchenPerformance ? 'Si' : 'No'}"',
      ),
    ].join('\n');
    final message = await exportCsvFile(
      fileName: 'compras-por-insumo.csv',
      content: csv,
    );
    if (!context.mounted) return;
    showAppSnackBar(context, message, type: AppSnackBarType.success);
  }
}

class _SupplierDialog extends StatefulWidget {
  const _SupplierDialog({required this.repository, this.supplier});

  final TacoPosRepository repository;
  final Supplier? supplier;

  @override
  State<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<_SupplierDialog> {
  late final TextEditingController _commercialController;
  late final TextEditingController _legalController;
  late final TextEditingController _rfcController;
  late final TextEditingController _phoneController;
  late final TextEditingController _contactController;
  late final TextEditingController _addressController;
  late final TextEditingController _creditDaysController;
  late final TextEditingController _notesController;
  late String _weekday;
  late String _method;
  late bool _active;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final supplier = widget.supplier;
    _commercialController = TextEditingController(
      text: supplier?.commercialName ?? '',
    );
    _legalController = TextEditingController(text: supplier?.legalName ?? '');
    _rfcController = TextEditingController(text: supplier?.rfc ?? '');
    _phoneController = TextEditingController(text: supplier?.phone ?? '');
    _contactController = TextEditingController(
      text: supplier?.contactName ?? '',
    );
    _addressController = TextEditingController(text: supplier?.address ?? '');
    _creditDaysController = TextEditingController(
      text: '${supplier?.creditDays ?? 0}',
    );
    _notesController = TextEditingController(text: supplier?.notes ?? '');
    _weekday = supplier?.paymentWeekday ?? 'none';
    _method = supplier?.preferredPaymentMethod ?? 'both';
    _active = supplier?.active ?? true;
  }

  @override
  void dispose() {
    _commercialController.dispose();
    _legalController.dispose();
    _rfcController.dispose();
    _phoneController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _creditDaysController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.supplier == null ? 'Nuevo proveedor' : 'Editar proveedor',
      ),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _field(_commercialController, 'Nombre comercial', width: 330),
              _field(_legalController, 'Razon social', width: 330),
              _field(_rfcController, 'RFC', width: 160),
              _field(_phoneController, 'Telefono', width: 180),
              _field(_contactController, 'Contacto', width: 260),
              _field(_addressController, 'Direccion', width: 400),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: _weekday,
                  decoration: const InputDecoration(labelText: 'Dia de pago'),
                  items: _weekdayLabels.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _weekday = value ?? 'none'),
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: _method,
                  decoration: const InputDecoration(
                    labelText: 'Forma preferida',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                    DropdownMenuItem(
                      value: 'transfer',
                      child: Text('Transferencia'),
                    ),
                    DropdownMenuItem(value: 'both', child: Text('Ambas')),
                  ],
                  onChanged: (value) =>
                      setState(() => _method = value ?? 'both'),
                ),
              ),
              _field(_creditDaysController, 'Dias credito', width: 140),
              SizedBox(
                width: 160,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  title: const Text('Activo'),
                  onChanged: (value) => setState(() => _active = value),
                ),
              ),
              _field(_notesController, 'Notas', width: 680, maxLines: 2),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando...' : 'Guardar'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    required double width,
    int maxLines = 1,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repository.saveSupplier(
        supplierId: widget.supplier?.id,
        commercialName: _commercialController.text,
        legalName: _legalController.text,
        rfc: _rfcController.text,
        phone: _phoneController.text,
        contactName: _contactController.text,
        address: _addressController.text,
        notes: _notesController.text,
        active: _active,
        preferredPaymentMethod: _method,
        creditDays: int.tryParse(_creditDaysController.text) ?? 0,
        paymentWeekday: _weekday,
        paymentWeekdayName: _weekdayLabels[_weekday] ?? 'Sin dia fijo',
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _PurchaseKitchenStockItemDialog extends StatefulWidget {
  const _PurchaseKitchenStockItemDialog({
    required this.repository,
    required this.suppliers,
    this.item,
  });

  final TacoPosRepository repository;
  final List<Supplier> suppliers;
  final KitchenStockItem? item;

  @override
  State<_PurchaseKitchenStockItemDialog> createState() =>
      _PurchaseKitchenStockItemDialogState();
}

class _PurchaseKitchenStockItemDialogState
    extends State<_PurchaseKitchenStockItemDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _unitController;
  late final TextEditingController _sortController;
  late final TextEditingController _notesController;
  String? _supplierId;
  late bool _active;
  late bool _affectsKitchenPerformance;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameController = TextEditingController(text: item?.name ?? '');
    _categoryController = TextEditingController(
      text: item?.category ?? 'General',
    );
    _unitController = TextEditingController(text: item?.unit ?? 'kg');
    _sortController = TextEditingController(text: '${item?.sortOrder ?? 99}');
    _notesController = TextEditingController(text: item?.notes ?? '');
    _supplierId = item?.defaultSupplierId;
    if (_supplierId != null &&
        !widget.suppliers.any((supplier) => supplier.id == _supplierId)) {
      _supplierId = null;
    }
    _active = item?.active ?? true;
    _affectsKitchenPerformance = item?.affectsKitchenPerformance ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _unitController.dispose();
    _sortController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Nuevo insumo' : 'Editar insumo'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _text(_nameController, 'Nombre', 260),
              _text(_categoryController, 'Categoria', 180),
              _text(_unitController, 'Unidad', 120),
              _text(_sortController, 'Orden', 100),
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  initialValue: _supplierId,
                  decoration: const InputDecoration(
                    labelText: 'Proveedor default',
                  ),
                  items: widget.suppliers
                      .map(
                        (supplier) => DropdownMenuItem(
                          value: supplier.id,
                          child: Text(supplier.commercialName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _supplierId = value),
                ),
              ),
              SizedBox(
                width: 300,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _affectsKitchenPerformance,
                  title: const Text('Afecta rendimiento de cocina'),
                  subtitle: const Text('Usarlo en apertura, cierre y merma.'),
                  onChanged: (value) =>
                      setState(() => _affectsKitchenPerformance = value),
                ),
              ),
              SizedBox(
                width: 160,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  title: const Text('Activo'),
                  onChanged: (value) => setState(() => _active = value),
                ),
              ),
              _text(_notesController, 'Notas', 560, maxLines: 2),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando...' : 'Guardar'),
        ),
      ],
    );
  }

  Widget _text(
    TextEditingController controller,
    String label,
    double width, {
    int maxLines = 1,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final supplier = widget.suppliers.where((item) => item.id == _supplierId);
    try {
      await widget.repository.saveKitchenStockItem(
        itemId: widget.item?.id,
        name: _nameController.text,
        category: _categoryController.text,
        unit: _unitController.text,
        active: _active,
        sortOrder: int.tryParse(_sortController.text.trim()) ?? 99,
        affectsKitchenPerformance: _affectsKitchenPerformance,
        defaultSupplierId: _supplierId,
        defaultSupplierName: supplier.isEmpty
            ? null
            : supplier.first.commercialName,
        notes: _notesController.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _PurchaseLineDialog extends StatefulWidget {
  const _PurchaseLineDialog({required this.items, this.initial});

  final List<KitchenStockItem> items;
  final PurchaseLineInput? initial;

  @override
  State<_PurchaseLineDialog> createState() => _PurchaseLineDialogState();
}

class _PurchaseLineDialogState extends State<_PurchaseLineDialog> {
  final _nameController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _unitController = TextEditingController(text: 'kg');
  final _costController = TextEditingController();
  final _notesController = TextEditingController();
  String? _itemId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    _itemId = initial.kitchenStockItemId ?? initial.purchaseItemId;
    if (_itemId != null &&
        !widget.items
            .where((item) => item.active)
            .any((item) => item.id == _itemId)) {
      _itemId = null;
    }
    _nameController.text =
        initial.kitchenStockItemName ?? initial.purchaseItemName;
    _qtyController.text = _formatQty(initial.quantity);
    _unitController.text = initial.unit;
    _costController.text = initial.unitCost.toStringAsFixed(2);
    _notesController.text = initial.notes;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _qtyController.dispose();
    _unitController.dispose();
    _costController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Agregar renglon' : 'Editar renglon',
      ),
      content: SizedBox(
        width: 520,
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 480,
              child: DropdownButtonFormField<String>(
                initialValue: _itemId,
                decoration: const InputDecoration(
                  labelText: 'Insumo catalogado',
                ),
                items: widget.items
                    .where((item) => item.active)
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    )
                    .toList(),
                onChanged: _selectItem,
              ),
            ),
            _field(_nameController, 'Nombre libre', 240),
            _field(_qtyController, 'Cantidad', 110),
            _field(_unitController, 'Unidad', 100),
            _field(_costController, 'Costo unitario', 140),
            _field(_notesController, 'Notas', 480),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.initial == null ? 'Agregar' : 'Guardar'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label, double width) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: label == 'Nombre libre'
            ? TextInputType.text
            : const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  void _selectItem(String? value) {
    final item = widget.items.where((item) => item.id == value);
    setState(() {
      _itemId = value;
      if (item.isNotEmpty) {
        _nameController.text = item.first.name;
        _unitController.text = item.first.unit;
      }
    });
  }

  void _submit() {
    final quantity = _parse(_qtyController.text);
    final unitCost = _parse(_costController.text);
    final name = _nameController.text.trim();
    final item = widget.items.where((item) => item.id == _itemId);
    if (item.isEmpty) {
      showAppSnackBar(context, 'Selecciona un insumo del catalogo.');
      return;
    }
    if (name.isEmpty || quantity <= 0 || unitCost < 0) {
      showAppSnackBar(context, 'Revisa nombre, cantidad y costo.');
      return;
    }
    Navigator.pop(
      context,
      PurchaseLineInput(
        supplierPurchaseItemId: widget.initial?.supplierPurchaseItemId,
        purchaseItemId: null,
        purchaseItemName: name,
        kitchenStockItemId: item.isEmpty ? null : item.first.id,
        kitchenStockItemName: item.isEmpty ? null : item.first.name,
        affectsKitchenStock:
            item.isNotEmpty && item.first.affectsKitchenPerformance,
        quantity: quantity,
        unit: _unitController.text.trim(),
        unitCost: unitCost,
        notes: _notesController.text,
      ),
    );
  }
}

class _EditSupplierPurchaseDialog extends StatefulWidget {
  const _EditSupplierPurchaseDialog({
    required this.repository,
    required this.data,
    required this.purchase,
  });

  final TacoPosRepository repository;
  final _PurchaseData data;
  final SupplierPurchase purchase;

  @override
  State<_EditSupplierPurchaseDialog> createState() =>
      _EditSupplierPurchaseDialogState();
}

class _EditSupplierPurchaseDialogState
    extends State<_EditSupplierPurchaseDialog> {
  late final TextEditingController _folioController;
  late final TextEditingController _notesController;
  late Future<List<SupplierPurchaseItem>> _itemsFuture;
  late String _supplierId;
  late String _documentType;
  late DateTime _purchaseDate;
  late DateTime _dueDate;
  final _lines = <PurchaseLineInput>[];
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _supplierId = widget.purchase.supplierId;
    _documentType = widget.purchase.documentType;
    _purchaseDate = widget.purchase.purchaseDate;
    _dueDate = widget.purchase.dueDate ?? widget.purchase.purchaseDate;
    _folioController = TextEditingController(text: widget.purchase.folio);
    _notesController = TextEditingController(text: widget.purchase.notes);
    _itemsFuture = widget.repository.getSupplierPurchaseItemsForPurchases([
      widget.purchase,
    ]);
  }

  @override
  void dispose() {
    _folioController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activePayments = widget.data.payments
        .where(
          (payment) =>
              payment.purchaseId == widget.purchase.id && payment.isActive,
        )
        .toList();
    final paidTotal = activePayments.fold<double>(
      0,
      (sum, payment) => sum + payment.amount,
    );
    final total = _lines.fold<double>(0, (sum, line) => sum + line.total);
    return AlertDialog(
      title: const Text('Editar compra a proveedor'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width.clamp(340, 980).toDouble(),
        child: FutureBuilder<List<SupplierPurchaseItem>>(
          future: _itemsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return EmptyState(
                icon: Icons.error_outline,
                title: 'No se pudo cargar la compra',
                message: '${snapshot.error}',
              );
            }
            if (!snapshot.hasData) {
              return const LoadingPanel(message: 'Cargando compra...');
            }
            if (!_loaded) {
              _lines.addAll(snapshot.data!.map(_lineFromPurchaseItem));
              _loaded = true;
            }
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (activePayments.isNotEmpty)
                    const GlassPanel(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Esta compra ya tiene pagos aplicados. No puedes reducir el total por debajo de lo pagado.',
                        style: TextStyle(
                          color: BrandColors.accentYellow,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 280,
                        child: DropdownButtonFormField<String>(
                          initialValue: _supplierId,
                          decoration: const InputDecoration(
                            labelText: 'Proveedor',
                          ),
                          items: widget.data.suppliers
                              .map(
                                (supplier) => DropdownMenuItem(
                                  value: supplier.id,
                                  child: Text(supplier.commercialName),
                                ),
                              )
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (value) =>
                                    setState(() => _supplierId = value ?? ''),
                        ),
                      ),
                      _editField(_folioController, 'Folio / nota', 180),
                      SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<String>(
                          initialValue: _documentType,
                          decoration: const InputDecoration(
                            labelText: 'Documento',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'note',
                              child: Text('Nota'),
                            ),
                            DropdownMenuItem(
                              value: 'invoice',
                              child: Text('Factura'),
                            ),
                            DropdownMenuItem(
                              value: 'ticket',
                              child: Text('Ticket'),
                            ),
                            DropdownMenuItem(
                              value: 'remision',
                              child: Text('Remision'),
                            ),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                  () => _documentType = value ?? 'note',
                                ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _pickDate(true),
                        icon: const Icon(Icons.event_outlined),
                        label: Text('Compra ${_dateLabel(_purchaseDate)}'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _pickDate(false),
                        icon: const Icon(Icons.event_available_outlined),
                        label: Text('Vence ${_dateLabel(_dueDate)}'),
                      ),
                      _editField(_notesController, 'Observaciones', 360),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Renglones',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _addLine,
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar articulo'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_lines.isEmpty)
                    const Text(
                      'Sin renglones.',
                      style: TextStyle(color: BrandColors.textMuted),
                    )
                  else
                    ..._lines.asMap().entries.map((entry) {
                      final line = entry.value;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(line.purchaseItemName),
                        subtitle: Text(
                          '${_formatQty(line.quantity)} ${line.unit} x ${_money(line.unitCost)}'
                          '${line.notes.trim().isEmpty ? '' : ' · ${line.notes}'}',
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            MoneyText(value: line.total),
                            IconButton(
                              tooltip: 'Editar renglon',
                              onPressed: _saving
                                  ? null
                                  : () => _editLine(entry.key),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Quitar renglon',
                              onPressed: _saving
                                  ? null
                                  : () => setState(
                                      () => _lines.removeAt(entry.key),
                                    ),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      );
                    }),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 14,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Metric(label: 'Pagado', value: paidTotal),
                        _Metric(label: 'Nuevo total', value: total),
                        _Metric(
                          label: 'Nuevo saldo',
                          value: (total - paidTotal).clamp(0, double.infinity),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : () => _save(paidTotal),
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Guardando...' : 'Guardar cambios'),
        ),
      ],
    );
  }

  Widget _editField(
    TextEditingController controller,
    String label,
    double width,
  ) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        enabled: !_saving,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Future<void> _pickDate(bool purchaseDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: purchaseDate ? _purchaseDate : _dueDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (purchaseDate) {
        _purchaseDate = picked;
      } else {
        _dueDate = picked;
      }
    });
  }

  Future<void> _addLine() async {
    final line = await showDialog<PurchaseLineInput>(
      context: context,
      builder: (_) => _PurchaseLineDialog(items: widget.data.kitchenStockItems),
    );
    if (line != null && mounted) {
      setState(() => _lines.add(line));
    }
  }

  Future<void> _editLine(int index) async {
    final line = await showDialog<PurchaseLineInput>(
      context: context,
      builder: (_) => _PurchaseLineDialog(
        items: widget.data.kitchenStockItems,
        initial: _lines[index],
      ),
    );
    if (line != null && mounted) {
      setState(() => _lines[index] = line);
    }
  }

  Future<void> _save(double paidTotal) async {
    final supplier = widget.data.suppliers
        .where((supplier) => supplier.id == _supplierId)
        .firstOrNull;
    if (supplier == null) {
      showAppSnackBar(context, 'Selecciona proveedor.');
      return;
    }
    if (_lines.isEmpty) {
      showAppSnackBar(context, 'La compra debe tener al menos un articulo.');
      return;
    }
    final total = _lines.fold<double>(0, (sum, line) => sum + line.total);
    if (total + 0.01 < paidTotal) {
      showAppSnackBar(
        context,
        'No puedes dejar el total menor a lo ya pagado. Esta compra tiene pagos aplicados por ${_money(paidTotal)}.',
        type: AppSnackBarType.warning,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.updateSupplierPurchase(
        purchase: widget.purchase,
        supplier: supplier,
        purchaseDate: _purchaseDate,
        dueDate: _dueDate,
        folio: _folioController.text,
        documentType: _documentType,
        items: _lines,
        notes: _notesController.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnackBar(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
        type: AppSnackBarType.error,
      );
    }
  }
}

class _SupplierPaymentDialog extends StatefulWidget {
  const _SupplierPaymentDialog({
    required this.repository,
    required this.purchase,
  });

  final TacoPosRepository repository;
  final SupplierPurchase purchase;

  @override
  State<_SupplierPaymentDialog> createState() => _SupplierPaymentDialogState();
}

class _SupplierPaymentDialogState extends State<_SupplierPaymentDialog> {
  late final TextEditingController _amountController;
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _paymentDate = DateTime.now();
  String _method = 'cash';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.purchase.balance.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar pago a proveedor'),
      content: SizedBox(
        width: 420,
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            Text('Saldo: ${_money(widget.purchase.balance)}'),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Monto'),
              ),
            ),
            SizedBox(
              width: 180,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _pickPaymentDate,
                icon: const Icon(Icons.event_outlined),
                label: Text(_dateLabel(_paymentDate)),
              ),
            ),
            SizedBox(
              width: 390,
              child: DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(labelText: 'Forma de pago'),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                  DropdownMenuItem(
                    value: 'transfer',
                    child: Text('Transferencia'),
                  ),
                  DropdownMenuItem(
                    value: 'partner_contribution',
                    child: Text('Aportacion de socios'),
                  ),
                ],
                onChanged: (value) => setState(() => _method = value ?? 'cash'),
              ),
            ),
            _dialogText(_referenceController, 'Referencia', 390),
            _dialogText(_notesController, 'Notas', 390),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando...' : 'Registrar pago'),
        ),
      ],
    );
  }

  Future<void> _pickPaymentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (picked != null && mounted) {
      setState(() => _paymentDate = picked);
    }
  }

  Widget _dialogText(
    TextEditingController controller,
    String label,
    double width,
  ) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repository.registerSupplierPayment(
        purchase: widget.purchase,
        amount: _parse(_amountController.text),
        fundingSource: _method,
        paymentDate: _paymentDate,
        reference: _referenceController.text,
        notes: _notesController.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

void _showPurchaseDetail(
  BuildContext context, {
  required TacoPosRepository repository,
  required SupplierPurchase purchase,
  required List<SupplierPayment> payments,
  required _PurchaseData data,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => _PurchaseDetailDialog(
      repository: repository,
      purchase: purchase,
      payments: payments,
      data: data,
    ),
  );
}

Future<void> _cancelSupplierPayment(
  BuildContext context, {
  required TacoPosRepository repository,
  required SupplierPayment payment,
  bool closeAfterSuccess = false,
}) async {
  if (payment.isCancelled) {
    showAppSnackBar(
      context,
      'Este pago ya fue cancelado.',
      type: AppSnackBarType.warning,
    );
    return;
  }
  final reason = await showDialog<String>(
    context: context,
    builder: (_) => const _CancelSupplierPaymentDialog(),
  );
  if (!context.mounted || reason == null) return;
  try {
    await repository.cancelSupplierPayment(payment: payment, reason: reason);
    if (!context.mounted) return;
    showAppSnackBar(context, 'Pago cancelado.', type: AppSnackBarType.success);
    if (closeAfterSuccess && context.mounted) {
      Navigator.pop(context);
    }
  } catch (error) {
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      error.toString().replaceFirst('Bad state: ', ''),
      type: AppSnackBarType.error,
    );
  }
}

class _CancelSupplierPaymentDialog extends StatefulWidget {
  const _CancelSupplierPaymentDialog();

  @override
  State<_CancelSupplierPaymentDialog> createState() =>
      _CancelSupplierPaymentDialogState();
}

class _CancelSupplierPaymentDialogState
    extends State<_CancelSupplierPaymentDialog> {
  final _reasonController = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancelar pago a proveedor'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Esta accion anulara el pago y regresara el saldo a la cuenta por pagar.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Motivo de cancelacion',
                errorText: _error.isEmpty ? null : _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final reason = _reasonController.text.trim();
            if (reason.isEmpty) {
              setState(() => _error = 'Captura el motivo de cancelacion.');
              return;
            }
            Navigator.pop(context, reason);
          },
          child: const Text('Confirmar cancelacion'),
        ),
      ],
    );
  }
}

class _CancelSupplierPurchaseDialog extends StatefulWidget {
  const _CancelSupplierPurchaseDialog();

  @override
  State<_CancelSupplierPurchaseDialog> createState() =>
      _CancelSupplierPurchaseDialogState();
}

class _CancelSupplierPurchaseDialogState
    extends State<_CancelSupplierPurchaseDialog> {
  final _reasonController = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancelar compra'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Esta accion cancelara la compra y la cuenta por pagar. '
              'No se eliminara el registro, solo quedara marcado como cancelado.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Motivo de cancelacion',
                errorText: _error.isEmpty ? null : _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final reason = _reasonController.text.trim();
            if (reason.isEmpty) {
              setState(() => _error = 'Captura el motivo de cancelacion.');
              return;
            }
            Navigator.pop(context, reason);
          },
          child: const Text('Confirmar cancelacion'),
        ),
      ],
    );
  }
}

class _PurchaseDetailDialog extends StatelessWidget {
  const _PurchaseDetailDialog({
    required this.repository,
    required this.purchase,
    required this.payments,
    required this.data,
  });

  final TacoPosRepository repository;
  final SupplierPurchase purchase;
  final List<SupplierPayment> payments;
  final _PurchaseData data;

  @override
  Widget build(BuildContext context) {
    final appliedPayments =
        payments.where((payment) => payment.purchaseId == purchase.id).toList()
          ..sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
    return AlertDialog(
      title: const Text('Detalle de compra'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width.clamp(320, 980).toDouble(),
        child: StreamBuilder<List<SupplierPurchaseItem>>(
          stream: repository.watchSupplierPurchaseItems(purchase.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return EmptyState(
                icon: Icons.error_outline,
                title: 'No se pudieron cargar productos',
                message: '${snapshot.error}',
              );
            }
            if (!snapshot.hasData) {
              return const LoadingPanel(message: 'Cargando detalle...');
            }
            final items = snapshot.data ?? const <SupplierPurchaseItem>[];
            final itemsTotal = items.fold<double>(
              0,
              (sum, item) => sum + item.total,
            );
            final totalsMatch = (itemsTotal - purchase.total).abs() <= 0.01;
            return LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PurchaseDetailSummary(
                        purchase: purchase,
                        itemsTotal: itemsTotal,
                      ),
                      if (!totalsMatch) ...[
                        const SizedBox(height: 12),
                        const GlassPanel(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'El total de los productos no coincide con el total registrado.',
                            style: TextStyle(
                              color: BrandColors.danger,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _PurchaseItemsDetail(items: items, compact: compact),
                      const SizedBox(height: 14),
                      _PurchasePaymentsDetail(
                        repository: repository,
                        payments: appliedPayments,
                        compact: compact,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        if (!purchase.isCancelled)
          OutlinedButton.icon(
            onPressed: () async {
              final saved = await showDialog<bool>(
                context: context,
                builder: (_) => _EditSupplierPurchaseDialog(
                  repository: repository,
                  data: data,
                  purchase: purchase,
                ),
              );
              if (!context.mounted || saved != true) return;
              Navigator.pop(context);
              showAppSnackBar(
                context,
                'Compra actualizada.',
                type: AppSnackBarType.success,
              );
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar compra'),
          ),
        if (!purchase.isCancelled)
          OutlinedButton.icon(
            onPressed: () async {
              final changed = await showDialog<bool>(
                context: context,
                builder: (_) => _ChangeDueDateDialog(
                  repository: repository,
                  purchase: purchase,
                ),
              );
              if (!context.mounted || changed != true) return;
              Navigator.pop(context);
              showAppSnackBar(
                context,
                'Fecha de vencimiento actualizada.',
                type: AppSnackBarType.success,
              );
            },
            icon: const Icon(Icons.event_available_outlined),
            label: const Text('Cambiar vencimiento'),
          ),
        if (purchase.hasBalance && !purchase.isCancelled)
          FilledButton.icon(
            onPressed: () async {
              final paid = await showDialog<bool>(
                context: context,
                builder: (_) => _SupplierPaymentDialog(
                  repository: repository,
                  purchase: purchase,
                ),
              );
              if (!context.mounted || paid != true) return;
              Navigator.pop(context);
              showAppSnackBar(
                context,
                'Pago registrado.',
                type: AppSnackBarType.success,
              );
            },
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Registrar pago'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _ChangeDueDateDialog extends StatefulWidget {
  const _ChangeDueDateDialog({
    required this.repository,
    required this.purchase,
  });

  final TacoPosRepository repository;
  final SupplierPurchase purchase;

  @override
  State<_ChangeDueDateDialog> createState() => _ChangeDueDateDialogState();
}

class _ChangeDueDateDialogState extends State<_ChangeDueDateDialog> {
  final _reasonController = TextEditingController();
  late DateTime _newDueDate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _newDueDate = widget.purchase.dueDate ?? widget.purchase.purchaseDate;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar fecha de vencimiento'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DetailValue(
              label: 'Proveedor',
              value: widget.purchase.supplierName,
            ),
            const SizedBox(height: 10),
            _DetailValue(
              label: 'Folio / nota',
              value: widget.purchase.folio.isEmpty
                  ? 'Sin folio'
                  : widget.purchase.folio,
            ),
            const SizedBox(height: 10),
            _DetailValue(
              label: 'Fecha compra',
              value: _dateLabel(widget.purchase.purchaseDate),
            ),
            const SizedBox(height: 10),
            _DetailValue(
              label: 'Fecha vencimiento actual',
              value: _dueDateLabel(widget.purchase.dueDate),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickDueDate,
              icon: const Icon(Icons.event_available_outlined),
              label: Text('Nueva fecha: ${_dateLabel(_newDueDate)}'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              enabled: !_saving,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  color: BrandColors.danger,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Guardando...' : 'Guardar cambio'),
        ),
      ],
    );
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _newDueDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked != null && mounted) {
      setState(() => _newDueDate = picked);
    }
  }

  Future<void> _save() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Captura el motivo del cambio.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.updateSupplierPurchaseDueDate(
        purchase: widget.purchase,
        dueDate: _newDueDate,
        reason: reason,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }
}

class _PurchaseDetailSummary extends StatelessWidget {
  const _PurchaseDetailSummary({
    required this.purchase,
    required this.itemsTotal,
  });

  final SupplierPurchase purchase;
  final double itemsTotal;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 18,
        runSpacing: 12,
        children: [
          _DetailValue(label: 'Proveedor', value: purchase.supplierName),
          _DetailValue(label: 'Sucursal', value: purchase.branchName),
          _DetailValue(
            label: 'Fecha compra',
            value: DateFormat('dd/MM/yyyy').format(purchase.purchaseDate),
          ),
          _DetailValue(
            label: 'Fecha vencimiento',
            value: _dueDateLabel(purchase.dueDate),
          ),
          _DetailValue(label: 'Vencimiento', value: _dueStatusLabel(purchase)),
          _DetailValue(
            label: 'Folio',
            value: purchase.folio.isEmpty ? 'Sin folio' : purchase.folio,
          ),
          _DetailValue(
            label: 'Documento',
            value: _documentTypeLabel(purchase.documentType),
          ),
          _DetailValue(
            label: 'Estado',
            value: _purchaseStatusLabel(purchase.status),
          ),
          _DetailValue(
            label: 'Total registrado',
            value: _money(purchase.total),
          ),
          _DetailValue(label: 'Total renglones', value: _money(itemsTotal)),
          _DetailValue(label: 'Pagado', value: _money(purchase.paidTotal)),
          _DetailValue(label: 'Saldo', value: _money(purchase.balance)),
          if (purchase.isCancelled) ...[
            _DetailValue(
              label: 'Motivo',
              value: purchase.cancelReason?.trim().isEmpty == false
                  ? purchase.cancelReason!.trim()
                  : '-',
            ),
            _DetailValue(
              label: 'Cancelo',
              value: purchase.cancelledByEmployeeName?.trim().isEmpty == false
                  ? purchase.cancelledByEmployeeName!.trim()
                  : '-',
            ),
            _DetailValue(
              label: 'Fecha cancelacion',
              value: _dateTimeLabel(purchase.cancelledAt),
            ),
          ],
          _DetailValue(
            label: 'Usuario',
            value: purchase.createdByEmployeeName.isEmpty
                ? 'Sin usuario'
                : purchase.createdByEmployeeName,
          ),
          _DetailValue(
            label: 'Registro',
            value: _dateTimeLabel(purchase.createdAt),
          ),
          if (purchase.notes.trim().isNotEmpty)
            _DetailValue(label: 'Observaciones', value: purchase.notes),
        ],
      ),
    );
  }
}

class _DetailValue extends StatelessWidget {
  const _DetailValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: BrandColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _PurchaseItemsDetail extends StatelessWidget {
  const _PurchaseItemsDetail({required this.items, required this.compact});

  final List<SupplierPurchaseItem> items;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Productos',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Text(
              'Sin productos guardados en esta compra.',
              style: TextStyle(color: BrandColors.textMuted),
            )
          else if (compact)
            ...items.map(_itemCard)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Insumo')),
                  DataColumn(label: Text('Cantidad')),
                  DataColumn(label: Text('Unidad')),
                  DataColumn(label: Text('Costo unitario')),
                  DataColumn(label: Text('Total')),
                  DataColumn(label: Text('Notas')),
                ],
                rows: items
                    .map(
                      (item) => DataRow(
                        cells: [
                          DataCell(Text(_purchaseItemName(item))),
                          DataCell(Text(_formatQty(item.quantity))),
                          DataCell(Text(item.unit)),
                          DataCell(Text(_money(item.unitCost))),
                          DataCell(Text(_money(item.total))),
                          DataCell(Text(item.notes)),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _itemCard(SupplierPurchaseItem item) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        _purchaseItemName(item),
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(
        '${_formatQty(item.quantity)} ${item.unit} x ${_money(item.unitCost)}'
        '${item.notes.trim().isEmpty ? '' : '\n${item.notes}'}',
      ),
      trailing: MoneyText(value: item.total),
    );
  }
}

class _PurchasePaymentsDetail extends StatelessWidget {
  const _PurchasePaymentsDetail({
    required this.repository,
    required this.payments,
    required this.compact,
  });

  final TacoPosRepository repository;
  final List<SupplierPayment> payments;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Pagos aplicados',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (payments.isEmpty)
            const Text(
              'Sin pagos aplicados.',
              style: TextStyle(color: BrandColors.textMuted),
            )
          else if (compact)
            ...payments.map((payment) => _paymentCard(context, payment))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Fecha')),
                  DataColumn(label: Text('Forma de pago')),
                  DataColumn(label: Text('Monto')),
                  DataColumn(label: Text('Referencia')),
                  DataColumn(label: Text('Socio')),
                  DataColumn(label: Text('Usuario')),
                  DataColumn(label: Text('Observaciones')),
                  DataColumn(label: Text('Estado / accion')),
                ],
                rows: payments
                    .map(
                      (payment) => DataRow(
                        cells: [
                          DataCell(Text(_dateTimeLabel(payment.paymentDate))),
                          DataCell(Text(_supplierPaymentMethodLabel(payment))),
                          DataCell(Text(_money(payment.amount))),
                          DataCell(Text(payment.reference)),
                          DataCell(Text(payment.partnerName ?? '')),
                          DataCell(Text(_paymentUser(payment))),
                          DataCell(
                            Text(
                              payment.isCancelled
                                  ? '${payment.cancelReason ?? ''}\nCancelado por: ${payment.cancelledByEmployeeName ?? ''}\nFecha: ${_dateTimeLabel(payment.cancelledAt)}'
                                  : payment.notes,
                            ),
                          ),
                          DataCell(
                            payment.isCancelled
                                ? const Chip(label: Text('Cancelado'))
                                : TextButton(
                                    onPressed: () => _cancelSupplierPayment(
                                      context,
                                      repository: repository,
                                      payment: payment,
                                      closeAfterSuccess: true,
                                    ),
                                    child: const Text('Cancelar pago'),
                                  ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _paymentCard(BuildContext context, SupplierPayment payment) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        '${_supplierPaymentMethodLabel(payment)} · ${_money(payment.amount)}',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(
        '${_dateTimeLabel(payment.paymentDate)} · ${_paymentUser(payment)}'
        '\nForma: ${_supplierPaymentMethodLabel(payment)}'
        '${payment.partnerName == null ? '' : '\nSocio: ${payment.partnerName}'}'
        '${payment.reference.trim().isEmpty ? '' : '\nRef: ${payment.reference}'}'
        '${payment.isCancelled
            ? '\nMotivo: ${payment.cancelReason ?? ''}\nCancelado por: ${payment.cancelledByEmployeeName ?? ''}'
                  '\nFecha: ${_dateTimeLabel(payment.cancelledAt)}'
            : payment.notes.trim().isEmpty
            ? ''
            : '\n${payment.notes}'}',
      ),
      trailing: payment.isCancelled
          ? const Chip(label: Text('Cancelado'))
          : TextButton(
              onPressed: () => _cancelSupplierPayment(
                context,
                repository: repository,
                payment: payment,
                closeAfterSuccess: true,
              ),
              child: const Text('Cancelar'),
            ),
    );
  }
}

class _StatementTable extends StatelessWidget {
  const _StatementTable({
    required this.rows,
    this.onViewPurchase,
    this.onChangeDueDate,
    this.onEditPurchase,
    this.onCancelPayment,
  });

  final List<SupplierStatementRow> rows;
  final ValueChanged<String>? onViewPurchase;
  final ValueChanged<String>? onChangeDueDate;
  final ValueChanged<String>? onEditPurchase;
  final ValueChanged<String>? onCancelPayment;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Fecha')),
            DataColumn(label: Text('Proveedor')),
            DataColumn(label: Text('Vencimiento')),
            DataColumn(label: Text('Tipo')),
            DataColumn(label: Text('Folio')),
            DataColumn(label: Text('Cargo')),
            DataColumn(label: Text('Abono')),
            DataColumn(label: Text('Saldo')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Forma de pago')),
            DataColumn(label: Text('Socio')),
            DataColumn(label: Text('Referencia')),
            DataColumn(label: Text('Notas')),
            DataColumn(label: Text('Acciones')),
          ],
          rows: rows
              .map(
                (row) => DataRow(
                  cells: [
                    DataCell(Text(DateFormat('dd/MM').format(row.date))),
                    DataCell(Text(row.supplierName)),
                    DataCell(Text(_dueDateLabel(row.dueDate))),
                    DataCell(Text(row.type)),
                    DataCell(Text(row.folio)),
                    DataCell(Text(_money(row.charge))),
                    DataCell(Text(_money(row.credit))),
                    DataCell(Text(_money(row.balance))),
                    DataCell(Text(_purchaseStatusLabel(row.status))),
                    DataCell(Text(_statementPaymentMethodLabel(row))),
                    DataCell(Text(row.partnerName ?? '')),
                    DataCell(Text(row.reference)),
                    DataCell(Text(row.notes)),
                    DataCell(
                      Wrap(
                        spacing: 8,
                        children: [
                          if (row.type.startsWith('Compra') &&
                              row.purchaseId != null &&
                              onViewPurchase != null)
                            TextButton(
                              onPressed: () => onViewPurchase!(row.purchaseId!),
                              child: const Text('Ver detalle'),
                            ),
                          if (row.type == 'Compra' &&
                              row.purchaseId != null &&
                              onChangeDueDate != null)
                            TextButton(
                              onPressed: () =>
                                  onChangeDueDate!(row.purchaseId!),
                              child: const Text('Cambiar vencimiento'),
                            ),
                          if (row.type == 'Compra' &&
                              row.purchaseId != null &&
                              onEditPurchase != null)
                            TextButton(
                              onPressed: () => onEditPurchase!(row.purchaseId!),
                              child: const Text('Editar compra'),
                            ),
                          if (row.status == 'cancelled')
                            Chip(
                              label: Text(
                                row.type == 'Compra cancelada'
                                    ? 'Compra cancelada'
                                    : 'Pago cancelado',
                              ),
                            )
                          else if (row.paymentId != null &&
                              row.type.startsWith('Pago') &&
                              onCancelPayment != null)
                            TextButton(
                              onPressed: () => onCancelPayment!(row.paymentId!),
                              child: const Text('Cancelar pago'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _PurchaseHeader extends StatelessWidget {
  const _PurchaseHeader({
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: SectionHeader(title: title, subtitle: subtitle),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _FiltersWrap extends StatelessWidget {
  const _FiltersWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Wrap(spacing: 10, runSpacing: 10, children: children),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: values.entries
            .map(
              (entry) =>
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: BrandColors.textMuted, fontSize: 11),
        ),
        MoneyText(
          value: value,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _TextMetric extends StatelessWidget {
  const _TextMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: BrandColors.textMuted, fontSize: 11),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

String _qty(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}

String _categoryLabel(String category) {
  return switch (category) {
    'meat' => 'Carne',
    'tortilla' => 'Tortilla',
    'dairy' => 'Lacteo',
    'drink' => 'Bebida',
    'water' => 'Agua',
    _ => category.trim().isEmpty ? 'General' : category,
  };
}

String _unitLabel(String unit) {
  return switch (unit) {
    'piece' => 'pieza',
    'liter' => 'litro',
    _ => unit,
  };
}

const _weekdayLabels = {
  'monday': 'Lunes',
  'tuesday': 'Martes',
  'wednesday': 'Miercoles',
  'thursday': 'Jueves',
  'friday': 'Viernes',
  'saturday': 'Sabado',
  'sunday': 'Domingo',
  'none': 'Sin dia fijo',
};

String _paymentMethodLabel(String method) {
  return switch (method) {
    'cash' => 'Efectivo',
    'transfer' => 'Transferencia',
    'partner_contribution' => 'Aportacion de socios',
    'both' => 'Ambas',
    '' => '',
    _ => method,
  };
}

String _supplierPaymentMethodLabel(SupplierPayment payment) {
  return _paymentMethodLabel(_normalizeSupplierPaymentMethod(payment.method));
}

String _statementPaymentMethodLabel(SupplierStatementRow row) {
  final method = _normalizeSupplierPaymentMethod(row.method);
  if (method.isEmpty) return row.fundingSourceName;
  return _paymentMethodLabel(method);
}

String _normalizeSupplierPaymentMethod(String value) {
  return switch (value) {
    'business_cash' || 'cash' => 'cash',
    'business_transfer' || 'transfer' => 'transfer',
    'partner_cash' ||
    'partner_transfer' ||
    'partner_contribution' => 'partner_contribution',
    _ => value,
  };
}

String _purchaseStatusLabel(String status) {
  return switch (status) {
    'pending' => 'Pendiente',
    'partial' => 'Parcial',
    'paid' => 'Pagada',
    'cancelled' => 'Cancelada',
    _ => status,
  };
}

String _documentTypeLabel(String type) {
  return switch (type) {
    'note' => 'Nota',
    'invoice' => 'Factura',
    'ticket' => 'Ticket',
    'remision' => 'Remision',
    _ => type,
  };
}

String _dateTimeLabel(DateTime? value) {
  if (value == null) {
    return 'Sin fecha';
  }
  return DateFormat('dd/MM/yyyy HH:mm').format(value);
}

String _dateLabel(DateTime value) {
  return DateFormat('dd/MM/yyyy').format(value);
}

String _dueDateLabel(DateTime? value) {
  if (value == null) {
    return 'Sin vencimiento';
  }
  return _dateLabel(value);
}

DateTime _startOfDay(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

bool _dateInRange(DateTime? value, DateTime? start, DateTime? end) {
  if (value == null) return false;
  final day = _startOfDay(value);
  final startDay = start == null ? null : _startOfDay(start);
  final endDay = end == null ? null : _startOfDay(end);
  if (startDay != null && day.isBefore(startDay)) return false;
  if (endDay != null && day.isAfter(endDay)) return false;
  return true;
}

int _compareNullableDates(DateTime? a, DateTime? b) {
  if (a != null && b != null) return a.compareTo(b);
  if (a != null) return -1;
  if (b != null) return 1;
  return 0;
}

String _dueStatusLabel(SupplierPurchase purchase) {
  if (purchase.isCancelled) return 'Cancelada';
  final dueDate = purchase.dueDate;
  if (dueDate == null) return 'Sin vencimiento';
  if (!purchase.hasBalance) return 'Sin saldo';
  final today = _startOfDay(DateTime.now());
  final dueDay = _startOfDay(dueDate);
  final diff = dueDay.difference(today).inDays;
  if (diff < 0) return 'Vencida hace ${diff.abs()} dias';
  if (diff == 0) return 'Vence hoy';
  if (diff <= 7) return 'Por vencer en $diff dias';
  return 'Por vencer';
}

Color _purchaseDueAccent(SupplierPurchase purchase) {
  if (purchase.isCancelled) return BrandColors.textMuted;
  if (!purchase.hasBalance) return BrandColors.success;
  final dueDate = purchase.dueDate;
  if (dueDate == null) return BrandColors.textMuted;
  final today = _startOfDay(DateTime.now());
  final dueDay = _startOfDay(dueDate);
  if (dueDay.isBefore(today)) return BrandColors.danger;
  if (dueDay.difference(today).inDays <= 7) return BrandColors.accentYellow;
  return BrandColors.success;
}

String _paymentUser(SupplierPayment payment) {
  return payment.createdByEmployeeName.trim().isEmpty
      ? 'Sin usuario'
      : payment.createdByEmployeeName;
}

bool _canCancelSupplierPurchase() {
  final employee = AppSession.instance.employee;
  return employee?.hasAdminAccess == true ||
      employee?.canRegisterPurchases == true ||
      employee?.canManageSuppliers == true ||
      employee?.canViewPurchases == true ||
      employee?.canViewAccountsPayable == true ||
      employee?.name.toLowerCase().trim() == 'admin';
}

String _purchaseItemName(SupplierPurchaseItem item) {
  final kitchenName = item.kitchenStockItemName?.trim();
  if (kitchenName != null && kitchenName.isNotEmpty) {
    return kitchenName;
  }
  return item.purchaseItemName;
}

PurchaseLineInput _lineFromPurchaseItem(SupplierPurchaseItem item) {
  return PurchaseLineInput(
    supplierPurchaseItemId: item.id,
    purchaseItemId: item.purchaseItemId,
    purchaseItemName: item.purchaseItemName,
    kitchenStockItemId: item.kitchenStockItemId,
    kitchenStockItemName: item.kitchenStockItemName,
    affectsKitchenStock: item.affectsKitchenStock,
    quantity: item.quantity,
    unit: item.unit,
    unitCost: item.unitCost,
    notes: item.notes,
  );
}

double _parse(String value) {
  return double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
}

String _money(double value) {
  return '\$${value.toStringAsFixed(2)}';
}

String _formatQty(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
