import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

enum PlaybackStatus { stopped, playing, paused }

const stemNames = ['drums', 'vocals', 'bass', 'other'];

/// Sample-accurate multi-stem playback.
/// All 4 stems are voices in a single SoLoud engine → shared sample clock → no drift.
class AudioEngine {
  final SoLoud _soloud = SoLoud.instance;
  final Map<String, AudioSource> _sources = {};
  final Map<String, SoundHandle> _handles = {};

  final Map<String, double> _stemVolumes = {for (final n in stemNames) n: 1.0};
  final Map<String, bool> _muteStates = {for (final n in stemNames) n: false};
  double _masterVolume = 0.25;

  PlaybackStatus _status = PlaybackStatus.stopped;
  Duration _duration = Duration.zero;
  bool _hasSong = false;
  void Function()? _onComplete;

  Timer? _positionTimer;
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  bool _completeFired = false;
  late final Future<void> _initFuture;

  AudioEngine() {
    _initFuture = _init();
  }

  Future<void> _init() async {
    if (!_soloud.isInitialized) {
      await _soloud.init();
    }
  }

  PlaybackStatus get status => _status;
  Duration get duration => _duration;
  double get masterVolume => _masterVolume;
  Map<String, double> get stemVolumes => Map.unmodifiable(_stemVolumes);
  Map<String, bool> get muteStates => Map.unmodifiable(_muteStates);
  Stream<Duration> get positionStream => _positionController.stream;

  void setOnComplete(void Function() callback) {
    _onComplete = callback;
  }

  /// Loads the 4 stems from in-memory compressed bytes (works for both
  /// filesystem and SAF content:// sources). [songKey] must be unique per
  /// song — SoLoud uses it to identify the buffers.
  Future<bool> load(String songKey, Map<String, Uint8List> stemBytes) async {
    try {
      await _initFuture;
      await _disposeSources();
      _hasSong = true;

      for (final name in stemNames) {
        _sources[name] = await _soloud.loadMem(
          '$songKey/$name.mp3',
          stemBytes[name]!,
        );
      }

      // Stems can differ slightly in length; track the longest so
      // end-of-track detection doesn't cut the others short.
      _duration = stemNames
          .map((n) => _soloud.getLength(_sources[n]!))
          .reduce((a, b) => a > b ? a : b);
      await _createHandles();

      _status = PlaybackStatus.stopped;
      _completeFired = false;
      return true;
    } catch (e) {
      debugPrint('AudioEngine.load("$songKey") failed: $e');
      return false;
    }
  }

  /// Create all 4 voices paused at position 0, with correct volumes.
  /// Starting them paused and then unpausing together is the sync trick.
  Future<void> _createHandles() async {
    _handles.clear();
    for (final name in stemNames) {
      final muted = _muteStates[name] ?? false;
      final stemVol = _stemVolumes[name] ?? 1.0;
      final vol = muted ? 0.0 : stemVol * _masterVolume;
      _handles[name] = await _soloud.play(
        _sources[name]!,
        volume: vol,
        paused: true,
      );
    }
  }

  Future<void> _disposeSources() async {
    for (final h in _handles.values) {
      if (_soloud.getIsValidVoiceHandle(h)) {
        _soloud.stop(h);
      }
    }
    _handles.clear();
    for (final s in _sources.values) {
      await _soloud.disposeSource(s);
    }
    _sources.clear();
  }

  Future<void> play() async {
    if (!_hasSong || _sources.isEmpty) return;

    // Recreate handles if invalid (after stop or end-of-track)
    final drumsHandle = _handles['drums'];
    if (drumsHandle == null || !_soloud.getIsValidVoiceHandle(drumsHandle)) {
      await _createHandles();
    }

    // Unpause all 4 voices. SoLoud processes them in the same audio callback
    // → they start on the same sample. No Future.wait needed.
    for (final h in _handles.values) {
      _soloud.setPause(h, false);
    }

    _status = PlaybackStatus.playing;
    _completeFired = false;
    _startPositionTimer();
  }

  Future<void> pause() async {
    for (final h in _handles.values) {
      if (_soloud.getIsValidVoiceHandle(h)) {
        _soloud.setPause(h, true);
      }
    }
    _status = PlaybackStatus.paused;
    _positionTimer?.cancel();
  }

  Future<void> stop() async {
    _positionTimer?.cancel();
    for (final h in _handles.values) {
      if (_soloud.getIsValidVoiceHandle(h)) {
        _soloud.stop(h);
      }
    }
    _handles.clear();
    _status = PlaybackStatus.stopped;
    if (!_positionController.isClosed) {
      _positionController.add(Duration.zero);
    }
  }

  Future<void> seek(Duration position) async {
    // If handles dead (e.g., after stop), recreate at position 0 then seek
    final drumsHandle = _handles['drums'];
    if ((drumsHandle == null || !_soloud.getIsValidVoiceHandle(drumsHandle)) &&
        _sources.isNotEmpty) {
      await _createHandles();
    }
    for (final h in _handles.values) {
      if (_soloud.getIsValidVoiceHandle(h)) {
        _soloud.seek(h, position);
      }
    }
    if (!_positionController.isClosed) {
      _positionController.add(position);
    }
  }

  void setMasterVolume(double volume) {
    _masterVolume = volume.clamp(0.0, 1.0);
    _applyVolumes();
  }

  void setStemVolume(String name, double volume) {
    _stemVolumes[name] = volume.clamp(0.0, 1.0);
    _applyVolumes();
  }

  void toggleMute(String name) {
    _muteStates[name] = !(_muteStates[name] ?? false);
    _applyVolumes();
  }

  void _applyVolumes() {
    for (final name in stemNames) {
      final h = _handles[name];
      if (h == null || !_soloud.getIsValidVoiceHandle(h)) continue;
      final muted = _muteStates[name] ?? false;
      final stemVol = _stemVolumes[name] ?? 1.0;
      _soloud.setVolume(h, muted ? 0.0 : stemVol * _masterVolume);
    }
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_status != PlaybackStatus.playing) return;
      final drumsHandle = _handles['drums'];
      if (drumsHandle == null) return;

      // Voice died before expected end — treat as complete
      if (!_soloud.getIsValidVoiceHandle(drumsHandle)) {
        _fireComplete();
        return;
      }

      final pos = _soloud.getPosition(drumsHandle);
      if (!_positionController.isClosed) {
        _positionController.add(pos);
      }

      if (_duration > Duration.zero &&
          pos >= _duration - const Duration(milliseconds: 100)) {
        _fireComplete();
      }
    });
  }

  void _fireComplete() {
    if (_completeFired) return;
    _completeFired = true;
    _status = PlaybackStatus.stopped;
    _positionTimer?.cancel();
    _onComplete?.call();
  }

  Future<void> dispose() async {
    _positionTimer?.cancel();
    await _disposeSources();
    await _positionController.close();
  }
}
