import 'dart:typed_data';
import 'package:flutter/material.dart';

class CoverView extends StatelessWidget {
  /// Read once per song by the provider (works for SAF and filesystem).
  final Uint8List? coverBytes;

  const CoverView({super.key, this.coverBytes});

  @override
  Widget build(BuildContext context) {
    final decodeWidth =
        (MediaQuery.sizeOf(context).shortestSide *
                MediaQuery.devicePixelRatioOf(context))
            .round();

    final Widget image = coverBytes != null
        ? Image.memory(
            coverBytes!,
            fit: BoxFit.contain,
            cacheWidth: decodeWidth,
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => _placeholderImage(),
          )
        : _placeholderImage();

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
    return Image.asset('assets/images/default_cover.png', fit: BoxFit.contain);
  }
}
