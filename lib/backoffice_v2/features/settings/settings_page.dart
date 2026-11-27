import 'package:flutter/material.dart';

import '../../../models/branch.dart';
import '../../../models/order_platform.dart';
import '../../../models/pos_table.dart';
import '../../../models/product.dart';
import '../../../models/product_category.dart';
import '../../../models/product_recipe_item.dart';
import '../../auth/backoffice_session.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../widgets/empty_error_state.dart';
import '../../widgets/saas_card.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/status_pill.dart';
import 'settings_repository.dart';

enum _SettingsTab {
  products('Productos'),
  categories('Categorías'),
  branches('Sucursales'),
  tablesAndChannels('Mesas y Canales'),
  operations('Finanzas y Operación'),
  devices('Dispositivos');

  const _SettingsTab(this.label);
  final String label;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.session,
    required this.repository,
  });

  final BackofficeSession session;
  final SettingsRepository repository;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _SettingsTab _tab = _SettingsTab.products;
  final TextEditingController _searchCtrl = TextEditingController();
  Future<SettingsBundle>? _future;
  String? _lastBranchId;
  String _lastRestaurantId = '';

  @override
  void initState() {
    super.initState();
    _lastBranchId = widget.session.selectedBranchId;
    _lastRestaurantId = widget.session.restaurantId;
    widget.session.addListener(_onSessionChanged);
    _load();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (_lastBranchId != widget.session.selectedBranchId ||
        _lastRestaurantId != widget.session.restaurantId) {
      _lastBranchId = widget.session.selectedBranchId;
      _lastRestaurantId = widget.session.restaurantId;
      _load();
    }
  }

  void _load() {
    setState(() {
      _future = widget.repository.loadAll(
        restaurantId: widget.session.restaurantId,
        branchId: widget.session.selectedBranchId,
      );
    });
  }

  Future<bool> _confirmDangerous(String title, String message) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _openProductDialog(
    SettingsBundle bundle,
    Product? existing,
  ) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(
      text: existing != null ? existing.price.toStringAsFixed(2) : '',
    );
    final costCtrl = TextEditingController(
      text: existing?.unitCost != null
          ? existing!.unitCost!.toStringAsFixed(2)
          : '',
    );
    var catName = existing?.categoryName ??
        (bundle.categories.isNotEmpty ? bundle.categories.first.name : 'Tacos');
    var catId = existing?.categoryId ??
        (bundle.categories.isNotEmpty ? bundle.categories.first.id : 'tacos');
    var active = existing?.active ?? true;
    var sendToKitchen = existing?.sendToKitchen ?? true;
    var affectsStock = existing?.affectsKitchenStock ?? false;
    var stockItemId = existing?.kitchenStockItemId ??
        (bundle.stockItems.isNotEmpty ? bundle.stockItems.first.id : '');
    final factorCtrl = TextEditingController(
      text: (existing?.stockConsumptionQty ?? 1.0).toString(),
    );
    final platformCtrls = <String, TextEditingController>{
      for (final p in bundle.platforms.where((p) => p.id != 'en_persona'))
        p.id: TextEditingController(
          text: existing?.platformPrices[p.id]?.toStringAsFixed(2) ?? '',
        ),
    };
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            existing == null ? 'Nuevo producto' : 'Editar · ${existing.name}',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  const SizedBox(height: 10),
                  if (bundle.categories.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: bundle.categories.any((c) => c.id == catId)
                          ? catId
                          : bundle.categories.first.id,
                      decoration: const InputDecoration(labelText: 'Categoría'),
                      items: bundle.categories
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (v) {
                        if (v == null) return;
                        final c = bundle.categories.firstWhere((e) => e.id == v);
                        setS(() {
                          catId = c.id;
                          catName = c.name;
                        });
                      },
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Precio base (\$)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: costCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Costo unitario (\$ opc.)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (platformCtrls.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Precios por plataforma (opcional)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    for (final p in bundle.platforms.where(
                      (p) => p.id != 'en_persona',
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextField(
                          controller: platformCtrls[p.id],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Precio ${p.name}',
                            isDense: true,
                          ),
                        ),
                      ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Producto activo'),
                    value: active,
                    onChanged: (v) => setS(() => active = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enviar a cocina (Android KDS)'),
                    value: sendToKitchen,
                    onChanged: (v) => setS(() => sendToKitchen = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Descuenta insumo de cocina'),
                    value: affectsStock,
                    onChanged: (v) => setS(() => affectsStock = v),
                  ),
                  if (affectsStock && bundle.stockItems.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      initialValue:
                          bundle.stockItems.any((s) => s.id == stockItemId)
                          ? stockItemId
                          : bundle.stockItems.first.id,
                      decoration: const InputDecoration(
                        labelText: 'Insumo de cocina',
                      ),
                      items: bundle.stockItems
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.id,
                              child: Text('${s.name} (${s.unit})'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (v) {
                        if (v != null) setS(() => stockItemId = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: factorCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Consumo por unidad vendida',
                      ),
                    ),
                  ],
                ],
              ),
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
                      final price = double.tryParse(priceCtrl.text.trim());
                      if (nameCtrl.text.trim().isEmpty ||
                          price == null ||
                          price < 0) {
                        return;
                      }
                      if (existing != null && existing.price != price) {
                        final ok = await _confirmDangerous(
                          'Confirmar cambio de precio',
                          'Cambiar el precio de ${existing.name} afecta las ventas en Android POS.',
                        );
                        if (!ok) return;
                      }
                      setS(() => saving = true);
                      final platformPrices = <String, double>{};
                      for (final e in platformCtrls.entries) {
                        final val = double.tryParse(e.value.text.trim());
                        if (val != null && val > 0) platformPrices[e.key] = val;
                      }
                      final recipes = <ProductRecipeItem>[];
                      if (affectsStock && bundle.stockItems.isNotEmpty) {
                        final stock = bundle.stockItems.firstWhere(
                          (s) => s.id == stockItemId,
                          orElse: () => bundle.stockItems.first,
                        );
                        recipes.add(
                          ProductRecipeItem(
                            kitchenStockItemId: stock.id,
                            kitchenStockItemName: stock.name,
                            kitchenStockUnit: stock.unit,
                            consumptionFactor:
                                double.tryParse(factorCtrl.text.trim()) ?? 1.0,
                          ),
                        );
                      }
                      final emp = widget.session.employee;
                      await widget.repository.saveProduct(
                        restaurantId: widget.session.restaurantId,
                        productId: existing?.id,
                        name: nameCtrl.text,
                        categoryId: catId,
                        categoryName: catName,
                        price: price,
                        unitCost: double.tryParse(costCtrl.text.trim()),
                        platformPrices: platformPrices,
                        active: active,
                        sendToKitchen: sendToKitchen,
                        affectsKitchenStock: affectsStock,
                        recipeItems: recipes,
                        sortOrder:
                            existing?.sortOrder ?? (bundle.products.length + 1),
                        actorId: emp?.id ?? '',
                        actorName: emp?.name ?? 'Admin',
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    },
              child: Text(saving ? 'Guardando...' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _openCategoryDialog(
    SettingsBundle bundle,
    ProductCategory? existing,
  ) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final colorCtrl = TextEditingController(
      text: existing?.colorHex ?? '#F97316',
    );
    var active = existing?.active ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            existing == null ? 'Nueva categoría' : 'Editar categoría',
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: colorCtrl,
                  decoration: const InputDecoration(labelText: 'Color Hex'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activa'),
                  value: active,
                  onChanged: (v) => setS(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    final emp = widget.session.employee;
    await widget.repository.saveProductCategory(
      restaurantId: widget.session.restaurantId,
      categoryId: existing?.id,
      name: nameCtrl.text,
      sortOrder: existing?.sortOrder ?? (bundle.categories.length + 1),
      colorHex: colorCtrl.text,
      active: active,
      actorId: emp?.id ?? '',
      actorName: emp?.name ?? 'Admin',
    );
    if (mounted) _load();
  }

  Future<void> _openBranchDialog(SettingsBundle bundle, Branch? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final addrCtrl = TextEditingController(text: existing?.address ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final tzCtrl = TextEditingController(
      text: existing?.timezone ?? 'America/Mexico_City',
    );
    var active = existing?.active ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(existing == null ? 'Nueva sucursal' : 'Editar sucursal'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: addrCtrl,
                  decoration: const InputDecoration(labelText: 'Dirección'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: tzCtrl,
                  decoration: const InputDecoration(labelText: 'Zona horaria'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sucursal activa'),
                  value: active,
                  onChanged: (v) => setS(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    if (existing != null && existing.active && !active) {
      final confirm = await _confirmDangerous(
        'Desactivar sucursal',
        'Desactivar ${existing.name} restringirá operaciones en esa sucursal.',
      );
      if (!confirm) return;
    }
    final emp = widget.session.employee;
    await widget.repository.saveBranch(
      restaurantId: widget.session.restaurantId,
      restaurantName: bundle.restaurantName,
      branchId: existing?.id,
      name: nameCtrl.text,
      address: addrCtrl.text,
      phone: phoneCtrl.text,
      timezone: tzCtrl.text,
      sortOrder: existing?.sortOrder ?? (bundle.branches.length + 1),
      active: active,
      actorId: emp?.id ?? '',
      actorName: emp?.name ?? 'Admin',
    );
    if (mounted) _load();
  }

  Future<void> _openTableDialog(SettingsBundle bundle, PosTable? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var type = existing?.type == 'takeout_entry' ? 'takeout_entry' : 'table';
    var active = existing?.active ?? true;
    final branch = bundle.branches.firstWhere(
      (b) => b.id == (existing?.branchId ?? widget.session.selectedBranchId),
      orElse: () => bundle.branches.first,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(existing == null ? 'Nueva mesa / canal' : 'Editar mesa'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(value: 'table', child: Text('Mesa')),
                    DropdownMenuItem(
                      value: 'takeout_entry',
                      child: Text('Para llevar / Mostrador'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setS(() => type = v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activa'),
                  value: active,
                  onChanged: (v) => setS(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    final emp = widget.session.employee;
    await widget.repository.saveTable(
      restaurantId: widget.session.restaurantId,
      restaurantName: bundle.restaurantName,
      branchId: branch.id,
      branchName: branch.name,
      tableId: existing?.id,
      name: nameCtrl.text,
      type: type,
      sortOrder: existing?.sortOrder ?? (bundle.tables.length + 1),
      active: active,
      actorId: emp?.id ?? '',
      actorName: emp?.name ?? 'Admin',
    );
    if (mounted) _load();
  }

  Future<void> _openPlatformDialog(
    SettingsBundle bundle,
    OrderPlatform? existing,
  ) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var active = existing?.active ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            existing == null ? 'Nueva plataforma' : 'Editar plataforma',
          ),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activa'),
                  value: active,
                  onChanged: (v) => setS(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    final emp = widget.session.employee;
    await widget.repository.saveOrderPlatform(
      restaurantId: widget.session.restaurantId,
      platformId: existing?.id,
      name: nameCtrl.text,
      sortOrder: existing?.sortOrder ?? (bundle.platforms.length + 1),
      active: active,
      actorId: emp?.id ?? '',
      actorName: emp?.name ?? 'Admin',
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Configuración General y Catálogos',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Productos, categorías, sucursales, mesas, plataformas, políticas operativas y dispositivos.',
                style: TextStyle(fontSize: 13, color: tokens.textSecondary),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _SettingsTab.values
                    .map(
                      (t) => ChoiceChip(
                        label: Text(t.label),
                        selected: _tab == t,
                        onSelected: (_) => setState(() => _tab = t),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 16),
              FutureBuilder<SettingsBundle>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const TableSkeleton(rows: 6);
                  }
                  if (snap.hasError) {
                    return SaasErrorState(
                      title: 'No pudimos cargar la configuración',
                      message:
                          'Verifica tu conexión o permisos e intenta nuevamente.',
                      onRetry: _load,
                    );
                  }
                  final bundle = snap.data;
                  if (bundle == null) return const SizedBox.shrink();

                  return switch (_tab) {
                    _SettingsTab.products => _buildProducts(bundle, tokens),
                    _SettingsTab.categories => _buildCategories(bundle, tokens),
                    _SettingsTab.branches => _buildBranches(bundle, tokens),
                    _SettingsTab.tablesAndChannels =>
                      _buildTablesAndChannels(bundle, tokens),
                    _SettingsTab.operations => _buildOperations(bundle, tokens),
                    _SettingsTab.devices => _buildDevices(bundle, tokens),
                  };
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProducts(SettingsBundle bundle, BackofficeTokens tokens) {
    final canManage = widget.session.permissions.canManageSettings;
    final q = _searchCtrl.text.trim().toLowerCase();
    final items = bundle.products
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Buscar producto...',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (canManage) ...[
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () => _openProductDialog(bundle, null),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Nuevo producto'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        SaasCard(
          title: 'Catálogo de productos (${items.length})',
          subtitle: 'Compatible 100% con modelos operativos Android POS.',
          padding: EdgeInsets.zero,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
            itemBuilder: (context, i) {
              final p = items[i];
              return ListTile(
                onTap: canManage ? () => _openProductDialog(bundle, p) : null,
                title: Text(
                  p.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${p.categoryName} · ${BackofficeSalesAdapter.formatMoney(p.price)}${p.affectsKitchenStock ? ' · Cocina: ${p.kitchenStockItemName ?? ''}' : ''}',
                  style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                ),
                trailing: StatusPill(
                  label: p.active ? 'Activo' : 'Inactivo',
                  tone: p.active ? StatusTone.success : StatusTone.neutral,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategories(SettingsBundle bundle, BackofficeTokens tokens) {
    final canManage = widget.session.permissions.canManageSettings;
    return SaasCard(
      title: 'Categorías de productos (${bundle.categories.length})',
      trailing: canManage
          ? FilledButton.icon(
              onPressed: () => _openCategoryDialog(bundle, null),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Nueva categoría'),
            )
          : null,
      padding: EdgeInsets.zero,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: bundle.categories.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
        itemBuilder: (context, i) {
          final c = bundle.categories[i];
          return ListTile(
            onTap: canManage ? () => _openCategoryDialog(bundle, c) : null,
            title: Text(
              c.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('Orden: ${c.sortOrder}'),
            trailing: StatusPill(
              label: c.active ? 'Activa' : 'Inactiva',
              tone: c.active ? StatusTone.success : StatusTone.neutral,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBranches(SettingsBundle bundle, BackofficeTokens tokens) {
    final canManage = widget.session.isSuperAdmin ||
        (widget.session.employee?.canViewAdmin ?? false);
    return SaasCard(
      title: 'Restaurante: ${bundle.restaurantName}',
      subtitle: '${bundle.branches.length} sucursal(es) configuradas.',
      trailing: canManage
          ? FilledButton.icon(
              onPressed: () => _openBranchDialog(bundle, null),
              icon: const Icon(Icons.add_business_rounded, size: 16),
              label: const Text('Nueva sucursal'),
            )
          : null,
      padding: EdgeInsets.zero,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: bundle.branches.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
        itemBuilder: (context, i) {
          final b = bundle.branches[i];
          return ListTile(
            onTap: canManage ? () => _openBranchDialog(bundle, b) : null,
            title: Text(
              b.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${b.timezone} · ${b.address ?? 'Sin dirección'}',
              style: TextStyle(fontSize: 12, color: tokens.textSecondary),
            ),
            trailing: StatusPill(
              label: b.active ? 'Activa' : 'Inactiva',
              tone: b.active ? StatusTone.success : StatusTone.neutral,
            ),
          );
        },
      ),
    );
  }

  Widget _buildTablesAndChannels(SettingsBundle bundle, BackofficeTokens tokens) {
    final canManage = widget.session.permissions.canManageSettings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaasCard(
          title: 'Mesas y puntos de atención (${bundle.tables.length})',
          trailing: canManage && bundle.branches.isNotEmpty
              ? FilledButton.icon(
                  onPressed: () => _openTableDialog(bundle, null),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Nueva mesa'),
                )
              : null,
          padding: EdgeInsets.zero,
          child: bundle.tables.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No hay mesas registradas en esta sucursal.'),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: bundle.tables.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: tokens.border),
                  itemBuilder: (context, i) {
                    final t = bundle.tables[i];
                    return ListTile(
                      onTap:
                          canManage ? () => _openTableDialog(bundle, t) : null,
                      title: Text(
                        t.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${t.branchName} · ${t.type == 'takeout_entry' ? 'Para llevar' : 'Mesa'}',
                      ),
                      trailing: StatusPill(
                        label: t.active ? 'Activa' : 'Inactiva',
                        tone: t.active ? StatusTone.success : StatusTone.neutral,
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 16),
        SaasCard(
          title: 'Plataformas y canales de venta (${bundle.platforms.length})',
          trailing: canManage
              ? FilledButton.icon(
                  onPressed: () => _openPlatformDialog(bundle, null),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Nueva plataforma'),
                )
              : null,
          padding: EdgeInsets.zero,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: bundle.platforms.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
            itemBuilder: (context, i) {
              final p = bundle.platforms[i];
              return ListTile(
                onTap: canManage ? () => _openPlatformDialog(bundle, p) : null,
                title: Text(
                  p.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: StatusPill(
                  label: p.active ? 'Activa' : 'Inactiva',
                  tone: p.active ? StatusTone.success : StatusTone.neutral,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOperations(SettingsBundle bundle, BackofficeTokens tokens) {
    final emp = widget.session.employee;
    final canAdmin = widget.session.isSuperAdmin || (emp?.canViewAdmin ?? false);
    final dc = bundle.discountConfig;
    final auc = bundle.appUpdateConfig;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaasCard(
          title: 'Descuento general operativo (Android POS)',
          subtitle:
              'Afecta directamente la operación de descuentos en Android.',
          trailing: canAdmin
              ? OutlinedButton(
                  onPressed: () async {
                    final nameCtrl = TextEditingController(text: dc.name);
                    final pctCtrl = TextEditingController(
                      text: dc.percent.toStringAsFixed(1),
                    );
                    var active = dc.active;
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => StatefulBuilder(
                        builder: (ctx, setS) => AlertDialog(
                          title: const Text('Configurar descuento general'),
                          content: SizedBox(
                            width: 360,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Activo'),
                                  value: active,
                                  onChanged: (v) => setS(() => active = v),
                                ),
                                TextField(
                                  controller: nameCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Nombre',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: pctCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Porcentaje (%)',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancelar'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Guardar'),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (ok == true) {
                      await widget.repository.saveDiscountSettings(
                        restaurantId: widget.session.restaurantId,
                        config: GeneralDiscountConfig(
                          active: active,
                          name: nameCtrl.text,
                          percent: double.tryParse(pctCtrl.text.trim()) ?? 0.0,
                        ),
                        actorId: emp?.id ?? '',
                        actorName: emp?.name ?? 'Admin',
                      );
                      if (mounted) _load();
                    }
                  },
                  child: const Text('Editar'),
                )
              : null,
          child: Text(
            'Estado: ${dc.active ? 'Activo' : 'Inactivo'} · ${dc.name} (${dc.percent.toStringAsFixed(1)}%)',
          ),
        ),
        const SizedBox(height: 16),
        SaasCard(
          title: 'Versiones mínimas y actualizaciones Android (Crítico)',
          subtitle:
              'Afecta directamente el acceso de terminales Android. Exclusivo SuperAdmin.',
          trailing: widget.session.isSuperAdmin
              ? OutlinedButton(
                  onPressed: () async {
                    final minCtrl = TextEditingController(
                      text: '${auc.minimumSupportedVersionCode}',
                    );
                    final recCtrl = TextEditingController(
                      text: '${auc.recommendedVersionCode}',
                    );
                    final msgCtrl = TextEditingController(
                      text: auc.updateMessage,
                    );
                    var force = auc.forceUpdate;
                    var active = auc.active;
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => StatefulBuilder(
                        builder: (ctx, setS) => AlertDialog(
                          title: const Text('Configuración crítica appUpdates'),
                          content: SizedBox(
                            width: 380,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Control de versión activo'),
                                  value: active,
                                  onChanged: (v) => setS(() => active = v),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Forzar actualización'),
                                  value: force,
                                  onChanged: (v) => setS(() => force = v),
                                ),
                                TextField(
                                  controller: minCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Código versión mínimo',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: recCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Código versión recomendado',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: msgCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Mensaje al usuario',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancelar'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Guardar'),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (ok == true) {
                      final confirm = await _confirmDangerous(
                        'Confirmar cambio en appUpdates',
                        'Si activas actualización obligatoria, las terminales con versión menor quedarán bloqueadas hasta actualizar.',
                      );
                      if (!confirm) return;
                      await widget.repository.saveAppUpdateSettings(
                        restaurantId: widget.session.restaurantId,
                        config: AppUpdateConfig(
                          active: active,
                          minimumSupportedVersionCode:
                              int.tryParse(minCtrl.text.trim()) ?? 1,
                          recommendedVersionCode:
                              int.tryParse(recCtrl.text.trim()) ?? 1,
                          forceUpdate: force,
                          updateMessage: msgCtrl.text,
                        ),
                        actorId: emp?.id ?? '',
                        actorName: emp?.name ?? 'Admin',
                      );
                      if (mounted) _load();
                    }
                  },
                  child: const Text('Configurar'),
                )
              : null,
          child: Text(
            'Control: ${auc.active ? 'Activo' : 'Inactivo'} · Mín: v${auc.minimumSupportedVersionCode} · Rec: v${auc.recommendedVersionCode} · Forzar: ${auc.forceUpdate ? 'Sí' : 'No'}',
          ),
        ),
      ],
    );
  }

  Widget _buildDevices(SettingsBundle bundle, BackofficeTokens tokens) {
    return SaasCard(
      title: 'Dispositivos registrados (${bundle.devices.length})',
      subtitle:
          'Diagnóstico de solo lectura (no inventa estado de conexión si falta última actividad).',
      padding: EdgeInsets.zero,
      child: bundle.devices.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No hay dispositivos registrados en este restaurante.'),
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: bundle.devices.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: tokens.border),
              itemBuilder: (context, i) {
                final d = bundle.devices[i];
                final lastSeen = d.lastSeenAt != null
                    ? BackofficeSalesAdapter.formatDateTime(d.lastSeenAt)
                    : 'Sin registro';
                return ListTile(
                  title: Text(
                    '${d.deviceName} · ${d.role}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${d.branchName.isNotEmpty ? d.branchName : 'Sin sucursal'} · ${d.platform} · v${d.appVersionName} (${d.appVersionCode}) · Última act: $lastSeen',
                    style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                  ),
                  trailing: StatusPill(
                    label: d.active ? 'Activo' : 'Inactivo',
                    tone: d.active ? StatusTone.success : StatusTone.neutral,
                  ),
                );
              },
            ),
    );
  }
}
