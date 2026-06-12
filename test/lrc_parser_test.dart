import 'package:flutter_test/flutter_test.dart';
import 'package:playit_mobile/services/lrc_parser.dart';

void main() {
  group('parseLrcLines', () {
    test('parses timestamped lines', () {
      final result = parseLrcLines([
        '[00:12.50]Primera línea',
        '[01:05.00]Segunda línea',
      ]);
      expect(result.length, 2);
      expect(result[0].timeSeconds, 12.5);
      expect(result[0].text, 'Primera línea');
      expect(result[1].timeSeconds, 65.0);
      expect(result[1].text, 'Segunda línea');
    });

    test('joins continuation lines into the previous timestamp', () {
      final result = parseLrcLines([
        '[00:10.00]Línea uno',
        'continuación',
        '[00:20.00]Línea dos',
      ]);
      expect(result.length, 2);
      expect(result[0].text, 'Línea uno\ncontinuación');
    });

    test('strips enhanced-LRC angle-bracket tags', () {
      final result = parseLrcLines([
        '[00:01.00]<00:01.00>Hola <00:01.50>mundo',
      ]);
      expect(result.single.text, 'Hola mundo');
    });

    test('skips entries that are empty after cleaning', () {
      final result = parseLrcLines([
        '[00:01.00]<00:01.00>',
        '[00:02.00]Texto real',
      ]);
      expect(result.single.text, 'Texto real');
    });

    test('ignores metadata and malformed lines', () {
      final result = parseLrcLines([
        '[ar:Artista]',
        '[ti:Título]',
        'línea suelta sin timestamp previo',
        '[00:03.25]Letra',
      ]);
      expect(result.single.timeSeconds, 3.25);
      expect(result.single.text, 'Letra');
    });

    test('returns empty list for empty input', () {
      expect(parseLrcLines([]), isEmpty);
    });
  });
}
