import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../models/branch.dart';
import '../../models/employee.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';

class EmployeeCatalogScreen extends StatefulWidget {
  const EmployeeCatalogScreen({super.key});

  @override
  State<EmployeeCatalogScreen> createState() => _EmployeeCatalogScreenState();
}

class _EmployeeCatalogScreenState extends State<EmployeeCatalogScreen> {
  late final TacoPosRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = TacoPosRepository();
  }

  @override
  Widget build(BuildContext context) {
    if (AppSession.instance.employee?.canManageEmployees != true &&
        AppSession.instance.employee?.hasAdminAccess != true) {
      return const BrandedScaffold(
        title: 'Empleados',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para administrar empleados.',
        ),
      );
    }

    return BrandedScaffold(
      title: 'Empleados',
      actions: [
        IconButton(
          tooltip: 'Agregar empleado',
          onPressed: () => _showEmployeeDialog(),
          icon: const Icon(Icons.person_add_alt_1),
        ),
      ],
      body: StreamBuilder<List<Employee>>(
        stream: _repository.watchEmployees(activeOnly: false),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudieron cargar empleados',
              message: '${snapshot.error}',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Cargando empleados...');
          }

          final employees = snapshot.data ?? [];
          if (employees.isEmpty) {
            return const EmptyState(
              icon: Icons.badge_outlined,
              title: 'Catalogo vacio',
              message: 'Agrega empleados para consumo empleado.',
            );
          }

          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              SectionHeader(
                title: 'Empleados',
                subtitle: '${employees.length} empleados configurados',
              ),
              const SizedBox(height: 18),
              ...employees.map(
                (employee) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _EmployeeAdminTile(
                    employee: employee,
                    onEdit: () => _showEmployeeDialog(employee: employee),
                    onToggle: () => _repository.toggleEmployee(employee),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: GlassButton(
          onTap: () => _showEmployeeDialog(),
          icon: Icons.person_add_alt_1,
          label: 'Agregar empleado',
          prominent: true,
        ),
      ),
    );
  }

  Future<void> _showEmployeeDialog({Employee? employee}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _EmployeeDialog(repository: _repository, employee: employee),
    );

    if (!mounted || saved != true) {
      return;
    }

    showAppSnackBar(
      context,
      employee == null ? 'Empleado agregado.' : 'Empleado actualizado.',
      type: AppSnackBarType.success,
    );
  }
}

class _EmployeeDialog extends StatefulWidget {
  const _EmployeeDialog({required this.repository, this.employee});

  final TacoPosRepository repository;
  final Employee? employee;

  @override
  State<_EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends State<_EmployeeDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _pinController;
  late bool _active;
  late bool _canTakeOrders;
  late bool _canCharge;
  late bool _canViewKitchen;
  late bool _canViewAdmin;
  late bool _canManageProducts;
  late bool _canManageTables;
  late bool _canManagePlatforms;
  late bool _canManageEmployees;
  late bool _canManageCash;
  late bool _canAuthorizeCashWithdrawals;
  late bool _canOpenKitchen;
  late bool _canCloseKitchen;
  late bool _canViewKitchenReports;
  late bool _canManageKitchenStock;
  late bool _canCancelOrders;
  late bool _canCancelPayments;
  late bool _canCancelSupplierPayments;
  late bool _canCancelItems;
  late bool _canApproveKitchenCancellations;
  late bool _canViewLiveOperations;
  late bool _canControlLiveOperations;
  late final Future<List<Branch>> _branchesFuture;
  late Set<String> _branchAccessIds;
  late String _defaultBranchId;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.employee?.name ?? '');
    _pinController = TextEditingController(text: widget.employee?.pin ?? '');
    _active = widget.employee?.active ?? true;
    _canTakeOrders = widget.employee?.canTakeOrders ?? false;
    _canCharge = widget.employee?.canCharge ?? false;
    _canViewKitchen = widget.employee?.canViewKitchen ?? false;
    _canViewAdmin = widget.employee?.canViewAdmin ?? false;
    _canManageProducts = widget.employee?.canManageProducts ?? false;
    _canManageTables = widget.employee?.canManageTables ?? false;
    _canManagePlatforms = widget.employee?.canManagePlatforms ?? false;
    _canManageEmployees = widget.employee?.canManageEmployees ?? false;
    _canManageCash = widget.employee?.canManageCash ?? false;
    _canAuthorizeCashWithdrawals =
        widget.employee?.canAuthorizeCashWithdrawals ?? false;
    _canOpenKitchen = widget.employee?.canOpenKitchen ?? false;
    _canCloseKitchen = widget.employee?.canCloseKitchen ?? false;
    _canViewKitchenReports = widget.employee?.canViewKitchenReports ?? false;
    _canManageKitchenStock = widget.employee?.canManageKitchenStock ?? false;
    _canCancelOrders = widget.employee?.canCancelOrders ?? false;
    _canCancelPayments = widget.employee?.canCancelPayments ?? false;
    _canCancelSupplierPayments =
        widget.employee?.canCancelSupplierPayments ?? false;
    _canCancelItems = widget.employee?.canCancelItems ?? false;
    _canApproveKitchenCancellations =
        widget.employee?.canApproveKitchenCancellations ?? false;
    _canViewLiveOperations = widget.employee?.canViewLiveOperations ?? false;
    _canControlLiveOperations =
        widget.employee?.canControlLiveOperations ?? false;
    _branchesFuture = widget.repository.getBranchesOnce(activeOnly: true);
    final access = widget.employee?.effectiveBranchAccess ?? const [];
    _branchAccessIds = access.map((item) => item.branchId).toSet();
    if (_branchAccessIds.isEmpty) {
      _branchAccessIds = {AppConstants.defaultBranchId};
    }
    _defaultBranchId =
        widget.employee?.defaultBranchId ??
        (_branchAccessIds.contains(AppConstants.defaultBranchId)
            ? AppConstants.defaultBranchId
            : _branchAccessIds.first);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _error = 'Captura el nombre del empleado.';
      });
      return;
    }
    if (_pinController.text.trim().isEmpty) {
      setState(() {
        _error = 'Captura el PIN del empleado.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = '';
    });

    final navigator = Navigator.of(context);

    try {
      final branches = await _branchesFuture;
      final branchesById = {for (final branch in branches) branch.id: branch};
      final cleanDefaultBranchId = _branchAccessIds.contains(_defaultBranchId)
          ? _defaultBranchId
          : _branchAccessIds.first;
      final branchAccess = _branchAccessIds.map((branchId) {
        final branch = branchesById[branchId] ?? Branch.defaultBranch;
        return EmployeeBranchAccess(
          restaurantId: branch.restaurantId,
          branchId: branch.id,
          branchName: branch.name,
          active: true,
          permissions: {
            'canTakeOrders': _canTakeOrders,
            'canCharge': _canCharge,
            'canViewKitchen': _canViewKitchen,
            'canViewAdmin': _canViewAdmin,
            'canManageProducts': _canManageProducts,
            'canManageTables': _canManageTables,
            'canManagePlatforms': _canManagePlatforms,
            'canManageEmployees': _canManageEmployees,
            'canManageCash': _canManageCash,
            'canAuthorizeCashWithdrawals': _canAuthorizeCashWithdrawals,
            'canOpenKitchen': _canOpenKitchen,
            'canCloseKitchen': _canCloseKitchen,
            'canViewKitchenReports': _canViewKitchenReports,
            'canManageKitchenStock': _canManageKitchenStock,
            'canCancelOrders': _canCancelOrders,
            'canCancelPayments': _canCancelPayments,
            'canCancelItems': _canCancelItems,
            'canApproveKitchenCancellations': _canApproveKitchenCancellations,
            'canViewLiveOperations': _canViewLiveOperations,
            'canControlLiveOperations': _canControlLiveOperations,
          },
        );
      }).toList();
      await widget.repository.saveEmployee(
        employeeId: widget.employee?.id,
        name: name,
        active: _active,
        pin: _pinController.text,
        canTakeOrders: _canTakeOrders,
        canCharge: _canCharge,
        canViewKitchen: _canViewKitchen,
        canViewAdmin: _canViewAdmin,
        canManageProducts: _canManageProducts,
        canManageTables: _canManageTables,
        canManagePlatforms: _canManagePlatforms,
        canManageEmployees: _canManageEmployees,
        canManageCash: _canManageCash,
        canAuthorizeCashWithdrawals: _canAuthorizeCashWithdrawals,
        canOpenKitchen: _canOpenKitchen,
        canCloseKitchen: _canCloseKitchen,
        canViewKitchenReports: _canViewKitchenReports,
        canManageKitchenStock: _canManageKitchenStock,
        canCancelOrders: _canCancelOrders,
        canCancelPayments: _canCancelPayments,
        canCancelSupplierPayments: _canCancelSupplierPayments,
        canCancelItems: _canCancelItems,
        canApproveKitchenCancellations: _canApproveKitchenCancellations,
        canViewLiveOperations: _canViewLiveOperations,
        canControlLiveOperations: _canControlLiveOperations,
        branchAccess: branchAccess,
        defaultBranchId: cleanDefaultBranchId,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = 'No se pudo guardar: $error';
      });
      return;
    }

    if (!mounted) {
      return;
    }
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.employee == null ? 'Agregar empleado' : 'Editar empleado',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pinController,
                enabled: !_saving,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'PIN'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activo'),
                value: _active,
                onChanged: _saving
                    ? null
                    : (value) {
                        setState(() {
                          _active = value;
                        });
                      },
              ),
              const Divider(height: 20),
              FutureBuilder<List<Branch>>(
                future: _branchesFuture,
                builder: (context, snapshot) {
                  final branches = snapshot.data ?? const <Branch>[];
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Cargando sucursales...'),
                    );
                  }
                  if (branches.isEmpty) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Primero crea sucursales desde Configuracion > Sucursales.',
                        style: TextStyle(color: BrandColors.textMuted),
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Acceso por sucursal',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      ...branches.map(
                        (branch) => CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(branch.name),
                          subtitle: Text(
                            branch.id == _defaultBranchId
                                ? 'Sucursal default'
                                : 'Permisos actuales se aplican a esta sucursal',
                          ),
                          value: _branchAccessIds.contains(branch.id),
                          onChanged: _saving
                              ? null
                              : (value) {
                                  setState(() {
                                    if (value == true) {
                                      _branchAccessIds.add(branch.id);
                                      _defaultBranchId = branch.id;
                                    } else if (_branchAccessIds.length > 1) {
                                      _branchAccessIds.remove(branch.id);
                                      if (_defaultBranchId == branch.id) {
                                        _defaultBranchId =
                                            _branchAccessIds.first;
                                      }
                                    }
                                  });
                                },
                          secondary: IconButton(
                            tooltip: 'Marcar como default',
                            onPressed:
                                _saving ||
                                    !_branchAccessIds.contains(branch.id) ||
                                    _defaultBranchId == branch.id
                                ? null
                                : () {
                                    setState(
                                      () => _defaultBranchId = branch.id,
                                    );
                                  },
                            icon: Icon(
                              _defaultBranchId == branch.id
                                  ? Icons.star
                                  : Icons.star_border,
                            ),
                            color: _defaultBranchId == branch.id
                                ? BrandColors.accentYellow
                                : BrandColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const Divider(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Operacion',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              _PermissionSwitch(
                title: 'Puede levantar pedidos',
                value: _canTakeOrders,
                enabled: !_saving,
                onChanged: (value) => setState(() => _canTakeOrders = value),
              ),
              _PermissionSwitch(
                title: 'Puede cobrar',
                value: _canCharge,
                enabled: !_saving,
                onChanged: (value) => setState(() => _canCharge = value),
              ),
              _PermissionSwitch(
                title: 'Puede cancelar tickets',
                value: _canCancelOrders,
                enabled: !_saving,
                onChanged: (value) => setState(() => _canCancelOrders = value),
              ),
              _PermissionSwitch(
                title: 'Puede cancelar pagos',
                value: _canCancelPayments,
                enabled: !_saving,
                onChanged: (value) =>
                    setState(() => _canCancelPayments = value),
              ),
              _PermissionSwitch(
                title: 'Puede cancelar pagos a proveedor',
                value: _canCancelSupplierPayments,
                enabled: !_saving,
                onChanged: (value) =>
                    setState(() => _canCancelSupplierPayments = value),
              ),
              _PermissionSwitch(
                title: 'Puede cancelar articulos',
                value: _canCancelItems,
                enabled: !_saving,
                onChanged: (value) => setState(() => _canCancelItems = value),
              ),
              _PermissionSwitch(
                title: 'Puede abrir/cerrar caja',
                value: _canManageCash,
                enabled: !_saving,
                onChanged: (value) => setState(() => _canManageCash = value),
              ),
              _PermissionSwitch(
                title: 'Puede ver cocina',
                value: _canViewKitchen,
                enabled: !_saving,
                onChanged: (value) => setState(() => _canViewKitchen = value),
              ),
              _PermissionSwitch(
                title: 'Puede abrir cocina',
                value: _canOpenKitchen,
                enabled: !_saving,
                onChanged: (value) => setState(() => _canOpenKitchen = value),
              ),
              _PermissionSwitch(
                title: 'Puede cerrar cocina',
                value: _canCloseKitchen,
                enabled: !_saving,
                onChanged: (value) => setState(() => _canCloseKitchen = value),
              ),
              _PermissionSwitch(
                title: 'Puede aprobar cancelaciones cocina',
                value: _canApproveKitchenCancellations,
                enabled: !_saving,
                onChanged: (value) =>
                    setState(() => _canApproveKitchenCancellations = value),
              ),
              const Divider(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Administracion',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              _PermissionSwitch(
                title: 'Puede ver admin',
                value: _canViewAdmin,
                enabled: !_saving,
                onChanged: (value) => setState(() => _canViewAdmin = value),
              ),
              _PermissionSwitch(
                title: 'Administrar productos',
                value: _canManageProducts,
                enabled: !_saving,
                onChanged: (value) =>
                    setState(() => _canManageProducts = value),
              ),
              _PermissionSwitch(
                title: 'Administrar mesas',
                value: _canManageTables,
                enabled: !_saving,
                onChanged: (value) => setState(() => _canManageTables = value),
              ),
              _PermissionSwitch(
                title: 'Administrar plataformas',
                value: _canManagePlatforms,
                enabled: !_saving,
                onChanged: (value) =>
                    setState(() => _canManagePlatforms = value),
              ),
              _PermissionSwitch(
                title: 'Administrar empleados',
                value: _canManageEmployees,
                enabled: !_saving,
                onChanged: (value) =>
                    setState(() => _canManageEmployees = value),
              ),
              _PermissionSwitch(
                title: 'Autorizar retiros de caja',
                value: _canAuthorizeCashWithdrawals,
                enabled: !_saving,
                onChanged: (value) =>
                    setState(() => _canAuthorizeCashWithdrawals = value),
              ),
              _PermissionSwitch(
                title: 'Ver reportes de cocina',
                value: _canViewKitchenReports,
                enabled: !_saving,
                onChanged: (value) =>
                    setState(() => _canViewKitchenReports = value),
              ),
              _PermissionSwitch(
                title: 'Administrar insumos de cocina',
                value: _canManageKitchenStock,
                enabled: !_saving,
                onChanged: (value) =>
                    setState(() => _canManageKitchenStock = value),
              ),
              _PermissionSwitch(
                title: 'Puede ver visor operativo',
                value: _canViewLiveOperations,
                enabled: !_saving,
                onChanged: (value) =>
                    setState(() => _canViewLiveOperations = value),
              ),
              _PermissionSwitch(
                title: 'Puede controlar desde visor operativo',
                value: _canControlLiveOperations,
                enabled: !_saving,
                onChanged: (value) =>
                    setState(() => _canControlLiveOperations = value),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _error,
                  style: const TextStyle(
                    color: BrandColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
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
          child: Text(_saving ? 'Guardando...' : 'Listo'),
        ),
      ],
    );
  }
}

class _PermissionSwitch extends StatelessWidget {
  const _PermissionSwitch({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _EmployeeAdminTile extends StatelessWidget {
  const _EmployeeAdminTile({
    required this.employee,
    required this.onEdit,
    required this.onToggle,
  });

  final Employee employee;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accent: employee.active ? BrandColors.info : BrandColors.textMuted,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: employee.active
                  ? BrandColors.info.withValues(alpha: 0.16)
                  : BrandColors.glassFill,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              employee.active ? Icons.badge_outlined : Icons.person_off,
              color: employee.active ? BrandColors.info : BrandColors.textMuted,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  employee.active ? _permissionSummary(employee) : 'Inactivo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: BrandColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Editar',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: employee.active ? 'Desactivar' : 'Activar',
            onPressed: onToggle,
            icon: Icon(employee.active ? Icons.toggle_on : Icons.toggle_off),
            color: employee.active
                ? BrandColors.success
                : BrandColors.textMuted,
          ),
        ],
      ),
    );
  }

  String _permissionSummary(Employee employee) {
    final permissions = <String>[
      if (employee.canTakeOrders) 'Pedidos',
      if (employee.canCharge) 'Cobro',
      if (employee.canCancelOrders) 'Cancela tickets',
      if (employee.canCancelPayments) 'Cancela pagos',
      if (employee.canCancelItems) 'Cancela articulos',
      if (employee.canManageCash) 'Caja',
      if (employee.canAuthorizeCashWithdrawals) 'Retiros',
      if (employee.canViewKitchen) 'Cocina',
      if (employee.canOpenKitchen) 'Abrir cocina',
      if (employee.canCloseKitchen) 'Cerrar cocina',
      if (employee.canViewKitchenReports) 'Reporte cocina',
      if (employee.canManageKitchenStock) 'Insumos cocina',
      if (employee.canApproveKitchenCancellations) 'Aprueba cancelaciones',
      if (employee.canViewLiveOperations) 'Visor operativo',
      if (employee.canControlLiveOperations) 'Control visor',
      if (employee.canViewAdmin) 'Admin',
    ];
    return permissions.isEmpty ? 'Sin permisos' : permissions.join(' · ');
  }
}
