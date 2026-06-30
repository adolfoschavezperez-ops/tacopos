import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/brand_colors.dart';
import '../services/app_session.dart';
import '../services/taco_pos_repository.dart';
import 'glass.dart';

class BrandedScaffold extends StatelessWidget {
  const BrandedScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.bottomNavigationBar,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 700;
    final toolbarHeight = compact ? 58.0 : 68.0;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(toolbarHeight),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AppBar(
              toolbarHeight: toolbarHeight,
              titleSpacing: compact ? 8 : 12,
              backgroundColor: BrandColors.backgroundPrimary.withValues(
                alpha: 0.62,
              ),
              title: Row(
                children: [
                  _AppBarLogo(compact: compact),
                  SizedBox(width: compact ? 8 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!compact)
                          const Text(
                            AppConstants.brandName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: BrandColors.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                _OperationDateBadge(compact: compact),
                _SessionBadge(compact: compact),
                _ConnectionStatusBadge(compact: compact),
                if (actions != null) ...actions!,
              ],
            ),
          ),
        ),
      ),
      body: PremiumBackground(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(top: toolbarHeight),
            child: body,
          ),
        ),
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class _OperationDateBadge extends StatelessWidget {
  const _OperationDateBadge({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();
    return StreamBuilder(
      stream: repository.watchOpenCashSession(),
      builder: (context, snapshot) {
        final businessDate = snapshot.data?.businessDate;
        final label = businessDate == null
            ? (compact ? 'Sin caja' : 'Sin caja abierta')
            : compact
            ? 'Op: $businessDate'
            : 'Operacion: $businessDate';
        final color = businessDate == null
            ? BrandColors.accentYellow
            : BrandColors.textSecondary;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Tooltip(
            message: label,
            child: Container(
              constraints: BoxConstraints(maxWidth: compact ? 132 : 180),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 10,
                vertical: compact ? 5 : 6,
              ),
              decoration: BoxDecoration(
                color: BrandColors.glassFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BrandColors.glassBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_outlined, size: 16, color: color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SessionBadge extends StatelessWidget {
  const _SessionBadge({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSession.instance,
      builder: (context, _) {
        final employee = AppSession.instance.employee;
        if (employee == null) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Tooltip(
            message: 'Cerrar sesion',
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
                AppSession.instance.signOut();
              },
              child: Container(
                constraints: BoxConstraints(maxWidth: compact ? 82 : 170),
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 10,
                  vertical: compact ? 5 : 6,
                ),
                decoration: BoxDecoration(
                  color: BrandColors.glassFill,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: BrandColors.glassBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.person_outline,
                      size: 16,
                      color: BrandColors.accentYellow,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        compact ? 'Salir' : employee.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.logout, size: 15),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConnectionStatusBadge extends StatelessWidget {
  const _ConnectionStatusBadge({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final restaurantStream = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(AppConstants.restaurantId)
        .snapshots(includeMetadataChanges: true);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: restaurantStream,
      builder: (context, snapshot) {
        final metadata = snapshot.data?.metadata;
        final offlineOrPending =
            metadata == null ||
            metadata.isFromCache ||
            metadata.hasPendingWrites;
        final label = offlineOrPending
            ? (compact ? 'Sync' : 'Sin conexion / pendiente de sincronizar')
            : (compact ? 'OK' : 'En linea');
        final color = offlineOrPending
            ? BrandColors.accentYellow
            : BrandColors.success;

        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Tooltip(
            message: label,
            child: Container(
              constraints: BoxConstraints(maxWidth: compact ? 54 : 190),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 10,
                vertical: compact ? 5 : 6,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.42)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    offlineOrPending ? Icons.cloud_off : Icons.cloud_done,
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AppBarLogo extends StatelessWidget {
  const _AppBarLogo({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 34 : 40,
      height: compact ? 34 : 40,
      decoration: BoxDecoration(
        color: BrandColors.glassFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BrandColors.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Image.asset(
          AppConstants.logoAsset,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.local_fire_department,
            color: BrandColors.accentYellow,
          ),
        ),
      ),
    );
  }
}
