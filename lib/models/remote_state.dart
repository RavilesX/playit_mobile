/// Data model of the remote-control protocol (PLAN_REMOTO.md §3).
///
/// Everything here is a pure parser over the JSON the desktop serves — no
/// network, no Flutter binding — so it is unit-tested directly.
library;

import 'dart:convert';

/// Protocol version this build speaks. The desktop reports its own in
/// `/api/hello`; a higher one means the phone is the outdated half.
const kRemoteProtocolVersion = 1;

/// Commands the desktop accepts on `/api/command`.
enum RemoteCommand { playPause, stop, next, prev, repeat, playIndex }

extension RemoteCommandWire on RemoteCommand {
  String get wire => switch (this) {
    RemoteCommand.playPause => 'play_pause',
    RemoteCommand.stop => 'stop',
    RemoteCommand.next => 'next',
    RemoteCommand.prev => 'prev',
    RemoteCommand.repeat => 'repeat',
    RemoteCommand.playIndex => 'play_index',
  };
}

/// Desktop playback state. The wire format uses the Spanish strings the
/// desktop already keeps in `AudioPlayer.playback_state`.
enum RemotePlayback { detenido, activa, pausada }

RemotePlayback _playbackFromWire(Object? raw) => switch (raw) {
  'Activa' => RemotePlayback.activa,
  'Pausada' => RemotePlayback.pausada,
  _ => RemotePlayback.detenido,
};

/// Connection details for one desktop, obtained from the QR code or typed by
/// hand. Persisted so the phone reconnects without pairing again.
class PairingInfo {
  final String host;
  final int port;
  final String token;

  /// Name to show in the UI ("PC-Ricardo"). Empty until `/api/hello` answers.
  final String name;

  const PairingInfo({
    required this.host,
    required this.port,
    required this.token,
    this.name = '',
  });

  PairingInfo withName(String value) =>
      PairingInfo(host: host, port: port, token: token, name: value);

  /// Parses the payload encoded in the desktop's QR code:
  /// `{"v":1,"h":"192.168.1.42","p":8770,"t":"<32 hex>","n":"PC-Ricardo"}`
  ///
  /// Throws [RemotePairingException] with a user-facing Spanish message when
  /// the text is not a pairing payload or comes from a newer protocol.
  static PairingInfo parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw.trim());
    } on FormatException {
      throw const RemotePairingException(
        'El código no es de PlayIt Desktop.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const RemotePairingException('El código no es de PlayIt Desktop.');
    }

    final version = decoded['v'];
    if (version is int && version > kRemoteProtocolVersion) {
      throw const RemotePairingException(
        'La PC usa una versión más nueva. Actualizá PlayIt Mobile.',
        recognized: true,
      );
    }

    final host = decoded['h'];
    final token = decoded['t'];
    final port = decoded['p'];
    if (host is! String ||
        host.isEmpty ||
        token is! String ||
        token.isEmpty ||
        port is! int) {
      throw const RemotePairingException(
        'El código está incompleto.',
        recognized: true,
      );
    }

    return PairingInfo(
      host: host,
      port: port,
      token: token,
      name: decoded['n'] is String ? decoded['n'] as String : '',
    );
  }

  /// Validates hand-typed pairing data. [address] is `host` or `host:port`.
  static PairingInfo fromManual(String address, String token) {
    final cleanAddress = address.trim();
    final cleanToken = token.replaceAll(RegExp(r'\s'), '');
    if (cleanAddress.isEmpty) {
      throw const RemotePairingException('Falta la dirección de la PC.');
    }
    if (cleanToken.isEmpty) {
      throw const RemotePairingException('Falta el código de la PC.');
    }

    var host = cleanAddress;
    var port = kDefaultRemotePort;
    final colon = cleanAddress.lastIndexOf(':');
    if (colon > 0) {
      final parsed = int.tryParse(cleanAddress.substring(colon + 1));
      if (parsed == null || parsed < 1 || parsed > 65535) {
        throw const RemotePairingException('El puerto no es válido.');
      }
      host = cleanAddress.substring(0, colon);
      port = parsed;
    }
    if (host.isEmpty) {
      throw const RemotePairingException('Falta la dirección de la PC.');
    }

    return PairingInfo(host: host, port: port, token: cleanToken);
  }

  String get address => '$host:$port';

  /// Token in groups of four, the way the desktop dialog shows it.
  String get prettyToken => [
    for (var i = 0; i < token.length; i += 4)
      token.substring(i, i + 4 > token.length ? token.length : i + 4),
  ].join(' ');
}

/// Picks the pairing out of everything the camera read in one frame.
///
/// Kept here, apart from the scanner widget, so it can be tested without a
/// camera: the QR reader hands over raw strings and nothing else. A frame may
/// hold several codes (a poster, a sticker, a screen behind the PC), so every
/// value is tried before giving up.
///
/// Throws [RemotePairingException] with the most useful failure in the frame:
/// a PlayIt code we can't use ("actualizá la app") beats a QR that was never
/// ours ("no es de PlayIt Desktop"), because only the first one tells the user
/// they are pointing at the right thing.
PairingInfo pairingFromBarcodes(Iterable<String?> rawValues) {
  RemotePairingException? failure;

  for (final raw in rawValues) {
    if (raw == null || raw.trim().isEmpty) continue;
    try {
      return PairingInfo.parse(raw);
    } on RemotePairingException catch (e) {
      if (failure == null || (e.recognized && !failure.recognized)) {
        failure = e;
      }
    }
  }

  throw failure ?? const RemotePairingException('No se leyó ningún código.');
}

/// Default port of the desktop server (`DEFAULT_PORT` in `remote_server.py`).
/// It falls back to 8771-8779 when busy, hence the manual `host:port` form.
const kDefaultRemotePort = 8770;

/// Raised while pairing, before there is any connection to talk about.
class RemotePairingException implements Exception {
  final String message;

  /// True when the payload did decode as a PlayIt-shaped object and failed for
  /// a reason worth telling the user about (unsupported version, missing
  /// field), as opposed to a QR that has nothing to do with the app. Lets
  /// [pairingFromBarcodes] pick the message that helps when the camera sees
  /// several codes at once.
  final bool recognized;

  const RemotePairingException(this.message, {this.recognized = false});

  @override
  String toString() => 'RemotePairingException: $message';
}

/// One row of the desktop's playlist. Metadata only — no audio, no paths.
class RemoteTrack {
  final int index;
  final String artist;
  final String song;

  /// "M:SS" as the desktop computed it; empty when it doesn't know yet.
  final String duration;

  const RemoteTrack({
    required this.index,
    required this.artist,
    required this.song,
    this.duration = '',
  });

  /// Never throws: a malformed row degrades to blanks rather than killing the
  /// whole list. `i` falling back to [fallbackIndex] keeps taps addressing the
  /// right song even if the desktop omits the field.
  factory RemoteTrack.fromJson(Map<String, dynamic> json, int fallbackIndex) {
    final i = json['i'];
    return RemoteTrack(
      index: i is int ? i : fallbackIndex,
      artist: json['artist'] is String ? json['artist'] as String : '',
      song: json['song'] is String ? json['song'] as String : '',
      duration: json['duration'] is String ? json['duration'] as String : '',
    );
  }

  String get displayName => '$artist - $song';
}

/// The desktop's playlist plus the revision it was taken at.
class RemotePlaylist {
  final int rev;
  final List<RemoteTrack> items;

  const RemotePlaylist({required this.rev, required this.items});

  static const empty = RemotePlaylist(rev: -1, items: []);

  factory RemotePlaylist.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return RemotePlaylist(
      rev: json['rev'] is int ? json['rev'] as int : 0,
      items: raw is! List
          ? const []
          : [
              for (var i = 0; i < raw.length; i++)
                if (raw[i] is Map<String, dynamic>)
                  RemoteTrack.fromJson(raw[i] as Map<String, dynamic>, i),
            ],
    );
  }
}

/// Snapshot of what the desktop is doing right now (`/api/state`).
class RemoteState {
  final RemotePlayback playback;
  final int index;
  final String artist;
  final String song;
  final Duration position;
  final Duration duration;
  final bool repeat;
  final int count;

  /// Playlist revision. When it differs from the cached playlist's, the list
  /// changed on the PC (folder loaded, song separated, re-sorted) and has to
  /// be downloaded again.
  final int rev;

  const RemoteState({
    required this.playback,
    required this.index,
    required this.artist,
    required this.song,
    required this.position,
    required this.duration,
    required this.repeat,
    required this.count,
    required this.rev,
  });

  static const unknown = RemoteState(
    playback: RemotePlayback.detenido,
    index: -1,
    artist: '',
    song: '',
    position: Duration.zero,
    duration: Duration.zero,
    repeat: false,
    count: 0,
    rev: -1,
  );

  /// Tolerant by design: a missing or oddly-typed field becomes its default
  /// instead of throwing. A control remote that blanks out because the PC
  /// sent `null` where an int was expected is worse than one showing 0:00.
  factory RemoteState.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v, [int fallback = 0]) => v is int
        ? v
        : v is num
        ? v.toInt()
        : fallback;

    return RemoteState(
      playback: _playbackFromWire(json['state']),
      index: asInt(json['index'], -1),
      artist: json['artist'] is String ? json['artist'] as String : '',
      song: json['song'] is String ? json['song'] as String : '',
      position: Duration(milliseconds: asInt(json['position_ms'])),
      duration: Duration(milliseconds: asInt(json['duration_ms'])),
      repeat: json['repeat'] == true,
      count: asInt(json['count']),
      rev: asInt(json['rev'], -1),
    );
  }

  bool get isPlaying => playback == RemotePlayback.activa;
  bool get isStopped => playback == RemotePlayback.detenido;
  bool get hasSong => index >= 0 && (artist.isNotEmpty || song.isNotEmpty);

  String get displayName => hasSong ? '$artist - $song' : '';

  String get playbackLabel => switch (playback) {
    RemotePlayback.activa => 'Reproduciendo',
    RemotePlayback.pausada => 'En pausa',
    RemotePlayback.detenido => 'Detenido',
  };

  /// What the UI should show the instant a button is tapped, before the PC
  /// confirms (see RemoteProvider.send). Guessing wrong is harmless — the
  /// confirming poll overwrites it a few hundred ms later — but guessing
  /// right is what makes the buttons feel connected instead of broken.
  RemoteState optimistic(RemoteCommand cmd, {int? index, bool? value}) =>
      switch (cmd) {
        RemoteCommand.playPause => copyWith(
          playback: isPlaying ? RemotePlayback.pausada : RemotePlayback.activa,
        ),
        RemoteCommand.stop => copyWith(
          playback: RemotePlayback.detenido,
          position: Duration.zero,
        ),
        RemoteCommand.repeat => copyWith(repeat: value ?? !repeat),
        RemoteCommand.playIndex => copyWith(
          playback: RemotePlayback.activa,
          index: index ?? this.index,
          position: Duration.zero,
        ),
        // prev/next change the song: which one is the desktop's business
        // (repeat mode, wrap-around), so only the position is safe to guess.
        RemoteCommand.next ||
        RemoteCommand.prev => copyWith(position: Duration.zero),
      };

  RemoteState copyWith({
    RemotePlayback? playback,
    int? index,
    String? artist,
    String? song,
    Duration? position,
    Duration? duration,
    bool? repeat,
    int? count,
    int? rev,
  }) => RemoteState(
    playback: playback ?? this.playback,
    index: index ?? this.index,
    artist: artist ?? this.artist,
    song: song ?? this.song,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    repeat: repeat ?? this.repeat,
    count: count ?? this.count,
    rev: rev ?? this.rev,
  );
}
