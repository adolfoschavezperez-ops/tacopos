import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/branch.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';

class BranchCatalogScreen extends StatefulWidget {
  const BranchCatalogScreen({super.key});

  @override
  State<BranchCatalogScreen> createState() => _BranchCatalogScreenState();
}

class _BranchCatalogScreenState extends State<BranchCatalogScreen> {
  final _repository = TacoPosRepository();
  bool _preparing = false;
  late Future<int> _pendingPreparationFuture;

  @override
  void initState() {
    super.initState();
    _pendingPreparationFuture = _loadPendingPreparationStatus();
  }

  Future<int> _loadPendingPreparationStatus() {
    if (AppSession.instance.employee?.hasAdminAccess != true) {
      return Future.value(0);
    }
    return _repository.countDefaultBranchBackfillPending();
  }

  Future<void> _showBranchDialog({Branch? branch}) async {
    final isNew = branch == null;
    final result = await showDialog<_BranchFormResult>(
      context: context,
      builder: (_) => _BranchDialog(branch: branch),
    );
    if (!mounted || result == null) return;
    try {
      await _repository.saveBranch(
        branchId: branch?.id,
        name: result.name,
        active: result.active,
        sortOrder: result.sortOrder,
        address: result.address,
        phone: result.phone,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNew
                ? 'Sucursal creada correctamente.'
                : 'Sucursal actualizada correctamente.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar sucursal: $error')),
      );
    }
  }

  Future<void> _prepareData() async {
    setState(() => _preparing = true);
    try {
      final updated = await _repository.backfillDefaultBranch();
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _pendingPreparationFuture = _loadPendingPreparationStatus();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updated == 0
                ? 'Los datos actuales ya están preparados.'
                : 'Datos preparados correctamente.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _preparing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron preparar los datos: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppSession.instance.employee?.hasAdminAccess != true) {
      return const BrandedScaffold(
        title: 'Sucursales',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para administrar sucursales.',
        ),
      );
    }

    return BrandedScaffold(
      title: 'Sucursales',
      actions: [
        IconButton(
          tooltip: 'Nueva sucursal',
          onPressed: () => _showBranchDialog(),
          icon: const Icon(Icons.add_business_outlined),
        ),
      ],
      body: StreamBuilder<List<Branch>>(
        stream: _repository.watchBranches(activeOnly: false),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudieron cargar sucursales',
              message: '${snapshot.error}',
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Cargando sucursales...');
          }
          final branches = snapshot.data ?? [];
          if (branches.isEmpty) {
            return _EmptyBranchesPanel(
              onCreate: () => _showBranchDialog(),
              preparing: _preparing,
              pendingPreparationFuture: _pendingPreparationFuture,
              onPrepareData: _prepareData,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              _BranchCatalogHeader(onCreate: () => _showBranchDialog()),
              const SizedBox(height: 18),
              ...branches.map(
                (branch) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BranchTile(
                    branch: branch,
                    repository: _repository,
                    onEdit: () => _showBranchDialog(branch: branch),
                    onToggle: () => _repository.toggleBranch(branch),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _AdvancedPreparationPanel(
                preparing: _preparing,
                pendingFuture: _pendingPreparationFuture,
                onPrepareData: _prepareData,
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: GlassButton(
          onTap: () => _showBranchDialog(),
          icon: Icons.add_business_outlined,
          label: 'Nueva sucursal',
          prominent: true,
        ),
      ),
    );
  }
}

class _BranchTile extends StatelessWidget {
  const _BranchTile({
    required this.branch,
    required this.repository,
    required this.onEdit,
    required this.onToggle,
  });

  final Branch branch;
  final TacoPosRepository repository;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BranchSummary>(
      future: repository.branchSummary(branch),
      builder: (context, snapshot) {
        final summary = snapshot.data;
        return GlassCard(
          accent: branch.active ? BrandColors.info : BrandColors.textMuted,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: branch.active
                      ? BrandColors.info.withValues(alpha: 0.16)
                      : BrandColors.glassFill,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.storefront_outlined,
                  color: branch.active
                      ? BrandColors.info
                      : BrandColors.textMuted,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      branch.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        'Orden ${branch.sortOrder}',
                        if (!branch.active) 'Inactiva',
                        if (summary != null) '${summary.tableCount} mesas',
                        if (summary != null)
                          '${summary.openOrderCount} ordenes abiertas',
                        if (summary != null)
                          summary.cashOpen ? 'Caja abierta' : 'Caja cerrada',
                        if (summary != null)
                          '${summary.employeeAccessCount} empleados',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: BrandColors.textMuted),
                    ),
                    if ((branch.address ?? '').isNotEmpty ||
                        (branch.phone ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        [branch.address, branch.phone]
                            .where((value) => (value ?? '').trim().isNotEmpty)
                            .join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: BrandColors.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Editar',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: branch.active ? 'Desactivar' : 'Activar',
                onPressed: onToggle,
                icon: Icon(branch.active ? Icons.toggle_on : Icons.toggle_off),
                color: branch.active
                    ? BrandColors.success
                    : BrandColors.textMuted,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BranchCatalogHeader extends StatelessWidget {
  const _BranchCatalogHeader({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const Icon(
            Icons.storefront_outlined,
            color: BrandColors.accentYellow,
            size: 30,
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sucursales',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 4),
                Text(
                  'Administra las sucursales del restaurante.',
                  style: TextStyle(color: BrandColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Nueva sucursal'),
          ),
        ],
      ),
    );
  }
}

class _AdvancedPreparationPanel extends StatelessWidget {
  const _AdvancedPreparationPanel({
    required this.preparing,
    required this.pendingFuture,
    required this.onPrepareData,
  });

  final bool preparing;
  final Future<int> pendingFuture;
  final VoidCallback onPrepareData;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: const Icon(Icons.tune_outlined, color: BrandColors.textMuted),
        title: const Text(
          'Avanzado',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: const Text(
          'Opciones de preparación.',
          style: TextStyle(color: BrandColors.textMuted),
        ),
        children: [
          FutureBuilder<int>(
            future: pendingFuture,
            builder: (context, snapshot) {
              final pendingCount = snapshot.data;
              if (snapshot.connectionState == ConnectionState.waiting &&
                  pendingCount == null) {
                return const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Revisando datos actuales...',
                    style: TextStyle(color: BrandColors.textMuted),
                  ),
                );
              }
              if (snapshot.hasError) {
                return _PreparationActionContent(
                  message: 'No se pudo revisar si hay datos pendientes.',
                  preparing: preparing,
                  onPrepareData: onPrepareData,
                );
              }
              if ((pendingCount ?? 0) == 0) {
                return const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Los datos actuales ya están preparados.',
                    style: TextStyle(color: BrandColors.textMuted),
                  ),
                );
              }
              return _PreparationActionContent(
                message:
                    'Asigna la sucursal Aviación a datos antiguos que todavía no tienen sucursal.',
                preparing: preparing,
                onPrepareData: onPrepareData,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PreparationActionContent extends StatelessWidget {
  const _PreparationActionContent({
    required this.message,
    required this.preparing,
    required this.onPrepareData,
  });

  final String message;
  final bool preparing;
  final VoidCallback onPrepareData;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Preparar datos actuales',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(message, style: const TextStyle(color: BrandColors.textMuted)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: preparing ? null : onPrepareData,
          icon: const Icon(Icons.account_tree_outlined),
          label: Text(preparing ? 'Preparando...' : 'Preparar datos'),
        ),
      ],
    );
  }
}

class _EmptyBranchesPanel extends StatelessWidget {
  const _EmptyBranchesPanel({
    required this.onCreate,
    required this.preparing,
    required this.pendingPreparationFuture,
    required this.onPrepareData,
  });

  final VoidCallback onCreate;
  final bool preparing;
  final Future<int> pendingPreparationFuture;
  final VoidCallback onPrepareData;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const EmptyState(
          icon: Icons.storefront_outlined,
          title: 'No hay sucursales registradas.',
          message: 'Crea la primera sucursal del restaurante.',
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Crear primera sucursal'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _AdvancedPreparationPanel(
          preparing: preparing,
          pendingFuture: pendingPreparationFuture,
          onPrepareData: onPrepareData,
        ),
      ],
    );
  }
}

class _BranchDialog extends StatefulWidget {
  const _BranchDialog({this.branch});

  final Branch? branch;

  @override
  State<_BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends State<_BranchDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late final TextEditingController _sortController;
  late bool _active;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final branch = widget.branch;
    _nameController = TextEditingController(text: branch?.name ?? '');
    _addressController = TextEditingController(text: branch?.address ?? '');
    _phoneController = TextEditingController(text: branch?.phone ?? '');
    _sortController = TextEditingController(
      text: (branch?.sortOrder ?? 1).toString(),
    );
    _active = branch?.active ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _sortController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final sortOrder = int.tryParse(_sortController.text.trim());
    if (name.isEmpty || sortOrder == null) {
      setState(() => _error = 'Completa nombre y orden.');
      return;
    }
    Navigator.pop(
      context,
      _BranchFormResult(
        name: name,
        address: _addressController.text.trim(),
        phone: _phoneController.text.trim(),
        active: _active,
        sortOrder: sortOrder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.branch == null ? 'Agregar sucursal' : 'Editar sucursal',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Direccion'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telefono'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sortController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Orden'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activa'),
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
              if (_error.isNotEmpty)
                Text(_error, style: const TextStyle(color: BrandColors.danger)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

class _BranchFormResult {
  const _BranchFormResult({
    required this.name,
    required this.address,
    required this.phone,
    required this.active,
    required this.sortOrder,
  });

  final String name;
  final String address;
  final String phone;
  final bool active;
  final int sortOrder;
}
