import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/remote_state.dart';

/// Why a request to the desktop failed. Each case maps to one Spanish
/// sentence in [RemoteException.message] — the user is standing behind a drum
/// kit, not reading stack traces.
enum RemoteErrorKind {
  /// The phone is not on the network, or the PC is off / on another subnet.
  noResponde,

  /// The token was rejected: the desktop generated a new code, or remote mode
  /// was turned off and on again.
  noAutorizado,

  /// The desktop refused the request (403): we are not seen as a LAN client.
  rechazado,

  /// Reached the PC but the answer wasn't the protocol we expect.
  respuestaInvalida,

  /// Desktop speaks a newer protocol version.
  versionIncompatible,

  /// Command was well-formed but impossible right now (empty playlist).
  imposible,
}

class RemoteException implements Exception {
  final RemoteErrorKind kind;
  final String message;
  const RemoteException(this.kind, this.message);

  @override
  String toString() => 'RemoteException(${kind.name}): $message';
}

/// HTTP transport to one paired desktop. Knows nothing about UI or state —
/// it turns endpoints into models and failures into [RemoteException].
///
/// Uses `dart:io`'s [HttpClient] rather than `package:http` for the same
/// reason [UpdateChecker] does: one less dependency for four endpoints. One
/// client instance is kept alive so the 1 Hz polling reuses the keep-alive
/// connection instead of opening a socket per second.
class RemoteClient {
  final PairingInfo pairing;

  /// On a LAN, 3 s without an answer already means "the PC is gone".
  static const timeout = Duration(seconds: 3);

  final HttpClient _client;

  RemoteClient(this.pairing)
    : _client = HttpClient()..connectionTimeout = timeout;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.http(pairing.address, path, query);

  /// Validates the pairing and returns the desktop's display name.
  Future<String> hello() async {
    final json = await _get('/api/hello');
    final version = json['v'];
    if (version is int && version > kRemoteProtocolVersion) {
      throw const RemoteException(
        RemoteErrorKind.versionIncompatible,
        'La PC usa una versión más nueva de PlayIt. Actualizá PlayIt Mobile.',
      );
    }
    final name = json['name'];
    return name is String && name.isNotEmpty ? name : pairing.host;
  }

  Future<RemoteState> state() async =>
      RemoteState.fromJson(await _get('/api/state'));

  Future<RemotePlaylist> playlist() async =>
      RemotePlaylist.fromJson(await _get('/api/playlist'));

  Future<void> send(RemoteCommand cmd, {int? index, bool? value}) async {
    await _post('/api/command', {
      'cmd': cmd.wire,
      'index': ?index,
      'value': ?value,
    });
  }

  /// Cover art of one playlist entry, already downscaled by the desktop.
  ///
  /// Null when that song simply has no `cover.png` (the desktop answers 404),
  /// which is a normal case and not an error worth showing.
  Future<Uint8List?> cover(int index) async {
    try {
      final request = await _client
          .getUrl(_uri('/api/cover', {'index': '$index'}))
          .timeout(timeout);
      request.headers.set('X-PlayIt-Token', pairing.token);
      final response = await request.close().timeout(timeout);

      if (response.statusCode == 404) {
        await response.drain<void>();
        return null;
      }
      if (response.statusCode != 200) {
        // Read the body so the keep-alive connection stays usable, then let
        // the JSON path produce the right message for 401/403/etc.
        final text = await response.transform(utf8.decoder).join();
        _decode(response.statusCode, text);
      }

      final chunks = await response.toList().timeout(timeout);
      return Uint8List.fromList([for (final c in chunks) ...c]);
    } on RemoteException {
      rethrow;
    } catch (e) {
      _throwTransportFailure(e);
    }
  }

  void dispose() => _client.close(force: true);

  // ──────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _get(String path) =>
      _send(() => _client.getUrl(_uri(path)));

  Future<Map<String, dynamic>> _post(String path, Map<String, Object> body) =>
      _send(() => _client.postUrl(_uri(path)), body: body);

  Future<Map<String, dynamic>> _send(
    Future<HttpClientRequest> Function() open, {
    Map<String, Object>? body,
  }) async {
    try {
      final request = await open().timeout(timeout);
      request.headers.set('X-PlayIt-Token', pairing.token);
      if (body != null) {
        final encoded = utf8.encode(jsonEncode(body));
        request.headers.contentType = ContentType.json;
        request.headers.contentLength = encoded.length;
        request.add(encoded);
      }
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return _decode(response.statusCode, text);
    } on RemoteException {
      rethrow; // _decode ya tradujo el código de estado.
    } catch (e) {
      _throwTransportFailure(e);
    }
  }

  /// Turns any transport-level failure into a [RemoteException].
  ///
  /// `dart:io` surfaces plenty of failures that are neither [SocketException]
  /// nor [HttpException] — a keep-alive socket reset by the PC is one of them.
  /// They all mean the same thing to the user, and none may escape: an
  /// unhandled error here would take down the poll timer's zone instead of
  /// showing "no responde".
  Never _throwTransportFailure(Object error) {
    throw switch (error) {
      SocketException() => const RemoteException(
        RemoteErrorKind.noResponde,
        'No se encontró la PC. Verificá que ambos estén en la misma red Wi-Fi.',
      ),
      TimeoutException() => const RemoteException(
        RemoteErrorKind.noResponde,
        'La PC no respondió. ¿Sigue encendida y con PlayIt abierto?',
      ),
      _ => const RemoteException(
        RemoteErrorKind.noResponde,
        'Se cortó la conexión con la PC.',
      ),
    };
  }

  Map<String, dynamic> _decode(int status, String text) {
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(text.isEmpty ? '{}' : text);
      if (decoded is Map<String, dynamic>) json = decoded;
    } on FormatException {
      json = null;
    }

    if (status == 200) {
      if (json == null) {
        throw const RemoteException(
          RemoteErrorKind.respuestaInvalida,
          'La PC respondió algo inesperado. ¿Es PlayIt Desktop?',
        );
      }
      return json;
    }

    // The desktop sends {"error": "..."} on every non-200; fall back to the
    // status code when something else answered on that port.
    final detail = json?['error'] is String ? json!['error'] as String : '';
    throw switch (status) {
      401 => const RemoteException(
        RemoteErrorKind.noAutorizado,
        'El código ya no es válido. Volvé a emparejar desde la PC.',
      ),
      403 => const RemoteException(
        RemoteErrorKind.rechazado,
        'La PC rechazó la conexión: sólo acepta equipos de la red local.',
      ),
      409 => const RemoteException(
        RemoteErrorKind.imposible,
        'La PC no puede hacer eso ahora. ¿La playlist está vacía?',
      ),
      _ => RemoteException(
        RemoteErrorKind.respuestaInvalida,
        detail.isEmpty ? 'La PC respondió $status.' : detail,
      ),
    };
  }
}
