import 'package:flutter_test/flutter_test.dart';
import 'package:playit_mobile/utils/text_fold.dart';

void main() {
  group('foldText', () {
    test('canción and cancion fold to the same value', () {
      expect(foldText('Canción'), foldText('cancion'));
    });

    test('strips accents and lowercases', () {
      expect(foldText('Joaquín Sabina'), 'joaquin sabina');
    });

    test('handles ñ and ç', () {
      expect(foldText('Muñeca de porcelana'), 'muneca de porcelana');
      expect(foldText('França'), 'franca');
    });

    test('leaves plain ASCII untouched aside from case', () {
      expect(foldText('Hello World'), 'hello world');
    });
  });
}
