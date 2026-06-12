import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

class ProgressBarWidget extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final bool enabled;
  final ValueChanged<Duration> onSeek;

  const ProgressBarWidget({
    super.key,
    required this.position,
    required this.duration,
    required this.enabled,
    required this.onSeek,
  });

  @override
  State<ProgressBarWidget> createState() => _ProgressBarWidgetState();
}

class _ProgressBarWidgetState extends State<ProgressBarWidget> {
  /// While dragging, the slider tracks this local value; the engine seek
  /// (4 voices) fires once on release instead of on every drag frame.
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds.toDouble();
    final current =
        _dragValue ??
        widget.position.inMilliseconds.toDouble().clamp(
          0.0,
          total > 0 ? total : 1.0,
        );
    final shown = Duration(milliseconds: current.round());

    return Column(
      children: [
        Text(
          '${_fmt(shown)} / ${_fmt(widget.duration)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 12,
            activeTrackColor: AppColors.accentPurple,
            inactiveTrackColor: AppColors.progressInactive,
            thumbColor: Colors.white,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            overlayColor: AppColors.pinkHighlight.withValues(alpha: 0.3),
          ),
          child: Slider(
            value: current,
            min: 0,
            max: total > 0 ? total : 1,
            onChanged: widget.enabled
                ? (v) => setState(() => _dragValue = v)
                : null,
            onChangeEnd: widget.enabled
                ? (v) {
                    setState(() => _dragValue = null);
                    widget.onSeek(Duration(milliseconds: v.round()));
                  }
                : null,
          ),
        ),
      ],
    );
  }
}
