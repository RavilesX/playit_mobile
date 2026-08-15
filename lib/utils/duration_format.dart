/// "M:SS" (unpadded minutes), matching desktop's `get_song_duration`
/// (lazy_resources.py): `f"{int(seconds)//60}:{int(seconds)%60:02d}"`.
String formatSongDuration(Duration d) {
  final totalSeconds = d.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
