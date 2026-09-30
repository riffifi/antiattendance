import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'accounts.dart';
import 'l10n.dart';
import 'session_transfer.dart';

class SessionImportPage extends StatefulWidget {
  const SessionImportPage({super.key});

  @override
  State<SessionImportPage> createState() => _SessionImportPageState();
}

class _SessionImportPageState extends State<SessionImportPage> {
  final _camera = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 400,
    formats: const [BarcodeFormat.qrCode],
  );
  final _collector = SessionTransferCollector();
  final _code = TextEditingController();
  List<SavedAccount>? _accounts;
  String? _error;
  bool _decrypting = false;

  @override
  void dispose() {
    _code.dispose();
    unawaited(_camera.dispose());
    super.dispose();
  }

  Future<void> _decrypt() async {
    if (_decrypting) return;
    setState(() {
      _decrypting = true;
      _error = null;
    });
    try {
      final accounts = await _collector.decrypt(_code.text);
      if (mounted) setState(() => _accounts = accounts);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(
            context,
            'Неверный код, повреждённые данные или срок передачи истёк.',
            'Wrong code, damaged data, or expired transfer.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _decrypting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, 'Импорт сессий', 'Import sessions')),
    ),
    body: _accounts != null
        ? _preview(context)
        : _collector.complete
        ? _codeEntry(context)
        : _scanner(context),
  );

  Widget _scanner(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      MobileScanner(
        controller: _camera,
        onDetect: (capture) {
          if (_collector.complete) return;
          var changed = false;
          for (final barcode in capture.barcodes) {
            final value = barcode.rawValue;
            if (value != null && _collector.accept(value)) changed = true;
          }
          if (changed && mounted) {
            setState(() {});
            if (_collector.complete) unawaited(_camera.stop());
          }
        },
        errorBuilder: (context, error) => Center(
          child: Text(
            tr(context, 'Камера недоступна', 'Camera unavailable'),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
      Center(
        child: Container(
          width: 250,
          height: 250,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 3),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: const Color(0xE6181B24),
            child: Text(
              _collector.total == 0
                  ? tr(
                      context,
                      'Наведите камеру на QR с другого телефона',
                      'Point the camera at the QR on the other phone',
                    )
                  : tr(
                      context,
                      'Получено ${_collector.received} из ${_collector.total} кадров. Держите камеру на экране.',
                      'Received ${_collector.received} of ${_collector.total} frames. Keep the camera pointed at the screen.',
                    ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _codeEntry(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            tr(context, 'QR получен', 'QR received'),
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              'Попросите отправителя открыть «Показать код» и введите его здесь.',
              'Ask the sender to tap “Show code” and enter it here.',
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _code,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: tr(context, 'Код передачи', 'Transfer code'),
            ),
            onSubmitted: (_) => _decrypt(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _decrypting ? null : _decrypt,
            child: Text(
              _decrypting
                  ? tr(context, 'Проверяем…', 'Checking…')
                  : tr(context, 'Продолжить', 'Continue'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _preview(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            tr(context, 'Импортировать аккаунты?', 'Import these accounts?'),
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              'Сессии будут сохранены на этом устройстве.',
              'Sessions will be saved on this device.',
            ),
          ),
          const SizedBox(height: 16),
          for (final account in _accounts!)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(account.label),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_accounts),
            child: Text(tr(context, 'Импортировать', 'Import')),
          ),
        ],
      ),
    ),
  );
}
