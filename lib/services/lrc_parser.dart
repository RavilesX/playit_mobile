import 'dart:convert';
import 'dart:typed_data';
import '../models/lrc_line.dart';

final _tagPattern = RegExp(r'<[^>]+>');
final _timePattern = RegExp(r'^\[(\d+):(\d+\.\d+)\](.*)');

/// Parses raw .lrc file bytes (UTF-8, tolerant of malformed sequences).
List<LrcLine> parseLrcBytes(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return [];
  try {
    final text = utf8.decode(bytes, allowMalformed: true);
    return parseLrcLines(const LineSplitter().convert(text));
  } catch (_) {
    return [];
  }
}

List<LrcLine> parseLrcLines(List<String> lines) {
  final result = <LrcLine>[];
  double? currentTime;
  final buffer = <String>[];

  void flush() {
    if (currentTime != null && buffer.isNotEmpty) {
      final raw = buffer.join('\n');
      final clean = raw.replaceAll(_tagPattern, '').trim();
      if (clean.isNotEmpty) {
        result.add(LrcLine(timeSeconds: currentTime, text: clean));
      }
    }
  }

  for (final line in lines) {
    final match = _timePattern.firstMatch(line.trim());
    if (match != null) {
      flush();
      buffer.clear();
      final mins = int.parse(match.group(1)!);
      final secs = double.parse(match.group(2)!);
      currentTime = mins * 60.0 + secs;
      final text = match.group(3) ?? '';
      if (text.trim().isNotEmpty) buffer.add(text);
    } else if (currentTime != null && line.trim().isNotEmpty) {
      buffer.add(line);
    }
  }
  flush();

  return result;
}
