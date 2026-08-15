import 'package:flutter_test/flutter_test.dart';
import 'package:playit_mobile/services/media_library.dart';

void main() {
  group('songsFromDataJson', () {
    test('parses artist/title pairs', () {
      const raw = '{"Artista": {"Canción Uno": {}, "Canción Dos": {}}}';
      final result = songsFromDataJson(raw);
      expect(result.length, 2);
      expect(result[0].artist, 'Artista');
      expect(result[0].title, 'Canción Uno');
      expect(result[1].title, 'Canción Dos');
    });

    test('supports multiple artists', () {
      const raw = '{"A": {"x": {}}, "B": {"y": {}}}';
      final result = songsFromDataJson(raw);
      expect(result.map((e) => e.artist).toSet(), {'A', 'B'});
    });

    test('skips artists whose value is not a map', () {
      const raw = '{"A": "no es mapa", "B": {"y": {}}}';
      final result = songsFromDataJson(raw);
      expect(result.single.artist, 'B');
    });

    test('returns empty for malformed JSON', () {
      expect(songsFromDataJson('not json'), isEmpty);
      expect(songsFromDataJson('[1,2,3]'), isEmpty);
      expect(songsFromDataJson(''), isEmpty);
    });

    test('extracts the metadata block when present', () {
      const raw = '''
      {"Alejandro Sanz": {"Corazón Partío": {
        "path": "music_library/Alejandro Sanz/Corazón Partío",
        "metadata": {"album": "Colección Definitiva", "anio": "2011",
                      "genero": "Latin Pop", "formato": "FLAC", "kbps": 320}
      }}}''';
      final result = songsFromDataJson(raw);
      expect(result.single.metadata['album'], 'Colección Definitiva');
      expect(result.single.metadata['kbps'], 320);
    });

    test('metadata is empty when the block is absent (old library entries)', () {
      const raw = '{"A": {"x": {"path": "some/path"}}}';
      final result = songsFromDataJson(raw);
      expect(result.single.metadata, isEmpty);
    });

    test('metadata is empty when the song entry is not a map', () {
      const raw = '{"A": {"x": "not a map"}}';
      final result = songsFromDataJson(raw);
      expect(result.single.metadata, isEmpty);
    });
  });
}
