import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import 'tacopos_brand_mark.dart';

/// Left-hand 55% atmospheric dark showcase panel for the Login screen.
///
/// Uses purely illustrative static metrics and lightweight CustomPainters
/// (zero Firestore reads) to establish a Stripe / Linear / Vercel SaaS aesthetic.
class LoginShowcasePanel extends StatefulWidget {
  const LoginShowcasePanel({super.key});

  @override
  State<LoginShowcasePanel> createState() => _LoginShowcasePanelState();
}

class _LoginShowcasePanelState extends State<LoginShowcasePanel>
    with SingleTickerProviderStateMixin {
  AnimationController? _ambientController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations) {
      _ambientController?.dispose();
      _ambientController = null;
    } else {
      _ambientController ??= AnimationController(
        vsync: this,
        duration: const Duration(seconds: 6),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ambientController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF111318)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Ambient orange/amber radial lighting
          Positioned(
            top: -140,
            left: -100,
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFF97316).withValues(alpha: 0.18),
                    const Color(0xFFF97316).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -160,
            right: -80,
            child: Container(
              width: 480,
              height: 480,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    const Color(0xFFF59E0B).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Subtle architectural dot grid
          Positioned.fill(
            child: CustomPaint(painter: _DotGridPainter()),
          ),
          // Foreground composition
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const TacoPosBrandMark(size: 34, showWordmark: true),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540),
                    child: _FloatingDashboardPreview(
                      animation: _ambientController,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tu restaurante, bajo control.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: [
                            'Segoe UI',
                            'Roboto',
                            'sans-serif',
                          ],
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.9,
                          height: 1.12,
                          color: Color(0xFFFAFAF9),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Ventas, operación y finanzas. Todo tu negocio en un solo lugar.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const [
                            'Segoe UI',
                            'Roboto',
                            'sans-serif',
                          ],
                          fontSize: 15,
                          height: 1.5,
                          color: const Color(0xFFFAFAF9).withValues(alpha: 0.68),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingDashboardPreview extends StatelessWidget {
  const _FloatingDashboardPreview({required this.animation});

  final Animation<double>? animation;

  @override
  Widget build(BuildContext context) {
    final anim = animation ?? const AlwaysStoppedAnimation<double>(0.5);

    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        final floatOffset = math.sin(anim.value * math.pi) * 4.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              height: 332,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Layer 1: Main Revenue Card
                  Positioned(
                    left: 0,
                    right: 36,
                    top: 24,
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1E25),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.09),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 32,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF111318),
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.1),
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.asset(
                                  AppConstants.logoAsset,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.storefront_rounded,
                                    size: 14,
                                    color: Color(0xFFF59E0B),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Ventas del día',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFFFAFAF9)
                                      .withValues(alpha: 0.72),
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: const Color(0xFF10B981)
                                        .withValues(alpha: 0.30),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.trending_up_rounded,
                                      size: 13,
                                      color: Color(0xFF34D399),
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      '+18.4%',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF34D399),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              const Text(
                                '\$38,420.00',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.8,
                                  color: Color(0xFFFAFAF9),
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'MXN',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFFAFAF9)
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 116,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _RevenueCurvePainter(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Layer 2: Overlapping Orders KPI Card (top-right)
                  Positioned(
                    right: 0,
                    top: 0 + floatOffset * 0.6,
                    child: Container(
                      width: 196,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF222630),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF97316),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Órdenes hoy',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFFFAFAF9)
                                      .withValues(alpha: 0.68),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '142',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                              color: Color(0xFFFAFAF9),
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ticket prom. \$270.56',
                            style: TextStyle(
                              fontSize: 11,
                              color: const Color(0xFFFAFAF9)
                                  .withValues(alpha: 0.50),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Layer 3: Overlapping Payment Mix Card (bottom-right)
                  Positioned(
                    right: 8,
                    bottom: 0 - floatOffset * 0.5,
                    child: Container(
                      width: 268,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF181B22),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.11),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.50),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Métodos de pago',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFFAFAF9)
                                  .withValues(alpha: 0.78),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: const SizedBox(
                              height: 7,
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 44,
                                    child: ColoredBox(color: Color(0xFF10B981)),
                                  ),
                                  SizedBox(width: 2),
                                  Expanded(
                                    flex: 38,
                                    child: ColoredBox(color: Color(0xFF3B82F6)),
                                  ),
                                  SizedBox(width: 2),
                                  Expanded(
                                    flex: 18,
                                    child: ColoredBox(color: Color(0xFFF97316)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              _LegendDot(
                                color: Color(0xFF10B981),
                                label: 'Efectivo 44%',
                              ),
                              _LegendDot(
                                color: Color(0xFF3B82F6),
                                label: 'Tarjeta 38%',
                              ),
                              _LegendDot(
                                color: Color(0xFFF97316),
                                label: 'Apps 18%',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Vista previa ilustrativa',
                style: TextStyle(
                  fontSize: 11,
                  color: const Color(0xFFFAFAF9).withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: const Color(0xFFFAFAF9).withValues(alpha: 0.65),
          ),
        ),
      ],
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    const step = 28.0;
    for (double x = 14; x < size.width; x += step) {
      for (double y = 14; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RevenueCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (final ratio in [0.25, 0.55, 0.85]) {
      final y = size.height * ratio;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final points = [
      Offset(0, size.height * 0.78),
      Offset(size.width * 0.16, size.height * 0.64),
      Offset(size.width * 0.32, size.height * 0.70),
      Offset(size.width * 0.50, size.height * 0.44),
      Offset(size.width * 0.68, size.height * 0.50),
      Offset(size.width * 0.84, size.height * 0.25),
      Offset(size.width, size.height * 0.14),
    ];

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final midX = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFF97316).withValues(alpha: 0.30),
          const Color(0xFFF97316).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    final strokePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFF59E0B), Color(0xFFF97316)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, strokePaint);

    // Glowing endpoint
    final last = points.last;
    canvas.drawCircle(
      last,
      7,
      Paint()..color = const Color(0xFFF97316).withValues(alpha: 0.30),
    );
    canvas.drawCircle(
      last,
      3.5,
      Paint()..color = const Color(0xFFFAFAF9),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
