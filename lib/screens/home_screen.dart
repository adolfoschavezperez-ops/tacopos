import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/brand_colors.dart';
import '../services/demo_seed_service.dart';
import '../widgets/glass.dart';
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
      body: PremiumBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? 40 : 22,
                  vertical: wide ? 34 : 22,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - (wide ? 68 : 44),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Expanded(flex: 11, child: _HeroBlock()),
                                const SizedBox(width: 34),
                                Expanded(
                                  flex: 9,
                                  child: _ModePanel(
                                    uid: uid,
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
                                const _HeroBlock(),
                                const SizedBox(height: 24),
                                _ModePanel(
                                  uid: uid,
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
      ),
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(14),
          borderRadius: 28,
          glowColor: BrandColors.accentGlow,
          child: SizedBox(
            width: 150,
            height: 150,
            child: Image.asset(
              AppConstants.logoAsset,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.local_fire_department,
                size: 72,
                color: BrandColors.accentYellow,
              ),
            ),
          ),
        ),
        const SizedBox(height: 34),
        Text(
          AppConstants.brandName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontSize: 54,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'TacoPOS',
          style: TextStyle(
            color: BrandColors.accentOrange,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: const Text(
            'Mesas, comandas y cocina en tiempo real.',
            style: TextStyle(
              color: BrandColors.textSecondary,
              fontSize: 20,
              height: 1.28,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModePanel extends StatelessWidget {
  const _ModePanel({
    required this.uid,
    required this.loading,
    required this.message,
    required this.onSeed,
    required this.onOpenMode,
  });

  final String uid;
  final bool loading;
  final String message;
  final VoidCallback onSeed;
  final ValueChanged<AppMode> onOpenMode;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(20),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SectionHeader(
            title: 'Accesos',
            subtitle: 'Elige el flujo de trabajo.',
          ),
          const SizedBox(height: 18),
          _ModeTile(
            icon: Icons.table_restaurant_outlined,
            title: 'Mesero / Caja',
            subtitle: 'Mesas, personas y cobro simple',
            onTap: () => onOpenMode(AppMode.waiterCashier),
          ),
          const SizedBox(height: 12),
          _ModeTile(
            icon: Icons.room_service_outlined,
            title: 'Cocina',
            subtitle: 'Comandas enviadas en tiempo real',
            onTap: () => onOpenMode(AppMode.kitchen),
          ),
          const SizedBox(height: 12),
          _ModeTile(
            icon: Icons.insights_outlined,
            title: 'Socio / Admin',
            subtitle: 'Metricas y catalogo de productos',
            onTap: () => onOpenMode(AppMode.admin),
          ),
          const SizedBox(height: 18),
          GlassButton(
            icon: loading ? Icons.hourglass_top : Icons.cloud_upload_outlined,
            label: loading ? 'Creando datos...' : 'Crear datos demo',
            onTap: loading ? null : onSeed,
            prominent: true,
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: message.startsWith('Error')
                    ? BrandColors.danger
                    : BrandColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            'Firebase conectado | ${_shortUid(uid)}',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: BrandColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _shortUid(String uid) {
    if (uid.length <= 12) {
      return uid;
    }

    return '${uid.substring(0, 6)}...${uid.substring(uid.length - 4)}';
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
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: BrandColors.glassHighlight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: BrandColors.accentYellow, size: 26),
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
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BrandColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 16,
            color: BrandColors.textMuted,
          ),
        ],
      ),
    );
  }
}
