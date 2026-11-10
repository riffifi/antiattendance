import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import 'campus_design.dart';
import 'l10n.dart';
import 'app_settings.dart';
import 'app_theme.dart';
import 'expressive.dart';

/// A local, skippable introduction. It never signs in or submits attendance.
class AppTutorial extends StatefulWidget {
  const AppTutorial({
    super.key,
    required this.onComplete,
    this.settings,
    this.language,
    this.themeMode = AppThemeMode.light,
    this.onLanguageChanged,
    this.onThemeModeChanged,
  });
  final AppSettingsStore? settings;
  final String? language;
  final AppThemeMode themeMode;
  final ValueChanged<String?>? onLanguageChanged;
  final ValueChanged<AppThemeMode>? onThemeModeChanged;
  final Future<void> Function() onComplete;
  @override
  State<AppTutorial> createState() => _AppTutorialState();
}

class _AppTutorialState extends State<AppTutorial> {
  final _pages = PageController();
  int _step = 0;
  bool _finishing = false;
  bool _saving = false, _sounds = true;
  late String? _language = widget.language;
  late AppThemeMode _theme = widget.themeMode;
  AppSettingsStore get _store => widget.settings ?? AppSettingsStore();
  static const languages = {
    'ru': 'Русский',
    'en': 'English',
    'fr': 'Français',
    'pt': 'Português',
    'zh': '简体中文',
  };
  @override
  void initState() {
    super.initState();
    _store
        .interfaceSounds()
        .then((v) {
          if (mounted) setState(() => _sounds = v);
        })
        .catchError((Object _) {});
  }

  String _themeLabel(AppThemeMode mode) => switch (mode) {
    AppThemeMode.light => tr(context, 'Светлая', 'Light'),
    AppThemeMode.dark => tr(context, 'Тёмная', 'Dark'),
    AppThemeMode.amoled => tr(context, 'Чёрная (AMOLED)', 'Black (AMOLED)'),
  };
  Future<void> _chooseLanguage() async {
    final choice = await showChoicePage<String>(
      context,
      title: tr(context, 'Язык приложения', 'App language'),
      options: [
        ChoiceOption(
          value: 'system',
          label: tr(context, 'Как на телефоне', 'Use phone language'),
          selected: _language == null,
        ),
        for (final entry in languages.entries)
          ChoiceOption(
            value: entry.key,
            label: entry.value,
            selected: entry.key == _language,
          ),
      ],
    );
    if (!mounted || choice == null) return;
    setState(() => _saving = true);
    try {
      final value = choice == 'system' ? null : choice;
      await _store.saveLanguage(value);
      if (mounted) {
        setState(() => _language = value);
        widget.onLanguageChanged?.call(value);
      }
    } catch (_) {
      if (mounted) {
        CampusNotice.show(
          context,
          message: tr(
            context,
            'Не удалось сохранить язык.',
            'Could not save language.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseTheme() async {
    final mode = await showChoicePage<AppThemeMode>(
      context,
      title: tr(context, 'Оформление', 'Appearance'),
      options: [
        for (final mode in AppThemeMode.values)
          ChoiceOption(
            value: mode,
            label: _themeLabel(mode),
            selected: _theme == mode,
          ),
      ],
    );
    if (!mounted || mode == null) return;
    setState(() => _saving = true);
    try {
      await _store.saveThemeMode(mode);
      if (mounted) {
        setState(() => _theme = mode);
        widget.onThemeModeChanged?.call(mode);
      }
    } catch (_) {
      if (mounted) {
        CampusNotice.show(
          context,
          message: tr(
            context,
            'Не удалось сохранить оформление.',
            'Could not save appearance.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setSounds(bool value) async {
    setState(() => _saving = true);
    try {
      await _store.saveInterfaceSounds(value);
      if (!mounted) return;
      setState(() => _sounds = value);
      await BrockmannFeedbackScope.of(context)?.configure(
        mode: value ? BrockmannSoundMode.subtle : BrockmannSoundMode.off,
      );
    } catch (_) {
      if (mounted) {
        CampusNotice.show(
          context,
          message: tr(
            context,
            'Не удалось сохранить оформление.',
            'Could not save appearance.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finish() async {
    if (_finishing || _saving) return;
    setState(() => _finishing = true);
    try {
      await widget.onComplete();
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      (
        tr(context, 'Добро пожаловать в AA', 'Welcome to AA'),
        tr(
          context,
          'Выберите язык и оформление. Всё это можно изменить в настройках позже.',
          'Choose your language and appearance. You can change these later in Settings.',
        ),
      ),
      (
        'AA ID',
        tr(
          context,
          'Войдите через МИРЭА один раз. AA ID подключит вашу группу и доступные вам данные. Пароли в приложении вводить не нужно.',
          'Sign in with MIREA once. AA ID connects your group and the data you can access. You do not need to enter a password in the app.',
        ),
      ),
      (
        tr(context, 'Посещаемость', 'Attendance'),
        tr(
          context,
          'Проверьте занятие, выберите людей и нажмите сканирование внизу. Сканируйте QR именно этого занятия. Серые аккаунты требуют повторного входа владельца.',
          'Check the class, select people, then tap Scan at the bottom. Scan that class’s QR code. Grey accounts need their owner to sign in again.',
        ),
      ),
      (
        tr(context, 'Расписание', 'Schedule'),
        tr(
          context,
          'Проводите по экрану или заголовкам, чтобы менять раздел. В расписании выбирайте день, а нажатие на аудиторию откроет карту.',
          'Swipe the screen or its headings to switch sections. Choose a day in Schedule; tap a room to open the map.',
        ),
      ),
      (
        tr(context, 'NFC-пропуска', 'NFC passes'),
        tr(
          context,
          'Откройте пропуска и нажмите значок NFC внизу. Выберите один пропуск или очередь. Владелец выдаёт доступ; для прохода держите экран открытым, а телефон разблокированным. Три точки на панели раскрывают подписи команд.',
          'Open Passes and tap NFC at the bottom. Choose one pass or a queue. The owner grants access; keep the screen open and the phone unlocked at the gate. The app bar’s three dots reveal command labels.',
        ),
      ),
    ];
    return CampusScaffold(
      appBar: CampusAppBar(
        title: _step == 0
            ? const Align(
                alignment: Alignment.centerLeft,
                child: CampusBrand(width: 64),
              )
            : Text(tr(context, 'Как пользоваться', 'How to use')),
        compact: _step == 0,
        automaticallyImplyLeading: false,
        actions: [
          CampusTextAction(
            label: tr(context, 'Пропустить', 'Skip'),
            onPressed: _finishing || _saving ? null : _finish,
          ),
        ],
      ),
      bottomNavigationBar: ColoredBox(
        color: context.brockmann.background,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Wrap(
              alignment: _step == 0
                  ? WrapAlignment.end
                  : WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                if (_step > 0)
                  CampusButton.text(
                    onPressed: _finishing || _saving
                        ? null
                        : () => _pages.previousPage(
                            duration: context.brockmann.pivotDuration(context),
                            curve: Curves.easeOutCubic,
                          ),
                    child: Text(tr(context, 'Назад', 'Back')),
                  ),
                CampusButton.filled(
                  onPressed: _finishing || _saving
                      ? null
                      : _step == steps.length - 1
                      ? _finish
                      : () => _pages.nextPage(
                          duration: context.brockmann.pivotDuration(context),
                          curve: Curves.easeOutCubic,
                        ),
                  child: Text(
                    _step == steps.length - 1
                        ? tr(context, 'Начать', 'Get started')
                        : tr(context, 'Далее', 'Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Semantics(
              liveRegion: true,
              child: BrockmannText(
                '${_step + 1} / ${steps.length}',
                role: BrockmannType.caption,
                color: context.brockmann.secondary,
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: steps.length,
              onPageChanged: (index) => setState(() => _step = index),
              itemBuilder: (context, i) => ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                children: [
                  BrockmannText(
                    steps[i].$1.toLowerCase(),
                    role: BrockmannType.title,
                  ),
                  const SizedBox(height: 24),
                  BrockmannText(steps[i].$2),
                  if (i == 0) ...[
                    const SizedBox(height: 24),
                    CampusListItem(
                      key: const ValueKey('oobe-language'),
                      headline: tr(context, 'Язык приложения', 'App language'),
                      supportingText:
                          languages[_language] ??
                          tr(context, 'Как на телефоне', 'Use phone language'),
                      onTap: _saving ? null : _chooseLanguage,
                    ),
                    CampusListItem(
                      key: const ValueKey('oobe-theme'),
                      headline: tr(context, 'Тема', 'Theme'),
                      supportingText: _themeLabel(_theme),
                      onTap: _saving ? null : _chooseTheme,
                    ),
                    CampusListItem(
                      headline: tr(
                        context,
                        'Звуки интерфейса',
                        'Interface sounds',
                      ),
                      onTap: _saving ? null : () => _setSounds(!_sounds),
                      trailing: CampusSwitch(
                        label: tr(
                          context,
                          'Звуки интерфейса',
                          'Interface sounds',
                        ),
                        value: _sounds,
                        onChanged: _saving ? null : _setSounds,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
