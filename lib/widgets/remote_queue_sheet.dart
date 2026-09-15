import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/remote_state.dart';
import '../providers/remote_provider.dart';
import '../utils/tags.dart';
import 'tag_chips.dart';

/// The PC's playback queue, managed from the phone: what plays before the
/// desktop's playlist resumes its own order, plus each song's tags (naming
/// a stem there mutes it when the PC reaches that song through the queue).
///
/// The provider is passed down explicitly, like the remote mixer sheet: the
/// sheet is built by the root navigator, outside the remote screen's own
/// provider scope.
Future<void> showRemoteQueueSheet(BuildContext context) {
  final remote = context.read<RemoteProvider>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => ChangeNotifierProvider<RemoteProvider>.value(
      value: remote,
      child: const _RemoteQueueSheet(),
    ),
  );
}

class _RemoteQueueSheet extends StatelessWidget {
  const _RemoteQueueSheet();

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

    final queue = remote.queue;
    final byIndex = {for (final t in remote.playlist.items) t.index: t};

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  const Icon(Icons.queue_music, color: AppColors.accentBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      queue.isEmpty
                          ? 'Cola de la PC'
                          : 'Cola de la PC · ${queue.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: queue.isEmpty ? null : remote.clearQueue,
                    child: Text(
                      'Limpiar',
                      style: TextStyle(
                        color: queue.isEmpty
                            ? AppColors.border
                            : AppColors.lyricRojo,
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
            ),
            if (queue.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: Text(
                  'La cola de la PC está vacía. Mantén presionada una canción '
                  'de la lista para agregarla.',
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
                  itemBuilder: (_, i) => _RemoteQueueRow(
                    position: i + 1,
                    index: queue[i],
                    track: byIndex[queue[i]],
                    remote: remote,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RemoteQueueRow extends StatelessWidget {
  final int position;

  /// Playlist index on the PC — what every queue command addresses.
  final int index;

  /// The playlist row it names, or null if the cached playlist doesn't have
  /// it yet (the PC changed its list and `rev` hasn't been re-fetched).
  final RemoteTrack? track;
  final RemoteProvider remote;

  const _RemoteQueueRow({
    required this.position,
    required this.index,
    required this.track,
    required this.remote,
  });

  @override
  Widget build(BuildContext context) {
    final tags = remote.queueTagsOf(index);
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
              style: const TextStyle(
                color: AppColors.accentPurple,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track?.song ?? 'Canción #$index',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                if (track != null)
                  Text(
                    track!.artist,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                const SizedBox(height: 6),
                TagChips(
                  tags: tags,
                  onAdd: (t) => remote.addQueueTag(index, t),
                  onRemove: (t) => remote.removeQueueTag(index, t),
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
            onPressed: () => remote.removeFromQueue(index),
          ),
        ],
      ),
    );
  }
}

/// Long-press menu of a remote playlist row: queue it on the PC, or open
/// the queue manager.
Future<void> showRemoteTrackActionsSheet(
  BuildContext context,
  RemoteTrack track,
) {
  final remote = context.read<RemoteProvider>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) {
      final queued = remote.isQueued(track.index);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    track.song,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    track.artist,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            ListTile(
              leading: const Icon(
                Icons.play_arrow,
                color: AppColors.accentBlue,
              ),
              title: const Text(
                'Reproducir ahora',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              onTap: () {
                remote.playIndex(track.index);
                Navigator.of(sheetCtx).pop();
              },
            ),
            ListTile(
              leading: Icon(
                queued ? Icons.playlist_remove : Icons.queue_music,
                color: AppColors.accentPurple,
              ),
              title: Text(
                queued ? 'Quitar de la cola' : 'Agregar a la cola',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              onTap: () {
                remote.toggleQueue(track.index);
                Navigator.of(sheetCtx).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.list_alt, color: AppColors.accentBlue),
              title: const Text(
                'Administrar cola',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                showRemoteQueueSheet(context);
              },
            ),
          ],
        ),
      );
    },
  );
}
