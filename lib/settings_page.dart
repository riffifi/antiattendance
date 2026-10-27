import 'updates_page.dart';
import 'session_server_page.dart';
import 'aa_id_page.dart';
import 'expressive.dart';
import 'campus_design.dart';

import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'about_page.dart';
import 'app_settings.dart';
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
    this.updates,
    this.downloadApk,
    this.installApk,
    this.scheduleApi,
    this.accounts = const [],
  });

  final bool embedded;
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
  bool _daySummary = false;
  bool _summarySaving = false;
  bool _summaryTouched = false;
  ScheduleGroup? _myGroup;

  @override
  void initState() {
    super.initState();
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
    final result = await showExpressiveSheet<Object>(
      context: context,
      compact: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CampusSectionTitle(tr(context, 'Моя группа', 'My group')),
            CampusListItem(
              headline: tr(context, 'Все группы', 'All groups'),
              selected: _myGroup == null,
              onTap: () => Navigator.pop(context, 'all'),
            ),
            for (final group in groups.values)
              CampusListItem(
                headline: group.name,
                selected: group.id == _myGroup?.id,
                onTap: () => Navigator.pop(context, group),
              ),
            CampusListItem(
              headline: tr(context, 'Найти группу', 'Find a group'),
              onTap: () => Navigator.pop(context, 'search'),
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
    await showExpressiveSheet<void>(
      context: context,
      compact: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: CampusSectionTitle(
                tr(context, 'Язык приложения', 'App language'),
              ),
            ),
            for (final entry in <String?, String>{
              null: tr(context, 'Как на телефоне', 'Use phone language'),
              ..._languages,
            }.entries)
              _Choice(
                title: entry.value,
                selected: entry.key == _language,
                onTap: _saving
                    ? null
                    : () async {
                        await _choose(entry.key);
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded
        ? null
        : CampusAppBar(
            title: Text(tr(context, 'Настройки', 'Settings')),
            automaticallyImplyLeading: true,
          ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              if (widget.embedded)
                CampusHeader(title: tr(context, 'Настройки', 'Settings')),
              CampusSectionTitle(tr(context, 'Моя группа', 'My group')),
              CampusPanel(
                padding: EdgeInsets.zero,
                child: CampusListItem(
                  headline:
                      _myGroup?.name ?? tr(context, 'Все группы', 'All groups'),
                  supportingText: tr(
                    context,
                    'С сервера загружаются только аккаунты и пропуска выбранной группы.',
                    'Only the selected group’s accounts and passes are fetched from the server.',
                  ),
                  onTap: _saving ? null : _chooseMyGroup,
                ),
              ),
              const SizedBox(height: 28),
              CampusSectionTitle(tr(context, 'Оформление', 'Appearance')),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (mode, title) in [
                      (AppThemeMode.light, tr(context, 'Светлая', 'Light')),
                      (AppThemeMode.dark, tr(context, 'Тёмная', 'Dark')),
                      (
                        AppThemeMode.amoled,
                        tr(context, 'Чёрная (AMOLED)', 'Black (AMOLED)'),
                      ),
                    ])
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: mode == AppThemeMode.amoled ? 0 : 8,
                          ),
                          child: _ThemePreview(
                            mode: mode,
                            title: title,
                            selected: mode == _themeMode,
                            onTap: _saving ? null : () => _chooseTheme(mode),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 28),
              Text(
                tr(context, 'Язык приложения', 'App language'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  context,
                  'По умолчанию — язык телефона.',
                  'Your phone language is used by default.',
                ),
                style: TextStyle(color: context.palette.muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              CampusPanel(
                padding: EdgeInsets.zero,
                child: CampusListItem(
                  headline:
                      _languages[_language] ??
                      tr(context, 'Как на телефоне', 'Use phone language'),
                  onTap: _saving ? null : _openLanguages,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                tr(context, 'Тестирование', 'Testing'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              CampusPanel(
                padding: EdgeInsets.zero,
                child: CampusListItem(
                  headline: (tr(context, 'Проверка NFC', 'NFC diagnostics')),
                  supportingText: (tr(
                    context,
                    'Посмотреть сведения о найденном NFC-устройстве',
                    'View detected NFC connection details',
                  )),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const NfcDiagnosticsPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              CampusPanel(
                padding: EdgeInsets.zero,
                child: CampusListItem(
                  headline: (tr(
                    context,
                    'Сигнал турникета',
                    'Turnstile signal',
                  )),
                  supportingText: (tr(
                    context,
                    'Посмотреть опрос NFC-считывателя',
                    'Observe NFC reader polling',
                  )),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const TurnstileProbePage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                tr(context, 'Приложение', 'App'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              CampusPanel(
                padding: EdgeInsets.zero,
                child: CampusListItem(
                  headline: tr(context, 'Сервер сессий', 'Session server'),
                  supportingText: tr(
                    context,
                    'Адрес сервера и автоматическая синхронизация',
                    'Server address and automatic synchronization',
                  ),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const SessionServerPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (Theme.of(context).platform == TargetPlatform.android) ...[
                CampusPanel(
                  padding: EdgeInsets.zero,
                  child: CampusListItem(
                    headline: tr(
                      context,
                      'Итоги учебного дня',
                      'Study day summary',
                    ),
                    supportingText: tr(
                      context,
                      'После последнего занятия: подтверждения каждого человека и истёкшие сессии.',
                      'After the last class: each person’s confirmations and expired sessions.',
                    ),
                    trailing: CampusSwitch(
                      value: _daySummary,
                      onChanged: _summarySaving ? null : _chooseSummary,
                    ),
                    onTap: _summarySaving
                        ? null
                        : () => _chooseSummary(!_daySummary),
                  ),
                ),
                CampusButton.text(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const StudySummaryPage(),
                          ),
                        ),
                  child: Text(tr(context, 'Последние итоги', 'Last summary')),
                ),
                CampusPanel(
                  padding: EdgeInsets.zero,
                  child: CampusListItem(
                    headline: tr(
                      context,
                      'Виджет отметки всех',
                      'Mark-all widget',
                    ),
                    supportingText: tr(
                      context,
                      'Предпросмотр виджета',
                      'Widget preview',
                    ),
                    onTap: _pinScanWidget,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              CampusPanel(
                padding: EdgeInsets.zero,
                child: CampusListItem(
                  headline: 'AA ID',
                  supportingText: tr(
                    context,
                    'Ваш аккаунт, устройства и выход',
                    'Your account, devices and sign-out',
                  ),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const AaIdAccountPage()),
                  ),
                ),
              ),
              if (widget.updates != null) ...[
                const SizedBox(height: 24),
                AnimatedBuilder(
                  animation: widget.updates!,
                  builder: (context, _) => CampusPanel(
                    padding: EdgeInsets.zero,
                    child: CampusListItem(
                      headline: tr(context, 'Обновления', 'Updates'),
                      supportingText: widget.updates!.updateAvailable
                          ? trf(
                              context,
                              'Доступна версия {version}',
                              'Version {version} is available',
                              {'version': widget.updates!.release!.tag},
                            )
                          : tr(context, 'Проверить', 'Check now'),
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => UpdatesPage(
                            updates: widget.updates!,
                            downloadApk: widget.downloadApk,
                            installApk: widget.installApk,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              CampusPanel(
                padding: EdgeInsets.zero,
                child: CampusListItem(
                  headline: (tr(
                    context,
                    'О AntiAttendance',
                    'About AntiAttendance',
                  )),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const AboutPage()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? context.palette.selected : context.palette.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: selected
              ? context.palette.blue.withValues(alpha: .4)
              : context.palette.line,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.zero,
        child: CampusListItem(
          selected: selected,
          headline: title,
          trailing: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 140),
            child: Text(selected ? '×' : '', key: ValueKey(selected)),
          ),
          onTap: onTap,
        ),
      ),
    ),
  );
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({
    required this.mode,
    required this.title,
    required this.selected,
    required this.onTap,
  });
  final AppThemeMode mode;
  final String title;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final preview = AppTheme.build(mode);
    return Semantics(
      selected: selected,
      child: EditorialAction(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Container(
                height: 92,
                decoration: BoxDecoration(
                  color: preview.scaffoldBackgroundColor,
                  border: Border.all(
                    color: selected
                        ? context.palette.ink
                        : context.palette.line,
                    width: selected ? 1.5 : .5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: preview.colorScheme.outlineVariant,
                            width: .5,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Aa',
                            style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 32,
                              fontWeight: FontWeight.w300,
                              color: preview.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(title, style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
