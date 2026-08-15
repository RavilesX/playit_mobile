/// Line color tags supported by the desktop .lrc format (`<font color>`).
/// `rojo` doubles as the auto-unmute marker: it counts as a blank line even
/// when it has text (see [LrcLine.isBlankForAutoUnmute]).
enum LyricColor { defaultColor, azul, blanco, rojo }

class LyricRow {
  final String text;
  final LyricColor color;

  const LyricRow(this.text, this.color);
}

class LrcLine {
  final double timeSeconds;
  final List<LyricRow> rows;

  const LrcLine({required this.timeSeconds, required this.rows});

  /// Plain-text join of all rows (compatibility with single-string display).
  String get text => rows.map((r) => r.text).join('\n');

  /// True when this line should trigger the vocals auto-unmute: no real
  /// text, or explicitly marked red. Mirrors desktop's
  /// `_current_lyric_is_blank` (audio_player.py).
  bool get isBlankForAutoUnmute =>
      rows.any((r) => r.color == LyricColor.rojo) || text.trim().isEmpty;
}
