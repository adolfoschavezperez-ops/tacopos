import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/brand_colors.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import '../models/cash_withdrawal_request.dart';
import '../services/app_session.dart';
import '../services/live_presence_service.dart';
import '../services/taco_pos_repository.dart';
import '../widgets/glass.dart';
import 'admin/cash_admin_screen.dart';
import 'admin/admin_dashboard_screen.dart';
import 'admin/backoffice_screen.dart';
import 'cash/cash_session_screen.dart';
import 'kitchen_control/kitchen_control_screen.dart';
import 'kitchen/kitchen_screen.dart';
import 'waiter/tables_screen.dart';

enum AppMode { waiterCashier, cash, kitchenControl, kitchen, admin }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    _markMainMenu();
  }

  Future<void> _markMainMenu({String action = 'En menú principal'}) {
    return LivePresenceService.instance.markMainMenu(currentAction: action);
  }

  Future<void> _showBranchSelector() async {
    final selected = await showDialog<Branch>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Seleccionar sucursal'),
        children: AppSession.instance.accessibleBranches
            .map(
              (branch) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, branch),
                child: Text(branch.name),
              ),
            )
            .toList(),
      ),
    );
    if (selected != null) {
      AppSession.instance.selectBranch(selected);
      await _markMainMenu(action: 'Sucursal cambiada');
    }
  }

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

  Future<void> _openMode(AppMode mode) async {
    if (kIsWeb && mode != AppMode.admin) {
      return;
    }
    if (mode == AppMode.kitchen) {
      final repository = TacoPosRepository();
      final kitchenIsOpen = await repository
          .hasCompletedOpenKitchenForCurrentBusinessDate();
      if (!mounted) {
        return;
      }
      if (!kitchenIsOpen) {
        final openKitchenControl = await _showKitchenNotOpenDialog();
        if (!mounted) {
          return;
        }
        if (openKitchenControl) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const KitchenControlScreen()),
          );
          if (!mounted) {
            return;
          }
        }
        await _markMainMenu();
        return;
      }
    }

    final Widget screen = switch (mode) {
      AppMode.waiterCashier => const TablesScreen(),
      AppMode.cash => const CashSessionScreen(),
      AppMode.kitchenControl => const KitchenControlScreen(),
      AppMode.kitchen => const KitchenScreen(),
      AppMode.admin => const AdminDashboardScreen(),
    };

    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (!mounted) {
      return;
    }
    await _markMainMenu();
  }

  Future<bool> _showKitchenNotOpenDialog() async {
    final canOpenKitchen = AppSession.instance.employee?.canOpenKitchen == true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cocina sin apertura'),
            content: Text(
              canOpenKitchen
                  ? 'Debes completar la apertura de cocina antes de entrar a operacion.'
                  : 'Debes completar la apertura de cocina antes de entrar a operacion.\n\nNo tienes permiso para abrir cocina. Solicita a un administrador.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cerrar'),
              ),
              if (canOpenKitchen)
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.soup_kitchen_outlined),
                  label: const Text('Abrir cocina'),
                ),
            ],
          ),
        ) ??
        false;
  }

  void _openWithdrawalRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CashAdminScreen(initialTabIndex: 1),
      ),
    ).then((_) {
      if (mounted) {
        _markMainMenu();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final employee = AppSession.instance.employee;
    if (kIsWeb) {
      return const BackofficeScreen();
    }
    return Scaffold(
      body: PremiumBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final compact =
                  constraints.maxWidth < 700 || constraints.maxHeight < 800;

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: compact
                      ? 14
                      : wide
                      ? 40
                      : 22,
                  vertical: compact
                      ? 12
                      : wide
                      ? 34
                      : 22,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        constraints.maxHeight -
                        (compact
                            ? 24
                            : wide
                            ? 68
                            : 44),
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
                                    compact: compact,
                                    onSignOut: _confirmSignOut,
                                    onChangeBranch: _showBranchSelector,
                                  ),
                                ),
                                const SizedBox(width: 34),
                                Expanded(
                                  flex: 9,
                                  child: _ModePanel(
                                    employee: employee,
                                    compact: compact,
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
                                  compact: compact,
                                  onSignOut: _confirmSignOut,
                                  onChangeBranch: _showBranchSelector,
                                ),
                                SizedBox(height: compact ? 12 : 24),
                                _ModePanel(
                                  employee: employee,
                                  compact: compact,
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
  const _HeroBlock({
    required this.employee,
    required this.compact,
    required this.onSignOut,
    required this.onChangeBranch,
  });

  final Employee? employee;
  final bool compact;
  final VoidCallback onSignOut;
  final VoidCallback onChangeBranch;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassPanel(
          padding: EdgeInsets.all(compact ? 8 : 14),
          borderRadius: compact ? 20 : 28,
          glowColor: BrandColors.accentGlow,
          child: SizedBox(
            width: compact ? 82 : 150,
            height: compact ? 82 : 150,
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
        SizedBox(height: compact ? 14 : 34),
        Text(
          AppConstants.brandName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontSize: compact ? 34 : 54,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: compact ? 4 : 10),
        Text(
          'TacoPOS',
          style: TextStyle(
            color: BrandColors.accentOrange,
            fontSize: compact ? 15 : 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: compact ? 8 : 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Text(
            'Mesas, comandas y cocina en tiempo real.',
            style: TextStyle(
              color: BrandColors.textSecondary,
              fontSize: compact ? 15 : 20,
              height: 1.28,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        SizedBox(height: compact ? 10 : 18),
        const _HomeOperationBadge(),
        SizedBox(height: compact ? 6 : 10),
        _BranchBadge(onChangeBranch: onChangeBranch),
        SizedBox(height: compact ? 6 : 10),
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

class _BranchBadge extends StatelessWidget {
  const _BranchBadge({required this.onChangeBranch});

  final VoidCallback onChangeBranch;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSession.instance,
      builder: (context, _) {
        final session = AppSession.instance;
        return OutlinedButton.icon(
          onPressed: session.canChangeBranch ? onChangeBranch : null,
          icon: const Icon(Icons.storefront_outlined),
          label: Text(
            session.canChangeBranch
                ? 'Cambiar sucursal · ${session.currentBranchName}'
                : '${session.currentRestaurantName} · ${session.currentBranchName}',
          ),
        );
      },
    );
  }
}

class _HomeOperationBadge extends StatelessWidget {
  const _HomeOperationBadge();

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();
    return StreamBuilder(
      stream: repository.watchOpenCashSession(),
      builder: (context, snapshot) {
        final businessDate = snapshot.data?.businessDate;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: BrandColors.glassFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: BrandColors.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.event_outlined,
                size: 16,
                color: businessDate == null
                    ? BrandColors.accentYellow
                    : BrandColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                businessDate == null
                    ? 'Sin caja abierta'
                    : 'Operacion: $businessDate',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: BrandColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModePanel extends StatelessWidget {
  const _ModePanel({
    required this.employee,
    required this.compact,
    required this.onOpenMode,
    required this.onReviewWithdrawals,
  });

  final Employee? employee;
  final bool compact;
  final ValueChanged<AppMode> onOpenMode;
  final VoidCallback onReviewWithdrawals;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: EdgeInsets.all(compact ? 12 : 20),
      borderRadius: compact ? 20 : 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) ...[
            const SectionHeader(
              title: 'Accesos',
              subtitle: 'Elige el flujo de trabajo.',
            ),
            const SizedBox(height: 18),
          ],
          if (employee?.canAuthorizeCashWithdrawals == true) ...[
            _PendingWithdrawalsAlert(
              compact: compact,
              onReview: onReviewWithdrawals,
            ),
            SizedBox(height: compact ? 8 : 14),
          ],
          if (employee?.canTakeOrders == true ||
              employee?.canCharge == true) ...[
            _ModeTile(
              icon: Icons.table_restaurant_outlined,
              title: 'Mesero / Caja',
              subtitle: 'Mesas, personas y cobro simple',
              compact: compact,
              onTap: () => onOpenMode(AppMode.waiterCashier),
            ),
            SizedBox(height: compact ? 8 : 12),
          ],
          if (employee?.canCharge == true ||
              employee?.canManageCash == true) ...[
            _ModeTile(
              icon: Icons.point_of_sale_outlined,
              title: 'Caja / Corte',
              subtitle: 'Abrir dia, revisar totales y cerrar caja',
              compact: compact,
              onTap: () => onOpenMode(AppMode.cash),
            ),
            SizedBox(height: compact ? 8 : 12),
          ],
          if (employee?.canViewKitchen == true ||
              employee?.canOpenKitchen == true ||
              employee?.canCloseKitchen == true) ...[
            _ModeTile(
              icon: Icons.soup_kitchen_outlined,
              title: 'Control de cocina',
              subtitle: 'Apertura, entradas y cierre diario',
              compact: compact,
              onTap: () => onOpenMode(AppMode.kitchenControl),
            ),
            SizedBox(height: compact ? 8 : 12),
          ],
          if (employee?.canViewKitchen == true) ...[
            _ModeTile(
              icon: Icons.room_service_outlined,
              title: 'Cocina',
              subtitle: 'Comandas enviadas en tiempo real',
              compact: compact,
              onTap: () => onOpenMode(AppMode.kitchen),
            ),
            SizedBox(height: compact ? 8 : 12),
          ],
          if (employee?.canViewAdmin == true)
            _ModeTile(
              icon: Icons.insights_outlined,
              title: 'Socio / Admin',
              subtitle: 'Metricas y catalogo de productos',
              compact: compact,
              onTap: () => onOpenMode(AppMode.admin),
            ),
          if (employee != null &&
              !employee!.canTakeOrders &&
              !employee!.canCharge &&
              !employee!.canManageCash &&
              !employee!.canViewKitchen &&
              !employee!.canOpenKitchen &&
              !employee!.canCloseKitchen &&
              !employee!.canViewKitchenReports &&
              !employee!.canManageKitchenStock &&
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
  const _PendingWithdrawalsAlert({
    required this.compact,
    required this.onReview,
  });

  final bool compact;
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
          return GlassCard(
            padding: EdgeInsets.all(compact ? 10 : 16),
            child: Row(
              children: [
                const Icon(Icons.verified_outlined, color: BrandColors.success),
                SizedBox(width: compact ? 8 : 12),
                const Expanded(
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
          padding: EdgeInsets.all(compact ? 10 : 16),
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
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: EdgeInsets.all(compact ? 10 : 16),
      child: Row(
        children: [
          Container(
            width: compact ? 38 : 48,
            height: compact ? 38 : 48,
            decoration: BoxDecoration(
              color: BrandColors.glassHighlight,
              borderRadius: BorderRadius.circular(compact ? 12 : 16),
            ),
            child: Icon(
              icon,
              color: BrandColors.accentYellow,
              size: compact ? 21 : 26,
            ),
          ),
          SizedBox(width: compact ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.textPrimary,
                  ),
                ),
                SizedBox(height: compact ? 2 : 4),
                Text(
                  subtitle,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: BrandColors.textMuted,
                    fontSize: compact ? 11 : 13,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 6 : 10),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: compact ? 13 : 16,
            color: BrandColors.textMuted,
          ),
        ],
      ),
    );
  }
}
