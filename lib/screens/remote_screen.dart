import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/remote_state.dart';
import '../providers/player_provider.dart';
import '../providers/remote_provider.dart';
import '../services/audio_engine.dart';
import '../utils/duration_format.dart';
import '../widgets/remote_pair_form.dart';
import 'qr_scan_screen.dart';

/// Remote control for PlayIt Desktop on the same Wi-Fi (PLAN_REMOTO.md).
///
/// Owns its [RemoteProvider], so leaving the screen disposes the session and
/// stops the polling timer for good.
class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const RemoteScreen()),
  );

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen>
    with WidgetsBindingObserver {
  final RemoteProvider _remote = RemoteProvider();
  PairingInfo? _saved;
  bool _loadingSaved = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final saved = await RemoteProvider.savedPairing();
    if (!mounted) return;
    setState(() {
      _saved = saved;
      _loadingSaved = false;
    });
    if (saved != null && await _remote.connect(saved)) _onConnected();
  }

  /// Two audio sources at once is the worst possible outcome for someone
  /// rehearsing, so taking control of the PC stops whatever the phone was
  /// playing.
  void _onConnected() {
    if (!mounted) return;
    final player = context.read<PlayerProvider>();
    if (player.status == PlaybackStatus.stopped) return;
    player.stop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Se detuvo la reproducción local'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Polling only while visible: a 1 Hz network timer in the background is
    // battery burned for nothing.
    if (state == AppLifecycleState.resumed) {
      _remote.resumePolling();
    } else {
      _remote.pausePolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _remote,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/background.png', fit: BoxFit.cover),
          ),
          Scaffold(
            backgroundColor: Colors.black.withValues(alpha: 0.75),
            appBar: _buildAppBar(),
            body: SafeArea(
              top: false,
              child: _loadingSaved
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accentPurple,
                      ),
                    )
                  : Consumer<RemoteProvider>(
                      builder: (ctx, remote, _) => remote.isConnected
                          ? const _ConnectedView()
                          : _buildPairing(remote),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Consumer<RemoteProvider>(
        builder: (ctx, remote, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Control remoto', style: TextStyle(fontSize: 16)),
            if (remote.isConnected)
              Text(
                remote.desktopName,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.accentBlue,
                ),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
      actions: [
        Consumer<RemoteProvider>(
          builder: (ctx, remote, _) => PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: Colors.black,
            onSelected: (value) async {
              switch (value) {
                case 'disconnect':
                  await remote.disconnect();
                case 'forget':
                  await remote.forget();
                  if (mounted) setState(() => _saved = null);
              }
            },
            itemBuilder: (_) => [
              if (remote.isConnected)
                const PopupMenuItem(
                  value: 'disconnect',
                  child: Text(
                    'Desconectar',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              const PopupMenuItem(
                value: 'forget',
                child: Text(
                  'Olvidar esta PC',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPairing(RemoteProvider remote) {
    return Column(
      children: [
        if (remote.connection == RemoteConnection.error &&
            remote.errorMessage.isNotEmpty)
          _ErrorBanner(message: remote.errorMessage),
        Expanded(
          child: RemotePairForm(
            previous: _saved ?? remote.pairing,
            busy: remote.isBusy,
            onScan: () => QrScanScreen.open(context),
            onDiscover: remote.discover,
            onSubmit: (info) async {
              if (await remote.connect(info)) _onConnected();
            },
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.lyricRojo.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectedView extends StatelessWidget {
  const _ConnectedView();

  @override
  Widget build(BuildContext context) {
    final remote = context.watch<RemoteProvider>();
    return Column(
      children: [
        if (remote.errorMessage.isNotEmpty)
          _ErrorBanner(message: remote.errorMessage),
        const _NowPlayingHeader(),
        const Expanded(child: _RemotePlaylistList()),
        const _RemoteTransport(),
      ],
    );
  }
}

class _NowPlayingHeader extends StatelessWidget {
  const _NowPlayingHeader();

  @override
  Widget build(BuildContext context) {
    final remote = context.watch<RemoteProvider>();
    final state = remote.state;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _RemoteCover(bytes: remote.coverBytes),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.hasSong ? state.song : 'Sin canción',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.lyricsCurrentColor,
                    fontSize: 18,
                  ),
                ),
                if (state.hasSong)
                  Text(
                    state.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.accentBlue,
                      fontSize: 14,
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      state.isPlaying
                          ? Icons.play_arrow
                          : state.isStopped
                          ? Icons.stop
                          : Icons.pause,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        state.duration == Duration.zero
                            ? state.playbackLabel
                            : '${state.playbackLabel}  ·  '
                                  '${formatSongDuration(state.position)} / '
                                  '${formatSongDuration(state.duration)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cover art streamed from the PC. Falls back to a placeholder for songs
/// without `cover.png` and for desktops too old to serve `/api/cover`.
class _RemoteCover extends StatelessWidget {
  final Uint8List? bytes;
  const _RemoteCover({required this.bytes});

  static const _side = 64.0;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _side,
        height: _side,
        child: bytes == null
            ? const ColoredBox(
                color: AppColors.surface,
                child: Icon(
                  Icons.music_note,
                  color: AppColors.border,
                  size: 30,
                ),
              )
            : Image.memory(
                bytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth:
                    (_side * MediaQuery.devicePixelRatioOf(context)).round(),
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: AppColors.surface,
                  child: Icon(
                    Icons.broken_image,
                    color: AppColors.border,
                    size: 28,
                  ),
                ),
              ),
      ),
    );
  }
}

class _RemotePlaylistList extends StatelessWidget {
  const _RemotePlaylistList();

  @override
  Widget build(BuildContext context) {
    final remote = context.watch<RemoteProvider>();
    final items = remote.playlist.items;

    if (items.isEmpty) {
      return const Center(
        child: Text(
          'La PC no tiene canciones cargadas',
          style: TextStyle(color: AppColors.border),
        ),
      );
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (ctx, pos) {
        final track = items[pos];
        final isCurrent = track.index == remote.state.index;
        return ListTile(
          selected: isCurrent,
          selectedTileColor: AppColors.pinkHighlight.withValues(alpha: 0.3),
          leading: Icon(
            Icons.audiotrack,
            color: isCurrent ? AppColors.pinkHighlight : AppColors.accentBlue,
          ),
          title: Text(
            track.song,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isCurrent ? AppColors.pinkHighlight : Colors.white,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              fontStyle: isCurrent ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          subtitle: Text(
            track.artist,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isCurrent
                  ? AppColors.pinkHighlight.withValues(alpha: 0.8)
                  : Colors.grey,
              fontSize: 12,
            ),
          ),
          trailing: track.duration.isEmpty
              ? null
              : Text(
                  track.duration,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
          onTap: () => context.read<RemoteProvider>().playIndex(track.index),
        );
      },
    );
  }
}

/// Five buttons, deliberately oversized: they get used standing up, behind a
/// drum kit, with sticks in hand.
class _RemoteTransport extends StatelessWidget {
  const _RemoteTransport();

  @override
  Widget build(BuildContext context) {
    final remote = context.watch<RemoteProvider>();
    final state = remote.state;
    final hasPlaylist = remote.playlist.items.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RemoteBtn(
            asset: 'assets/icons/prev.png',
            size: 56,
            enabled: hasPlaylist,
            onTap: () => context.read<RemoteProvider>().previous(),
          ),
          _RemoteBtn(
            asset: 'assets/icons/play.png',
            size: 84,
            enabled: hasPlaylist,
            highlight: true,
            onTap: () => context.read<RemoteProvider>().togglePlayPause(),
          ),
          _RemoteBtn(
            asset: 'assets/icons/stop.png',
            size: 56,
            enabled: !state.isStopped,
            onTap: () => context.read<RemoteProvider>().stop(),
          ),
          _RemoteBtn(
            asset: 'assets/icons/next.png',
            size: 56,
            enabled: hasPlaylist,
            onTap: () => context.read<RemoteProvider>().next(),
          ),
          _RemoteBtn(
            asset: state.repeat
                ? 'assets/icons/repeat_on.png'
                : 'assets/icons/repeat.png',
            size: 56,
            enabled: true,
            active: state.repeat,
            onTap: () => context.read<RemoteProvider>().toggleRepeat(),
          ),
        ],
      ),
    );
  }
}

class _RemoteBtn extends StatelessWidget {
  final String asset;
  final double size;
  final bool enabled;
  final bool highlight;
  final bool active;
  final VoidCallback onTap;

  const _RemoteBtn({
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
          padding: EdgeInsets.all(highlight ? 12 : 10),
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
