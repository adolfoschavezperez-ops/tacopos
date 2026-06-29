import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/pos_table.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/status_badge.dart';
import '../../core/theme/status_styles.dart';

class TableCatalogScreen extends StatefulWidget {
  const TableCatalogScreen({super.key});

  @override
  State<TableCatalogScreen> createState() => _TableCatalogScreenState();
}

class _TableCatalogScreenState extends State<TableCatalogScreen> {
  final _repository = TacoPosRepository();

  Future<void> _showTableDialog({PosTable? table}) async {
    final result = await showDialog<_TableFormResult>(
      context: context,
      builder: (_) => _TableDialog(table: table),
    );

    if (!mounted || result == null) {
      return;
    }

    try {
      await _repository.saveTable(
        tableId: table?.id,
        name: result.name,
        type: result.type,
        active: result.active,
        sortOrder: result.sortOrder,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la mesa: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppSession.instance.employee?.canManageTables != true) {
      return const BrandedScaffold(
        title: 'Mesas',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para administrar mesas.',
        ),
      );
    }

    return BrandedScaffold(
      title: 'Mesas',
      actions: [
        IconButton(
          tooltip: 'Agregar mesa',
          onPressed: () => _showTableDialog(),
          icon: const Icon(Icons.add_circle),
        ),
      ],
      body: StreamBuilder<List<PosTable>>(
        stream: _repository.watchTables(activeOnly: false),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudieron cargar mesas',
              message: '${snapshot.error}',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Cargando mesas...');
          }

          final tables = snapshot.data ?? [];
          if (tables.isEmpty) {
            return const EmptyState(
              icon: Icons.table_restaurant,
              title: 'Sin mesas',
              message: 'Agrega mesas para Mesero / Caja.',
            );
          }

          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              SectionHeader(
                title: 'Catalogo de mesas',
                subtitle: '${tables.length} mesas configuradas',
              ),
              const SizedBox(height: 18),
              ...tables.map(
                (table) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TableAdminTile(
                    table: table,
                    onEdit: () => _showTableDialog(table: table),
                    onToggle: () => _repository.toggleTable(table),
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
          icon: Icons.add,
          label: 'Agregar mesa',
          prominent: true,
          onTap: () => _showTableDialog(),
        ),
      ),
    );
  }
}

class _TableDialog extends StatefulWidget {
  const _TableDialog({this.table});

  final PosTable? table;

  @override
  State<_TableDialog> createState() => _TableDialogState();
}

class _TableDialogState extends State<_TableDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _sortController;
  late String _type;
  late bool _active;
  String? _error;

  @override
  void initState() {
    super.initState();
    final table = widget.table;
    _nameController = TextEditingController(text: table?.name ?? '');
    _sortController = TextEditingController(
      text: (table?.sortOrder ?? 0).toString(),
    );
    _type = _normalizeType(table?.type ?? 'table');
    _active = table?.active ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sortController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final sortOrder = int.tryParse(_sortController.text.trim());
    if (name.isEmpty || sortOrder == null) {
      setState(() {
        _error = 'Completa nombre y orden.';
      });
      return;
    }

    Navigator.pop(
      context,
      _TableFormResult(
        name: name,
        type: _type,
        active: _active,
        sortOrder: sortOrder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.table == null ? 'Agregar mesa' : 'Editar mesa'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: const [
                DropdownMenuItem(value: 'table', child: Text('Mesa')),
                DropdownMenuItem(
                  value: 'takeout_entry',
                  child: Text('Entrada Para llevar'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _type = value;
                  });
                }
              },
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
              title: const Text('Activo'),
              value: _active,
              onChanged: (value) {
                setState(() {
                  _active = value;
                });
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: BrandColors.danger)),
            ],
          ],
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

  String _normalizeType(String type) {
    return type == 'takeout' ? 'takeout_entry' : type;
  }
}

class _TableFormResult {
  const _TableFormResult({
    required this.name,
    required this.type,
    required this.active,
    required this.sortOrder,
  });

  final String name;
  final String type;
  final bool active;
  final int sortOrder;
}

class _TableAdminTile extends StatelessWidget {
  const _TableAdminTile({
    required this.table,
    required this.onEdit,
    required this.onToggle,
  });

  final PosTable table;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final style = tableStatusStyle(table.status);
    final isTakeout = table.type == 'takeout' || table.type == 'takeout_entry';

    return GlassCard(
      accent: table.active ? BrandColors.accentOrange : BrandColors.textMuted,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: table.active ? style.background : BrandColors.glassFill,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isTakeout ? Icons.shopping_bag_outlined : Icons.table_bar,
              color: table.active ? style.color : BrandColors.textMuted,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  table.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${isTakeout ? 'Para llevar' : 'Mesa'} · Orden ${table.sortOrder}',
                  style: const TextStyle(color: BrandColors.textMuted),
                ),
              ],
            ),
          ),
          StatusBadge(style: style),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Editar',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: table.active ? 'Desactivar' : 'Activar',
            onPressed: onToggle,
            icon: Icon(table.active ? Icons.toggle_on : Icons.toggle_off),
            color: table.active ? BrandColors.success : BrandColors.textMuted,
          ),
        ],
      ),
    );
  }
}
