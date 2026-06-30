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
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AppBar(
              toolbarHeight: 68,
              titleSpacing: 12,
              backgroundColor: BrandColors.backgroundPrimary.withValues(
                alpha: 0.62,
              ),
              title: Row(
                children: [
                  const _AppBarLogo(),
                  const SizedBox(width: 12),
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
                const _OperationDateBadge(),
                const _SessionBadge(),
                const _ConnectionStatusBadge(),
                if (actions != null) ...actions!,
              ],
            ),
          ),
        ),
      ),
      body: PremiumBackground(
        child: SafeArea(
          top: false,
          child: Padding(padding: const EdgeInsets.only(top: 68), child: body),
        ),
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class _OperationDateBadge extends StatelessWidget {
  const _OperationDateBadge();

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();
    return StreamBuilder(
      stream: repository.watchOpenCashSession(),
      builder: (context, snapshot) {
        final businessDate = snapshot.data?.businessDate;
        final label = businessDate == null
            ? 'Sin caja abierta'
            : 'Operacion: $businessDate';
        final color = businessDate == null
            ? BrandColors.accentYellow
            : BrandColors.textSecondary;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Tooltip(
            message: label,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 180),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
  const _SessionBadge();

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
                constraints: const BoxConstraints(maxWidth: 170),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
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
                        employee.name,
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
  const _ConnectionStatusBadge();

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
            ? 'Sin conexion / pendiente de sincronizar'
            : 'En linea';
        final color = offlineOrPending
            ? BrandColors.accentYellow
            : BrandColors.success;

        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Tooltip(
            message: label,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 190),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
  const _AppBarLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
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
