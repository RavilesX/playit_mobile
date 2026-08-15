// Discovery over UDP, tested against a real socket that answers probes the
// way `remote_server.py` will (PLAN_REMOTO.md §5.8).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playit_mobile/models/remote_state.dart';
import 'package:playit_mobile/services/remote_discovery.dart';

/// Answers discovery probes on a loopback port, like the desktop's UDP
/// listener. Bound to 127.0.0.1 rather than a broadcast address so the test
/// never depends on the machine's real network.
class FakeResponder {
  late final RawDatagramSocket _socket;

  /// What to answer with; null means "stay silent" (a PC that isn't in
  /// remote mode).
  String? reply;

  int probesSeen = 0;
  String? lastProbe;

  int get port => _socket.port;

  Future<void> start({required String? reply, int tcpPort = 8770}) async {
    this.reply =
        reply ??
        jsonEncode({'v': 1, 'h': '127.0.0.1', 'p': tcpPort, 'n': 'PC-Prueba'});
    _socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket.receive();
      if (datagram == null) return;
      probesSeen++;
      lastProbe = utf8.decode(datagram.data);
      final answer = this.reply;
      if (answer == null) return;
      _socket.send(utf8.encode(answer), datagram.address, datagram.port);
    });
  }

  void close() => _socket.close();
}

/// Sends probes straight at [target] instead of the broadcast address, so the
/// test exercises the real parsing and collection path without needing a LAN.
Future<List<DiscoveredDesktop>> probeLoopback(
  int target, {
  Duration timeout = const Duration(milliseconds: 600),
}) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final found = <DiscoveredDesktop>{};

  socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final datagram = socket.receive();
    if (datagram == null) return;
    final desktop = DiscoveredDesktop.tryParse(
      utf8.decode(datagram.data),
      senderHost: datagram.address.address,
    );
    if (desktop != null) found.add(desktop);
  });

  socket.send(
    utf8.encode(kDiscoveryProbe),
    InternetAddress.loopbackIPv4,
    target,
  );
  await Future.delayed(timeout);
  socket.close();
  return found.toList();
}

void main() {
  group('DiscoveredDesktop.tryParse', () {
    test('lee la respuesta del desktop', () {
      final desktop = DiscoveredDesktop.tryParse(
        '{"v":1,"h":"192.168.1.42","p":8770,"n":"PC-Ricardo"}',
      );
      expect(desktop!.host, '192.168.1.42');
      expect(desktop.port, 8770);
      expect(desktop.name, 'PC-Ricardo');
    });

    test('la dirección real del datagrama le gana a la que dice la PC', () {
      // Una PC con varias interfaces puede anunciar una que el teléfono no
      // alcanza; la que contestó sí alcanza por definición.
      final desktop = DiscoveredDesktop.tryParse(
        '{"v":1,"h":"10.8.0.1","p":8770,"n":"PC"}',
        senderHost: '192.168.1.42',
      );
      expect(desktop!.host, '192.168.1.42');
    });

    test('descarta ruido, versiones nuevas y puertos inválidos', () {
      expect(DiscoveredDesktop.tryParse('hola'), isNull);
      expect(DiscoveredDesktop.tryParse('[1,2]'), isNull);
      expect(
        DiscoveredDesktop.tryParse('{"v":99,"h":"1.2.3.4","p":8770}'),
        isNull,
      );
      expect(DiscoveredDesktop.tryParse('{"v":1,"h":"1.2.3.4"}'), isNull);
      expect(
        DiscoveredDesktop.tryParse('{"v":1,"h":"1.2.3.4","p":0}'),
        isNull,
      );
      expect(DiscoveredDesktop.tryParse('{"v":1,"p":8770}'), isNull);
    });

    test('sin nombre usa la dirección', () {
      final desktop = DiscoveredDesktop.tryParse('{"v":1,"h":"1.2.3.4","p":1}');
      expect(desktop!.name, '1.2.3.4');
    });

    test('pairingWith conserva el código y cambia la dirección', () {
      const saved = PairingInfo(
        host: '192.168.1.42',
        port: 8770,
        token: '9f2c',
        name: 'viejo',
      );
      const desktop = DiscoveredDesktop(
        host: '192.168.1.77',
        port: 8771,
        name: 'PC-Ricardo',
      );

      final moved = desktop.pairingWith(saved);
      expect(moved.token, '9f2c', reason: 'el código no cambia con la IP');
      expect(moved.address, '192.168.1.77:8771');
      expect(moved.name, 'PC-Ricardo');
    });

    test('dos respuestas del mismo equipo cuentan como una', () {
      const a = DiscoveredDesktop(host: '1.2.3.4', port: 8770, name: 'A');
      const b = DiscoveredDesktop(host: '1.2.3.4', port: 8770, name: 'B');
      expect({a, b}, hasLength(1));
    });
  });

  group('sonda UDP contra un respondedor real', () {
    late FakeResponder responder;

    setUp(() async {
      responder = FakeResponder();
    });

    tearDown(() => responder.close());

    test('la PC recibe la sonda y su respuesta se convierte en un equipo',
        () async {
      await responder.start(reply: null);

      final found = await probeLoopback(responder.port);

      expect(responder.probesSeen, greaterThan(0));
      expect(responder.lastProbe, kDiscoveryProbe);
      expect(found, hasLength(1));
      expect(found.single.host, '127.0.0.1');
      expect(found.single.name, 'PC-Prueba');
    });

    test('una PC callada no aparece', () async {
      await responder.start(reply: null);
      responder.reply = null;

      expect(await probeLoopback(responder.port), isEmpty);
    });

    test('una respuesta que no es de PlayIt se ignora', () async {
      await responder.start(reply: 'soy otro servicio');

      expect(await probeLoopback(responder.port), isEmpty);
    });
  });

  test('discoverDesktops sin nadie en la red devuelve vacío, no lanza',
      () async {
    // Puerto de descubrimiento improbable: nada debería contestar. Lo que se
    // prueba es que un barrido sin resultados es un caso normal.
    final found = await discoverDesktops(
      timeout: const Duration(milliseconds: 400),
      port: 59321,
    );
    expect(found, isEmpty);
  });
}
