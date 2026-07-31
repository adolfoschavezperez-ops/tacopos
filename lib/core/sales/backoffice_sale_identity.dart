import '../../models/order.dart';
import 'daily_sale_folio.dart';

const backofficeHistoricalNoFolioText = 'Sin folio';

class BackofficeSaleIdentity {
  const BackofficeSaleIdentity({
    required this.visibleOrderId,
    required this.dailyFolio,
    this.fullFolio,
  });

  final String visibleOrderId;
  final String dailyFolio;
  final String? fullFolio;

  bool get hasFullFolio => fullFolio != null && fullFolio!.isNotEmpty;
}

BackofficeSaleIdentity backofficeSaleIdentity(
  PosOrder order, {
  int folioDigits = 4,
}) {
  final display = order.saleFolioDisplay?.trim();
  final sequence = order.saleFolioSequence;
  final full = order.saleFolioFull?.trim();
  return BackofficeSaleIdentity(
    visibleOrderId: backofficeVisibleOrderId(order.id),
    dailyFolio: display != null && display.isNotEmpty
        ? display
        : sequence != null && sequence > 0
        ? formatSaleFolioDisplay(sequence, folioDigits)
        : backofficeHistoricalNoFolioText,
    fullFolio: full == null || full.isEmpty ? null : full,
  );
}

String backofficeVisibleOrderId(String id) {
  return id.length <= 6 ? id : id.substring(0, 6);
}

bool backofficeSaleMatchesQuery(
  PosOrder order,
  String query, {
  int folioDigits = 4,
}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  return backofficeSaleSearchText(
    order,
    folioDigits: folioDigits,
  ).contains(normalized);
}

String backofficeSaleSearchText(PosOrder order, {int folioDigits = 4}) {
  final identity = backofficeSaleIdentity(order, folioDigits: folioDigits);
  final sequence = order.saleFolioSequence;
  return [
        identity.visibleOrderId,
        order.id,
        identity.dailyFolio,
        if (sequence != null && sequence > 0) sequence.toString(),
        if (identity.hasFullFolio) identity.fullFolio,
        order.displayName,
        order.tableName,
        order.customerName,
        order.platformName,
      ]
      .whereType<String>()
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .join(' | ');
}
