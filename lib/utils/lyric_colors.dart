import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/lrc_line.dart';

/// Maps a parsed [LyricColor] to the color it's drawn with on screen.
/// Explicit line colors (azul/blanco/rojo) render the same regardless of
/// whether the line is current or next; the default color differs between
/// the two (current line is brighter/larger, matching desktop's rich text).
Color lyricRowColor(LyricColor color, {required bool isCurrent}) {
  switch (color) {
    case LyricColor.azul:
      return AppColors.lyricAzul;
    case LyricColor.blanco:
      return AppColors.lyricBlanco;
    case LyricColor.rojo:
      return AppColors.lyricRojo;
    case LyricColor.defaultColor:
      return isCurrent
          ? AppColors.lyricsCurrentColor
          : AppColors.lyricsNextColor;
  }
}

/// Builds the colored, multi-row rich-text span for one lyric line. Shared
/// between the inline lyrics tab and the fullscreen karaoke view so both
/// render identically.
TextSpan lyricLineSpan(
  LrcLine line,
  double fontSize, {
  required bool isCurrent,
}) {
  final children = <TextSpan>[];
  for (var i = 0; i < line.rows.length; i++) {
    if (i > 0) children.add(const TextSpan(text: '\n'));
    final row = line.rows[i];
    children.add(
      TextSpan(
        text: row.text,
        style: TextStyle(color: lyricRowColor(row.color, isCurrent: isCurrent)),
      ),
    );
  }
  return TextSpan(
    style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, height: 1.4),
    children: children,
  );
}
