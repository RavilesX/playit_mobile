import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import '../providers/player_provider.dart';
import 'audio_engine.dart';

/// Registers the media session / notification bridge. Must run before
/// runApp. Returns null if the platform has no audio_service support.
Future<AudioHandler?> initPlayItAudioHandler(PlayerProvider provider) async {
  try {
    return await AudioService.init(
      builder: () => PlayItAudioHandler(provider),
      config: const AudioServiceConfig(
        androidNotificationChannelId:
            'com.ravilesx.playit_mobile.channel.audio',
        androidNotificationChannelName: 'Reproducción',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (e) {
    debugPrint('audio_service init failed: $e');
    return null;
  }
}

/// Mirrors PlayerProvider state into the system media session (status bar
/// notification, lock screen, headset buttons) and routes media commands
/// back into the provider.
class PlayItAudioHandler extends BaseAudioHandler {
  final PlayerProvider _provider;
  String? _lastMediaId;
  Duration _lastDuration = Duration.zero;

  PlayItAudioHandler(this._provider) {
    _provider.addListener(_sync);
    _sync();
  }

  void _sync() {
    final song = _provider.currentSong;
    final playing = _provider.status == PlaybackStatus.playing;

    if (song == null) {
      if (_lastMediaId != null) {
        _lastMediaId = null;
        mediaItem.add(null);
      }
    } else if (song.displayName != _lastMediaId ||
        _provider.duration != _lastDuration) {
      _lastMediaId = song.displayName;
      _lastDuration = _provider.duration;

      Uri? artUri;
      final cover = song.coverRef;
      if (cover != null) {
        artUri = cover.startsWith('content://')
            ? Uri.tryParse(cover)
            : Uri.file(cover);
      }

      mediaItem.add(
        MediaItem(
          id: song.displayName,
          title: song.title,
          artist: song.artist,
          duration: _provider.duration,
          artUri: artUri,
        ),
      );
    }

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: song == null
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
        playing: playing,
        updatePosition: _provider.position,
      ),
    );
  }

  @override
  Future<void> play() async {
    if (_provider.status != PlaybackStatus.playing) {
      await _provider.togglePlayPause();
    }
  }

  @override
  Future<void> pause() async {
    if (_provider.status == PlaybackStatus.playing) {
      await _provider.togglePlayPause();
    }
  }

  @override
  Future<void> skipToNext() => _provider.playNext();

  @override
  Future<void> skipToPrevious() => _provider.playPrevious();

  @override
  Future<void> stop() => _provider.stop();

  @override
  Future<void> seek(Duration position) => _provider.seekTo(position);
}
