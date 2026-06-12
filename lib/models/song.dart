/// A song's files are addressed by opaque refs (filesystem paths on
/// desktop/iOS, content:// URIs on Android). Only the MediaLibrary that
/// produced them knows how to read them.
class Song {
  final String artist;
  final String title;

  /// stem name ('drums', 'vocals', 'bass', 'other') -> ref. Always complete.
  final Map<String, String> stemRefs;
  final String? coverRef;
  final String? lyricsRef;

  const Song({
    required this.artist,
    required this.title,
    required this.stemRefs,
    this.coverRef,
    this.lyricsRef,
  });

  String get displayName => '$artist - $title';

  @override
  bool operator ==(Object other) =>
      other is Song && artist == other.artist && title == other.title;

  @override
  int get hashCode => Object.hash(artist, title);
}
