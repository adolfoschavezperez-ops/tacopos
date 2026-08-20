import 'package:flutter/material.dart';

import '../../core/expenses/expense_policy.dart';
import '../../core/theme/brand_colors.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';

class ExpensePolicyAdminScreen extends StatefulWidget {
  const ExpensePolicyAdminScreen({super.key});

  @override
  State<ExpensePolicyAdminScreen> createState() =>
      _ExpensePolicyAdminScreenState();
}

class _ExpensePolicyAdminScreenState extends State<ExpensePolicyAdminScreen> {
  final _repository = TacoPosRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Politicas de gasto')),
      body: StreamBuilder<ExpensePolicySettings>(
        stream: _repository.watchExpensePolicySettings(),
        builder: (context, settingsSnapshot) {
          final settings =
              settingsSnapshot.data ?? const ExpensePolicySettings();
          return StreamBuilder<List<ExpensePolicy>>(
            stream: _repository.watchExpensePolicies(),
            builder: (context, policiesSnapshot) {
              if (policiesSnapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudieron cargar politicas',
                  message: '${policiesSnapshot.error}',
                );
              }
              if (!policiesSnapshot.hasData &&
                  policiesSnapshot.connectionState == ConnectionState.waiting) {
                return const LoadingPanel(message: 'Cargando politicas...');
              }
              final policies = policiesSnapshot.data ?? const [];
              return ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  ExpensePolicySettingsPanel(
                    settings: settings,
                    onChanged: (value) async {
                      await _repository.saveExpensePolicySettings(value);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: _SectionTitle(
                          title: 'Politicas',
                          subtitle:
                              'Permisos configurables para gastos rutinarios.',
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _openEditor(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Nueva'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (policies.isEmpty)
                    const GlassPanel(
                      child: Text(
                        'Sin politicas configuradas.',
                        style: TextStyle(color: BrandColors.textMuted),
                      ),
                    )
                  else
                    ...policies.map(
                      (policy) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PolicyCard(
                          policy: policy,
                          repository: _repository,
                          onEdit: () => _openEditor(context, policy: policy),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    ExpensePolicy? policy,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _PolicyEditorDialog(repository: _repository, policy: policy),
    );
    if (!context.mounted || saved != true) return;
    showAppSnackBar(
      context,
      'Politica guardada.',
      type: AppSnackBarType.success,
    );
  }
}

typedef ExpensePolicyTimePicker =
    Future<TimeOfDay?> Function(BuildContext context, TimeOfDay initialTime);

class ExpensePolicySettingsPanel extends StatefulWidget {
  const ExpensePolicySettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
    this.timePicker,
  });

  final ExpensePolicySettings settings;
  final Future<void> Function(ExpensePolicySettings settings) onChanged;
  final ExpensePolicyTimePicker? timePicker;

  @override
  State<ExpensePolicySettingsPanel> createState() =>
      _ExpensePolicySettingsPanelState();
}

class _ExpensePolicySettingsPanelState
    extends State<ExpensePolicySettingsPanel> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final mode = settings.expensePolicyMode;
    return GlassPanel(
      borderColor: switch (mode) {
        ExpensePolicyMode.live => BrandColors.success,
        ExpensePolicyMode.shadow => BrandColors.accentYellow,
        ExpensePolicyMode.off => BrandColors.textMuted,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            title: 'Autoautorizacion de gastos',
            subtitle:
                'Kill switch global. En OFF conserva el flujo manual actual.',
          ),
          const SizedBox(height: 10),
          SegmentedButton<ExpensePolicyMode>(
            segments: const [
              ButtonSegment(
                value: ExpensePolicyMode.off,
                label: Text('Desactivado'),
              ),
              ButtonSegment(
                value: ExpensePolicyMode.shadow,
                label: Text('Prueba'),
              ),
              ButtonSegment(
                value: ExpensePolicyMode.live,
                label: Text('Activo'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: _saving
                ? null
                : (values) => _save(
                    ExpensePolicySettings(
                      expensePolicyMode: values.first,
                      manualApprovalCutoffEnabled:
                          settings.manualApprovalCutoffEnabled,
                      manualApprovalCutoffTime:
                          settings.manualApprovalCutoffTime,
                      defaultReceiptRequired: settings.defaultReceiptRequired,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            switch (mode) {
              ExpensePolicyMode.off => 'OFF: conserva el flujo manual actual.',
              ExpensePolicyMode.shadow =>
                'SHADOW: evalua politicas sin autoautorizar ni consumir cupo.',
              ExpensePolicyMode.live =>
                'LIVE: puede autoautorizar gastos y consumir cupo.',
            },
            style: TextStyle(
              color: mode == ExpensePolicyMode.live
                  ? BrandColors.danger
                  : BrandColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: settings.manualApprovalCutoffEnabled,
            title: const Text('Horario limite para aprobacion manual'),
            subtitle: Text(
              settings.manualApprovalCutoffEnabled
                  ? settings.manualApprovalCutoffTime.trim().isEmpty
                        ? 'Sin hora configurada'
                        : 'Hora limite ${_formatCutoffLabel(context, settings.manualApprovalCutoffTime)}'
                  : 'Sin limite de horario',
            ),
            onChanged: _saving ? null : _toggleManualApprovalCutoff,
          ),
          if (settings.manualApprovalCutoffEnabled) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Hora limite',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton.icon(
                  onPressed: _saving ? null : _editManualApprovalCutoffTime,
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text(
                    _formatCutoffLabel(
                      context,
                      settings.manualApprovalCutoffTime,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  onPressed: _saving ? null : _editManualApprovalCutoffTime,
                  child: const Text('Editar'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleManualApprovalCutoff(bool value) async {
    final settings = widget.settings;
    if (!value) {
      await _save(
        ExpensePolicySettings(
          expensePolicyMode: settings.expensePolicyMode,
          manualApprovalCutoffEnabled: false,
          manualApprovalCutoffTime: settings.manualApprovalCutoffTime,
          defaultReceiptRequired: settings.defaultReceiptRequired,
        ),
      );
      return;
    }

    final current = _parseCutoffTime(settings.manualApprovalCutoffTime);
    if (current == null) {
      final selected = await _pickTime(const TimeOfDay(hour: 22, minute: 0));
      if (selected == null) return;
      await _saveCutoffTime(selected);
      return;
    }

    await _save(
      ExpensePolicySettings(
        expensePolicyMode: settings.expensePolicyMode,
        manualApprovalCutoffEnabled: true,
        manualApprovalCutoffTime: settings.manualApprovalCutoffTime,
        defaultReceiptRequired: settings.defaultReceiptRequired,
      ),
    );
  }

  Future<void> _editManualApprovalCutoffTime() async {
    final selected = await _pickTime(
      _parseCutoffTime(widget.settings.manualApprovalCutoffTime) ??
          const TimeOfDay(hour: 22, minute: 0),
    );
    if (selected == null) return;
    await _saveCutoffTime(selected);
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initialTime) {
    final picker = widget.timePicker;
    if (picker != null) return picker(context, initialTime);
    return showTimePicker(context: context, initialTime: initialTime);
  }

  Future<void> _saveCutoffTime(TimeOfDay time) {
    final settings = widget.settings;
    return _save(
      ExpensePolicySettings(
        expensePolicyMode: settings.expensePolicyMode,
        manualApprovalCutoffEnabled: true,
        manualApprovalCutoffTime: _formatCutoffStorage(time),
        defaultReceiptRequired: settings.defaultReceiptRequired,
      ),
    );
  }

  Future<void> _save(ExpensePolicySettings settings) async {
    setState(() => _saving = true);
    try {
      await widget.onChanged(settings);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

TimeOfDay? _parseCutoffTime(String value) {
  final parts = value.trim().split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

String _formatCutoffStorage(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

String _formatCutoffLabel(BuildContext context, String value) {
  final time = _parseCutoffTime(value);
  if (time == null) return 'Sin hora configurada';
  return time.format(context);
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({
    required this.policy,
    required this.repository,
    required this.onEdit,
  });

  final ExpensePolicy policy;
  final TacoPosRepository repository;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color = policy.active
        ? policy.autoApproveEnabled
              ? BrandColors.success
              : BrandColors.accentYellow
        : BrandColors.textMuted;
    return GlassPanel(
      borderColor: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rule_folder_outlined, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  policy.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text('v${policy.policyVersion}'),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _ChipText('Operacion', _money(policy.maxAmountPerTransaction)),
              _ChipText('Periodo', _money(policy.maxAmountPerPeriod)),
              _ChipText('Usos', '${policy.maxUsesPerPeriod}'),
              _ChipText('Frecuencia', _frequencyLabel(policy)),
              _ChipText('Comprobante', policy.receiptRequired ? 'Si' : 'No'),
              _ChipText('Auto', policy.autoApproveEnabled ? 'Si' : 'No'),
              _ChipText('Estado', policy.active ? 'Activa' : 'Inactiva'),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<ExpensePolicyUsage>>(
            stream: repository.watchExpensePolicyUsage(policy.id),
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const <ExpensePolicyUsage>[];
              final usage = rows.isEmpty ? null : rows.first;
              if (usage == null) {
                return const Text(
                  'Sin consumo registrado.',
                  style: TextStyle(color: BrandColors.textMuted),
                );
              }
              return Text(
                'Ultimo consumo ${usage.periodKey}: '
                '${usage.usesUsed}/${policy.maxUsesPerPeriod} usos, '
                '${_money(usage.amountUsed)}/${_money(policy.maxAmountPerPeriod)}',
                style: const TextStyle(color: BrandColors.textMuted),
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar'),
              ),
              TextButton.icon(
                onPressed: () => repository.duplicateExpensePolicy(policy),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Duplicar'),
              ),
              TextButton.icon(
                onPressed: () => repository.setExpensePolicyActive(
                  policy: policy,
                  active: !policy.active,
                ),
                icon: Icon(
                  policy.active
                      ? Icons.toggle_off_outlined
                      : Icons.toggle_on_outlined,
                ),
                label: Text(policy.active ? 'Desactivar' : 'Activar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PolicyEditorDialog extends StatefulWidget {
  const _PolicyEditorDialog({required this.repository, this.policy});

  final TacoPosRepository repository;
  final ExpensePolicy? policy;

  @override
  State<_PolicyEditorDialog> createState() => _PolicyEditorDialogState();
}

class _PolicyEditorDialogState extends State<_PolicyEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _description;
  late final TextEditingController _maxTransaction;
  late final TextEditingController _maxPeriod;
  late final TextEditingController _maxUses;
  late final TextEditingController _frequencyValue;
  ExpensePolicyFrequencyType _frequency = ExpensePolicyFrequencyType.daily;
  bool _active = true;
  bool _autoApprove = false;
  bool _receiptRequired = false;
  bool _allowFreeConcept = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final policy = widget.policy;
    _name = TextEditingController(text: policy?.name ?? '');
    _code = TextEditingController(text: policy?.code ?? '');
    _description = TextEditingController(text: policy?.description ?? '');
    _maxTransaction = TextEditingController(
      text: (policy?.maxAmountPerTransaction ?? 0).toStringAsFixed(2),
    );
    _maxPeriod = TextEditingController(
      text: (policy?.maxAmountPerPeriod ?? 0).toStringAsFixed(2),
    );
    _maxUses = TextEditingController(text: '${policy?.maxUsesPerPeriod ?? 1}');
    _frequencyValue = TextEditingController(
      text: '${policy?.frequencyValue ?? 1}',
    );
    _frequency = policy?.frequencyType ?? ExpensePolicyFrequencyType.daily;
    _active = policy?.active ?? true;
    _autoApprove = policy?.autoApproveEnabled ?? false;
    _receiptRequired = policy?.receiptRequired ?? false;
    _allowFreeConcept = policy?.allowFreeConcept ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _description.dispose();
    _maxTransaction.dispose();
    _maxPeriod.dispose();
    _maxUses.dispose();
    _frequencyValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.policy == null ? 'Nueva politica' : 'Editar politica'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              TextField(
                controller: _code,
                decoration: const InputDecoration(labelText: 'Codigo'),
              ),
              TextField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Descripcion'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _maxTransaction,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Max. operacion',
                        prefixText: r'$',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _maxPeriod,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Max. periodo',
                        prefixText: r'$',
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _maxUses,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Usos'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _frequencyValue,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cada X'),
                    ),
                  ),
                ],
              ),
              DropdownButtonFormField<ExpensePolicyFrequencyType>(
                initialValue: _frequency,
                decoration: const InputDecoration(labelText: 'Frecuencia'),
                items: ExpensePolicyFrequencyType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(_frequencyName(type)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(
                  () => _frequency = value ?? ExpensePolicyFrequencyType.daily,
                ),
              ),
              SwitchListTile.adaptive(
                value: _active,
                title: const Text('Activa'),
                onChanged: (value) => setState(() => _active = value),
              ),
              SwitchListTile.adaptive(
                value: _autoApprove,
                title: const Text('Autoautorizar'),
                onChanged: (value) => setState(() => _autoApprove = value),
              ),
              SwitchListTile.adaptive(
                value: _receiptRequired,
                title: const Text('Comprobante requerido'),
                onChanged: (value) => setState(() => _receiptRequired = value),
              ),
              SwitchListTile.adaptive(
                value: _allowFreeConcept,
                title: const Text('Permite concepto libre'),
                onChanged: (value) => setState(() => _allowFreeConcept = value),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: BrandColors.danger),
                ),
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
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final code = _code.text.trim();
    final maxTransaction = double.tryParse(_maxTransaction.text.trim()) ?? 0;
    final maxPeriod = double.tryParse(_maxPeriod.text.trim()) ?? 0;
    final maxUses = int.tryParse(_maxUses.text.trim()) ?? 0;
    final frequencyValue = int.tryParse(_frequencyValue.text.trim()) ?? 1;
    if (name.isEmpty || code.isEmpty) {
      setState(() => _error = 'Captura nombre y codigo.');
      return;
    }
    if (maxTransaction < 0 || maxPeriod < 0 || maxUses < 0) {
      setState(() => _error = 'Los limites no pueden ser negativos.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final current = widget.policy;
      await widget.repository.saveExpensePolicy(
        ExpensePolicy(
          id: current?.id ?? '',
          restaurantId: AppSession.instance.currentRestaurantId,
          branchId: current?.branchId ?? AppSession.instance.currentBranchId,
          name: name,
          code: code,
          description: _description.text.trim(),
          active: _active,
          autoApproveEnabled: _autoApprove,
          maxAmountPerTransaction: maxTransaction,
          maxAmountPerPeriod: maxPeriod,
          maxUsesPerPeriod: maxUses,
          frequencyType: _frequency,
          frequencyValue: frequencyValue <= 0 ? 1 : frequencyValue,
          receiptRequired: _receiptRequired,
          allowFreeConcept: _allowFreeConcept,
          policyVersion: current?.policyVersion ?? 1,
          createdBy: current?.createdBy ?? '',
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: BrandColors.textMuted)),
      ],
    );
  }
}

class _ChipText extends StatelessWidget {
  const _ChipText(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: $value',
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
  }
}

String _money(double value) => '\$${value.toStringAsFixed(2)}';

String _frequencyLabel(ExpensePolicy policy) {
  return switch (policy.frequencyType) {
    ExpensePolicyFrequencyType.daily => 'Diario',
    ExpensePolicyFrequencyType.everyNDays =>
      'Cada ${policy.frequencyValue} dias',
    ExpensePolicyFrequencyType.weekly => 'Semanal',
    ExpensePolicyFrequencyType.everyNWeeks =>
      'Cada ${policy.frequencyValue} semanas',
    ExpensePolicyFrequencyType.monthly => 'Mensual',
    ExpensePolicyFrequencyType.specificWeekdays => 'Dias especificos',
  };
}

String _frequencyName(ExpensePolicyFrequencyType type) {
  return switch (type) {
    ExpensePolicyFrequencyType.daily => 'Diario',
    ExpensePolicyFrequencyType.everyNDays => 'Cada X dias',
    ExpensePolicyFrequencyType.weekly => 'Semanal',
    ExpensePolicyFrequencyType.everyNWeeks => 'Cada X semanas',
    ExpensePolicyFrequencyType.monthly => 'Mensual',
    ExpensePolicyFrequencyType.specificWeekdays => 'Dias especificos',
  };
}
