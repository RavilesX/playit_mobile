import 'package:flutter/services.dart';

/// A file inside a SAF tree: its content:// URI and path relative to the tree.
class SafFile {
  final String uri;
  final String relPath;
  const SafFile(this.uri, this.relPath);
}

/// Thin wrapper over the native Storage Access Framework channel
/// (see android MainActivity). No storage permissions involved.
class SafStorage {
  static const MethodChannel _channel = MethodChannel('playit/saf');

  /// Opens the system folder picker. Returns the tree URI, or null if the
  /// user cancelled. The grant is persisted natively across reboots.
  Future<String?> pickTree() => _channel.invokeMethod<String>('pickTree');

  /// Tree URI granted in a previous session, if still valid.
  Future<String?> persistedTree() =>
      _channel.invokeMethod<String>('persistedTree');

  Future<List<SafFile>> walkTree(String treeUri) async {
    final raw =
        await _channel.invokeListMethod<dynamic>('walkTree', {
          'uri': treeUri,
        }) ??
        const [];
    return raw.map((e) {
      final m = (e as Map).cast<String, String>();
      return SafFile(m['uri']!, m['relPath']!);
    }).toList();
  }

  Future<Uint8List?> readFile(String uri) =>
      _channel.invokeMethod<Uint8List>('readFile', {'uri': uri});
}
