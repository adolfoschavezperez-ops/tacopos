import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/brand_colors.dart';
import '../models/employee.dart';
import '../models/cash_withdrawal_request.dart';
import '../services/app_session.dart';
import '../services/taco_pos_repository.dart';
import '../widgets/glass.dart';
import 'admin/cash_admin_screen.dart';
import 'admin/admin_dashboard_screen.dart';
import 'cash/cash_session_screen.dart';
import 'kitchen/kitchen_screen.dart';
import 'waiter/tables_screen.dart';

enum AppMode { waiterCashier, cash, kitchen, admin }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesion'),
        content: const Text('Se cerrara la sesion operativa del empleado.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesion'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      AppSession.instance.signOut();
    }
  }

  void _openMode(AppMode mode) {
    final Widget screen = switch (mode) {
      AppMode.waiterCashier => const TablesScreen(),
      AppMode.cash => const CashSessionScreen(),
      AppMode.kitchen => const KitchenScreen(),
      AppMode.admin => const AdminDashboardScreen(),
    };

    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void _openWithdrawalRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CashAdminScreen(initialTabIndex: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final employee = AppSession.instance.employee;
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
                                Expanded(
                                  flex: 11,
                                  child: _HeroBlock(
                                    employee: employee,
                                    onSignOut: _confirmSignOut,
                                  ),
                                ),
                                const SizedBox(width: 34),
                                Expanded(
                                  flex: 9,
                                  child: _ModePanel(
                                    employee: employee,
                                    onOpenMode: _openMode,
                                    onReviewWithdrawals:
                                        _openWithdrawalRequests,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _HeroBlock(
                                  employee: employee,
                                  onSignOut: _confirmSignOut,
                                ),
                                const SizedBox(height: 24),
                                _ModePanel(
                                  employee: employee,
                                  onOpenMode: _openMode,
                                  onReviewWithdrawals: _openWithdrawalRequests,
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
  const _HeroBlock({required this.employee, required this.onSignOut});

  final Employee? employee;
  final VoidCallback onSignOut;

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
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout),
          label: Text(
            employee == null
                ? 'Cerrar sesion'
                : 'Cerrar sesion · ${employee!.name}',
          ),
        ),
      ],
    );
  }
}

class _ModePanel extends StatelessWidget {
  const _ModePanel({
    required this.employee,
    required this.onOpenMode,
    required this.onReviewWithdrawals,
  });

  final Employee? employee;
  final ValueChanged<AppMode> onOpenMode;
  final VoidCallback onReviewWithdrawals;

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
          if (employee?.canAuthorizeCashWithdrawals == true) ...[
            _PendingWithdrawalsAlert(onReview: onReviewWithdrawals),
            const SizedBox(height: 14),
          ],
          if (employee?.canTakeOrders == true ||
              employee?.canCharge == true) ...[
            _ModeTile(
              icon: Icons.table_restaurant_outlined,
              title: 'Mesero / Caja',
              subtitle: 'Mesas, personas y cobro simple',
              onTap: () => onOpenMode(AppMode.waiterCashier),
            ),
            const SizedBox(height: 12),
          ],
          if (employee?.canCharge == true ||
              employee?.canManageCash == true) ...[
            _ModeTile(
              icon: Icons.point_of_sale_outlined,
              title: 'Caja / Corte',
              subtitle: 'Abrir dia, revisar totales y cerrar caja',
              onTap: () => onOpenMode(AppMode.cash),
            ),
            const SizedBox(height: 12),
          ],
          if (employee?.canViewKitchen == true) ...[
            _ModeTile(
              icon: Icons.room_service_outlined,
              title: 'Cocina',
              subtitle: 'Comandas enviadas en tiempo real',
              onTap: () => onOpenMode(AppMode.kitchen),
            ),
            const SizedBox(height: 12),
          ],
          if (employee?.canViewAdmin == true)
            _ModeTile(
              icon: Icons.insights_outlined,
              title: 'Socio / Admin',
              subtitle: 'Metricas y catalogo de productos',
              onTap: () => onOpenMode(AppMode.admin),
            ),
          if (employee != null &&
              !employee!.canTakeOrders &&
              !employee!.canCharge &&
              !employee!.canManageCash &&
              !employee!.canViewKitchen &&
              !employee!.canViewAdmin)
            const Text(
              'Este usuario no tiene permisos asignados.',
              style: TextStyle(color: BrandColors.textMuted),
            ),
        ],
      ),
    );
  }
}

class _PendingWithdrawalsAlert extends StatelessWidget {
  const _PendingWithdrawalsAlert({required this.onReview});

  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();
    return StreamBuilder<List<CashWithdrawalRequest>>(
      stream: repository.watchCashWithdrawalRequests(status: 'pending'),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return GlassCard(
            accent: BrandColors.danger,
            padding: const EdgeInsets.all(16),
            child: Text(
              'No se pudieron cargar solicitudes: ${snapshot.error}',
              style: const TextStyle(
                color: BrandColors.danger,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }

        final pendingCount = snapshot.data?.length ?? 0;
        if (pendingCount == 0) {
          return const GlassCard(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.verified_outlined, color: BrandColors.success),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sin solicitudes pendientes',
                    style: TextStyle(
                      color: BrandColors.textMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return GlassCard(
          accent: BrandColors.accentYellow,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.notification_important_outlined,
                    color: BrandColors.accentYellow,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tienes $pendingCount solicitudes de gasto pendientes',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: BrandColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: GlassButton(
                  icon: Icons.verified_user_outlined,
                  label: 'Revisar solicitudes',
                  prominent: true,
                  onTap: onReview,
                ),
              ),
            ],
          ),
        );
      },
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
