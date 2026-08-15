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

/// Extensions accepted for the "any image in the folder" cover fallback
/// (desktop's second cascade level, §2.5 in the functional doc).
const _fallbackCoverExtensions = ['.jpg', '.jpeg', '.png', '.bmp', '.gif'];

/// Parses the data.json shape
/// {artist: {songTitle: {path, metadata: {...}}}} into (artist, title,
/// metadata) triples. Malformed input, or a song entry that isn't a map,
/// yields metadata {} for that entry; the whole file being malformed
/// yields an empty list.
List<({String artist, String title, Map<String, dynamic> metadata})>
songsFromDataJson(String raw) {
  try {
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic>) return const [];
    final out = <({String artist, String title, Map<String, dynamic> metadata})>[];
    for (final artist in data.keys) {
      final artistMap = data[artist];
      if (artistMap is! Map) continue;
      for (final title in artistMap.keys) {
        final songData = artistMap[title];
        final meta = songData is Map && songData['metadata'] is Map
            ? Map<String, dynamic>.from(songData['metadata'] as Map)
            : const <String, dynamic>{};
        out.add((artist: artist, title: title.toString(), metadata: meta));
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

  /// cover.png, or failing that the first image file directly in the
  /// song's folder (alphabetical, non-recursive — matches desktop's
  /// second fallback level).
  static String? _resolveCover(String folder) {
    final coverPath = '$folder/cover.png';
    if (File(coverPath).existsSync()) return coverPath;

    try {
      final candidates = Directory(folder)
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) {
            final lower = p.toLowerCase();
            return _fallbackCoverExtensions.any((ext) => lower.endsWith(ext));
          })
          .toList()
        ..sort();
      return candidates.isEmpty ? null : candidates.first;
    } catch (_) {
      return null;
    }
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

          final coverRef = _resolveCover(folder);
          final lyricsPath = '$folder/lyrics.lrc';
          for (final e in entries) {
            songs.add(
              Song(
                artist: e.artist,
                title: e.title,
                stemRefs: stemRefs,
                coverRef: coverRef,
                lyricsRef: File(lyricsPath).existsSync() ? lyricsPath : null,
                metadata: e.metadata,
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

      final coverRef = byRelPath[child('cover.png')] ?? _fallbackCover(byRelPath, dir);

      for (final e in entries) {
        songs.add(
          Song(
            artist: e.artist,
            title: e.title,
            stemRefs: stemRefs,
            coverRef: coverRef,
            lyricsRef: byRelPath[child('lyrics.lrc')],
            metadata: e.metadata,
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

  /// First image file directly inside [dir] (alphabetical), or null.
  static String? _fallbackCover(Map<String, String> byRelPath, String dir) {
    final candidates = byRelPath.keys.where((rel) {
      if (_dirname(rel) != dir) return false;
      final lower = rel.toLowerCase();
      return _fallbackCoverExtensions.any((ext) => lower.endsWith(ext));
    }).toList()
      ..sort();
    return candidates.isEmpty ? null : byRelPath[candidates.first];
  }
}
