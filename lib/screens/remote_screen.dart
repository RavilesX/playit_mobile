import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../models/remote_state.dart';
import '../providers/player_provider.dart';
import '../providers/remote_provider.dart';
import '../services/audio_engine.dart';
import '../utils/duration_format.dart';
import '../widgets/remote_mixer.dart';
import '../widgets/remote_pair_form.dart';
import '../widgets/remote_queue_sheet.dart';
import '../widgets/search_field.dart';
import 'qr_scan_screen.dart';

/// Remote control for PlayIt Desktop on the same Wi-Fi (PLAN_REMOTO.md).
///
/// Owns its [RemoteProvider], so leaving the screen disposes the session and
/// stops the polling timer for good.
class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const RemoteScreen()));

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
            child: Image.asset(
              'assets/images/background.png',
              fit: BoxFit.cover,
            ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Landscape phones (and portrait with the keyboard up) don't have
        // room for full-size chrome above the playlist; below this height
        // every fixed-size section shrinks together so the total always
        // fits instead of overflowing the Column.
        final compact = constraints.maxHeight < 420;
        // Compact chrome floors out around 207px (header+search+mixer+
        // transport at their smallest fixed sizes, measured). Landscape
        // with the keyboard up can still be shorter than that, so shrink
        // further instead of overflowing.
        const compactFloor = 207.0;
        final scale = compact && constraints.maxHeight < compactFloor
            ? (constraints.maxHeight / compactFloor).clamp(0.55, 1.0)
            : 1.0;
        return Column(
          children: [
            if (remote.errorMessage.isNotEmpty)
              _ErrorBanner(message: remote.errorMessage),
            _NowPlayingHeader(compact: compact, scale: scale),
            // The search field's TextField has a fixed minimum height that
            // can't shrink further; when even the scaled-down chrome
            // doesn't fit, drop it instead of overflowing.
            if (remote.playlist.items.isNotEmpty && scale >= 1.0)
              _RemoteSearchField(compact: compact),
            const Expanded(child: _RemotePlaylistList()),
            // Older desktops don't serve the mixer fields; hiding the
            // controls beats offering buttons that answer 400.
            if (remote.hasMixer)
              RemoteMixerBar(compact: compact, scale: scale),
            _RemoteTransport(compact: compact, scale: scale),
          ],
        );
      },
    );
  }
}

class _RemoteSearchField extends StatelessWidget {
  final bool compact;
  const _RemoteSearchField({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final query = context.select<RemoteProvider, String>((r) => r.searchQuery);
    return Padding(
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 4, 12, 2)
          : const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: SearchField(
        query: query,
        onChanged: (v) => context.read<RemoteProvider>().setSearchQuery(v),
      ),
    );
  }
}

class _NowPlayingHeader extends StatelessWidget {
  final bool compact;
  final double scale;
  const _NowPlayingHeader({this.compact = false, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    final remote = context.watch<RemoteProvider>();
    final state = remote.state;
    final title = state.hasSong ? state.song : 'Sin canción';
    final subtitle = state.duration == Duration.zero
        ? state.playbackLabel
        : '${state.playbackLabel}  ·  '
              '${formatSongDuration(state.position)} / '
              '${formatSongDuration(state.duration)}';

    return Container(
      width: double.infinity,
      padding: compact
          ? EdgeInsets.symmetric(horizontal: 16, vertical: 6 * scale)
          : const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _RemoteCover(bytes: remote.coverBytes, compact: compact, scale: scale),
          SizedBox(width: compact ? 14 * scale : 14),
          Expanded(
            // Landscape/short screens collapse to two lines: title, then
            // artist and playback status merged into one — the full
            // 3-4 line layout is what pushed the header past the
            // available height there.
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.lyricsCurrentColor,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        state.hasSong
                            ? '${state.artist}  ·  $subtitle'
                            : subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
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
                              subtitle,
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
          // Only shown by a desktop that reports its queue; the badge is the
          // fastest read of "how many songs are waiting".
          if (remote.hasQueue)
            _QueueButton(count: remote.queue.length, compact: compact),
        ],
      ),
    );
  }
}

/// Opens the PC's queue manager, with the queued count as a badge.
class _QueueButton extends StatelessWidget {
  final int count;
  final bool compact;
  const _QueueButton({required this.count, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Cola de la PC',
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      onPressed: () => showRemoteQueueSheet(context),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.queue_music,
            color: count > 0 ? AppColors.accentPurple : AppColors.border,
            size: compact ? 22 : 26,
          ),
          if (count > 0)
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accentPurple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
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
  final bool compact;
  final double scale;
  const _RemoteCover({
    required this.bytes,
    this.compact = false,
    this.scale = 1.0,
  });

  static const _fullSide = 64.0;
  static const _compactSide = 40.0;

  @override
  Widget build(BuildContext context) {
    final side = compact ? _compactSide * scale : _fullSide;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: side,
        height: side,
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
                cacheWidth: (side * MediaQuery.devicePixelRatioOf(context))
                    .round(),
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

    if (remote.playlist.items.isEmpty) {
      return const Center(
        child: Text(
          'La PC no tiene canciones cargadas',
          style: TextStyle(color: AppColors.border),
        ),
      );
    }

    final items = remote.visibleTracks;
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'Sin resultados',
          style: TextStyle(color: AppColors.border),
        ),
      );
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (ctx, pos) {
        final track = items[pos];
        final isCurrent = track.index == remote.state.index;
        final queued = remote.isQueued(track.index);
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Queued on the PC — the same purple dot the desktop paints
              // on its own playlist rows.
              if (queued)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.circle,
                    size: 9,
                    color: AppColors.accentPurple,
                  ),
                ),
              if (track.duration.isNotEmpty)
                Text(
                  track.duration,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
            ],
          ),
          onTap: () => context.read<RemoteProvider>().playIndex(track.index),
          // Older desktops don't serve the queue; long-pressing would only
          // offer actions that answer 400.
          onLongPress: remote.hasQueue
              ? () => showRemoteTrackActionsSheet(context, track)
              : null,
        );
      },
    );
  }
}

/// Five buttons, deliberately oversized: they get used standing up, behind a
/// drum kit, with sticks in hand.
class _RemoteTransport extends StatelessWidget {
  final bool compact;

  /// Extra shrink factor for when [compact] alone still doesn't fit
  /// vertically (landscape with the keyboard up). 1.0 = no extra shrink.
  final double scale;

  const _RemoteTransport({this.compact = false, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    final remote = context.watch<RemoteProvider>();
    final state = remote.state;
    final hasPlaylist = remote.playlist.items.isNotEmpty;

    final baseSize = (compact ? 40.0 : 56.0) * (compact ? scale : 1);
    final playSize = (compact ? 60.0 : 84.0) * (compact ? scale : 1);
    final hPadding = compact ? 8.0 * scale : 12.0;
    final vPadding = compact ? 6.0 * scale : 14.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The five buttons are fixed-size (deliberately, for use behind a
        // drum kit) so on the narrowest phones (~320dp) they don't fit
        // side by side; scale them down just enough to fit instead of
        // overflowing the row.
        // Only the buttons themselves shrink — hPadding stays fixed — so
        // the available width for the scale check excludes it too.
        final available = constraints.maxWidth - hPadding * 2;
        final needed = baseSize * 4 + playSize;
        final widthScale = available < needed ? available / needed : 1.0;
        final btnSize = baseSize * widthScale;
        final playBtnSize = playSize * widthScale;

        return Container(
          padding: EdgeInsets.symmetric(
            vertical: vPadding,
            horizontal: hPadding,
          ),
          decoration: const BoxDecoration(
            color: Colors.black,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RemoteBtn(
                asset: 'assets/icons/prev.png',
                size: btnSize,
                enabled: hasPlaylist,
                onTap: () => context.read<RemoteProvider>().previous(),
              ),
              _RemoteBtn(
                asset: 'assets/icons/play.png',
                size: playBtnSize,
                enabled: hasPlaylist,
                highlight: true,
                onTap: () => context.read<RemoteProvider>().togglePlayPause(),
              ),
              _RemoteBtn(
                asset: 'assets/icons/stop.png',
                size: btnSize,
                enabled: !state.isStopped,
                onTap: () => context.read<RemoteProvider>().stop(),
              ),
              _RemoteBtn(
                asset: 'assets/icons/next.png',
                size: btnSize,
                enabled: hasPlaylist,
                onTap: () => context.read<RemoteProvider>().next(),
              ),
              _RemoteBtn(
                asset: state.repeat
                    ? 'assets/icons/repeat_on.png'
                    : 'assets/icons/repeat.png',
                size: btnSize,
                enabled: true,
                active: state.repeat,
                onTap: () => context.read<RemoteProvider>().toggleRepeat(),
              ),
            ],
          ),
        );
      },
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
