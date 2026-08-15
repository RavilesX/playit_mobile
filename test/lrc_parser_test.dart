import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:playit_mobile/models/lrc_line.dart';
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

    test('keeps blank entries (needed for auto-unmute detection)', () {
      // Desktop's loader always appends an entry per timestamp, even with
      // empty text — auto-unmute triggers on exactly this case.
      final result = parseLrcLines([
        '[00:01.00]<00:01.00>',
        '[00:02.00]Texto real',
      ]);
      expect(result.length, 2);
      expect(result[0].text, '');
      expect(result[0].isBlankForAutoUnmute, isTrue);
      expect(result[1].text, 'Texto real');
    });

    test('a line with only a timestamp and no text is blank', () {
      final result = parseLrcLines(['[00:05.00]']);
      expect(result.single.text, '');
      expect(result.single.isBlankForAutoUnmute, isTrue);
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

  group('line colors', () {
    test('a single <font> wrapping the whole line colors every row', () {
      final result = parseLrcLines([
        '[00:01.00]<center><font color="#3AABEF">Hola mundo</font></center>',
      ]);
      final row = result.single.rows.single;
      expect(row.text, 'Hola mundo');
      expect(row.color, LyricColor.azul);
    });

    test('hex matching is case-insensitive', () {
      final result = parseLrcLines([
        '[00:01.00]<center><font color="#b23a36">Rojo</font></center>',
      ]);
      expect(result.single.rows.single.color, LyricColor.rojo);
    });

    test('mixed per-row colors within one multi-line block', () {
      final result = parseLrcLines([
        '[00:01.00]<center><font color="#3AABEF">Renglón 1</font>',
        '<font color="#F6F5F4">Renglón 2</font></center>',
      ]);
      final rows = result.single.rows;
      expect(rows, hasLength(2));
      expect(rows[0].text, 'Renglón 1');
      expect(rows[0].color, LyricColor.azul);
      expect(rows[1].text, 'Renglón 2');
      expect(rows[1].color, LyricColor.blanco);
    });

    test('no color tag falls back to the default color', () {
      final result = parseLrcLines(['[00:01.00]<center>Sin color</center>']);
      expect(result.single.rows.single.color, LyricColor.defaultColor);
    });

    test('rojo marks the line as blank for auto-unmute even with text', () {
      final result = parseLrcLines([
        '[00:01.00]<center><font color="#B23A36">Instrumental</font></center>',
      ]);
      expect(result.single.text, 'Instrumental');
      expect(result.single.isBlankForAutoUnmute, isTrue);
    });
  });

  group('parseLrcBytes sentinel handling', () {
    test('a "letras no encontradas" file yields no lyrics', () {
      const content =
          '[00:00.00]<center style="color: #ff2626;">'
          'Letras no encontradas</center>\n';
      final result = parseLrcBytes(Uint8List.fromList(utf8.encode(content)));
      expect(result, isEmpty);
    });

    test('is case-insensitive and ignores surrounding markup', () {
      const content = '[00:00.00]<center>LETRAS NO ENCONTRADAS</center>\n';
      final result = parseLrcBytes(Uint8List.fromList(utf8.encode(content)));
      expect(result, isEmpty);
    });

    test('a real lyrics file is unaffected', () {
      const content = '[00:01.00]Hola\n[00:02.00]Mundo\n';
      final result = parseLrcBytes(Uint8List.fromList(utf8.encode(content)));
      expect(result, hasLength(2));
    });
  });
}
