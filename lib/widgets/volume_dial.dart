import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

class VolumeDial extends StatelessWidget {
  final double value; // 0.0 - 1.0
  final ValueChanged<double> onChanged;
  final double size;

  const VolumeDial({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 90,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (d) {
        final newVal = (value - d.delta.dy / 150).clamp(0.0, 1.0);
        onChanged(newVal);
      },
      onHorizontalDragUpdate: (d) {
        final newVal = (value + d.delta.dx / 150).clamp(0.0, 1.0);
        onChanged(newVal);
      },
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _DialPainter(value: value),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final double value;
  _DialPainter({required this.value});

  static const double startAngle = 0.75 * math.pi; // 135°
  static const double sweepMax = 1.5 * math.pi;    // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Track (background arc)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepMax,
      false,
      Paint()
        ..color = AppColors.border
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Active arc. LinearGradient on the bounding rect avoids all SweepGradient
    // angle-wrapping issues that appear above ~83% value.
    final sweepAngle = sweepMax * value;
    if (sweepAngle > 0.01) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        false,
        Paint()
          ..shader = const LinearGradient(
            colors: [AppColors.accentPurple, AppColors.accentBlue],
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
          ).createShader(rect)
          ..strokeWidth = 8
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // Knob dot at current angle (original coordinate space)
    final theta = startAngle + sweepAngle;
    final knobX = center.dx + radius * math.cos(theta);
    final knobY = center.dy + radius * math.sin(theta);
    canvas.drawCircle(
      Offset(knobX, knobY),
      7,
      Paint()..color = AppColors.pinkHighlight,
    );

    // Center value text — explicit font since CustomPainter bypasses theme
    final pct = (value * 100).round();
    final tp = TextPainter(
      text: TextSpan(
        text: '$pct',
        style: GoogleFonts.sairaStencilOne(
          color: Colors.white,
          fontSize: 18,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.value != value;
}
