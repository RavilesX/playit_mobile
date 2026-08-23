import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../providers/player_provider.dart';
import '../services/audio_engine.dart';

const _stemLabels = {
  'drums': 'Batería',
  'vocals': 'Voz',
  'bass': 'Bajo',
  'other': 'Otros',
};

/// Opens the four stems' volume as sliders in a sheet, instead of the
/// circular dial each stem used to carry around under its mute icon —
/// same trade the remote mixer already makes, and it frees up the row for
/// cover/lyrics. Master volume keeps its own dial on the main screen.
class StemMixerButton extends StatelessWidget {
  const StemMixerButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Mezcla de pistas',
      child: GestureDetector(
        onTap: () => showStemMixerSheet(context),
        child: Container(
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: AppColors.accentBlue, width: 2),
          ),
          child: const Icon(Icons.tune, color: AppColors.accentBlue),
        ),
      ),
    );
  }
}

Future<void> showStemMixerSheet(BuildContext context) {
  final provider = context.read<PlayerProvider>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.black,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => ChangeNotifierProvider<PlayerProvider>.value(
      value: provider,
      child: const _StemMixerSheet(),
    ),
  );
}

class _StemMixerSheet extends StatelessWidget {
  const _StemMixerSheet();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final enabled = provider.currentIndex >= 0;

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
                    'Mezcla de pistas',
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
            for (final name in stemNames)
              _StemVolumeRow(
                name: name,
                enabled: enabled,
                volume: provider.engine.stemVolumes[name] ?? 1.0,
                muted: provider.engine.muteStates[name] ?? false,
              ),
          ],
        ),
      ),
    );
  }
}

class _StemVolumeRow extends StatelessWidget {
  final String name;
  final bool enabled;
  final double volume;
  final bool muted;

  const _StemVolumeRow({
    required this.name,
    required this.enabled,
    required this.volume,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<PlayerProvider>();
    final percent = (volume.clamp(0.0, 1.0) * 100).round();
    return Row(
      children: [
        GestureDetector(
          onTap: enabled ? () => provider.toggleMute(name) : null,
          child: SizedBox(
            width: 34,
            child: Center(
              child: Image.asset(
                muted ? 'assets/icons/no_$name.png' : 'assets/icons/$name.png',
                width: 26,
                height: 26,
                color: enabled ? null : Colors.grey.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            _stemLabels[name] ?? name,
            style: TextStyle(
              color: muted ? AppColors.border : Colors.white,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: Slider(
            value: volume.clamp(0.0, 1.0),
            onChanged: enabled ? (v) => provider.setStemVolume(name, v) : null,
            activeColor: muted ? AppColors.border : AppColors.accentPurple,
            inactiveColor: AppColors.border.withValues(alpha: 0.4),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '$percent',
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
