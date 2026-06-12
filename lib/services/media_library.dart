import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import '../models/song.dart';
import 'audio_engine.dart' show stemNames;
import 'saf_storage.dart';

/// Source of the music library. Scans for songs and reads their files by ref.
abstract class MediaLibrary {
  Future<List<Song>> scan();
  Future<Uint8List?> read(String ref);
}

/// Parses the data.json shape {artist: {songTitle: ...}} into (artist, title)
/// pairs. Malformed input yields an empty list.
List<({String artist, String title})> songsFromDataJson(String raw) {
  try {
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic>) return const [];
    final out = <({String artist, String title})>[];
    for (final artist in data.keys) {
      final artistMap = data[artist];
      if (artistMap is! Map) continue;
      for (final title in artistMap.keys) {
        out.add((artist: artist, title: title.toString()));
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// Direct filesystem access (desktop, iOS sandbox). Refs are absolute paths.
class FileMediaLibrary implements MediaLibrary {
  final String rootPath;
  const FileMediaLibrary(this.rootPath);

  @override
  Future<List<Song>> scan() {
    final path = rootPath;
    return Isolate.run(() => _scanSync(path));
  }

  @override
  Future<Uint8List?> read(String ref) async {
    final file = File(ref);
    return await file.exists() ? file.readAsBytes() : null;
  }

  static List<Song> _scanSync(String rootPath) {
    final songs = <Song>[];
    final dir = Directory(rootPath);
    if (!dir.existsSync()) return songs;

    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('data.json')) continue;

        try {
          final entries = songsFromDataJson(entity.readAsStringSync());
          if (entries.isEmpty) continue;

          final folder = entity.parent.path;
          final stemRefs = <String, String>{};
          var complete = true;
          for (final name in stemNames) {
            final stemPath = '$folder/separated/$name.mp3';
            if (!File(stemPath).existsSync()) {
              complete = false;
              break;
            }
            stemRefs[name] = stemPath;
          }
          if (!complete) continue;

          final coverPath = '$folder/cover.png';
          final lyricsPath = '$folder/lyrics.lrc';
          for (final e in entries) {
            songs.add(
              Song(
                artist: e.artist,
                title: e.title,
                stemRefs: stemRefs,
                coverRef: File(coverPath).existsSync() ? coverPath : null,
                lyricsRef: File(lyricsPath).existsSync() ? lyricsPath : null,
              ),
            );
          }
        } catch (_) {
          continue;
        }
      }
    } catch (_) {}

    return songs;
  }
}

/// Storage Access Framework tree (Android). Refs are content:// URIs.
class SafMediaLibrary implements MediaLibrary {
  final String treeUri;
  final SafStorage _saf;

  SafMediaLibrary(this.treeUri, {SafStorage? saf}) : _saf = saf ?? SafStorage();

  @override
  Future<List<Song>> scan() async {
    final files = await _saf.walkTree(treeUri);
    final byRelPath = {for (final f in files) f.relPath: f.uri};

    final songs = <Song>[];
    for (final f in files) {
      if (!_isDataJson(f.relPath)) continue;

      final bytes = await _saf.readFile(f.uri);
      if (bytes == null) continue;
      final entries = songsFromDataJson(
        utf8.decode(bytes, allowMalformed: true),
      );
      if (entries.isEmpty) continue;

      final dir = _dirname(f.relPath);
      String child(String rel) => dir.isEmpty ? rel : '$dir/$rel';

      final stemRefs = <String, String>{};
      var complete = true;
      for (final name in stemNames) {
        final uri = byRelPath[child('separated/$name.mp3')];
        if (uri == null) {
          complete = false;
          break;
        }
        stemRefs[name] = uri;
      }
      if (!complete) continue;

      for (final e in entries) {
        songs.add(
          Song(
            artist: e.artist,
            title: e.title,
            stemRefs: stemRefs,
            coverRef: byRelPath[child('cover.png')],
            lyricsRef: byRelPath[child('lyrics.lrc')],
          ),
        );
      }
    }
    return songs;
  }

  @override
  Future<Uint8List?> read(String ref) => _saf.readFile(ref);

  static bool _isDataJson(String relPath) =>
      relPath == 'data.json' || relPath.endsWith('/data.json');

  static String _dirname(String relPath) {
    final idx = relPath.lastIndexOf('/');
    return idx < 0 ? '' : relPath.substring(0, idx);
  }
}
