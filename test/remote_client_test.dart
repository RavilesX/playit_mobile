// End-to-end test of the remote-control transport against a stand-in for
// PlayIt Desktop: a real HttpServer on loopback speaking the protocol of
// PLAN_REMOTO.md §3. Covers what the pure-parser tests can't — headers, the
// encoded command body, status-code mapping, polling and `rev` refetching —
// without needing the PC.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playit_mobile/models/remote_state.dart';
import 'package:playit_mobile/providers/remote_provider.dart';
import 'package:playit_mobile/services/remote_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal stand-in for `remote_server.py`.
class FakeDesktop {
  late final HttpServer _server;

  String token = 'abcd1234';
  String name = 'PC-Prueba';
  int protocolVersion = kRemoteProtocolVersion;

  String playback = 'Activa';
  int index = 0;
  bool repeat = false;
  int rev = 1;
  List<Map<String, Object>> items = [
    {'i': 0, 'artist': 'Rush', 'song': 'YYZ', 'duration': '4:26'},
    {'i': 1, 'artist': 'Tool', 'song': 'Schism', 'duration': '6:47'},
  ];

  /// Commands received, in order, as the desktop would see them.
  final List<Map<String, dynamic>> commands = [];

  /// Cover bytes per playlist index. A missing entry answers 404, the way a
  /// song folder without cover.png does.
  Map<int, List<int>> covers = {
    0: [0x89, 0x50, 0x4E, 0x47, 1, 2, 3],
  };
  int coverRequests = 0;

  /// Token seen on the last request, to prove the header travels.
  String? lastToken;

  int stateRequests = 0;
  int playlistRequests = 0;

  /// When set, every request answers with this status instead of the real
  /// route — used to exercise the error mapping.
  int? forcedStatus;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_serve());
  }

  PairingInfo get pairing =>
      PairingInfo(host: '127.0.0.1', port: _server.port, token: token);

  int get port => _server.port;

  Future<void> stop() => _server.close(force: true);

  Map<String, Object> get _current =>
      index >= 0 && index < items.length ? items[index] : const {};

  Future<void> _serve() async {
    await for (final request in _server) {
      lastToken = request.headers.value('X-PlayIt-Token');
      final body = await utf8.decoder.bind(request).join();

      if (forcedStatus != null) {
        _send(request, forcedStatus!, {'error': 'forzado'});
        continue;
      }
      if (lastToken != token) {
        _send(request, 401, {'error': 'token invalido'});
        continue;
      }

      switch (request.uri.path) {
        case '/api/hello':
          _send(request, 200, {
            'v': protocolVersion,
            'name': name,
            'app': '1.2.8',
          });
        case '/api/state':
          stateRequests++;
          _send(request, 200, {
            'v': 1,
            'state': playback,
            'index': index,
            'artist': _current['artist'] ?? '',
            'song': _current['song'] ?? '',
            'position_ms': 1000,
            'duration_ms': 266000,
            'repeat': repeat,
            'count': items.length,
            'rev': rev,
          });
        case '/api/playlist':
          playlistRequests++;
          _send(request, 200, {'rev': rev, 'items': items});
        case '/api/cover':
          coverRequests++;
          final i = int.tryParse(request.uri.queryParameters['index'] ?? '');
          // El desktop distingue los dos casos: fuera de rango es un pedido
          // mal hecho (400); dentro de rango pero sin cover.png es normal
          // (404). Ver PLAN_REMOTO.md §5.7.
          if (i == null || i < 0 || i >= items.length) {
            _send(request, 400, {'error': 'indice fuera de rango'});
          } else if (covers[i] case final bytes?) {
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType('image', 'png')
              ..add(bytes);
            request.response.close();
          } else {
            _send(request, 404, {'error': 'sin caratula'});
          }
        case '/api/command':
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          commands.add(decoded);
          _apply(decoded);
          _send(request, 200, {'ok': true});
        default:
          _send(request, 404, {'error': 'no existe'});
      }
    }
  }

  /// Mimics the desktop actually obeying, so polling sees real changes.
  void _apply(Map<String, dynamic> cmd) {
    switch (cmd['cmd']) {
      case 'play_pause':
        playback = playback == 'Activa' ? 'Pausada' : 'Activa';
      case 'stop':
        playback = 'Detenido';
      case 'next':
        index = (index + 1) % items.length;
        playback = 'Activa';
      case 'prev':
        index = (index - 1 + items.length) % items.length;
        playback = 'Activa';
      case 'repeat':
        repeat = cmd['value'] == true;
      case 'play_index':
        index = cmd['index'] as int;
        playback = 'Activa';
    }
  }

  void _send(HttpRequest request, int status, Map<String, Object> payload) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(payload));
    request.response.close();
  }
}

void main() {
  // Needed for SharedPreferences' mock channel — but the test binding also
  // installs HttpOverrides that answer every request with 400 without
  // touching the network. Clearing it gives RemoteClient a real socket to
  // the fake desktop, which is the whole point of this suite.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late FakeDesktop desktop;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    desktop = FakeDesktop();
    await desktop.start();
  });

  tearDown(() => desktop.stop());

  group('RemoteClient', () {
    test('hello valida el emparejamiento y devuelve el nombre de la PC', () async {
      final client = RemoteClient(desktop.pairing);
      addTearDown(client.dispose);

      expect(await client.hello(), 'PC-Prueba');
      expect(desktop.lastToken, desktop.token);
    });

    test('un desktop con protocolo más nuevo se reporta como incompatible',
        () async {
      desktop.protocolVersion = kRemoteProtocolVersion + 1;
      final client = RemoteClient(desktop.pairing);
      addTearDown(client.dispose);

      expect(
        client.hello(),
        throwsA(
          isA<RemoteException>().having(
            (e) => e.kind,
            'kind',
            RemoteErrorKind.versionIncompatible,
          ),
        ),
      );
    });

    test('state y playlist se mapean a los modelos', () async {
      final client = RemoteClient(desktop.pairing);
      addTearDown(client.dispose);

      final state = await client.state();
      expect(state.playback, RemotePlayback.activa);
      expect(state.displayName, 'Rush - YYZ');
      expect(state.count, 2);

      final playlist = await client.playlist();
      expect(playlist.rev, 1);
      expect(playlist.items[1].song, 'Schism');
    });

    test('send codifica el comando y su argumento', () async {
      final client = RemoteClient(desktop.pairing);
      addTearDown(client.dispose);

      await client.send(RemoteCommand.playIndex, index: 1);
      await client.send(RemoteCommand.repeat, value: true);
      await client.send(RemoteCommand.stop);

      expect(desktop.commands, [
        {'cmd': 'play_index', 'index': 1},
        {'cmd': 'repeat', 'value': true},
        {'cmd': 'stop'},
      ]);
    });

    test('cover devuelve los bytes tal cual', () async {
      final client = RemoteClient(desktop.pairing);
      addTearDown(client.dispose);

      expect(await client.cover(0), [0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    });

    test('una canción sin carátula da null, no un error', () async {
      final client = RemoteClient(desktop.pairing);
      addTearDown(client.dispose);

      expect(await client.cover(1), isNull);
    });

    test('un índice fuera de rango es un error, no "sin carátula"', () async {
      final client = RemoteClient(desktop.pairing);
      addTearDown(client.dispose);

      await expectLater(
        client.cover(99),
        throwsA(
          isA<RemoteException>()
              .having((e) => e.kind, 'kind', RemoteErrorKind.respuestaInvalida)
              .having((e) => e.message, 'message', 'indice fuera de rango'),
        ),
      );
    });

    test('un 401 en la carátula sí es un error', () async {
      final client = RemoteClient(
        PairingInfo(host: '127.0.0.1', port: desktop.port, token: 'malo'),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.cover(0),
        throwsA(
          isA<RemoteException>()
              .having((e) => e.kind, 'kind', RemoteErrorKind.noAutorizado),
        ),
      );
    });

    test('token equivocado da noAutorizado con mensaje accionable', () async {
      final client = RemoteClient(
        PairingInfo(host: '127.0.0.1', port: desktop.port, token: 'malo'),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.state(),
        throwsA(
          isA<RemoteException>()
              .having((e) => e.kind, 'kind', RemoteErrorKind.noAutorizado)
              .having((e) => e.message, 'message', contains('emparejar')),
        ),
      );
    });

    test('403 y 409 se traducen a sus casos propios', () async {
      final client = RemoteClient(desktop.pairing);
      addTearDown(client.dispose);

      desktop.forcedStatus = 403;
      await expectLater(
        client.state(),
        throwsA(
          isA<RemoteException>()
              .having((e) => e.kind, 'kind', RemoteErrorKind.rechazado),
        ),
      );

      desktop.forcedStatus = 409;
      await expectLater(
        client.send(RemoteCommand.next),
        throwsA(
          isA<RemoteException>()
              .having((e) => e.kind, 'kind', RemoteErrorKind.imposible),
        ),
      );
    });

    test('un 500 conserva el detalle que mandó la PC', () async {
      desktop.forcedStatus = 500;
      final client = RemoteClient(desktop.pairing);
      addTearDown(client.dispose);

      await expectLater(
        client.state(),
        throwsA(
          isA<RemoteException>()
              .having((e) => e.kind, 'kind', RemoteErrorKind.respuestaInvalida)
              .having((e) => e.message, 'message', 'forzado'),
        ),
      );
    });

    test('sin nadie escuchando el puerto: noResponde', () async {
      final port = desktop.port;
      await desktop.stop();

      final client = RemoteClient(
        PairingInfo(host: '127.0.0.1', port: port, token: 'x'),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.state(),
        throwsA(
          isA<RemoteException>()
              .having((e) => e.kind, 'kind', RemoteErrorKind.noResponde)
              .having((e) => e.message, 'message', contains('Wi-Fi')),
        ),
      );
    });
  });

  group('RemoteProvider', () {
    test('connect baja lista y estado, y guarda el emparejamiento', () async {
      final provider = RemoteProvider();
      addTearDown(provider.dispose);

      expect(await provider.connect(desktop.pairing), isTrue);
      expect(provider.isConnected, isTrue);
      expect(provider.desktopName, 'PC-Prueba');
      expect(provider.playlist.items, hasLength(2));
      expect(provider.state.song, 'YYZ');

      final saved = await RemoteProvider.savedPairing();
      expect(saved!.token, desktop.token);
      expect(saved.port, desktop.port);
      expect(saved.name, 'PC-Prueba');
    });

    test('connect fallido deja el error a la vista y no conecta', () async {
      final provider = RemoteProvider();
      addTearDown(provider.dispose);

      final ok = await provider.connect(
        PairingInfo(host: '127.0.0.1', port: desktop.port, token: 'malo'),
      );
      expect(ok, isFalse);
      expect(provider.connection, RemoteConnection.error);
      expect(provider.errorMessage, contains('emparejar'));
    });

    test('un comando llega a la PC y el estado real lo confirma', () async {
      final provider = RemoteProvider();
      addTearDown(provider.dispose);
      await provider.connect(desktop.pairing);

      await provider.playIndex(1);

      expect(desktop.commands.single, {'cmd': 'play_index', 'index': 1});
      expect(provider.state.index, 1);
      expect(provider.state.song, 'Schism');
    });

    test('si el comando falla, se deshace el update optimista', () async {
      final provider = RemoteProvider();
      addTearDown(provider.dispose);
      await provider.connect(desktop.pairing);
      expect(provider.state.isPlaying, isTrue);

      desktop.forcedStatus = 500;
      await provider.stop();

      // La PC nunca lo ejecutó: la UI no puede quedar diciendo "Detenido".
      expect(provider.state.isPlaying, isTrue);
      expect(provider.errorMessage, isNotEmpty);
      expect(provider.isConnected, isTrue);
    });

    test('el sondeo ve los cambios hechos en la PC', () async {
      final provider = RemoteProvider();
      addTearDown(provider.dispose);
      await provider.connect(desktop.pairing);

      desktop.playback = 'Pausada';
      desktop.index = 1;
      await Future.delayed(RemoteProvider.pollInterval * 1.5);

      expect(provider.state.playback, RemotePlayback.pausada);
      expect(provider.state.index, 1);
    });

    test('un cambio de rev vuelve a bajar la playlist', () async {
      final provider = RemoteProvider();
      addTearDown(provider.dispose);
      await provider.connect(desktop.pairing);
      final downloads = desktop.playlistRequests;

      // La PC carga otra carpeta: nueva lista, nueva revisión.
      desktop.items = [
        {'i': 0, 'artist': 'Slayer', 'song': 'Raining Blood', 'duration': '4:16'},
      ];
      desktop.index = 0;
      desktop.rev = 2;
      await Future.delayed(RemoteProvider.pollInterval * 1.5);

      expect(desktop.playlistRequests, greaterThan(downloads));
      expect(provider.playlist.rev, 2);
      expect(provider.playlist.items.single.song, 'Raining Blood');
    });

    test('sin cambio de rev la playlist no se vuelve a pedir', () async {
      final provider = RemoteProvider();
      addTearDown(provider.dispose);
      await provider.connect(desktop.pairing);
      final downloads = desktop.playlistRequests;

      await Future.delayed(RemoteProvider.pollInterval * 2);

      expect(desktop.stateRequests, greaterThan(1));
      expect(desktop.playlistRequests, downloads);
    });

    test('un 401 durante el sondeo corta la sesión enseguida', () async {
      final provider = RemoteProvider();
      addTearDown(provider.dispose);
      await provider.connect(desktop.pairing);

      // La PC generó un código nuevo: el nuestro ya no sirve.
      desktop.token = 'otro';
      await Future.delayed(RemoteProvider.pollInterval * 1.5);

      expect(provider.connection, RemoteConnection.error);
      expect(provider.errorMessage, contains('emparejar'));
    });

    test('un fallo aislado no tira la sesión', () async {
      final provider = RemoteProvider();
      addTearDown(provider.dispose);
      await provider.connect(desktop.pairing);

      desktop.forcedStatus = 500;
      await Future.delayed(RemoteProvider.pollInterval * 1.5);
      expect(provider.isConnected, isTrue, reason: 'un poll fallido tolerado');

      desktop.forcedStatus = null;
      await Future.delayed(RemoteProvider.pollInterval * 1.5);
      expect(provider.isConnected, isTrue);
    });

    test('fallos consecutivos sí la cortan', () async {
      final provider = RemoteProvider();
      addTearDown(provider.dispose);
      await provider.connect(desktop.pairing);

      desktop.forcedStatus = 500;
      await Future.delayed(
        RemoteProvider.pollInterval * (RemoteProvider.maxPollFailures + 1),
      );

      expect(provider.connection, RemoteConnection.error);
    });

    test('pausePolling frena las peticiones (app en segundo plano)', () async {
      final provider = RemoteProvider();
      addTearDown(provider.dispose);
      await provider.connect(desktop.pairing);

      provider.pausePolling();
      await Future.delayed(RemoteProvider.pollInterval);
      final frozen = desktop.stateRequests;
      await Future.delayed(RemoteProvider.pollInterval * 2);
      expect(desktop.stateRequests, frozen);

      provider.resumePolling();
      await Future.delayed(RemoteProvider.pollInterval);
      expect(desktop.stateRequests, greaterThan(frozen));
    });

    test('la carátula de la canción actual se baja al conectar', () async {
      final provider = RemoteProvider();
      addTearDown(provider.dispose);
      await provider.connect(desktop.pairing);
      await Future.delayed(const Duration(milliseconds: 200));

      expect(provider.coverBytes, isNotNull);
    });

    test('cambiar de canción baja la carátula nueva, una sola vez', () async {
      final provider = RemoteProvider();
      addTearDown(provider.dispose);
      await provider.connect(desktop.pairing);
      await Future.delayed(const Duration(milliseconds: 200));
      final downloads = desktop.coverRequests;

      // La pista 1 no tiene carátula: el hueco se muestra, no un error.
      await provider.playIndex(1);
      await Future.delayed(const Duration(milliseconds: 200));
      expect(provider.coverBytes, isNull);
      expect(provider.isConnected, isTrue);

      final afterChange = desktop.coverRequests;
      expect(afterChange, greaterThan(downloads));

      // Los sondeos siguientes, con la misma canción, no la vuelven a pedir.
      await Future.delayed(RemoteProvider.pollInterval * 2);
      expect(desktop.coverRequests, afterChange);
    });

    test('un 400 de carátula no tira la sesión', () async {
      final provider = RemoteProvider();
      addTearDown(provider.dispose);
      await provider.connect(desktop.pairing);
      await Future.delayed(const Duration(milliseconds: 200));

      // La PC vacía la playlist entre dos sondeos: el índice que el móvil
      // acaba de leer ya no existe y /api/cover responde 400. Es una carrera
      // normal, no una desconexión.
      desktop.index = 99;
      await Future.delayed(RemoteProvider.pollInterval * 1.5);

      expect(provider.isConnected, isTrue);
      expect(provider.coverBytes, isNull);
    });

    test('forget borra el token guardado', () async {
      final provider = RemoteProvider();
      addTearDown(provider.dispose);
      await provider.connect(desktop.pairing);

      await provider.forget();

      expect(provider.connection, RemoteConnection.desconectado);
      expect(await RemoteProvider.savedPairing(), isNull);
    });

    test('connectToSaved reconecta sin volver a emparejar', () async {
      final first = RemoteProvider();
      await first.connect(desktop.pairing);
      first.dispose();

      final second = RemoteProvider();
      addTearDown(second.dispose);
      expect(await second.connectToSaved(), isTrue);
      expect(second.state.song, 'YYZ');
    });
  });
}
