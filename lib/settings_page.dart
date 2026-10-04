import 'updates_page.dart';
import 'expressive.dart';
import 'campus_design.dart';

import 'package:material_3_expressive/material_3_expressive.dart';

import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'about_page.dart';
import 'app_settings.dart';
import 'app_theme.dart';
import 'l10n.dart';
import 'nfc_diagnostics_page.dart';
import 'turnstile_probe_page.dart';
import 'update_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.store,
    required this.language,
    required this.onLanguageChanged,
    this.themeMode = AppThemeMode.light,
    this.onThemeModeChanged,
    this.monetEnabled = false,
    this.monetAvailable = false,
    this.onMonetChanged,
    this.updates,
    this.downloadApk,
    this.installApk,
  });

  final AppSettingsStore store;
  final String? language;
  final ValueChanged<String?> onLanguageChanged;
  final AppThemeMode themeMode;
  final ValueChanged<AppThemeMode>? onThemeModeChanged;
  final bool monetEnabled;
  final bool monetAvailable;
  final ValueChanged<bool>? onMonetChanged;
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
  late bool _monetEnabled = widget.monetEnabled;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_saving) return;
    if (widget.language != oldWidget.language) _language = widget.language;
    if (widget.themeMode != oldWidget.themeMode) _themeMode = widget.themeMode;
    if (widget.monetEnabled != oldWidget.monetEnabled) {
      _monetEnabled = widget.monetEnabled;
    }
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
      M3ESnackbar.show(
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
    setState(() => _saving = true);
    try {
      await widget.store.saveThemeMode(mode);
      if (!mounted) return;
      setState(() => _themeMode = mode);
      widget.onThemeModeChanged?.call(mode);
    } catch (_) {
      if (mounted) _saveAppearanceError();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseMonet(bool enabled) async {
    if (_saving || !widget.monetAvailable) return;
    setState(() => _saving = true);
    try {
      await widget.store.saveMonetEnabled(enabled);
      if (!mounted) return;
      setState(() => _monetEnabled = enabled);
      widget.onMonetChanged?.call(enabled);
    } catch (_) {
      if (mounted) _saveAppearanceError();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _saveAppearanceError() => M3ESnackbar.show(
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
    appBar: AppBar(
      title: Text(tr(context, 'Настройки', 'Settings')),
      automaticallyImplyLeading: true,
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
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
                          seed: _monetEnabled
                              ? Theme.of(context).colorScheme.primary
                              : null,
                          onTap: _saving ? null : () => _chooseTheme(mode),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (Platform.isAndroid || widget.monetAvailable)
              CampusPanel(
                padding: EdgeInsets.zero,
                child: CampusListItem(
                  headline: (tr(
                    context,
                    'Цвета телефона',
                    'Phone colors (Monet)',
                  )),
                  supportingText: (widget.monetAvailable
                      ? tr(
                          context,
                          'Цвет оформления подстраивается под обои.',
                          'Use your wallpaper colors for any theme.',
                        )
                      : tr(
                          context,
                          'Доступно на Android 12 и новее.',
                          'Available on Android 12 and newer.',
                        )),
                  onTap: _saving || !widget.monetAvailable
                      ? null
                      : () => _chooseMonet(!_monetEnabled),
                  trailing: M3ESwitch(
                    value: _monetEnabled && widget.monetAvailable,
                    onChanged: _saving || !widget.monetAvailable
                        ? null
                        : _chooseMonet,
                  ),
                ),
              ),
            const SizedBox(height: 28),
            Text(
              tr(context, 'Язык приложения', 'App language'),
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
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
                leading: Icon(
                  Icons.language_rounded,
                  color: context.palette.blue,
                ),
                trailing: const Icon(Icons.unfold_more_rounded),
                onTap: _saving ? null : _openLanguages,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              tr(context, 'Тестирование', 'Testing'),
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            CampusPanel(
              padding: EdgeInsets.zero,
              child: CampusListItem(
                leading: Icon(Icons.nfc_rounded, color: context.palette.blue),
                headline: (tr(context, 'Проверка NFC', 'NFC diagnostics')),
                supportingText: (tr(
                  context,
                  'Посмотреть сведения о найденном NFC-устройстве',
                  'View detected NFC connection details',
                )),
                trailing: Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const NfcDiagnosticsPage()),
                ),
              ),
            ),
            const SizedBox(height: 12),
            CampusPanel(
              padding: EdgeInsets.zero,
              child: CampusListItem(
                leading: Icon(
                  Icons.sensors_rounded,
                  color: context.palette.blue,
                ),
                headline: (tr(context, 'Сигнал турникета', 'Turnstile signal')),
                supportingText: (tr(
                  context,
                  'Посмотреть опрос NFC-считывателя',
                  'Observe NFC reader polling',
                )),
                trailing: Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const TurnstileProbePage()),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              tr(context, 'Приложение', 'App'),
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (widget.updates != null) ...[
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
                    leading: Badge(
                      isLabelVisible: widget.updates!.updateAvailable,
                      child: Icon(
                        Icons.system_update_rounded,
                        color: context.palette.blue,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
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
                leading: Icon(
                  Icons.info_outline_rounded,
                  color: context.palette.blue,
                ),
                headline: (tr(
                  context,
                  'О AntiAttendance',
                  'About AntiAttendance',
                )),
                trailing: Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                ),
              ),
            ),
          ],
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? context.palette.blue.withValues(alpha: .4)
              : context.palette.line,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: CampusListItem(
          selected: selected,
          headline: title,
          trailing: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 140),
            child: Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              key: ValueKey(selected),
              color: selected ? context.palette.blue : context.palette.muted,
            ),
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
    this.seed,
  });
  final AppThemeMode mode;
  final String title;
  final bool selected;
  final VoidCallback? onTap;
  final Color? seed;
  @override
  Widget build(BuildContext context) {
    final preview = AppTheme.build(mode, monetSeed: seed);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    return Semantics(
      selected: selected,
      button: true,
      child: CampusPressable(
        enabled: onTap != null,
        child: AnimatedContainer(
          duration: duration,
          decoration: BoxDecoration(
            color: selected
                ? context.palette.selected
                : context.palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? context.palette.blue : context.palette.line,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        height: 92,
                        width: double.infinity,
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: preview.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: preview.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 22,
                              height: 4,
                              color: preview.colorScheme.onSurface,
                            ),
                            const SizedBox(height: 10),
                            Container(
                              height: 17,
                              decoration: BoxDecoration(
                                color: preview.colorScheme.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              height: 17,
                              decoration: BoxDecoration(
                                color: preview.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const Spacer(),
                            Row(
                              children: [
                                for (var i = 0; i < 3; i++)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      child: Container(
                                        height: 5,
                                        color: i == 0
                                            ? preview.colorScheme.primary
                                            : preview
                                                  .colorScheme
                                                  .outlineVariant,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.palette.ink,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: duration,
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        key: ValueKey(selected),
                        size: 20,
                        color: selected
                            ? context.palette.blue
                            : context.palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
