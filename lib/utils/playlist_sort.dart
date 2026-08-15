import 'dart:math';
import '../models/song.dart';

/// Sorts (or shuffles, for key == 'random') a copy of [songs]. Mirrors
/// desktop's `sort_playlist` (audio_player.py): ties break on the other
/// field, comparisons are case-insensitive.
List<Song> sortedSongs(
  List<Song> songs, {
  required String key,
  bool reverse = false,
  Random? random,
}) {
  final out = List<Song>.of(songs);
  if (key == 'random') {
    out.shuffle(random);
    return out;
  }

  int Function(Song, Song) cmp;
  if (key == 'song') {
    cmp = (a, b) {
      final c = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return c != 0 ? c : a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
    };
  } else {
    cmp = (a, b) {
      final c = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
      return c != 0 ? c : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    };
  }
  out.sort(reverse ? (a, b) => cmp(b, a) : cmp);
  return out;
}
