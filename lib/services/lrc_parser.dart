import 'dart:io';
import '../models/lrc_line.dart';

final _tagPattern = RegExp(r'<[^>]+>');
final _timePattern = RegExp(r'^\[(\d+):(\d+\.\d+)\](.*)');

Future<List<LrcLine>> parseLrcFile(String path) async {
  final file = File(path);
  if (!file.existsSync()) return [];

  try {
    final lines = file.readAsLinesSync();
    return _parseLines(lines);
  } catch (_) {
    return [];
  }
}

List<LrcLine> _parseLines(List<String> lines) {
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
