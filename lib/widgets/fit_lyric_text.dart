import 'package:flutter/material.dart';
import '../models/lrc_line.dart';
import '../utils/lyric_colors.dart';

/// Renders the current lyric line, shrinking [fontSize] just enough for it
/// to fit the space it's given — never scaling up past it, since that's
/// already the user's chosen size (base size × pinch-zoom).
///
/// A plain [FittedBox] can't do this correctly: it measures its child at
/// unbounded width, which collapses word-wrap onto one line before scaling,
/// producing a different (often worse) fit than shrinking a normally-
/// wrapped block. This measures with [TextPainter] at the real width so
/// wrapping stays intact.
class FitLyricText extends StatelessWidget {
  final LrcLine line;
  final double fontSize;
  final bool isCurrent;

  const FitLyricText({
    super.key,
    required this.line,
    required this.fontSize,
    required this.isCurrent,
  });

  /// Below this, a lyric line is unreadable anyway — better to let it
  /// clip slightly than shrink to nothing.
  static const _minFontSize = 10.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final size = (maxWidth.isFinite && maxHeight.isFinite)
            ? _fitFontSize(
                context: context,
                maxWidth: maxWidth,
                maxHeight: maxHeight,
              )
            : fontSize;
        return Text.rich(
          lyricLineSpan(line, size, isCurrent: isCurrent),
          textAlign: TextAlign.center,
        );
      },
    );
  }

  bool _fits(BuildContext context, double size, double maxWidth, double maxHeight) {
    final painter = TextPainter(
      text: lyricLineSpan(line, size, isCurrent: isCurrent),
      textAlign: TextAlign.center,
      textDirection: Directionality.of(context),
    )..layout(maxWidth: maxWidth);
    return painter.height <= maxHeight;
  }

  double _fitFontSize({
    required BuildContext context,
    required double maxWidth,
    required double maxHeight,
  }) {
    if (_fits(context, fontSize, maxWidth, maxHeight)) return fontSize;
    if (!_fits(context, _minFontSize, maxWidth, maxHeight)) return _minFontSize;

    var lo = _minFontSize;
    var hi = fontSize;
    for (var i = 0; i < 8; i++) {
      final mid = (lo + hi) / 2;
      if (_fits(context, mid, maxWidth, maxHeight)) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
