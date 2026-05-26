import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lrc_line.dart';
import '../models/song.dart';
import '../services/audio_engine.dart';
import '../services/library_scanner.dart';
import '../services/lrc_parser.dart';

class PlayerProvider extends ChangeNotifier {
  final AudioEngine _engine = AudioEngine();

  List<Song> _playlist = [];
  int _currentIndex = -1;
  PlaybackStatus _status = PlaybackStatus.stopped;
  String? _libraryPath;
  bool _isLoading = false;
  String _statusText = 'Listo';

  List<LrcLine> _lyrics = [];
  int _currentLyricIndex = -1;
  Timer? _lyricsTimer;
  Timer? _statusTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _positionSub;
  bool _repeatMode = false;

  List<Song> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  PlaybackStatus get status => _status;
  String? get libraryPath => _libraryPath;
  bool get isLoading => _isLoading;
  String get statusText => _statusText;
  List<LrcLine> get lyrics => _lyrics;
  int get currentLyricIndex => _currentLyricIndex;
  Duration get position => _position;
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
      _position = pos;
      notifyListeners();
    });

    _engine.setOnComplete(playNext);

    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });

    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('library_path');
    if (savedPath != null && Directory(savedPath).existsSync()) {
      _libraryPath = savedPath;
      await _loadLibrary(savedPath);
    }
  }

  Future<void> pickLibraryFolder() async {
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        final legacy = await Permission.storage.request();
        if (!legacy.isGranted) return;
      }
    }

    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Seleccionar carpeta music_library',
    );
    if (result == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('library_path', result);
    _libraryPath = result;
    await _loadLibrary(result);
  }

  Future<void> _loadLibrary(String path) async {
    _isLoading = true;
    _statusText = 'Cargando playlist...';
    notifyListeners();

    final songs = await scanLibrary(path);
    _playlist = songs;
    _currentIndex = -1;
    _isLoading = false;
    _statusText = 'Playlist: ${songs.length} canciones';
    notifyListeners();
  }

  Future<void> playSong(int index) async {
    if (index < 0 || index >= _playlist.length) return;

    await _engine.stop();
    _currentIndex = index;
    _lyrics = [];
    _currentLyricIndex = -1;
    _position = Duration.zero;
    _status = PlaybackStatus.stopped;
    notifyListeners();

    final song = _playlist[index];

    try {
      final loaded = await _engine.load(song.folderPath);
      if (!loaded) {
        _statusText = 'Error cargando audio: pistas no encontradas';
        return;
      }

      _duration = _engine.duration;
      await _engine.play();
      _status = PlaybackStatus.playing;
      _statusText = song.displayName;

      _lyrics = await parseLrcFile(song.lyricsPath);
      _startLyricsTimer();
    } catch (e) {
      _statusText = 'Error reproduciendo: $e';
      _status = PlaybackStatus.stopped;
    } finally {
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    if (_status == PlaybackStatus.playing) {
      await _engine.pause();
      _status = PlaybackStatus.paused;
      _lyricsTimer?.cancel();
    } else if (_status == PlaybackStatus.paused) {
      await _engine.play();
      _status = PlaybackStatus.playing;
      _startLyricsTimer();
    } else if (_currentIndex >= 0) {
      await playSong(_currentIndex);
      return;
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _engine.stop();
    _status = PlaybackStatus.stopped;
    _position = Duration.zero;
    _lyrics = [];
    _currentLyricIndex = -1;
    _lyricsTimer?.cancel();
    _statusText = 'Detenido';
    notifyListeners();
  }

  Future<void> playNext() async {
    if (_playlist.isEmpty) return;
    if (_repeatMode) {
      await playSong(_currentIndex);
    } else {
      await playSong((_currentIndex + 1) % _playlist.length);
    }
  }

  Future<void> playPrevious() async {
    if (_playlist.isEmpty) return;
    await playSong((_currentIndex - 1 + _playlist.length) % _playlist.length);
  }

  Future<void> seekTo(Duration position) async {
    await _engine.seek(position);
    _position = position;
    _updateLyricIndex();
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

  void _startLyricsTimer() {
    _lyricsTimer?.cancel();
    _lyricsTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _updateLyricIndex();
    });
  }

  void _updateLyricIndex() {
    if (_lyrics.isEmpty) return;
    final currentSecs = _position.inMilliseconds / 1000.0;
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
    _lyricsTimer?.cancel();
    _statusTimer?.cancel();
    _engine.dispose();
    super.dispose();
  }
}
