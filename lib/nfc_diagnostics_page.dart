import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'l10n.dart';

class NfcDiagnosticsPage extends StatefulWidget {
  const NfcDiagnosticsPage({super.key});

  @override
  State<NfcDiagnosticsPage> createState() => _NfcDiagnosticsPageState();
}

class _NfcDiagnosticsPageState extends State<NfcDiagnosticsPage> {
  static const _channel = MethodChannel('antiattendance/nfc_diagnostics');

  String? _errorCode;
  Map<String, Object?>? _tag;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler(_handleNativeCall);
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'tagDetected' || !mounted) return;
    final raw = call.arguments;
    if (raw is! Map) return;
    setState(() {
      _tag = raw.map((key, value) => MapEntry('$key', value));
      _errorCode = null;
    });
  }

  Future<void> _start() async {
    if (!mounted) return;
    try {
      await _channel.invokeMethod<void>('start');
      if (mounted) setState(() => _scanning = true);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _errorCode = error.code);
    } catch (_) {
      if (mounted) setState(() => _errorCode = 'NFC_ERROR');
    }
  }

  @override
  void dispose() {
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler(null);
      unawaited(_channel.invokeMethod<void>('stop').catchError((_) {}));
    }
    super.dispose();
  }

  String _status(BuildContext context) {
    if (!Platform.isAndroid) {
      return tr(
        context,
        'Доступно только на Android.',
        'Available on Android only.',
      );
    }
    return switch (_errorCode) {
      'NFC_UNAVAILABLE' => tr(
        context,
        'На этом телефоне нет NFC.',
        'This phone has no NFC reader.',
      ),
      'NFC_DISABLED' => tr(
        context,
        'Включите NFC в настройках телефона и откройте экран снова.',
        'Turn on NFC in phone settings, then reopen this screen.',
      ),
      null when _tag != null => tr(
        context,
        'Устройство NFC обнаружено.',
        'NFC device detected.',
      ),
      null when _scanning => tr(
        context,
        'Поднесите телефон с открытым пропуском к задней панели этого телефона.',
        'Hold the phone with its pass open against the back of this phone.',
      ),
      null => tr(context, 'Запускаем NFC…', 'Starting NFC…'),
      _ => tr(context, 'Не удалось запустить NFC.', 'Could not start NFC.'),
    };
  }

  Widget _detail(String label, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Text(label, style: TextStyle(color: context.palette.muted)),
        ),
        Expanded(
          flex: 4,
          child: SelectableText('$value', textAlign: TextAlign.end),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tag = _tag;
    final technologies = (tag?['technologies'] as List?)?.join(', ') ?? '—';
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Проверка NFC', 'NFC diagnostics')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: context.palette.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      tag == null
                          ? Icons.nfc_rounded
                          : Icons.check_circle_rounded,
                      color: context.palette.blue,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _status(context),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_scanning && tag == null) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
              if (tag != null) ...[
                const SizedBox(height: 20),
                Text(
                  tr(context, 'Что увидел телефон', 'What this phone detected'),
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.palette.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _detail(
                        tr(context, 'Технологии', 'Technologies'),
                        technologies,
                      ),
                      if (tag['atqa'] != null)
                        _detail('NFC-A ATQA', tag['atqa']),
                      if (tag['sak'] != null) _detail('NFC-A SAK', tag['sak']),
                      if (tag['maxTransceiveLength'] != null) ...[
                        _detail(
                          'ISO-DEP max bytes',
                          tag['maxTransceiveLength'],
                        ),
                        _detail(
                          'ISO-DEP historical bytes',
                          tag['historicalBytesLength'],
                        ),
                        _detail(
                          'ISO-DEP higher layer bytes',
                          tag['hiLayerResponseLength'],
                        ),
                        _detail(
                          'Extended APDU',
                          tag['extendedApduSupported'] == true
                              ? tr(context, 'Да', 'Yes')
                              : tr(context, 'Нет', 'No'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                tr(
                  context,
                  'Это технические сведения о NFC-соединении. Они не подтверждают, что обнаружен именно Пульс; данные пропуска не считываются и не сохраняются.',
                  'These are NFC connection details. They do not confirm that the device is Pulse; pass data is neither read nor saved.',
                ),
                style: TextStyle(color: context.palette.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
