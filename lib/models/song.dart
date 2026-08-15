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

  /// Source-file metadata from data.json's "metadata" block (album, anio,
  /// genero, formato, kbps) — see songsFromDataJson. Empty for songs
  /// separated before this was recorded, or when a field wasn't present.
  final Map<String, dynamic> metadata;

  /// "M:SS", filled in lazily the first time the song is played and cached
  /// (see PlayerProvider) — not known until the stems are decoded. Mutable
  /// so the cache can update an already-scanned Song in place.
  String? duration;

  Song({
    required this.artist,
    required this.title,
    required this.stemRefs,
    this.coverRef,
    this.lyricsRef,
    this.metadata = const {},
    this.duration,
  });

  String get displayName => '$artist - $title';

  String metadataOrUnknown(String key) {
    final v = metadata[key];
    return v == null || v.toString().isEmpty ? 'Desconocido' : v.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is Song && artist == other.artist && title == other.title;

  @override
  int get hashCode => Object.hash(artist, title);
}
