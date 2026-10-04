import 'campus_design.dart';
import 'expressive.dart';

import 'package:material_3_expressive/material_3_expressive.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:nfc_pass_client/nfc_pass_client.dart';

import 'accounts.dart';
import 'app_theme.dart';
import 'l10n.dart';
import 'nfc_pass.dart';

class NfcPassPage extends StatefulWidget {
  const NfcPassPage({
    super.key,
    required this.accounts,
    this.startOnOpen = false,
  });
  final List<SavedAccount> accounts;
  final bool startOnOpen;

  @override
  State<NfcPassPage> createState() => NfcPassPageState();
}

class NfcPassPageState extends State<NfcPassPage> with WidgetsBindingObserver {
  final _store = NfcPassStore();
  final _numbers = <String, String>{};
  final _selected = <String>{};
  final _seconds = TextEditingController(text: '60');
  final _search = TextEditingController();
  String _query = '';
  bool _nfcDisabled = false;
  bool _widgetStartPending = false;
  String? _ownId;
  String? _message;
  bool _busy = true;
  bool _running = false;
  bool _polling = false;
  int _runEpoch = 0;
  int _viewEpoch = 0;
  Map<String, dynamic> _status = {};
  List<SavedAccount> _queue = [];
  Timer? _timer;
  Timer? _preferencesTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    final viewEpoch = _viewEpoch;
    try {
      final settings = await _store.settings();
      final numbers = <String, String>{};
      for (final account in widget.accounts) {
        final number = await _store.number(account);
        if (number != null) numbers[account.id] = number;
      }
      if (!mounted) return;
      setState(() {
        _numbers.addAll(numbers);
        final savedSelection = settings['selectedIds'];
        _selected.addAll(
          savedSelection is List
              ? numbers.keys.where(savedSelection.contains)
              : numbers.keys,
        );
        final seconds = settings['seconds'];
        if (seconds is int && seconds >= 1 && seconds <= 300) {
          _seconds.text = '$seconds';
        }
        final ownId = settings['ownAccountId'];
        if (widget.accounts.any((a) => a.id == ownId)) _ownId = ownId as String;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = tr(
            context,
            'Не удалось загрузить пропуска.',
            'Could not load passes.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted &&
        viewEpoch == _viewEpoch &&
        (widget.startOnOpen || _widgetStartPending)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && viewEpoch == _viewEpoch) unawaited(startFromWidget());
      });
    }
  }

  Future<void> startFromWidget() async {
    if (!mounted || _running) return;
    if (_busy) {
      _widgetStartPending = true;
      return;
    }
    _widgetStartPending = false;
    if (_selected.isEmpty) {
      setState(
        () => _message = tr(
          context,
          'Подключите и выберите пропуска перед запуском виджета.',
          'Enroll and select passes before using the widget.',
        ),
      );
      return;
    }
    await _start();
  }

  String _formatTime(DateTime date) {
    final local = date.toLocal();
    final localization = MaterialLocalizations.of(context);
    return '${localization.formatMediumDate(local)}, ${localization.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
  }

  Future<void> _addWidget() async {
    final compact = await showExpressiveSheet<bool>(
      context: context,
      compact: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CampusListItem(
                leading: const Icon(Icons.nfc_rounded),
                headline: (tr(context, 'Компактный · 1×1', 'Compact · 1×1')),
                supportingText: (tr(context, 'Только значок', 'Icon only')),
                onTap: () => Navigator.pop(context, true),
              ),
              CampusListItem(
                leading: const Icon(Icons.widgets_outlined),
                headline: (tr(context, 'С подписью · 2×1', 'Labeled · 2×1')),
                supportingText: (tr(
                  context,
                  'Значок и название',
                  'Icon and title',
                )),
                onTap: () => Navigator.pop(context, false),
              ),
            ],
          ),
        ),
      ),
    );
    if (compact == null || !mounted) return;
    try {
      final supported = await nfcPassChannel.invokeMethod<bool>(
        'pinNfcWidget',
        {'compact': compact},
      );
      if (supported != true && mounted) {
        setState(
          () => _message = tr(
            context,
            'Добавьте виджет через меню виджетов на главном экране.',
            'Add the widget from your home screen’s widget picker.',
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    }
  }

  String _error(Object error) {
    if (error is PlatformException) {
      if (error.code == 'NFC_DISABLED') {
        return tr(
          context,
          'Включите NFC в настройках телефона.',
          'Turn on NFC in phone settings.',
        );
      }
      if (error.code == 'NFC_UNAVAILABLE' ||
          error.code == 'NFC_HCE_UNAVAILABLE') {
        return tr(
          context,
          'Этот телефон не поддерживает NFC-пропуска.',
          'This phone does not support NFC passes.',
        );
      }
      return tr(
        context,
        'Не удалось запустить NFC. Закройте проверку NFC и повторите.',
        'Could not start NFC. Close NFC diagnostics and retry.',
      );
    }
    if (error is NfcVerificationException) {
      return tr(
        context,
        'Неверный код или ошибка выдачи пропуска.',
        'Incorrect code or pass issuance failed.',
      );
    }
    if (error is NfcPassTransportException) {
      return tr(
        context,
        'Ошибка сервиса пропусков. Проверьте вход в аккаунт и повторите.',
        'Pass service failed. Check your account sign-in and retry.',
      );
    }
    return tr(
      context,
      'Не удалось выполнить операцию с пропуском.',
      'Could not complete the pass operation.',
    );
  }

  Future<void> _enroll(SavedAccount account) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final epoch = _viewEpoch;
    final client = passClient(account);
    try {
      final token = await client.getAccessTokenForDigitalPass();
      passTokenExpiry(token);
      if (!mounted || epoch != _viewEpoch) return;
      final result = await client.sendVerificationCode(token);
      if (!mounted || epoch != _viewEpoch) return;
      if (result is NfcVerificationUnavailable) {
        setState(
          () => _message = tr(
            context,
            'Для этого аккаунта нет доступного пропуска или способа подтверждения.',
            'No pass or verification method is available for this account.',
          ),
        );
        return;
      }
      if (result is NfcVerificationCooldown) {
        setState(
          () => _message =
              '${tr(context, 'Повторная отправка кода доступна:', 'You can request another code at:')} ${_formatTime(result.retryAt)}',
        );
      }
      final code = await showExpressiveDialog<String>(
        context: context,
        builder: (context) => _VerificationDialog(label: account.label),
      );
      if (code == null || !mounted || epoch != _viewEpoch) return;
      final number = await client.getDigitalPass(
        bearerToken: token,
        sixDigitCode: code,
        deviceName: 'AntiAttendance Android NFC test',
      );
      await _store.save(account, number);
      if (mounted) {
        setState(() {
          _numbers[account.id] = number.toString();
          _selected.add(account.id);
        });
      }
      if (mounted) unawaited(_savePreferences());
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      client.httpClient.close();
      if (mounted) setState(() => _busy = false);
      if (mounted && epoch == _viewEpoch && _widgetStartPending) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && epoch == _viewEpoch) unawaited(startFromWidget());
        });
      }
    }
  }

  Future<void> _start() async {
    if (_ownId != null && !_selected.contains(_ownId)) {
      setState(
        () => _message = tr(
          context,
          'Подключите и выберите свой пропуск, чтобы предъявить его последним.',
          'Enroll and select your own pass to present it last.',
        ),
      );
      return;
    }
    final seconds = int.tryParse(_seconds.text);
    if (seconds == null || seconds < 1 || seconds > 300) {
      setState(
        () => _message = tr(
          context,
          'Укажите задержку от 1 до 300 секунд.',
          'Enter a delay from 1 to 300 seconds.',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _nfcDisabled = false;
    });
    final epoch = ++_runEpoch;
    try {
      _queue = orderPassQueue(
        widget.accounts.where((a) => _selected.contains(a.id)).toList(),
        _ownId,
      );
      final passes = <Map<String, Object>>[];
      for (final account in _queue) {
        final client = passClient(account);
        try {
          final token = await client.getAccessTokenForDigitalPass();
          passes.add({
            'accountId': account.id,
            'number': _numbers[account.id]!,
            'expiresAt': passTokenExpiry(token).millisecondsSinceEpoch,
          });
        } finally {
          client.httpClient.close();
        }
        if (!mounted || epoch != _runEpoch) return;
      }
      await _store.saveSettings(seconds, _ownId, _selected);
      if (!mounted || epoch != _runEpoch) return;
      final status = await nfcPassChannel.invokeMapMethod<String, dynamic>(
        'start',
        {'passes': passes, 'intervalSeconds': seconds},
      );
      if (!mounted || epoch != _runEpoch) {
        await nfcPassChannel.invokeMethod<void>('stop');
        return;
      }
      setState(() {
        _running = true;
        _status = status ?? {};
      });
      _timer = Timer.periodic(
        const Duration(milliseconds: 300),
        (_) => unawaited(_poll()),
      );
    } catch (error) {
      _nfcDisabled = error is PlatformException && error.code == 'NFC_DISABLED';
      if (mounted) setState(() => _message = _error(error));
    } finally {
      _widgetStartPending = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _poll() async {
    if (_polling || !_running) return;
    _polling = true;
    try {
      final status =
          await nfcPassChannel.invokeMapMethod<String, dynamic>('status') ?? {};
      if (!mounted || !_running) return;
      setState(() => _status = status);
      if (status['armed'] != true || status['expired'] == true) {
        final complete =
            status['total'] == _queue.length &&
            status['presented'] == _queue.length;
        await _stop();
        if (mounted) {
          setState(
            () => _message = complete
                ? tr(
                    context,
                    'Очередь предъявлена. Проверяйте результат на турникете.',
                    'Queue presented. Check the result at the gate.',
                  )
                : tr(
                    context,
                    'Очередь остановлена. Запустите снова для продолжения.',
                    'Queue stopped. Start again to continue.',
                  ),
          );
        }
      }
    } catch (error) {
      await _stop();
      if (mounted) setState(() => _message = _error(error));
    } finally {
      _polling = false;
    }
  }

  Future<void> _savePreferences() async {
    final seconds = int.tryParse(_seconds.text);
    if (seconds == null || seconds < 1 || seconds > 300) return;
    try {
      await _store.saveSettings(seconds, _ownId, _selected);
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    }
  }

  Future<void> deactivateQueue() async {
    _runEpoch++;
    _viewEpoch++;
    _widgetStartPending = false;
    await _stop();
  }

  Future<void> _stop() async {
    _timer?.cancel();
    if (mounted) setState(() => _running = false);
    try {
      await nfcPassChannel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _runEpoch++;
      if (_running) unawaited(_stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if ((defaultTargetPlatform == TargetPlatform.android)) {
      unawaited(nfcPassChannel.invokeMethod<void>('stop').catchError((_) {}));
    }
    _preferencesTimer?.cancel();
    if (!_busy) unawaited(_savePreferences());
    _seconds.dispose();
    _search.dispose();
    super.dispose();
  }

  Widget _card({required Widget child, Color? color}) =>
      CampusPanel(color: color, child: child);

  void _toggle(SavedAccount account) {
    setState(() {
      if (!_selected.add(account.id)) _selected.remove(account.id);
    });
    unawaited(_savePreferences());
  }

  Future<void> _removePass(SavedAccount account) async {
    try {
      await _store.remove(account.id);
      if (mounted) {
        setState(() {
          _numbers.remove(account.id);
          _selected.remove(account.id);
        });
      }
      if (mounted) unawaited(_savePreferences());
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    }
  }

  Widget _accountCard(SavedAccount account, bool enabled) {
    final enrolled = _numbers.containsKey(account.id);
    final selected = _selected.contains(account.id);
    final own = account.id == _ownId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CampusPressable(
        enabled: enabled && enrolled,
        child: Material(
          animationDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 140),
          color: selected ? context.palette.selected : context.palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: selected
                  ? context.palette.blue.withValues(alpha: .45)
                  : context.palette.line,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled && enrolled ? () => _toggle(account) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
              child: Row(
                children: [
                  if (enrolled)
                    M3ECheckbox(
                      value: selected,
                      onChanged: enabled ? (_) => _toggle(account) : null,
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        Icons.badge_outlined,
                        color: context.palette.muted,
                      ),
                    ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.label,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          own
                              ? tr(
                                  context,
                                  'Ваш пропуск · последним',
                                  'Your pass · last in queue',
                                )
                              : enrolled
                              ? tr(
                                  context,
                                  'Пропуск подключён',
                                  'Pass enrolled',
                                )
                              : tr(
                                  context,
                                  'Подключите пропуск',
                                  'Enroll a pass',
                                ),
                          style: TextStyle(
                            fontSize: 12,
                            color: own
                                ? context.palette.blue
                                : context.palette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (enrolled)
                    M3EIconButton(
                      suppressInk: true,
                      tooltip: tr(context, 'Удалить пропуск', 'Remove pass'),
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: context.palette.muted,
                      ),
                      onPressed: enabled ? () => _passMenu(account) : null,
                      variant: M3EIconButtonVariant.standard,
                    )
                  else
                    CampusButton.text(
                      onPressed: enabled ? () => _enroll(account) : null,
                      child: Text(tr(context, 'Подключить', 'Enroll')),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _passMenu(SavedAccount account) async {
    final remove = await showExpressiveSheet<bool>(
      context: context,
      compact: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          child: CampusListItem(
            leading: const Icon(Icons.delete_outline_rounded),
            headline: (tr(context, 'Удалить пропуск', 'Remove pass')),
            supportingText: (account.label),
            onTap: () => Navigator.pop(context, true),
          ),
        ),
      ),
    );
    if (remove == true && mounted) await _removePass(account);
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        !_busy &&
        !_running &&
        (defaultTargetPlatform == TargetPlatform.android);
    final current = _queue
        .where((a) => a.id == _status['accountId'])
        .firstOrNull;
    final presented = (_status['presented'] as num? ?? 0).toInt();
    final remaining = ((_status['remainingMillis'] as num? ?? 0) / 1000).ceil();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            children: [
              CampusHeader(
                title: tr(context, 'NFC-пропуска', 'NFC passes'),
                subtitle: tr(
                  context,
                  'Все пропуска. Одна очередь. Ваш — последним.',
                  'One queue for your passes. Yours goes last.',
                ),
                icon: Icons.nfc_rounded,
              ),
              _card(
                color: context.palette.selected,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: context.palette.blue.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.nfc_rounded,
                            color: scheme.onPrimaryContainer,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _running
                                ? tr(
                                    context,
                                    'Очередь работает',
                                    'Queue is running',
                                  )
                                : _numbers.isEmpty
                                ? tr(
                                    context,
                                    'Подключите первый пропуск',
                                    'Enroll your first pass',
                                  )
                                : tr(
                                    context,
                                    'Готовы к проходу',
                                    'Ready for the gate',
                                  ),
                            style: TextStyle(
                              color: scheme.onPrimaryContainer,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _running
                          ? current?.label ?? '—'
                          : _selected.length == 1
                          ? tr(context, 'Выбран 1 пропуск', '1 pass selected')
                          : trf(
                              context,
                              'Выбрано пропусков: {count}',
                              '{count} passes selected',
                              {'count': _selected.length},
                            ),
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _running
                          ? _status['responded'] == true
                                ? trf(
                                    context,
                                    'Следующий через {seconds} с',
                                    'Next pass in {seconds}s',
                                    {'seconds': remaining},
                                  )
                                : tr(
                                    context,
                                    'Поднесите телефон к турникету',
                                    'Hold your phone against the gate',
                                  )
                          : tr(
                              context,
                              'Выберите людей ниже и запустите очередь.',
                              'Choose people below, then start the queue.',
                            ),
                      style: TextStyle(
                        color: scheme.onPrimaryContainer.withValues(alpha: .8),
                        fontSize: 13,
                      ),
                    ),
                    if (_running) ...[
                      const SizedBox(height: 16),
                      M3EProgressIndicator.linearWavy(
                        value: _queue.isEmpty ? 0 : presented / _queue.length,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        trf(
                          context,
                          'Предъявлено: {count} из {total}',
                          'Presented: {count} of {total}',
                          {'count': presented, 'total': _queue.length},
                        ),
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, 'Настройка очереди', 'Queue settings'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          color: context.palette.muted,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr(
                                  context,
                                  'Между пропусками',
                                  'Between passes',
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tr(
                                  context,
                                  'От 1 до 300 секунд',
                                  'From 1 to 300 seconds',
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.palette.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 86,
                          child: CampusTextField(
                            controller: _seconds,
                            enabled: enabled,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            suffixText: tr(context, 'с', 's'),
                            onChanged: (_) {
                              _preferencesTimer?.cancel();
                              _preferencesTimer = Timer(
                                const Duration(milliseconds: 400),
                                () => unawaited(_savePreferences()),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Divider(height: 1, color: context.palette.line),
                    ),
                    AppPassPicker(
                      key: ValueKey(_ownId),
                      enabled: enabled,
                      hint: tr(context, 'Ваш аккаунт', 'Your account'),
                      items: [
                        M3EDropdownItem(
                          value: '',
                          label: tr(context, 'Не выбран', 'Not selected'),
                          selected: _ownId == null,
                        ),
                        for (final account in widget.accounts)
                          M3EDropdownItem(
                            value: account.id,
                            label: account.label,
                            selected: account.id == _ownId,
                          ),
                      ],
                      onChanged: (items) {
                        final value = items.isEmpty ? '' : items.first.value;
                        setState(() {
                          _ownId = value == '' ? null : value;
                          if (_numbers.containsKey(_ownId)) {
                            _selected.add(_ownId!);
                          }
                        });
                        unawaited(_savePreferences());
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        context,
                        'Ваш пропуск автоматически окажется в конце.',
                        'Your pass is automatically placed last.',
                      ),
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(context, 'Пропуска', 'Passes'),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_numbers.isNotEmpty)
                    CampusButton.text(
                      onPressed: enabled
                          ? () {
                              setState(() {
                                if (_selected.length == _numbers.length) {
                                  _selected.clear();
                                } else {
                                  _selected
                                    ..clear()
                                    ..addAll(_numbers.keys);
                                }
                              });
                              unawaited(_savePreferences());
                            }
                          : null,
                      child: Text(
                        _selected.length == _numbers.length
                            ? tr(context, 'Снять выбор', 'Clear selection')
                            : tr(context, 'Выбрать все', 'Select all'),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (widget.accounts.isEmpty)
                _card(
                  child: Column(
                    children: [
                      Icon(
                        Icons.badge_outlined,
                        color: context.palette.muted,
                        size: 36,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr(
                          context,
                          'Сначала добавьте аккаунты на вкладке посещаемости.',
                          'Add accounts on the Attendance tab first.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              if (widget.accounts.length > 5) ...[
                CampusTextField(
                  controller: _search,
                  label: tr(context, 'Найти пропуск', 'Search passes'),
                  leading: const Icon(Icons.search_rounded),
                  trailing: _query.isEmpty
                      ? null
                      : M3EIconButton(
                          suppressInk: true,
                          tooltip: tr(
                            context,
                            'Очистить поиск',
                            'Clear search',
                          ),
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          variant: M3EIconButtonVariant.standard,
                        ),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                ),
                const SizedBox(height: 12),
              ],
              if (_query.isNotEmpty &&
                  !widget.accounts.any(
                    (a) => a.label.toLowerCase().contains(_query),
                  ))
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tr(context, 'Ничего не найдено.', 'No matches found.'),
                  ),
                ),
              for (final account
                  in (_running
                          ? _queue
                          : orderPassQueue(widget.accounts, _ownId))
                      .where((a) => a.label.toLowerCase().contains(_query)))
                _accountCard(account, enabled),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: M3EProgressIndicator.linearWavy(),
                ),

              if (!(defaultTargetPlatform == TargetPlatform.android))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    tr(
                      context,
                      'Доступно только на Android.',
                      'Available on Android only.',
                    ),
                    style: TextStyle(color: context.palette.muted),
                  ),
                ),
              const SizedBox(height: 8),
              if (defaultTargetPlatform == TargetPlatform.android)
                _card(
                  child: Row(
                    children: [
                      Icon(Icons.widgets_outlined, color: context.palette.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(
                                context,
                                'На главном экране',
                                'On your home screen',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tr(
                                context,
                                'Запуск сохранённой очереди одним касанием.',
                                'Start your saved queue with one tap.',
                              ),
                              style: TextStyle(
                                color: context.palette.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      CampusButton.text(
                        onPressed: enabled ? _addWidget : null,
                        child: Text(
                          tr(context, 'Добавить виджет', 'Add widget'),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              M3EList(
                itemCount: 1,
                itemBuilder: (context, index) => CampusListItem(
                  headline: tr(context, 'Как пользоваться', 'How to use'),
                  leading: Icon(
                    Icons.info_outline_rounded,
                    color: context.palette.muted,
                    size: 20,
                  ),
                  expanded: M3EExpandableExpanded.content(
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            tr(
                              context,
                              'Для подключения нужен код подтверждения владельца. Поднесите разблокированный телефон к турникету. После первого ответа очередь выдержит задержку и переключится дальше. Иногда нужно убрать и снова поднести телефон. Предъявление не подтверждает допуск — проверяйте результат на турникете.',
                              'Enroll each pass with its owner’s verification code. Hold the unlocked phone against the gate. After the first response, the queue waits for the delay and advances. You may need to lift and tap again. Presentation does not confirm admission; check the gate result.',
                            ),
                            style: TextStyle(
                              color: context.palette.muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),

          child: Column(
            children: [
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: context.palette.blue,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _message!,
                            style: TextStyle(
                              color: context.palette.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        M3EIconButton(
                          suppressInk: true,
                          tooltip: tr(context, 'Закрыть', 'Dismiss'),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => setState(() => _message = null),
                          variant: M3EIconButtonVariant.standard,
                        ),
                      ],
                    ),
                  ),
                ),
              if (_nfcDisabled)
                CampusButton.icon(
                  onPressed: () =>
                      nfcPassChannel.invokeMethod<void>('openNfcSettings'),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(tr(context, 'Настройки NFC', 'NFC settings')),
                  style: M3EButtonStyle.text,
                ),
              SizedBox(
                width: double.infinity,
                child: CampusButton.icon(
                  onPressed: _running
                      ? _stop
                      : enabled && _selected.isNotEmpty
                      ? _start
                      : null,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: M3EProgressIndicator.circularWavy(
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(_running ? Icons.stop_rounded : Icons.nfc_rounded),
                  label: Text(
                    _busy
                        ? tr(context, 'Подождите…', 'Please wait…')
                        : _running
                        ? tr(context, 'Остановить очередь', 'Stop queue')
                        : tr(context, 'Запустить очередь', 'Start queue'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  context,
                  'Не закрывайте вкладку, пока очередь работает.',
                  'Keep this tab open while the queue runs.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: context.palette.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VerificationDialog extends StatefulWidget {
  const _VerificationDialog({required this.label});
  final String label;
  @override
  State<_VerificationDialog> createState() => _VerificationDialogState();
}

class _VerificationDialogState extends State<_VerificationDialog> {
  final _code = TextEditingController();
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.label),
    content: CampusTextField(
      controller: _code,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      label: tr(
        context,
        'Код подтверждения (6 цифр)',
        'Verification code (6 digits)',
      ),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      CampusButton.text(
        onPressed: () => Navigator.pop(context),
        child: Text(tr(context, 'Отмена', 'Cancel')),
      ),
      CampusButton.filled(
        onPressed: _code.text.length == 6
            ? () => Navigator.pop(context, _code.text)
            : null,
        child: Text(tr(context, 'Подключить', 'Enroll')),
      ),
    ],
  );
}
