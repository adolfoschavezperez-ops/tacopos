import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/activity_event.dart';
import '../../../models/cash_session.dart';
import '../../../models/order.dart';
import '../../../models/product.dart';
import '../../../models/purchase_models.dart';
import '../../core/adapters/sales_adapter.dart';

enum AuditAlertSeverity { info, warning, high }

class AdminAlertFinding {
  const AdminAlertFinding({
    required this.category,
    required this.title,
    required this.detail,
    required this.severity,
    this.orderId,
    this.targetModule,
  });

  final String category;
  final String title;
  final String detail;
  final AuditAlertSeverity severity;
  final String? orderId;
  final String? targetModule;
}

class AuditDashboardData {
  const AuditDashboardData({
    required this.events,
    required this.alerts,
    required this.readCount,
  });

  final List<ActivityEvent> events;
  final List<AdminAlertFinding> alerts;
  final int readCount;
}

/// Strictly read-only repository for Audit Logs and Administrative Alerts.
class AuditRepository {
  AuditRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<AuditDashboardData> loadAuditData({
    required String restaurantId,
    required DateTime startDate,
    required DateTime endDate,
    String? branchId,
  }) async {
    final startStr = BackofficeSalesAdapter.formatBusinessDate(startDate);
    final endStr = BackofficeSalesAdapter.formatBusinessDate(endDate);
    final restRef = _db.collection('restaurants').doc(restaurantId);

    final results = await Future.wait([
      restRef
          .collection('activityLog')
          .orderBy('createdAt', descending: true)
          .limit(300)
          .get(),
      restRef
          .collection('cashSessions')
          .where('businessDate', isGreaterThanOrEqualTo: startStr)
          .where('businessDate', isLessThanOrEqualTo: endStr)
          .limit(80)
          .get(),
      restRef
          .collection('orders')
          .where('businessDate', isGreaterThanOrEqualTo: startStr)
          .where('businessDate', isLessThanOrEqualTo: endStr)
          .limit(250)
          .get(),
      restRef
          .collection('cashWithdrawalRequests')
          .where('status', isEqualTo: 'pending')
          .limit(50)
          .get(),
      restRef
          .collection('discountAuthorizationRequests')
          .where('status', isEqualTo: 'pending')
          .limit(50)
          .get(),
      restRef
          .collection('supplierPurchases')
          .where('businessDate', isGreaterThanOrEqualTo: startStr)
          .where('businessDate', isLessThanOrEqualTo: endStr)
          .limit(120)
          .get(),
      restRef.collection('products').limit(200).get(),
      restRef.collection('productRecipes').limit(200).get(),
    ]);

    var readCount = 0;
    for (final r in results) {
      readCount += r.docs.length;
    }

    bool matchesBranch(String docBranch) =>
        branchId == null ||
        branchId.isEmpty ||
        docBranch.isEmpty ||
        docBranch == branchId;

    final startBoundary = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final endBoundary = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      23,
      59,
      59,
    );

    final events = results[0].docs
        .map(ActivityEvent.fromDoc)
        .where((e) {
          if (!matchesBranch(e.branchId)) return false;
          final ts = e.createdAt;
          if (ts != null) {
            if (ts.isBefore(startBoundary) || ts.isAfter(endBoundary)) {
              return false;
            }
          }
          return true;
        })
        .toList(growable: false);

    final alerts = <AdminAlertFinding>[];

    // 1. Cash shortages/overages
    final sessions = results[1].docs
        .map(CashSession.fromDoc)
        .where((s) => matchesBranch(s.branchId));
    for (final s in sessions) {
      if (s.shortageAmount > 0.02) {
        alerts.add(
          AdminAlertFinding(
            category: 'Caja',
            title: 'Faltante en corte ${s.businessDate}',
            detail:
                '${s.branchName}: diferencia negativa de ${BackofficeSalesAdapter.formatMoney(s.shortageAmount)}.',
            severity: AuditAlertSeverity.high,
            targetModule: 'cash',
          ),
        );
      } else if (s.overAmount > 0.02) {
        alerts.add(
          AdminAlertFinding(
            category: 'Caja',
            title: 'Sobrante en corte ${s.businessDate}',
            detail:
                '${s.branchName}: diferencia positiva de ${BackofficeSalesAdapter.formatMoney(s.overAmount)}.',
            severity: AuditAlertSeverity.warning,
            targetModule: 'cash',
          ),
        );
      }
    }

    // 2. Cancellations & unusual discounts
    final orders = results[2].docs
        .map(PosOrder.fromDoc)
        .where((o) => matchesBranch(o.branchId))
        .toList(growable: false);
    final cancelled = orders
        .where((o) => o.status.trim().toLowerCase() == 'cancelled')
        .toList(growable: false);
    if (cancelled.length >= 3) {
      alerts.add(
        AdminAlertFinding(
          category: 'Cancelaciones',
          title: '${cancelled.length} órdenes canceladas en el periodo',
          detail:
              'Revisa motivos y responsables en Ventas o en el reporte de Cancelaciones.',
          severity: AuditAlertSeverity.warning,
          targetModule: 'sales',
        ),
      );
    }
    for (final o in orders) {
      final gross = o.grossSubtotal ?? o.total;
      if (gross > 0 && o.explicitDiscount / gross > 0.25) {
        alerts.add(
          AdminAlertFinding(
            category: 'Descuentos',
            title:
                'Descuento alto en ${BackofficeSalesAdapter.resolveFolioLabel(o)}',
            detail:
                'Descuento de ${BackofficeSalesAdapter.formatMoney(o.explicitDiscount)} sobre ${BackofficeSalesAdapter.formatMoney(gross)}.',
            severity: AuditAlertSeverity.warning,
            orderId: o.id,
          ),
        );
      }
    }

    // 3. Pending authorizations
    final pendingWithdrawals = results[3].docs
        .where((d) => matchesBranch((d.data()['branchId'] ?? '').toString()))
        .length;
    final pendingDiscounts = results[4].docs
        .where((d) => matchesBranch((d.data()['branchId'] ?? '').toString()))
        .length;
    if (pendingWithdrawals + pendingDiscounts > 0) {
      alerts.add(
        AdminAlertFinding(
          category: 'Autorizaciones',
          title: 'Solicitudes pendientes de revisión',
          detail:
              '$pendingWithdrawals retiro(s) y $pendingDiscounts descuento(s) esperan autorización.',
          severity: AuditAlertSeverity.info,
          targetModule: 'authorizations',
        ),
      );
    }

    // 4. Overdue CXP
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final purchases = results[5].docs
        .map(SupplierPurchase.fromDoc)
        .where((p) => matchesBranch(p.branchId));
    var overdueCount = 0;
    var overdueAmount = 0.0;
    for (final p in purchases) {
      if (p.status.toLowerCase() != 'cancelled' &&
          p.balance > 0.01 &&
          p.dueDate != null &&
          p.dueDate!.isBefore(today)) {
        overdueCount++;
        overdueAmount += p.balance;
      }
    }
    if (overdueCount > 0) {
      alerts.add(
        AdminAlertFinding(
          category: 'Cuentas por pagar',
          title: '$overdueCount factura(s) vencida(s)',
          detail:
              'Saldo vencido acumulado: ${BackofficeSalesAdapter.formatMoney(overdueAmount)}.',
          severity: AuditAlertSeverity.high,
          targetModule: 'purchases',
        ),
      );
    }

    // 5. Products without theoretical recipe
    final activeProducts = results[6].docs
        .map(Product.fromDoc)
        .where((p) => p.active)
        .toList(growable: false);
    final recipeIds = results[7].docs.map((d) => d.id).toSet();
    final missingRecipeCount = activeProducts
        .where((p) => !recipeIds.contains(p.id))
        .length;
    if (missingRecipeCount > 0) {
      alerts.add(
        AdminAlertFinding(
          category: 'Rentabilidad',
          title: '$missingRecipeCount producto(s) activo(s) sin receta teórica',
          detail:
              'Su costo aparece como "Costo N/D" hasta configurar receta en Inventarios.',
          severity: AuditAlertSeverity.info,
          targetModule: 'inventory',
        ),
      );
    }

    return AuditDashboardData(
      events: events,
      alerts: alerts,
      readCount: readCount,
    );
  }
}
