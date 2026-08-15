import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../models/song.dart';

/// Metadata modal (desktop's "Información" context-menu item, §2.6): the
/// data.json keys (artist/title) plus the source-file metadata block
/// (album/year/genre/format/kbps). Missing fields read "Desconocido",
/// same as desktop for songs separated before that metadata existed.
void showSongInfoSheet(BuildContext context, Song song) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _SongInfoSheet(song: song),
  );
}

class _SongInfoSheet extends StatelessWidget {
  final Song song;
  const _SongInfoSheet({required this.song});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Información',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _InfoRow(label: 'Artista', value: song.artist, copyValue: song.artist),
            _InfoRow(label: 'Canción', value: song.title, copyValue: song.title),
            _InfoRow(
              label: 'Artista - Canción',
              value: song.displayName,
              copyValue: song.displayName,
            ),
            const Divider(color: AppColors.border, height: 24),
            _InfoRow(label: 'Álbum', value: song.metadataOrUnknown('album')),
            _InfoRow(label: 'Año', value: song.metadataOrUnknown('anio')),
            _InfoRow(label: 'Género', value: song.metadataOrUnknown('genero')),
            _InfoRow(label: 'Formato', value: song.metadataOrUnknown('formato')),
            _InfoRow(label: 'Kbps', value: song.metadataOrUnknown('kbps')),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final String? copyValue;

  const _InfoRow({required this.label, required this.value, this.copyValue});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (copyValue != null)
            IconButton(
              iconSize: 16,
              icon: const Icon(Icons.copy, color: AppColors.border),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copyValue!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copiado'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
