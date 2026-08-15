import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../constants/app_colors.dart';
import '../models/remote_state.dart';

/// Reads the pairing QR that PlayIt Desktop shows (Opciones → Modo remoto).
///
/// Pops with the [PairingInfo] it read, or null if the user backed out. The
/// camera is only ever opened from here, and the remote works without it —
/// see [RemotePairForm] for the manual path.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  static Future<PairingInfo?> open(BuildContext context) =>
      Navigator.of(context).push<PairingInfo>(
        MaterialPageRoute(builder: (_) => const QrScanScreen()),
      );

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    // Only QR: skipping the other formats keeps the detector from chewing on
    // barcodes we could never use.
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// The camera keeps delivering frames after a hit; without this the same QR
  /// pops the route several times.
  bool _handled = false;

  /// Last complaint about a code that isn't ours, shown under the viewfinder.
  /// Held as state instead of a snackbar so pointing at the wrong QR doesn't
  /// stack twenty toasts.
  String? _message;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final PairingInfo info;
    try {
      info = pairingFromBarcodes(capture.barcodes.map((b) => b.rawValue));
    } on RemotePairingException catch (e) {
      if (e.message != _message && mounted) {
        setState(() => _message = e.message);
      }
      return;
    }

    _handled = true;
    _controller.stop();
    Navigator.of(context).pop(info);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Escanear código', style: TextStyle(fontSize: 16)),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (ctx, state, _) {
              if (state.torchState == TorchState.unavailable) {
                return const SizedBox.shrink();
              }
              final on = state.torchState == TorchState.on;
              return IconButton(
                icon: Icon(on ? Icons.flash_on : Icons.flash_off),
                color: on ? AppColors.accentBlue : Colors.white,
                tooltip: 'Linterna',
                onPressed: _controller.toggleTorch,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final size = constraints.biggest;
                final side = size.shortestSide * 0.7;
                final window = Rect.fromCenter(
                  center: size.center(Offset.zero),
                  width: side,
                  height: side,
                );
                return MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  scanWindow: window,
                  errorBuilder: (ctx, error) => _ScannerError(error: error),
                  overlayBuilder: (ctx, _) => _Viewfinder(side: side),
                );
              },
            ),
          ),
          _Footer(message: _message),
        ],
      ),
    );
  }
}

class _Viewfinder extends StatelessWidget {
  final double side;
  const _Viewfinder({required this.side});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: side,
          height: side,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.accentPurple, width: 3),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final String? message;
  const _Footer({required this.message});

  @override
  Widget build(BuildContext context) {
    final bad = message != null;
    return Container(
      width: double.infinity,
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Text(
        message ?? 'Apuntá al código QR que muestra PlayIt en la PC.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: bad ? AppColors.pinkText : Colors.grey,
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }
}

/// Camera unavailable. Denying the permission is a supported outcome, not a
/// dead end: the message sends the user back to typing the code by hand.
class _ScannerError extends StatelessWidget {
  final MobileScannerException error;
  const _ScannerError({required this.error});

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final unsupported = error.errorCode == MobileScannerErrorCode.unsupported;

    final text = denied
        ? 'Sin permiso de cámara no se puede leer el QR. Podés volver y '
              'escribir la dirección y el código a mano.'
        : unsupported
        ? 'Este dispositivo no puede escanear códigos. Volvé y escribí los '
              'datos a mano.'
        : 'No se pudo abrir la cámara. Volvé y escribí los datos a mano.';

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                denied ? Icons.no_photography : Icons.videocam_off,
                color: AppColors.border,
                size: 56,
              ),
              const SizedBox(height: 20),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accentBlue,
                  side: const BorderSide(color: AppColors.accentPurple),
                ),
                icon: const Icon(Icons.keyboard),
                label: const Text('Escribir a mano'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
