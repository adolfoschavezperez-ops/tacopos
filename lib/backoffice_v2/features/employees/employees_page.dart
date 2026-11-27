import 'package:flutter/material.dart';

import '../../../models/employee.dart';
import '../../auth/backoffice_session.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../widgets/empty_error_state.dart';
import '../../widgets/saas_card.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/status_pill.dart';
import 'employees_repository.dart';

class _PermissionItem {
  const _PermissionItem(this.key, this.label, {this.isCritical = false});
  final String key;
  final String label;
  final bool isCritical;
}

class _PermissionGroup {
  const _PermissionGroup(this.title, this.items);
  final String title;
  final List<_PermissionItem> items;
}

const List<_PermissionGroup> _permissionGroups = [
  _PermissionGroup('Ventas y Caja', [
    _PermissionItem('canTakeOrders', 'Tomar órdenes'),
    _PermissionItem('canCharge', 'Cobrar órdenes'),
    _PermissionItem('canCancelOrders', 'Cancelar órdenes', isCritical: true),
    _PermissionItem('canCancelPayments', 'Cancelar pagos', isCritical: true),
    _PermissionItem('canCancelItems', 'Cancelar partidas', isCritical: true),
    _PermissionItem('canManageCash', 'Administrar caja', isCritical: true),
    _PermissionItem(
      'canAuthorizeCashWithdrawals',
      'Autorizar retiros y descuentos',
      isCritical: true,
    ),
  ]),
  _PermissionGroup('Cocina e Inventarios', [
    _PermissionItem('canViewKitchen', 'Ver pantalla de cocina'),
    _PermissionItem('canOpenKitchen', 'Abrir cocina'),
    _PermissionItem('canCloseKitchen', 'Cerrar cocina'),
    _PermissionItem(
      'canApproveKitchenCancellations',
      'Aprobar cancelaciones cocina',
    ),
    _PermissionItem('canViewKitchenReports', 'Ver reportes de cocina'),
    _PermissionItem(
      'canViewKitchenHourlySalesComparison',
      'Comparativo horario cocina',
    ),
    _PermissionItem('canManageKitchenStock', 'Administrar insumos cocina'),
  ]),
  _PermissionGroup('Compras, Proveedores y CXP', [
    _PermissionItem('canViewPurchases', 'Ver módulo de compras'),
    _PermissionItem('canManageSuppliers', 'Administrar proveedores e insumos'),
    _PermissionItem('canRegisterPurchases', 'Registrar compras'),
    _PermissionItem('canPaySuppliers', 'Pagar a proveedores', isCritical: true),
    _PermissionItem(
      'canCancelSupplierPayments',
      'Cancelar pagos a proveedores',
      isCritical: true,
    ),
    _PermissionItem('canViewAccountsPayable', 'Ver cuentas por pagar'),
    _PermissionItem('canViewPurchaseReports', 'Ver reportes de compras'),
  ]),
  _PermissionGroup('Administración y Catálogos', [
    _PermissionItem('canViewAdmin', 'Acceso Backoffice / Admin', isCritical: true),
    _PermissionItem('canManageProducts', 'Administrar productos'),
    _PermissionItem('canManageTables', 'Administrar mesas'),
    _PermissionItem('canManagePlatforms', 'Administrar plataformas'),
    _PermissionItem(
      'canManageEmployees',
      'Administrar empleados y permisos',
      isCritical: true,
    ),
    _PermissionItem('canViewLiveOperations', 'Ver operación en vivo'),
    _PermissionItem(
      'canControlLiveOperations',
      'Intervenir operación en vivo',
      isCritical: true,
    ),
  ]),
];

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({
    super.key,
    required this.session,
    required this.repository,
    required this.onOpenSaleDetail,
  });

  final BackofficeSession session;
  final EmployeesRepository repository;
  final ValueChanged<String> onOpenSaleDetail;

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _statusFilter = 'all';
  Future<EmployeesDashboardData>? _future;
  String _lastRestaurantId = '';

  @override
  void initState() {
    super.initState();
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
    if (_lastRestaurantId != widget.session.restaurantId) {
      _lastRestaurantId = widget.session.restaurantId;
      _load();
    }
  }

  void _load() {
    setState(() {
      _future = widget.repository.loadEmployees(
        restaurantId: widget.session.restaurantId,
      );
    });
  }

  Map<String, bool> _employeePermMap(Employee? emp) {
    if (emp == null) {
      return {
        for (final g in _permissionGroups)
          for (final i in g.items) i.key: false,
      };
    }
    return {
      'canTakeOrders': emp.canTakeOrders,
      'canCharge': emp.canCharge,
      'canCancelOrders': emp.canCancelOrders,
      'canCancelPayments': emp.canCancelPayments,
      'canCancelItems': emp.canCancelItems,
      'canManageCash': emp.canManageCash,
      'canAuthorizeCashWithdrawals': emp.canAuthorizeCashWithdrawals,
      'canViewKitchen': emp.canViewKitchen,
      'canOpenKitchen': emp.canOpenKitchen,
      'canCloseKitchen': emp.canCloseKitchen,
      'canApproveKitchenCancellations': emp.canApproveKitchenCancellations,
      'canViewKitchenReports': emp.canViewKitchenReports,
      'canViewKitchenHourlySalesComparison':
          emp.canViewKitchenHourlySalesComparison,
      'canManageKitchenStock': emp.canManageKitchenStock,
      'canViewPurchases': emp.canViewPurchases,
      'canManageSuppliers': emp.canManageSuppliers,
      'canRegisterPurchases': emp.canRegisterPurchases,
      'canPaySuppliers': emp.canPaySuppliers,
      'canCancelSupplierPayments': emp.canCancelSupplierPayments,
      'canViewAccountsPayable': emp.canViewAccountsPayable,
      'canViewPurchaseReports': emp.canViewPurchaseReports,
      'canViewAdmin': emp.canViewAdmin,
      'canManageProducts': emp.canManageProducts,
      'canManageTables': emp.canManageTables,
      'canManagePlatforms': emp.canManagePlatforms,
      'canManageEmployees': emp.canManageEmployees,
      'canViewLiveOperations': emp.canViewLiveOperations,
      'canControlLiveOperations': emp.canControlLiveOperations,
    };
  }

  Future<void> _openEmployeeDialog(Employee? existing) async {
    final actor = widget.session.employee;
    final isSelfEdit = existing != null && existing.id == actor?.id;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var active = existing?.active ?? true;
    var isSuperAdmin = existing?.isSuperAdmin ?? false;
    final perms = _employeePermMap(existing);
    final allBranches = widget.session.branches;
    final selectedBranchIds = existing != null && existing.branchAccess.isNotEmpty
        ? existing.branchAccess.map((b) => b.branchId).toSet()
        : allBranches.map((b) => b.id).toSet();
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            existing == null
                ? 'Nuevo empleado'
                : 'Editar empleado · ${existing.name}',
          ),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del empleado',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    ),
                    child: const Text(
                      'Por seguridad, Backoffice 2.0 no muestra ni almacena PINs en texto plano. '
                      'La gestión de credenciales operativas permanece aislada en el flujo de autenticación.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Empleado activo'),
                    value: active,
                    onChanged: isSelfEdit
                        ? null
                        : (v) => setS(() => active = v),
                  ),
                  if (widget.session.isSuperAdmin)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Super Administrador (acceso total)'),
                      value: isSuperAdmin,
                      onChanged: isSelfEdit
                          ? null
                          : (v) => setS(() => isSuperAdmin = v),
                    ),
                  const Divider(),
                  const Text(
                    'Sucursales autorizadas',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Wrap(
                    spacing: 8,
                    children: allBranches
                        .map(
                          (b) => FilterChip(
                            label: Text(b.name),
                            selected: selectedBranchIds.contains(b.id),
                            onSelected: (v) {
                              setS(() {
                                if (v) {
                                  selectedBranchIds.add(b.id);
                                } else {
                                  selectedBranchIds.remove(b.id);
                                }
                              });
                            },
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 10),
                  for (final group in _permissionGroups) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Text(
                        group.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    for (final item in group.items)
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          item.isCritical ? '${item.label} •' : item.label,
                          style: const TextStyle(fontSize: 13),
                        ),
                        value: perms[item.key] ?? false,
                        onChanged:
                            (isSelfEdit &&
                                (item.key == 'canManageEmployees' ||
                                    item.key == 'canViewAdmin'))
                            ? null
                            : (v) => setS(() => perms[item.key] = v),
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
                      if (nameCtrl.text.trim().isEmpty) return;
                      setS(() => saving = true);
                      final branches = allBranches
                          .where((b) => selectedBranchIds.contains(b.id))
                          .toList(growable: false);
                      await widget.repository.saveEmployee(
                        restaurantId: widget.session.restaurantId,
                        existingEmployeeId: existing?.id,
                        name: nameCtrl.text,
                        active: active,
                        isSuperAdmin: isSuperAdmin,
                        permissions: perms,
                        assignedBranches: branches,
                        actorEmployeeId: actor?.id ?? '',
                        actorEmployeeName: actor?.name ?? 'Admin',
                        actorIsSuperAdmin: widget.session.isSuperAdmin,
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

  Future<void> _confirmToggle(Employee emp) async {
    final action = emp.active ? 'Desactivar' : 'Activar';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action empleado'),
        content: Text(
          emp.active
              ? 'Al desactivar a ${emp.name} se revocará su acceso al Backoffice y POS. Esta acción queda auditada.'
              : '¿Reactivar acceso para ${emp.name}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final actor = widget.session.employee;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.toggleEmployeeActive(
        restaurantId: widget.session.restaurantId,
        employee: emp,
        actorEmployeeId: actor?.id ?? '',
        actorEmployeeName: actor?.name ?? 'Admin',
      );
      if (mounted) _load();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void _openProfile(Employee emp, List<DeviceSummaryRow> devices) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => FutureBuilder<EmployeeProfileBundle>(
          future: widget.repository.loadEmployeeProfile(
            restaurantId: widget.session.restaurantId,
            employee: emp,
            allDevices: devices,
          ),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: TableSkeleton(rows: 5),
              );
            }
            final bundle = snap.data;
            if (bundle == null) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No pudimos cargar el perfil.'),
              );
            }
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  bundle.employee.name,
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Estado: ${bundle.employee.active ? 'Activo' : 'Inactivo'} · Órdenes/Descuentos 30d: ${bundle.ordersCount} (${BackofficeSalesAdapter.formatMoney(bundle.salesTotal)})',
                ),
                const Divider(height: 24),
                Text(
                  'Dispositivos asociados (${bundle.devices.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (bundle.devices.isEmpty)
                  const Text('Sin dispositivos asociados.')
                else
                  ...bundle.devices.map(
                    (d) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${d.deviceName} · ${d.role}'),
                      subtitle: Text(
                        '${d.branchName} · v${d.appVersionName} (${d.appVersionCode})',
                      ),
                    ),
                  ),
                const Divider(height: 24),
                Text(
                  'Descuentos y beneficios (${bundle.discountUsages.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (bundle.discountUsages.isEmpty)
                  const Text('Sin usos de descuento registrados.')
                else
                  ...bundle.discountUsages.take(15).map(
                    (u) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${u.discountName} (${u.businessDate})'),
                      subtitle: Text(
                        'Desc: ${BackofficeSalesAdapter.formatMoney(u.discountAmount)} · Neto: ${BackofficeSalesAdapter.formatMoney(u.totalAfterDiscount)}',
                      ),
                      trailing: u.orderId != null
                          ? TextButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                widget.onOpenSaleDetail(u.orderId!);
                              },
                              child: const Text('Ver orden'),
                            )
                          : null,
                    ),
                  ),
                const Divider(height: 24),
                Text(
                  'Actividad reciente (${bundle.recentEvents.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (bundle.recentEvents.isEmpty)
                  const Text('Sin actividad reciente en bitácora.')
                else
                  ...bundle.recentEvents.take(15).map(
                    (e) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.type),
                      subtitle: Text(
                        '${BackofficeSalesAdapter.formatDateTime(e.createdAt)} · ${e.reason ?? e.note ?? e.actionSource}',
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final canManage = widget.session.permissions.canManageEmployees;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Empleados, Roles y Permisos',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Gestión segura de accesos por sucursal, módulo y acción.',
                          style: TextStyle(
                            fontSize: 13,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canManage)
                    FilledButton.icon(
                      onPressed: () => _openEmployeeDialog(null),
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                      label: const Text('Nuevo empleado'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Buscar empleado por nombre...',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ChoiceChip(
                    label: const Text('Todos'),
                    selected: _statusFilter == 'all',
                    onSelected: (_) => setState(() => _statusFilter = 'all'),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Activos'),
                    selected: _statusFilter == 'active',
                    onSelected: (_) => setState(() => _statusFilter = 'active'),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Inactivos'),
                    selected: _statusFilter == 'inactive',
                    onSelected: (_) =>
                        setState(() => _statusFilter = 'inactive'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FutureBuilder<EmployeesDashboardData>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const TableSkeleton(rows: 6);
                  }
                  if (snap.hasError) {
                    return SaasErrorState(
                      title: 'No pudimos cargar los empleados',
                      message:
                          'Verifica tu conexión o permisos e intenta nuevamente.',
                      onRetry: _load,
                    );
                  }
                  final data = snap.data;
                  if (data == null) return const SizedBox.shrink();

                  final q = _searchCtrl.text.trim().toLowerCase();
                  final filtered = data.employees
                      .where((e) {
                        if (_statusFilter == 'active' && !e.active) return false;
                        if (_statusFilter == 'inactive' && e.active) {
                          return false;
                        }
                        if (q.isNotEmpty && !e.name.toLowerCase().contains(q)) {
                          return false;
                        }
                        return true;
                      })
                      .toList(growable: false);

                  if (filtered.isEmpty) {
                    return const SaasEmptyState(
                      icon: Icons.badge_outlined,
                      title: 'Sin empleados coincidentes',
                      message: 'Prueba ajustando los filtros de búsqueda.',
                    );
                  }

                  return SaasCard(
                    title: 'Catálogo de empleados (${filtered.length})',
                    subtitle: 'PINs ocultos por política de seguridad.',
                    padding: EdgeInsets.zero,
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: tokens.border),
                      itemBuilder: (context, i) {
                        final emp = filtered[i];
                        final permCount = _employeePermMap(emp).values
                            .where((v) => v)
                            .length;
                        final branchCount = emp.branchAccess.isEmpty
                            ? widget.session.branches.length
                            : emp.branchAccess.length;
                        return ListTile(
                          onTap: () => _openProfile(emp, data.devices),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  emp.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              StatusPill(
                                label: emp.active ? 'Activo' : 'Inactivo',
                                tone: emp.active
                                    ? StatusTone.success
                                    : StatusTone.neutral,
                              ),
                            ],
                          ),
                          subtitle: Text(
                            '${emp.isSuperAdmin ? 'Super Admin · ' : ''}$permCount permiso(s) · $branchCount sucursal(es)',
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.textSecondary,
                            ),
                          ),
                          trailing: canManage
                              ? Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      tooltip: 'Editar permisos',
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                      onPressed: () => _openEmployeeDialog(emp),
                                    ),
                                    IconButton(
                                      tooltip: emp.active
                                          ? 'Desactivar'
                                          : 'Activar',
                                      icon: Icon(
                                        emp.active
                                            ? Icons.person_off_outlined
                                            : Icons.person_add_outlined,
                                        size: 18,
                                      ),
                                      onPressed: () => _confirmToggle(emp),
                                    ),
                                  ],
                                )
                              : null,
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
