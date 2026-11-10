import 'dart:async';

import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'aa_id.dart';
import 'app_settings.dart';
import 'app_theme.dart';
import 'campus_design.dart';
import 'expressive.dart';
import 'frontend/command_bar.dart';
import 'frontend/page_layout.dart';
import 'l10n.dart';
import 'pulse_api.dart';
import 'screen_navigation.dart';
import 'server_api.dart';
import 'server_login_page.dart';
import 'server_passes_page.dart';
import 'server_qr_scanner.dart';
import 'server_schedule_page.dart';
import 'server_sessions.dart';
import 'server_today_page.dart';
import 'session_server_page.dart';
import 'settings_page.dart';
import 'sensitive_data.dart';
import 'update_service.dart';

/// Production application for the server-owned API. Old local Pulse workflows
/// remain isolated from this shell and are never used as a network fallback.
class ServerWorkspace extends StatefulWidget {
  const ServerWorkspace({
    super.key,
    this.client,
    required this.settings,
    this.language,
    required this.onLanguageChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.updates,
  });
  final SessionServerClient? client;
  final AppSettingsStore settings;
  final String? language;
  final ValueChanged<String?> onLanguageChanged;
  final AppThemeMode themeMode;
  final ValueChanged<AppThemeMode> onThemeModeChanged;
  final UpdateController? updates;
  @override
  State<ServerWorkspace> createState() => _ServerWorkspaceState();
}

class _ServerWorkspaceState extends State<ServerWorkspace>
    with WidgetsBindingObserver {
  SessionServerClient? _client;
  AaServerApi? _api;
  StreamSubscription<void>? _changes;
  Timer? _refreshTimer;
  int _tab = 0, _generation = 0;
  int? _lessonStart, _group;
  Map<String, dynamic>? _state;
  final Set<String> _selected = {};
  final Map<String, Map<String, dynamic>> _results = {};
  static const _widgetChannel = MethodChannel('antiattendance/launcher_widget');
  bool _widgetScanPending = false;
  bool _loading = true, _refreshing = false, _busy = false;
  String? _error;
  final _scheduleKey = GlobalKey<ServerSchedulePageState>();
  final _passesKey = GlobalKey<ServerPassesPageState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changes = ServerSessions.changes.listen((_) {
      if (widget.client == null && ServerSessions.active != _client) {
        if (ServerSessions.active == null) {
          ++_generation;
          setState(() {
            _client = null;
            _api = null;
            _state = null;
            _loading = false;
            _error = null;
          });
        } else {
          _initialize();
        }
      } else if (!_busy) {
        _refreshActive();
      }
    });
    _widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'scanAll') {
        _widgetScanPending = true;
        _openWidgetScan();
      }
      if (call.method == 'nfcPasses') _selectTab(2);
    });
    _initialize();
    _widgetChannel
        .invokeMethod<bool>('takeScanAllRequest')
        .then((value) {
          if (mounted && value == true) {
            _widgetScanPending = true;
            _openWidgetScan();
          }
        })
        .catchError((Object _) {});
    _widgetChannel
        .invokeMethod<bool>('takeNfcPassRequest')
        .then((value) {
          if (mounted && value == true) _selectTab(2);
        })
        .catchError((Object _) {});
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_busy &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused) {
        _refreshActive();
      }
    });
  }

  void _refreshActive() {
    if (_tab == 0) _refresh();
    if (_tab == 1) _scheduleKey.currentState?.refresh();
    if (_tab == 2) _passesKey.currentState?.refresh();
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    try {
      await ServerSessions.initialize();
      if (!mounted || generation != _generation) return;
      final client =
          widget.client ??
          ServerSessions.active ??
          SessionServerClient(defaultSessionServerUrl);
      _client = client;
      _api = AaServerApi(client);
      if (widget.client == null && ServerSessions.active == null) {
        await ServerSessions.connect(client);
      } else {
        await client.fetch();
      }
      if (!mounted || generation != _generation) return;
      if (widget.client == null) {
        client.watch();
        unawaited(SensitiveData.purge().catchError((Object _) {}));
      }
      await _refresh();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = serverError(context, error);
        });
      }
    }
  }

  Future<void> _refresh({int? lessonStart, bool changeLesson = false}) async {
    if (_refreshing || _api == null || _busy) return;
    setState(() => _refreshing = true);
    final generation = _generation;
    try {
      final state = await _api!.state(
        lessonStart: changeLesson ? lessonStart : _lessonStart,
      );
      if (!mounted || generation != _generation) return;
      final oldLesson = serverObject(
        _state?['selected_lesson'],
      )['lesson_start'];
      final selectedLesson = serverObject(state['selected_lesson']);
      final people = serverRows(state['people']);
      final eligible = people
          .where((p) => p['session'] == 'valid')
          .map((p) => p['id'])
          .whereType<String>()
          .toSet();
      setState(() {
        if (_state == null || oldLesson != selectedLesson['lesson_start']) {
          _selected
            ..clear()
            ..addAll(eligible);
          _results.clear();
        } else {
          _selected.retainAll(eligible);
        }
        if (_group != null &&
            !serverRows(state['groups'])
                .any((group) => group['id'] == _group)) {
          _group = null;
        }
        _state = state;
        _lessonStart = selectedLesson['lesson_start'] as int?;
        _loading = false;
        _error = null;
      });
      _openWidgetScan();
    } catch (error) {
      if (!mounted || generation != _generation) return;
      if (error is SessionServerException &&
          error.status == 409 &&
          _lessonStart != null) {
        _lessonStart = null;
        _selected.clear();
      }
      setState(() {
        _loading = false;
        _error = serverError(context, error);
      });
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _openWidgetScan() {
    if (!_widgetScanPending || _state == null || _busy || !mounted) return;
    _widgetScanPending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_lessonStart == null || _selected.isEmpty) {
        CampusNotice.show(
          context,
          message: tr(
            context,
            'Сейчас нет доступных занятий.',
            'No class available now.',
          ),
        );
        return;
      }
      setState(() => _tab = 0);
      _scan();
    });
  }

  Future<void> _renew() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ServerLoginPage(
          address: AaId.url,
          expectedUserId: AaId.session?.userId,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _scan() async {
    if (_busy || _api == null || _lessonStart == null) return;
    final lesson = _lessonStart!;
    final people = serverRows(_state?['people'])
        .where(
          (p) =>
              _selected.contains(p['id']) &&
              p['session'] == 'valid' &&
              (_group == null || p['group_id'] == _group),
        )
        .toList();
    if (people.isEmpty) return;
    setState(() {
      _busy = true;
      _results.removeWhere((id, _) => people.any((p) => p['id'] == id));
    });
    try {
      final results = await Navigator.of(context)
          .push<Map<String, Map<String, dynamic>>>(
            MaterialPageRoute(
              builder: (_) => ServerQrScanner(
                api: _api!,
                people: people,
                lessonStart: lesson,
              ),
            ),
          );
      if (mounted && results != null && lesson == _lessonStart) {
        setState(() => _results.addAll(results));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _refresh();
      }
    }
  }

  Future<void> _paste() async {
    final controller = TextEditingController();
    try {
      final qr = await showExpressiveDialog<String>(
        context: context,
        builder: (context) => BrockmannDialog(
          title: Text(tr(context, 'Ссылка занятия', 'Class link')),
          content: CampusTextField(
            controller: controller,
            label: tr(context, 'Ссылка', 'Link'),
            keyboardType: TextInputType.url,
          ),
          actions: [
            CampusButton.text(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context, 'Отмена', 'Cancel')),
            ),
            CampusButton.filled(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(tr(context, 'Отправить', 'Submit')),
            ),
          ],
        ),
      );
      if (mounted && qr != null) await _mark(qr);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _mark(String qr) async {
    if (_busy || _selected.isEmpty || _lessonStart == null || _api == null) {
      return;
    }
    try {
      attendanceTokenFromQr(qr);
    } on FormatException {
      setState(
        () => _error = tr(
          context,
          'Проверьте QR-ссылку занятия.',
          'Check the attendance QR link.',
        ),
      );
      return;
    }
    final ids = serverRows(_state?['people'])
        .where(
          (person) =>
              _selected.contains(person['id']) &&
              (_group == null || person['group_id'] == _group),
        )
        .map((person) => person['id'] as String)
        .toSet();
    if (ids.isEmpty) return;
    final lesson = _lessonStart;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await _api!.mark(qr, ids, lessonStart: lesson);
      if (!mounted) return;
      setState(() {
        for (final result in results) {
          if (result['id'] is String) _results[result['id'] as String] = result;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = serverError(context, error));
      if (error is SessionServerException && error.status == 409) {
        _lessonStart = null;
        _selected.clear();
      }
      // Never resubmit automatically after network errors or partial success.
    } finally {
      if (mounted) {
        final operationError = _error;
        setState(() => _busy = false);
        await _refresh();
        if (mounted && operationError != null) {
          setState(() => _error = operationError);
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (widget.client == null) _client?.watch();
      _refresh();
    }
    if (state == AppLifecycleState.paused && widget.client == null) {
      _client?.pause();
    }
  }

  @override
  void dispose() {
    ++_generation;
    _widgetChannel.setMethodCallHandler(null);
    _changes?.cancel();
    _refreshTimer?.cancel();
    if (widget.client == null) _client?.pause();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _selectTab(int tab) {
    if (_busy || _tab == tab) return;
    setState(() => _tab = tab);
    if (tab == 0) _refresh();
  }

  Widget _attendance() {
    final me = serverObject(_state?['me']);
    final lesson = serverObject(_state?['selected_lesson']);
    final choices = serverRows(_state?['available_lessons']);
    final people = serverRows(_state?['people']);
    final groups = serverRows(_state?['groups']);
    final visible = people
        .where((p) => _group == null || p['group_id'] == _group)
        .toList();
    final canMark =
        !_busy &&
        !_refreshing &&
        _lessonStart != null &&
        visible.any((person) => _selected.contains(person['id'])) &&
        _error == null;
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              key: const PageStorageKey('server-attendance'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AaPageLayout.insets(context),
              children: [
                if (me['connected'] != true) ...[
                  AaEmptyState(
                    title: tr(
                      context,
                      'Нужен вход в МИРЭА',
                      'MIREA sign-in needed',
                    ),
                    detail: tr(
                      context,
                      'AA ID подключён, но на сервере нет действующей сессии МИРЭА.',
                      'AA ID is signed in, but the server has no connected MIREA session.',
                    ),
                    action: CampusButton.filled(
                      onPressed: _renew,
                      child: Text(tr(context, 'Войти снова', 'Sign in again')),
                    ),
                  ),
                ],
                if (_refreshing) const CampusProgress.compact(),
                if (lesson.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: BrockmannText(
                          '${lesson['start']}–${lesson['end']}',
                          role: BrockmannType.monoValue,
                          color: context.brockmann.accentText,
                        ),
                      ),
                      if (choices.length > 1)
                        CampusTextAction(
                          icon: Icons.swap_horiz_rounded,
                          label: tr(context, 'Занятие', 'Class'),
                          onPressed: _busy || _refreshing
                              ? null
                              : () async {
                                  final chosen = await showChoicePage<int>(
                                    context,
                                    title: tr(context, 'Занятие', 'Class'),
                                    options: [
                                      for (final choice in choices)
                                        ChoiceOption(
                                          value: choice['lesson_start'] as int,
                                          label:
                                              '${choice['start']} · ${choice['subject']}',
                                          selected:
                                              choice['lesson_start'] ==
                                              _lessonStart,
                                        ),
                                    ],
                                  );
                                  if (mounted &&
                                      chosen != null &&
                                      chosen != _lessonStart) {
                                    await _refresh(
                                      lessonStart: chosen,
                                      changeLesson: true,
                                    );
                                  }
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  BrockmannText(
                    '${lesson['subject']}',
                    role: BrockmannType.heading,
                  ),
                  const SizedBox(height: 8),
                  BrockmannText(
                    [lesson['location'], lesson['type']]
                        .whereType<String>()
                        .where((v) => v.trim().isNotEmpty)
                        .join(' · '),
                    color: context.brockmann.secondary,
                  ),
                ] else if (me['connected'] == true)
                  AaEmptyState(
                    title: tr(
                      context,
                      'Сейчас нет доступных занятий',
                      'No class available now',
                    ),
                    detail: tr(
                      context,
                      'Отметка доступна за 30 минут до и после занятия.',
                      'Attendance opens 30 minutes before class and closes 30 minutes after it.',
                    ),
                  ),
                if (_state?['schedule_error'] != null)
                  ServerMessage(message: '${_state!['schedule_error']}'),
                if (_error != null) ServerMessage(message: _error!),
                if (groups.length > 1)
                  BrockmannPicker(
                    label: tr(context, 'Группа', 'Group'),
                    options: [
                      tr(context, 'Все группы', 'All groups'),
                      for (final g in groups) '${g['name']}',
                    ],
                    selected: _group == null
                        ? 0
                        : (groups.indexWhere((g) => g['id'] == _group) + 1)
                              .clamp(0, groups.length),
                    onChanged: _busy
                        ? null
                        : (i) => setState(
                            () => _group = i == 0
                                ? null
                                : groups[i - 1]['id'] as int?,
                          ),
                  ),
                AaSectionHeading(
                  title:
                      '${tr(context, 'Люди', 'People')} · ${visible.where((p) => _selected.contains(p['id'])).length}/${visible.length}',
                  action: CampusButton.text(
                    onPressed:
                        _busy || !visible.any((p) => p['session'] == 'valid')
                        ? null
                        : () {
                            final ids = visible
                                .where((p) => p['session'] == 'valid')
                                .map((p) => p['id'])
                                .whereType<String>()
                                .toSet();
                            setState(() {
                              if (ids.every(_selected.contains)) {
                                _selected.removeAll(ids);
                              } else {
                                _selected.addAll(ids);
                              }
                            });
                          },
                    child: Text(
                      visible
                              .where((p) => p['session'] == 'valid')
                              .every((p) => _selected.contains(p['id']))
                          ? tr(context, 'Снять выбор', 'Clear selection')
                          : tr(context, 'Выбрать всех', 'Select all'),
                    ),
                  ),
                ),
                for (final (index, person) in visible.indexed)
                  BrockmannFeather(index: index, child: _person(person)),
                if (visible.isEmpty && _state?['schedule_error'] == null)
                  BrockmannText(
                    tr(
                      context,
                      'Список людей появится для выбранного занятия.',
                      'People appear for the selected class.',
                    ),
                    color: context.brockmann.secondary,
                  ),
              ],
            ),
          ),
        ),
        CampusCommandBar(
          active: _tab == 0,
          commands: [
            CampusCommand(
              icon: Icons.qr_code_scanner_rounded,
              label: tr(context, 'Сканировать', 'Scan'),
              onPressed: canMark ? _scan : null,
            ),
            CampusCommand(
              icon: Icons.content_paste_rounded,
              label: tr(context, 'Вставить', 'Paste'),
              onPressed: canMark ? _paste : null,
            ),
            CampusCommand(
              icon: Icons.table_rows_outlined,
              label: tr(context, 'За день', 'Today'),
              onPressed: _api == null
                  ? null
                  : () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => ServerTodayPage(api: _api!),
                      ),
                    ),
            ),
            CampusCommand(
              icon: Icons.refresh_rounded,
              label: tr(context, 'Обновить', 'Refresh'),
              onPressed: _busy ? null : _refresh,
            ),
          ],
        ),
      ],
    );
  }

  Widget _person(Map<String, dynamic> person) {
    final id = person['id'] as String;
    final result = _results[id] ?? serverObject(person['mark']);
    final valid = person['session'] == 'valid';
    return CampusListItem(
      leading: CampusCheckbox(
        value: _selected.contains(id),
        onChanged: _busy || !valid
            ? null
            : (_) => setState(() {
                if (!_selected.add(id)) _selected.remove(id);
              }),
      ),
      onTap: _busy || !valid
          ? null
          : () => setState(() {
              if (!_selected.add(id)) _selected.remove(id);
            }),
      headline: '${person['label'] ?? person['username'] ?? '—'}',
      supportingText: [
        if (person['group_name'] != null) '${person['group_name']}',
        if (!valid) tr(context, 'Нужен повторный вход', 'Sign-in needed'),
        if (person['inside'] == true)
          tr(context, 'В университете', 'On campus'),
        if (person['inside'] == false)
          tr(context, 'Вне университета', 'Off campus'),
        if (result.isNotEmpty) '${result['message'] ?? result['state']}',
      ].join(' · '),
    );
  }

  @override
  Widget build(BuildContext context) => ScreenNavigation(
    selectedIndex: _tab,
    onSelected: _selectTab,
    child: _loading
        ? const Center(child: CampusProgress.compact())
        : _state == null
        ? ListView(
            padding: AaPageLayout.insets(context),
            children: [
              AaEmptyState(
                title: tr(context, 'Сервер недоступен', 'Server unavailable'),
                detail: _error ?? '',
                action: CampusButton.filled(
                  onPressed: _initialize,
                  child: Text(tr(context, 'Повторить', 'Retry')),
                ),
              ),
              CampusButton.text(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const SessionServerPage()),
                ),
                child: Text(tr(context, 'Адрес сервера', 'Server address')),
              ),
            ],
          )
        : IndexedStack(
            index: _tab,
            children: [
              _attendance(),
              ServerSchedulePage(
                key: _scheduleKey,
                api: _api!,
                active: _tab == 1,
              ),
              ServerPassesPage(key: _passesKey, api: _api!, active: _tab == 2),
              SettingsPage(
                embedded: true,
                serverManaged: true,
                store: widget.settings,
                language: widget.language,
                onLanguageChanged: widget.onLanguageChanged,
                themeMode: widget.themeMode,
                onThemeModeChanged: widget.onThemeModeChanged,
                updates: widget.updates,
              ),
            ],
          ),
  );
}

String serverError(BuildContext context, Object error) {
  final status = error is SessionServerException ? error.status : null;
  return switch (status) {
    401 => tr(context, 'Войдите в AA ID снова.', 'Sign in to AA ID again.'),
    403 => tr(
      context,
      'Сервер не разрешил это действие.',
      'The server did not allow this action.',
    ),
    404 => tr(
      context,
      'Запись не найдена или недоступна.',
      'This record is unavailable.',
    ),
    409 => tr(
      context,
      'Данные изменились. Обновите список и повторите действие.',
      'The context changed. Refresh and choose again.',
    ),
    429 => tr(
      context,
      'Слишком много запросов. Подождите немного.',
      'Too many requests. Please wait.',
    ),
    _ => tr(
      context,
      'Не удалось получить ответ. Проверьте подключение.',
      'Could not get a response. Check your connection.',
    ),
  };
}

class ServerMessage extends StatelessWidget {
  const ServerMessage({super.key, required this.message, this.isError = true});
  final String message;
  final bool isError;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Semantics(
      liveRegion: true,
      child: BrockmannText(
        message,
        color: isError
            ? Theme.of(context).colorScheme.error
            : context.brockmann.secondary,
      ),
    ),
  );
}
