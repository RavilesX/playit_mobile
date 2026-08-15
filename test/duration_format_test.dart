import 'package:flutter_test/flutter_test.dart';
import 'package:playit_mobile/utils/duration_format.dart';

void main() {
  group('formatSongDuration', () {
    test('minutes are unpadded, seconds are zero-padded', () {
      expect(formatSongDuration(const Duration(seconds: 5)), '0:05');
      expect(formatSongDuration(const Duration(minutes: 3, seconds: 45)), '3:45');
      expect(
        formatSongDuration(const Duration(minutes: 12, seconds: 3)),
        '12:03',
      );
    });

    test('drops sub-second precision', () {
      expect(
        formatSongDuration(const Duration(minutes: 1, milliseconds: 59900)),
        '1:59',
      );
    });
  });
}
