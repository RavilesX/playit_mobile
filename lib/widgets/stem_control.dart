import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class StemControl extends StatelessWidget {
  final String name; // 'drums', 'vocals', 'bass', 'other'
  final bool muted;
  final bool enabled;
  final VoidCallback onMuteToggle;

  /// Vocals-only: whether auto-unmute is enabled, and its toggle. Null for
  /// every other stem (no badge shown).
  final bool? autoUnmuteEnabled;
  final VoidCallback? onAutoUnmuteToggle;

  const StemControl({
    super.key,
    required this.name,
    required this.muted,
    required this.enabled,
    required this.onMuteToggle,
    this.autoUnmuteEnabled,
    this.onAutoUnmuteToggle,
  });

  String get _iconAsset =>
      muted ? 'assets/icons/no_$name.png' : 'assets/icons/$name.png';

  @override
  Widget build(BuildContext context) {
    // scaleDown keeps the fixed-size icon from overflowing tight rows
    // (small phones, landscape)
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Stack(
        clipBehavior: Clip.none,
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
                cacheWidth: (48 * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                color: enabled ? null : Colors.grey.withValues(alpha: 0.4),
              ),
            ),
          ),
          if (autoUnmuteEnabled != null)
            Positioned(
              right: -4,
              top: -4,
              child: GestureDetector(
                onTap: enabled ? onAutoUnmuteToggle : null,
                child: Tooltip(
                  message:
                      'Auto-unmute: deja oír la voz en los tramos sin letra',
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.85),
                      border: Border.all(
                        color: autoUnmuteEnabled!
                            ? AppColors.accentBlue
                            : AppColors.border,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      autoUnmuteEnabled!
                          ? Icons.record_voice_over
                          : Icons.voice_over_off,
                      size: 14,
                      color: autoUnmuteEnabled!
                          ? AppColors.accentBlue
                          : Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
