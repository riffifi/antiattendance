import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'accounts.dart';
import 'l10n.dart';
import 'session_transfer.dart';

class SessionSharePage extends StatefulWidget {
  const SessionSharePage({super.key, required this.accounts});
  final List<SavedAccount> accounts;

  @override
  State<SessionSharePage> createState() => _SessionSharePageState();
}

class _SessionSharePageState extends State<SessionSharePage> {
  SessionTransfer? _transfer;
  String? _error;
  Timer? _timer;
  int _frame = 0;
  bool _showCode = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final transfer = await createSessionTransfer(widget.accounts);
      if (!mounted) return;
      setState(() => _transfer = transfer);
      _timer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
        if (mounted && !_showCode) {
          setState(() => _frame = (_frame + 1) % transfer.frames.length);
        }
      });
    } on FormatException {
      if (mounted) setState(() => _error = 'too_many');
    } catch (_) {
      if (mounted) setState(() => _error = 'transfer_failed');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transfer = _transfer;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Передать сессии', 'Share sessions')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _error != null
                ? Text(
                    tr(
                      context,
                      _error == 'too_many'
                          ? 'Слишком много данных для QR. Используйте передачу рядом.'
                          : 'Не удалось создать QR-передачу.',
                      _error == 'too_many'
                          ? 'Too much data for QR. Use nearby transfer.'
                          : 'Could not create the QR transfer.',
                    ),
                  )
                : transfer == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _showCode
                            ? tr(context, 'Код передачи', 'Transfer code')
                            : tr(
                                context,
                                'Сканируйте все QR-кадры',
                                'Scan all QR frames',
                              ),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _showCode
                            ? tr(
                                context,
                                'Введите этот код на другом телефоне после сканирования.',
                                'Enter this code on the other phone after scanning.',
                              )
                            : tr(
                                context,
                                'Откройте «Импорт сессий» на другом телефоне и держите камеру на экране.',
                                'Open “Import sessions” on the other phone and keep its camera pointed here.',
                              ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (_showCode)
                        SelectableText(
                          transfer.code
                              .replaceAllMapped(
                                RegExp(r'.{4}'),
                                (m) => '${m.group(0)} ',
                              )
                              .trim(),
                          style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                          textAlign: TextAlign.center,
                        )
                      else ...[
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(12),
                          child: QrImageView(
                            data: transfer.frames[_frame],
                            version: QrVersions.auto,
                            errorCorrectionLevel: QrErrorCorrectLevel.L,
                            size: 290,
                            backgroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('${_frame + 1} / ${transfer.frames.length}'),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () =>
                              setState(() => _showCode = !_showCode),
                          child: Text(
                            _showCode
                                ? tr(context, 'Показать QR', 'Show QR')
                                : tr(context, 'Показать код', 'Show code'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr(
                          context,
                          'Сессии дают доступ к аккаунтам. Передавайте QR и код только доверенному человеку.',
                          'Sessions grant account access. Share the QR and code only with someone you trust.',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
