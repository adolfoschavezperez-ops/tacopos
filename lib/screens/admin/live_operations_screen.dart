import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/reports/operational_blockers.dart';
import '../../core/theme/brand_colors.dart';
import '../../models/active_session.dart';
import '../../models/activity_event.dart';
import '../../models/employee.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';
import '../../models/product.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/formatters.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';
import '../waiter/payment_screen.dart';

class LiveOperationsScreen extends StatefulWidget {
  const LiveOperationsScreen({super.key, required this.employee});

  final Employee employee;

  @override
  State<LiveOperationsScreen> createState() => _LiveOperationsScreenState();
}

class _LiveOperationsScreenState extends State<LiveOperationsScreen> {
  final _repository = TacoPosRepository();
  final _searchController = TextEditingController();
  String _screenFilter = 'Todos';
  String _statusFilter = 'Todos';
  late String _branchId;
  late Stream<OperationalOpenOrdersSummary> _operationalSummary;
  bool _refreshing = false;

  bool get _canControl => widget.employee.canControlLiveOperations;
  bool get _canView =>
      widget.employee.canViewLiveOperations || widget.employee.canViewAdmin;

  @override
  void initState() {
    super.initState();
    _branchId = AppSession.instance.currentBranchId;
    _operationalSummary = _repository.watchOperationalOpenOrdersSummary();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const EmptyState(
        icon: Icons.lock_outline,
        title: 'Sin permiso',
        message: 'No tienes permiso para ver el visor operativo.',
      );
    }

    final currentBranchId = AppSession.instance.currentBranchId;
    if (_branchId != currentBranchId) {
      _branchId = currentBranchId;
      _operationalSummary = _repository.watchOperationalOpenOrdersSummary();
    }

    return DefaultTabController(
      length: 6,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: GlassPanel(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: SectionHeader(
                          title: 'Visor operativo',
                          subtitle:
                              'Estado en vivo basado en sesiones, ordenes, cocina y pagos.',
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Actualizar',
                        onPressed: _refreshing ? null : _refresh,
                        icon: _refreshing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _cleanupInactiveSessions,
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('Limpiar sesiones inactivas'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: 260,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Buscar empleado',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.clear),
                                  ),
                          ),
                        ),
                      ),
                      _FilterDropdown(
                        label: 'Pantalla',
                        value: _screenFilter,
                        values: const [
                          'Todos',
                          'Inicio',
                          'Mesas',
                          'Orden',
                          'Cobro',
                          'Cocina',
                          'Cocina detalle',
                          'Caja',
                          'Control de cocina',
                          'Backoffice',
                          'Admin',
                        ],
                        onChanged: (value) =>
                            setState(() => _screenFilter = value ?? 'Todos'),
                      ),
                      _FilterDropdown(
                        label: 'Estado',
                        value: _statusFilter,
                        values: const ['Todos', 'En linea', 'Inactivo'],
                        onChanged: (value) =>
                            setState(() => _statusFilter = value ?? 'Todos'),
                      ),
                      _LivePermissionBadge(canControl: _canControl),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<OperationalOpenOrdersSummary>(
              stream: _operationalSummary,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: GlassPanel(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 46,
                            color: BrandColors.accentOrange,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No se pudo cargar el Visor operativo.',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: BrandColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const LoadingPanel(
                    message: 'Cargando operación actual…',
                  );
                }
                _finishRefresh();
                final summary = snapshot.data!;
                final reconciliation = reconcileOperationalViewer(summary);
                return Column(
                  children: [
                    if (!reconciliation.valid)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                        child: GlassPanel(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_outlined,
                                color: BrandColors.accentOrange,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'El conteo operativo no coincide. '
                                  'Dashboard: ${reconciliation.dashboardOpen}; '
                                  'Visor: ${reconciliation.viewerTotal}.',
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _refresh,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Actualizar'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    TabBar(
                      isScrollable: true,
                      tabs: [
                        const Tab(text: 'Usuarios activos'),
                        Tab(text: 'Mesas (${summary.openTableCount})'),
                        const Tab(text: 'Cocina en vivo'),
                        Tab(text: 'Para llevar (${summary.openTakeoutCount})'),
                        Tab(
                          text:
                              'Parados sin mesa (${summary.openStandingCount})',
                        ),
                        const Tab(text: 'Intervenciones recientes'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _UsersLiveTab(
                            repository: _repository,
                            search: _searchController.text,
                            screenFilter: _screenFilter,
                            statusFilter: _statusFilter,
                            canControl: _canControl,
                            onOpenOrder: _openOrderDetail,
                          ),
                          _TablesLiveTab(
                            summary: summary,
                            canControl: _canControl,
                            onOpenOrder: _openOrderDetail,
                          ),
                          _KitchenLiveTab(
                            repository: _repository,
                            canControl: _canControl,
                            onOpenOrder: _openOrderDetail,
                          ),
                          _TakeoutLiveTab(
                            summary: summary,
                            canControl: _canControl,
                            onOpenOrder: _openOrderDetail,
                          ),
                          _StandingLiveTab(
                            summary: summary,
                            canControl: _canControl,
                            onOpenOrder: _openOrderDetail,
                          ),
                          _ActivityLiveTab(
                            repository: _repository,
                            onOpenOrder: _openOrderDetail,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openOrderDetail(String orderId) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _LiveOrderDialog(
        repository: _repository,
        orderId: orderId,
        canControl: _canControl,
      ),
    );
    if (mounted) _refresh();
  }

  void _refresh() {
    _repository.invalidateReportDataCache(branchId: _branchId);
    setState(() {
      _refreshing = true;
      _operationalSummary = _repository.watchOperationalOpenOrdersSummary();
    });
  }

  void _finishRefresh() {
    if (!_refreshing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _refreshing) setState(() => _refreshing = false);
    });
  }

  Future<void> _cleanupInactiveSessions() async {
    try {
      final count = await _repository.cleanupInactiveActiveSessions();
      if (!mounted) return;
      showAppSnackBar(
        context,
        '$count sesiones inactivas archivadas.',
        type: AppSnackBarType.success,
      );
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, '$error', type: AppSnackBarType.error);
    }
  }
}

class _UsersLiveTab extends StatelessWidget {
  const _UsersLiveTab({
    required this.repository,
    required this.search,
    required this.screenFilter,
    required this.statusFilter,
    required this.canControl,
    required this.onOpenOrder,
  });

  final TacoPosRepository repository;
  final String search;
  final String screenFilter;
  final String statusFilter;
  final bool canControl;
  final ValueChanged<String> onOpenOrder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ActiveSession>>(
      stream: repository.watchActiveSessions(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudo cargar sesiones',
            message: '${snapshot.error}',
          );
        }
        if (!snapshot.hasData) {
          return const LoadingPanel(message: 'Cargando sesiones...');
        }
        final query = search.toLowerCase().trim();
        final sessions = snapshot.data!.where((session) {
          if (!session.isVisibleInLiveViewer) {
            return false;
          }
          if (query.isNotEmpty &&
              !session.employeeName.toLowerCase().contains(query)) {
            return false;
          }
          if (screenFilter != 'Todos' &&
              _liveScreenLabel(session.currentScreen) != screenFilter) {
            return false;
          }
          if (statusFilter != 'Todos' &&
              session.connectionLabel != statusFilter) {
            return false;
          }
          return true;
        }).toList();
        if (sessions.isEmpty) {
          return const EmptyState(
            icon: Icons.people_outline,
            title: 'Sin usuarios activos',
            message: 'No hay usuarios activos en este momento.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(18),
          itemCount: sessions.length,
          itemBuilder: (context, index) {
            final session = sessions[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SessionCard(
                session: session,
                canControl: canControl,
                onOpenOrder: session.currentOrderId == null
                    ? null
                    : () => onOpenOrder(session.currentOrderId!),
              ),
            );
          },
        );
      },
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.canControl,
    required this.onOpenOrder,
  });

  final ActiveSession session;
  final bool canControl;
  final VoidCallback? onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final color = switch (session.connectionLabel) {
      'En linea' => BrandColors.success,
      'Inactivo' => BrandColors.accentYellow,
      _ => BrandColors.textMuted,
    };
    final screenLabel = _liveScreenLabel(session.currentScreen);
    final actionLabel = _liveActionLabel(session.currentAction);
    final appModeLabel = _liveAppModeLabel(session.appMode);
    return GlassCard(
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  session.employeeName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _Pill(label: session.connectionLabel, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(label: session.platform, color: BrandColors.info),
              _Pill(label: appModeLabel, color: BrandColors.accentYellow),
              _Pill(label: screenLabel, color: BrandColors.textMuted),
              _Pill(label: actionLabel, color: BrandColors.success),
              if ((session.currentTableName ?? '').isNotEmpty)
                _Pill(
                  label: 'Mesa ${session.currentTableName}',
                  color: BrandColors.accentOrange,
                ),
              if ((session.currentOrderId ?? '').isNotEmpty)
                _Pill(
                  label: 'Orden ${_shortId(session.currentOrderId!)}',
                  color: BrandColors.accentYellow,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Ultima actividad: ${_timeAgo(session.lastSeenAt)}',
            style: const TextStyle(color: BrandColors.textMuted),
          ),
          if (onOpenOrder != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onOpenOrder,
                icon: const Icon(Icons.visibility_outlined),
                label: Text(
                  canControl ? 'Ver e intervenir' : 'Ver lo que hace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TablesLiveTab extends StatelessWidget {
  const _TablesLiveTab({
    required this.summary,
    required this.canControl,
    required this.onOpenOrder,
  });

  final OperationalOpenOrdersSummary summary;
  final bool canControl;
  final ValueChanged<String> onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final blockers = summary.tableBlockers;
    return _OperationalOrdersSection(
      title: 'Mesas',
      counterLabel: blockers.length == 1
          ? '1 mesa ocupada'
          : '${blockers.length} mesas ocupadas',
      icon: Icons.table_restaurant_outlined,
      blockers: blockers,
      canControl: canControl,
      onOpenOrder: onOpenOrder,
    );
  }
}

class _KitchenLiveTab extends StatelessWidget {
  const _KitchenLiveTab({
    required this.repository,
    required this.canControl,
    required this.onOpenOrder,
  });

  final TacoPosRepository repository;
  final bool canControl;
  final ValueChanged<String> onOpenOrder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<KitchenOrderBundle>>(
      stream: repository.watchKitchenOrderBundles(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LoadingPanel(message: 'Cargando cocina...');
        }
        final bundles = snapshot.data!;
        if (bundles.isEmpty) {
          return const EmptyState(
            icon: Icons.restaurant_menu,
            title: 'Cocina sin comandas',
            message: 'No hay productos activos en cocina.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(18),
          itemCount: bundles.length,
          itemBuilder: (context, index) {
            final bundle = bundles[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _KitchenLiveCard(
                repository: repository,
                bundle: bundle,
                canControl: canControl,
                onOpenOrder: () => onOpenOrder(bundle.order.id),
              ),
            );
          },
        );
      },
    );
  }
}

class _KitchenLiveCard extends StatelessWidget {
  const _KitchenLiveCard({
    required this.repository,
    required this.bundle,
    required this.canControl,
    required this.onOpenOrder,
  });

  final TacoPosRepository repository;
  final KitchenOrderBundle bundle;
  final bool canControl;
  final VoidCallback onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final activeItems = bundle.items.where(isKitchenQueueItem).toList();
    final pendingIds = activeItems
        .where((item) => normalizeStatus(item.kitchenStatus) == 'sent')
        .map((item) => item.id)
        .toList();
    final cookingIds = activeItems
        .where(
          (item) =>
              isActiveKitchenItem(item) &&
              ['sent', 'cooking'].contains(normalizeStatus(item.kitchenStatus)),
        )
        .map((item) => item.id)
        .toList();
    return GlassCard(
      accent: _statusColor(bundle.order.kitchenStatus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  bundle.order.displayName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _Pill(
                label: formatKitchenStatus(bundle.order.kitchenStatus),
                color: _statusColor(bundle.order.kitchenStatus),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            bundle.shortSummary,
            style: const TextStyle(color: BrandColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onOpenOrder,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Ver comanda'),
              ),
              if (canControl)
                OutlinedButton.icon(
                  onPressed: pendingIds.isEmpty
                      ? null
                      : () async {
                          await repository.updateKitchenItemsStatus(
                            orderId: bundle.order.id,
                            itemIds: pendingIds,
                            status: 'cooking',
                          );
                          await repository.logBackofficeIntervention(
                            type: 'kitchen_mark_cooking',
                            orderId: bundle.order.id,
                            note: 'Marcado en preparacion desde visor.',
                          );
                        },
                  icon: const Icon(Icons.local_fire_department_outlined),
                  label: const Text('En preparacion'),
                ),
              if (canControl)
                FilledButton.icon(
                  onPressed: cookingIds.isEmpty
                      ? null
                      : () async {
                          await repository.updateKitchenItemsStatus(
                            orderId: bundle.order.id,
                            itemIds: cookingIds,
                            status: 'ready',
                          );
                          await repository.logBackofficeIntervention(
                            type: 'kitchen_mark_ready',
                            orderId: bundle.order.id,
                            note: 'Marcado listo desde visor.',
                          );
                        },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Listo'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TakeoutLiveTab extends StatelessWidget {
  const _TakeoutLiveTab({
    required this.summary,
    required this.canControl,
    required this.onOpenOrder,
  });

  final OperationalOpenOrdersSummary summary;
  final bool canControl;
  final ValueChanged<String> onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final blockers = summary.takeoutBlockers;
    return _OperationalOrdersSection(
      title: 'Para llevar',
      counterLabel: blockers.length == 1
          ? '1 pedido activo'
          : '${blockers.length} pedidos activos',
      icon: Icons.shopping_bag_outlined,
      blockers: blockers,
      canControl: canControl,
      onOpenOrder: onOpenOrder,
    );
  }
}

class _StandingLiveTab extends StatelessWidget {
  const _StandingLiveTab({
    required this.summary,
    required this.canControl,
    required this.onOpenOrder,
  });

  final OperationalOpenOrdersSummary summary;
  final bool canControl;
  final ValueChanged<String> onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final blockers = summary.standingBlockers;
    return _OperationalOrdersSection(
      title: 'Parados sin mesa',
      counterLabel: blockers.length == 1
          ? '1 orden activa'
          : '${blockers.length} órdenes activas',
      icon: Icons.accessibility_new,
      blockers: blockers,
      canControl: canControl,
      onOpenOrder: onOpenOrder,
    );
  }
}

class _OperationalOrdersSection extends StatelessWidget {
  const _OperationalOrdersSection({
    required this.title,
    required this.counterLabel,
    required this.icon,
    required this.blockers,
    required this.canControl,
    required this.onOpenOrder,
  });

  final String title;
  final String counterLabel;
  final IconData icon;
  final List<OperationalOrderBlocker> blockers;
  final bool canControl;
  final ValueChanged<String> onOpenOrder;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Expanded(
              child: SectionHeader(
                title: title,
                subtitle:
                    'Órdenes activas de la sucursal y fecha operativa vigentes.',
              ),
            ),
            _Pill(label: counterLabel, color: BrandColors.info),
          ],
        ),
        const SizedBox(height: 14),
        if (blockers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 42),
            child: Column(
              children: [
                Icon(icon, size: 40, color: BrandColors.textMuted),
                const SizedBox(height: 10),
                const Text(
                  'Sin pedidos activos',
                  style: TextStyle(
                    color: BrandColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          )
        else
          for (final blocker in blockers) ...[
            _OperationalOrderCard(
              blocker: blocker,
              canControl: canControl,
              onOpenOrder: () => onOpenOrder(blocker.order.id),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _OperationalOrderCard extends StatelessWidget {
  const _OperationalOrderCard({
    required this.blocker,
    required this.canControl,
    required this.onOpenOrder,
  });

  final OperationalOrderBlocker blocker;
  final bool canControl;
  final VoidCallback onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final order = blocker.order;
    final type = normalizeOrderType(order.orderType);
    final netTotal = order.netTotal ?? order.total;
    final title = switch (type) {
      'takeout' => 'Para llevar · ${order.customerDisplayName}',
      'standing' => 'Parados sin mesa · ${order.customerDisplayName}',
      _ => order.displayName,
    };
    final platform = type == 'standing'
        ? 'En persona'
        : (order.platformName?.trim().isNotEmpty == true
              ? order.platformName!.trim()
              : type == 'takeout'
              ? 'Sin plataforma'
              : '');
    final icon = switch (type) {
      'takeout' => Icons.shopping_bag_outlined,
      'standing' => Icons.accessibility_new,
      _ => Icons.table_restaurant_outlined,
    };
    final details = Wrap(
      spacing: 14,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (platform.isNotEmpty)
          _Pill(label: platform, color: BrandColors.info),
        Text('Folio ${order.takeoutNumber ?? _shortId(order.id)}'),
        Text(_dateTime(order.createdAt)),
        Text('Total neto ${_money(netTotal)}'),
        Text('Pagado ${_money(order.paidTotal)}'),
        Text('Pendiente ${_money(order.pendingTotal)}'),
        Text('${blocker.activeItemCount} items activos'),
        _Pill(
          label: formatKitchenStatus(order.kitchenStatus),
          color: _statusColor(order.kitchenStatus),
        ),
        _Pill(
          label: formatPaymentStatus(order.paymentStatus),
          color: _statusColor(order.paymentStatus),
        ),
      ],
    );
    return GlassCard(
      accent: _statusColor(order.kitchenStatus),
      onTap: onOpenOrder,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final heading = Row(
            children: [
              Icon(icon, color: BrandColors.info),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          );
          final action = OutlinedButton.icon(
            onPressed: onOpenOrder,
            icon: const Icon(Icons.open_in_new),
            label: Text(canControl ? 'Intervenir' : 'Ver detalle'),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: 12),
                details,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 250, child: heading),
              const SizedBox(width: 18),
              Expanded(child: details),
              const SizedBox(width: 12),
              action,
            ],
          );
        },
      ),
    );
  }
}

// ignore: unused_element
class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.repository});

  final TacoPosRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ActivityEvent>>(
      stream: repository.watchRecentActivityEvents(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LoadingPanel(message: 'Cargando intervenciones...');
        }
        final events = snapshot.data!
            .where((event) => event.actionSource == 'backoffice_live_viewer')
            .toList();
        if (events.isEmpty) {
          return const EmptyState(
            icon: Icons.history,
            title: 'Sin intervenciones recientes',
            message: 'Todavia no hay sesiones reportando actividad.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(18),
          itemCount: events.length,
          itemBuilder: (context, index) {
            final event = events[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                accent: BrandColors.info,
                child: ListTile(
                  title: Text(event.type),
                  subtitle: Text(
                    '${event.employeeName} · ${_timeAgo(event.createdAt)}'
                    '${event.orderId == null ? '' : ' · Orden ${_shortId(event.orderId!)}'}',
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ActivityLiveTab extends StatefulWidget {
  const _ActivityLiveTab({required this.repository, required this.onOpenOrder});

  final TacoPosRepository repository;
  final ValueChanged<String> onOpenOrder;

  @override
  State<_ActivityLiveTab> createState() => _ActivityLiveTabState();
}

class _ActivityLiveTabState extends State<_ActivityLiveTab> {
  String _filter = 'Todos';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ActivityEvent>>(
      stream: widget.repository.watchRecentActivityEvents(limit: 50),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LoadingPanel(message: 'Cargando intervenciones...');
        }
        final events =
            snapshot.data!.where((event) => _matchesFilter(event)).toList()
              ..sort((a, b) {
                final aDate = a.createdAt ?? DateTime(1970);
                final bDate = b.createdAt ?? DateTime(1970);
                return bDate.compareTo(aDate);
              });
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _ActivityFilters(value: _filter, onChanged: _setFilter),
            const SizedBox(height: 14),
            if (events.isEmpty)
              const EmptyState(
                icon: Icons.history,
                title: 'Sin intervenciones recientes',
                message: 'Todavia no hay actividad reciente para este filtro.',
              )
            else
              ...events.map(
                (event) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ActivityCard(
                    event: event,
                    onOpenOrder: event.orderId == null
                        ? null
                        : () => widget.onOpenOrder(event.orderId!),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _setFilter(String value) {
    setState(() => _filter = value);
  }

  bool _matchesFilter(ActivityEvent event) {
    return switch (_filter) {
      'Ordenes' => event.orderId != null || event.type.contains('order'),
      'Cocina' => event.type.contains('kitchen'),
      'Pagos' => event.type.contains('payment') || event.type.contains('pay'),
      'Cancelaciones' =>
        event.type.contains('cancel') || event.type.contains('removed'),
      'Backoffice' => event.actionSource == 'backoffice_live_viewer',
      _ => true,
    };
  }
}

class _ActivityFilters extends StatelessWidget {
  const _ActivityFilters({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const filters = [
      'Todos',
      'Ordenes',
      'Cocina',
      'Pagos',
      'Cancelaciones',
      'Backoffice',
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in filters)
          ChoiceChip(
            selected: value == filter,
            onSelected: (_) => onChanged(filter),
            label: Text(filter),
          ),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.event, required this.onOpenOrder});

  final ActivityEvent event;
  final VoidCallback? onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final color = _activityColor(event);
    final itemName = event.productName ?? event.itemName;
    final details = <String>[
      event.employeeName,
      _timeAgo(event.createdAt),
      if ((event.tableName ?? '').isNotEmpty) 'Mesa ${event.tableName}',
      if ((event.orderId ?? '').isNotEmpty) 'Orden ${_shortId(event.orderId!)}',
      if ((itemName ?? '').isNotEmpty) itemName!,
    ];
    final note = event.reason ?? event.note;
    return GlassCard(
      accent: color,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatInterventionAction(event.type),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _Pill(
                label: _formatActionSource(event.actionSource),
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            details.join(' - '),
            style: const TextStyle(color: BrandColors.textMuted),
          ),
          if ((note ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Motivo/nota: ${note!.trim()}',
              style: const TextStyle(color: BrandColors.textSecondary),
            ),
          ],
          if (formatInterventionAction(event.type) == 'Actividad registrada')
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                event.type,
                style: const TextStyle(
                  color: BrandColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
          if (onOpenOrder != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onOpenOrder,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Ver orden'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveOrderDialog extends StatelessWidget {
  const _LiveOrderDialog({
    required this.repository,
    required this.orderId,
    required this.canControl,
  });

  final TacoPosRepository repository;
  final String orderId;
  final bool canControl;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: SizedBox(
        width: 920,
        height: 720,
        child: GlassPanel(
          borderRadius: 18,
          child: StreamBuilder<PosOrder?>(
            stream: repository.watchOrder(orderId),
            builder: (context, orderSnapshot) {
              final order = orderSnapshot.data;
              if (order == null) {
                return const LoadingPanel(message: 'Cargando orden...');
              }
              return StreamBuilder<List<OrderItem>>(
                stream: repository.watchOrderItems(orderId),
                builder: (context, itemsSnapshot) {
                  final items = itemsSnapshot.data ?? const <OrderItem>[];
                  return StreamBuilder<List<Payment>>(
                    stream: repository.watchOrderPayments(orderId),
                    builder: (context, paymentsSnapshot) {
                      final payments =
                          paymentsSnapshot.data ?? const <Payment>[];
                      return _LiveOrderDetail(
                        repository: repository,
                        order: order,
                        items: items,
                        payments: payments,
                        canControl: canControl,
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LiveOrderDetail extends StatelessWidget {
  const _LiveOrderDetail({
    required this.repository,
    required this.order,
    required this.items,
    required this.payments,
    required this.canControl,
  });

  final TacoPosRepository repository;
  final PosOrder order;
  final List<OrderItem> items;
  final List<Payment> payments;
  final bool canControl;

  @override
  Widget build(BuildContext context) {
    final activePayments = payments
        .where((payment) => payment.isActive)
        .toList();
    final peopleCount = order.personNames.isEmpty
        ? 1
        : order.personNames.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SectionHeader(
                title: _liveOrderTitle(order),
                subtitle:
                    'Orden ${_shortId(order.id)} · ${formatKitchenStatus(order.kitchenStatus)} · ${formatPaymentStatus(order.paymentStatus)}',
              ),
            ),
            IconButton(
              tooltip: 'Cerrar',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Pill(
              label: 'Total ${_money(order.total)}',
              color: BrandColors.accentYellow,
            ),
            _Pill(
              label: 'Pagado ${_money(order.paidTotal)}',
              color: BrandColors.success,
            ),
            _Pill(
              label: 'Pendiente ${_money(order.pendingTotal)}',
              color: BrandColors.danger,
            ),
            if (order.createdAt != null)
              _Pill(
                label: 'Creada ${_dateTime(order.createdAt!)}',
                color: BrandColors.info,
              ),
            _Pill(
              label: peopleCount == 1 ? '1 persona' : '$peopleCount personas',
              color: BrandColors.info,
            ),
            if (isStandingOrder(order) || isTakeoutOrder(order))
              _Pill(
                label: isStandingOrder(order)
                    ? 'En persona'
                    : (order.platformName?.trim().isNotEmpty == true
                          ? order.platformName!.trim()
                          : 'Sin plataforma'),
                color: BrandColors.info,
              ),
            if (order.explicitDiscount > 0.01)
              _Pill(
                label: 'Descuento ${_money(order.explicitDiscount)}',
                color: BrandColors.accentOrange,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (canControl)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _addProduct(context),
                icon: const Icon(Icons.add),
                label: const Text('Agregar producto'),
              ),
              OutlinedButton.icon(
                onPressed: items.any((item) => item.kitchenStatus == 'pending')
                    ? () async {
                        await repository.sendOrderToKitchen(order.id);
                        await repository.logBackofficeIntervention(
                          type: 'send_to_kitchen',
                          orderId: order.id,
                          note: 'Pendientes enviados desde visor.',
                        );
                      }
                    : null,
                icon: const Icon(Icons.room_service_outlined),
                label: const Text('Enviar cocina'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PaymentScreen(orderId: order.id),
                    ),
                  );
                },
                icon: const Icon(Icons.point_of_sale_outlined),
                label: const Text('Abrir cobro'),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: _OrderItemsPanel(
                  repository: repository,
                  order: order,
                  items: items,
                  canControl: canControl,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PaymentsPanel(
                  repository: repository,
                  order: order,
                  payments: activePayments,
                  canControl: canControl,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addProduct(BuildContext context) async {
    final product = await showDialog<Product>(
      context: context,
      builder: (_) => _ProductPickDialog(repository: repository),
    );
    if (product == null) return;
    await repository.addProductToOrder(
      orderId: order.id,
      product: product,
      personNumber: 1,
    );
    await repository.logBackofficeIntervention(
      type: 'add_product',
      orderId: order.id,
      targetId: product.id,
      note: product.name,
    );
  }
}

class _OrderItemsPanel extends StatelessWidget {
  const _OrderItemsPanel({
    required this.repository,
    required this.order,
    required this.items,
    required this.canControl,
  });

  final TacoPosRepository repository;
  final PosOrder order;
  final List<OrderItem> items;
  final bool canControl;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long,
        title: 'Sin articulos',
        message: 'La orden no tiene productos cargados.',
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 18),
      itemBuilder: (context, index) {
        final item = items[index];
        final cancelled = item.isCancelled;
        final cancelReason = getItemCancelReason(item);
        return Row(
          children: [
            Expanded(
              child: Opacity(
                opacity: cancelled ? 0.55 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.qty} ${item.productName}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        decoration: cancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${item.personName} · ${formatKitchenStatus(item.kitchenStatus)} · ${formatPaymentStatus(item.paymentStatus)}',
                      style: const TextStyle(color: BrandColors.textMuted),
                    ),
                    if (cancelled) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: BrandColors.danger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: BrandColors.danger.withValues(
                                  alpha: 0.28,
                                ),
                              ),
                            ),
                            child: const Text(
                              'Cancelado',
                              style: TextStyle(
                                color: BrandColors.danger,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          if (cancelReason.isNotEmpty)
                            Text(
                              'Motivo: $cancelReason',
                              style: const TextStyle(
                                color: BrandColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            MoneyText(value: item.total),
            if (canControl)
              IconButton(
                tooltip: item.kitchenStatus == 'pending'
                    ? 'Cancelar item'
                    : 'Solicitar cancelacion',
                onPressed: cancelled || item.paymentStatus == 'paid'
                    ? null
                    : () => _cancelItem(context, item),
                icon: const Icon(Icons.cancel_outlined),
                color: BrandColors.danger,
              ),
          ],
        );
      },
    );
  }

  Future<void> _cancelItem(BuildContext context, OrderItem item) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(),
    );
    if (reason == null) return;
    if (item.kitchenStatus == 'pending' ||
        item.kitchenStatus == 'not_required') {
      await repository.cancelOrderItem(
        orderId: order.id,
        itemId: item.id,
        reason: reason,
      );
      await repository.logBackofficeIntervention(
        type: 'cancel_item',
        orderId: order.id,
        targetId: item.id,
        note: reason,
      );
    } else {
      await repository.requestOrderItemCancellation(
        orderId: order.id,
        itemId: item.id,
        reason: reason,
      );
      await repository.logBackofficeIntervention(
        type: 'request_item_cancellation',
        orderId: order.id,
        targetId: item.id,
        note: reason,
      );
    }
  }
}

class _PaymentsPanel extends StatelessWidget {
  const _PaymentsPanel({
    required this.repository,
    required this.order,
    required this.payments,
    required this.canControl,
  });

  final TacoPosRepository repository;
  final PosOrder order;
  final List<Payment> payments;
  final bool canControl;

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return const EmptyState(
        icon: Icons.payments_outlined,
        title: 'Sin pagos',
        message: 'Aun no hay pagos activos en esta orden.',
      );
    }
    return ListView.separated(
      itemCount: payments.length,
      separatorBuilder: (_, _) => const Divider(height: 18),
      itemBuilder: (context, index) {
        final payment = payments[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(formatPaymentMethod(payment.method)),
          subtitle: Text(_dateTime(payment.createdAt)),
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MoneyText(value: payment.chargedAmount),
              if (canControl)
                IconButton(
                  tooltip: 'Cancelar pago',
                  onPressed: () => _cancelPayment(context, payment),
                  icon: const Icon(Icons.cancel_outlined),
                  color: BrandColors.danger,
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _cancelPayment(BuildContext context, Payment payment) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(),
    );
    if (reason == null) return;
    await repository.cancelPayment(
      orderId: order.id,
      paymentId: payment.id,
      reason: reason,
    );
    await repository.logBackofficeIntervention(
      type: 'cancel_payment',
      orderId: order.id,
      targetId: payment.id,
      note: reason,
    );
  }
}

class _ProductPickDialog extends StatelessWidget {
  const _ProductPickDialog({required this.repository});

  final TacoPosRepository repository;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar producto'),
      content: SizedBox(
        width: 420,
        height: 520,
        child: StreamBuilder<List<Product>>(
          stream: repository.watchProducts(activeOnly: true),
          builder: (context, snapshot) {
            final products = snapshot.data ?? const <Product>[];
            if (!snapshot.hasData) {
              return const LoadingPanel(message: 'Cargando productos...');
            }
            return ListView.builder(
              itemCount: products.length,
              itemBuilder: (context, index) {
                final product = products[index];
                return ListTile(
                  title: Text(product.name),
                  subtitle: Text(product.category),
                  trailing: MoneyText(value: product.price),
                  onTap: () => Navigator.pop(context, product),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Motivo'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(labelText: 'Motivo obligatorio'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final reason = _controller.text.trim();
            if (reason.isEmpty) return;
            Navigator.pop(context, reason);
          },
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

class _LivePermissionBadge extends StatelessWidget {
  const _LivePermissionBadge({required this.canControl});

  final bool canControl;

  @override
  Widget build(BuildContext context) {
    return _Pill(
      label: canControl ? 'Control total habilitado' : 'Solo lectura',
      color: canControl ? BrandColors.success : BrandColors.textMuted,
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final value in values)
            DropdownMenuItem(value: value, child: Text(value)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

Color _statusColor(String status) {
  return switch (status) {
    'ready' => BrandColors.success,
    'cooking' => BrandColors.info,
    'sent' => BrandColors.accentYellow,
    'partial' => BrandColors.accentYellow,
    'paid' => BrandColors.success,
    'cancelled' => BrandColors.danger,
    _ => BrandColors.textMuted,
  };
}

Color _activityColor(ActivityEvent event) {
  final type = event.type.toLowerCase();
  if (type.contains('payment') || type.contains('pay')) {
    return BrandColors.success;
  }
  if (type.contains('cancel') || type.contains('removed')) {
    return BrandColors.danger;
  }
  if (type.contains('kitchen')) {
    return BrandColors.accentYellow;
  }
  if (event.actionSource == 'backoffice_live_viewer') {
    return BrandColors.info;
  }
  return BrandColors.textMuted;
}

String formatInterventionAction(String actionType) {
  return switch (actionType) {
    'kitchen_mark_ready' => 'Producto marcado como listo',
    'kitchen_mark_cooking' => 'Producto marcado en preparacion',
    'kitchen_start_order' => 'Cocina inicio comanda',
    'item_cancel_requested' ||
    'request_item_cancellation' => 'Solicitud de cancelacion de producto',
    'item_cancel_accepted' => 'Cancelacion de producto aceptada',
    'item_cancel_rejected' => 'Cancelacion de producto rechazada',
    'order_cancelled' => 'Orden cancelada',
    'payment_created' ||
    'full_table' ||
    'person' ||
    'partial' ||
    'platform' => 'Pago registrado',
    'payment_cancelled' || 'cancel_payment' => 'Pago cancelado',
    'order_sent_to_kitchen' || 'send_to_kitchen' => 'Orden enviada a cocina',
    'product_added' || 'add_product' => 'Producto agregado',
    'product_removed' ||
    'cancel_item' ||
    'order_item_cancelled' => 'Producto cancelado',
    'backoffice_live_viewer' => 'Intervencion desde backoffice',
    _ => 'Actividad registrada',
  };
}

String _formatActionSource(String source) {
  return switch (source) {
    'backoffice_live_viewer' => 'Backoffice',
    'kitchen' => 'Cocina',
    'cash' => 'Caja',
    'tablet' || 'waiter' || 'app' => 'Tablet',
    _ => source.trim().isEmpty ? 'Sistema' : source,
  };
}

String _timeAgo(DateTime? date) {
  if (date == null) return 'sin registro';
  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 60) return 'hace ${diff.inSeconds}s';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  return 'hace ${diff.inHours} h';
}

String _dateTime(DateTime? date) {
  if (date == null) return '-';
  return DateFormat('dd/MM HH:mm').format(date);
}

String _liveOrderTitle(PosOrder order) {
  if (isStandingOrder(order)) {
    return 'Parados sin mesa · ${order.customerDisplayName}';
  }
  if (isTakeoutOrder(order)) {
    return 'Para llevar · ${order.customerDisplayName}';
  }
  return order.displayName;
}

String _shortId(String value) {
  return value.length <= 6 ? value : value.substring(0, 6);
}

String _liveScreenLabel(String value) {
  final normalized = _normalizeLiveLabel(value);
  if (normalized == 'home' ||
      normalized == 'inicio' ||
      normalized == 'main_menu' ||
      normalized == 'menu_principal') {
    return 'Inicio';
  }
  if (normalized == 'control_cocina' ||
      normalized == 'control_de_cocina' ||
      normalized == 'kitchen_control' ||
      normalized == 'kitchencontrolscreen') {
    return 'Control de cocina';
  }
  return value;
}

String _liveActionLabel(String value) {
  final normalized = _normalizeLiveLabel(value);
  if (normalized == 'main_menu' ||
      normalized == 'menu_principal' ||
      normalized == 'seleccionando_modulo') {
    return 'En menú principal';
  }
  if (normalized == 'controlando_cocina') {
    return 'Administrando cocina';
  }
  return value;
}

String _liveAppModeLabel(String value) {
  return switch (_normalizeLiveLabel(value)) {
    'home' => 'Inicio',
    'waiter' => 'Mesero',
    'cash' => 'Caja',
    'kitchen' => 'Cocina',
    'kitchen_control' ||
    'control_cocina' ||
    'kitchencontrol' => 'Control de cocina',
    'admin' => 'Backoffice',
    _ => value,
  };
}

String _normalizeLiveLabel(String value) {
  return value
      .toLowerCase()
      .trim()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll(' ', '_');
}

String _money(double value) {
  return '\$${value.toStringAsFixed(2)}';
}
