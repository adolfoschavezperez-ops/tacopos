import 'package:flutter/material.dart';

/// Custom vector brand mark for TacoPOS (RenovaDev SaaS).
class TacoPosBrandMark extends StatelessWidget {
  const TacoPosBrandMark({
    super.key,
    this.size = 34,
    this.showWordmark = true,
    this.lightText = true,
  });

  final double size;
  final bool showWordmark;
  final bool lightText;

  @override
  Widget build(BuildContext context) {
    final textColor = lightText
        ? const Color(0xFFFAFAF9)
        : const Color(0xFF111318);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF97316), Color(0xFFF59E0B)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF97316).withValues(alpha: 0.32),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: CustomPaint(
            painter: _EmblemPainter(),
          ),
        ),
        if (showWordmark) ...[
          const SizedBox(width: 11),
          Text(
            'TacoPOS',
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['Segoe UI', 'Roboto', 'sans-serif'],
              fontSize: size * 0.56,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: textColor,
            ),
          ),
        ],
      ],
    );
  }
}

class _EmblemPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Stylized geometric Taco/Apex + POS bar mark
    final arcPath = Path()
      ..moveTo(w * 0.24, h * 0.60)
      ..quadraticBezierTo(w * 0.50, h * 0.22, w * 0.76, h * 0.60)
      ..close();
    canvas.drawPath(arcPath, paint);

    // Subtle rising analytics bar accent inside
    final barPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.30, h * 0.74),
      Offset(w * 0.70, h * 0.74),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
