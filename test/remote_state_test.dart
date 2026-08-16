import 'package:flutter_test/flutter_test.dart';
import 'package:playit_mobile/models/remote_state.dart';

void main() {
  group('PairingInfo.parse (carga del QR)', () {
    test('lee el payload que genera el desktop', () {
      final info = PairingInfo.parse(
        '{"v":1,"h":"192.168.1.42","p":8770,"t":"9f2c4d1a","n":"PC-Ricardo"}',
      );
      expect(info.host, '192.168.1.42');
      expect(info.port, 8770);
      expect(info.token, '9f2c4d1a');
      expect(info.name, 'PC-Ricardo');
      expect(info.address, '192.168.1.42:8770');
    });

    test('tolera espacios alrededor', () {
      final info = PairingInfo.parse(
        '  {"v":1,"h":"10.0.0.5","p":8771,"t":"abcd"}  ',
      );
      expect(info.port, 8771);
      expect(info.name, '');
    });

    test('rechaza texto que no es JSON', () {
      expect(
        () => PairingInfo.parse('https://ejemplo.com'),
        throwsA(isA<RemotePairingException>()),
      );
    });

    test('rechaza un protocolo más nuevo con un mensaje accionable', () {
      expect(
        () => PairingInfo.parse('{"v":99,"h":"1.2.3.4","p":8770,"t":"ab"}'),
        throwsA(
          isA<RemotePairingException>().having(
            (e) => e.message,
            'message',
            contains('Actualiza'),
          ),
        ),
      );
    });

    test('rechaza payloads incompletos', () {
      for (final raw in [
        '{"v":1,"p":8770,"t":"ab"}', // sin host
        '{"v":1,"h":"1.2.3.4","t":"ab"}', // sin puerto
        '{"v":1,"h":"1.2.3.4","p":8770}', // sin token
        '{"v":1,"h":"1.2.3.4","p":"8770","t":"ab"}', // puerto como texto
        '[1,2,3]',
      ]) {
        expect(
          () => PairingInfo.parse(raw),
          throwsA(isA<RemotePairingException>()),
          reason: raw,
        );
      }
    });
  });

  group('PairingInfo.fromManual (tecleado a mano)', () {
    test('acepta host:puerto', () {
      final info = PairingInfo.fromManual('192.168.1.42:8771', 'abcd');
      expect(info.host, '192.168.1.42');
      expect(info.port, 8771);
    });

    test('usa el puerto por defecto cuando no se escribe', () {
      expect(PairingInfo.fromManual('192.168.1.42', 'abcd').port,
          kDefaultRemotePort);
    });

    test('limpia los espacios del código en grupos de cuatro', () {
      expect(
        PairingInfo.fromManual('192.168.1.42', ' 9f2c 4d1a ').token,
        '9f2c4d1a',
      );
    });

    test('rechaza campos vacíos y puertos inválidos', () {
      expect(() => PairingInfo.fromManual('', 'ab'),
          throwsA(isA<RemotePairingException>()));
      expect(() => PairingInfo.fromManual('1.2.3.4', '   '),
          throwsA(isA<RemotePairingException>()));
      expect(() => PairingInfo.fromManual('1.2.3.4:0', 'ab'),
          throwsA(isA<RemotePairingException>()));
      expect(() => PairingInfo.fromManual('1.2.3.4:puerto', 'ab'),
          throwsA(isA<RemotePairingException>()));
    });

    test('prettyToken agrupa de a cuatro', () {
      expect(
        const PairingInfo(host: 'h', port: 1, token: '9f2c4d1ab').prettyToken,
        '9f2c 4d1a b',
      );
    });
  });

  group('RemoteState.fromJson', () {
    test('mapea el estado que publica el desktop', () {
      final state = RemoteState.fromJson({
        'v': 1,
        'state': 'Activa',
        'index': 3,
        'artist': 'Rush',
        'song': 'YYZ',
        'position_ms': 84000,
        'duration_ms': 265000,
        'repeat': true,
        'count': 42,
        'rev': 7,
      });
      expect(state.playback, RemotePlayback.activa);
      expect(state.isPlaying, isTrue);
      expect(state.index, 3);
      expect(state.displayName, 'Rush - YYZ');
      expect(state.position, const Duration(seconds: 84));
      expect(state.duration, const Duration(milliseconds: 265000));
      expect(state.repeat, isTrue);
      expect(state.rev, 7);
    });

    test('un estado desconocido cae en Detenido', () {
      expect(
        RemoteState.fromJson({'state': 'Vaya'}).playback,
        RemotePlayback.detenido,
      );
      expect(RemoteState.fromJson({}).playback, RemotePlayback.detenido);
    });

    test('no lanza con campos faltantes o de otro tipo', () {
      final state = RemoteState.fromJson({
        'state': 'Pausada',
        'index': null,
        'artist': 42,
        'position_ms': 1500.9,
        'repeat': 'sí',
      });
      expect(state.playback, RemotePlayback.pausada);
      expect(state.index, -1);
      expect(state.artist, '');
      expect(state.position, const Duration(milliseconds: 1500));
      // Sólo el booleano true cuenta: un "sí" no enciende la repetición.
      expect(state.repeat, isFalse);
      expect(state.hasSong, isFalse);
    });
  });

  group('RemoteState.optimistic', () {
    const playing = RemoteState(
      playback: RemotePlayback.activa,
      index: 2,
      artist: 'Rush',
      song: 'YYZ',
      position: Duration(seconds: 30),
      duration: Duration(seconds: 200),
      repeat: false,
      count: 5,
      rev: 1,
    );

    test('play/pausa alterna', () {
      final paused = playing.optimistic(RemoteCommand.playPause);
      expect(paused.playback, RemotePlayback.pausada);
      expect(
        paused.optimistic(RemoteCommand.playPause).playback,
        RemotePlayback.activa,
      );
    });

    test('detenido vuelve a arrancar', () {
      final stopped = playing.optimistic(RemoteCommand.stop);
      expect(stopped.isStopped, isTrue);
      expect(stopped.position, Duration.zero);
      expect(
        stopped.optimistic(RemoteCommand.playPause).playback,
        RemotePlayback.activa,
      );
    });

    test('play_index mueve el índice y arranca', () {
      final jumped = playing.optimistic(RemoteCommand.playIndex, index: 9);
      expect(jumped.index, 9);
      expect(jumped.isPlaying, isTrue);
      expect(jumped.position, Duration.zero);
    });

    test('repeat usa el valor mandado', () {
      expect(playing.optimistic(RemoteCommand.repeat, value: true).repeat,
          isTrue);
      expect(playing.optimistic(RemoteCommand.repeat).repeat, isTrue);
    });

    test('prev/next no adivinan la canción, sólo la posición', () {
      final next = playing.optimistic(RemoteCommand.next);
      expect(next.position, Duration.zero);
      // Cuál sigue depende del modo repetir del desktop: no se inventa.
      expect(next.index, playing.index);
      expect(next.song, playing.song);
    });
  });

  group('RemotePlaylist.fromJson', () {
    test('lee la lista con su revisión', () {
      final playlist = RemotePlaylist.fromJson({
        'rev': 4,
        'items': [
          {'i': 0, 'artist': 'Rush', 'song': 'YYZ', 'duration': '4:26'},
          {'i': 1, 'artist': 'Tool', 'song': 'Schism', 'duration': '6:47'},
        ],
      });
      expect(playlist.rev, 4);
      expect(playlist.items, hasLength(2));
      expect(playlist.items[1].displayName, 'Tool - Schism');
      expect(playlist.items[0].duration, '4:26');
    });

    test('descarta renglones que no son objetos y rellena los incompletos', () {
      final playlist = RemotePlaylist.fromJson({
        'rev': 1,
        'items': [
          'basura',
          {'artist': 'Rush'},
        ],
      });
      expect(playlist.items, hasLength(1));
      // Sin "i" cae al índice de posición: el tap sigue apuntando bien.
      expect(playlist.items.single.index, 1);
      expect(playlist.items.single.song, '');
      expect(playlist.items.single.duration, '');
    });

    test('items ausente o de otro tipo da una lista vacía', () {
      expect(RemotePlaylist.fromJson({'rev': 2}).items, isEmpty);
      expect(RemotePlaylist.fromJson({'items': 5}).items, isEmpty);
    });

    test('la lista vacía por defecto nunca coincide con una revisión real', () {
      // rev -1 fuerza la primera descarga: el desktop arranca en 0.
      expect(RemotePlaylist.empty.rev, -1);
      expect(RemoteState.unknown.rev, -1);
    });
  });

  group('pairingFromBarcodes (lo que devuelve la cámara)', () {
    const valid = '{"v":1,"h":"192.168.1.42","p":8770,"t":"9f2c","n":"PC"}';

    test('toma el emparejamiento aunque venga junto a otros códigos', () {
      final info = pairingFromBarcodes([
        'https://otracosa.com',
        null,
        valid,
      ]);
      expect(info.host, '192.168.1.42');
      expect(info.name, 'PC');
    });

    test('ignora valores nulos y vacíos', () {
      expect(pairingFromBarcodes([null, '', '   ', valid]).port, 8770);
    });

    test('un frame sin códigos legibles avisa que no leyó nada', () {
      expect(
        () => pairingFromBarcodes([null, '  ']),
        throwsA(
          isA<RemotePairingException>().having(
            (e) => e.message,
            'message',
            contains('No se leyó'),
          ),
        ),
      );
    });

    test('con un QR ajeno explica qué pasa, no un error genérico', () {
      expect(
        () => pairingFromBarcodes(['https://ejemplo.com']),
        throwsA(
          isA<RemotePairingException>().having(
            (e) => e.message,
            'message',
            contains('no es de PlayIt Desktop'),
          ),
        ),
      );
    });

    test('un QR de PlayIt inservible le gana al mensaje del QR ajeno', () {
      // Apuntando a la pantalla de la PC entra basura de alrededor en el
      // mismo frame: el mensaje útil es el del código de PlayIt.
      expect(
        () => pairingFromBarcodes([
          'basura',
          '{"v":99,"h":"1.2.3.4","p":8770,"t":"ab"}',
        ]),
        throwsA(
          isA<RemotePairingException>()
              .having((e) => e.message, 'message', contains('Actualiza'))
              .having((e) => e.recognized, 'recognized', isTrue),
        ),
      );
    });

    test('un código de PlayIt incompleto también gana', () {
      expect(
        () => pairingFromBarcodes([
          'https://ejemplo.com',
          '{"v":1,"h":"1.2.3.4"}',
        ]),
        throwsA(
          isA<RemotePairingException>().having(
            (e) => e.message,
            'message',
            contains('incompleto'),
          ),
        ),
      );
    });
  });

  test('los comandos usan los nombres del protocolo', () {
    expect(RemoteCommand.playPause.wire, 'play_pause');
    expect(RemoteCommand.playIndex.wire, 'play_index');
    expect(RemoteCommand.prev.wire, 'prev');
  });
}
