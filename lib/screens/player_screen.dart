import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/player_provider.dart';
import '../services/audio_engine.dart';
import 'remote_screen.dart';
import '../widgets/cover_view.dart';
import '../widgets/lyrics_display.dart';
import '../widgets/playlist_drawer.dart';
import '../widgets/progress_bar_widget.dart';
import '../widgets/spectrum_visualizer.dart';
import '../widgets/stem_control.dart';
import '../widgets/stem_mixer_sheet.dart';
import '../services/update_checker.dart';
import '../widgets/transport_controls.dart';
import '../widgets/update_dialogs.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    // Silent check: honours the user's preference, at most once a day, and
    // never interrupts with an error if there's no network.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  Future<void> _checkForUpdates() async {
    final current = await currentAppVersion();
    final release = await UpdateChecker().checkForUpdateSilently(current);
    if (release == null || !mounted) return;
    await showUpdateAvailableDialog(context, release, current, skippable: true);
  }

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
          body: const _PlayerLayout(),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Player layout — cover/lyrics on top, stem/transport controls stacked
// below at full width, on phone and tablet alike, portrait or landscape.
// ────────────────────────────────────────────────────────────────────────────
class _PlayerLayout extends StatelessWidget {
  const _PlayerLayout();

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
            icon: Icon(
              Icons.graphic_eq,
              color: provider.spectrumEnabled
                  ? AppColors.accentPurple
                  : Colors.grey,
            ),
            onPressed: () => context.read<PlayerProvider>().toggleSpectrum(),
            tooltip: 'Visualizador de espectro',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open, color: AppColors.accentBlue),
            onPressed: () => context.read<PlayerProvider>().pickLibraryFolder(),
            tooltip: 'Seleccionar carpeta',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: Colors.black,
            tooltip: 'Más opciones',
            onSelected: (value) {
              switch (value) {
                case 'remote':
                  RemoteScreen.open(context);
                case 'update':
                  runManualUpdateCheck(context);
                case 'about':
                  showAboutPlayItDialog(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'remote',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_remote, color: Colors.white),
                  title: Text(
                    'Controlar PlayIt Desktop',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'update',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.system_update, color: Colors.white),
                  title: Text(
                    'Buscar actualizaciones',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'about',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline, color: Colors.white),
                  title: Text(
                    'Acerca de',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TabSection extends StatefulWidget {
  @override
  State<_TabSection> createState() => _TabSectionState();
}

class _TabSectionState extends State<_TabSection> {
  /// Live pointer count over the tab body. With two fingers down the page
  /// swipe is disabled so the lyrics pinch-to-zoom wins the gesture arena —
  /// otherwise the TabBarView's horizontal drag claims the pointers first and
  /// the scale gesture never starts.
  int _pointers = 0;
  bool _swipeLocked = false;

  void _updatePointers(int delta) {
    _pointers = (_pointers + delta).clamp(0, 10);
    final locked = _pointers >= 2;
    // Only rebuild on the threshold crossing, not on every pointer event.
    if (locked != _swipeLocked) setState(() => _swipeLocked = locked);
  }

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
            child: Listener(
              onPointerDown: (_) => _updatePointers(1),
              onPointerUp: (_) => _updatePointers(-1),
              onPointerCancel: (_) => _updatePointers(-1),
              child: TabBarView(
                physics: _swipeLocked
                    ? const NeverScrollableScrollPhysics()
                    : null,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: CoverView(coverBytes: provider.coverBytes),
                  ),
                  const LyricsDisplay(),
                ],
              ),
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

    final showSpectrum =
        provider.spectrumEnabled && provider.status == PlaybackStatus.playing;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Stack(
        children: [
          if (showSpectrum)
            const Positioned.fill(
              child: Opacity(opacity: 0.5, child: SpectrumVisualizer()),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ...stemNames.map((name) {
                return Expanded(
                  child: StemControl(
                    name: name,
                    muted: provider.engine.muteStates[name] ?? false,
                    enabled: enabled,
                    onMuteToggle: () => provider.toggleMute(name),
                    autoUnmuteEnabled: name == 'vocals'
                        ? provider.autoUnmuteEnabled
                        : null,
                    onAutoUnmuteToggle: name == 'vocals'
                        ? provider.toggleAutoUnmute
                        : null,
                  ),
                );
              }),
              const Expanded(child: StemMixerButton()),
            ],
          ),
        ],
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
  // Mirrors TransportControls' own button sizes/gaps (40+34+70+34+40+40+40
  // icons, 8dp gaps) plus the dial and its leading gap — there's no cheap
  // way to ask a widget its natural size before it's laid out.
  static const _fullRowWidth = 346.0 + 16.0 + 80.0;

  /// Below this fraction of natural size, the standard 40dp buttons would
  /// shrink under the ~34dp the app already uses for the seek icons
  /// elsewhere — drop the seek buttons (least essential; scrubbing is
  /// still available on the progress bar) to recover legibility for the
  /// rest instead of shrinking everything further.
  static const _seekScaleFloor = 0.70;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSeek =
            constraints.maxWidth >= _fullRowWidth * _seekScaleFloor;
        // Scales the whole row down on narrow screens instead of
        // overflowing — showSeek above keeps this near 1.0 on most phones.
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: TransportControls(
            status: provider.status,
            hasPlaylist: provider.playlist.isNotEmpty,
            hasCurrentSong: provider.currentIndex >= 0,
            repeatMode: provider.repeatMode,
            onPrev: provider.playPrevious,
            onPlayPause: provider.togglePlayPause,
            onNext: provider.playNext,
            onStop: provider.stop,
            onRepeatToggle: provider.toggleRepeat,
            onSeekBack: () => provider.seekBy(const Duration(seconds: -5)),
            onSeekForward: () => provider.seekBy(const Duration(seconds: 5)),
            showSeek: showSeek,
          ),
        );
      },
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
