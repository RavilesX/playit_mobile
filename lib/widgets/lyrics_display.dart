import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/lrc_line.dart';
import '../models/song.dart';

class LyricsDisplay extends StatelessWidget {
  final Song? song;
  final List<LrcLine> lyrics;
  final int currentIndex;

  const LyricsDisplay({
    super.key,
    required this.song,
    required this.lyrics,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    if (song == null) {
      return const Center(
        child: Text('Sin canción', style: TextStyle(color: AppColors.border)),
      );
    }

    if (lyrics.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            song!.artist,
            style: const TextStyle(
              color: AppColors.accentBlue,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            song!.title,
            style: const TextStyle(
              color: AppColors.accentPurple,
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const Text(
            'Sin letras disponibles',
            style: TextStyle(color: AppColors.border),
          ),
        ],
      );
    }

    final current = currentIndex >= 0 && currentIndex < lyrics.length
        ? lyrics[currentIndex].text
        : '';
    final next = currentIndex + 1 < lyrics.length
        ? lyrics[currentIndex + 1].text
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                Text(
                  song!.artist,
                  style: const TextStyle(
                    color: AppColors.accentBlue,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  song!.title,
                  style: const TextStyle(
                    color: AppColors.accentPurple,
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          // Current lyric
          Expanded(
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  current,
                  key: ValueKey(currentIndex),
                  style: const TextStyle(
                    color: AppColors.lyricsCurrentColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          // Next lyric
          if (next.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                next,
                style: const TextStyle(
                  color: AppColors.lyricsNextColor,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
