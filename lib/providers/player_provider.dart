import 'dart:async';
import 'dart:convert';
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
import '../utils/duration_format.dart';
import '../utils/playlist_sort.dart';
import '../utils/text_fold.dart';

/// "artist|title" — matches a Song regardless of playlist position or
/// sort order. Used to key the per-song duration/lyric-offset caches.
String _songKey(Song s) => '${s.artist}|${s.title}';

/// One entry of the cyclic sort toggle (desktop's _SORT_MODES,
/// audio_player.py). key == 'random' reshuffles every time it's applied.
typedef _SortMode = ({String key, bool reverse, String label});

const _sortModes = <_SortMode>[
  (key: 'artist', reverse: false, label: 'Artista A-Z'),
  (key: 'artist', reverse: true, label: 'Artista Z-A'),
  (key: 'song', reverse: false, label: 'Título A-Z'),
  (key: 'song', reverse: true, label: 'Título Z-A'),
  (key: 'random', reverse: false, label: 'Aleatorio'),
];

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

  /// Lets the muted vocals stem through during blank/instrumental lyric
  /// lines (see LrcLine.isBlankForAutoUnmute). On by default, like desktop.
  bool _autoUnmuteEnabled = true;

  /// Multiplies the base lyrics font size (desktop: 20-100px absolute,
  /// mobile: a relative scale since screen sizes vary far more).
  static const minLyricsScale = 0.6;
  static const maxLyricsScale = 2.5;
  double _lyricsScale = 1.0;

  /// Position updates at ~10 Hz. Exposed as a ValueNotifier so only the
  /// progress bar listens to it — the rest of the tree rebuilds via
  /// notifyListeners() only on real state changes.
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _positionSub;
  bool _repeatMode = false;

  /// Guards against interleaved playSong calls from rapid taps.
  int _playToken = 0;

  /// -1 = "Sin orden" (freshly loaded folder, desktop's default state).
  int _sortModeIndex = -1;
  String _searchQuery = '';

  /// "M:SS" durations, keyed by "artist|title", filled in the first time
  /// each song is played (duration isn't known until the stems are
  /// decoded — see PLAN_ACTUALIZACION.md §6.1). Persisted across app
  /// restarts.
  final Map<String, String> _durationCache = {};

  /// Per-song lyric timing offset in integer centiseconds (same unit
  /// desktop uses when rewriting .lrc timestamps, to avoid float rounding
  /// — see seconds_to_lrc_ts in lyrics_sync_editor.py). Applied only in
  /// memory; the .lrc file itself is never modified.
  final Map<String, int> _lyricOffsetCs = {};
  int _currentLyricOffsetCs = 0;

  bool _spectrumEnabled = false;

  /// Small LRU-ish caches (insertion-ordered maps, oldest evicted first) so
  /// re-visiting a nearby song doesn't re-read its cover/lyrics over
  /// SAF/disk, and so adjacent songs can be preloaded in the background.
  static const _coverCacheSize = 12;
  static const _lyricsCacheSize = 20;
  final _coverCache = <String, Uint8List?>{};
  final _lyricsCache = <String, List<LrcLine>>{};

  Timer? _playbackStateDebounce;

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
  bool get autoUnmuteEnabled => _autoUnmuteEnabled;
  double get lyricsScale => _lyricsScale;
  String get sortModeLabel =>
      _sortModeIndex < 0 ? 'Sin orden' : _sortModes[_sortModeIndex].label;
  String get searchQuery => _searchQuery;

  /// Current song's lyric offset in whole 0.5s steps (e.g. -1 = 0.5s
  /// earlier, 2 = 1s later). 0 when there's no current song.
  double get currentLyricOffsetSeconds => _currentLyricOffsetCs / 100.0;

  /// Indices into [playlist] matching the current search query (folded,
  /// accent/case-insensitive over artist + title), in playlist order. All
  /// indices when the query is empty.
  List<int> get visiblePlaylistIndices {
    if (_searchQuery.isEmpty) {
      return List.generate(_playlist.length, (i) => i);
    }
    final needle = foldText(_searchQuery);
    return [
      for (var i = 0; i < _playlist.length; i++)
        if (foldText(_playlist[i].artist).contains(needle) ||
            foldText(_playlist[i].title).contains(needle))
          i,
    ];
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  bool get spectrumEnabled => _spectrumEnabled;

  Future<void> toggleSpectrum() async {
    _spectrumEnabled = !_spectrumEnabled;
    await _engine.setVisualizationEnabled(_spectrumEnabled);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('spectrum_enabled', _spectrumEnabled);
  }

  void toggleRepeat() {
    _repeatMode = !_repeatMode;
    notifyListeners();
    _schedulePersistPlaybackState();
  }

  Future<void> toggleAutoUnmute() async {
    _autoUnmuteEnabled = !_autoUnmuteEnabled;
    _applyAutoUnmute();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_unmute_enabled', _autoUnmuteEnabled);
  }

  void setLyricsScale(double scale) {
    final clamped = scale.clamp(minLyricsScale, maxLyricsScale).toDouble();
    if (clamped == _lyricsScale) return;
    _lyricsScale = clamped;
    notifyListeners();
    _persistLyricsScale();
  }

  void adjustLyricsScale(double delta) => setLyricsScale(_lyricsScale + delta);

  Future<void> _persistLyricsScale() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('lyrics_scale', _lyricsScale);
  }

  Song? get currentSong =>
      _currentIndex >= 0 && _currentIndex < _playlist.length
      ? _playlist[_currentIndex]
      : null;

  Future<void> initialize() async {
    _positionSub = _engine.positionStream.listen((pos) {
      positionNotifier.value = pos;
      _updateLyricIndex();
      _applyAutoUnmute();
    });

    _engine.setOnComplete(playNext);

    final prefs = await SharedPreferences.getInstance();
    _autoUnmuteEnabled = prefs.getBool('auto_unmute_enabled') ?? true;
    _lyricsScale = prefs.getDouble('lyrics_scale') ?? 1.0;
    _loadJsonStringMap(prefs, 'duration_cache', _durationCache);
    _loadJsonIntMap(prefs, 'lyric_offsets', _lyricOffsetCs);
    _restorePlaybackState(prefs);

    _spectrumEnabled = prefs.getBool('spectrum_enabled') ?? false;
    if (_spectrumEnabled) unawaited(_engine.setVisualizationEnabled(true));

    await _restoreLibrary();
  }

  /// Restores master/stem volumes, mutes and repeat across app restarts.
  /// The engine defaults (master 0.25, stems unmuted at 1.0) stay in place
  /// for a first-ever launch, when there's nothing saved yet.
  void _restorePlaybackState(SharedPreferences prefs) {
    final master = prefs.getDouble('master_volume');
    if (master != null) _engine.setMasterVolume(master);

    final volumesRaw = prefs.getString('stem_volumes');
    if (volumesRaw != null) {
      try {
        final decoded = jsonDecode(volumesRaw);
        if (decoded is Map) {
          for (final n in stemNames) {
            final v = decoded[n];
            if (v is num) _engine.setStemVolume(n, v.toDouble());
          }
        }
      } catch (_) {}
    }

    final mutesRaw = prefs.getString('stem_mutes');
    if (mutesRaw != null) {
      try {
        final decoded = jsonDecode(mutesRaw);
        if (decoded is Map) {
          for (final n in stemNames) {
            final v = decoded[n];
            if (v is bool) _engine.setMuted(n, v);
          }
        }
      } catch (_) {}
    }

    _repeatMode = prefs.getBool('repeat_mode') ?? false;
  }

  void _schedulePersistPlaybackState() {
    _playbackStateDebounce?.cancel();
    _playbackStateDebounce = Timer(
      const Duration(milliseconds: 400),
      _persistPlaybackState,
    );
  }

  Future<void> _persistPlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('master_volume', _engine.masterVolume);
    await prefs.setString('stem_volumes', jsonEncode(_engine.stemVolumes));
    await prefs.setString('stem_mutes', jsonEncode(_engine.muteStates));
    await prefs.setBool('repeat_mode', _repeatMode);
  }

  void _loadJsonStringMap(
    SharedPreferences prefs,
    String key,
    Map<String, String> into,
  ) {
    final raw = prefs.getString(key);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final e in decoded.entries) {
          into[e.key] = e.value.toString();
        }
      }
    } catch (_) {}
  }

  void _loadJsonIntMap(
    SharedPreferences prefs,
    String key,
    Map<String, int> into,
  ) {
    final raw = prefs.getString(key);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final e in decoded.entries) {
          if (e.value is int) into[e.key] = e.value as int;
        }
      }
    } catch (_) {}
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
      final scanned = await lib.scan();
      // Dedup by (artist, title) — a data.json with several song entries,
      // or two folders describing the same song, would otherwise show up
      // twice (desktop keys its playlist the same way).
      final seen = <Song>{};
      _playlist = [
        for (final s in scanned)
          if (seen.add(s)) s,
      ];
      for (final song in _playlist) {
        song.duration = _durationCache[_songKey(song)];
      }
      _coverCache.clear();
      _lyricsCache.clear();
      _statusText = 'Playlist: ${_playlist.length} canciones';
    } catch (e) {
      debugPrint('library scan failed: $e');
      _playlist = [];
      _statusText = 'Error leyendo la carpeta';
    }
    _currentIndex = -1;
    _sortModeIndex = -1;
    _searchQuery = '';
    _isLoading = false;
    notifyListeners();
  }

  /// Advances the toggle button through the 5 sort modes (desktop's
  /// `_cycle_sort`): Artista A-Z/Z-A, Título A-Z/Z-A, Aleatorio.
  void cycleSort() {
    final next = (_sortModeIndex + 1) % _sortModes.length;
    final mode = _sortModes[next];
    sortPlaylist(mode.key, reverse: mode.reverse);
    _sortModeIndex = next;
  }

  /// Sorts by artist, title, or shuffles ("random"); preserves the
  /// currently playing song's position by identity (desktop's
  /// `sort_playlist`, audio_player.py).
  void sortPlaylist(String key, {bool reverse = false}) {
    if (_playlist.isEmpty) return;

    final idx = _sortModes.indexWhere(
      (m) => m.key == key && m.reverse == reverse,
    );
    if (idx >= 0) _sortModeIndex = idx;

    final current = _currentIndex >= 0 && _currentIndex < _playlist.length
        ? _playlist[_currentIndex]
        : null;

    _playlist = sortedSongs(_playlist, key: key, reverse: reverse);

    if (current != null) _currentIndex = _playlist.indexOf(current);
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
      _cacheDuration(song, _duration);
      _currentLyricOffsetCs = _lyricOffsetCs[_songKey(song)] ?? 0;
      await _engine.play();
      if (token != _playToken) return;
      _status = PlaybackStatus.playing;
      _statusText = song.displayName;

      _coverBytes = await _readCover(lib, song);
      _lyrics = await _readLyrics(lib, song);
      _preloadAdjacent(lib);
    } catch (e) {
      debugPrint('playSong error: $e');
      _statusText = 'Error reproduciendo: $e';
      _status = PlaybackStatus.stopped;
    } finally {
      if (token == _playToken) notifyListeners();
    }
  }

  Future<Uint8List?> _readCover(MediaLibrary lib, Song song) async {
    if (song.coverRef == null) return null;
    final key = _songKey(song);
    if (_coverCache.containsKey(key)) {
      return _touchCache(_coverCache, key);
    }
    final bytes = await lib.read(song.coverRef!);
    _putCache(_coverCache, key, bytes, _coverCacheSize);
    return bytes;
  }

  Future<List<LrcLine>> _readLyrics(MediaLibrary lib, Song song) async {
    if (song.lyricsRef == null) return [];
    final key = _songKey(song);
    if (_lyricsCache.containsKey(key)) {
      return _touchCache(_lyricsCache, key);
    }
    final parsed = parseLrcBytes(await lib.read(song.lyricsRef!));
    _putCache(_lyricsCache, key, parsed, _lyricsCacheSize);
    return parsed;
  }

  /// Re-inserts [key] so it counts as most-recently-used.
  V _touchCache<V>(Map<String, V> cache, String key) {
    final value = cache.remove(key) as V;
    cache[key] = value;
    return value;
  }

  void _putCache<V>(Map<String, V> cache, String key, V value, int maxSize) {
    cache[key] = value;
    while (cache.length > maxSize) {
      cache.remove(cache.keys.first);
    }
  }

  /// Background-warms the cover/lyrics cache for the previous and next
  /// songs so skipping feels instant (desktop preloads adjacent songs the
  /// same way — LazyImageManager/LazyLyricsManager in lazy_resources.py).
  void _preloadAdjacent(MediaLibrary lib) {
    if (_playlist.length < 2) return;
    for (final offset in [-1, 1]) {
      final idx =
          (_currentIndex + offset + _playlist.length) % _playlist.length;
      if (idx == _currentIndex) continue;
      final song = _playlist[idx];
      unawaited(_readCover(lib, song));
      unawaited(_readLyrics(lib, song));
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
    // Keep _lyrics: the song stays selected, so discarding them made the
    // lyrics tab claim "Sin letras disponibles" until playback restarted.
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

  /// Relative seek, clamped to the track — used by the ±5s transport
  /// buttons (desktop's keyboard shortcut, §2.1).
  Future<void> seekBy(Duration delta) async {
    final target = position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    await seekTo(clamped);
  }

  void _cacheDuration(Song song, Duration d) {
    if (d <= Duration.zero) return;
    final formatted = formatSongDuration(d);
    if (song.duration == formatted) return;
    song.duration = formatted;
    _durationCache[_songKey(song)] = formatted;
    unawaited(_persistJsonMap('duration_cache', _durationCache));
  }

  /// Shifts the current song's lyrics by 0.5s steps (desktop's
  /// Ctrl+Shift+←/→, §2.4): negative = earlier ("adelantar"), positive =
  /// later ("retrasar"). In-memory only — the .lrc file is never rewritten.
  void adjustLyricOffset(int deltaCs) {
    final song = currentSong;
    if (song == null) return;
    _currentLyricOffsetCs += deltaCs;
    _lyricOffsetCs[_songKey(song)] = _currentLyricOffsetCs;
    _updateLyricIndex(force: true);
    notifyListeners();
    unawaited(_persistJsonMap('lyric_offsets', _lyricOffsetCs));
  }

  Future<void> _persistJsonMap(String key, Map<String, Object> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(map));
  }

  void setMasterVolume(double v) {
    _engine.setMasterVolume(v);
    notifyListeners();
    _schedulePersistPlaybackState();
  }

  void setStemVolume(String name, double v) {
    _engine.setStemVolume(name, v);
    notifyListeners();
    _schedulePersistPlaybackState();
  }

  void toggleMute(String name) {
    _engine.toggleMute(name);
    _applyAutoUnmute();
    notifyListeners();
    _schedulePersistPlaybackState();
  }

  /// Drives AudioEngine's fade based on whether the active lyric line is
  /// blank/instrumental. Mirrors desktop's `_auto_unmute_ramp`: only takes
  /// effect while vocals is muted and the feature is enabled; before the
  /// first lyric line (currentLyricIndex == -1) it never triggers.
  void _applyAutoUnmute() {
    if (!_autoUnmuteEnabled || !(_engine.muteStates['vocals'] ?? false)) {
      _engine.setAutoUnmuteGain(false);
      return;
    }
    final blank =
        _currentLyricIndex >= 0 &&
        _currentLyricIndex < _lyrics.length &&
        _lyrics[_currentLyricIndex].isBlankForAutoUnmute;
    _engine.setAutoUnmuteGain(blank);
  }

  void _updateLyricIndex({bool force = false}) {
    if (_lyrics.isEmpty) return;
    final offsetSecs = _currentLyricOffsetCs / 100.0;
    final currentSecs = positionNotifier.value.inMilliseconds / 1000.0;
    int newIdx = -1;
    for (int i = 0; i < _lyrics.length; i++) {
      if (currentSecs >= _lyrics[i].timeSeconds + offsetSecs) {
        newIdx = i;
      } else {
        break;
      }
    }
    if (newIdx != _currentLyricIndex || force) {
      _currentLyricIndex = newIdx;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _playbackStateDebounce?.cancel();
    positionNotifier.dispose();
    _engine.dispose();
    super.dispose();
  }
}
