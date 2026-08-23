import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/remote_state.dart';
import '../providers/remote_provider.dart';

const _stemLabels = {
  'drums': 'Batería',
  'vocals': 'Voz',
  'bass': 'Bajo',
  'other': 'Otros',
};

/// Stem mute buttons, always in reach on the remote screen: muting the voice
/// between songs is the single most used control of the whole app, and it
/// shouldn't cost a trip into a menu. Volumes live one tap deeper, in
/// [showRemoteMixerSheet] — they get set once per rehearsal, not per song.
class RemoteMixerBar extends StatelessWidget {
  final bool compact;

  /// Extra shrink factor for when [compact] alone still doesn't fit
  /// (landscape with the keyboard up). 1.0 = no extra shrink.
  final double scale;

  const RemoteMixerBar({super.key, this.compact = false, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    final remote = context.watch<RemoteProvider>();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: compact ? 3 * scale : 8,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final track in kRemoteTrackNames)
            _StemMuteButton(
              track: track,
              muted: remote.isMuted(track),
              compact: compact,
              scale: scale,
              onTap: () => context.read<RemoteProvider>().toggleStemMute(track),
            ),
          _MixerButton(
            onTap: () => showRemoteMixerSheet(context),
            master: remote.volumeOf(kRemoteMasterTrack),
            compact: compact,
            scale: scale,
          ),
        ],
      ),
    );
  }
}

class _StemMuteButton extends StatelessWidget {
  final String track;
  final bool muted;
  final bool compact;
  final double scale;
  final VoidCallback onTap;

  const _StemMuteButton({
    required this.track,
    required this.muted,
    required this.onTap,
    this.compact = false,
    this.scale = 1.0,
  });

  static const _fullSide = 52.0;
  static const _compactSide = 38.0;

  @override
  Widget build(BuildContext context) {
    final side = compact ? _compactSide * scale : _fullSide;
    return Tooltip(
      message:
          '${_stemLabels[track] ?? track}: ${muted ? "silenciada" : "activa"}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: side,
          height: side,
          padding: EdgeInsets.all(compact ? 5 * scale : 7),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: muted
                ? null
                : const LinearGradient(
                    colors: [AppColors.accentPurple, AppColors.gradientA],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            border: Border.all(
              color: muted ? AppColors.border : AppColors.accentPurple,
              width: 2,
            ),
          ),
          child: Image.asset(
            muted ? 'assets/icons/no_$track.png' : 'assets/icons/$track.png',
            cacheWidth: (side * MediaQuery.devicePixelRatioOf(context))
                .round(),
          ),
        ),
      ),
    );
  }
}

class _MixerButton extends StatelessWidget {
  final VoidCallback onTap;
  final int master;
  final bool compact;
  final double scale;

  const _MixerButton({
    required this.onTap,
    required this.master,
    this.compact = false,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final side = compact ? 38.0 * scale : 52.0;
    return Tooltip(
      message: 'Volúmenes',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: side,
          height: side,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: AppColors.accentBlue),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.tune,
                color: AppColors.accentBlue,
                size: compact ? 15 * scale : 20,
              ),
              Text(
                '$master',
                style: TextStyle(
                  color: AppColors.accentBlue,
                  fontSize: compact ? 9 * scale : 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Master + per-stem volume sliders for the PC.
///
/// The provider is passed down explicitly: the sheet is built by the root
/// navigator, outside the remote screen's own provider scope.
Future<void> showRemoteMixerSheet(BuildContext context) {
  final remote = context.read<RemoteProvider>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.black,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => ChangeNotifierProvider<RemoteProvider>.value(
      value: remote,
      child: const _MixerSheet(),
    ),
  );
}

class _MixerSheet extends StatelessWidget {
  const _MixerSheet();

  @override
  Widget build(BuildContext context) {
    final remote = context.watch<RemoteProvider>();

    // Losing the connection while the sheet is open leaves controls that
    // command nothing; close instead of pretending.
    if (!remote.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, color: AppColors.accentBlue),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Mezcla en la PC',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.border),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _VolumeRow(
              label: 'General',
              track: kRemoteMasterTrack,
              value: remote.volumeOf(kRemoteMasterTrack),
              icon: const Icon(
                Icons.volume_up,
                color: AppColors.accentBlue,
                size: 26,
              ),
            ),
            const Divider(color: AppColors.border, height: 20),
            for (final track in kRemoteTrackNames)
              _VolumeRow(
                label: _stemLabels[track] ?? track,
                track: track,
                value: remote.volumeOf(track),
                muted: remote.isMuted(track),
                icon: Image.asset(
                  remote.isMuted(track)
                      ? 'assets/icons/no_$track.png'
                      : 'assets/icons/$track.png',
                  width: 26,
                  height: 26,
                ),
                onIconTap: () =>
                    context.read<RemoteProvider>().toggleStemMute(track),
              ),
            const Divider(color: AppColors.border, height: 20),
            _AutoUnmuteRow(enabled: remote.autoUnmuteEnabled),
          ],
        ),
      ),
    );
  }
}

/// Toggles the desktop's vocals auto-unmute — same feature as the badge on
/// the vocals stem button locally, mirrored here since the phone has no
/// audio engine of its own to read the lyric line from.
class _AutoUnmuteRow extends StatelessWidget {
  final bool enabled;

  const _AutoUnmuteRow({required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Center(
            child: Icon(
              enabled ? Icons.record_voice_over : Icons.voice_over_off,
              color: enabled ? AppColors.accentBlue : Colors.grey,
              size: 22,
            ),
          ),
        ),
        const Expanded(
          child: Text(
            'Auto-unmute',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        Switch(
          value: enabled,
          activeTrackColor: AppColors.accentPurple,
          onChanged: (_) =>
              context.read<RemoteProvider>().toggleAutoUnmute(),
        ),
      ],
    );
  }
}

class _VolumeRow extends StatelessWidget {
  final String label;
  final String track;
  final int value;
  final bool muted;
  final Widget icon;
  final VoidCallback? onIconTap;

  const _VolumeRow({
    required this.label,
    required this.track,
    required this.value,
    required this.icon,
    this.muted = false,
    this.onIconTap,
  });

  @override
  Widget build(BuildContext context) {
    final remote = context.read<RemoteProvider>();
    return Row(
      children: [
        GestureDetector(
          onTap: onIconTap,
          child: SizedBox(width: 34, child: Center(child: icon)),
        ),
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: TextStyle(
              color: muted ? AppColors.border : Colors.white,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            activeColor: muted ? AppColors.border : AppColors.accentPurple,
            inactiveColor: AppColors.border.withValues(alpha: 0.4),
            // Every drag pixel goes to the provider, which debounces the POST
            // and holds the shown value until the PC catches up.
            onChanged: (v) => remote.setVolume(track, v.round()),
            onChangeEnd: (_) => remote.commitVolume(track),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '$value',
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
