import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models.dart';

final class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  var _handled = false;
  var _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final payload = PairingPayload.tryParse(raw);
      if (payload == null) {
        _handled = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That QR code is not an AgentLink pairing code. '
              'Run agentlink-bridge on the PC and scan its QR code.',
            ),
          ),
        );
        Future<void>.delayed(const Duration(milliseconds: 1600), () {
          if (mounted) _handled = false;
        });
        return;
      }
      _handled = true;
      Navigator.of(context).pop(payload);
      return;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: const Text('Scan pairing QR'),
      actions: [
        IconButton(
          tooltip: 'Toggle flashlight',
          onPressed: () async {
            await _controller.toggleTorch();
            if (mounted) setState(() => _torch = !_torch);
          },
          icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
        ),
      ],
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => _CameraError(
            message: error.errorDetails?.message ?? error.errorCode.name,
          ),
        ),
        IgnorePointer(
          child: Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 48,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: const Text(
              'Open the terminal on your PC where agentlink-bridge is running '
              'and point the camera at the QR code.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ),
      ],
    ),
  );
}

final class _CameraError extends StatelessWidget {
  const _CameraError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, size: 52),
          const SizedBox(height: 16),
          Text(
            'The camera is not available.\n$message',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Grant camera permission in Android settings, or paste the '
            'pairing link from the desktop terminal instead.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
