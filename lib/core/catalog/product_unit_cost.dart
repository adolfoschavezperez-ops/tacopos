class ProductUnitCostParseResult {
  const ProductUnitCostParseResult._(this.value, this.error);

  const ProductUnitCostParseResult.valid(double? value) : this._(value, null);

  const ProductUnitCostParseResult.invalid(String error) : this._(null, error);

  final double? value;
  final String? error;

  bool get isValid => error == null;
}

ProductUnitCostParseResult parseProductUnitCostInput(String input) {
  final clean = input.trim();
  if (clean.isEmpty) {
    return const ProductUnitCostParseResult.valid(null);
  }

  final normalized = clean.replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(normalized)) {
    return const ProductUnitCostParseResult.invalid(
      'El costo unitario debe ser un numero positivo con maximo 2 decimales.',
    );
  }

  final parsed = double.tryParse(normalized);
  if (parsed == null || !parsed.isFinite) {
    return const ProductUnitCostParseResult.invalid(
      'El costo unitario debe ser un numero valido.',
    );
  }

  return ProductUnitCostParseResult.valid(
    double.parse(parsed.toStringAsFixed(2)),
  );
}

String formatProductUnitCostInput(double? value) {
  return value == null ? '' : value.toStringAsFixed(2);
}

String productUnitCostLabel(double? value) {
  return value == null ? 'Sin costo' : '\$${value.toStringAsFixed(2)}';
}
