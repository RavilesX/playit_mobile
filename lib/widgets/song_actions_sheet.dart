import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import 'queue_sheet.dart';
import 'song_info_sheet.dart';

/// Long-press menu of a playlist row — mobile's take on the desktop
/// playlist's right-click menu: queue the song, open the queue manager, or
/// see its metadata.
Future<void> showSongActionsSheet(BuildContext context, Song song) {
  final provider = context.read<PlayerProvider>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) {
      final queued = provider.isQueued(song);
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
                    song.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    song.artist,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
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
                provider.toggleQueue(song);
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
                showQueueSheet(context);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.info_outline,
                color: AppColors.accentBlue,
              ),
              title: const Text(
                'Información',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                showSongInfoSheet(context, song);
              },
            ),
          ],
        ),
      );
    },
  );
}
