import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/player_provider.dart';
import '../services/audio_engine.dart';
import '../utils/lyric_colors.dart';

const _kFullscreenCurrentFontSize = 56.0;
const _kFullscreenNextFontSize = 26.0;

const _stemLabels = {
  'drums': 'Batería',
  'vocals': 'Voz',
  'bass': 'Bajo',
  'other': 'Otros',
};

/// Karaoke fullscreen: current line at max size, next line below it,
/// auto-hiding transport so the letters stay uncluttered. Opened with a
/// double tap on the lyrics tab, closed the same way or with the back
/// button/close icon.
class LyricsFullscreenScreen extends StatefulWidget {
  const LyricsFullscreenScreen({super.key});

  @override
  State<LyricsFullscreenScreen> createState() =>
      _LyricsFullscreenScreenState();
}

class _LyricsFullscreenScreenState extends State<LyricsFullscreenScreen> {
  bool _controlsVisible = true;
  Timer? _hideTimer;
  String? _muteNotice;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleAutoHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _noticeTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleAutoHide();
  }

  void _showMuteNotice(String stemName, bool nowMuted) {
    _noticeTimer?.cancel();
    setState(() {
      final label = _stemLabels[stemName] ?? stemName;
      _muteNotice = '$label: ${nowMuted ? 'Silenciada' : 'Activada'}';
    });
    _noticeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _muteNotice = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final lyrics = provider.lyrics;
    final idx = provider.currentLyricIndex;
    final scale = provider.lyricsScale;

    final currentLine = idx >= 0 && idx < lyrics.length ? lyrics[idx] : null;
    final nextLine = idx + 1 < lyrics.length ? lyrics[idx + 1] : null;

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          onDoubleTap: () => Navigator.of(context).pop(),
          child: Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    AnimatedOpacity(
                      opacity: _controlsVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !_controlsVisible,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: currentLine == null
                              ? const SizedBox.shrink()
                              : Text.rich(
                                  lyricLineSpan(
                                    currentLine,
                                    _kFullscreenCurrentFontSize * scale,
                                    isCurrent: true,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                        ),
                      ),
                    ),
                    // Pinned just above the controls (fixed size whether
                    // shown or hidden, so this never shifts) — as low as
                    // possible without ever overlapping them. Font size is
                    // fixed on purpose: only the current line responds to
                    // the A-/A+ scale, so the preview stays a stable size.
                    if (nextLine != null && nextLine.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        child: Text.rich(
                          lyricLineSpan(
                            nextLine,
                            _kFullscreenNextFontSize,
                            isCurrent: false,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    AnimatedOpacity(
                      opacity: _controlsVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !_controlsVisible,
                        child: _BottomControls(
                          provider: provider,
                          onSeekBy: provider.seekBy,
                          onMuteToggled: _showMuteNotice,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Momentary mute feedback — the stem buttons aren't visible
              // once the controls auto-hide.
              Positioned(
                top: 16,
                right: 16,
                child: AnimatedOpacity(
                  opacity: _muteNotice != null ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.accentPurple),
                    ),
                    child: Text(
                      _muteNotice ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  final PlayerProvider provider;
  final ValueChanged<Duration> onSeekBy;
  final void Function(String stemName, bool nowMuted) onMuteToggled;

  const _BottomControls({
    required this.provider,
    required this.onSeekBy,
    required this.onMuteToggled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: stemNames.map((name) {
              final muted = provider.engine.muteStates[name] ?? false;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: GestureDetector(
                  onTap: () {
                    provider.toggleMute(name);
                    onMuteToggled(name, !muted);
                  },
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: muted
                        ? Colors.transparent
                        : AppColors.accentPurple.withValues(alpha: 0.3),
                    child: Image.asset(
                      muted
                          ? 'assets/icons/no_$name.png'
                          : 'assets/icons/$name.png',
                      width: 22,
                      height: 22,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.text_decrease, color: Colors.white),
                onPressed: () => provider.adjustLyricsScale(-0.1),
              ),
              IconButton(
                icon: const Icon(Icons.replay_5, color: Colors.white, size: 28),
                onPressed: () => onSeekBy(const Duration(seconds: -5)),
              ),
              IconButton(
                icon: Icon(
                  provider.status == PlaybackStatus.playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: AppColors.accentBlue,
                  size: 48,
                ),
                onPressed: provider.togglePlayPause,
              ),
              IconButton(
                icon: const Icon(Icons.forward_5, color: Colors.white, size: 28),
                onPressed: () => onSeekBy(const Duration(seconds: 5)),
              ),
              IconButton(
                icon: const Icon(Icons.text_increase, color: Colors.white),
                onPressed: () => provider.adjustLyricsScale(0.1),
              ),
            ],
          ),
          if (provider.currentSong != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 20,
                  tooltip: 'Adelantar letra 0.5s',
                  icon: const Icon(Icons.fast_rewind, color: Colors.white70),
                  onPressed: () => provider.adjustLyricOffset(-50),
                ),
                Text(
                  '${provider.currentLyricOffsetSeconds >= 0 ? '+' : ''}'
                  '${provider.currentLyricOffsetSeconds.toStringAsFixed(1)}s',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                IconButton(
                  iconSize: 20,
                  tooltip: 'Atrasar letra 0.5s',
                  icon: const Icon(Icons.fast_forward, color: Colors.white70),
                  onPressed: () => provider.adjustLyricOffset(50),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
