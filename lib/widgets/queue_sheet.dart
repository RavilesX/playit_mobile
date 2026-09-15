import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../utils/tags.dart';
import 'tag_chips.dart';

/// Playback queue manager (desktop's "Administrar cola"): the songs that
/// play before the playlist resumes its own order, each with its tags.
/// Songs are removed here or from the playlist's own long-press menu;
/// order is the order they were queued in.
Future<void> showQueueSheet(BuildContext context) {
  final provider = context.read<PlayerProvider>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => ChangeNotifierProvider<PlayerProvider>.value(
      value: provider,
      child: const _QueueSheet(),
    ),
  );
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final queue = provider.playQueue;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _QueueSheetHeader(
              count: queue.length,
              onClear: queue.isEmpty ? null : provider.clearQueue,
            ),
            if (queue.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: Text(
                  'La cola está vacía. Mantén presionada una canción de la '
                  'playlist para agregarla.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.border, fontSize: 13),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 16),
                  shrinkWrap: true,
                  itemCount: queue.length,
                  separatorBuilder: (_, _) =>
                      const Divider(color: AppColors.border, height: 1),
                  itemBuilder: (_, i) => _QueueRow(
                    position: i + 1,
                    song: queue[i],
                    provider: provider,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Header shared with the remote queue sheet in look, not in code: the two
/// talk to different providers, and folding them together would mean
/// passing callbacks for every action.
class _QueueSheetHeader extends StatelessWidget {
  final int count;
  final VoidCallback? onClear;
  const _QueueSheetHeader({required this.count, this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          const Icon(Icons.queue_music, color: AppColors.accentBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count == 0 ? 'Cola de reproducción' : 'Cola · $count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            child: Text(
              'Limpiar',
              style: TextStyle(
                color: onClear == null ? AppColors.border : AppColors.lyricRojo,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.border),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final int position;
  final Song song;
  final PlayerProvider provider;

  const _QueueRow({
    required this.position,
    required this.song,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final tags = provider.tagsOf(song);
    final muted = stemsNamedBy(tags);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$position',
              style: const TextStyle(color: AppColors.accentPurple, fontSize: 13),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                Text(
                  song.artist,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 6),
                TagChips(
                  tags: tags,
                  onAdd: (t) => provider.addTag(song, t),
                  onRemove: (t) => provider.removeTag(song, t),
                ),
                if (muted.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Al sonar se silencia: '
                      '${muted.map(stemLabel).join(', ')}',
                      style: const TextStyle(
                        color: AppColors.accentBlue,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Quitar de la cola',
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            color: AppColors.border,
            onPressed: () => provider.removeFromQueue(song),
          ),
        ],
      ),
    );
  }
}
