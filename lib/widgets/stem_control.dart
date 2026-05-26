import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class StemControl extends StatelessWidget {
  final String name; // 'drums', 'vocals', 'bass', 'other'
  final bool muted;
  final double volume; // 0.0 - 1.0
  final bool enabled;
  final VoidCallback onMuteToggle;
  final ValueChanged<double> onVolumeChanged;

  const StemControl({
    super.key,
    required this.name,
    required this.muted,
    required this.volume,
    required this.enabled,
    required this.onMuteToggle,
    required this.onVolumeChanged,
  });

  String get _iconAsset => muted
      ? 'assets/icons/no_$name.png'
      : 'assets/icons/$name.png';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: enabled ? onMuteToggle : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: muted
                  ? null
                  : const LinearGradient(
                      colors: [AppColors.accentPurple, AppColors.gradientA],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              color: muted ? Colors.transparent : null,
              border: Border.all(
                color: muted ? AppColors.border : AppColors.accentPurple,
                width: 2,
              ),
            ),
            padding: const EdgeInsets.all(6),
            child: Image.asset(
              _iconAsset,
              width: 48,
              height: 48,
              color: enabled ? null : Colors.grey.withValues(alpha: 0.4),
            ),
          ),
        ),
        const SizedBox(height: 6),
        RotatedBox(
          quarterTurns: 3,
          child: SizedBox(
            width: 70,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: AppColors.accentPurple,
                inactiveTrackColor: AppColors.progressInactive,
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: volume,
                onChanged: enabled ? onVolumeChanged : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
