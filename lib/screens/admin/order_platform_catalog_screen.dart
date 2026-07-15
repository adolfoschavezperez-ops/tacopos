import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/order_platform.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';

class OrderPlatformCatalogScreen extends StatefulWidget {
  const OrderPlatformCatalogScreen({super.key});

  @override
  State<OrderPlatformCatalogScreen> createState() =>
      _OrderPlatformCatalogScreenState();
}

class _OrderPlatformCatalogScreenState
    extends State<OrderPlatformCatalogScreen> {
  final _repository = TacoPosRepository();

  @override
  void initState() {
    super.initState();
    _repository.ensureDefaultOrderPlatforms();
  }

  Future<void> _showPlatformDialog({OrderPlatform? platform}) async {
    final result = await showDialog<_PlatformFormResult>(
      context: context,
      builder: (_) => _PlatformDialog(platform: platform),
    );

    if (!mounted || result == null) {
      return;
    }

    try {
      await _repository.saveOrderPlatform(
        platformId: platform?.id,
        name: result.name,
        active: result.active,
        sortOrder: result.sortOrder,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        'No se pudo guardar plataforma: $error',
        type: AppSnackBarType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppSession.instance.employee?.canManagePlatforms != true) {
      return const BrandedScaffold(
        title: 'Plataformas',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para administrar plataformas.',
        ),
      );
    }

    return BrandedScaffold(
      title: 'Plataformas',
      actions: [
        IconButton(
          tooltip: 'Agregar plataforma',
          onPressed: () => _showPlatformDialog(),
          icon: const Icon(Icons.add_circle),
        ),
      ],
      body: StreamBuilder<List<OrderPlatform>>(
        stream: _repository.watchOrderPlatforms(activeOnly: false),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudieron cargar plataformas',
              message: '${snapshot.error}',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Cargando plataformas...');
          }

          final platforms = snapshot.data ?? [];
          if (platforms.isEmpty) {
            return const EmptyState(
              icon: Icons.delivery_dining,
              title: 'Sin plataformas',
              message: 'Agrega canales para pedidos para llevar.',
            );
          }

          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              SectionHeader(
                title: 'Catalogo de plataformas',
                subtitle: '${platforms.length} canales configurados',
              ),
              const SizedBox(height: 18),
              ...platforms.map(
                (platform) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PlatformTile(
                    platform: platform,
                    onEdit: () => _showPlatformDialog(platform: platform),
                    onToggle: () => _repository.toggleOrderPlatform(platform),
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
          label: 'Agregar plataforma',
          prominent: true,
          onTap: () => _showPlatformDialog(),
        ),
      ),
    );
  }
}

class _PlatformDialog extends StatefulWidget {
  const _PlatformDialog({this.platform});

  final OrderPlatform? platform;

  @override
  State<_PlatformDialog> createState() => _PlatformDialogState();
}

class _PlatformDialogState extends State<_PlatformDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _sortController;
  late bool _active;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.platform?.name ?? '');
    _sortController = TextEditingController(
      text: (widget.platform?.sortOrder ?? 0).toString(),
    );
    _active = widget.platform?.active ?? true;
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
      _PlatformFormResult(name: name, active: _active, sortOrder: sortOrder),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.platform == null ? 'Agregar plataforma' : 'Editar plataforma',
      ),
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
}

class _PlatformFormResult {
  const _PlatformFormResult({
    required this.name,
    required this.active,
    required this.sortOrder,
  });

  final String name;
  final bool active;
  final int sortOrder;
}

class _PlatformTile extends StatelessWidget {
  const _PlatformTile({
    required this.platform,
    required this.onEdit,
    required this.onToggle,
  });

  final OrderPlatform platform;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accent: platform.active ? BrandColors.info : BrandColors.textMuted,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: platform.active
                  ? BrandColors.info.withValues(alpha: 0.16)
                  : BrandColors.glassFill,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              platform.active ? Icons.delivery_dining : Icons.visibility_off,
              color: platform.active ? BrandColors.info : BrandColors.textMuted,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  platform.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Orden ${platform.sortOrder}',
                  style: const TextStyle(color: BrandColors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Editar',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: platform.active ? 'Desactivar' : 'Activar',
            onPressed: onToggle,
            icon: Icon(platform.active ? Icons.toggle_on : Icons.toggle_off),
            color: platform.active
                ? BrandColors.success
                : BrandColors.textMuted,
          ),
        ],
      ),
    );
  }
}
