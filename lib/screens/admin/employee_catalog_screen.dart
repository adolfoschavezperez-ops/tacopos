import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/employee.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';

class EmployeeCatalogScreen extends StatelessWidget {
  const EmployeeCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();

    return BrandedScaffold(
      title: 'Empleados',
      actions: [
        IconButton(
          tooltip: 'Agregar empleado',
          onPressed: () => _showEmployeeDialog(context, repository),
          icon: const Icon(Icons.person_add_alt_1),
        ),
      ],
      body: StreamBuilder<List<Employee>>(
        stream: repository.watchEmployees(activeOnly: false),
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
                    onEdit: () => _showEmployeeDialog(
                      context,
                      repository,
                      employee: employee,
                    ),
                    onToggle: () => repository.toggleEmployee(employee),
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
          onTap: () => _showEmployeeDialog(context, repository),
          icon: Icons.person_add_alt_1,
          label: 'Agregar empleado',
          prominent: true,
        ),
      ),
    );
  }

  Future<void> _showEmployeeDialog(
    BuildContext context,
    TacoPosRepository repository, {
    Employee? employee,
  }) async {
    final nameController = TextEditingController(text: employee?.name ?? '');
    var active = employee?.active ?? true;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                employee == null ? 'Agregar empleado' : 'Editar empleado',
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Activo'),
                      value: active,
                      onChanged: (value) {
                        setDialogState(() {
                          active = value;
                        });
                      },
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
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Captura el nombre del empleado.'),
                        ),
                      );
                      return;
                    }

                    await repository.saveEmployee(
                      employeeId: employee?.id,
                      name: nameController.text,
                      active: active,
                    );

                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
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
