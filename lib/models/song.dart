class Song {
  final String artist;
  final String title;
  final String folderPath;

  const Song({
    required this.artist,
    required this.title,
    required this.folderPath,
  });

  String get drumsPath => '$folderPath/separated/drums.mp3';
  String get vocalsPath => '$folderPath/separated/vocals.mp3';
  String get bassPath => '$folderPath/separated/bass.mp3';
  String get otherPath => '$folderPath/separated/other.mp3';
  String get coverPath => '$folderPath/cover.png';
  String get lyricsPath => '$folderPath/lyrics.lrc';
  String get displayName => '$artist - $title';

  @override
  bool operator ==(Object other) =>
      other is Song && artist == other.artist && title == other.title;

  @override
  int get hashCode => Object.hash(artist, title);
}
