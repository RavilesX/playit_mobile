import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import '../models/song.dart';

Future<List<Song>> scanLibrary(String libraryPath) async {
  return Isolate.run(() => _scanSync(libraryPath));
}

List<Song> _scanSync(String libraryPath) {
  final songs = <Song>[];
  final dir = Directory(libraryPath);
  if (!dir.existsSync()) return songs;

  try {
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('data.json')) continue;

      try {
        final raw = entity.readAsStringSync();
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final folderPath = File(entity.path).parent.path;

        for (final artist in data.keys) {
          final artistMap = data[artist];
          if (artistMap is! Map) continue;
          for (final songTitle in artistMap.keys) {
            final otherFile = File('$folderPath/separated/other.mp3');
            if (otherFile.existsSync()) {
              songs.add(Song(
                artist: artist,
                title: songTitle.toString(),
                folderPath: folderPath,
              ));
            }
          }
        }
      } catch (_) {
        continue;
      }
    }
  } catch (_) {}

  return songs;
}
