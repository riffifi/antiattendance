import 'package:brockmann/brockmann.dart';

import 'updates_page.dart';
import 'frontend/settings_view.dart';
import 'frontend/page_layout.dart';
import 'session_server_page.dart';
import 'aa_id_page.dart';
import 'server_api.dart';
import 'server_profile_page.dart';
import 'campus_design.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'about_page.dart';
import 'app_settings.dart';
import 'app_tutorial.dart';
import 'expressive.dart';
import 'accounts.dart';
import 'server_sessions.dart';
import 'session_server_sync.dart';
import 'schedule_api.dart';
import 'group_picker_page.dart';
import 'app_theme.dart';
import 'l10n.dart';
import 'nfc_diagnostics_page.dart';
import 'turnstile_probe_page.dart';
import 'update_service.dart';
import 'study_summary.dart';
import 'study_summary_page.dart';
import 'widget_preview.dart';

import 'package:flutter/services.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.store,
    required this.language,
    required this.onLanguageChanged,
    this.themeMode = AppThemeMode.light,
    this.onThemeModeChanged,
    this.embedded = false,
    this.serverManaged = false,
    this.updates,
    this.downloadApk,
    this.installApk,
    this.scheduleApi,
    this.accounts = const [],
  });

  final bool embedded;
  final bool serverManaged;
  final ScheduleApi? scheduleApi;
  final List<SavedAccount> accounts;
  final AppSettingsStore store;
  final String? language;
  final ValueChanged<String?> onLanguageChanged;
  final AppThemeMode themeMode;
  final ValueChanged<AppThemeMode>? onThemeModeChanged;
  final UpdateController? updates;
  final Future<File> Function(
    AppRelease release,
    void Function(int received, int? total) onProgress,
  )?
  downloadApk;
  final Future<void> Function(File apk)? installApk;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String? _language = widget.language;
  late AppThemeMode _themeMode = widget.themeMode;
  bool _saving = false;
  bool _sounds = true;
  bool _daySummary = false;
  bool _summarySaving = false;
  bool _summaryTouched = false;
  ScheduleGroup? _myGroup;

  @override
  void initState() {
    super.initState();
    widget.store
        .interfaceSounds()
        .then((value) {
          if (mounted) setState(() => _sounds = value);
        })
        .catchError((Object _) {});
    widget.store
        .loadMyGroup()
        .then((value) {
          if (mounted) setState(() => _myGroup = value);
        })
        .catchError((Object _) {});
    widget.store
        .loadDaySummaryEnabled()
        .then((value) {
          if (mounted && !_summaryTouched) setState(() => _daySummary = value);
        })
        .catchError((Object _) {});
  }

  Future<void> _chooseMyGroup() async {
    final groups = <int, ScheduleGroup>{
      for (final a in widget.accounts)
        if (a.groupId != null)
          a.groupId!: ScheduleGroup(
            id: a.groupId!,
            name: a.groupName ?? '${a.groupId}',
          ),
    };
    final preferred = _myGroup;
    if (preferred != null) {
      groups[preferred.id] = preferred;
    }
    try {
      for (final group
          in await ServerSessions.active?.groups() ?? <ScheduleGroup>[]) {
        groups[group.id] = group;
      }
    } catch (_) {
      /* Local groups and university search remain available offline. */
    }
    if (!mounted) return;
    final result = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => _SettingsChoicePage(
          title: tr(context, 'Моя группа', 'My group'),
          options: [
            _SettingsChoice(
              title: tr(context, 'Все группы', 'All groups').toLowerCase(),
              selected: _myGroup == null,
              value: 'all',
            ),
            for (final group in groups.values)
              _SettingsChoice(
                title: group.name,
                selected: group.id == _myGroup?.id,
                value: group,
              ),
            _SettingsChoice(
              title: tr(context, 'Найти группу', 'Find a group').toLowerCase(),
              selected: false,
              value: 'search',
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    ScheduleGroup? group;
    if (result == 'search') {
      group = await Navigator.of(context).push<ScheduleGroup>(
        MaterialPageRoute(
          builder: (_) =>
              GroupPickerPage(api: widget.scheduleApi ?? ScheduleApi()),
        ),
      );
      if (!mounted || group == null) return;
    } else if (result is ScheduleGroup) {
      group = result;
    }
    setState(() => _saving = true);
    try {
      await widget.store.saveMyGroup(group);
      final client = ServerSessions.active;
      client?.setGroupFilter(group?.id);
      if (client != null) {
        await ServerSessions.saveSnapshot();
        await SessionAutoSync.sync();
        client.watch();
        ServerSessions.notify();
      }
      if (mounted) setState(() => _myGroup = group);
    } catch (_) {
      if (mounted) {
        CampusNotice.show(
          context,
          message: tr(
            context,
            'Не удалось сохранить группу.',
            'Could not save group.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseSummary(bool enabled) async {
    if (_summarySaving || enabled == _daySummary) return;
    final previous = _daySummary;
    var committed = false;
    var nativeChanged = false;
    setState(() {
      _summaryTouched = true;
      _summarySaving = true;
      _daySummary = enabled;
    });
    try {
      if (enabled) {
        final allowed =
            await studySummaryChannel.invokeMethod<bool>('requestPermission') ??
            false;
        if (!allowed) {
          if (mounted) {
            CampusNotice.show(
              context,
              message: tr(
                context,
                'Разрешите уведомления в настройках Android.',
                'Allow notifications in Android settings.',
              ),
            );
          }
          return;
        }
      }
      await studySummaryChannel.invokeMethod('enable', {'enabled': enabled});
      nativeChanged = true;
      await widget.store.saveDaySummaryEnabled(enabled);
      committed = true;
      if (enabled) {
        final service = StudySummaryService(settings: widget.store);
        unawaited(
          service.sync().catchError((Object _) {}).whenComplete(service.close),
        );
      }
    } catch (_) {
      if (nativeChanged) {
        try {
          await studySummaryChannel.invokeMethod('enable', {
            'enabled': previous,
          });
          await widget.store.saveDaySummaryEnabled(previous);
        } catch (_) {
          // The original failure is reported below; retry remains available.
        }
      }
      if (mounted) {
        CampusNotice.show(
          context,
          message: tr(
            context,
            'Не удалось обновить расписание уведомлений. Повторите при подключении к сети.',
            'Could not update notification schedules. Retry when online.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (!committed) _daySummary = previous;
          _summarySaving = false;
        });
      }
    }
  }

  Future<void> _pinScanWidget() async {
    final compact = await showWidgetPreview(context, nfc: false);
    if (compact == null || !mounted) return;
    try {
      final supported = await const MethodChannel(
        'antiattendance/launcher_widget',
      ).invokeMethod<bool>('pinScanWidget', {'compact': compact});
      if (supported != true && mounted) {
        CampusNotice.show(
          context,
          message: tr(
            context,
            'Добавьте виджет через меню виджетов на главном экране.',
            'Add the widget from your home screen’s widget picker.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        CampusNotice.show(
          context,
          message: tr(
            context,
            'Не удалось добавить виджет.',
            'Could not add the widget.',
          ),
        );
      }
    }
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_saving) return;
    if (widget.language != oldWidget.language) _language = widget.language;
    if (widget.themeMode != oldWidget.themeMode) _themeMode = widget.themeMode;
  }

  Future<void> _choose(String? language) async {
    if (_saving || language == _language) return;
    setState(() => _saving = true);
    try {
      await widget.store.saveLanguage(language);
      if (!mounted) return;
      setState(() => _language = language);
      widget.onLanguageChanged(language);
    } catch (_) {
      if (!mounted) return;
      CampusNotice.show(
        context,
        message: tr(
          context,
          'Не удалось сохранить язык.',
          'Could not save language.',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseTheme(AppThemeMode mode) async {
    if (_saving || mode == _themeMode) return;
    final previous = _themeMode;
    setState(() {
      _saving = true;
      _themeMode = mode;
    });
    widget.onThemeModeChanged?.call(mode);
    try {
      await widget.store.saveThemeMode(mode);
    } catch (_) {
      if (mounted) {
        setState(() => _themeMode = previous);
        widget.onThemeModeChanged?.call(previous);
        _saveAppearanceError();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _saveAppearanceError() => CampusNotice.show(
    context,
    message: tr(
      context,
      'Не удалось сохранить оформление.',
      'Could not save appearance.',
    ),
  );

  static const _languages = <String, String>{
    'ru': 'Русский',
    'en': 'English',
    'fr': 'Français',
    'pt': 'Português',
    'zh': '简体中文',
  };

  Future<void> _openLanguages() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _SettingsChoicePage(
          title: tr(context, 'Язык приложения', 'App language'),
          options: [
            for (final entry in <String?, String>{
              null: tr(context, 'Как на телефоне', 'Use phone language'),
              ..._languages,
            }.entries)
              _SettingsChoice(
                title: entry.key == null
                    ? entry.value.toLowerCase()
                    : entry.value,
                selected: entry.key == _language,
                enabled: !_saving,
                value: entry.key ?? 'system',
                onSelected: () => _choose(entry.key),
              ),
          ],
        ),
      ),
    );
  }

  String _themeLabel(AppThemeMode mode) => switch (mode) {
    AppThemeMode.light => tr(context, 'Светлая', 'Light'),
    AppThemeMode.dark => tr(context, 'Тёмная', 'Dark'),
    AppThemeMode.amoled => tr(context, 'Чёрная (AMOLED)', 'Black (AMOLED)'),
  };
  Future<void> _openThemes() async {
    final mode = await showChoicePage<AppThemeMode>(
      context,
      title: tr(context, 'Оформление', 'Appearance'),
      options: [
        for (final mode in AppThemeMode.values)
          ChoiceOption(
            value: mode,
            label: _themeLabel(mode).toLowerCase(),
            selected: mode == _themeMode,
          ),
      ],
    );
    if (mounted && mode != null) await _chooseTheme(mode);
  }

  Future<void> _chooseSounds(bool value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.store.saveInterfaceSounds(value);
      if (mounted) {
        setState(() => _sounds = value);
        await BrockmannFeedbackScope.of(context)?.configure(
          mode: value ? BrockmannSoundMode.subtle : BrockmannSoundMode.off,
        );
      }
    } catch (_) {
      if (mounted) _saveAppearanceError();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openPage(Widget page) async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    try {
      final sounds = await widget.store.interfaceSounds();
      if (mounted) setState(() => _sounds = sounds);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => CampusScaffold(
    appBar: widget.embedded
        ? null
        : CampusAppBar(
            title: Text(tr(context, 'Настройки', 'Settings')),
            automaticallyImplyLeading: true,
          ),
    body: SettingsView(
      embedded: widget.embedded,
      sections: [
        SettingsSection(
          tr(context, 'Аккаунт и синхронизация', 'Account & sync'),
          [
            if (widget.serverManaged && ServerSessions.active != null)
              CampusListItem(
                showDivider: false,
                headline: tr(
                  context,
                  'Мой профиль',
                  'My profile',
                ).toLowerCase(),
                supportingText: tr(
                  context,
                  'Имя и username',
                  'Name and username',
                ),
                onTap: () => _openPage(
                  ServerProfilePage(api: AaServerApi(ServerSessions.active!)),
                ),
              ),
            if (!widget.serverManaged)
              CampusListItem(
                showDivider: false,
                headline: 'AA ID',
                supportingText: tr(
                  context,
                  'Ваш аккаунт, устройства и выход',
                  'Your account, devices and sign-out',
                ),
                onTap: () => _openPage(const AaIdAccountPage()),
              ),
            CampusListItem(
              showDivider: false,
              headline: tr(
                context,
                'Сервер сессий',
                'Session server',
              ).toLowerCase(),
              supportingText: tr(
                context,
                'Адрес сервера и автоматическая синхронизация',
                'Server address and automatic synchronization',
              ),
              onTap: () => _openPage(const SessionServerPage()),
            ),
            if (!widget.serverManaged) ...[
              CampusListItem(
                showDivider: false,
                headline: tr(context, 'Моя группа', 'My group').toLowerCase(),
                supportingText:
                    _myGroup?.name ??
                    tr(context, 'Все группы', 'All groups').toLowerCase(),
                onTap: _saving ? null : _chooseMyGroup,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: BrockmannText(
                  tr(
                    context,
                    'С сервера загружаются только аккаунты и пропуска выбранной группы.',
                    'Only the selected group’s accounts and passes are fetched from the server.',
                  ),
                  role: BrockmannType.caption,
                  color: context.brockmann.secondary,
                ),
              ),
            ],
          ],
        ),
        SettingsSection(tr(context, 'Оформление', 'Appearance'), [
          CampusListItem(
            headline: tr(context, 'Тема', 'Theme').toLowerCase(),
            supportingText: _themeLabel(_themeMode),
            onTap: _saving ? null : _openThemes,
          ),
          CampusListItem(
            showDivider: false,
            headline: tr(
              context,
              'Язык приложения',
              'App language',
            ).toLowerCase(),
            supportingText:
                _languages[_language] ??
                tr(context, 'Как на телефоне', 'Use phone language'),
            onTap: _saving ? null : _openLanguages,
          ),
          CampusListItem(
            headline: tr(
              context,
              'Звуки интерфейса',
              'Interface sounds',
            ).toLowerCase(),
            onTap: _saving ? null : () => _chooseSounds(!_sounds),
            trailing: CampusSwitch(
              label: tr(context, 'Звуки интерфейса', 'Interface sounds'),
              value: _sounds,
              onChanged: _saving ? null : _chooseSounds,
            ),
          ),
        ]),
        if (Theme.of(context).platform == TargetPlatform.android)
          SettingsSection(tr(context, 'Каждый день', 'Daily tools'), [
            CampusListItem(
              showDivider: false,
              headline: tr(
                context,
                'Итоги учебного дня',
                'Study day summary',
              ).toLowerCase(),
              supportingText: tr(
                context,
                'После последнего занятия: подтверждения каждого человека и истёкшие сессии.',
                'After the last class: each person’s confirmations and expired sessions.',
              ),
              trailing: CampusSwitch(
                label: tr(context, 'Итоги учебного дня', 'Study day summary'),
                value: _daySummary,
                onChanged: _summarySaving ? null : _chooseSummary,
              ),
              onTap: _summarySaving ? null : () => _chooseSummary(!_daySummary),
            ),
            CampusListItem(
              showDivider: false,
              headline: tr(
                context,
                'Последние итоги',
                'Last summary',
              ).toLowerCase(),
              onTap: _saving ? null : () => _openPage(const StudySummaryPage()),
            ),
            CampusListItem(
              showDivider: false,
              headline: tr(
                context,
                'Виджет отметки всех',
                'Mark-all widget',
              ).toLowerCase(),
              supportingText: tr(
                context,
                'Предпросмотр виджета',
                'Widget preview',
              ),
              onTap: _pinScanWidget,
            ),
          ]),
        SettingsSection(tr(context, 'Приложение', 'App'), [
          CampusListItem(
            headline: tr(context, 'Как пользоваться', 'How to use'),
            onTap: () => _openPage(
              Builder(
                builder: (context) => AppTutorial(
                  settings: widget.store,
                  language: _language,
                  themeMode: _themeMode,
                  onLanguageChanged: (value) {
                    setState(() => _language = value);
                    widget.onLanguageChanged(value);
                  },
                  onThemeModeChanged: (value) {
                    setState(() => _themeMode = value);
                    widget.onThemeModeChanged?.call(value);
                  },
                  onComplete: () async {
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ),
          ),
          if (widget.updates != null)
            AnimatedBuilder(
              animation: widget.updates!,
              builder: (context, _) => CampusListItem(
                showDivider: false,
                headline: tr(context, 'Обновления', 'Updates').toLowerCase(),
                supportingText: widget.updates!.updateAvailable
                    ? trf(
                        context,
                        'Доступна версия {version}',
                        'Version {version} is available',
                        {'version': widget.updates!.release!.tag},
                      )
                    : tr(context, 'Проверить', 'Check now'),
                onTap: () => _openPage(
                  UpdatesPage(
                    updates: widget.updates!,
                    downloadApk: widget.downloadApk,
                    installApk: widget.installApk,
                  ),
                ),
              ),
            ),
          CampusListItem(
            showDivider: false,
            headline: tr(
              context,
              'О AntiAttendance',
              'About AntiAttendance',
            ).toLowerCase(),
            onTap: () => _openPage(const AboutPage()),
          ),
        ]),
        if (!widget.serverManaged)
          SettingsSection(tr(context, 'Тестирование', 'Testing'), [
            CampusListItem(
              showDivider: false,
              headline: tr(
                context,
                'Проверка NFC',
                'NFC diagnostics',
              ).toLowerCase(),
              supportingText: tr(
                context,
                'Посмотреть сведения о найденном NFC-устройстве',
                'View detected NFC connection details',
              ),
              onTap: () => _openPage(const NfcDiagnosticsPage()),
            ),
            CampusListItem(
              showDivider: false,
              headline: tr(
                context,
                'Сигнал турникета',
                'Turnstile signal',
              ).toLowerCase(),
              supportingText: tr(
                context,
                'Посмотреть опрос NFC-считывателя',
                'Observe NFC reader polling',
              ),
              onTap: () => _openPage(const TurnstileProbePage()),
            ),
          ]),
      ],
    ),
  );
}

class _SettingsChoice {
  const _SettingsChoice({
    required this.title,
    required this.selected,
    required this.value,
    this.enabled = true,
    this.onSelected,
  });
  final String title;
  final bool selected, enabled;
  final Object value;
  final Future<void> Function()? onSelected;
}

class _SettingsChoicePage extends StatefulWidget {
  const _SettingsChoicePage({required this.title, required this.options});
  final String title;
  final List<_SettingsChoice> options;
  @override
  State<_SettingsChoicePage> createState() => _SettingsChoicePageState();
}

class _SettingsChoicePageState extends State<_SettingsChoicePage> {
  bool _choosing = false;
  @override
  Widget build(BuildContext context) => CampusScaffold(
    appBar: CampusAppBar(title: Text(widget.title)),
    body: SingleChildScrollView(
      padding: AaPageLayout.insets(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in widget.options)
            CampusListItem(
              showDivider: false,
              headline: option.title,
              trailing: option.selected
                  ? BrockmannGlyph(
                      BrockmannIcon.check,
                      size: 20,
                      color: context.brockmann.accent,
                    )
                  : null,
              onTap: option.enabled && !_choosing
                  ? () async {
                      if (_choosing) return;
                      setState(() => _choosing = true);
                      try {
                        await option.onSelected?.call();
                        if (context.mounted &&
                            (ModalRoute.of(context)?.isCurrent ?? false)) {
                          Navigator.of(context).pop(option.value);
                        }
                      } finally {
                        if (mounted) setState(() => _choosing = false);
                      }
                    }
                  : null,
            ),
        ],
      ),
    ),
  );
}
