import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/employee.dart';
import '../../services/taco_pos_repository.dart';
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          employee == null ? 'Empleado agregado.' : 'Empleado actualizado.',
        ),
      ),
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
  late bool _active;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.employee?.name ?? '');
    _active = widget.employee?.active ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
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

    setState(() {
      _saving = true;
      _error = '';
    });

    final navigator = Navigator.of(context);

    try {
      await widget.repository.saveEmployee(
        employeeId: widget.employee?.id,
        name: name,
        active: _active,
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
                  employee.active ? 'Activo' : 'Inactivo',
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
}
