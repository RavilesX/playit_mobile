import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:playit_mobile/models/song.dart';
import 'package:playit_mobile/utils/playlist_sort.dart';

Song _song(String artist, String title) =>
    Song(artist: artist, title: title, stemRefs: const {});

void main() {
  group('sortedSongs', () {
    final songs = [
      _song('Beta', 'Zeta'),
      _song('alfa', 'Alfa'),
      _song('Beta', 'Alfa'),
    ];

    test('artist A-Z, ties broken by title', () {
      final result = sortedSongs(songs, key: 'artist');
      expect(result.map((s) => '${s.artist}/${s.title}').toList(), [
        'alfa/Alfa',
        'Beta/Alfa',
        'Beta/Zeta',
      ]);
    });

    test('artist Z-A', () {
      final result = sortedSongs(songs, key: 'artist', reverse: true);
      expect(result.first.artist.toLowerCase(), 'beta');
      expect(result.last.artist.toLowerCase(), 'alfa');
    });

    test('song A-Z, ties broken by artist', () {
      final result = sortedSongs(songs, key: 'song');
      expect(result.map((s) => '${s.title}/${s.artist}').toList(), [
        'Alfa/alfa',
        'Alfa/Beta',
        'Zeta/Beta',
      ]);
    });

    test('comparison is case-insensitive', () {
      final mixed = [_song('zeta', 'x'), _song('Alfa', 'y')];
      final result = sortedSongs(mixed, key: 'artist');
      expect(result.first.artist, 'Alfa');
    });

    test('random reshuffles without mutating the input list', () {
      final original = List<Song>.of(songs);
      final result = sortedSongs(songs, key: 'random', random: Random(1));
      expect(songs, original); // input untouched
      expect(result.toSet(), songs.toSet()); // same elements
    });

    test('does not mutate the input for regular sorts either', () {
      final original = List<Song>.of(songs);
      sortedSongs(songs, key: 'artist');
      expect(songs, original);
    });
  });
}
