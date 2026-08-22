import '../../models/cash_session.dart';
import '../../models/order.dart';
import '../cash/operational_business_date.dart';

class PaymentOperationalScope {
  const PaymentOperationalScope({
    required this.businessDate,
    required this.cashSessionId,
  });

  final String businessDate;
  final String cashSessionId;
}

PaymentOperationalScope resolveNewPaymentOperationalScope({
  required PosOrder order,
  required CashSession? activeCashSession,
}) {
  validateOrderCanReceiveNewPayment(order);
  final session = activeCashSession;
  if (session == null) {
    throw StateError('No hay una caja abierta para registrar el pago.');
  }
  final businessDate = businessDateForOpenCashSession(session);
  return PaymentOperationalScope(
    businessDate: businessDate,
    cashSessionId: session.id,
  );
}

void validateOrderCanReceiveNewPayment(PosOrder order) {
  final status = order.status.trim().toLowerCase();
  final paymentStatus = order.paymentStatus.trim().toLowerCase();
  if (status == 'cancelled' ||
      status == 'canceled' ||
      status == 'cancelado' ||
      status == 'voided' ||
      paymentStatus == 'cancelled' ||
      paymentStatus == 'canceled' ||
      paymentStatus == 'cancelado') {
    throw StateError('No se puede cobrar una orden cancelada.');
  }
  if (paymentStatus == 'paid' || order.pendingTotal <= 0.01) {
    throw StateError('La orden no tiene saldo pendiente por cobrar.');
  }
}
