import 'campus_design.dart';
import 'expressive.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:nfc_pass_client/nfc_pass_client.dart';

import 'accounts.dart';
import 'app_theme.dart';
import 'l10n.dart';
import 'nfc_pass.dart';
import 'session_check.dart';
import 'widget_preview.dart';
import 'server_sessions.dart';

class NfcPassPage extends StatefulWidget {
  const NfcPassPage({
    super.key,
    required this.accounts,
    this.startOnOpen = false,
    this.onReauth,
    this.onSessionExpired,
    this.clientFactory = passClient,
  });
  final List<SavedAccount> accounts;
  final bool startOnOpen;
  final Future<void> Function(SavedAccount)? onReauth;
  final Future<void> Function(SavedAccount)? onSessionExpired;
  final NfcPassClient Function(SavedAccount) clientFactory;

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
  bool _single = false;
  String? _singleId;
  Set<String> get _activeIds => _single
      ? {if (_singleId != null && _numbers.containsKey(_singleId)) _singleId!}
      : _selected;
  String? _message;
  SavedAccount? _reauthAccount;
  String? _operationAccountId;
  bool _busy = true;
  bool _bulkEnrolling = false;
  bool _enrollmentSucceeded = false;
  int _bulkIndex = 0;
  int _bulkTotal = 0;
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

  @override
  void didUpdateWidget(covariant NfcPassPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedIds = oldWidget.accounts
        .where(
          (old) => !widget.accounts.any(
            (next) => next.id == old.id && next.cookie == old.cookie,
          ),
        )
        .map((a) => a.id)
        .toSet();
    if (changedIds.isEmpty) return;
    _viewEpoch++;
    _runEpoch++;
    _numbers.removeWhere((id, _) => changedIds.contains(id));
    _selected.removeAll(changedIds);
    if (changedIds.contains(_reauthAccount?.id)) {
      _reauthAccount = null;
      _message = null;
    }
    if (_running) unawaited(deactivateQueue());
  }

  Future<void> _handlePassError(
    Object error,
    SavedAccount account,
    String stage,
  ) async {
    var expired =
        error is NfcPassTransportException && error.requiresAuthentication;
    // Bearer-token rejection during issuance doesn't necessarily reject the cookie.
    if (expired && stage != 'token') {
      final checkClient = widget.clientFactory(account);
      final SessionCheckResult check;
      try {
        check = await checkSession(account, client: checkClient);
      } finally {
        checkClient.httpClient.close();
      }
      if (!mounted ||
          !widget.accounts.any(
            (item) => item.id == account.id && item.cookie == account.cookie,
          )) {
        return;
      }
      expired = check.state == SessionCheckState.expired;
      if (check.state == SessionCheckState.valid) {
        if (mounted) {
          setState(
            () => _message = tr(
              context,
              'Токен пропуска отклонён. Подключите пропуск снова; сессия действительна.',
              'Pass token rejected. Enroll the pass again; your session is valid.',
            ),
          );
        }
        return;
      }
      if (!expired) {
        if (mounted) {
          setState(
            () => _message = tr(
              context,
              'Сервис недоступен. Сессию проверить не удалось.',
              'Service unavailable. Could not check the session.',
            ),
          );
        }
        return;
      }
    }
    if (expired) {
      await widget.onSessionExpired?.call(account);
      if (mounted) {
        setState(() {
          _reauthAccount = account;
          _message = tr(
            context,
            'Сессия истекла. Войдите снова.',
            'Session expired. Sign in again.',
          );
        });
      }
    } else if (mounted) {
      setState(() => _message = _error(error));
    }
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
        _single = settings['mode'] == 'single';
        final singleId = settings['singleAccountId'];
        _singleId = singleId is String && numbers.containsKey(singleId)
            ? singleId
            : numbers.keys.firstOrNull;
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
    if (_activeIds.isEmpty) {
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
    final compact = await showWidgetPreview(context, nfc: true);
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
    if (error is NfcPassUnreachableException) {
      return tr(
        context,
        'Сервис пропусков недоступен. Проверьте интернет и повторите позже.',
        'Pass service unreachable. Check your connection and try later.',
      );
    }
    if (error is FormatException) {
      return tr(
        context,
        'Сервис вернул некорректный или просроченный токен пропуска. Повторите подключение.',
        'The service returned an invalid or expired pass token. Restart enrollment.',
      );
    }
    if (error is NfcVerificationException) {
      if (error.failure == NfcVerificationFailure.wrongCode) {
        return tr(
          context,
          'Неверный код подтверждения. Проверьте код и введите его снова.',
          'Incorrect verification code. Check the code and enter it again.',
        );
      }
      return tr(
        context,
        'МИРЭА не удалось выдать пропуск. Обратитесь в поддержку.',
        'MIREA could not issue the pass. Contact support.',
      );
    }
    if (error is NfcPassTransportException) {
      if (error.requiresAuthentication) {
        return tr(
          context,
          'Сессия истекла. Войдите снова.',
          'Session expired. Sign in again.',
        );
      }
      if (error.httpStatusCode == 403 || error.grpcStatus == 7) {
        return tr(
          context,
          'Доступ к сервису пропусков запрещён. Обратитесь в поддержку МИРЭА.',
          'Pass service access denied. Contact MIREA support.',
        );
      }
      return trf(
        context,
        'Ошибка сервиса пропусков ({status}). Повторите позже.',
        'Pass service error ({status}). Try again later.',
        {
          'status': error.httpStatusCode != null
              ? 'HTTP ${error.httpStatusCode}'
              : 'gRPC ${error.grpcStatus ?? '—'}',
        },
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
      _enrollmentSucceeded = false;
      _message = null;
      _reauthAccount = null;
      _operationAccountId = account.id;
    });
    final epoch = _viewEpoch;
    final client = widget.clientFactory(account);
    var stage = 'token';
    try {
      var token = await client.getAccessTokenForDigitalPass();
      var tokenExpiry = passTokenExpiry(token);
      if (!mounted || epoch != _viewEpoch) return;
      stage = 'verification';
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
      stage = 'issuance';
      String? codeError;
      int? number;
      while (number == null) {
        final code = await showExpressiveDialog<String>(
          context: context,
          builder: (context) =>
              _VerificationDialog(label: account.label, error: codeError),
        );
        if (code == null || !mounted || epoch != _viewEpoch) return;
        try {
          // Refresh the bearer token if the owner took longer than its lifetime.
          if (!tokenExpiry.isAfter(
            DateTime.now().add(const Duration(seconds: 5)),
          )) {
            stage = 'token';
            token = await client.getAccessTokenForDigitalPass();
            tokenExpiry = passTokenExpiry(token);
          }
          stage = 'issuance';
          number = await client.getDigitalPass(
            bearerToken: token,
            sixDigitCode: code,
            deviceName: 'AntiAttendance Android',
          );
        } on NfcVerificationException catch (error) {
          if (error.failure != NfcVerificationFailure.wrongCode) rethrow;
          codeError = _error(error);
        }
        if (!mounted || epoch != _viewEpoch) return;
      }
      await _store.save(account, number);
      if (mounted) {
        setState(() {
          _enrollmentSucceeded = true;
          _numbers[account.id] = number.toString();
          _selected.add(account.id);
        });
      }
      if (mounted) unawaited(_savePreferences());
    } catch (error) {
      if (mounted && epoch == _viewEpoch) {
        await _handlePassError(error, account, stage);
      }
    } finally {
      _operationAccountId = null;
      client.httpClient.close();
      if (mounted) setState(() => _busy = _bulkEnrolling);
      if (mounted &&
          !_bulkEnrolling &&
          epoch == _viewEpoch &&
          _widgetStartPending) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && epoch == _viewEpoch) unawaited(startFromWidget());
        });
      }
    }
  }

  Future<void> _bulkEnroll() async {
    if (_busy || _running) return;
    final picked = widget.accounts
        .where((a) => !_numbers.containsKey(a.id))
        .map((a) => a.id)
        .toSet();
    if (picked.isEmpty) picked.addAll(widget.accounts.map((a) => a.id));
    final ids = await showExpressiveSheet<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  tr(
                    context,
                    'Подключить пропуска вместе',
                    'Enroll passes together',
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final account in widget.accounts)
                      CampusListItem(
                        headline: account.label,
                        supportingText: _numbers.containsKey(account.id)
                            ? tr(
                                context,
                                'Существующий пропуск будет заменён после подтверждения.',
                                'The existing pass will be replaced after verification.',
                              )
                            : tr(
                                context,
                                'Подключите пропуск',
                                'Enroll a pass',
                              ),
                        leading: CampusCheckbox(
                          value: picked.contains(account.id),
                          onChanged: (_) => update(() {
                            if (!picked.add(account.id)) {
                              picked.remove(account.id);
                            }
                          }),
                        ),
                        onTap: () => update(() {
                          if (!picked.add(account.id)) {
                            picked.remove(account.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: CampusButton.filled(
                  onPressed: picked.isEmpty
                      ? null
                      : () => Navigator.pop(context, Set<String>.of(picked)),
                  child: Text(tr(context, 'Продолжить', 'Continue')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || ids == null) return;
    final queue = widget.accounts.where((a) => ids.contains(a.id)).toList();
    final epoch = _viewEpoch;
    setState(() {
      _bulkEnrolling = true;
      _busy = true;
      _bulkTotal = queue.length;
    });
    try {
      for (var index = 0; index < queue.length; index++) {
        if (!mounted || epoch != _viewEpoch) return;
        setState(() => _bulkIndex = index + 1);
        await _enroll(queue[index]);
        if (!_enrollmentSucceeded) break;
      }
    } finally {
      if (mounted) {
        setState(() {
          _bulkEnrolling = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _start() async {
    if (!_single && _ownId != null && !_selected.contains(_ownId)) {
      setState(
        () => _message = tr(
          context,
          'Подключите и выберите свой пропуск, чтобы предъявить его последним.',
          'Enroll and select your own pass to present it last.',
        ),
      );
      return;
    }
    final seconds = _single
        ? (int.tryParse(_seconds.text) ?? 60)
        : int.tryParse(_seconds.text);
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
      final selectedAccounts = widget.accounts
          .where((a) => _activeIds.contains(a.id))
          .toList();
      _queue = _single
          ? selectedAccounts
          : orderPassQueue(selectedAccounts, _ownId);
      final passes = <Map<String, Object>>[];
      for (final account in _queue) {
        _operationAccountId = account.id;
        final client = widget.clientFactory(account);
        try {
          final token = await client.getAccessTokenForDigitalPass();
          var expires = passTokenExpiry(token);
          final remoteId = serverAccountId(account.cookie);
          final testExpiry = remoteId == null
              ? null
              : ServerSessions.active?.testingExpiryFor(remoteId);
          if (testExpiry != null && testExpiry.isBefore(expires)) {
            expires = testExpiry;
          }
          passes.add({
            'accountId': account.id,
            'number': _numbers[account.id]!,
            'expiresAt': expires.millisecondsSinceEpoch,
          });
        } finally {
          client.httpClient.close();
        }
        if (!mounted || epoch != _runEpoch) return;
      }
      await _store.saveSettings(seconds, _ownId, _selected, _single, _singleId);
      if (!mounted || epoch != _runEpoch) return;
      final status = await nfcPassChannel.invokeMapMethod<String, dynamic>(
        'start',
        {'passes': passes, 'intervalSeconds': seconds, 'single': _single},
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
      if (!mounted || epoch != _runEpoch) return;
      final account = widget.accounts
          .where((a) => a.id == _operationAccountId)
          .firstOrNull;
      if (account != null) {
        await _handlePassError(error, account, 'token');
      } else if (mounted) {
        setState(() => _message = _error(error));
      }
    } finally {
      _operationAccountId = null;
      _widgetStartPending = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _poll() async {
    if (_polling || !_running) return;
    _polling = true;
    try {
      if (_queue.any((account) {
        final id = serverAccountId(account.cookie);
        return id != null && !(ServerSessions.active?.canUsePass(id) ?? false);
      })) {
        await _stop();
        return;
      }
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
    final seconds = _single
        ? (int.tryParse(_seconds.text) ?? 60)
        : int.tryParse(_seconds.text);
    if (seconds == null || seconds < 1 || seconds > 300) return;
    try {
      await _store.saveSettings(seconds, _ownId, _selected, _single, _singleId);
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

  Future<void> _showPassGuide() => showExpressiveSheet<void>(
    context: context,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'Как пользоваться', 'How to use'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            Text(
              tr(context, '1. Подключите пропуск', '1. Enroll a pass'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                context,
                'Владелец подтверждает подключение кодом. Для повторного подключения используйте кнопку подключения нескольких пропусков.',
                'The owner confirms enrollment with their verification code. Use bulk enrollment when several passes need renewing.',
              ),
            ),
            const SizedBox(height: 18),
            Text(
              tr(context, '2. Выберите режим', '2. Choose a mode'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                context,
                'Один пропуск: выберите владельца и нажмите «Активировать». Очередь: выберите людей, задержку и свой аккаунт, затем запустите очередь.',
                'Single pass: select the owner and activate it. Queue: select people, a delay and your own account, then start the queue.',
              ),
            ),
            const SizedBox(height: 18),
            Text(
              tr(context, '3. Поднесите телефон', '3. Tap at the gate'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                context,
                'Включите NFC и держите телефон разблокированным на этой вкладке. Проверяйте результат на турникете: предъявление не означает успешный проход.',
                'Enable NFC and keep the phone unlocked on this tab. Check the gate result: presenting a pass does not confirm admission.',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                context,
                'Один пропуск не переключается после касания. Очередь переходит к следующему после ответа и заданной задержки; может потребоваться убрать и снова поднести телефон.',
                'A single pass stays selected after a tap. The queue advances after a response and the chosen delay; you may need to lift and tap again.',
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _card({required Widget child, Color? color}) =>
      CampusPanel(color: color, child: child);

  void _toggle(SavedAccount account) {
    setState(() {
      if (_single) {
        _singleId = account.id;
      } else if (!_selected.add(account.id)) {
        _selected.remove(account.id);
      }
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
    final selected = _activeIds.contains(account.id);
    final own = !_single && account.id == _ownId;
    return Padding(
      padding: EdgeInsets.zero,
      child: CampusPressable(
        enabled: enabled && enrolled,
        child: Material(
          animationDuration: Duration.zero,
          color: context.palette.surface,
          shape: Border(
            bottom: BorderSide(color: context.palette.line, width: .5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled && enrolled ? () => _toggle(account) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
              child: Row(
                children: [
                  if (enrolled && _single)
                    CampusRadio<String>(
                      value: account.id,
                      groupValue: _singleId,
                      onChanged: enabled ? (_) => _toggle(account) : null,
                    )
                  else if (enrolled)
                    CampusCheckbox(
                      value: selected,
                      onChanged: enabled ? (_) => _toggle(account) : null,
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.label,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
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
                    CampusTextAction(
                      onPressed: enabled ? () => _passMenu(account) : null,
                      tooltip: tr(context, 'Удалить пропуск', 'Remove pass'),
                      label: tr(context, 'удалить', 'remove'),
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
        !_bulkEnrolling &&
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
                subtitle: _single
                    ? tr(
                        context,
                        'Выберите один пропуск ниже и активируйте его.',
                        'Choose one pass below and activate it.',
                      )
                    : tr(
                        context,
                        'Все пропуска. Одна очередь. Ваш — последним.',
                        'One queue for your passes. Yours goes last.',
                      ),
              ),
              if (_numbers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: CampusButton.action(
                          style: _single
                              ? CampusButtonStyle.outlined
                              : CampusButtonStyle.tonal,
                          onPressed: enabled
                              ? () {
                                  setState(() => _single = false);
                                  unawaited(_savePreferences());
                                }
                              : null,
                          label: Text(tr(context, 'Очередь', 'Queue')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CampusButton.action(
                          style: _single
                              ? CampusButtonStyle.tonal
                              : CampusButtonStyle.outlined,
                          onPressed: enabled
                              ? () {
                                  setState(() {
                                    _single = true;
                                    _singleId ??= _numbers.keys.firstOrNull;
                                  });
                                  unawaited(_savePreferences());
                                }
                              : null,
                          label: Text(
                            tr(context, 'Один пропуск', 'Single pass'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_bulkEnrolling)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    trf(
                      context,
                      'Подключаем пропуск {current} из {total}',
                      'Enrolling pass {current} of {total}',
                      {'current': _bulkIndex, 'total': _bulkTotal},
                    ),
                  ),
                ),
              if (_numbers.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: CampusButton.action(
                    onPressed: enabled && widget.accounts.isNotEmpty
                        ? _bulkEnroll
                        : null,
                    label: Text(
                      tr(
                        context,
                        'Подключить пропуска вместе',
                        'Enroll passes together',
                      ),
                    ),
                    style: CampusButtonStyle.tonal,
                  ),
                ),
              const SizedBox(height: 12),
              _card(
                color: _running
                    ? context.palette.selected
                    : context.palette.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _running
                                ? (_single
                                      ? tr(
                                          context,
                                          'Пропуск активен',
                                          'Pass is active',
                                        )
                                      : tr(
                                          context,
                                          'Очередь работает',
                                          'Queue is running',
                                        ))
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
                              color: (_running
                                  ? scheme.onPrimaryContainer
                                  : context.palette.ink),
                              fontSize: 18,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_numbers.isNotEmpty || _running) ...[
                      const SizedBox(height: 16),
                      Text(
                        _running
                            ? current?.label ?? '—'
                            : _single
                            ? widget.accounts
                                      .where((a) => a.id == _singleId)
                                      .firstOrNull
                                      ?.label ??
                                  tr(
                                    context,
                                    'Выберите пропуск',
                                    'Choose a pass',
                                  )
                            : _selected.length == 1
                            ? tr(context, 'Выбран 1 пропуск', '1 pass selected')
                            : trf(
                                context,
                                'Выбрано пропусков: {count}',
                                '{count} passes selected',
                                {'count': _selected.length},
                              ),
                        style: TextStyle(
                          color: (_running
                              ? scheme.onPrimaryContainer
                              : context.palette.ink),
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      _running
                          ? _single
                                ? tr(
                                    context,
                                    'Один пропуск активен до остановки или истечения токена.',
                                    'This pass stays active until stopped or its token expires.',
                                  )
                                : _status['responded'] == true
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
                          : _numbers.isEmpty
                          ? tr(
                              context,
                              'Подключите пропуска выбранных аккаунтов.',
                              'Enroll passes for your selected accounts.',
                            )
                          : _single
                          ? tr(
                              context,
                              'Выберите один пропуск ниже и активируйте его.',
                              'Choose one pass below and activate it.',
                            )
                          : tr(
                              context,
                              'Выберите людей ниже и запустите очередь.',
                              'Choose people below, then start the queue.',
                            ),
                      style: TextStyle(
                        color:
                            (_running
                                    ? scheme.onPrimaryContainer
                                    : context.palette.ink)
                                .withValues(alpha: .8),
                        fontSize: 13,
                      ),
                    ),
                    if (_running && !_single) ...[
                      const SizedBox(height: 16),
                      CampusProgress.linear(
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
                          color: (_running
                              ? scheme.onPrimaryContainer
                              : context.palette.ink),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(context, 'Пропуска', 'Passes'),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  if (_numbers.isNotEmpty && !_single)
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
                  trailing: _query.isEmpty
                      ? null
                      : CampusTextAction(
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          tooltip: tr(
                            context,
                            'Очистить поиск',
                            'Clear search',
                          ),
                          label: tr(context, 'очистить', 'clear'),
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
              if (!_single && _numbers.isNotEmpty)
                ExpansionTile(
                  trailing: const Text(
                    '+',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300),
                  ),
                  key: const PageStorageKey('nfc-queue-options'),
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    tr(context, 'Настройка очереди', 'Queue settings'),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
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
                                        fontWeight: FontWeight.w400,
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
                            child: Divider(
                              height: 1,
                              color: context.palette.line,
                            ),
                          ),
                          AppPassPicker(
                            key: ValueKey(_ownId),
                            enabled: enabled,
                            hint: tr(context, 'Ваш аккаунт', 'Your account'),
                            items: [
                              PassPickerItem(
                                value: '',
                                label: tr(context, 'Не выбран', 'Not selected'),
                                selected: _ownId == null,
                              ),
                              for (final account in widget.accounts)
                                PassPickerItem(
                                  value: account.id,
                                  label: account.label,
                                  selected: account.id == _ownId,
                                ),
                            ],
                            onChanged: (items) {
                              final value = items.isEmpty
                                  ? ''
                                  : items.first.value;
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
                  ],
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: CampusProgress.linear(),
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
                CampusListItem(
                  headline: tr(
                    context,
                    'На главном экране',
                    'On your home screen',
                  ),
                  supportingText: tr(
                    context,
                    'Запуск сохранённой очереди одним касанием.',
                    'Start your saved queue with one tap.',
                  ),
                  trailing: CampusButton.text(
                    onPressed: enabled ? _addWidget : null,
                    child: Text(tr(context, 'Добавить виджет', 'Add widget')),
                  ),
                ),
              const SizedBox(height: 8),
              CampusListItem(
                headline: tr(context, 'Как пользоваться', 'How to use'),
                onTap: _showPassGuide,
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
                        Expanded(
                          child: Text(
                            _message!,
                            style: TextStyle(
                              color: context.palette.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        CampusTextAction(
                          onPressed: () => setState(() => _message = null),
                          tooltip: tr(context, 'Закрыть', 'Dismiss'),
                          label: tr(context, 'Закрыть', 'Dismiss'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_reauthAccount != null && widget.onReauth != null && !_busy)
                CampusButton.text(
                  onPressed: () => widget.onReauth!(_reauthAccount!),
                  child: Text(tr(context, 'Войти снова', 'Sign in again')),
                ),
              if (_nfcDisabled)
                CampusButton.action(
                  onPressed: () =>
                      nfcPassChannel.invokeMethod<void>('openNfcSettings'),
                  label: Text(tr(context, 'Настройки NFC', 'NFC settings')),
                  style: CampusButtonStyle.text,
                ),
              SizedBox(
                width: double.infinity,
                child: CampusButton.action(
                  onPressed: _running
                      ? _stop
                      : enabled &&
                            _numbers.isEmpty &&
                            widget.accounts.isNotEmpty
                      ? _bulkEnroll
                      : enabled && _activeIds.isNotEmpty
                      ? _start
                      : null,
                  label: Text(
                    _busy
                        ? tr(context, 'Подождите…', 'Please wait…')
                        : _running
                        ? (_single
                              ? tr(
                                  context,
                                  'Отключить пропуск',
                                  'Deactivate pass',
                                )
                              : tr(context, 'Остановить очередь', 'Stop queue'))
                        : _numbers.isEmpty
                        ? tr(context, 'Подключить пропуска', 'Enroll passes')
                        : (_single
                              ? tr(
                                  context,
                                  'Активировать пропуск',
                                  'Activate pass',
                                )
                              : tr(
                                  context,
                                  'Запустить очередь',
                                  'Start queue',
                                )),
                  ),
                ),
              ),
              if (_numbers.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _single
                      ? tr(
                          context,
                          'Не закрывайте вкладку, пока пропуск активен.',
                          'Keep this tab open while the pass is active.',
                        )
                      : tr(
                          context,
                          'Не закрывайте вкладку, пока очередь работает.',
                          'Keep this tab open while the queue runs.',
                        ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.palette.muted, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _VerificationDialog extends StatefulWidget {
  const _VerificationDialog({required this.label, this.error});
  final String label;
  final String? error;
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
    scrollable: true,
    title: Text(widget.label),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              widget.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        CampusTextField(
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
          onSubmitted: (_) {
            if (_code.text.length == 6) Navigator.pop(context, _code.text);
          },
        ),
      ],
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
