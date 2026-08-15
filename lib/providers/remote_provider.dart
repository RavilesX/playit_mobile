import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/remote_state.dart';
import '../services/remote_client.dart';
import '../services/remote_discovery.dart';

const _prefHost = 'remote_host';
const _prefPort = 'remote_port';
const _prefToken = 'remote_token';
const _prefName = 'remote_name';

enum RemoteConnection { desconectado, conectando, conectado, error }

/// Drives the remote-control session: pairing, polling, and commands.
///
/// Deliberately separate from PlayerProvider. The remote has no audio engine,
/// and the local player has no business knowing about sockets — the only
/// contact between them lives in the screen (entering remote mode stops local
/// playback so two sources never sound at once).
class RemoteProvider extends ChangeNotifier {
  /// How often the desktop is polled while the screen is in the foreground.
  static const pollInterval = Duration(seconds: 1);

  /// A command is acknowledged over HTTP *before* the desktop's GUI thread
  /// runs it — the handler only queues a Qt signal (PLAN_REMOTO.md §5.2). So
  /// the confirming refresh waits a beat; otherwise it reads the snapshot
  /// from before the command and undoes the optimistic update for one frame.
  static const confirmDelay = Duration(milliseconds: 250);

  /// Wi-Fi drops a packet now and then. Only give up after this many polls in
  /// a row fail, so a single hiccup doesn't tear down a working session.
  static const maxPollFailures = 3;

  RemoteConnection _connection = RemoteConnection.desconectado;
  RemoteState _state = RemoteState.unknown;
  RemotePlaylist _playlist = RemotePlaylist.empty;
  PairingInfo? _pairing;
  RemoteClient? _client;
  String _errorMessage = '';

  /// Why the last attempt failed, so [connectToSaved] can tell "the PC moved"
  /// (worth searching the network for) from "the code is wrong" (isn't).
  RemoteErrorKind? _lastErrorKind;

  Timer? _pollTimer;
  bool _polling = false;
  bool _pollInFlight = false;
  int _pollFailures = 0;

  /// Cover of the song the desktop is on, and the "rev|index" it belongs to.
  /// Only the current one is kept: the screen never shows another, and a
  /// cache of covers for a playlist that lives on the PC is memory spent on
  /// images the user may never see.
  Uint8List? _coverBytes;
  String? _coverKey;
  bool _coverInFlight = false;

  /// Bumped on every connect/disconnect so late responses from a previous
  /// session can't write into the current one.
  int _sessionToken = 0;

  RemoteConnection get connection => _connection;
  RemoteState get state => _state;
  RemotePlaylist get playlist => _playlist;
  PairingInfo? get pairing => _pairing;
  String get errorMessage => _errorMessage;

  /// Cover of the current song, or null while it loads / when it has none.
  Uint8List? get coverBytes => _coverBytes;

  bool get isConnected => _connection == RemoteConnection.conectado;
  bool get isBusy => _connection == RemoteConnection.conectando;

  /// Name of the paired PC, for the app bar.
  String get desktopName =>
      _pairing?.name.isNotEmpty == true ? _pairing!.name : (_pairing?.host ?? '');

  // ── Emparejamiento ────────────────────────────────────────────────────

  /// Pairing saved from a previous session, or null if never paired.
  static Future<PairingInfo?> savedPairing() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_prefHost);
    final token = prefs.getString(_prefToken);
    if (host == null || host.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    return PairingInfo(
      host: host,
      port: prefs.getInt(_prefPort) ?? kDefaultRemotePort,
      token: token,
      name: prefs.getString(_prefName) ?? '',
    );
  }

  /// Validates the pairing against the desktop, downloads playlist + state and
  /// starts polling. Returns false and fills [errorMessage] on failure.
  Future<bool> connect(PairingInfo info) async {
    await disconnect();

    final session = ++_sessionToken;
    _pairing = info;
    _connection = RemoteConnection.conectando;
    _errorMessage = '';
    _lastErrorKind = null;
    notifyListeners();

    final client = RemoteClient(info);
    try {
      final name = await client.hello();
      final playlist = await client.playlist();
      final state = await client.state();
      if (session != _sessionToken) {
        client.dispose();
        return false;
      }

      _client = client;
      _pairing = info.withName(name);
      _playlist = playlist;
      _state = state;
      _connection = RemoteConnection.conectado;
      _pollFailures = 0;
      await _persist(_pairing!);
      notifyListeners();
      resumePolling();
      unawaited(_refreshCover());
      return true;
    } on RemoteException catch (e) {
      client.dispose();
      if (session != _sessionToken) return false;
      _connection = RemoteConnection.error;
      _errorMessage = e.message;
      _lastErrorKind = e.kind;
      notifyListeners();
      return false;
    }
  }

  /// Reconnects to the PC paired last time. False when there is none saved.
  ///
  /// If the saved address no longer answers, the network is searched for the
  /// same desktop and the saved token is retried at whatever address it has
  /// now — that is what keeps a DHCP lease change from forcing the user to
  /// scan the QR again. A rejected *token* is not retried: that one really
  /// does need re-pairing.
  Future<bool> connectToSaved() async {
    final saved = await savedPairing();
    if (saved == null) return false;
    if (await connect(saved)) return true;
    if (_lastErrorKind != RemoteErrorKind.noResponde) return false;

    for (final desktop in await discoverDesktops()) {
      if (desktop.host == saved.host && desktop.port == saved.port) {
        continue; // already tried, and it didn't answer
      }
      if (await connect(desktop.pairingWith(saved))) return true;
    }
    return false;
  }

  /// Looks for PlayIt desktops on the local network. Used by the "buscar"
  /// button on the pairing screen; the token still has to come from the QR or
  /// be typed, so this only saves reading an IP off the PC's screen.
  Future<List<DiscoveredDesktop>> discover() => discoverDesktops();

  Future<void> disconnect() async {
    _sessionToken++;
    pausePolling();
    _client?.dispose();
    _client = null;
    _connection = RemoteConnection.desconectado;
    _state = RemoteState.unknown;
    _playlist = RemotePlaylist.empty;
    _errorMessage = '';
    _coverBytes = null;
    _coverKey = null;
    notifyListeners();
  }

  /// Disconnects and forgets the saved token, so the next session has to scan
  /// the QR again. For "Olvidar esta PC".
  Future<void> forget() async {
    await disconnect();
    _pairing = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefHost);
    await prefs.remove(_prefPort);
    await prefs.remove(_prefToken);
    await prefs.remove(_prefName);
    notifyListeners();
  }

  Future<void> _persist(PairingInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefHost, info.host);
    await prefs.setInt(_prefPort, info.port);
    await prefs.setString(_prefToken, info.token);
    await prefs.setString(_prefName, info.name);
  }

  // ── Sondeo ────────────────────────────────────────────────────────────

  /// Starts the 1 Hz poll. Called on connect and when the screen comes back to
  /// the foreground.
  void resumePolling() {
    if (_polling || !isConnected) return;
    _polling = true;
    _pollTimer = Timer.periodic(pollInterval, (_) => _poll());
    _poll();
  }

  /// Stops polling. Must be called when the screen is left or the app is
  /// backgrounded — a network timer surviving in the background is battery
  /// burned for nothing.
  void pausePolling() {
    _polling = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _poll() async {
    final client = _client;
    if (client == null || _pollInFlight) return;
    _pollInFlight = true;
    final session = _sessionToken;
    try {
      final state = await client.state();
      if (session != _sessionToken) return;
      _pollFailures = 0;
      _applyState(state);
      // The desktop bumps `rev` whenever its playlist changes (folder loaded,
      // song separated, re-sorted): that is the signal to download it again.
      if (state.rev != _playlist.rev) {
        final playlist = await client.playlist();
        if (session != _sessionToken) return;
        _playlist = playlist;
        notifyListeners();
      }
    } on RemoteException catch (e) {
      if (session != _sessionToken) return;
      // A rejected token will never start working again on its own; retrying
      // it once a second only delays telling the user to re-pair.
      if (e.kind == RemoteErrorKind.noAutorizado) {
        _failSession(e.message);
        return;
      }
      if (++_pollFailures >= maxPollFailures) _failSession(e.message);
    } finally {
      _pollInFlight = false;
    }
  }

  void _applyState(RemoteState next) {
    final changed =
        next.playback != _state.playback ||
        next.index != _state.index ||
        next.repeat != _state.repeat ||
        next.song != _state.song ||
        next.artist != _state.artist ||
        next.count != _state.count ||
        next.duration != _state.duration ||
        next.position.inSeconds != _state.position.inSeconds;
    _state = next;
    if (changed) notifyListeners();
    unawaited(_refreshCover());
  }

  /// Downloads the current song's cover when it changed. A new playlist
  /// revision also invalidates it: index 3 may well be a different song now.
  Future<void> _refreshCover() async {
    final client = _client;
    if (client == null || _coverInFlight) return;

    if (_state.index < 0) {
      if (_coverBytes == null && _coverKey == null) return;
      _coverBytes = null;
      _coverKey = null;
      notifyListeners();
      return;
    }

    final key = '${_state.rev}|${_state.index}';
    if (key == _coverKey) return;

    _coverInFlight = true;
    final session = _sessionToken;
    try {
      final bytes = await client.cover(_state.index);
      if (session != _sessionToken) return;
      _coverKey = key;
      _coverBytes = bytes;
      notifyListeners();
    } on RemoteException {
      // A missing cover must never look like a lost connection: the polling
      // is the only thing allowed to judge whether the PC is still there.
      if (session != _sessionToken) return;
      _coverKey = key;
      _coverBytes = null;
      notifyListeners();
    } finally {
      _coverInFlight = false;
    }
  }

  void _failSession(String message) {
    pausePolling();
    _client?.dispose();
    _client = null;
    _connection = RemoteConnection.error;
    _errorMessage = message;
    notifyListeners();
  }

  // ── Comandos ──────────────────────────────────────────────────────────

  /// Sends a command, updating the UI immediately with the expected outcome
  /// and letting the confirming poll correct it (see [confirmDelay]).
  Future<void> send(RemoteCommand cmd, {int? index, bool? value}) async {
    final client = _client;
    if (client == null) return;
    final session = _sessionToken;

    final previous = _state;
    _state = _state.optimistic(cmd, index: index, value: value);
    notifyListeners();

    try {
      await client.send(cmd, index: index, value: value);
      _pollFailures = 0;
      await Future.delayed(confirmDelay);
      if (session != _sessionToken) return;
      await _poll();
    } on RemoteException catch (e) {
      if (session != _sessionToken) return;
      // The command never landed: undo the guess instead of leaving the UI
      // claiming something the PC never did.
      _state = previous;
      if (e.kind == RemoteErrorKind.noAutorizado) {
        _failSession(e.message);
      } else {
        _errorMessage = e.message;
        notifyListeners();
      }
    }
  }

  Future<void> togglePlayPause() => send(RemoteCommand.playPause);
  Future<void> stop() => send(RemoteCommand.stop);
  Future<void> next() => send(RemoteCommand.next);
  Future<void> previous() => send(RemoteCommand.prev);
  Future<void> toggleRepeat() =>
      send(RemoteCommand.repeat, value: !_state.repeat);
  Future<void> playIndex(int index) =>
      send(RemoteCommand.playIndex, index: index);

  /// Clears a transient command error without dropping the session.
  void clearError() {
    if (_errorMessage.isEmpty || _connection == RemoteConnection.error) return;
    _errorMessage = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionToken++;
    pausePolling();
    _client?.dispose();
    _client = null;
    super.dispose();
  }
}
