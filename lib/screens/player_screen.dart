import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/player_provider.dart';
import '../services/audio_engine.dart';
import '../widgets/cover_view.dart';
import '../widgets/lyrics_display.dart';
import '../widgets/playlist_drawer.dart';
import '../widgets/progress_bar_widget.dart';
import '../widgets/stem_control.dart';
import '../widgets/transport_controls.dart';
import '../widgets/volume_dial.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Stack(
      children: [
        // Vertically fixed full-screen background
        Positioned.fill(
          child: Image.asset(
            'assets/images/background.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            cacheHeight: (screen.height * dpr).round(),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          drawer: Drawer(
            backgroundColor: Colors.transparent,
            width: math.min(300, screen.width * 0.85),
            child: const PlaylistDrawer(),
          ),
          body: LayoutBuilder(
            builder: (ctx, constraints) {
              final isLandscape = constraints.maxWidth > constraints.maxHeight;
              final isTablet = constraints.maxWidth > 600;

              if (isTablet || isLandscape) {
                return _WideLayout(isTablet: isTablet);
              }
              return const _PortraitLayout();
            },
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Portrait layout (phone, vertical)
// ────────────────────────────────────────────────────────────────────────────
class _PortraitLayout extends StatelessWidget {
  const _PortraitLayout();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _AppBar(),
          Expanded(flex: 5, child: _TabSection()),
          _StemControlsRow(),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ProgressSection(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: _TransportRow(),
          ),
          _StatusBar(),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Wide layout (landscape phone / tablet)
// ────────────────────────────────────────────────────────────────────────────
class _WideLayout extends StatelessWidget {
  final bool isTablet;
  const _WideLayout({required this.isTablet});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Row(
        children: [
          if (isTablet) ...[
            SizedBox(width: 280, child: const PlaylistDrawer()),
            Container(width: 1, color: AppColors.border),
          ],
          Expanded(
            child: Column(
              children: [
                _AppBar(),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: _TabSection()),
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            Expanded(child: _StemControlsRow()),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: _ProgressSection(),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: _TransportRow(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Shared section widgets
// ────────────────────────────────────────────────────────────────────────────
class _AppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          Image.asset(
            'assets/icons/main_icon.png',
            height: 30,
            width: 30,
            cacheWidth: (30 * MediaQuery.devicePixelRatioOf(context)).round(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              provider.currentSong?.displayName ?? 'Play It',
              style: const TextStyle(color: Colors.white, fontSize: 15),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.folder_open, color: AppColors.accentBlue),
            onPressed: () => context.read<PlayerProvider>().pickLibraryFolder(),
            tooltip: 'Seleccionar carpeta',
          ),
        ],
      ),
    );
  }
}

class _TabSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.black.withValues(alpha: 0.5),
            child: const TabBar(
              tabs: [
                Tab(text: 'Portada'),
                Tab(text: 'Letras'),
              ],
              labelColor: AppColors.accentBlue,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.accentPurple,
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: CoverView(coverBytes: provider.coverBytes),
                ),
                LyricsDisplay(
                  song: provider.currentSong,
                  lyrics: provider.lyrics,
                  currentIndex: provider.currentLyricIndex,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StemControlsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final enabled = provider.currentIndex >= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: stemNames.map((name) {
          return Expanded(
            child: StemControl(
              name: name,
              muted: provider.engine.muteStates[name] ?? false,
              volume: provider.engine.stemVolumes[name] ?? 1.0,
              enabled: enabled,
              onMuteToggle: () => provider.toggleMute(name),
              onVolumeChanged: (v) => provider.setStemVolume(name, v),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ProgressSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    // Only this subtree rebuilds at 10 Hz with the playback position.
    return ValueListenableBuilder<Duration>(
      valueListenable: provider.positionNotifier,
      builder: (context, position, _) {
        return ProgressBarWidget(
          position: position,
          duration: provider.duration,
          enabled: provider.status != PlaybackStatus.stopped,
          onSeek: provider.seekTo,
        );
      },
    );
  }
}

class _TransportRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    // Scales the whole row down on narrow screens instead of overflowing
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TransportControls(
            status: provider.status,
            hasPlaylist: provider.playlist.isNotEmpty,
            hasCurrentSong: provider.currentIndex >= 0,
            repeatMode: provider.repeatMode,
            onPrev: provider.playPrevious,
            onPlayPause: provider.togglePlayPause,
            onNext: provider.playNext,
            onStop: provider.stop,
            onRepeatToggle: provider.toggleRepeat,
          ),
          const SizedBox(width: 16),
          VolumeDial(
            value: provider.engine.masterVolume,
            onChanged: provider.setMasterVolume,
            size: 80,
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Colors.black.withValues(alpha: 0.6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              provider.statusText,
              style: const TextStyle(color: Colors.white, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            'Canciones: ${provider.playlist.length}',
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
