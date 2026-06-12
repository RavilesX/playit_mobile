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
  });
}
