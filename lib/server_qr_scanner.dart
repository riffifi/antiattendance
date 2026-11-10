import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'campus_design.dart';
import 'l10n.dart';
import 'pulse_api.dart';

class ServerQrScanner extends StatefulWidget {
  const ServerQrScanner({super.key});
  @override
  State<ServerQrScanner> createState() => _ServerQrScannerState();
}

class _ServerQrScannerState extends State<ServerQrScanner> {
  final _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _finished = false;
  String? _error;
  @override
  void dispose() {
    unawaited(_camera.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CampusScaffold(
    appBar: CampusAppBar(title: Text(tr(context, 'Сканировать QR', 'Scan QR'))),
    body: Stack(
      children: [
        MobileScanner(
          controller: _camera,
          onDetect: (capture) {
            if (_finished) return;
            for (final code in capture.barcodes) {
              final raw = code.rawValue;
              if (raw == null) continue;
              try {
                attendanceTokenFromQr(raw);
              } on FormatException {
                setState(
                  () => _error = tr(
                    context,
                    'Нужен QR-код посещаемости.',
                    'Scan an attendance QR code.',
                  ),
                );
                continue;
              }
              _finished = true;
              Navigator.of(context).pop(raw);
              return;
            }
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                tr(
                  context,
                  'Камера недоступна. Вернитесь и вставьте ссылку.',
                  'Camera unavailable. Go back and paste the link.',
                ),
              ),
            ),
          ),
        ),
        if (_error != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: ColoredBox(
              color: Colors.black87,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
