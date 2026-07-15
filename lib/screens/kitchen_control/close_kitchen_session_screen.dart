import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/kitchen_session.dart';
import '../../services/live_presence_service.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';

class CloseKitchenSessionScreen extends StatefulWidget {
  const CloseKitchenSessionScreen({super.key, required this.session});

  final KitchenSession session;

  @override
  State<CloseKitchenSessionScreen> createState() =>
      _CloseKitchenSessionScreenState();
}

class _CloseKitchenSessionScreenState extends State<CloseKitchenSessionScreen> {
  final _repository = TacoPosRepository();
  final _notesController = TextEditingController();
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    LivePresenceService.instance.updateCurrentScreen(
      appMode: 'kitchen_control',
      currentScreen: 'Control de cocina',
      currentAction: 'Cerrando cocina',
      force: true,
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _close(Map<String, KitchenCloseInput> inputs) async {
    if (_closing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar cocina'),
        content: const Text('Se guardara el cierre de cocina del dia.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar cocina'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _closing = true);
    try {
      await _repository.closeKitchenSession(
        kitchenSessionId: widget.session.id,
        closeInputs: inputs,
        notes: _notesController.text,
      );
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Cierre de cocina realizado.',
        type: AppSnackBarType.success,
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandedScaffold(
      title: 'Cerrar cocina',
      body: StreamBuilder<List<KitchenSessionItem>>(
        stream: _repository.watchKitchenSessionItems(widget.session.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudieron cargar insumos',
              message: '${snapshot.error}',
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Cargando cierre...');
          }
          final items = snapshot.data ?? [];
          return _CloseKitchenForm(
            items: items,
            notesController: _notesController,
            closing: _closing,
            onClose: _close,
          );
        },
      ),
    );
  }
}

class _CloseKitchenForm extends StatefulWidget {
  const _CloseKitchenForm({
    required this.items,
    required this.notesController,
    required this.closing,
    required this.onClose,
  });

  final List<KitchenSessionItem> items;
  final TextEditingController notesController;
  final bool closing;
  final ValueChanged<Map<String, KitchenCloseInput>> onClose;

  @override
  State<_CloseKitchenForm> createState() => _CloseKitchenFormState();
}

class _CloseKitchenFormState extends State<_CloseKitchenForm> {
  final _finalControllers = <String, TextEditingController>{};
  final _wasteControllers = <String, TextEditingController>{};
  final _notesControllers = <String, TextEditingController>{};
  final _focusNodes = <String, FocusNode>{};

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant _CloseKitchenForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  @override
  void dispose() {
    for (final controller in [
      ..._finalControllers.values,
      ..._wasteControllers.values,
      ..._notesControllers.values,
    ]) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    for (final item in widget.items) {
      _finalControllers.putIfAbsent(item.id, () => TextEditingController());
      _wasteControllers.putIfAbsent(item.id, () => TextEditingController());
      _notesControllers.putIfAbsent(item.id, () => TextEditingController());
      _focusNodes.putIfAbsent('${item.id}_final', () {
        final focusNode = FocusNode();
        focusNode.addListener(() {
          if (focusNode.hasFocus) {
            _selectAll(_finalControllers[item.id]!);
          }
        });
        return focusNode;
      });
      _focusNodes.putIfAbsent('${item.id}_waste', () {
        final focusNode = FocusNode();
        focusNode.addListener(() {
          if (focusNode.hasFocus) {
            _selectAll(_wasteControllers[item.id]!);
          }
        });
        return focusNode;
      });
      _focusNodes.putIfAbsent('${item.id}_notes', FocusNode.new);
    }
  }

  void _submit() {
    final inputs = <String, KitchenCloseInput>{};
    for (final item in widget.items) {
      final finalQty = _amount(_finalControllers[item.id]?.text);
      final wasteQty = _amount(_wasteControllers[item.id]?.text);
      if (finalQty == null) {
        _message('Captura sobrante final para ${item.name}.');
        return;
      }
      if (wasteQty == null) {
        _message('Captura merma valida para ${item.name}.');
        return;
      }
      inputs[item.id] = KitchenCloseInput(
        finalRemainingQty: finalQty,
        wasteQty: wasteQty,
        notes: _notesControllers[item.id]?.text ?? '',
      );
    }
    widget.onClose(inputs);
  }

  double? _amount(String? text) {
    final safeText = (text ?? '').trim();
    if (safeText.isEmpty) return 0;
    return double.tryParse(safeText.replaceAll(',', '.'));
  }

  void _message(String text) {
    showAppSnackBar(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<KitchenSessionItem>>{};
    for (final item in widget.items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const SectionHeader(
          title: 'Conteo final',
          subtitle: 'Captura sobrante, merma y notas por insumo.',
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
                ...group.value.map(_row),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        GlassPanel(
          child: TextField(
            controller: widget.notesController,
            enabled: !widget.closing,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Notas generales'),
          ),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerRight,
          child: GlassButton(
            icon: Icons.check_circle_outline,
            label: widget.closing ? 'Cerrando...' : 'Confirmar cierre',
            prominent: true,
            onTap: widget.closing ? null : _submit,
          ),
        ),
      ],
    );
  }

  Widget _row(KitchenSessionItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.name, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            'Disponible: ${_formatQty(item.availableQty)} ${item.unit}',
            style: const TextStyle(
              color: BrandColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              final fields = [
                _numberField(
                  controller: _finalControllers[item.id]!,
                  focusNode: _focusNodes['${item.id}_final']!,
                  label: 'Sobrante final (${item.unit})',
                ),
                _numberField(
                  controller: _wasteControllers[item.id]!,
                  focusNode: _focusNodes['${item.id}_waste']!,
                  label: 'Merma (${item.unit})',
                ),
                TextField(
                  controller: _notesControllers[item.id],
                  focusNode: _focusNodes['${item.id}_notes'],
                  enabled: !widget.closing,
                  decoration: const InputDecoration(labelText: 'Notas'),
                ),
              ];
              if (compact) {
                return Column(
                  children: fields
                      .map(
                        (field) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: field,
                        ),
                      )
                      .toList(),
                );
              }
              return Row(
                children: fields
                    .map(
                      (field) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: field,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: !widget.closing,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
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

  String _formatQty(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }
}

void _selectAll(TextEditingController controller) {
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: controller.text.length,
  );
}
