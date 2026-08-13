import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../core/visits/visit_classification.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/pos_table.dart';
import '../../services/app_session.dart';
import '../../services/live_presence_service.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/visit_survey_dialog.dart';
import 'order_screen.dart';
import 'takeout_orders_screen.dart';

const IconData takeoutEntryIcon = Icons.two_wheeler;

class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  final _repository = TacoPosRepository();
  final _scrollController = ScrollController(keepScrollOffset: false);
  late Future<GhostOrderReconciliationResult> _reconciliation;
  late Stream<List<PosTable>> _tables;
  bool _opening = false;
  bool _selectingTables = false;
  final Set<String> _selectedTableIds = {};

  @override
  void initState() {
    super.initState();
    _reconciliation = _repository.reconcileGhostOrdersAndTableLinks(
      branchId: AppSession.instance.currentBranchId,
      triggeredBy: 'waiter_tables',
    );
    _tables = _watchTablesAfterReconciliation();
    _markViewingTables();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTop());
  }

  Stream<List<PosTable>> _watchTablesAfterReconciliation() async* {
    await _reconciliation;
    yield* _repository.watchTables();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.jumpTo(0);
  }

  Future<void> _openTable(PosTable table) async {
    if (_selectingTables) {
      if (!table.isPhysicalTable) return;
      setState(() {
        if (!_selectedTableIds.remove(table.id)) {
          _selectedTableIds.add(table.id);
        }
      });
      return;
    }
    final employee = AppSession.instance.employee;
    final canTakeOrders = employee?.canTakeOrders == true;
    final canCharge = employee?.canCharge == true;
    if (!canTakeOrders && !canCharge) {
      _showMessage('No tienes permiso para levantar pedidos');
      return;
    }

    if (isTakeoutEntryTableType(table.type)) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TakeoutOrdersScreen()),
      );
      _markViewingTables();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTop());
      return;
    }

    final hasOpenOrder =
        table.currentOrderId != null || table.status != 'available';
    if (!canTakeOrders && !hasOpenOrder) {
      _showMessage('No tienes permiso para levantar pedidos');
      return;
    }

    if (_opening) {
      return;
    }

    setState(() {
      _opening = true;
    });

    try {
      VisitSurveyAnswer? visitAnswer;
      if (orderNeedsVisitSurvey(
        isNewOrder: !hasOpenOrder,
        visitClassification: null,
        isFirstVisit: null,
      )) {
        visitAnswer = await showVisitSurveyDialog(context);
        if (visitAnswer == null) {
          return;
        }
      }

      final order = await _repository.createOrGetOpenOrder(
        table,
        visitClassification: visitAnswer?.firestoreValue,
        isFirstVisit: visitAnswer?.isFirstVisit,
        visitSurveyAnsweredBy: employee?.id,
      );
      debugPrint(
        '[TacoPOS][TablesScreen.open] tableId=${table.id} '
        'tableName=${table.name} orderId=${order.id} total=${order.total}',
      );

      if (!mounted) {
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderScreen(
            orderId: order.id,
            tableId: table.id,
            tableName: table.name,
          ),
        ),
      );
      _markViewingTables();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTop());
    } catch (error) {
      if (!mounted) {
        return;
      }

      showAppSnackBar(
        context,
        'No se pudo abrir la mesa: $error',
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
        });
      }
    }
  }

  Future<void> _joinSelectedTables(List<PosTable> tables) async {
    final selected = tables
        .where((table) => _selectedTableIds.contains(table.id))
        .toList();
    final decision = evaluateTableJoinSelection(selected);
    if (!decision.allowed) {
      _showMessage(decision.message);
      return;
    }
    setState(() => _opening = true);
    try {
      final order = await _repository.joinTables(selected);
      if (!mounted) return;
      setState(() {
        _selectingTables = false;
        _selectedTableIds.clear();
      });
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderScreen(
            orderId: order.id,
            tableId: order.tableId,
            tableName: order.displayName,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        showAppSnackBar(context, '$error', type: AppSnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _toggleTableSelectionMode() {
    setState(() {
      _selectingTables = !_selectingTables;
      _selectedTableIds.clear();
    });
  }

  Future<void> _changeTableFromBoard({
    required List<PosTable> tables,
    required List<PosOrder> orders,
  }) async {
    if (_opening) return;
    final origin = await showDialog<_TableMoveOrigin>(
      context: context,
      builder: (context) => _ChangeTableOriginDialog(
        origins: _tableMoveOrigins(tables: tables, orders: orders),
      ),
    );
    if (!mounted || origin == null) return;

    final destination = await showDialog<PosTable>(
      context: context,
      builder: (context) =>
          _ChangeTableDestinationDialog(order: origin.order, tables: tables),
    );
    if (!mounted || destination == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar mesa'),
        content: Text(
          'Mover ${origin.label} a ${destination.name}? '
          'La orden, folio, productos, cocina y pagos se conservaran.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Cambiar mesa'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _opening = true);
    try {
      final moved = await _repository.changeOrderTable(
        orderId: origin.order.id,
        destinationTableId: destination.id,
      );
      if (!mounted) return;
      LivePresenceService.instance.update(
        currentTableId: moved.tableId,
        currentTableName: moved.displayName,
        currentOrderId: moved.id,
        currentAction: 'Orden cambiada de mesa',
      );
      showAppSnackBar(
        context,
        'Orden movida a ${moved.displayName}.',
        type: AppSnackBarType.success,
      );
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'No se pudo cambiar la mesa: $error',
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  List<_TableMoveOrigin> _tableMoveOrigins({
    required List<PosTable> tables,
    required List<PosOrder> orders,
  }) {
    final ordersById = {for (final order in orders) order.id: order};
    final seenOrderIds = <String>{};
    final origins = <_TableMoveOrigin>[];
    for (final table in tables.where((table) => table.isPhysicalTable)) {
      final orderId = table.currentOrderId?.trim() ?? '';
      if (orderId.isEmpty || !seenOrderIds.add(orderId)) continue;
      final order = ordersById[orderId];
      if (order == null || !isActiveOrderState(order)) continue;
      if (!isDineInOrder(order) && !isStandingOrder(order)) continue;
      origins.add(
        _TableMoveOrigin(
          order: order,
          label: order.displayName,
          subtitle: table.tableGroupLabel ?? table.name,
        ),
      );
    }

    final standing =
        orders
            .where(
              (order) => isStandingOrder(order) && isActiveOrderState(order),
            )
            .toList()
          ..sort((a, b) {
            final dateCompare =
                (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                    .compareTo(
                      b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                    );
            if (dateCompare != 0) return dateCompare;
            return a.id.compareTo(b.id);
          });
    for (final order in standing) {
      if (!seenOrderIds.add(order.id)) continue;
      origins.add(
        _TableMoveOrigin(
          order: order,
          label: order.displayName,
          subtitle: 'Parados sin mesa',
        ),
      );
    }
    return origins;
  }

  Future<void> _manageTableGroup(
    PosOrder order,
    List<PosTable> groupTables,
  ) async {
    final primaryId = order.primaryTableId ?? order.tableId;
    final removable = groupTables
        .where((table) => table.id != primaryId)
        .toList();
    if (removable.isEmpty) return;
    final table = await showDialog<PosTable>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Administrar mesas'),
        children: removable
            .map(
              (table) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, table),
                child: ListTile(
                  leading: const Icon(Icons.remove_circle_outline),
                  title: Text('Quitar ${table.name}'),
                  subtitle: const Text('La mesa quedará disponible'),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (!mounted || table == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Quitar ${table.name}'),
        content: const Text(
          'La orden, sus productos, personas y pagos permanecerán intactos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Quitar mesa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repository.removeTableFromGroup(
        orderId: order.id,
        tableId: table.id,
      );
    } catch (error) {
      if (mounted) {
        showAppSnackBar(context, '$error', type: AppSnackBarType.error);
      }
    }
  }

  void _showMessage(String message) {
    showAppSnackBar(context, message);
  }

  void _markViewingTables() {
    LivePresenceService.instance.updateCurrentScreen(
      appMode: 'waiter',
      currentScreen: 'Mesas',
      currentAction: 'Viendo mesas',
      force: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final employee = AppSession.instance.employee;
    if (employee?.canTakeOrders != true && employee?.canCharge != true) {
      return const BrandedScaffold(
        title: 'Mesas',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para levantar pedidos ni cobrar.',
        ),
      );
    }

    return BrandedScaffold(
      title: 'Mesas',
      actions: [
        if (_opening)
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
      body: StreamBuilder<List<PosTable>>(
        stream: _tables,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudieron cargar las mesas',
              message: '${snapshot.error}',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Cargando mesas...');
          }

          final tables = snapshot.data ?? [];
          if (tables.isEmpty) {
            return _NoTablesForBranch(
              canManageTables: employee?.canManageTables == true,
            );
          }

          return StreamBuilder<List<PosOrder>>(
            stream: _repository.watchOpenOrders(),
            initialData: const [],
            builder: (context, ordersSnapshot) {
              if (ordersSnapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudieron cargar las órdenes',
                  message: '${ordersSnapshot.error}',
                );
              }

              final orders = ordersSnapshot.data ?? const <PosOrder>[];
              final takeoutCount = orders
                  .where((order) => order.orderType == takeoutOrderType)
                  .length;
              final standingCount = orders
                  .where((order) => order.orderType == standingOrderType)
                  .length;
              final ordersById = {for (final order in orders) order.id: order};
              final physicalTables = tables
                  .where((table) => table.isPhysicalTable)
                  .toList();
              final visibleTables = <PosTable>[];
              final seenGroupOrders = <String>{};
              for (final table in tables) {
                final orderId = table.currentOrderId?.trim() ?? '';
                final grouped =
                    !_selectingTables &&
                    table.isPhysicalTable &&
                    orderId.isNotEmpty &&
                    physicalTables
                            .where(
                              (candidate) =>
                                  candidate.currentOrderId?.trim() == orderId,
                            )
                            .length >
                        1;
                if (grouped && !seenGroupOrders.add(orderId)) continue;
                visibleTables.add(table);
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final height = constraints.maxHeight;
                  final compact = width < 650 || height < 750;
                  final veryNarrow = width < 330;
                  final medium = width < 950;
                  final padding = compact
                      ? 8.0
                      : medium
                      ? 16.0
                      : 22.0;
                  final gap = compact ? 8.0 : 16.0;

                  return Padding(
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!compact) ...[
                          SectionHeader(
                            title: 'Mesas',
                            subtitle:
                                '${tables.length} puntos de servicio activos',
                          ),
                          const SizedBox(height: 18),
                        ],
                        Expanded(
                          child: GridView.builder(
                            controller: _scrollController,
                            gridDelegate: compact
                                ? SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: veryNarrow ? 1 : 2,
                                    mainAxisExtent: veryNarrow ? 88 : 104,
                                    crossAxisSpacing: gap,
                                    mainAxisSpacing: gap,
                                  )
                                : SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: medium ? 340 : 360,
                                    mainAxisExtent: medium ? 158 : 178,
                                    crossAxisSpacing: gap,
                                    mainAxisSpacing: gap,
                                  ),
                            itemCount: visibleTables.length + 1,
                            itemBuilder: (context, index) {
                              if (index == visibleTables.length) {
                                return _StandingEntryCard(
                                  activeCount: standingCount,
                                  compact: compact,
                                  onTap: _selectingTables
                                      ? null
                                      : () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const StandingOrdersScreen(),
                                          ),
                                        ),
                                );
                              }
                              final table = visibleTables[index];
                              final orderId =
                                  table.currentOrderId?.trim() ?? '';
                              final groupTables = orderId.isEmpty
                                  ? <PosTable>[table]
                                  : physicalTables
                                        .where(
                                          (candidate) =>
                                              candidate.currentOrderId
                                                  ?.trim() ==
                                              orderId,
                                        )
                                        .toList();
                              final order = ordersById[orderId];
                              return StreamBuilder<List<OrderItem>>(
                                stream: order == null
                                    ? null
                                    : _repository.watchOrderItems(order.id),
                                initialData: const [],
                                builder: (context, itemsSnapshot) {
                                  return _TableCard(
                                    table: table,
                                    takeoutCount: takeoutCount,
                                    compact: compact,
                                    order: order,
                                    orderItems:
                                        itemsSnapshot.data ??
                                        const <OrderItem>[],
                                    groupTables: groupTables,
                                    selecting: _selectingTables,
                                    selected: _selectedTableIds.contains(
                                      table.id,
                                    ),
                                    onTap: () => _openTable(table),
                                    onManageGroup:
                                        order?.isTableGroup == true &&
                                            !_selectingTables
                                        ? () => _manageTableGroup(
                                            order!,
                                            groupTables,
                                          )
                                        : null,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        if (employee?.canTakeOrders == true &&
                            physicalTables.length >= 2) ...[
                          const SizedBox(height: 8),
                          if (_selectingTables)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${_selectedTableIds.length} mesas seleccionadas',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _toggleTableSelectionMode,
                                  child: const Text('Cancelar'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  onPressed:
                                      _selectedTableIds.length >= 2 && !_opening
                                      ? () =>
                                            _joinSelectedTables(physicalTables)
                                      : null,
                                  icon: const Icon(Icons.merge),
                                  label: const Text('Juntar mesas'),
                                ),
                              ],
                            )
                          else
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: _toggleTableSelectionMode,
                                  icon: const Icon(Icons.table_restaurant),
                                  label: const Text('Juntar mesas'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: !_opening
                                      ? () => _changeTableFromBoard(
                                          tables: physicalTables,
                                          orders: orders,
                                        )
                                      : null,
                                  icon: const Icon(Icons.swap_horiz),
                                  label: const Text('Cambiar mesa'),
                                ),
                              ],
                            ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _NoTablesForBranch extends StatelessWidget {
  const _NoTablesForBranch({required this.canManageTables});

  final bool canManageTables;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassPanel(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.table_restaurant,
              size: 46,
              color: BrandColors.accentOrange,
            ),
            const SizedBox(height: 12),
            Text(
              'No hay mesas registradas para esta sucursal.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Sucursal: ${AppSession.instance.currentBranchName}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: BrandColors.textMuted),
            ),
            if (canManageTables) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Crear mesas desde Backoffice'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TableMoveOrigin {
  const _TableMoveOrigin({
    required this.order,
    required this.label,
    required this.subtitle,
  });

  final PosOrder order;
  final String label;
  final String subtitle;
}

class _ChangeTableOriginDialog extends StatelessWidget {
  const _ChangeTableOriginDialog({required this.origins});

  final List<_TableMoveOrigin> origins;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Origen'),
      children: [
        if (origins.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 18),
            child: Text('No hay ordenes activas para cambiar de mesa.'),
          )
        else
          ...origins.map(
            (origin) => SimpleDialogOption(
              onPressed: () => Navigator.pop(context, origin),
              child: ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(origin.label),
                subtitle: Text(origin.subtitle),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChangeTableDestinationDialog extends StatelessWidget {
  const _ChangeTableDestinationDialog({
    required this.order,
    required this.tables,
  });

  final PosOrder order;
  final List<PosTable> tables;

  @override
  Widget build(BuildContext context) {
    final available =
        tables
            .where(
              (table) => evaluateChangeTableDestination(
                order: order,
                destination: table,
              ).allowed,
            )
            .toList()
          ..sort((a, b) {
            final sortCompare = a.sortOrder.compareTo(b.sortOrder);
            if (sortCompare != 0) return sortCompare;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

    return SimpleDialog(
      title: const Text('Destino'),
      children: [
        if (available.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 18),
            child: Text('No hay mesas libres disponibles.'),
          )
        else
          ...available.map(
            (table) => SimpleDialogOption(
              onPressed: () => Navigator.pop(context, table),
              child: ListTile(
                leading: const Icon(Icons.table_restaurant_outlined),
                title: Text(table.name),
                subtitle: const Text('Disponible'),
              ),
            ),
          ),
      ],
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.takeoutCount,
    required this.compact,
    required this.order,
    required this.orderItems,
    required this.groupTables,
    required this.selecting,
    required this.selected,
    required this.onTap,
    this.onManageGroup,
  });

  final PosTable table;
  final int takeoutCount;
  final bool compact;
  final PosOrder? order;
  final List<OrderItem> orderItems;
  final List<PosTable> groupTables;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onManageGroup;

  @override
  Widget build(BuildContext context) {
    final isTakeout = isTakeoutEntryTableType(table.type);
    final derivedStatus = waiterTableStatusKey(
      table: table,
      order: order,
      items: orderItems,
    );
    final status = tableStatusStyle(isTakeout ? 'available' : derivedStatus);
    final hasOrder = !isTakeout && derivedStatus != 'available';
    final takeoutActive = isTakeout && takeoutCount > 0;
    final accent = isTakeout ? BrandColors.accentOrange : status.color;
    final elapsedMinutes = order?.createdAt == null
        ? null
        : DateTime.now().difference(order!.createdAt!).inMinutes.clamp(0, 9999);
    final groupDetail =
        '${groupTables.length} mesas · '
        '${order?.personNames.length ?? 1} personas · '
        '\$${order?.total.toStringAsFixed(2) ?? '0.00'}'
        '${elapsedMinutes == null ? '' : ' · ${elapsedMinutes}m'}';

    return GlassCard(
      onTap: onTap,
      accent: accent,
      selected: selected || hasOrder || takeoutActive,
      selectedAccent: isTakeout ? BrandColors.accentOrange : null,
      borderAccent: isTakeout
          ? BrandColors.accentOrange.withValues(alpha: 0.55)
          : null,
      padding: EdgeInsets.all(compact ? 8 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isTakeout) ...[
                const Icon(takeoutEntryIcon, color: BrandColors.accentOrange),
                SizedBox(width: compact ? 6 : 10),
              ],
              Expanded(
                child: Text(
                  order?.displayName ?? table.tableGroupLabel ?? table.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 17 : 26,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.textPrimary,
                  ),
                ),
              ),
              if (!isTakeout) StatusBadge(style: status),
              if (onManageGroup != null)
                IconButton(
                  tooltip: 'Administrar mesas',
                  onPressed: onManageGroup,
                  icon: const Icon(Icons.more_vert),
                ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Text(
                  isTakeout
                      ? takeoutCount == 0
                            ? 'Sin pedidos activos'
                            : takeoutCount == 1
                            ? '1 pedido activo'
                            : '$takeoutCount pedidos activos'
                      : selecting
                      ? selected
                            ? 'Seleccionada'
                            : 'Toca para seleccionar'
                      : hasOrder
                      ? groupTables.length > 1
                            ? groupDetail
                            : status.label
                      : 'Lista para tomar orden',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isTakeout
                        ? BrandColors.accentOrange
                        : BrandColors.textMuted,
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(width: compact ? 4 : 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: compact ? 12 : 14,
                color: BrandColors.textMuted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StandingEntryCard extends StatelessWidget {
  const _StandingEntryCard({
    required this.activeCount,
    required this.compact,
    required this.onTap,
  });

  final int activeCount;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      accent: BrandColors.info,
      selected: activeCount > 0,
      padding: EdgeInsets.all(compact ? 8 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Parados sin mesa',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              const Icon(Icons.accessibility_new, color: BrandColors.info),
            ],
          ),
          const Spacer(),
          Text(
            activeCount == 0
                ? 'Sin órdenes activas'
                : activeCount == 1
                ? '1 orden activa'
                : '$activeCount órdenes activas',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: BrandColors.textMuted),
          ),
        ],
      ),
    );
  }
}
