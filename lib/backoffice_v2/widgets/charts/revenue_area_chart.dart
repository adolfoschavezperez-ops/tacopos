import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../features/dashboard/dashboard_repository.dart';

/// Smooth Bezier area + line chart with interactive hover/tap tooltip.
class RevenueAreaChart extends StatefulWidget {
  const RevenueAreaChart({super.key, required this.series});

  final List<DailyRevenuePoint> series;

  @override
  State<RevenueAreaChart> createState() => _RevenueAreaChartState();
}

class _RevenueAreaChartState extends State<RevenueAreaChart> {
  int? _hoveredIndex;

  List<DailyRevenuePoint> _bucketize(List<DailyRevenuePoint> raw) {
    if (raw.length <= 14) return raw;
    final bucketSize = (raw.length / 12).ceil();
    final out = <DailyRevenuePoint>[];
    for (var i = 0; i < raw.length; i += bucketSize) {
      final slice = raw.sublist(i, math.min(i + bucketSize, raw.length));
      final sum = slice.fold<double>(0, (acc, p) => acc + p.netSales);
      final count = slice.fold<int>(0, (acc, p) => acc + p.ordersCount);
      final label = slice.length == 1
          ? slice.first.businessDate
          : '${slice.first.businessDate.substring(5)} — ${slice.last.businessDate.substring(5)}';
      out.add(
        DailyRevenuePoint(
          businessDate: label,
          netSales: sum,
          ordersCount: count,
        ),
      );
    }
    return out;
  }

  void _updateHover(Offset localPos, double width, int count) {
    if (count <= 0 || width <= 0) return;
    final step = count == 1 ? width : width / (count - 1);
    final idx = count == 1 ? 0 : (localPos.dx / step).round().clamp(0, count - 1);
    if (_hoveredIndex != idx) {
      setState(() => _hoveredIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final points = _bucketize(widget.series);
    if (points.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(child: Text('Sin ventas registradas en este periodo')),
      );
    }

    final activeIdx = _hoveredIndex != null && _hoveredIndex! < points.length
        ? _hoveredIndex!
        : points.length - 1;
    final activePoint = points[activeIdx];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Interactive readout bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: tokens.surfaceSubtle,
            borderRadius: BorderRadius.circular(BackofficeSpacing.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: tokens.brandAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    activePoint.businessDate,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    BackofficeSalesAdapter.formatMoney(activePoint.netSales),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${activePoint.ordersCount} órdenes',
                    style: TextStyle(fontSize: 12, color: tokens.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 196,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return MouseRegion(
                onHover: (e) => _updateHover(
                  e.localPosition,
                  constraints.maxWidth,
                  points.length,
                ),
                onExit: (_) => setState(() => _hoveredIndex = null),
                child: GestureDetector(
                  onTapDown: (d) => _updateHover(
                    d.localPosition,
                    constraints.maxWidth,
                    points.length,
                  ),
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 196),
                    painter: _AreaPainter(
                      points: points,
                      activeIndex: activeIdx,
                      accent: tokens.brandAccent,
                      amber: tokens.brandAmber,
                      gridColor: tokens.border,
                      dotCenter: tokens.surface,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _shortLabel(points.first.businessDate),
              style: TextStyle(fontSize: 11, color: tokens.textMuted),
            ),
            if (points.length > 2)
              Text(
                _shortLabel(points[points.length ~/ 2].businessDate),
                style: TextStyle(fontSize: 11, color: tokens.textMuted),
              ),
            Text(
              _shortLabel(points.last.businessDate),
              style: TextStyle(fontSize: 11, color: tokens.textMuted),
            ),
          ],
        ),
      ],
    );
  }

  String _shortLabel(String s) {
    if (s.length == 10 && s.contains('-')) return s.substring(5);
    return s;
  }
}

class _AreaPainter extends CustomPainter {
  const _AreaPainter({
    required this.points,
    required this.activeIndex,
    required this.accent,
    required this.amber,
    required this.gridColor,
    required this.dotCenter,
  });

  final List<DailyRevenuePoint> points;
  final int activeIndex;
  final Color accent;
  final Color amber;
  final Color gridColor;
  final Color dotCenter;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final ratio in [0.15, 0.45, 0.75, 0.96]) {
      final y = size.height * ratio;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final maxVal = points.fold<double>(
      1,
      (prev, e) => math.max(prev, e.netSales),
    );
    final coords = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? size.width / 2
          : (i / (points.length - 1)) * size.width;
      final norm = (points[i].netSales / maxVal).clamp(0.0, 1.0);
      final y = size.height - (norm * (size.height - 24) + 12);
      coords.add(Offset(x, y));
    }

    if (coords.length == 1) {
      canvas.drawCircle(coords.first, 6, Paint()..color = accent);
      return;
    }

    final path = Path()..moveTo(coords.first.dx, coords.first.dy);
    for (var i = 0; i < coords.length - 1; i++) {
      final p0 = coords[i];
      final p1 = coords[i + 1];
      final midX = (p0.dx + p1.dx) / 2;
      path.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    final fill = Path.from(path)
      ..lineTo(coords.last.dx, size.height)
      ..lineTo(coords.first.dx, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent.withValues(alpha: 0.24), accent.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [amber, accent],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );

    // Active vertical guide + glowing marker
    final active = coords[activeIndex];
    canvas.drawLine(
      Offset(active.dx, 0),
      Offset(active.dx, size.height),
      Paint()
        ..color = accent.withValues(alpha: 0.25)
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(
      active,
      8,
      Paint()..color = accent.withValues(alpha: 0.22),
    );
    canvas.drawCircle(active, 4.5, Paint()..color = accent);
    canvas.drawCircle(active, 2.2, Paint()..color = dotCenter);
  }

  @override
  bool shouldRepaint(covariant _AreaPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.activeIndex != activeIndex;
}
