import 'package:flutter_test/flutter_test.dart';
import 'package:playit_mobile/utils/tags.dart';

void main() {
  group('splitTags', () {
    test('parte por comas y limpia espacios', () {
      expect(splitTags('Voz, Bajo'), ['Voz', 'Bajo']);
      expect(splitTags('  Voz ,Bajo  '), ['Voz', 'Bajo']);
    });

    test('descarta vacíos en vez de dejar tags en blanco', () {
      expect(splitTags(''), isEmpty);
      expect(splitTags(',, ,'), isEmpty);
      expect(splitTags('Voz,,Bajo'), ['Voz', 'Bajo']);
    });

    test('conserva el orden en que se escribieron', () {
      expect(splitTags('c, a, b'), ['c', 'a', 'b']);
    });
  });

  group('stemForTag', () {
    test('reconoce las pistas como las escribe el usuario', () {
      expect(stemForTag('Batería'), 'drums');
      expect(stemForTag('bateria'), 'drums');
      expect(stemForTag('VOZ'), 'vocals');
      expect(stemForTag(' Bajo '), 'bass');
      expect(stemForTag('Otros'), 'other');
    });

    test('acepta también los nombres en inglés del motor', () {
      expect(stemForTag('drums'), 'drums');
      expect(stemForTag('vocals'), 'vocals');
    });

    test('una tag común no nombra ninguna pista', () {
      expect(stemForTag('ensayo'), isNull);
      expect(stemForTag(''), isNull);
    });
  });

  group('stemsNamedBy', () {
    test('junta las pistas nombradas, ignorando el resto', () {
      expect(stemsNamedBy('Voz, ensayo, Bajo'), {'vocals', 'bass'});
    });

    test('sin pistas nombradas devuelve vacío (no toca la mezcla)', () {
      expect(stemsNamedBy('ensayo, tono alto'), isEmpty);
      expect(stemsNamedBy(''), isEmpty);
    });

    test('la misma pista dos veces cuenta una sola', () {
      expect(stemsNamedBy('Voz, vocales, VOCALS'), {'vocals'});
    });
  });

  test('las sugerencias son pistas reales del mezclador', () {
    for (final s in tagSuggestions) {
      expect(stemForTag(s), isNotNull, reason: '$s debería nombrar una pista');
    }
  });
}
