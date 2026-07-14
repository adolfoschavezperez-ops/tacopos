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

  Future<void> _showBranchDialog({Branch? branch}) async {
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar sucursal: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppSession.instance.employee?.canViewAdmin != true) {
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
          tooltip: 'Agregar sucursal',
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
            return const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'Sin sucursales',
              message: 'Crea Aviacion para preparar la operacion actual.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              const SectionHeader(
                title: 'Catalogo de sucursales',
                subtitle: 'Las apps leen esta lista desde Firestore.',
              ),
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
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: GlassButton(
          onTap: () => _showBranchDialog(),
          icon: Icons.add_business_outlined,
          label: 'Agregar sucursal',
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
