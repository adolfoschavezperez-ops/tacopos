import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/design/design_tokens.dart';
import 'status_pill.dart';

/// Protagonist dark-graphite Hero KPI Card for Net Sales.
class HeroRevenueCard extends StatelessWidget {
  const HeroRevenueCard({
    super.key,
    required this.title,
    required this.amountText,
    required this.subtitle,
    required this.sparkValues,
    this.deltaLabel,
    this.deltaPositive,
    this.statusLabel,
    this.statusPositive = true,
  });

  final String title;
  final String amountText;
  final String subtitle;
  final List<double> sparkValues;
  final String? deltaLabel;
  final bool? deltaPositive;
  final String? statusLabel;
  final bool statusPositive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BackofficeSpacing.radiusLg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF111318), Color(0xFF1B1F28)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFF97316).withValues(alpha: 0.22),
                    const Color(0xFFF97316).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF97316).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFF97316).withValues(alpha: 0.30),
                      ),
                    ),
                    child: const Icon(
                      Icons.payments_outlined,
                      size: 16,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFFAFAF9).withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                  if (statusLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: (statusPositive
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444))
                            .withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusPositive
                              ? const Color(0xFF34D399)
                              : const Color(0xFFFCA5A5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: Text(
                                amountText,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.7,
                                  color: Color(0xFFFAFAF9),
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'MXN',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFFAFAF9)
                                    .withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (deltaLabel != null)
                              StatusPill(
                                label: deltaLabel!,
                                tone: switch (deltaPositive) {
                                  true => StatusTone.success,
                                  false => StatusTone.danger,
                                  null => StatusTone.neutral,
                                },
                              ),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: const Color(0xFFFAFAF9)
                                    .withValues(alpha: 0.62),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (sparkValues.length >= 2) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 86,
                      height: 42,
                      child: CustomPaint(
                        painter: _MiniSparkPainter(
                          values: sparkValues,
                          color: const Color(0xFFF97316),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Refined KPI card with tinted icon badge, delta pill, and optional sparkline.
class KpiSparkCard extends StatelessWidget {
  const KpiSparkCard({
    super.key,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    this.deltaLabel,
    this.deltaPositive,
    this.sparkValues = const [],
  });

  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final String? deltaLabel;
  final bool? deltaPositive;
  final List<double> sparkValues;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(BackofficeSpacing.radiusLg),
        border: Border.all(color: tokens.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: tokens.isDark ? 0.22 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: tokens.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (deltaLabel != null)
                StatusPill(
                  label: deltaLabel!,
                  tone: switch (deltaPositive) {
                    true => StatusTone.success,
                    false => StatusTone.danger,
                    null => StatusTone.neutral,
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: tokens.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: tokens.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (sparkValues.length >= 2) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 64,
                  height: 32,
                  child: CustomPaint(
                    painter: _MiniSparkPainter(
                      values: sparkValues,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniSparkPainter extends CustomPainter {
  const _MiniSparkPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minVal = values.reduce(math.min);
    final maxVal = values.reduce(math.max);
    final range = (maxVal - minVal).abs() < 0.001 ? 1.0 : (maxVal - minVal);

    final pts = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final norm = (values[i] - minVal) / range;
      final y = size.height - (norm * (size.height - 6) + 3);
      pts.add(Offset(x, y));
    }

    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final midX = (pts[i].dx + pts[i + 1].dx) / 2;
      line.cubicTo(midX, pts[i].dy, midX, pts[i + 1].dy, pts[i + 1].dx, pts[i + 1].dy);
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniSparkPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
