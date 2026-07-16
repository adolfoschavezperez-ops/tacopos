import '../models/order_item.dart';

String formatOrderItemDisplayName(
  OrderItem item, {
  bool includeQuantity = true,
}) {
  final quantity = _formatQuantity(item.qty);
  final category = item.category.trim();
  final productName = item.productName.trim().isEmpty
      ? 'Producto'
      : item.productName.trim();
  final name = category.isEmpty ? productName : '$category - $productName';

  return includeQuantity ? '$quantity $name' : name;
}

String _formatQuantity(num value) {
  final number = value.toDouble();
  if (number == number.roundToDouble()) {
    return number.toInt().toString();
  }
  return number.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

String formatKitchenStatus(String status) {
  return switch (status) {
    'pending' => 'Pendiente',
    'sent' => 'En cocina',
    'cooking' => 'En preparacion',
    'ready' => 'Servido',
    'not_required' => 'No requiere cocina',
    'cancel_requested' => 'Cancelacion solicitada',
    'cancelled' => 'Cancelado',
    'voided' => 'Anulado',
    _ => status,
  };
}

String formatCancelStatus(String status) {
  return switch (status) {
    'none' => 'Sin cancelacion',
    'requested' => 'Cancelacion solicitada',
    'accepted' => 'Cancelado',
    'rejected' => 'Cancelacion rechazada',
    'cancelled' => 'Cancelado',
    _ => status,
  };
}

String formatPaymentStatus(String status) {
  return switch (status) {
    'pending' => 'Pendiente',
    'partial' => 'Parcial',
    'paid' => 'Pagado',
    'cancelled' => 'Cancelado',
    'voided' => 'Anulado',
    _ => status,
  };
}

String formatOrderStatus(String status) {
  return switch (status) {
    'open' => 'Abierta',
    'sent' => 'En cocina',
    'cooking' => 'En preparacion',
    'ready' => 'Lista',
    'paid' => 'Pagada',
    'cancelled' => 'Cancelada',
    'voided' => 'Anulada',
    _ => status,
  };
}

String formatPaymentMethod(String method) {
  return switch (method) {
    'cash' => 'Efectivo',
    'card' => 'Tarjeta',
    'employee_consumption' => 'Consumo empleado',
    'platform_paid' => 'Pagado en plataforma',
    _ => method,
  };
}
