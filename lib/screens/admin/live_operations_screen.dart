import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/active_session.dart';
import '../../models/activity_event.dart';
import '../../models/employee.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';
import '../../models/pos_table.dart';
import '../../models/product.dart';
import '../../services/taco_pos_repository.dart';
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

  bool get _canControl => widget.employee.canControlLiveOperations;
  bool get _canView =>
      widget.employee.canViewLiveOperations || widget.employee.canViewAdmin;

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

    return DefaultTabController(
      length: 5,
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
                        tooltip: 'Refrescar',
                        onPressed: () => setState(() {}),
                        icon: const Icon(Icons.refresh),
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
                          'Mesas',
                          'Orden',
                          'Cobro',
                          'Cocina',
                          'Cocina detalle',
                          'Caja',
                          'Control cocina',
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
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Usuarios activos'),
              Tab(text: 'Mesas en vivo'),
              Tab(text: 'Cocina en vivo'),
              Tab(text: 'Para llevar'),
              Tab(text: 'Intervenciones recientes'),
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
                  repository: _repository,
                  canControl: _canControl,
                  onOpenOrder: _openOrderDetail,
                ),
                _KitchenLiveTab(
                  repository: _repository,
                  canControl: _canControl,
                  onOpenOrder: _openOrderDetail,
                ),
                _TakeoutLiveTab(
                  repository: _repository,
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
  }

  Future<void> _cleanupInactiveSessions() async {
    try {
      final count = await _repository.cleanupInactiveActiveSessions();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count sesiones inactivas archivadas.')),
      );
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
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
              session.currentScreen != screenFilter) {
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
              _Pill(label: session.appMode, color: BrandColors.accentYellow),
              _Pill(label: session.currentScreen, color: BrandColors.textMuted),
              _Pill(label: session.currentAction, color: BrandColors.success),
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
    required this.repository,
    required this.canControl,
    required this.onOpenOrder,
  });

  final TacoPosRepository repository;
  final bool canControl;
  final ValueChanged<String> onOpenOrder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PosTable>>(
      stream: repository.watchTables(),
      builder: (context, tablesSnapshot) {
        if (!tablesSnapshot.hasData) {
          return const LoadingPanel(message: 'Cargando mesas...');
        }
        return StreamBuilder<List<PosOrder>>(
          stream: repository.watchOpenOrders(),
          builder: (context, ordersSnapshot) {
            final orders = ordersSnapshot.data ?? const <PosOrder>[];
            final orderByTable = <String, PosOrder>{};
            for (final order in orders) {
              if (order.tableId.trim().isEmpty) continue;
              orderByTable.putIfAbsent(order.tableId, () => order);
            }
            final tables = tablesSnapshot.data!;
            return GridView.builder(
              padding: const EdgeInsets.all(18),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280,
                childAspectRatio: 1.55,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: tables.length,
              itemBuilder: (context, index) {
                final table = tables[index];
                final order = orderByTable[table.id];
                return _LiveTableCard(
                  table: table,
                  order: order,
                  canControl: canControl,
                  onOpenOrder: order == null
                      ? null
                      : () => onOpenOrder(order.id),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _LiveTableCard extends StatelessWidget {
  const _LiveTableCard({
    required this.table,
    required this.order,
    required this.canControl,
    required this.onOpenOrder,
  });

  final PosTable table;
  final PosOrder? order;
  final bool canControl;
  final VoidCallback? onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final currentOrder = order;
    final color = currentOrder == null
        ? BrandColors.success
        : _statusColor(currentOrder.kitchenStatus);
    return GlassCard(
      accent: color,
      onTap: onOpenOrder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            table.name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          _Pill(
            label: currentOrder == null
                ? 'Disponible'
                : '${formatKitchenStatus(currentOrder.kitchenStatus)} · ${formatPaymentStatus(currentOrder.paymentStatus)}',
            color: color,
          ),
          const Spacer(),
          if (currentOrder == null)
            const Text(
              'Sin orden activa',
              style: TextStyle(color: BrandColors.textMuted),
            )
          else ...[
            MoneyText(
              value: currentOrder.total,
              style: const TextStyle(
                color: BrandColors.accentYellow,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              canControl ? 'Click para intervenir' : 'Click para ver detalle',
              style: const TextStyle(color: BrandColors.textMuted),
            ),
          ],
        ],
      ),
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
    final activeItems = bundle.items
        .where((item) => !item.isCancelled)
        .toList();
    final pendingIds = activeItems
        .where((item) => item.kitchenStatus == 'sent')
        .map((item) => item.id)
        .toList();
    final cookingIds = activeItems
        .where((item) => ['sent', 'cooking'].contains(item.kitchenStatus))
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
    required this.repository,
    required this.canControl,
    required this.onOpenOrder,
  });

  final TacoPosRepository repository;
  final bool canControl;
  final ValueChanged<String> onOpenOrder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PosOrder>>(
      stream: repository.watchOpenTakeoutOrders(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LoadingPanel(message: 'Cargando para llevar...');
        }
        final orders = snapshot.data!;
        if (orders.isEmpty) {
          return const EmptyState(
            icon: Icons.shopping_bag_outlined,
            title: 'Sin pedidos para llevar',
            message: 'No hay pedidos para llevar activos.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(18),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                accent: _statusColor(order.kitchenStatus),
                onTap: () => onOpenOrder(order.id),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.displayName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${formatKitchenStatus(order.kitchenStatus)} · ${formatPaymentStatus(order.paymentStatus)}',
                            style: const TextStyle(
                              color: BrandColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    MoneyText(value: order.total),
                  ],
                ),
              ),
            );
          },
        );
      },
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SectionHeader(
                title: order.displayName,
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

String _shortId(String value) {
  return value.length <= 6 ? value : value.substring(0, 6);
}

String _money(double value) {
  return '\$${value.toStringAsFixed(2)}';
}
