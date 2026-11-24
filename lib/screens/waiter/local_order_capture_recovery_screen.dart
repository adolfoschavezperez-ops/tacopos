import 'package:flutter/material.dart';

import '../../core/orders/local_order_capture.dart';
import '../../core/theme/brand_colors.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';
import 'order_screen.dart';

class LocalOrderCaptureRecoveryScreen extends StatefulWidget {
  const LocalOrderCaptureRecoveryScreen({
    super.key,
    required this.repository,
    required this.restaurantId,
    required this.branchId,
  });

  final TacoPosRepository repository;
  final String restaurantId;
  final String branchId;

  @override
  State<LocalOrderCaptureRecoveryScreen> createState() =>
      _LocalOrderCaptureRecoveryScreenState();
}

class _LocalOrderCaptureRecoveryScreenState
    extends State<LocalOrderCaptureRecoveryScreen> {
  late Future<List<LocalOrderCaptureRecoveryEntry>> _entries;
  final Set<String> _opening = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _entries = widget.repository.loadLocalOrderCaptureRecoveryEntries(
      restaurantId: widget.restaurantId,
      branchId: widget.branchId,
    );
  }

  Future<void> _open(LocalOrderCaptureRecoveryEntry entry) async {
    if (_opening.contains(entry.orderId)) return;
    setState(() => _opening.add(entry.orderId));
    try {
      final order = await widget.repository.getOrderForLocalCaptureRecovery(
        entry,
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => OrderScreen(
            orderId: order.id,
            tableId: order.tableId,
            tableName: order.displayName,
            repository: widget.repository,
          ),
        ),
      );
      if (!mounted) return;
      setState(_load);
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Comanda requiere revisión'),
          content: Text(
            '$error\n\nEl borrador local se conserva. No se reabrió ni se trasladó a otra orden.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _opening.remove(entry.orderId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final employee = AppSession.instance.employee;
    final canReview =
        employee?.canTakeOrders == true ||
        employee?.canCharge == true ||
        employee?.canViewAdmin == true;
    return BrandedScaffold(
      title: 'Comandas pendientes',
      body: !canReview
          ? const EmptyState(
              icon: Icons.lock_outline,
              title: 'Inicia sesión',
              message:
                  'Se requiere un empleado autorizado para revisar borradores.',
            )
          : FutureBuilder<List<LocalOrderCaptureRecoveryEntry>>(
              future: _entries,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyState(
                    icon: Icons.error_outline,
                    title: 'No se pudieron leer los borradores',
                    message: '${snapshot.error}',
                  );
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LoadingPanel(
                    message: 'Revisando capturas de esta tablet...',
                  );
                }
                final entries = snapshot.data ?? const [];
                if (entries.isEmpty) {
                  return const EmptyState(
                    icon: Icons.task_alt,
                    title: 'Sin comandas pendientes',
                    message: 'No hay borradores locales en esta sucursal.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _RecoveryEntryCard(
                    entry: entries[index],
                    opening: _opening.contains(entries[index].orderId),
                    onOpen: () => _open(entries[index]),
                  ),
                );
              },
            ),
    );
  }
}

class _RecoveryEntryCard extends StatelessWidget {
  const _RecoveryEntryCard({
    required this.entry,
    required this.opening,
    required this.onOpen,
  });

  final LocalOrderCaptureRecoveryEntry entry;
  final bool opening;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final lines = entry.visibleLines;
    final status = entry.submission == null
        ? 'Borrador local sin enviar'
        : 'Envío pendiente de confirmación';
    final date = entry.capturedAt;
    final capturedAt =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, color: BrandColors.accentYellow),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.tableName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('Orden ${entry.orderId}'),
                    ],
                  ),
                ),
                Text(status, textAlign: TextAlign.end),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Empleado: ${entry.employeeNames.isEmpty ? 'No disponible' : entry.employeeNames}',
            ),
            Text('Capturada: $capturedAt'),
            const Divider(height: 20),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${line.qty} × ${line.productName} · Persona ${line.personNumber}',
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('${entry.quantity} productos'),
                const Spacer(),
                MoneyText(value: entry.amount),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: opening ? null : onOpen,
              icon: opening
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.open_in_new),
              label: const Text('Abrir y recuperar orden activa'),
            ),
          ],
        ),
      ),
    );
  }
}
