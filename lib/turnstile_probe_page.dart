import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'l10n.dart';

class TurnstileProbePage extends StatefulWidget {
  const TurnstileProbePage({super.key});

  @override
  State<TurnstileProbePage> createState() => _TurnstileProbePageState();
}

class _TurnstileProbePageState extends State<TurnstileProbePage> {
  static const _channel = MethodChannel('antiattendance/turnstile_probe');
  final List<Map<String, Object?>> _frames = [];
  String? _error;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler(_handleCall);
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'frames' || !mounted || call.arguments is! List) return;
    final frames = (call.arguments as List)
        .whereType<Map>()
        .map((frame) => frame.map((key, value) => MapEntry('$key', value)))
        .toList();
    setState(() {
      _frames.insertAll(0, frames.reversed);
      if (_frames.length > 80) _frames.removeRange(80, _frames.length);
    });
  }

  Future<void> _start() async {
    if (!mounted || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('start');
      if (mounted) {
        setState(() {
          _listening = true;
          _error = null;
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _listening = false;
          _error = error.code;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _listening = false;
          _error = 'OBSERVE_ERROR';
        });
      }
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

  String _message(BuildContext context) {
    if (!Platform.isAndroid) {
      return tr(
        context,
        'Доступно только на Android.',
        'Available on Android only.',
      );
    }
    return switch (_error) {
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
      'OBSERVE_UNAVAILABLE' => tr(
        context,
        'Нужен Android 15 или новее и поддержка режима наблюдения NFC.',
        'Requires Android 15 or newer and NFC Observe Mode support.',
      ),
      null when _frames.isNotEmpty => tr(
        context,
        'Сигнал считывателя обнаружен.',
        'Reader polling detected.',
      ),
      null when _listening => tr(
        context,
        'Поднесите заднюю панель телефона к считывателю турникета.',
        'Hold the back of your phone near the turnstile reader.',
      ),
      null => tr(context, 'Запускаем NFC…', 'Starting NFC…'),
      _ => tr(
        context,
        'Не удалось запустить режим наблюдения NFC.',
        'Could not start NFC Observe Mode.',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Сигнал турникета', 'Turnstile signal')),
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _frames.isEmpty
                          ? Icons.sensors_rounded
                          : Icons.check_circle_rounded,
                      color: AppColors.blue,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _message(context),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_listening && _frames.isEmpty) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                    ],
                    if (_error != null && Platform.isAndroid) ...[
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(tr(context, 'Повторить', 'Retry')),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                tr(
                  context,
                  'Телефон только слушает опрос NFC. Пропуск не передаётся, вход через турникет не выполняется. На старых Android этот режим недоступен.',
                  'The phone only observes NFC polling. It does not present a pass or open the gate. Older Android versions cannot use this mode.',
                ),
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              if (_frames.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr(context, 'Кадры опроса', 'Polling frames'),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: tr(context, 'Очистить', 'Clear'),
                      onPressed: () => setState(_frames.clear),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final frame in _frames)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${frame['type'] ?? '—'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if ('${frame['data'] ?? ''}'.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            SelectableText(
                              '${frame['data']}',
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                          ],
                          const SizedBox(height: 5),
                          Text(
                            't = ${frame['timestampUs']} µs  ·  gain = ${frame['gain']}',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
