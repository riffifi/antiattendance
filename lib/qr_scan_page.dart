import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'pulse_api.dart';

class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  String? _error;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if (_handled) return;
            for (final barcode in capture.barcodes) {
              final value = barcode.rawValue;
              if (value != null && value.isNotEmpty) {
                try {
                  attendanceTokenFromQr(value);
                } on FormatException {
                  if (mounted) {
                    setState(() => _error = 'Это не QR-код занятия Пульса');
                  }
                  continue;
                }
                _handled = true;
                Navigator.of(context).pop(value);
                return;
              }
            }
          },
          errorBuilder: (context, error) => const Center(
            child: Text(
              'Камера недоступна',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Закрыть',
                  ),
                  const Expanded(
                    child: Text(
                      'Сканировать QR занятия',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                  IconButton(
                    onPressed: () => unawaited(_controller.toggleTorch()),
                    icon: const Icon(Icons.flashlight_on, color: Colors.white),
                    tooltip: 'Фонарик',
                  ),
                ],
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  _error ?? 'Наведите камеру на QR-код Пульса',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
