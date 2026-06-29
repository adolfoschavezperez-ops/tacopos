import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/brand_colors.dart';
import '../services/demo_seed_service.dart';
import '../widgets/brand_logo_mark.dart';
import 'admin/admin_dashboard_screen.dart';
import 'kitchen/kitchen_screen.dart';
import 'waiter/tables_screen.dart';

enum AppMode { waiterCashier, kitchen, admin }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _seedService = DemoSeedService();
  bool _loading = false;
  String _message = '';

  User? get _user => FirebaseAuth.instance.currentUser;

  Future<void> _createDemoData() async {
    setState(() {
      _loading = true;
      _message = '';
    });

    try {
      await _seedService.createDemoData();

      if (!mounted) {
        return;
      }

      setState(() {
        _message = 'Datos demo creados correctamente.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _message = 'Error: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _openMode(AppMode mode) {
    final Widget screen = switch (mode) {
      AppMode.waiterCashier => const TablesScreen(),
      AppMode.kitchen => const KitchenScreen(),
      AppMode.admin => const AdminDashboardScreen(),
    };

    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final uid = _user?.uid ?? 'Sin usuario';

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    BrandColors.black,
                    BrandColors.surface,
                    BrandColors.orangeDark.withValues(alpha: 0.28),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 42,
            right: -64,
            child: Transform.rotate(
              angle: -0.2,
              child: Container(
                width: 320,
                height: 56,
                color: BrandColors.orange.withValues(alpha: 0.28),
              ),
            ),
          ),
          Positioned(
            bottom: 62,
            left: -90,
            child: Transform.rotate(
              angle: -0.2,
              child: Container(
                width: 280,
                height: 48,
                color: BrandColors.yellow.withValues(alpha: 0.18),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 820;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 48,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(child: _HeroBlock(uid: uid)),
                                  const SizedBox(width: 30),
                                  Expanded(
                                    child: _ModePanel(
                                      loading: _loading,
                                      message: _message,
                                      onSeed: _createDemoData,
                                      onOpenMode: _openMode,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _HeroBlock(uid: uid),
                                  const SizedBox(height: 28),
                                  _ModePanel(
                                    loading: _loading,
                                    message: _message,
                                    onSeed: _createDemoData,
                                    onOpenMode: _openMode,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandLogoMark(),
        const SizedBox(height: 28),
        Text(
          AppConstants.appName.toUpperCase(),
          style: const TextStyle(
            color: BrandColors.yellow,
            fontSize: 72,
            fontWeight: FontWeight.w900,
            height: 0.9,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Mesas, comandas y cocina en tiempo real para una taqueria rapida.',
          style: TextStyle(
            color: BrandColors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: BrandColors.surfaceHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: BrandColors.orange.withValues(alpha: 0.5),
            ),
          ),
          child: Text(
            'Firebase conectado  |  UID: $uid',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: BrandColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModePanel extends StatelessWidget {
  const _ModePanel({
    required this.loading,
    required this.message,
    required this.onSeed,
    required this.onOpenMode,
  });

  final bool loading;
  final String message;
  final VoidCallback onSeed;
  final ValueChanged<AppMode> onOpenMode;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Entrar como',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            _ModeTile(
              icon: Icons.table_restaurant,
              title: 'Mesero / Caja',
              subtitle: 'Mesas, personas, comandas y cobro simple',
              onTap: () => onOpenMode(AppMode.waiterCashier),
            ),
            const SizedBox(height: 12),
            _ModeTile(
              icon: Icons.soup_kitchen,
              title: 'Cocina',
              subtitle: 'Ordenes enviadas, preparacion y listo',
              onTap: () => onOpenMode(AppMode.kitchen),
            ),
            const SizedBox(height: 12),
            _ModeTile(
              icon: Icons.analytics,
              title: 'Socio / Admin',
              subtitle: 'Dashboard y catalogo editable',
              onTap: () => onOpenMode(AppMode.admin),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: loading ? null : onSeed,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(loading ? 'Creando...' : 'Crear datos demo'),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: message.startsWith('Error')
                      ? BrandColors.danger
                      : BrandColors.success,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BrandColors.surfaceHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: BrandColors.orange.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: BrandColors.yellow, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: BrandColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right, color: BrandColors.orange),
            ],
          ),
        ),
      ),
    );
  }
}
