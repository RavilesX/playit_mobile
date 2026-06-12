import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lrc_line.dart';
import '../models/song.dart';
import '../services/audio_engine.dart';
import '../services/lrc_parser.dart';
import '../services/media_library.dart';
import '../services/saf_storage.dart';

class PlayerProvider extends ChangeNotifier {
  final AudioEngine _engine = AudioEngine();

  /// SAF tree on Android, filesystem path elsewhere. Null until the user
  /// picks a folder (or a previous grant is restored).
  MediaLibrary? _library;

  List<Song> _playlist = [];
  int _currentIndex = -1;
  PlaybackStatus _status = PlaybackStatus.stopped;
  bool _isLoading = false;
  String _statusText = 'Listo';
  Uint8List? _coverBytes;

  List<LrcLine> _lyrics = [];
  int _currentLyricIndex = -1;

  /// Position updates at ~10 Hz. Exposed as a ValueNotifier so only the
  /// progress bar listens to it — the rest of the tree rebuilds via
  /// notifyListeners() only on real state changes.
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _positionSub;
  bool _repeatMode = false;

  /// Guards against interleaved playSong calls from rapid taps.
  int _playToken = 0;

  List<Song> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  PlaybackStatus get status => _status;
  bool get isLoading => _isLoading;
  String get statusText => _statusText;
  Uint8List? get coverBytes => _coverBytes;
  List<LrcLine> get lyrics => _lyrics;
  int get currentLyricIndex => _currentLyricIndex;
  Duration get position => positionNotifier.value;
  Duration get duration => _duration;
  AudioEngine get engine => _engine;
  bool get repeatMode => _repeatMode;

  void toggleRepeat() {
    _repeatMode = !_repeatMode;
    notifyListeners();
  }

  Song? get currentSong =>
      _currentIndex >= 0 && _currentIndex < _playlist.length
      ? _playlist[_currentIndex]
      : null;

  Future<void> initialize() async {
    _positionSub = _engine.positionStream.listen((pos) {
      positionNotifier.value = pos;
      _updateLyricIndex();
    });

    _engine.setOnComplete(playNext);

    await _restoreLibrary();
  }

  Future<void> _restoreLibrary() async {
    if (Platform.isAndroid) {
      final treeUri = await SafStorage().persistedTree();
      if (treeUri != null) {
        _library = SafMediaLibrary(treeUri);
        await _loadLibrary();
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      final savedPath = prefs.getString('library_path');
      if (savedPath != null && Directory(savedPath).existsSync()) {
        _library = FileMediaLibrary(savedPath);
        await _loadLibrary();
      }
    }
  }

  Future<void> pickLibraryFolder() async {
    if (Platform.isAndroid) {
      // SAF system picker: no storage permissions, grant persists natively
      final treeUri = await SafStorage().pickTree();
      if (treeUri == null) return;
      _library = SafMediaLibrary(treeUri);
    } else {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Seleccionar carpeta music_library',
      );
      if (result == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('library_path', result);
      _library = FileMediaLibrary(result);
    }
    await _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    final lib = _library;
    if (lib == null) return;

    _isLoading = true;
    _statusText = 'Cargando playlist...';
    notifyListeners();

    try {
      _playlist = await lib.scan();
      _statusText = 'Playlist: ${_playlist.length} canciones';
    } catch (e) {
      debugPrint('library scan failed: $e');
      _playlist = [];
      _statusText = 'Error leyendo la carpeta';
    }
    _currentIndex = -1;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> playSong(int index) async {
    final lib = _library;
    if (lib == null || index < 0 || index >= _playlist.length) return;

    final token = ++_playToken;
    await _engine.stop();
    if (token != _playToken) return;

    _currentIndex = index;
    _lyrics = [];
    _currentLyricIndex = -1;
    _coverBytes = null;
    positionNotifier.value = Duration.zero;
    _status = PlaybackStatus.stopped;
    notifyListeners();

    final song = _playlist[index];

    try {
      final bytesList = await Future.wait(
        stemNames.map((n) => lib.read(song.stemRefs[n]!)),
      );
      if (token != _playToken) return;
      if (bytesList.any((b) => b == null)) {
        _statusText = 'Error cargando audio: pistas no encontradas';
        return;
      }
      final stemBytes = {
        for (var i = 0; i < stemNames.length; i++) stemNames[i]: bytesList[i]!,
      };

      final loaded = await _engine.load(song.stemRefs['drums']!, stemBytes);
      if (token != _playToken) return;
      if (!loaded) {
        _statusText = 'Error cargando audio: pistas no encontradas';
        return;
      }

      _duration = _engine.duration;
      await _engine.play();
      if (token != _playToken) return;
      _status = PlaybackStatus.playing;
      _statusText = song.displayName;

      _coverBytes = song.coverRef != null
          ? await lib.read(song.coverRef!)
          : null;
      _lyrics = song.lyricsRef != null
          ? parseLrcBytes(await lib.read(song.lyricsRef!))
          : [];
    } catch (e) {
      debugPrint('playSong error: $e');
      _statusText = 'Error reproduciendo: $e';
      _status = PlaybackStatus.stopped;
    } finally {
      if (token == _playToken) notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    if (_status == PlaybackStatus.playing) {
      await _engine.pause();
      _status = PlaybackStatus.paused;
    } else if (_status == PlaybackStatus.paused) {
      await _engine.play();
      _status = PlaybackStatus.playing;
    } else if (_currentIndex >= 0) {
      await playSong(_currentIndex);
      return;
    }
    notifyListeners();
  }

  Future<void> stop() async {
    _playToken++;
    await _engine.stop();
    _status = PlaybackStatus.stopped;
    positionNotifier.value = Duration.zero;
    _lyrics = [];
    _currentLyricIndex = -1;
    _statusText = 'Detenido';
    notifyListeners();
  }

  Future<void> playNext() async {
    if (_playlist.isEmpty) return;
    if (_repeatMode && _currentIndex >= 0) {
      await _replayCurrent();
    } else {
      await playSong((_currentIndex + 1) % _playlist.length);
    }
  }

  /// Repeat without reloading the 4 stem files: rewind and play.
  Future<void> _replayCurrent() async {
    await _engine.seek(Duration.zero);
    positionNotifier.value = Duration.zero;
    _currentLyricIndex = -1;
    await _engine.play();
    _status = PlaybackStatus.playing;
    notifyListeners();
  }

  Future<void> playPrevious() async {
    if (_playlist.isEmpty) return;
    await playSong((_currentIndex - 1 + _playlist.length) % _playlist.length);
  }

  Future<void> seekTo(Duration position) async {
    await _engine.seek(position);
    positionNotifier.value = position;
    _updateLyricIndex();
    // Discrete state change: lets the media session refresh its position
    notifyListeners();
  }

  void setMasterVolume(double v) {
    _engine.setMasterVolume(v);
    notifyListeners();
  }

  void setStemVolume(String name, double v) {
    _engine.setStemVolume(name, v);
    notifyListeners();
  }

  void toggleMute(String name) {
    _engine.toggleMute(name);
    notifyListeners();
  }

  void _updateLyricIndex() {
    if (_lyrics.isEmpty) return;
    final currentSecs = positionNotifier.value.inMilliseconds / 1000.0;
    int newIdx = -1;
    for (int i = 0; i < _lyrics.length; i++) {
      if (currentSecs >= _lyrics[i].timeSeconds) {
        newIdx = i;
      } else {
        break;
      }
    }
    if (newIdx != _currentLyricIndex) {
      _currentLyricIndex = newIdx;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    positionNotifier.dispose();
    _engine.dispose();
    super.dispose();
  }
}
