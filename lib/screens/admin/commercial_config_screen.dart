import 'package:flutter/material.dart';

import '../../core/commercial/tenant_runtime_context.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/brand_colors.dart';
import '../../services/app_session.dart';
import '../../services/commercial_config_service.dart';
import '../../utils/app_snackbar.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/commercial_branding.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';

class CommercialConfigScreen extends StatefulWidget {
  const CommercialConfigScreen({super.key});

  @override
  State<CommercialConfigScreen> createState() => _CommercialConfigScreenState();
}

class _CommercialConfigScreenState extends State<CommercialConfigScreen> {
  final _service = CommercialConfigService.instance;
  late Future<TenantRuntimeContext> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.loadRuntimeContext();
  }

  void _reload() {
    setState(() {
      _future = _service.loadRuntimeContext();
    });
  }

  @override
  Widget build(BuildContext context) {
    final employee = AppSession.instance.employee;
    final allowed =
        employee?.hasAdminAccess == true || employee?.canViewAdmin == true;
    if (!allowed) {
      return const BrandedScaffold(
        title: 'Configuracion comercial',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin acceso',
          message: 'Solo Admin puede revisar la configuracion comercial.',
        ),
      );
    }

    return BrandedScaffold(
      title: 'Configuracion comercial',
      body: FutureBuilder<TenantRuntimeContext>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const LoadingPanel(message: 'Cargando configuracion...');
          }
          final runtime = snapshot.data!;
          return _CommercialConfigView(runtime: runtime, onReload: _reload);
        },
      ),
    );
  }
}

class _CommercialConfigView extends StatefulWidget {
  const _CommercialConfigView({required this.runtime, required this.onReload});

  final TenantRuntimeContext runtime;
  final VoidCallback onReload;

  @override
  State<_CommercialConfigView> createState() => _CommercialConfigViewState();
}

class _CommercialConfigViewState extends State<_CommercialConfigView> {
  final _service = CommercialConfigService.instance;
  final _businessName = TextEditingController();
  final _shortName = TextEditingController();
  final _logoUrl = TextEditingController();
  final _primaryColor = TextEditingController();
  final _accentColor = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _receiptHeader = TextEditingController();
  final _receiptFooter = TextEditingController();
  final _currencyCode = TextEditingController();
  final _locale = TextEditingController();
  final _timezone = TextEditingController();
  final _cardPercent = TextEditingController();

  late OperationalPolicy _operations;
  late BenefitPolicies _benefits;
  bool _saving = false;
  CommercialPreparationResult? _lastPreparation;

  @override
  void initState() {
    super.initState();
    _hydrate(widget.runtime);
  }

  @override
  void didUpdateWidget(covariant _CommercialConfigView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) {
      _hydrate(widget.runtime);
    }
  }

  @override
  void dispose() {
    _businessName.dispose();
    _shortName.dispose();
    _logoUrl.dispose();
    _primaryColor.dispose();
    _accentColor.dispose();
    _address.dispose();
    _phone.dispose();
    _receiptHeader.dispose();
    _receiptFooter.dispose();
    _currencyCode.dispose();
    _locale.dispose();
    _timezone.dispose();
    _cardPercent.dispose();
    super.dispose();
  }

  void _hydrate(TenantRuntimeContext runtime) {
    final branding = runtime.branding;
    _businessName.text = branding.businessName;
    _shortName.text = branding.shortName;
    _logoUrl.text = branding.logoUrl;
    _primaryColor.text = branding.primaryColorHex;
    _accentColor.text = branding.accentColorHex;
    _address.text = branding.address;
    _phone.text = branding.phone;
    _receiptHeader.text = branding.receiptHeader;
    _receiptFooter.text = branding.receiptFooter;
    _currencyCode.text = branding.currencyCode;
    _locale.text = branding.locale;
    _timezone.text = branding.timezone;
    _operations = runtime.operations;
    _benefits = runtime.benefits;
    _cardPercent.text = _operations.cardCommissionPercent.toStringAsFixed(2);
  }

  Future<void> _prepare() async {
    setState(() => _saving = true);
    try {
      final result = await _service.prepareCommercialConfiguration();
      if (!mounted) return;
      setState(() => _lastPreparation = result);
      widget.onReload();
      showAppSnackBar(
        context,
        result.hasErrors
            ? 'Preparacion terminada con errores.'
            : 'Configuracion comercial preparada.',
      );
    } catch (error) {
      if (mounted) showAppSnackBar(context, 'No se pudo preparar: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveBranding() async {
    setState(() => _saving = true);
    try {
      await _service.saveBranding(
        CommercialBranding(
          businessName: _businessName.text.trim().isEmpty
              ? AppConstants.restaurantName
              : _businessName.text.trim(),
          shortName: _shortName.text.trim().isEmpty
              ? AppConstants.brandName
              : _shortName.text.trim(),
          logoUrl: _logoUrl.text.trim(),
          primaryColorHex: _primaryColor.text.trim(),
          accentColorHex: _accentColor.text.trim(),
          address: _address.text.trim(),
          phone: _phone.text.trim(),
          receiptHeader: _receiptHeader.text.trim().isEmpty
              ? AppConstants.restaurantName
              : _receiptHeader.text.trim(),
          receiptFooter: _receiptFooter.text.trim().isEmpty
              ? 'Gracias por su compra'
              : _receiptFooter.text.trim(),
          currencyCode: _currencyCode.text.trim().isEmpty
              ? 'MXN'
              : _currencyCode.text.trim(),
          locale: _locale.text.trim().isEmpty ? 'es_MX' : _locale.text.trim(),
          timezone: _timezone.text.trim().isEmpty
              ? AppConstants.defaultTimezone
              : _timezone.text.trim(),
          active: true,
        ),
      );
      if (!mounted) return;
      widget.onReload();
      showAppSnackBar(context, 'Branding guardado.');
    } catch (error) {
      if (mounted) showAppSnackBar(context, 'No se pudo guardar branding.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveOperations() async {
    setState(() => _saving = true);
    try {
      final percent = double.tryParse(_cardPercent.text.trim());
      await _service.saveOperations(
        OperationalPolicy(
          requireCashOpening: _operations.requireCashOpening,
          requireCashClosing: _operations.requireCashClosing,
          requireKitchenOpening: _operations.requireKitchenOpening,
          requireKitchenClosing: _operations.requireKitchenClosing,
          blockPaymentWhileKitchenPending:
              _operations.blockPaymentWhileKitchenPending,
          allowPaymentWithKitchenPending:
              _operations.allowPaymentWithKitchenPending,
          autoStartKitchenSession: _operations.autoStartKitchenSession,
          autoCloseKitchenSession: _operations.autoCloseKitchenSession,
          requireCancellationReason: _operations.requireCancellationReason,
          requireDiscountAuthorization:
              _operations.requireDiscountAuthorization,
          allowSplitPayments: _operations.allowSplitPayments,
          cardCommissionEnabled: _operations.cardCommissionEnabled,
          cardCommissionPercent: percent ?? _operations.cardCommissionPercent,
          businessDayFollowsCashSession:
              _operations.businessDayFollowsCashSession,
        ),
      );
      if (!mounted) return;
      widget.onReload();
      showAppSnackBar(context, 'Politicas guardadas en preparacion.');
    } catch (error) {
      if (mounted) {
        showAppSnackBar(context, 'No se pudieron guardar politicas.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveBenefits() async {
    setState(() => _saving = true);
    try {
      await _service.saveBenefits(_benefits);
      if (!mounted) return;
      widget.onReload();
      showAppSnackBar(context, 'Beneficios guardados en preparacion.');
    } catch (error) {
      if (mounted) {
        showAppSnackBar(context, 'No se pudieron guardar beneficios.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        _Header(runtime: runtime, busy: _saving, onPrepare: _prepare),
        if (_lastPreparation != null) ...[
          const SizedBox(height: 14),
          _PreparationSummary(result: _lastPreparation!),
        ],
        const SizedBox(height: 14),
        const _PassiveNotice(),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Identidad y marca',
          icon: Icons.palette_outlined,
          child: _BrandingForm(
            businessName: _businessName,
            shortName: _shortName,
            logoUrl: _logoUrl,
            primaryColor: _primaryColor,
            accentColor: _accentColor,
            address: _address,
            phone: _phone,
            receiptHeader: _receiptHeader,
            receiptFooter: _receiptFooter,
            currencyCode: _currencyCode,
            locale: _locale,
            timezone: _timezone,
            saving: _saving,
            onSave: _saveBranding,
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Plan',
          icon: Icons.workspace_premium_outlined,
          child: _PlanPreview(runtime: runtime),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Modulos',
          icon: Icons.apps_outlined,
          child: _FeaturesPreview(features: runtime.features),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Caja y Cocina',
          icon: Icons.tune_outlined,
          child: _OperationsForm(
            operations: _operations,
            cardPercent: _cardPercent,
            saving: _saving,
            onChanged: (value) => setState(() => _operations = value),
            onSave: _saveOperations,
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Descuentos, Empleados, Socios, Familia y amigos',
          icon: Icons.percent_outlined,
          child: _BenefitsForm(
            benefits: _benefits,
            saving: _saving,
            onChanged: (value) => setState(() => _benefits = value),
            onSave: _saveBenefits,
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.runtime,
    required this.busy,
    required this.onPrepare,
  });

  final TenantRuntimeContext runtime;
  final bool busy;
  final VoidCallback onPrepare;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Wrap(
        spacing: 18,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const CommercialBrandLogo(size: 64),
          SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Base comercial multirrestaurante',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  '${runtime.restaurantId} / ${runtime.branchId} · '
                  '${CommercialPlan.nameFor(runtime.planId)}',
                  style: const TextStyle(color: BrandColors.textMuted),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: busy ? null : onPrepare,
            icon: const Icon(Icons.playlist_add_check_outlined),
            label: Text(
              busy ? 'Preparando...' : 'Preparar configuracion comercial',
            ),
          ),
        ],
      ),
    );
  }
}

class _PassiveNotice extends StatelessWidget {
  const _PassiveNotice();

  @override
  Widget build(BuildContext context) {
    return const GlassCard(
      accent: BrandColors.accentYellow,
      child: Text(
        'Configuracion preparada; aun no afecta la operacion. '
        'commercialFeaturesEnabled y policyEngineEnabled permanecen apagados.',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PreparationSummary extends StatelessWidget {
  const _PreparationSummary({required this.result});

  final CommercialPreparationResult result;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accent: result.hasErrors ? BrandColors.danger : BrandColors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen de inicializacion',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text('Documentos creados: ${result.createdDocuments.join(', ')}'),
          Text('Documentos existentes: ${result.existingDocuments.join(', ')}'),
          Text(
            'Valores predeterminados: ${result.defaultDocuments.join(', ')}',
          ),
          Text(
            'Informacion operativa modificada: ${result.modifiedOperationalData}',
          ),
          if (result.errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...result.errors.map(
              (error) => Text(
                error,
                style: const TextStyle(color: BrandColors.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: BrandColors.accentYellow),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _BrandingForm extends StatelessWidget {
  const _BrandingForm({
    required this.businessName,
    required this.shortName,
    required this.logoUrl,
    required this.primaryColor,
    required this.accentColor,
    required this.address,
    required this.phone,
    required this.receiptHeader,
    required this.receiptFooter,
    required this.currencyCode,
    required this.locale,
    required this.timezone,
    required this.saving,
    required this.onSave,
  });

  final TextEditingController businessName;
  final TextEditingController shortName;
  final TextEditingController logoUrl;
  final TextEditingController primaryColor;
  final TextEditingController accentColor;
  final TextEditingController address;
  final TextEditingController phone;
  final TextEditingController receiptHeader;
  final TextEditingController receiptFooter;
  final TextEditingController currencyCode;
  final TextEditingController locale;
  final TextEditingController timezone;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _field(businessName, 'Nombre comercial', 320),
            _field(shortName, 'Nombre corto', 240),
            _field(logoUrl, 'Logo URL', 420),
            _field(primaryColor, 'Color primario', 180),
            _field(accentColor, 'Color acento', 180),
            _field(address, 'Direccion', 420),
            _field(phone, 'Telefono', 220),
            _field(receiptHeader, 'Encabezado ticket', 320),
            _field(receiptFooter, 'Pie ticket', 320),
            _field(currencyCode, 'Moneda', 140),
            _field(locale, 'Locale', 160),
            _field(timezone, 'Zona horaria', 240),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar branding'),
          ),
        ),
      ],
    );
  }
}

class _PlanPreview extends StatelessWidget {
  const _PlanPreview({required this.runtime});

  final TenantRuntimeContext runtime;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _pill('Plan actual', CommercialPlan.nameFor(runtime.planId)),
        _pill('Tenant', runtime.tenantId),
        _pill(
          'Compatibilidad',
          runtime.compatibilityMode ? 'Activa' : 'Inactiva',
        ),
        _pill(
          'Licenciamiento',
          runtime.licensingEnforcement ? 'Activo' : 'Apagado',
        ),
        _pill(
          'Motor de politicas',
          runtime.policyEngineEnabled ? 'Activo' : 'Apagado',
        ),
        _pill(
          'Commercial features',
          runtime.commercialFeaturesEnabled ? 'Activo' : 'Apagado',
        ),
      ],
    );
  }
}

class _FeaturesPreview extends StatelessWidget {
  const _FeaturesPreview({required this.features});

  final AppCapabilities features;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: AppCapabilities.featureKeys
          .map(
            (feature) => Chip(
              avatar: Icon(
                features.hasFeature(feature)
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
                size: 16,
              ),
              label: Text(feature),
            ),
          )
          .toList(),
    );
  }
}

class _OperationsForm extends StatelessWidget {
  const _OperationsForm({
    required this.operations,
    required this.cardPercent,
    required this.saving,
    required this.onChanged,
    required this.onSave,
  });

  final OperationalPolicy operations;
  final TextEditingController cardPercent;
  final bool saving;
  final ValueChanged<OperationalPolicy> onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _switch(
              'Caja requiere apertura',
              operations.requireCashOpening,
              (value) => onChanged(_copy(requireCashOpening: value)),
            ),
            _switch(
              'Caja requiere cierre',
              operations.requireCashClosing,
              (value) => onChanged(_copy(requireCashClosing: value)),
            ),
            _switch(
              'Cocina requiere apertura',
              operations.requireKitchenOpening,
              (value) => onChanged(_copy(requireKitchenOpening: value)),
            ),
            _switch(
              'Cocina requiere cierre',
              operations.requireKitchenClosing,
              (value) => onChanged(_copy(requireKitchenClosing: value)),
            ),
            _switch(
              'Bloquear cobro con cocina pendiente',
              operations.blockPaymentWhileKitchenPending,
              (value) =>
                  onChanged(_copy(blockPaymentWhileKitchenPending: value)),
            ),
            _switch(
              'Permitir cobro con cocina pendiente',
              operations.allowPaymentWithKitchenPending,
              (value) =>
                  onChanged(_copy(allowPaymentWithKitchenPending: value)),
            ),
            _switch(
              'Pagos divididos',
              operations.allowSplitPayments,
              (value) => onChanged(_copy(allowSplitPayments: value)),
            ),
            _switch(
              'Comision tarjeta',
              operations.cardCommissionEnabled,
              (value) => onChanged(_copy(cardCommissionEnabled: value)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: _field(cardPercent, 'Comision tarjeta %', 190),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar politicas'),
          ),
        ),
      ],
    );
  }

  OperationalPolicy _copy({
    bool? requireCashOpening,
    bool? requireCashClosing,
    bool? requireKitchenOpening,
    bool? requireKitchenClosing,
    bool? blockPaymentWhileKitchenPending,
    bool? allowPaymentWithKitchenPending,
    bool? allowSplitPayments,
    bool? cardCommissionEnabled,
  }) {
    return OperationalPolicy(
      requireCashOpening: requireCashOpening ?? operations.requireCashOpening,
      requireCashClosing: requireCashClosing ?? operations.requireCashClosing,
      requireKitchenOpening:
          requireKitchenOpening ?? operations.requireKitchenOpening,
      requireKitchenClosing:
          requireKitchenClosing ?? operations.requireKitchenClosing,
      blockPaymentWhileKitchenPending:
          blockPaymentWhileKitchenPending ??
          operations.blockPaymentWhileKitchenPending,
      allowPaymentWithKitchenPending:
          allowPaymentWithKitchenPending ??
          operations.allowPaymentWithKitchenPending,
      autoStartKitchenSession: operations.autoStartKitchenSession,
      autoCloseKitchenSession: operations.autoCloseKitchenSession,
      requireCancellationReason: operations.requireCancellationReason,
      requireDiscountAuthorization: operations.requireDiscountAuthorization,
      allowSplitPayments: allowSplitPayments ?? operations.allowSplitPayments,
      cardCommissionEnabled:
          cardCommissionEnabled ?? operations.cardCommissionEnabled,
      cardCommissionPercent: operations.cardCommissionPercent,
      businessDayFollowsCashSession: operations.businessDayFollowsCashSession,
    );
  }
}

class _BenefitsForm extends StatelessWidget {
  const _BenefitsForm({
    required this.benefits,
    required this.saving,
    required this.onChanged,
    required this.onSave,
  });

  final BenefitPolicies benefits;
  final bool saving;
  final ValueChanged<BenefitPolicies> onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _BenefitTile(
              title: 'Empleado',
              lines: [
                '${benefits.employeeDiscount.percent.toStringAsFixed(0)}% descuento',
                '${benefits.employeeDiscount.maxOrdersPerDay} orden/dia',
              ],
            ),
            _BenefitTile(
              title: 'Comida empleado',
              lines: [
                '${benefits.employeeMeal.maxMealsPerDay} comida/dia',
                benefits.employeeMeal.dineInOnly ? 'Consumo local' : 'Flexible',
              ],
            ),
            _BenefitTile(
              title: 'Socios',
              lines: [
                '${benefits.partnerDiscount.percent.toStringAsFixed(0)}% descuento',
                benefits.partnerDiscount.requiresPin
                    ? 'Requiere PIN'
                    : 'Sin PIN',
              ],
            ),
            _BenefitTile(
              title: 'Familia y amigos',
              lines: [
                '${benefits.friendsAndFamilyDiscount.percent.toStringAsFixed(0)}% descuento',
                'Autorizacion requerida',
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar beneficios'),
          ),
        ),
      ],
    );
  }
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            ...lines.map(
              (line) => Text(
                line,
                style: const TextStyle(color: BrandColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _field(TextEditingController controller, String label, double width) {
  return SizedBox(
    width: width,
    child: TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
    ),
  );
}

Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
  return SizedBox(
    width: 310,
    child: SwitchListTile(
      dense: true,
      value: value,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      onChanged: onChanged,
    ),
  );
}

Widget _pill(String label, String value) {
  return Container(
    width: 230,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: BrandColors.glassFill,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: BrandColors.glassBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: BrandColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    ),
  );
}
