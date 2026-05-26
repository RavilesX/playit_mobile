import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF1A1A1A);
  static const Color surface = Color(0xFF2A2A2A);
  static const Color border = Color(0xFF404040);
  static const Color accentBlue = Color(0xFF3AABEF);
  static const Color accentPurple = Color(0xFF7E54AF);
  static const Color pinkHighlight = Color(0xFFEEA1CD);
  static const Color pinkText = Color(0xFFFC5490);
  static const Color lyricsCurrentColor = Color(0xFFF88FFF);
  static const Color lyricsNextColor = Color(0xFFD3D3D3);
  static const Color gradientA = Color(0xFF7A82FF); // rgba(122,130,255)
  static const Color gradientB = Color(0xFF844CAB); // rgba(132,76,171)
  static const Color progressActive = Color(0xFFBC87FF); // blend purple-blue
  static const Color progressInactive = Color(0xFF343B48);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
    colors: [gradientA, gradientB],
  );

  static const LinearGradient progressGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFFEAAC7), Color(0xFF6455FF)],
  );
}
