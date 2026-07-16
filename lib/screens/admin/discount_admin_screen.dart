import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/money_text.dart';

class DiscountAdminScreen extends StatefulWidget {
  const DiscountAdminScreen({super.key});

  @override
  State<DiscountAdminScreen> createState() => _DiscountAdminScreenState();
}

class _DiscountAdminScreenState extends State<DiscountAdminScreen> {
  final _repository = TacoPosRepository();
  final _nameController = TextEditingController();
  final _percentController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _active = false;
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _percentController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BrandedScaffold(
      title: 'Descuentos',
      body: StreamBuilder<GeneralDiscountConfig>(
        stream: _repository.watchGeneralDiscountConfig(),
        builder: (context, configSnapshot) {
          final config = configSnapshot.data;
          if (config != null && !_loaded) {
            _active = config.active;
            _nameController.text = config.name;
            _percentController.text = config.percent <= 0
                ? ''
                : config.percent.toStringAsFixed(0);
            _descriptionController.text = config.description;
            _loaded = true;
          }

          return StreamBuilder<List<DiscountUsageRow>>(
            stream: _repository.watchDiscountUsage(),
            builder: (context, usageSnapshot) {
              final rows = usageSnapshot.data ?? const [];
              return ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Descuento general',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _active,
                          title: const Text('Activo'),
                          onChanged: (value) => setState(() => _active = value),
                        ),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nombre',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _percentController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Porcentaje',
                            suffixText: '%',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Descripcion',
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'Guardando...' : 'Guardar'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Historial',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  if (rows.isEmpty)
                    const EmptyState(
                      icon: Icons.percent_outlined,
                      title: 'Sin descuentos aplicados',
                      message: 'Los descuentos registrados apareceran aqui.',
                    )
                  else
                    ...rows.map(
                      (row) => GlassCard(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(row.discountName),
                          subtitle: Text(
                            '${row.businessDate} | ${row.branchName} | ${row.status}'
                            '${row.employeeName.isEmpty ? '' : ' | ${row.employeeName}'}'
                            '${row.partnerName.isEmpty ? '' : ' | ${row.partnerName}'}'
                            '${row.linkedEmployeeName.isEmpty ? '' : ' | Empleado ligado: ${row.linkedEmployeeName}'}',
                          ),
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              MoneyText(
                                value: row.discountAmount,
                                style: const TextStyle(
                                  color: BrandColors.accentYellow,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                'Final \$${row.totalAfterDiscount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: BrandColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _repository.saveGeneralDiscountConfig(
        active: _active,
        name: _nameController.text,
        percent:
            double.tryParse(_percentController.text.replaceAll(',', '.')) ?? 0,
        description: _descriptionController.text,
      );
      if (!mounted) return;
      showAppSnackBar(context, 'Descuento guardado.');
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
