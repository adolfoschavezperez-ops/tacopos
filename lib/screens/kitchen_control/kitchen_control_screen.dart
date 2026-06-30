import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/kitchen_session.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import 'close_kitchen_session_screen.dart';

class KitchenControlScreen extends StatefulWidget {
  const KitchenControlScreen({super.key});

  @override
  State<KitchenControlScreen> createState() => _KitchenControlScreenState();
}

class _KitchenControlScreenState extends State<KitchenControlScreen> {
  final _repository = TacoPosRepository();
  bool _opening = false;

  Future<void> _openKitchen(Map<String, double> inputs) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await _repository.openKitchenSessionWithInputs(
        todayInputByItemId: inputs,
      );
      if (!mounted) return;
      _showMessage('Cocina abierta.');
    } catch (error) {
      if (!mounted) return;
      _showMessage(_errorText(error));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _closeKitchen(KitchenSession session) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CloseKitchenSessionScreen(session: session),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorText(Object error) {
    return error.toString().replaceFirst('Bad state: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final employee = AppSession.instance.employee;
    final canEnter =
        employee?.canViewKitchen == true ||
        employee?.canOpenKitchen == true ||
        employee?.canCloseKitchen == true;
    if (!canEnter) {
      return const BrandedScaffold(
        title: 'Control de cocina',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para control de cocina.',
        ),
      );
    }

    return BrandedScaffold(
      title: 'Control de cocina',
      body: StreamBuilder<KitchenSession?>(
        stream: _repository.watchOpenKitchenSession(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudo cargar cocina',
              message: '${snapshot.error}',
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Cargando cocina...');
          }

          final session = snapshot.data;
          if (session == null) {
            return FutureBuilder<List<KitchenOpeningInput>>(
              future: _repository.buildKitchenOpeningInputs(),
              builder: (context, openingSnapshot) {
                if (openingSnapshot.hasError) {
                  return EmptyState(
                    icon: Icons.error_outline,
                    title: 'No se pudo cargar apertura',
                    message: '${openingSnapshot.error}',
                  );
                }
                if (openingSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const LoadingPanel(message: 'Preparando apertura...');
                }
                return _KitchenOpeningForm(
                  inputs: openingSnapshot.data ?? [],
                  opening: _opening,
                  onOpen: _openKitchen,
                );
              },
            );
          }

          return _OpenKitchenPanel(
            session: session,
            repository: _repository,
            canClose: employee?.canCloseKitchen == true,
            onClose: () => _closeKitchen(session),
          );
        },
      ),
    );
  }
}

class _KitchenOpeningForm extends StatefulWidget {
  const _KitchenOpeningForm({
    required this.inputs,
    required this.opening,
    required this.onOpen,
  });

  final List<KitchenOpeningInput> inputs;
  final bool opening;
  final ValueChanged<Map<String, double>> onOpen;

  @override
  State<_KitchenOpeningForm> createState() => _KitchenOpeningFormState();
}

class _KitchenOpeningFormState extends State<_KitchenOpeningForm> {
  final _controllers = <String, TextEditingController>{};
  final _focusNodes = <String, FocusNode>{};

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant _KitchenOpeningForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    for (final input in widget.inputs) {
      final item = input.item;
      _controllers.putIfAbsent(item.id, () => TextEditingController());
      _focusNodes.putIfAbsent(item.id, () {
        final focusNode = FocusNode();
        focusNode.addListener(() {
          if (focusNode.hasFocus) {
            _selectAll(_controllers[item.id]!);
          }
        });
        return focusNode;
      });
    }
  }

  void _submit() {
    final values = <String, double>{};
    for (final input in widget.inputs) {
      final raw = _controllers[input.item.id]?.text.trim() ?? '';
      if (raw.isEmpty) {
        _message('Captura las entradas del dia antes de abrir cocina.');
        return;
      }
      final value = double.tryParse(raw.replaceAll(',', '.'));
      if (value == null || value < 0) {
        _message('Captura las entradas del dia antes de abrir cocina.');
        return;
      }
      if (input.item.unit == 'piece' && value != value.roundToDouble()) {
        _message('${input.item.name} debe capturarse en piezas enteras.');
        return;
      }
      values[input.item.id] = value;
    }
    widget.onOpen(values);
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inputs.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Sin insumos controlados',
        message: 'Configura productos e insumos controlados desde Admin.',
      );
    }

    final grouped = <String, List<KitchenOpeningInput>>{};
    for (final input in widget.inputs) {
      grouped.putIfAbsent(input.item.category, () => []).add(input);
    }

    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const SectionHeader(
          title: 'Apertura de cocina',
          subtitle: 'Captura todas las entradas antes de abrir operacion.',
        ),
        const SizedBox(height: 18),
        for (final group in grouped.entries) ...[
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _categoryLabel(group.key),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ...group.value.map(_openingRow),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: GlassButton(
            icon: Icons.soup_kitchen_outlined,
            label: widget.opening ? 'Abriendo...' : 'Abrir cocina',
            prominent: true,
            onTap: widget.opening ? null : _submit,
          ),
        ),
      ],
    );
  }

  Widget _openingRow(KitchenOpeningInput input) {
    final item = input.item;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final inputField = TextField(
            controller: _controllers[item.id],
            focusNode: _focusNodes[item.id],
            enabled: !widget.opening,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Entrada (${item.unit})'),
          );
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Sobrante anterior: ${_formatQty(input.previousRemainingQty)} ${item.unit}',
                style: const TextStyle(
                  color: BrandColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [info, const SizedBox(height: 8), inputField],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 12),
              SizedBox(width: 180, child: inputField),
            ],
          );
        },
      ),
    );
  }

  String _categoryLabel(String category) {
    return kitchenCategoryLabel(category);
  }

  String _formatQty(double value) {
    return formatKitchenQty(value);
  }
}

class _OpenKitchenPanel extends StatelessWidget {
  const _OpenKitchenPanel({
    required this.session,
    required this.repository,
    required this.canClose,
    required this.onClose,
  });

  final KitchenSession session;
  final TacoPosRepository repository;
  final bool canClose;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<KitchenSessionItem>>(
      stream: repository.watchKitchenSessionItems(session.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudieron cargar insumos',
            message: '${snapshot.error}',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPanel(message: 'Cargando insumos...');
        }

        final items = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            SectionHeader(
              title: 'Cocina abierta',
              subtitle:
                  '${session.businessDate} | abierta por ${session.openedByEmployeeName ?? 'Empleado'}',
            ),
            const SizedBox(height: 18),
            _KitchenOpenInputsPanel(
              session: session,
              sessionId: session.id,
              items: items,
              repository: repository,
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: GlassButton(
                icon: Icons.check_circle_outline,
                label: 'Cerrar cocina',
                prominent: true,
                onTap: canClose ? onClose : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KitchenOpenInputsPanel extends StatefulWidget {
  const _KitchenOpenInputsPanel({
    required this.session,
    required this.sessionId,
    required this.items,
    required this.repository,
  });

  final KitchenSession session;
  final String sessionId;
  final List<KitchenSessionItem> items;
  final TacoPosRepository repository;

  @override
  State<_KitchenOpenInputsPanel> createState() =>
      _KitchenOpenInputsPanelState();
}

class _KitchenOpenInputsPanelState extends State<_KitchenOpenInputsPanel> {
  Future<void> _addEntry(KitchenSessionItem item) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AdditionalEntryDialog(
        repository: widget.repository,
        sessionId: widget.sessionId,
        item: item,
      ),
    );
    if (!mounted || saved != true) return;
    _message('Entrada del dia registrada.');
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<KitchenSessionItem>>{};
    for (final item in widget.items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    return Column(
      children: [
        const GlassPanel(
          child: Row(
            children: [
              Icon(Icons.lock_outline, color: BrandColors.accentYellow),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Apertura bloqueada. Las entradas iniciales ya no se pueden editar.',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final entry in grouped.entries) ...[
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _categoryLabel(entry.key),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ...entry.value.map(_itemRow),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        _AdditionalEntriesList(
          sessionId: widget.sessionId,
          repository: widget.repository,
        ),
      ],
    );
  }

  Widget _itemRow(KitchenSessionItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final info = Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _QtyLabel('Anterior', item.previousRemainingQty, item.unit),
              _QtyLabel('Inicial', item.todayInputQty, item.unit),
              _QtyLabel('Entradas extra', item.additionalEntriesQty, item.unit),
              _QtyLabel('Disponible', item.availableQty, item.unit),
            ],
          );
          final button = OutlinedButton.icon(
            onPressed: () => _addEntry(item),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Agregar entrada del dia'),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                info,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: button),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    info,
                  ],
                ),
              ),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
    );
  }

  String _categoryLabel(String category) {
    return switch (category) {
      'meat' => 'Carnes',
      'tortilla' => 'Tortilla',
      'drink' || 'water' => 'Bebidas / aguas',
      _ => 'Otros',
    };
  }
}

class _AdditionalEntriesList extends StatelessWidget {
  const _AdditionalEntriesList({
    required this.sessionId,
    required this.repository,
  });

  final String sessionId;
  final TacoPosRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<KitchenAdditionalEntry>>(
      stream: repository.watchKitchenAdditionalEntries(sessionId),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? [];
        if (entries.isEmpty) {
          return const GlassPanel(
            child: Text(
              'Sin entradas adicionales registradas.',
              style: TextStyle(
                color: BrandColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }
        return GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Entradas adicionales',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              ...entries.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add_box_outlined),
                  title: Text(
                    '${entry.name}: ${formatKitchenQty(entry.qty)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${entry.reason}${entry.notes.isEmpty ? '' : ' | ${entry.notes}'}',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AdditionalEntryDialog extends StatefulWidget {
  const _AdditionalEntryDialog({
    required this.repository,
    required this.sessionId,
    required this.item,
  });

  final TacoPosRepository repository;
  final String sessionId;
  final KitchenSessionItem item;

  @override
  State<_AdditionalEntryDialog> createState() => _AdditionalEntryDialogState();
}

class _AdditionalEntryDialogState extends State<_AdditionalEntryDialog> {
  final _qtyController = TextEditingController();
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  bool _saving = false;
  String _error = '';

  @override
  void dispose() {
    _qtyController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = double.tryParse(
      _qtyController.text.trim().replaceAll(',', '.'),
    );
    if (qty == null || qty <= 0 || _reasonController.text.trim().isEmpty) {
      setState(() => _error = 'Captura cantidad y motivo validos.');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await widget.repository.addKitchenAdditionalEntry(
        kitchenSessionId: widget.sessionId,
        item: widget.item,
        qty: qty,
        reason: _reasonController.text,
        notes: _notesController.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Entrada del dia | ${widget.item.name}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _qtyController,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Cantidad (${widget.item.unit})',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonController,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Motivo'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                enabled: !_saving,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notas'),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _error,
                  style: const TextStyle(
                    color: BrandColors.danger,
                    fontWeight: FontWeight.w800,
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
          child: Text(_saving ? 'Guardando...' : 'Guardar'),
        ),
      ],
    );
  }
}

class _QtyLabel extends StatelessWidget {
  const _QtyLabel(this.label, this.value, this.unit);

  final String label;
  final double value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: ${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)} $unit',
      style: const TextStyle(
        color: BrandColors.textMuted,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

void _selectAll(TextEditingController controller) {
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: controller.text.length,
  );
}

String kitchenCategoryLabel(String category) {
  return switch (category) {
    'meat' => 'Carnes',
    'tortilla' => 'Tortilla',
    'drink' => 'Bebidas',
    'water' => 'Aguas',
    _ => 'Otros',
  };
}

String formatKitchenQty(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}
