import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../models/order.dart';
import '../../models/pos_table.dart';
import '../../services/app_session.dart';
import '../../services/live_presence_service.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/status_badge.dart';
import 'order_screen.dart';
import 'takeout_orders_screen.dart';

class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  final _repository = TacoPosRepository();
  final _scrollController = ScrollController(keepScrollOffset: false);
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    LivePresenceService.instance.update(
      appMode: 'waiter',
      currentScreen: 'Mesas',
      currentAction: 'Viendo mesas',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTop());
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
    final employee = AppSession.instance.employee;
    final canTakeOrders = employee?.canTakeOrders == true;
    final canCharge = employee?.canCharge == true;
    if (!canTakeOrders && !canCharge) {
      _showMessage('No tienes permiso para levantar pedidos');
      return;
    }

    if (table.type == 'takeout' || table.type == 'takeout_entry') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TakeoutOrdersScreen()),
      );
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
      final order = await _repository.createOrGetOpenOrder(table);
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTop());
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir la mesa: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
        stream: _repository.watchTables(),
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
            return const EmptyState(
              icon: Icons.table_restaurant,
              title: 'Aun no hay mesas',
              message: 'Configura mesas activas en Firestore.',
            );
          }

          return StreamBuilder<List<PosOrder>>(
            stream: _repository.watchOpenTakeoutOrders(),
            initialData: const [],
            builder: (context, takeoutSnapshot) {
              if (takeoutSnapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudieron cargar pedidos para llevar',
                  message: '${takeoutSnapshot.error}',
                );
              }

              final takeoutCount = takeoutSnapshot.data?.length ?? 0;
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
                            itemCount: tables.length,
                            itemBuilder: (context, index) {
                              final table = tables[index];
                              return _TableCard(
                                table: table,
                                takeoutCount: takeoutCount,
                                compact: compact,
                                onTap: () => _openTable(table),
                              );
                            },
                          ),
                        ),
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

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.takeoutCount,
    required this.compact,
    required this.onTap,
  });

  final PosTable table;
  final int takeoutCount;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isTakeout = table.type == 'takeout' || table.type == 'takeout_entry';
    final status = tableStatusStyle(isTakeout ? 'available' : table.status);
    final hasOrder =
        !isTakeout &&
        (table.currentOrderId != null || table.status != 'available');
    final takeoutActive = isTakeout && takeoutCount > 0;
    final accent = takeoutActive ? BrandColors.accentOrange : status.color;

    return GlassCard(
      onTap: onTap,
      accent: accent,
      selected: hasOrder || takeoutActive,
      padding: EdgeInsets.all(compact ? 8 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  table.name,
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
                      : hasOrder
                      ? 'Orden abierta'
                      : 'Lista para tomar orden',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: BrandColors.textMuted,
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
