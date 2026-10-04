import 'campus_design.dart';

import 'package:material_3_expressive/material_3_expressive.dart';

import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
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
  bool _fieldOnly = false;
  bool _fieldDetected = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler(_handleCall);
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  Future<void> _handleCall(MethodCall call) async {
    if (!mounted) return;
    if (call.method == 'modeChanged') {
      setState(() {
        _fieldOnly = call.arguments == 'field';
        _fieldDetected = false;
      });
      return;
    }
    if (call.method == 'fieldChanged' && call.arguments is Map) {
      final event = call.arguments as Map;
      final detected = event['detected'] == true;
      setState(() {
        _fieldDetected = detected;
        _frames.insert(0, {
          'type': detected ? 'Field on' : 'Field off',
          'timestampUs': event['timestampUs'],
        });
        if (_frames.length > 80) _frames.removeRange(80, _frames.length);
      });
      return;
    }
    if (call.method != 'frames' || call.arguments is! List) return;
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
    setState(() => _fieldDetected = false);
    try {
      final mode = await _channel.invokeMethod<String>('start');
      if (mounted) {
        setState(() {
          _listening = true;
          _fieldOnly = mode == 'field';
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
      'OBSERVE_DISABLED_BY_SYSTEM' => tr(
        context,
        'NFC работает, но Android не разрешает включить режим наблюдения на этом устройстве.',
        'NFC works, but Android does not allow Observe Mode on this device.',
      ),
      'OBSERVE_PREFERENCE_FAILED' => tr(
        context,
        'Android не удалось выбрать сервис проверки NFC. Закройте экран и попробуйте снова.',
        'Android could not select the NFC diagnostic service. Reopen this screen and try again.',
      ),
      null when _fieldOnly && _fieldDetected => tr(
        context,
        'Поле NFC-считывателя обнаружено.',
        'NFC reader field detected.',
      ),
      null when _fieldOnly => tr(
        context,
        'Слушаем поле NFC-считывателя. Кадры опроса недоступны.',
        'Listening for an NFC reader field. Polling frames are unavailable.',
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
        automaticallyImplyLeading: true,
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
                      _frames.isEmpty
                          ? Icons.sensors_rounded
                          : Icons.check_circle_rounded,
                      color: context.palette.blue,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _message(context),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_listening && _frames.isEmpty) ...[
                      const SizedBox(height: 16),
                      const M3EProgressIndicator.linearWavy(),
                    ],
                    if (_error != null && Platform.isAndroid) ...[
                      const SizedBox(height: 12),
                      CampusButton.icon(
                        onPressed: _start,
                        icon: Icon(Icons.refresh_rounded),
                        label: Text(tr(context, 'Повторить', 'Retry')),
                        style: M3EButtonStyle.text,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _error != null
                    ? tr(
                        context,
                        'Этот экран не передаёт пропуск и не открывает турникет.',
                        'This screen does not present a pass or open the gate.',
                      )
                    : _fieldOnly
                    ? tr(
                        context,
                        'Android не предоставляет режим наблюдения на этом телефоне. Показываем только появление поля NFC-считывателя: его команды и данные пропуска недоступны.',
                        'Android reports Observe Mode unavailable on this phone. Only reader field detection is available; polling commands and pass data are not captured.',
                      )
                    : tr(
                        context,
                        'Телефон только слушает опрос NFC. Пропуск не передаётся, вход через турникет не выполняется. На старых Android этот режим недоступен.',
                        'The phone only observes NFC polling. It does not present a pass or open the gate. Older Android versions cannot use this mode.',
                      ),
                style: TextStyle(color: context.palette.muted, fontSize: 13),
              ),
              if (_frames.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _fieldOnly
                            ? tr(context, 'События поля', 'Field events')
                            : tr(context, 'Кадры опроса', 'Polling frames'),
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    M3EIconButton(
                      suppressInk: true,
                      tooltip: tr(context, 'Очистить', 'Clear'),
                      onPressed: () => setState(_frames.clear),
                      icon: Icon(Icons.delete_outline_rounded),
                      variant: M3EIconButtonVariant.standard,
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
                        color: context.palette.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(switch (frame['type']) {
                            'Field on' => tr(
                              context,
                              'Поле появилось',
                              'Field on',
                            ),
                            'Field off' => tr(
                              context,
                              'Поле исчезло',
                              'Field off',
                            ),
                            _ => '${frame['type'] ?? '—'}',
                          }, style: TextStyle(fontWeight: FontWeight.w700)),
                          if ('${frame['data'] ?? ''}'.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            SelectableText(
                              '${frame['data']}',
                              style: TextStyle(fontFamily: 'monospace'),
                            ),
                          ],
                          const SizedBox(height: 5),
                          Text(
                            _fieldOnly
                                ? trf(
                                    context,
                                    'Время: {time} мкс',
                                    'Time: {time} µs',
                                    {'time': frame['timestampUs'] ?? '—'},
                                  )
                                : trf(
                                    context,
                                    'Время: {time} мкс · усиление: {gain}',
                                    'Time: {time} µs · gain: {gain}',
                                    {
                                      'time': frame['timestampUs'] ?? '—',
                                      'gain': frame['gain'] ?? '—',
                                    },
                                  ),
                            style: TextStyle(
                              color: context.palette.muted,
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
