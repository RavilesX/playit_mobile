import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/player_provider.dart';
import '../screens/lyrics_fullscreen_screen.dart';
import '../utils/lyric_colors.dart';

const kLyricsBaseCurrentFontSize = 28.0;
const kLyricsBaseNextFontSize = 16.0;

class LyricsDisplay extends StatefulWidget {
  const LyricsDisplay({super.key});

  @override
  State<LyricsDisplay> createState() => _LyricsDisplayState();
}

class _LyricsDisplayState extends State<LyricsDisplay> {
  void _openFullscreen() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LyricsFullscreenScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final song = provider.currentSong;
    final lyrics = provider.lyrics;
    final currentIndex = provider.currentLyricIndex;
    final scale = provider.lyricsScale;

    if (song == null) {
      return const Center(
        child: Text('Sin canción', style: TextStyle(color: AppColors.border)),
      );
    }

    Widget content;
    if (lyrics.isEmpty) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            song.artist,
            style: const TextStyle(
              color: AppColors.accentBlue,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            song.title,
            style: const TextStyle(color: AppColors.accentPurple, fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const Text(
            'Sin letras disponibles',
            style: TextStyle(color: AppColors.border),
          ),
        ],
      );
    } else {
      final currentLine = currentIndex >= 0 && currentIndex < lyrics.length
          ? lyrics[currentIndex]
          : null;
      final nextLine = currentIndex + 1 < lyrics.length
          ? lyrics[currentIndex + 1]
          : null;

      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  Text(
                    song.artist,
                    style: const TextStyle(
                      color: AppColors.accentBlue,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    song.title,
                    style: const TextStyle(
                      color: AppColors.accentPurple,
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: currentLine == null
                      ? const SizedBox.shrink()
                      : Text.rich(
                          lyricLineSpan(
                            currentLine,
                            kLyricsBaseCurrentFontSize * scale,
                            isCurrent: true,
                          ),
                          key: ValueKey(currentIndex),
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
            ),
            if (nextLine != null && nextLine.text.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text.rich(
                  lyricLineSpan(
                    nextLine,
                    kLyricsBaseNextFontSize * scale,
                    isCurrent: false,
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

    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: lyrics.isEmpty ? null : _openFullscreen,
          child: content,
        ),
        if (lyrics.isNotEmpty) ...[
          Positioned(
            top: 0,
            right: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  iconSize: 20,
                  icon: const Icon(Icons.text_decrease, color: Colors.grey),
                  onPressed: () => provider.adjustLyricsScale(-0.1),
                ),
                IconButton(
                  iconSize: 20,
                  icon: const Icon(Icons.text_increase, color: Colors.grey),
                  onPressed: () => provider.adjustLyricsScale(0.1),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  iconSize: 18,
                  tooltip: 'Adelantar letra 0.5s',
                  icon: const Icon(Icons.fast_rewind, color: Colors.grey),
                  onPressed: () => provider.adjustLyricOffset(-50),
                ),
                if (provider.currentLyricOffsetSeconds != 0)
                  Text(
                    '${provider.currentLyricOffsetSeconds >= 0 ? '+' : ''}'
                    '${provider.currentLyricOffsetSeconds.toStringAsFixed(1)}s',
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                IconButton(
                  iconSize: 18,
                  tooltip: 'Atrasar letra 0.5s',
                  icon: const Icon(Icons.fast_forward, color: Colors.grey),
                  onPressed: () => provider.adjustLyricOffset(50),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
