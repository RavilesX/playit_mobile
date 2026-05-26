import 'dart:io';
import 'package:flutter/material.dart';
import '../models/song.dart';

class CoverView extends StatelessWidget {
  final Song? song;

  const CoverView({super.key, this.song});

  @override
  Widget build(BuildContext context) {
    Widget image;

    if (song != null) {
      final coverFile = File(song!.coverPath);
      if (coverFile.existsSync()) {
        image = Image.file(
          coverFile,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => _placeholderImage(),
        );
      } else {
        image = _placeholderImage();
      }
    } else {
      image = _placeholderImage();
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withValues(alpha: 0.75),
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }

  Widget _placeholderImage() {
    return Image.asset(
      'assets/images/default_cover.png',
      fit: BoxFit.contain,
    );
  }
}
