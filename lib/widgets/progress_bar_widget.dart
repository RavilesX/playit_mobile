import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

class ProgressBarWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds.toDouble();
    final current = position.inMilliseconds.toDouble().clamp(0.0, total > 0 ? total : 1.0);

    return Column(
      children: [
        Text(
          '${_fmt(position)} / ${_fmt(duration)}',
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
            onChanged: enabled
                ? (v) => onSeek(Duration(milliseconds: v.round()))
                : null,
          ),
        ),
      ],
    );
  }
}
