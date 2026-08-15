import 'dart:convert';
import 'dart:typed_data';
import '../models/lrc_line.dart';

final _timePattern = RegExp(r'^\[(\d+):(\d+\.\d+)\](.*)');
final _tagPattern = RegExp(r'<[^>]+>');
final _centerWrapPattern = RegExp(
  r'^<center\b[^>]*>([\s\S]*)</center>$',
  caseSensitive: false,
);
final _fullFontWrapPattern = RegExp(
  r'^<font\s+color="([^"]+)">([\s\S]*)</font>$',
  caseSensitive: false,
);
final _fontColorPattern = RegExp(
  r'<font\s+color="([^"]+)"',
  caseSensitive: false,
);

/// Sentinel text the desktop app writes when no lyrics were found online
/// (`LYRICS_NOT_FOUND_TEXT` in audio_player.py). Mobile never fetches
/// lyrics itself, but a synced `.lrc` from the shared library may still
/// carry this marker.
const _notFoundMarkers = ['letras no encontradas', 'no se encontraron'];

/// Maps the desktop's `LYRIC_COLORS` hex values (lyrics_sync_editor.py) to
/// [LyricColor]. Unknown hex values fall back to the default color.
LyricColor _hexToColor(String hex) {
  switch (hex.toLowerCase()) {
    case '#3aabef':
      return LyricColor.azul;
    case '#f6f5f4':
      return LyricColor.blanco;
    case '#b23a36':
      return LyricColor.rojo;
    default:
      return LyricColor.defaultColor;
  }
}

/// Color explicitly set on this row via its own `<font color>` tag, or null
/// if the row has none (falls back to the line-level color).
LyricColor? _rowOwnColor(String row) {
  final m = _fontColorPattern.firstMatch(row);
  if (m == null) return null;
  final c = _hexToColor(m.group(1)!);
  return c == LyricColor.defaultColor ? null : c;
}

/// Splits a raw (possibly multi-physical-line) lyric block into colored
/// rows. Mirrors desktop's `split_rows` (lyrics_sync_editor.py): supports
/// both a single `<font>` wrapping the whole line (every row inherits that
/// color) and per-row `<font>` tags (mixed colors within one line).
List<LyricRow> _splitRows(String raw) {
  var inner = raw.trim();

  final centerMatch = _centerWrapPattern.firstMatch(inner);
  if (centerMatch != null) inner = centerMatch.group(1)!;

  LyricColor? lineColor;
  final fontMatch = _fullFontWrapPattern.firstMatch(inner.trim());
  if (fontMatch != null) {
    final c = _hexToColor(fontMatch.group(1)!);
    lineColor = c == LyricColor.defaultColor ? null : c;
    inner = fontMatch.group(2)!;
  }

  return inner.split('\n').map((row) {
    final color = _rowOwnColor(row) ?? lineColor ?? LyricColor.defaultColor;
    final clean = row.replaceAll(_tagPattern, '').trim();
    return LyricRow(clean, color);
  }).toList();
}

/// Parses raw .lrc file bytes (UTF-8, tolerant of malformed sequences).
/// Returns an empty list if the file only contains the "not found"
/// sentinel the desktop app writes when it couldn't fetch lyrics.
List<LrcLine> parseLrcBytes(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return [];
  try {
    final text = utf8.decode(bytes, allowMalformed: true);
    final lines = parseLrcLines(const LineSplitter().convert(text));
    if (_isNotFoundSentinel(lines)) return [];
    return lines;
  } catch (_) {
    return [];
  }
}

bool _isNotFoundSentinel(List<LrcLine> lines) {
  if (lines.isEmpty) return false;
  final joined = lines.map((l) => l.text).join(' ').toLowerCase();
  return _notFoundMarkers.any(joined.contains);
}

List<LrcLine> parseLrcLines(List<String> lines) {
  final result = <LrcLine>[];
  double? currentTime;
  final buffer = <String>[];
  var hasEntry = false;

  void flush() {
    if (currentTime != null && hasEntry) {
      result.add(
        LrcLine(timeSeconds: currentTime, rows: _splitRows(buffer.join('\n'))),
      );
    }
  }

  for (final line in lines) {
    final match = _timePattern.firstMatch(line.trim());
    if (match != null) {
      flush();
      buffer.clear();
      hasEntry = true;
      final mins = int.parse(match.group(1)!);
      final secs = double.parse(match.group(2)!);
      currentTime = mins * 60.0 + secs;
      buffer.add(match.group(3) ?? '');
    } else if (currentTime != null && line.trim().isNotEmpty) {
      buffer.add(line);
    }
  }
  flush();

  return result;
}
