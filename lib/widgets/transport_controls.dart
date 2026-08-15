import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/audio_engine.dart';

class TransportControls extends StatelessWidget {
  final PlaybackStatus status;
  final bool hasPlaylist;
  final bool hasCurrentSong;
  final bool repeatMode;
  final VoidCallback onPrev;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onStop;
  final VoidCallback onRepeatToggle;
  final VoidCallback? onSeekBack;
  final VoidCallback? onSeekForward;

  const TransportControls({
    super.key,
    required this.status,
    required this.hasPlaylist,
    required this.hasCurrentSong,
    required this.repeatMode,
    required this.onPrev,
    required this.onPlayPause,
    required this.onNext,
    required this.onStop,
    required this.onRepeatToggle,
    this.onSeekBack,
    this.onSeekForward,
  });

  @override
  Widget build(BuildContext context) {
    final active = hasPlaylist;
    final canStop = hasCurrentSong;
    final canSeek = hasCurrentSong && status != PlaybackStatus.stopped;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _TransportBtn(
          asset: 'assets/icons/prev.png',
          size: 40,
          enabled: active,
          onTap: onPrev,
        ),
        const SizedBox(width: 8),
        _TransportIconBtn(
          icon: Icons.replay_5,
          size: 34,
          enabled: canSeek,
          onTap: onSeekBack,
        ),
        const SizedBox(width: 8),
        _TransportBtn(
          asset: 'assets/icons/play.png',
          size: 70,
          enabled: active,
          onTap: onPlayPause,
          highlight: true,
        ),
        const SizedBox(width: 8),
        _TransportIconBtn(
          icon: Icons.forward_5,
          size: 34,
          enabled: canSeek,
          onTap: onSeekForward,
        ),
        const SizedBox(width: 8),
        _TransportBtn(
          asset: 'assets/icons/next.png',
          size: 40,
          enabled: active,
          onTap: onNext,
        ),
        const SizedBox(width: 8),
        _TransportBtn(
          asset: 'assets/icons/stop.png',
          size: 40,
          enabled: canStop,
          onTap: onStop,
        ),
        const SizedBox(width: 8),
        _TransportBtn(
          asset: repeatMode
              ? 'assets/icons/repeat_on.png'
              : 'assets/icons/repeat.png',
          size: 40,
          enabled: true,
          onTap: onRepeatToggle,
          active: repeatMode,
        ),
      ],
    );
  }
}

class _TransportIconBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool enabled;
  final VoidCallback? onTap;

  const _TransportIconBtn({
    required this.icon,
    required this.size,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: enabled ? 0.08 : 0.0),
          border: Border.all(
            color: enabled ? AppColors.accentPurple : AppColors.border,
          ),
        ),
        child: Icon(
          icon,
          size: size * 0.55,
          color: enabled
              ? Colors.white
              : Colors.grey.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

class _TransportBtn extends StatelessWidget {
  final String asset;
  final double size;
  final bool enabled;
  final VoidCallback onTap;
  final bool highlight;
  final bool active;

  const _TransportBtn({
    required this.asset,
    required this.size,
    required this.enabled,
    required this.onTap,
    this.highlight = false,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? (highlight || active
                    ? AppColors.accentPurple.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.08))
              : Colors.transparent,
          border: Border.all(
            color: active
                ? AppColors.accentBlue
                : (enabled ? AppColors.accentPurple : AppColors.border),
            width: (highlight || active) ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(highlight ? 10 : 8),
          child: Opacity(
            opacity: enabled ? 1.0 : 0.35,
            child: Image.asset(
              asset,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                  .round(),
            ),
          ),
        ),
      ),
    );
  }
}
