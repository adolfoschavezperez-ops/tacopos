import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../services/live_presence_service.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/formatters.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/status_badge.dart';

class KitchenOrderDetailScreen extends StatefulWidget {
  const KitchenOrderDetailScreen({
    super.key,
    required this.orderId,
    this.kitchenBatchId = '',
  });

  final String orderId;
  final String kitchenBatchId;

  @override
  State<KitchenOrderDetailScreen> createState() =>
      _KitchenOrderDetailScreenState();
}

class _KitchenOrderDetailScreenState extends State<KitchenOrderDetailScreen> {
  final _repository = TacoPosRepository();
  late final Stream<PosOrder?> _orderStream;
  late final Stream<List<OrderItem>> _itemsStream;
  late final Stream<List<KitchenOrderBundle>> _expressBundlesStream;
  int _personIndex = 0;
  bool _busy = false;
  bool _returningToList = false;

  @override
  void initState() {
    super.initState();
    _orderStream = _repository.watchOrder(widget.orderId);
    _itemsStream = _repository.watchKitchenItems(
      widget.orderId,
      kitchenBatchId: widget.kitchenBatchId,
    );
    _expressBundlesStream = _repository.watchKitchenOrderBundles().map((
      bundles,
    ) {
      final currentKey = _currentKitchenKey;
      return bundles
          .where(
            (bundle) =>
                bundle.isKitchenExpress &&
                bundle.stableKitchenKey != currentKey,
          )
          .toList();
    });
    LivePresenceService.instance.update(
      appMode: 'kitchen',
      currentScreen: 'Cocina detalle',
      currentOrderId: widget.orderId,
      currentKitchenBundleId: widget.orderId,
      currentAction: 'Surtiendo comanda',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repository.markActiveKitchenItemsCooking(
        widget.orderId,
        kitchenBatchId: widget.kitchenBatchId,
      );
    });
  }

  String get _currentKitchenKey {
    final batchId = widget.kitchenBatchId.trim();
    return batchId.isEmpty
        ? 'order:${widget.orderId}'
        : 'order:${widget.orderId}:$batchId';
  }

  Future<void> _markReady(List<OrderItem> activeItems) async {
    await _run(() {
      return _repository.updateKitchenItemsStatus(
        orderId: widget.orderId,
        itemIds: activeItems.map((item) => item.id),
        status: 'ready',
      );
    }, popAfter: true);
  }

  Future<void> _resolveCancellation(OrderItem item, bool accepted) async {
    await _run(() {
      return _repository.resolveKitchenCancellation(
        orderId: widget.orderId,
        itemId: item.id,
        accepted: accepted,
      );
    });
  }

  void _returnToKitchenList() {
    if (_returningToList || !mounted) {
      return;
    }
    _returningToList = true;
    showAppSnackBar(
      context,
      'Comanda sin articulos pendientes.',
      position: AppSnackBarPosition.top,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool popAfter = false,
  }) async {
    if (_busy) {
      return;
    }

    if (popAfter) {
      _returningToList = true;
    }
    setState(() {
      _busy = true;
    });

    try {
      await action();
      if (mounted && popAfter) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (popAfter) {
        _returningToList = false;
      }
      if (mounted) {
        showAppSnackBar(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
          type: AppSnackBarType.error,
          position: AppSnackBarPosition.top,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PremiumBackground(
        child: SafeArea(
          child: StreamBuilder<PosOrder?>(
            stream: _orderStream,
            builder: (context, orderSnapshot) {
              if (orderSnapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudo abrir la comanda',
                  message: '${orderSnapshot.error}',
                );
              }

              final order = orderSnapshot.data;
              if (orderSnapshot.connectionState == ConnectionState.waiting ||
                  order == null) {
                return const LoadingPanel(message: 'Abriendo comanda...');
              }

              return StreamBuilder<List<OrderItem>>(
                stream: _itemsStream,
                builder: (context, itemSnapshot) {
                  if (itemSnapshot.hasError) {
                    return EmptyState(
                      icon: Icons.error_outline,
                      title: 'No se pudieron cargar articulos de cocina',
                      message: '${itemSnapshot.error}',
                    );
                  }
                  if (itemSnapshot.connectionState == ConnectionState.waiting) {
                    return const LoadingPanel(
                      message: 'Cargando articulos de cocina...',
                    );
                  }

                  final items = itemSnapshot.data ?? [];
                  final grouped = <int, List<OrderItem>>{};
                  for (final item in items) {
                    grouped.putIfAbsent(item.personNumber, () => []).add(item);
                  }
                  final people = grouped.keys.toList()..sort();
                  if (_personIndex >= people.length) {
                    _personIndex = people.isEmpty ? 0 : people.length - 1;
                  }

                  if (people.isEmpty) {
                    _returnToKitchenList();
                    return _NoActiveKitchenItems(
                      onBack: () {
                        if (mounted) {
                          Navigator.pop(context);
                        }
                      },
                    );
                  }

                  final personNumber = people[_personIndex];
                  final personItems = grouped[personNumber] ?? [];
                  final personName = _personDisplayName(
                    personNumber,
                    personItems,
                  );
                  final isLastPerson = _personIndex >= people.length - 1;
                  final elapsedSince = _elapsedStart(items);
                  final plateAccent = _plateAccent(_personIndex);

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 700;
                      final medium = constraints.maxWidth < 950;
                      final padding = compact
                          ? 8.0
                          : medium
                          ? 12.0
                          : 16.0;
                      final gap = compact ? 6.0 : 10.0;

                      return Padding(
                        padding: EdgeInsets.all(padding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Header(
                              order: order,
                              compact: compact,
                              onClose: () => Navigator.pop(context),
                            ),
                            SizedBox(height: gap),
                            _ExpressAlertSlot(
                              stream: _expressBundlesStream,
                              busy: _busy,
                              onOpen: _openExpressBundle,
                            ),
                            SizedBox(height: gap),
                            Expanded(
                              child: GlassPanel(
                                blur: 8,
                                padding: EdgeInsets.all(compact ? 8 : 12),
                                fill: plateAccent.withValues(alpha: 0.13),
                                borderColor: plateAccent.withValues(
                                  alpha: 0.80,
                                ),
                                glowColor: plateAccent.withValues(alpha: 0.22),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _PlateHeader(
                                      personName: personName,
                                      current: _personIndex + 1,
                                      total: people.length,
                                      accent: plateAccent,
                                      compact: compact,
                                    ),
                                    SizedBox(height: compact ? 6 : 8),
                                    Container(
                                      height: compact ? 4 : 5,
                                      decoration: BoxDecoration(
                                        color: plateAccent,
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    ),
                                    SizedBox(height: compact ? 6 : 8),
                                    Expanded(
                                      child: ListView.separated(
                                        itemCount: personItems.length,
                                        separatorBuilder: (_, _) =>
                                            Divider(height: compact ? 6 : 8),
                                        itemBuilder: (context, index) {
                                          final item = personItems[index];
                                          return _KitchenItemRow(
                                            item: item,
                                            compact: compact,
                                            busy: _busy,
                                            onAcceptCancellation: () =>
                                                _resolveCancellation(
                                                  item,
                                                  true,
                                                ),
                                            onRejectCancellation: () =>
                                                _resolveCancellation(
                                                  item,
                                                  false,
                                                ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: gap),
                            _KitchenDetailActions(
                              compact: compact,
                              busy: _busy,
                              isLastPerson: isLastPerson,
                              showPrevious:
                                  people.length > 1 && _personIndex > 0,
                              elapsedSince: elapsedSince,
                              onPrevious: () {
                                setState(() {
                                  _personIndex -= 1;
                                });
                              },
                              onNext: () {
                                setState(() {
                                  _personIndex += 1;
                                });
                              },
                              accent: plateAccent,
                              onReady: () => _markReady(items),
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
        ),
      ),
    );
  }

  DateTime? _elapsedStart(List<OrderItem> items) {
    return items
        .map((item) => item.cookingAt ?? item.sentToKitchenAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (min, date) => min == null || date.isBefore(min) ? date : min,
        );
  }

  Future<void> _openExpressBundle(KitchenOrderBundle bundle) async {
    await showDialog<void>(
      context: context,
      useSafeArea: true,
      builder: (dialogContext) {
        return _ExpressOrderDialog(bundle: bundle, repository: _repository);
      },
    );
  }
}

class _ExpressAlertSlot extends StatelessWidget {
  const _ExpressAlertSlot({
    required this.stream,
    required this.busy,
    required this.onOpen,
  });

  final Stream<List<KitchenOrderBundle>> stream;
  final bool busy;
  final ValueChanged<KitchenOrderBundle> onOpen;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<KitchenOrderBundle>>(
      stream: stream,
      builder: (context, snapshot) {
        final bundles = snapshot.data ?? const [];
        if (bundles.isEmpty) return const SizedBox.shrink();
        final bundle = bundles.first;
        return _BlinkingExpressAlert(
          bundle: bundle,
          pendingCount: bundles.length - 1,
          enabled: !busy,
          onTap: () => onOpen(bundle),
        );
      },
    );
  }
}

class _BlinkingExpressAlert extends StatefulWidget {
  const _BlinkingExpressAlert({
    required this.bundle,
    required this.pendingCount,
    required this.enabled,
    required this.onTap,
  });

  final KitchenOrderBundle bundle;
  final int pendingCount;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_BlinkingExpressAlert> createState() => _BlinkingExpressAlertState();
}

class _BlinkingExpressAlertState extends State<_BlinkingExpressAlert>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.58,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bundle = widget.bundle;
    return FadeTransition(
      opacity: _pulse,
      child: InkWell(
        onTap: widget.enabled ? widget.onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: BrandColors.danger.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: BrandColors.danger.withValues(alpha: 0.70),
              width: 1.4,
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.priority_high_rounded,
                color: BrandColors.danger,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Surtido express',
                      style: TextStyle(
                        color: BrandColors.danger,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${bundle.order.displayName} · ${bundle.personLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      _expressSummary(bundle.items),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: BrandColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.pendingCount > 0)
                Text(
                  '+${widget.pendingCount} express pendientes',
                  style: const TextStyle(
                    color: BrandColors.accentYellow,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpressOrderDialog extends StatefulWidget {
  const _ExpressOrderDialog({required this.bundle, required this.repository});

  final KitchenOrderBundle bundle;
  final TacoPosRepository repository;

  @override
  State<_ExpressOrderDialog> createState() => _ExpressOrderDialogState();
}

class _ExpressOrderDialogState extends State<_ExpressOrderDialog> {
  bool _busy = false;

  Future<void> _markReady() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.updateKitchenItemsStatus(
        orderId: widget.bundle.order.id,
        itemIds: widget.bundle.items.map((item) => item.id),
        status: 'ready',
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
        type: AppSnackBarType.error,
        position: AppSnackBarPosition.top,
      );
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: PremiumBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  order: widget.bundle.order,
                  compact: true,
                  onClose: () => Navigator.pop(context),
                ),
                const SizedBox(height: 10),
                GlassPanel(
                  borderColor: BrandColors.danger.withValues(alpha: 0.70),
                  fill: BrandColors.danger.withValues(alpha: 0.12),
                  child: const Text(
                    'Surtido express',
                    style: TextStyle(
                      color: BrandColors.danger,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: GlassPanel(
                    padding: const EdgeInsets.all(12),
                    child: ListView.separated(
                      itemCount: widget.bundle.items.length,
                      separatorBuilder: (_, _) => const Divider(height: 12),
                      itemBuilder: (context, index) {
                        final item = widget.bundle.items[index];
                        return _KitchenItemRow(
                          item: item,
                          compact: true,
                          busy: _busy,
                          onAcceptCancellation: () {},
                          onRejectCancellation: () {},
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy ? null : _markReady,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(_busy ? 'Marcando...' : 'Listo'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _expressSummary(List<OrderItem> items) {
  final activeItems = items.where((item) => !item.isCancelled).toList();
  if (activeItems.length == 1) {
    final item = activeItems.first;
    return '${item.qty} ${formatOrderItemDisplayName(item, includeQuantity: false)}';
  }
  final pieces = activeItems.fold<int>(0, (sum, item) => sum + item.qty);
  return '${activeItems.length} productos · $pieces piezas';
}

class _PlateHeader extends StatelessWidget {
  const _PlateHeader({
    required this.personName,
    required this.current,
    required this.total,
    required this.accent,
    required this.compact,
  });

  final String personName;
  final int current;
  final int total;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 12,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: accent, width: compact ? 5 : 6),
          top: BorderSide(color: accent.withValues(alpha: 0.42)),
          right: BorderSide(color: accent.withValues(alpha: 0.42)),
          bottom: BorderSide(color: accent.withValues(alpha: 0.42)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 24 : 28,
            height: compact ? 24 : 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$current',
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 13 : 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(width: compact ? 8 : 10),
          Expanded(
            child: Text(
              'Plato $current de $total · $personName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w800,
                color: BrandColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _plateAccent(int index) {
  const colors = [
    Color(0xFFE56A2C),
    Color(0xFF2577D7),
    Color(0xFF178A5A),
    Color(0xFF7B4DD8),
    Color(0xFFB8324A),
    Color(0xFF008B8B),
  ];
  return colors[index % colors.length];
}

class _KitchenItemRow extends StatelessWidget {
  const _KitchenItemRow({
    required this.item,
    required this.compact,
    required this.busy,
    required this.onAcceptCancellation,
    required this.onRejectCancellation,
  });

  final OrderItem item;
  final bool compact;
  final bool busy;
  final VoidCallback onAcceptCancellation;
  final VoidCallback onRejectCancellation;

  @override
  Widget build(BuildContext context) {
    final cancelled = item.isCancelled;
    final textDecoration = cancelled ? TextDecoration.lineThrough : null;
    final titleColor = cancelled
        ? BrandColors.textMuted.withValues(alpha: 0.72)
        : BrandColors.textPrimary;
    final notes = item.notes.trim();
    final cancelReason = (item.cancelReason ?? '').trim();

    return Opacity(
      opacity: cancelled ? 0.58 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 30 : 36,
                height: compact ? 30 : 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cancelled
                      ? BrandColors.textMuted.withValues(alpha: 0.12)
                      : item.hasCancellationRequested
                      ? BrandColors.danger.withValues(alpha: 0.16)
                      : BrandColors.accentGlow,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  'x${item.qty}',
                  style: TextStyle(
                    fontSize: compact ? 13 : 15,
                    fontWeight: FontWeight.w900,
                    decoration: textDecoration,
                    color: cancelled
                        ? BrandColors.textMuted
                        : item.hasCancellationRequested
                        ? BrandColors.danger
                        : BrandColors.accentYellow,
                  ),
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            formatOrderItemDisplayName(
                              item,
                              includeQuantity: false,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: titleColor,
                              decoration: textDecoration,
                              decorationThickness: 2,
                              fontSize: compact ? 15 : 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        SizedBox(width: compact ? 6 : 8),
                        _CompactKitchenStatusChip(item: item),
                      ],
                    ),
                    if (notes.isNotEmpty && !cancelled) ...[
                      const SizedBox(height: 2),
                      Text(
                        notes,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: BrandColors.textMuted,
                          fontSize: compact ? 11 : 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (cancelled) ...[
                      if (cancelReason.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Motivo: $cancelReason',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: BrandColors.textMuted,
                            fontSize: compact ? 11 : 12,
                          ),
                        ),
                      ],
                    ],
                    if (item.hasCancellationRequested) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Cancelacion solicitada',
                        style: TextStyle(
                          color: BrandColors.danger,
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 11 : 12,
                        ),
                      ),
                      if (cancelReason.isNotEmpty)
                        Text(
                          cancelReason,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: BrandColors.textMuted,
                            fontSize: compact ? 11 : 12,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (item.hasCancellationRequested && !cancelled) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : onAcceptCancellation,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Aceptar cancelacion'),
                  style: FilledButton.styleFrom(
                    minimumSize: Size(compact ? 190 : 230, compact ? 54 : 64),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onRejectCancellation,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Rechazar'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size(compact ? 140 : 170, compact ? 54 : 64),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactKitchenStatusChip extends StatelessWidget {
  const _CompactKitchenStatusChip({required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    final style = item.isCancelled
        ? const StatusStyle(
            label: 'Cancelado',
            color: BrandColors.danger,
            background: Color(0x1FFF5A5A),
          )
        : item.hasCancellationRequested
        ? const StatusStyle(
            label: 'Cancelacion',
            color: BrandColors.danger,
            background: Color(0x1FFF5A5A),
          )
        : kitchenStatusStyle(item.kitchenStatus);
    return Container(
      constraints: const BoxConstraints(maxWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.color.withValues(alpha: 0.45)),
      ),
      child: Text(
        style.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: style.color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _KitchenDetailActions extends StatelessWidget {
  const _KitchenDetailActions({
    required this.compact,
    required this.busy,
    required this.isLastPerson,
    required this.showPrevious,
    required this.elapsedSince,
    required this.onPrevious,
    required this.onNext,
    required this.accent,
    required this.onReady,
  });

  final bool compact;
  final bool busy;
  final bool isLastPerson;
  final bool showPrevious;
  final DateTime? elapsedSince;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Color accent;
  final VoidCallback onReady;

  @override
  Widget build(BuildContext context) {
    final primaryButton = isLastPerson
        ? FilledButton.icon(
            onPressed: busy ? null : onReady,
            style: FilledButton.styleFrom(
              minimumSize: Size.fromHeight(compact ? 72 : 84),
              backgroundColor: accent,
              foregroundColor: Colors.white,
              textStyle: TextStyle(
                fontSize: compact ? 20 : 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Listo'),
          )
        : FilledButton.icon(
            onPressed: busy ? null : onNext,
            style: FilledButton.styleFrom(
              minimumSize: Size.fromHeight(compact ? 78 : 90),
              textStyle: TextStyle(
                fontSize: compact ? 22 : 28,
                fontWeight: FontWeight.w900,
              ),
              backgroundColor: accent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.chevron_right, size: 34),
            label: const Text('Siguiente plato'),
          );
    final previousButton = OutlinedButton.icon(
      onPressed: busy ? null : onPrevious,
      style: OutlinedButton.styleFrom(
        minimumSize: Size.fromHeight(compact ? 52 : 60),
      ),
      icon: const Icon(Icons.chevron_left),
      label: const Text('Anterior'),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PreparationTimer(startTime: elapsedSince, compact: true),
          const SizedBox(height: 8),
          Row(
            children: [
              if (showPrevious) ...[
                Expanded(child: previousButton),
                const SizedBox(width: 8),
              ],
              Expanded(flex: 3, child: primaryButton),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: _PreparationTimer(startTime: elapsedSince)),
        if (showPrevious) ...[
          const SizedBox(width: 12),
          Expanded(child: previousButton),
        ],
        const SizedBox(width: 12),
        Expanded(flex: 3, child: primaryButton),
      ],
    );
  }
}

String _personDisplayName(int personNumber, List<OrderItem> items) {
  for (final item in items) {
    final name = item.personName.trim();
    if (name.isNotEmpty && name != 'Persona $personNumber') {
      return name;
    }
  }
  return 'Persona $personNumber';
}

class _NoActiveKitchenItems extends StatelessWidget {
  const _NoActiveKitchenItems({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassPanel(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: BrandColors.success,
              size: 42,
            ),
            const SizedBox(height: 12),
            const Text(
              'Comanda sin articulos pendientes.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver a comandas'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreparationTimer extends StatelessWidget {
  const _PreparationTimer({required this.startTime, this.compact = false});

  final DateTime? startTime;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return KitchenElapsedBadge(
      startTime: startTime,
      prefix: 'En preparacion',
      height: compact ? 42 : 48,
    );
  }
}

class KitchenElapsedBadge extends StatefulWidget {
  const KitchenElapsedBadge({
    super.key,
    required this.startTime,
    required this.prefix,
    required this.height,
  });

  final DateTime? startTime;
  final String prefix;
  final double height;

  @override
  State<KitchenElapsedBadge> createState() => _KitchenElapsedBadgeState();
}

class _KitchenElapsedBadgeState extends State<KitchenElapsedBadge> {
  late final Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = widget.startTime == null
        ? Duration.zero
        : _now.difference(widget.startTime!);
    final color = _elapsedColor(elapsed);

    return Container(
      height: widget.height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${widget.prefix} ${_formatElapsed(elapsed)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.order,
    required this.compact,
    required this.onClose,
  });

  final PosOrder order;
  final bool compact;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 18 : 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                _formatTime(order.sentToKitchenAt ?? order.updatedAt),
                style: TextStyle(
                  color: BrandColors.textMuted,
                  fontSize: compact ? 11 : 12,
                ),
              ),
            ],
          ),
        ),
        StatusBadge(style: kitchenStatusStyle(order.kitchenStatus)),
      ],
    );
  }

  String _formatTime(DateTime? date) {
    if (date == null) {
      return 'Hora pendiente';
    }

    return DateFormat('HH:mm').format(date);
  }
}

Color _elapsedColor(Duration elapsed) {
  if (elapsed <= const Duration(minutes: 4)) {
    return BrandColors.success;
  }
  if (elapsed <= const Duration(minutes: 6)) {
    return BrandColors.accentYellow;
  }
  return BrandColors.danger;
}

String _formatElapsed(Duration elapsed) {
  final safeElapsed = elapsed.isNegative ? Duration.zero : elapsed;
  final minutes = safeElapsed.inMinutes;
  final seconds = safeElapsed.inSeconds
      .remainder(60)
      .toString()
      .padLeft(2, '0');
  return '$minutes:$seconds';
}
