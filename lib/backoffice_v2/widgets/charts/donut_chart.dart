import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';

class DonutSlice {
  const DonutSlice({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;
}

class PaymentDonutChart extends StatelessWidget {
  const PaymentDonutChart({
    super.key,
    required this.slices,
    required this.totalAmount,
  });

  final List<DonutSlice> slices;
  final double totalAmount;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final activeSlices = slices.where((s) => s.amount > 0).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 340;
        final chart = SizedBox(
          width: 148,
          height: 148,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(148, 148),
                painter: _DonutPainter(
                  slices: activeSlices,
                  total: totalAmount,
                  emptyColor: tokens.surfaceSubtle,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total cobrado',
                    style: TextStyle(fontSize: 10.5, color: tokens.textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    BackofficeSalesAdapter.formatMoney(totalAmount),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        final legend = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: slices.map((slice) {
            final pct = totalAmount <= 0
                ? '0.0%'
                : '${((slice.amount / totalAmount) * 100).toStringAsFixed(1)}%';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: slice.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      slice.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    BackofficeSalesAdapter.formatMoney(slice.amount),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 42,
                    child: Text(
                      pct,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: tokens.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );

        if (compact) {
          return Column(
            children: [
              chart,
              const SizedBox(height: 16),
              legend,
            ],
          );
        }

        return Row(
          children: [
            chart,
            const SizedBox(width: 20),
            Expanded(child: legend),
          ],
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.slices,
    required this.total,
    required this.emptyColor,
  });

  final List<DonutSlice> slices;
  final double total;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: size.width / 2 - 12,
    );
    const stroke = 18.0;

    if (total <= 0 || slices.isEmpty) {
      canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = emptyColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      return;
    }

    var startAngle = -math.pi / 2;
    const gap = 0.04;
    for (final slice in slices) {
      final sweep = (slice.amount / total) * (math.pi * 2);
      final drawSweep = math.max(0.02, sweep - (slices.length > 1 ? gap : 0));
      canvas.drawArc(
        rect,
        startAngle,
        drawSweep,
        false,
        Paint()
          ..color = slice.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.total != total;
}
