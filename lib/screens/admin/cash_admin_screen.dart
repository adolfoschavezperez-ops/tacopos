import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/cash_session.dart';
import '../../models/cash_withdrawal_request.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';

class CashAdminScreen extends StatelessWidget {
  const CashAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final employee = AppSession.instance.employee;
    if (employee?.canViewAdmin != true) {
      return const BrandedScaffold(
        title: 'Caja Admin',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para ver cortes.',
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: BrandedScaffold(
        title: 'Caja Admin',
        body: const Column(
          children: [
            TabBar(
              tabs: [
                Tab(icon: Icon(Icons.receipt_long), text: 'Cortes'),
                Tab(icon: Icon(Icons.verified_user_outlined), text: 'Retiros'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [_CashSessionsTab(), _WithdrawalAuthorizationTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CashSessionsTab extends StatelessWidget {
  const _CashSessionsTab();

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();
    return StreamBuilder<List<CashSession>>(
      stream: repository.watchCashSessions(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudieron cargar cortes',
            message: '${snapshot.error}',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPanel(message: 'Cargando cortes...');
        }

        final sessions = snapshot.data ?? [];
        if (sessions.isEmpty) {
          return const EmptyState(
            icon: Icons.point_of_sale_outlined,
            title: 'Sin cortes',
            message: 'Aun no hay cajas registradas.',
          );
        }

        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const SectionHeader(
              title: 'Cortes de caja',
              subtitle: 'Desglose completo para Admin / Socio.',
            ),
            const SizedBox(height: 18),
            ...sessions.map(
              (session) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _CashSessionDetailCard(session: session),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CashSessionDetailCard extends StatelessWidget {
  const _CashSessionDetailCard({required this.session});

  final CashSession session;

  @override
  Widget build(BuildContext context) {
    final statusColor = session.isOpen
        ? BrandColors.success
        : BrandColors.textMuted;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Fecha operativa ${session.businessDate}',
            subtitle:
                '${session.isOpen ? 'Abierta' : 'Cerrada'} | abre ${_employeeName(session.openedByEmployeeName)} | cierra ${_employeeName(session.closedByEmployeeName)}',
            trailing: Icon(Icons.point_of_sale_outlined, color: statusColor),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 10,
            children: [
              _MoneyChip(
                label: 'Fondo inicial',
                value: session.openingCashAmount,
              ),
              _MoneyChip(
                label: 'Efectivo esperado',
                value: session.expectedCashAmount,
              ),
              _MoneyChip(
                label: 'Efectivo contado',
                value: session.countedCashAmount,
              ),
              _MoneyChip(
                label: 'Diferencia efectivo',
                value: session.cashDifference,
              ),
              _MoneyChip(
                label: 'Tarjeta esperada',
                value: session.expectedCardChargedAmount,
              ),
              _MoneyChip(
                label: 'Terminal reportada',
                value: session.terminalReportedAmount,
              ),
              _MoneyChip(
                label: 'Diferencia tarjeta',
                value: session.cardDifference,
              ),
              _MoneyChip(
                label: 'Comision tarjeta',
                value: session.expectedCardSurchargeAmount,
              ),
              _MoneyChip(
                label: 'Plataforma',
                value: session.expectedPlatformAmount,
              ),
              _MoneyChip(
                label: 'Consumo empleado',
                value: session.expectedEmployeeConsumptionAmount,
              ),
              _MoneyChip(
                label: 'Retiros aprobados',
                value: session.approvedWithdrawalsTotal,
              ),
              _MoneyChip(
                label: 'Retiros pendientes',
                value: session.pendingWithdrawalsTotal,
              ),
              _MoneyChip(label: 'Faltante', value: session.shortageAmount),
              _MoneyChip(label: 'Sobrante', value: session.overAmount),
            ],
          ),
          const Divider(height: 24),
          _InfoLine(
            label: 'Usuario que abrio',
            value: session.openedByEmployeeName,
          ),
          _InfoLine(
            label: 'Usuario que cerro',
            value: session.closedByEmployeeName ?? 'Sin cierre',
          ),
          _InfoLine(label: 'Fecha operativa', value: session.businessDate),
          _InfoLine(
            label: 'Notas',
            value: session.notes.isEmpty ? 'Sin notas' : session.notes,
          ),
        ],
      ),
    );
  }

  String _employeeName(String? name) {
    return name == null || name.isEmpty ? 'Empleado' : name;
  }
}

class _WithdrawalAuthorizationTab extends StatelessWidget {
  const _WithdrawalAuthorizationTab();

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();
    final canAuthorize =
        AppSession.instance.employee?.canAuthorizeCashWithdrawals == true;

    return StreamBuilder<List<CashWithdrawalRequest>>(
      stream: repository.watchCashWithdrawalRequests(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudieron cargar retiros',
            message: '${snapshot.error}',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPanel(message: 'Cargando retiros...');
        }

        final requests = snapshot.data ?? [];
        final pending = requests.where((request) => request.isPending).toList();
        final attended = requests.where((request) => !request.isPending);

        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const SectionHeader(
              title: 'Autorizacion de retiros',
              subtitle: 'Aprueba o rechaza gastos eventuales.',
            ),
            const SizedBox(height: 18),
            if (!canAuthorize)
              const GlassPanel(
                borderColor: BrandColors.danger,
                child: Text(
                  'No tienes permiso para autorizar retiros.',
                  style: TextStyle(
                    color: BrandColors.danger,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else if (pending.isEmpty)
              const GlassPanel(
                child: Text(
                  'Sin solicitudes pendientes.',
                  style: TextStyle(color: BrandColors.textMuted),
                ),
              )
            else
              ...pending.map(
                (request) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _WithdrawalAdminCard(
                    request: request,
                    repository: repository,
                    canAuthorize: canAuthorize,
                  ),
                ),
              ),
            const SizedBox(height: 18),
            const SectionHeader(
              title: 'Historial',
              subtitle: 'Solicitudes atendidas recientemente.',
            ),
            const SizedBox(height: 12),
            if (attended.isEmpty)
              const GlassPanel(
                child: Text(
                  'Aun no hay retiros atendidos.',
                  style: TextStyle(color: BrandColors.textMuted),
                ),
              )
            else
              ...attended
                  .take(20)
                  .map(
                    (request) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _WithdrawalAdminCard(
                        request: request,
                        repository: repository,
                        canAuthorize: false,
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }
}

class _WithdrawalAdminCard extends StatelessWidget {
  const _WithdrawalAdminCard({
    required this.request,
    required this.repository,
    required this.canAuthorize,
  });

  final CashWithdrawalRequest request;
  final TacoPosRepository repository;
  final bool canAuthorize;

  @override
  Widget build(BuildContext context) {
    final color = request.isApproved
        ? BrandColors.success
        : request.isRejected
        ? BrandColors.danger
        : BrandColors.accentYellow;

    return GlassPanel(
      borderColor: request.isPending ? BrandColors.accentYellow : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.request_quote_outlined, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  request.reason,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              MoneyText(
                value: request.amount,
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoLine(label: 'Estado', value: _statusText(request)),
          _InfoLine(
            label: 'Solicitado por',
            value: request.requestedByEmployeeName,
          ),
          _InfoLine(label: 'Fecha operativa', value: request.businessDate),
          _InfoLine(
            label: 'Solicitado',
            value: _formatDate(request.requestedAt),
          ),
          if (!request.isPending) ...[
            _InfoLine(
              label: request.isApproved ? 'Autorizado por' : 'Rechazado por',
              value: request.authorizedByEmployeeName ?? '',
            ),
            _InfoLine(
              label: 'Atendido',
              value: _formatDate(request.authorizedAt),
            ),
            _InfoLine(
              label: 'Notas admin',
              value: request.adminNotes?.isEmpty == false
                  ? request.adminNotes!
                  : 'Sin notas',
            ),
          ],
          if (canAuthorize && request.isPending) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _resolve(context, approved: false),
                  icon: const Icon(Icons.close),
                  label: const Text('Rechazar'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _resolve(context, approved: true),
                  icon: const Icon(Icons.check),
                  label: const Text('Aprobar'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _resolve(BuildContext context, {required bool approved}) async {
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approved ? 'Aprobar retiro' : 'Rechazar retiro'),
        content: TextField(
          controller: notesController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Notas admin'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(approved ? 'Aprobar' : 'Rechazar'),
          ),
        ],
      ),
    );

    if (!context.mounted) {
      notesController.dispose();
      return;
    }
    if (confirmed != true) {
      notesController.dispose();
      return;
    }

    try {
      await repository.authorizeCashWithdrawal(
        requestId: request.id,
        approved: approved,
        adminNotes: notesController.text,
      );
      notesController.dispose();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approved ? 'Retiro aprobado.' : 'Retiro rechazado.'),
        ),
      );
    } catch (error) {
      notesController.dispose();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  String _statusText(CashWithdrawalRequest request) {
    if (request.isApproved) {
      return 'Aprobado';
    }
    if (request.isRejected) {
      return 'Rechazado';
    }
    return 'Pendiente';
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return 'Sin fecha';
    }
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }
}

class _MoneyChip extends StatelessWidget {
  const _MoneyChip({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final color = value < 0 ? BrandColors.danger : BrandColors.accentYellow;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        accent: color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: BrandColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            MoneyText(
              value: value,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                color: BrandColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'Sin dato' : value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
