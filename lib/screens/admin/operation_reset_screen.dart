import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/branch.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';

class OperationResetScreen extends StatefulWidget {
  const OperationResetScreen({super.key});

  @override
  State<OperationResetScreen> createState() => _OperationResetScreenState();
}

class _OperationResetScreenState extends State<OperationResetScreen> {
  final _repository = TacoPosRepository();
  late final Future<List<Branch>> _branchesFuture;
  Branch? _selectedBranch;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _branchesFuture = _repository.getBranchesOnce(activeOnly: true);
  }

  Future<void> _runReset() async {
    final branch = _selectedBranch;
    if (branch == null) {
      _showMessage('Selecciona una sucursal antes de continuar.');
      return;
    }

    final confirmed = await _confirmBranchReset(branch);
    if (confirmed != true || !mounted) {
      return;
    }

    final pinAccepted = await _requestResetPin();
    if (pinAccepted != true || !mounted) {
      return;
    }

    setState(() => _running = true);
    try {
      await _repository.resetOperationalDataForBranch(branch.id);
      if (!mounted) {
        return;
      }
      _showMessage('Operación de ${branch.name} reiniciada correctamente.');
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage('No se pudo reiniciar la operación. Intenta nuevamente.');
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  Future<bool?> _confirmBranchReset(Branch branch) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar reinicio'),
        content: Text(
          'Vas a reiniciar la operación de la sucursal ${branch.name}. '
          'Esta acción no elimina catálogos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _requestResetPin() async {
    final controller = TextEditingController();
    var errorText = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('PIN de autorización'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ingresa el PIN de autorización para reiniciar la operación.',
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      errorText: errorText.isEmpty ? null : errorText,
                    ),
                    onSubmitted: (_) {
                      if (controller.text.trim() ==
                          TacoPosRepository.operationResetPin) {
                        Navigator.pop(context, true);
                        return;
                      }
                      setDialogState(() {
                        errorText =
                            'PIN incorrecto. No se reinició la operación.';
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    if (controller.text.trim() ==
                        TacoPosRepository.operationResetPin) {
                      Navigator.pop(context, true);
                      return;
                    }
                    setDialogState(() {
                      errorText =
                          'PIN incorrecto. No se reinició la operación.';
                    });
                  },
                  child: const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return accepted;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return BrandedScaffold(
      title: 'Reiniciar operación',
      body: FutureBuilder<List<Branch>>(
        future: _branchesFuture,
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
              message: 'Crea una sucursal antes de reiniciar operación.',
            );
          }

          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              GlassPanel(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Selecciona una sucursal',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'La limpieza se aplicará únicamente a la sucursal seleccionada.',
                      style: TextStyle(color: BrandColors.textMuted),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedBranch?.id,
                      decoration: const InputDecoration(
                        labelText: 'Sucursal',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                      items: branches
                          .map(
                            (branch) => DropdownMenuItem(
                              value: branch.id,
                              child: Text(branch.name),
                            ),
                          )
                          .toList(),
                      onChanged: _running
                          ? null
                          : (value) {
                              setState(() {
                                _selectedBranch = null;
                                for (final branch in branches) {
                                  if (branch.id == value) {
                                    _selectedBranch = branch;
                                    break;
                                  }
                                }
                              });
                            },
                    ),
                    if (_selectedBranch != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Se limpiará únicamente la operación de la sucursal ${_selectedBranch!.name}.',
                        style: const TextStyle(
                          color: BrandColors.accentYellow,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const _ResetScopePanel(),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _running || _selectedBranch == null
                      ? null
                      : _runReset,
                  icon: _running
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restart_alt_outlined),
                  label: Text(
                    _running ? 'Reiniciando...' : 'Reiniciar operación',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ResetScopePanel extends StatelessWidget {
  const _ResetScopePanel();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 720;
          final content = [
            const _ScopeList(
              title: 'Se borra',
              icon: Icons.delete_sweep_outlined,
              color: BrandColors.danger,
              items: [
                'ventas',
                'órdenes',
                'pagos',
                'caja',
                'cocina',
                'gastos',
                'sesiones activas',
              ],
            ),
            const _ScopeList(
              title: 'Se conserva',
              icon: Icons.inventory_2_outlined,
              color: BrandColors.success,
              items: [
                'productos',
                'empleados',
                'mesas',
                'sucursales',
                'plataformas',
                'insumos',
              ],
            ),
          ];

          if (twoColumns) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: content[0]),
                const SizedBox(width: 18),
                Expanded(child: content[1]),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [content[0], const SizedBox(height: 16), content[1]],
          );
        },
      ),
    );
  }
}

class _ScopeList extends StatelessWidget {
  const _ScopeList({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '• $item',
              style: const TextStyle(color: BrandColors.textMuted),
            ),
          ),
        ),
      ],
    );
  }
}
