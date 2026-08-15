import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import '../constants/app_colors.dart';

/// CAVA-style bar spectrum behind the stem controls, reading the real mix
/// via SoLoud's FFT sampling (desktop's audio_visualizer.py reimplemented
/// the same idea in NumPy; here SoLoud does the FFT natively).
///
/// Must only be mounted while `PlayerProvider.spectrumEnabled` is true —
/// visualization sampling has a small always-on cost in the native engine,
/// so the caller is responsible for calling `AudioEngine.setVisualizationEnabled`
/// around this widget's lifetime.
class SpectrumVisualizer extends StatefulWidget {
  final int barCount;
  const SpectrumVisualizer({super.key, this.barCount = 20});

  @override
  State<SpectrumVisualizer> createState() => _SpectrumVisualizerState();
}

class _SpectrumVisualizerState extends State<SpectrumVisualizer>
    with SingleTickerProviderStateMixin {
  AudioData? _audioData;
  Ticker? _ticker;
  late List<double> _bars;
  double _peak = 1e-6;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _bars = List.filled(widget.barCount, 0.0);
    try {
      _audioData = AudioData(GetSamplesKind.linear);
      _ticker = createTicker(_onTick)..start();
    } catch (e) {
      // FFT sampling wasn't enabled yet, or the engine isn't ready —
      // fail quietly, the bars just stay flat.
      _failed = true;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _audioData?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final data = _audioData;
    if (data == null || !mounted) return;
    try {
      data.updateSamples();
      final samples = data.getAudioData(alwaysReturnData: false);
      if (samples.length < 256) return;
      _updateBars(samples);
    } catch (_) {
      // Ignore transient failures (e.g. visualization toggled off
      // mid-flight elsewhere) rather than tearing down the widget.
    }
  }

  void _updateBars(Float32List fft) {
    final n = widget.barCount;
    final raw = List<double>.generate(n, (i) {
      final start = _logIndex(i, n);
      final end = max(start + 1, _logIndex(i + 1, n));
      var sum = 0.0;
      for (var j = start; j < end; j++) {
        sum += fft[j].abs();
      }
      return sum / (end - start);
    });

    final frameMax = raw.reduce(max);
    // Auto-gain: track the running peak so bars fill the widget regardless
    // of the FFT's absolute scale, decaying slowly when the music quiets
    // down (same spirit as CAVA's auto-sensitivity).
    _peak = frameMax > _peak ? frameMax : _peak * 0.985;
    final normalized = _peak <= 0
        ? raw
        : raw.map((v) => (v / _peak).clamp(0.0, 1.0)).toList();

    setState(() {
      // Gravity: bars rise instantly, fall gradually.
      for (var i = 0; i < n; i++) {
        _bars[i] = max(normalized[i], _bars[i] * 0.82);
      }
    });
  }

  static int _logIndex(int i, int n) =>
      (pow(256, i / n) - 1).round().clamp(0, 255);

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(painter: _BarsPainter(_bars), size: Size.infinite),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<double> bars;
  _BarsPainter(this.bars);

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty || size.width <= 0 || size.height <= 0) return;
    final barWidth = size.width / bars.length;
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [AppColors.accentPurple, AppColors.accentBlue],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    for (var i = 0; i < bars.length; i++) {
      final h = (bars[i] * size.height).clamp(1.0, size.height);
      final rect = Rect.fromLTWH(
        i * barWidth + barWidth * 0.15,
        size.height - h,
        barWidth * 0.7,
        h,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter oldDelegate) => true;
}
