import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/player_provider.dart';
import 'song_info_sheet.dart';

class PlaylistDrawer extends StatelessWidget {
  const PlaylistDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.queue_music, color: AppColors.accentBlue),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Playlist',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.folder_open,
                        color: AppColors.accentBlue,
                      ),
                      onPressed: () {
                        context.read<PlayerProvider>().pickLibraryFolder();
                      },
                      tooltip: 'Seleccionar carpeta',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const _SearchField(),
                const SizedBox(height: 8),
                const _SortToggle(),
              ],
            ),
          ),
          Expanded(child: _PlaylistList()),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    return TextField(
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Buscar canción...',
        hintStyle: const TextStyle(color: AppColors.border),
        prefixIcon: const Icon(
          Icons.search,
          color: AppColors.border,
          size: 20,
        ),
        suffixIcon: provider.searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(
                  Icons.clear,
                  color: AppColors.border,
                  size: 18,
                ),
                onPressed: () =>
                    context.read<PlayerProvider>().setSearchQuery(''),
              ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
      ),
      onChanged: (v) => context.read<PlayerProvider>().setSearchQuery(v),
    );
  }
}

class _SortToggle extends StatelessWidget {
  const _SortToggle();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    return Row(
      children: [
        SizedBox(
          height: 30,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentBlue,
              side: const BorderSide(color: AppColors.accentPurple),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: provider.playlist.isEmpty
                ? null
                : () => context.read<PlayerProvider>().cycleSort(),
            child: const Text('Ordenar', style: TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            provider.sortModeLabel,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _PlaylistList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();

    if (provider.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.accentPurple),
            SizedBox(height: 12),
            Text('Cargando...', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    if (provider.playlist.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off, color: AppColors.border, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Sin canciones',
              style: TextStyle(color: AppColors.border),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Seleccionar carpeta'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: () =>
                  context.read<PlayerProvider>().pickLibraryFolder(),
            ),
          ],
        ),
      );
    }

    final visible = provider.visiblePlaylistIndices;
    if (visible.isEmpty) {
      return const Center(
        child: Text(
          'Sin resultados',
          style: TextStyle(color: AppColors.border),
        ),
      );
    }

    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (ctx, pos) {
        final i = visible[pos];
        final song = provider.playlist[i];
        final isCurrent = i == provider.currentIndex;
        return ListTile(
          selected: isCurrent,
          selectedTileColor: AppColors.pinkHighlight.withValues(alpha: 0.3),
          leading: Icon(
            Icons.audiotrack,
            color: isCurrent ? AppColors.pinkHighlight : AppColors.accentBlue,
          ),
          title: Text(
            song.title,
            style: TextStyle(
              color: isCurrent ? AppColors.pinkHighlight : Colors.white,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              fontStyle: isCurrent ? FontStyle.italic : FontStyle.normal,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            song.artist,
            style: TextStyle(
              color: isCurrent
                  ? AppColors.pinkHighlight.withValues(alpha: 0.8)
                  : Colors.grey,
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: song.duration == null
              ? null
              : Text(
                  song.duration!,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
          onTap: () {
            context.read<PlayerProvider>().playSong(i);
            if (Scaffold.of(ctx).isDrawerOpen) {
              Navigator.of(ctx).pop();
            }
          },
          onLongPress: () => showSongInfoSheet(context, song),
        );
      },
    );
  }
}
