import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'about_page.dart';
import 'apk_update.dart';
import 'app_settings.dart';
import 'app_theme.dart';
import 'external_links.dart';
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
  bool _downloading = false;
  double? _downloadProgress;

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

  Future<File> _downloadApk(
    AppRelease release,
    void Function(int received, int? total) onProgress,
  ) async {
    final downloader = ApkUpdateDownloader();
    try {
      return await downloader.download(release, onProgress: onProgress);
    } finally {
      downloader.close();
    }
  }

  Future<void> _downloadAndInstall(AppRelease release) async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _downloadProgress = null;
    });
    try {
      final apk = await (widget.downloadApk ?? _downloadApk)(release, (
        received,
        total,
      ) {
        if (!mounted) return;
        final next = total == null || total == 0
            ? null
            : (received / total).clamp(0.0, 1.0);
        if (next == null && _downloadProgress == null ||
            next != null &&
                _downloadProgress != null &&
                (next * 100).floor() == (_downloadProgress! * 100).floor()) {
          return;
        }
        setState(() {
          _downloadProgress = next;
        });
      });
      if (!mounted) return;
      await (widget.installApk ?? openAndroidInstaller)(apk);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Подтвердите установку в Android.',
              'Confirm installation in Android.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Не удалось скачать или установить обновление.',
              'Could not download or install the update.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadProgress = null;
        });
      }
    }
  }

  Future<void> _openRelease(Uri uri) async {
    if (!await openWebPage(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                'Не удалось открыть GitHub.',
                'Could not open GitHub.',
              ),
            ),
          ),
        );
      }
    }
  }

  String _updateStatus(UpdateController updates) {
    if (updates.checking) {
      return tr(context, 'Проверяем обновления…', 'Checking for updates…');
    }
    if (updates.error != null) {
      return tr(
        context,
        'Не удалось проверить обновления.',
        'Could not check for updates.',
      );
    }
    if (!updates.checked) {
      return tr(context, 'Ещё не проверяли', 'Not checked yet');
    }
    if (updates.release == null) {
      return tr(context, 'Обновлений пока нет', 'No releases yet');
    }
    if (updates.updateAvailable) {
      return trf(
        context,
        'Доступна версия {version}',
        'Version {version} is available',
        {'version': updates.release!.tag},
      );
    }
    return tr(context, 'У вас последняя версия', 'You have the latest version');
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Не удалось сохранить язык.',
              'Could not save language.',
            ),
          ),
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

  void _saveAppearanceError() => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        tr(
          context,
          'Не удалось сохранить оформление.',
          'Could not save appearance.',
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'Настройки', 'Settings'))),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Text(
              tr(context, 'Оформление', 'Appearance'),
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _Choice(
              title: tr(context, 'Светлая', 'Light'),
              selected: _themeMode == AppThemeMode.light,
              onTap: _saving ? null : () => _chooseTheme(AppThemeMode.light),
            ),
            _Choice(
              title: tr(context, 'Тёмная', 'Dark'),
              selected: _themeMode == AppThemeMode.dark,
              onTap: _saving ? null : () => _chooseTheme(AppThemeMode.dark),
            ),
            _Choice(
              title: tr(context, 'Чёрная (AMOLED)', 'Black (AMOLED)'),
              selected: _themeMode == AppThemeMode.amoled,
              onTap: _saving ? null : () => _chooseTheme(AppThemeMode.amoled),
            ),
            if (Platform.isAndroid || widget.monetAvailable)
              Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                child: SwitchListTile.adaptive(
                  value: _monetEnabled && widget.monetAvailable,
                  onChanged: _saving || !widget.monetAvailable
                      ? null
                      : _chooseMonet,
                  title: Text(
                    tr(context, 'Цвета телефона', 'Phone colors (Monet)'),
                  ),
                  subtitle: Text(
                    widget.monetAvailable
                        ? tr(
                            context,
                            'Цвет оформления подстраивается под обои.',
                            'Use your wallpaper colors for any theme.',
                          )
                        : tr(
                            context,
                            'Доступно на Android 12 и новее.',
                            'Available on Android 12 and newer.',
                          ),
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
            _Choice(
              title: tr(context, 'Как на телефоне', 'Use phone language'),
              subtitle: tr(context, 'Автоматически', 'Automatic'),
              selected: _language == null,
              onTap: _saving ? null : () => _choose(null),
            ),
            _Choice(
              title: 'Русский',
              selected: _language == 'ru',
              onTap: _saving ? null : () => _choose('ru'),
            ),
            _Choice(
              title: 'English',
              selected: _language == 'en',
              onTap: _saving ? null : () => _choose('en'),
            ),
            _Choice(
              title: 'Français',
              selected: _language == 'fr',
              onTap: _saving ? null : () => _choose('fr'),
            ),
            _Choice(
              title: 'Português',
              selected: _language == 'pt',
              onTap: _saving ? null : () => _choose('pt'),
            ),
            _Choice(
              title: '简体中文',
              selected: _language == 'zh',
              onTap: _saving ? null : () => _choose('zh'),
            ),
            const SizedBox(height: 28),
            if (widget.updates != null) ...[
              Text(
                tr(context, 'Обновления', 'Updates'),
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              AnimatedBuilder(
                animation: widget.updates!,
                builder: (context, _) {
                  final updates = widget.updates!;
                  final release = updates.release;
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.palette.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              updates.updateAvailable
                                  ? Icons.system_update_rounded
                                  : Icons.check_circle_outline_rounded,
                              color: context.palette.blue,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _updateStatus(updates),
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        if (updates.installedVersion != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            trf(
                              context,
                              'Установлена версия {version}',
                              'Installed: {version}',
                              {'version': updates.installedVersion!},
                            ),
                            style: TextStyle(
                              color: context.palette.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            TextButton.icon(
                              onPressed: updates.checking
                                  ? null
                                  : () => unawaited(updates.check()),
                              icon: Icon(Icons.refresh_rounded, size: 18),
                              label: Text(
                                tr(context, 'Проверить', 'Check now'),
                              ),
                            ),
                            if (updates.updateAvailable && release != null)
                              FilledButton.icon(
                                onPressed: _downloading
                                    ? null
                                    : Platform.isAndroid && release.apk != null
                                    ? () => _downloadAndInstall(release)
                                    : () => _openRelease(release.page),
                                style: FilledButton.styleFrom(
                                  disabledBackgroundColor: context.palette.blue,
                                  disabledForegroundColor:
                                      context.palette.onBlue,
                                ),
                                icon: _downloading
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: context.palette.onBlue,
                                        ),
                                      )
                                    : Icon(
                                        Platform.isAndroid &&
                                                release.apk != null
                                            ? Icons.system_update_rounded
                                            : Icons.open_in_new_rounded,
                                        size: 18,
                                      ),
                                label: Text(
                                  _downloading
                                      ? _downloadProgress == null
                                            ? tr(
                                                context,
                                                'Скачиваем…',
                                                'Downloading…',
                                              )
                                            : trf(
                                                context,
                                                'Скачиваем: {percent}%',
                                                'Downloading {percent}%',
                                                {
                                                  'percent':
                                                      (_downloadProgress! * 100)
                                                          .round(),
                                                },
                                              )
                                      : Platform.isAndroid &&
                                            release.apk != null
                                      ? tr(
                                          context,
                                          'Установить обновление',
                                          'Install update',
                                        )
                                      : tr(
                                          context,
                                          'Открыть релиз',
                                          'Open release',
                                        ),
                                ),
                              ),
                            if (updates.updateAvailable &&
                                release != null &&
                                Platform.isAndroid &&
                                release.apk != null)
                              TextButton(
                                onPressed: () => _openRelease(release.page),
                                child: Text(
                                  tr(
                                    context,
                                    'Страница релиза',
                                    'Release page',
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (_downloading) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: _downloadProgress),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),
            ],
            Text(
              tr(context, 'Тестирование', 'Testing'),
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Material(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Icon(Icons.nfc_rounded, color: context.palette.blue),
                title: Text(tr(context, 'Проверка NFC', 'NFC diagnostics')),
                subtitle: Text(
                  tr(
                    context,
                    'Посмотреть сведения о найденном NFC-устройстве',
                    'View detected NFC connection details',
                  ),
                ),
                trailing: Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const NfcDiagnosticsPage()),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Icon(
                  Icons.sensors_rounded,
                  color: context.palette.blue,
                ),
                title: Text(
                  tr(context, 'Сигнал турникета', 'Turnstile signal'),
                ),
                subtitle: Text(
                  tr(
                    context,
                    'Посмотреть опрос NFC-считывателя',
                    'Observe NFC reader polling',
                  ),
                ),
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
            Material(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Icon(
                  Icons.info_outline_rounded,
                  color: context.palette.blue,
                ),
                title: Text(
                  tr(context, 'О AntiAttendance', 'About AntiAttendance'),
                ),
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
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: selected ? context.palette.selected : context.palette.surface,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: Icon(
          selected ? Icons.check_circle_rounded : Icons.circle_outlined,
          color: selected ? context.palette.blue : context.palette.muted,
        ),
        onTap: onTap,
      ),
    ),
  );
}
