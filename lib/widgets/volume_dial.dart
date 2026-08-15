import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class VolumeDial extends StatelessWidget {
  final double value; // 0.0 - 1.0
  final ValueChanged<double> onChanged;
  final double size;
  final bool enabled;

  /// Size the painter's proportions were designed at; every stroke, the knob
  /// and the label scale off it so smaller dials keep the same look.
  static const double baseSize = 90;

  const VolumeDial({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = baseSize,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    // Drag distance for a full 0→1 sweep scales with the dial, so a small
    // dial doesn't feel sluggish.
    final travel = 150 * (size / baseSize);
    return GestureDetector(
      onVerticalDragUpdate: enabled
          ? (d) => onChanged((value - d.delta.dy / travel).clamp(0.0, 1.0))
          : null,
      onHorizontalDragUpdate: enabled
          ? (d) => onChanged((value + d.delta.dx / travel).clamp(0.0, 1.0))
          : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _DialPainter(value: value)),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final double value;
  _DialPainter({required this.value});

  static const double startAngle = 0.75 * math.pi; // 135°
  static const double sweepMax = 1.5 * math.pi; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / VolumeDial.baseSize;
    final stroke = 8 * k;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10 * k;

    // Track (background arc)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepMax,
      false,
      Paint()
        ..color = AppColors.border
        ..strokeWidth = stroke
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
          ..strokeWidth = stroke
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
      7 * k,
      Paint()..color = AppColors.pinkHighlight,
    );

    // Center value text — explicit font since CustomPainter bypasses theme
    final pct = (value * 100).round();
    final tp = TextPainter(
      text: TextSpan(
        text: '$pct',
        style: TextStyle(
          fontFamily: 'SairaStencilOne',
          color: Colors.white,
          // Floor at 10: the arc scales down fine, the percentage stops being
          // readable well before it does.
          fontSize: (18 * k).clamp(10.0, 18.0),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.value != value;
}
