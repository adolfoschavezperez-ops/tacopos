// Unit-for-unit reconciliation. No inferred recipes, yield or regression.
enum ResaleFamily { water, empanada }

enum ResaleExitKind { paid, recordedOther, cancellationWithoutDeliveryProof }

// A zero-cash checkout is still a physical exit when the item was finalized.
// Use the payment linked to the item, not every payment on a split order.
ResaleExitKind resaleFinalizedExitKind({
  required String discountType,
  required String method,
  required double discountPercent,
  required double discountAmount,
  required double subtotal,
  required double chargedAmount,
  double legacyDiscountPercent = 0,
  double baseAmount = 0,
}) {
  final type = discountType.trim().toLowerCase();
  final paymentMethod = method.trim().toLowerCase();
  if (type == 'employee_free_meal') return ResaleExitKind.recordedOther;
  if (paymentMethod == 'employee_consumption' && type.isEmpty &&
      baseAmount > 0 && discountAmount <= 0.01 &&
      discountPercent <= 0.01 && legacyDiscountPercent <= 0.01) {
    // Legacy employee consumption is treated as a free meal by the canonical
    // sales summary. The physical unit must still leave stock.
    return ResaleExitKind.recordedOther;
  }
  final fullyDiscounted = chargedAmount <= 0.01 &&
      (discountPercent >= 99.99 ||
          (subtotal > 0 && discountAmount >= subtotal - 0.01));
  return fullyDiscounted ? ResaleExitKind.recordedOther : ResaleExitKind.paid;
}

class ResalePurchase {
  const ResalePurchase({required this.id, required this.date, required this.supplier,
    required this.name, required this.quantity, required this.unit,
    required this.lineCost, this.stockItemId = '', this.purchaseItemId = ''});
  final String id, date, supplier, name, unit, stockItemId, purchaseItemId;
  final double quantity, lineCost;
}

class ResaleExit {
  const ResaleExit({required this.date, required this.productId,
    required this.name, required this.category, required this.quantity,
    required this.saleAmount, required this.kind, this.stockItemId = ''});
  final String date, productId, name, category, stockItemId;
  final int quantity;
  final double saleAmount;
  final ResaleExitKind kind;
}

class ResaleCheckpoint {
  const ResaleCheckpoint({required this.date, required this.key,
    required this.physicalCount, this.boundary = 'closing', this.recordedAt,
    this.confirmed = true, this.correctionRevision = 0,
    this.correctionReason, this.originalPhysicalCount, this.originalRecordedAt,
    this.originalByUid = '', this.corrections = const []});
  final String date, key;
  final int physicalCount;
  // The count is measured after all movements for the operational date.
  final String boundary;
  final DateTime? recordedAt;
  // Retrospective declarations and late corrections never confirm a loss.
  final bool confirmed;
  final int correctionRevision;
  final String? correctionReason;
  final int? originalPhysicalCount;
  final DateTime? originalRecordedAt;
  final String originalByUid;
  final List<ResaleCheckpointCorrection> corrections;
}

bool resaleClosingCountIsRecent(DateTime closedAt, DateTime recordedAt) {
  final age = recordedAt.difference(closedAt);
  return !age.isNegative && age <= const Duration(hours: 24);
}

class ResaleCheckpointCorrection {
  const ResaleCheckpointCorrection({required this.revision,
    required this.physicalCount, required this.reason, required this.recordedAt,
    this.recordedByUid = ''});
  final int revision, physicalCount;
  final String reason;
  final DateTime recordedAt;
  final String recordedByUid;
}

ResaleCheckpoint resaleEffectiveCheckpoint(ResaleCheckpoint original,
    Iterable<ResaleCheckpointCorrection> corrections) {
  var revision = 0;
  var count = original.physicalCount;
  var recordedAt = original.recordedAt;
  var confirmed = original.confirmed;
  String? reason;
  final applied = <ResaleCheckpointCorrection>[];
  for (final correction in corrections.toList()
      ..sort((a, b) => a.revision.compareTo(b.revision))) {
    if (correction.revision != revision + 1 ||
        correction.physicalCount < 0 || correction.reason.trim().length < 10) {
      break;
    }
    revision = correction.revision;
    applied.add(correction);
    count = correction.physicalCount;
    recordedAt = correction.recordedAt;
    reason = correction.reason;
    confirmed = confirmed && original.recordedAt != null &&
        resaleClosingCountIsRecent(original.recordedAt!, correction.recordedAt);
  }
  return ResaleCheckpoint(date: original.date, key: original.key,
    physicalCount: count, boundary: original.boundary, recordedAt: recordedAt,
    confirmed: confirmed, correctionRevision: revision, correctionReason: reason,
    originalPhysicalCount: original.originalPhysicalCount ?? original.physicalCount,
    originalRecordedAt: original.originalRecordedAt ?? original.recordedAt,
    originalByUid: original.originalByUid, corrections: applied);
}

class ResaleDay {
  const ResaleDay(this.date, this.bought, this.sold, this.other,
    this.relativeBalance, this.cost, this.revenue);
  final String date;
  final int bought, sold, other, relativeBalance;
  final double cost, revenue;
}

class ResalePeriod {
  const ResalePeriod(this.bought, this.sold, this.other, this.cost, this.revenue);
  final int bought, sold, other;
  final double cost, revenue;
  int get netUnits => bought - sold - other;
}

class ResaleProduct {
  const ResaleProduct({required this.key, required this.family,
    required this.name, required this.suppliers, required this.productIds,
    required this.days, required this.lastPurchaseDate,
    required this.initialUnknown, required this.checkpoint, required this.checkpoints,
    required this.physicalDifference, required this.unprovenCancellations});
  final String key, name, lastPurchaseDate;
  final ResaleFamily family;
  final List<String> suppliers, productIds;
  final List<ResaleDay> days;
  final bool initialUnknown;
  final ResaleCheckpoint? checkpoint;
  final List<ResaleCheckpoint> checkpoints;
  // physical count minus theoretical count, only available after a checkpoint.
  final int? physicalDifference;
  final int unprovenCancellations;

  int get bought => days.fold(0, (n, d) => n + d.bought);
  int get sold => days.fold(0, (n, d) => n + d.sold);
  int get other => days.fold(0, (n, d) => n + d.other);
  int get relativeBalance => days.isEmpty ? 0 : days.last.relativeBalance;
  int balanceAt(String date) {
    final selected = days.where((d) => d.date.compareTo(date) <= 0);
    return selected.isEmpty ? 0 : selected.last.relativeBalance;
  }
  double get cost => days.fold(0, (n, d) => n + d.cost);
  double get revenue => days.fold(0, (n, d) => n + d.revenue);
  double get unitCost => bought == 0 ? 0 : cost / bought;
  double? get theoreticalInventory => initialUnknown ? null :
    ((checkpoint?.physicalCount ?? 0) +
    days.where((d) => checkpoint == null || d.date.compareTo(checkpoint!.date) > 0)
      .fold<int>(0, (n, d) => n + d.bought - d.sold - d.other)).toDouble();
  double? get theoreticalValue => theoreticalInventory == null ? null :
    theoreticalInventory! * unitCost;
  bool get hasNegativeRelativeBalance => days.any((d) => d.relativeBalance < 0);
  // A zero inferred only from purchases and sales is not an inventory count.
  // Closed cycle boundaries require an actual physical starting checkpoint.
  List<String> get anchoredCycleStarts {
    if (checkpoint == null || initialUnknown) return const [];
    var opening = checkpoint!.physicalCount;
    final starts = <String>[];
    for (final day in days.where((d) => d.date.compareTo(checkpoint!.date) > 0)) {
      if (day.bought > 0 && opening == 0) starts.add(day.date);
      opening += day.bought - day.sold - day.other;
    }
    return starts;
  }
  ResalePeriod period(String start, String end) {
    final selected = days.where((d) => d.date.compareTo(start) >= 0 && d.date.compareTo(end) <= 0);
    return ResalePeriod(
      selected.fold(0, (n, d) => n + d.bought),
      selected.fold(0, (n, d) => n + d.sold),
      selected.fold(0, (n, d) => n + d.other),
      selected.fold(0.0, (n, d) => n + d.cost),
      selected.fold(0.0, (n, d) => n + d.revenue),
    );
  }
}

class ResaleAudit {
  const ResaleAudit({required this.products, required this.unmatchedPurchases,
    required this.unmatchedSales, required this.notes});
  final List<ResaleProduct> products;
  final List<String> unmatchedPurchases, unmatchedSales, notes;
}

String resaleNormalize(String value) {
  const accented = 'áéíóúüñ';
  const plain = 'aeiouun';
  var result = value.toLowerCase();
  for (var i = 0; i < accented.length; i++) {
    result = result.replaceAll(accented[i], plain[i]);
  }
  return result.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

ResaleFamily? resaleSupplierFamily(String supplier) {
  final words = resaleNormalize(supplier).split(' ');
  if (words.contains('aguas') && words.contains('fanny')) return ResaleFamily.water;
  if (words.contains('empanaditas')) return ResaleFamily.empanada;
  return null;
}

String _itemKey(String name) => resaleNormalize(name)
    .replaceAll(RegExp(r'\s+x\s*\d+\s*$'), '').trim();

bool _isExplicitlyDifferentProduct(String name, ResaleFamily family) {
  final normalized = resaleNormalize(name);
  if (family != ResaleFamily.water) return false;
  return RegExp(r'\b(?:refresco|refrescos|soda|coca cola|pepsi|sprite|fanta)\b')
      .hasMatch(normalized) || normalized.contains('agua mineral');
}

int? _units(ResalePurchase line) {
  final unit = resaleNormalize(line.unit);
  final match = RegExp(r'\bx\s*(\d+)\s*$').firstMatch(resaleNormalize(line.name));
  final pack = match == null ? null : int.tryParse(match.group(1)!);
  var multiplier = 1;
  if (RegExp(r'^(caja|cajas|paquete|paquetes|charola|charolas|pack)$').hasMatch(unit)) {
    if (pack == null || pack < 1) return null;
    multiplier = pack;
  } else if (!RegExp(r'^(|pza|pzas|pieza|piezas|piece|pieces|unidad|unidades|botella|botellas)$').hasMatch(unit)) {
    return null;
  } else if (pack != null && line.quantity != pack) {
    // A line labelled x30 with quantity 1 may be one case or one bottle.
    // Only an explicit package unit establishes the conversion.
    return null;
  }
  final value = line.quantity * multiplier;
  if (!value.isFinite || value <= 0 || value != value.roundToDouble()) return null;
  return value.toInt();
}

ResaleAudit buildResaleAudit({required Iterable<ResalePurchase> purchases,
  required Iterable<ResaleExit> exits, Iterable<ResaleCheckpoint> checkpoints = const [],
  required String endDate}) {
  final candidatePurchases = purchases.where((p) =>
    resaleSupplierFamily(p.supplier) != null && p.date.compareTo(endDate) <= 0).toList();
  final candidateSales = exits.where((s) => s.date.compareTo(endDate) <= 0).toList();
  final unresolvedPurchases = <String>[];
  final unresolvedSales = <String>[];
  final byKey = <String, List<ResalePurchase>>{};
  final mappedExits = <String, List<ResaleExit>>{};
  final names = <String, String>{};
  final families = <String, ResaleFamily>{};

  for (final p in candidatePurchases) {
    final family = resaleSupplierFamily(p.supplier)!;
    if (_units(p) == null || _itemKey(p.name).isEmpty ||
        _isExplicitlyDifferentProduct(p.name, family) ||
        (p.purchaseItemId.isNotEmpty &&
            !RegExp(r'^[A-Za-z0-9_.-]{1,100}$').hasMatch(p.purchaseItemId))) {
      unresolvedPurchases.add('${p.id}: ${p.name} (${p.quantity} ${p.unit})');
      continue;
    }
    // A shared kitchen stock link must not collapse different bottle sizes.
    // A real purchase catalog ID takes priority over a display name.
    final identity = p.purchaseItemId.isNotEmpty
        ? 'sku:${p.purchaseItemId}' : 'name:${_itemKey(p.name)}';
    final key = '${family.name}:$identity';
    byKey.putIfAbsent(key, () => []).add(p);
    names[key] = _itemKey(p.name);
    families[key] = family;
  }
  // One catalog ID reused with different presentation labels is not a
  // trustworthy unit identity. Keep every affected purchase unresolved.
  for (final key in byKey.keys.toList()) {
    if (!key.contains(':sku:')) continue;
    final variants = byKey[key]!.map((p) => _itemKey(p.name)).toSet();
    if (variants.length <= 1) continue;
    for (final p in byKey.remove(key)!) {
      unresolvedPurchases.add('${p.id}: ${p.name} (SKU compartido entre presentaciones)');
    }
    names.remove(key);
    families.remove(key);
  }

  final salesByProduct = <String, List<ResaleExit>>{};
  for (final sale in candidateSales) {
    if (sale.quantity <= 0) continue;
    final identity = '${sale.productId}|${_itemKey(sale.name)}|${sale.stockItemId}';
    salesByProduct.putIfAbsent(identity, () => []).add(sale);
  }
  for (final productSales in salesByProduct.values) {
    final example = productSales.first;
    final possible = <String>{};
    for (final entry in byKey.entries) {
      if (names[entry.key] == _itemKey(example.name)) {
        possible.add(entry.key);
      }
    }
    if (possible.length > 1 && example.stockItemId.isNotEmpty) {
      final linked = possible.where((key) => byKey[key]!.any(
        (p) => p.stockItemId == example.stockItemId)).toSet();
      if (linked.length == 1) {
        possible..clear()..add(linked.single);
      }
    }
    // A kitchen stock link alone cannot establish bottle size or flavor.
    // A single generic empanada purchase can be reconciled across flavors,
    // provided there are no separately purchased flavors to double count.
    if (possible.isEmpty && RegExp(r'\bempanad(?:a|as|ita|itas)\b')
        .hasMatch(resaleNormalize(example.name))) {
      final empanadaKeys = byKey.keys.where((k) => families[k] == ResaleFamily.empanada).toList();
      if (empanadaKeys.length == 1 &&
          const {'empanada', 'empanadas', 'empanadita', 'empanaditas'}
            .contains(names[empanadaKeys.single])) {
        possible.add(empanadaKeys.single);
      }
    }
    if (possible.length == 1) {
      mappedExits.putIfAbsent(possible.single, () => []).addAll(productSales);
    } else if (possible.isNotEmpty || example.stockItemId.isNotEmpty ||
        RegExp(r'\b(?:agua|aguas|empanad(?:a|as|ita|itas))\b')
            .hasMatch(resaleNormalize(example.name)) ||
        RegExp(r'\b(?:bebida|bebidas|postre|postres)\b')
            .hasMatch(resaleNormalize(example.category))) {
      unresolvedSales.add('${example.productId}: ${example.name} (${possible.isEmpty ? 'sin compra equivalente' : 'match ambiguo'})');
    }
  }

  final products = <ResaleProduct>[];
  for (final entry in byKey.entries) {
    final saleLines = mappedExits[entry.key] ?? const <ResaleExit>[];
    final daily = <String, _MutableDay>{};
    for (final p in entry.value) {
      final day = daily.putIfAbsent(p.date, _MutableDay.new);
      day.bought += _units(p)!;
      day.cost += p.lineCost;
    }
    var unproven = 0;
    for (final s in saleLines) {
      if (s.kind == ResaleExitKind.cancellationWithoutDeliveryProof) {
        unproven += s.quantity;
        continue;
      }
      final day = daily.putIfAbsent(s.date, _MutableDay.new);
      if (s.kind == ResaleExitKind.paid) {
        day.sold += s.quantity;
        day.revenue += s.saleAmount;
      } else {
        day.other += s.quantity;
      }
    }
    var balance = 0;
    final days = <ResaleDay>[];
    for (final date in daily.keys.toList()..sort()) {
      final d = daily[date]!;
      balance += d.bought - d.sold - d.other;
      days.add(ResaleDay(date, d.bought, d.sold, d.other, balance, d.cost, d.revenue));
    }
    final relevantCheckpoints = checkpoints.where((c) => c.key == entry.key &&
      c.boundary == 'closing' && c.physicalCount >= 0 &&
      c.date.compareTo(endDate) <= 0).toList()..sort((a,b) => a.date.compareTo(b.date));
    final checkpoint = relevantCheckpoints.isEmpty ? null : relevantCheckpoints.last;
    int? difference;
    if (relevantCheckpoints.length >= 2 && checkpoint!.confirmed &&
        relevantCheckpoints[relevantCheckpoints.length - 2].confirmed) {
      final previous = relevantCheckpoints[relevantCheckpoints.length - 2];
      final expected = previous.physicalCount + days
        .where((d) => d.date.compareTo(previous.date) > 0 &&
            d.date.compareTo(checkpoint.date) <= 0)
        .fold<int>(0, (n, d) => n + d.bought - d.sold - d.other);
      difference = checkpoint.physicalCount - expected;
    }
    products.add(ResaleProduct(key: entry.key, family: families[entry.key]!,
      name: names[entry.key]!,
      suppliers: entry.value.map((p) => p.supplier).toSet().toList()..sort(),
      productIds: saleLines.map((s) => s.productId).toSet().toList()..sort(),
      days: days, lastPurchaseDate: entry.value.map((p) => p.date).reduce(
        (a,b) => a.compareTo(b) > 0 ? a : b),
      initialUnknown: checkpoint?.confirmed != true, checkpoint: checkpoint,
      checkpoints: relevantCheckpoints,
      physicalDifference: difference, unprovenCancellations: unproven));
  }
  products.sort((a,b) => a.name.compareTo(b.name));
  return ResaleAudit(products: products, unmatchedPurchases: unresolvedPurchases,
    unmatchedSales: unresolvedSales, notes: const [
      'Inventario inicial desconocido sin conteo físico: el acumulado es relativo, no un faltante.',
      'Saldo relativo negativo: revisar compras, captura, presentación, match o inventario inicial.',
      'Una cancelación de cocina no demuestra entrega física y no se descuenta.',
      'La relación compras/ventas entre periodos incluye arrastre de inventario.',
      'El histórico de ventas se carga desde la primera compra objetivo registrada; '
        'movimientos anteriores requieren una fecha de inventario inicial verificable.',
    ]);
}

class _MutableDay {
  int bought = 0, sold = 0, other = 0;
  double cost = 0, revenue = 0;
}
