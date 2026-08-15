import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/remote_state.dart';

/// UDP port the desktop listens on for discovery probes — the same number as
/// the HTTP port, but UDP, so nothing collides.
const kDiscoveryPort = kDefaultRemotePort;

/// What the phone broadcasts. Short and versioned so a future protocol can
/// tell old probes apart.
const kDiscoveryProbe = 'PLAYIT?v$kRemoteProtocolVersion';

/// A desktop that answered a discovery probe.
///
/// Deliberately carries **no token**: discovery only answers "there is a
/// PlayIt here, at this address". Pairing still needs the QR or the typed
/// code, so a broadcast never leaks the credential to the whole network.
class DiscoveredDesktop {
  final String host;
  final int port;
  final String name;

  const DiscoveredDesktop({
    required this.host,
    required this.port,
    required this.name,
  });

  /// Parses one reply. Returns null for anything that isn't a PlayIt answer —
  /// a broadcast port hears all kinds of noise.
  static DiscoveredDesktop? tryParse(String raw, {String? senderHost}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw.trim());
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['v'] is int && (decoded['v'] as int) > kRemoteProtocolVersion) {
      return null;
    }

    final port = decoded['p'];
    if (port is! int || port < 1 || port > 65535) return null;

    // The address the datagram actually came from wins over the one the PC
    // reports: a multi-homed desktop can easily name an interface the phone
    // can't reach.
    final host = senderHost ?? (decoded['h'] is String ? decoded['h'] as String : '');
    if (host.isEmpty) return null;

    return DiscoveredDesktop(
      host: host,
      port: port,
      name: decoded['n'] is String ? decoded['n'] as String : host,
    );
  }

  /// Reuses an existing pairing's token at this (possibly new) address. This
  /// is what makes a DHCP lease change invisible: same code, new IP.
  PairingInfo pairingWith(PairingInfo saved) =>
      PairingInfo(host: host, port: port, token: saved.token, name: name);

  @override
  bool operator ==(Object other) =>
      other is DiscoveredDesktop && host == other.host && port == other.port;

  @override
  int get hashCode => Object.hash(host, port);
}

/// Broadcasts a probe on the local network and collects the PlayIt desktops
/// that answer within [timeout].
///
/// Chosen over mDNS on purpose: it needs no package on either side (Python's
/// stdlib socket answers it) and no extra Android permission — sending a
/// broadcast and receiving the unicast reply works under plain INTERNET,
/// while multicast would want a WifiManager.MulticastLock.
///
/// Never throws: a network that blocks broadcasts (many guest Wi-Fis do)
/// simply yields an empty list.
Future<List<DiscoveredDesktop>> discoverDesktops({
  Duration timeout = const Duration(seconds: 2),
  int port = kDiscoveryPort,
}) async {
  RawDatagramSocket? socket;
  final found = <DiscoveredDesktop>{};

  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;

    final completer = Completer<void>();
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket?.receive();
      if (datagram == null) return;
      final String text;
      try {
        text = utf8.decode(datagram.data);
      } on FormatException {
        return; // random binary noise on the port
      }
      final desktop = DiscoveredDesktop.tryParse(
        text,
        senderHost: datagram.address.address,
      );
      if (desktop != null) found.add(desktop);
    }, onError: (_) {});

    final probe = utf8.encode(kDiscoveryProbe);
    // Two probes: the first datagram is the one most likely to be dropped
    // while Wi-Fi wakes the radio up.
    for (var i = 0; i < 2; i++) {
      socket.send(probe, InternetAddress('255.255.255.255'), port);
      await Future.delayed(const Duration(milliseconds: 150));
    }

    Timer(timeout, () {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
    await subscription.cancel();
  } on SocketException {
    // No network, or the OS refused the broadcast: nothing found.
  } catch (_) {
    // Discovery is a convenience; it must never take down the caller.
  } finally {
    socket?.close();
  }

  final list = found.toList()..sort((a, b) => a.name.compareTo(b.name));
  return list;
}
