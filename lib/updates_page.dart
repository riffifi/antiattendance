import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import 'apk_update.dart';
import 'app_theme.dart';
import 'campus_design.dart';
import 'external_links.dart';
import 'l10n.dart';
import 'update_service.dart';

class UpdatesPage extends StatefulWidget {
  const UpdatesPage({
    super.key,
    required this.updates,
    this.downloadApk,
    this.installApk,
  });
  final UpdateController updates;
  final Future<File> Function(AppRelease, void Function(int, int?))?
  downloadApk;
  final Future<void> Function(File)? installApk;
  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  bool _downloading = false;
  double? _downloadProgress;
  @override
  void initState() {
    super.initState();
    if (!widget.updates.checked && !widget.updates.checking) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(widget.updates.check());
      });
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
      M3ESnackbar.show(
        context,
        message: tr(
          context,
          'Подтвердите установку в Android.',
          'Confirm installation in Android.',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      M3ESnackbar.show(
        context,
        message: tr(
          context,
          'Не удалось скачать или установить обновление.',
          'Could not download or install the update.',
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
        M3ESnackbar.show(
          context,
          message: tr(
            context,
            'Не удалось открыть GitHub.',
            'Could not open GitHub.',
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.updates,
    builder: (context, _) {
      final updates = widget.updates;
      final release = updates.release;
      final available = updates.updateAvailable && release != null;
      return Scaffold(
        appBar: AppBar(
          title: Text(tr(context, 'Обновления', 'Updates')),
          actions: [
            IconButton(
              onPressed: updates.checking ? null : () => updates.check(),
              tooltip: tr(context, 'Обновить', 'Refresh'),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_downloading) ...[
                      LinearProgressIndicator(value: _downloadProgress),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: CampusButton.icon(
                        onPressed: _downloading || updates.checking
                            ? null
                            : available
                            ? Platform.isAndroid && release.apk != null
                                  ? () => _downloadAndInstall(release)
                                  : () => _openRelease(release.page)
                            : () => updates.check(),
                        icon: Icon(
                          available
                              ? Icons.system_update_rounded
                              : Icons.refresh_rounded,
                        ),
                        label: Text(
                          _downloading
                              ? _downloadProgress == null
                                    ? tr(context, 'Скачиваем…', 'Downloading…')
                                    : trf(
                                        context,
                                        'Скачиваем: {percent}%',
                                        'Downloading {percent}%',
                                        {
                                          'percent': (_downloadProgress! * 100)
                                              .round(),
                                        },
                                      )
                              : available
                              ? Platform.isAndroid && release.apk != null
                                    ? tr(
                                        context,
                                        'Установить обновление',
                                        'Install update',
                                      )
                                    : tr(
                                        context,
                                        'Открыть релиз',
                                        'Open release',
                                      )
                              : tr(context, 'Проверить', 'Check now'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              children: [
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: available
                        ? context.palette.selected
                        : context.palette.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: context.palette.line),
                    boxShadow: available
                        ? [
                            BoxShadow(
                              color: context.palette.blue.withValues(
                                alpha: .08,
                              ),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (updates.checking)
                        const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          available
                              ? Icons.system_update_rounded
                              : updates.error != null
                              ? Icons.cloud_off_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 36,
                          color: context.palette.blue,
                        ),
                      const SizedBox(height: 20),
                      if (available) ...[
                        Text(
                          release.tag,
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        _updateStatus(updates),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (updates.installedVersion != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          trf(
                            context,
                            'Установлена версия {version}',
                            'Installed: {version}',
                            {'version': updates.installedVersion!},
                          ),
                          style: TextStyle(color: context.palette.muted),
                        ),
                      ],
                      if (release?.publishedAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          MaterialLocalizations.of(
                            context,
                          ).formatMediumDate(release!.publishedAt!.toLocal()),
                          style: TextStyle(
                            color: context.palette.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (release != null) ...[
                  const SizedBox(height: 28),
                  CampusSectionTitle(tr(context, 'Что нового', 'What’s new')),
                  CampusPanel(
                    child: ReleaseNotes(
                      notes: release.notes.isEmpty
                          ? tr(
                              context,
                              'В этом релизе нет описания изменений.',
                              'No release notes were provided.',
                            )
                          : release.notes,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CampusButton.icon(
                    onPressed: () => _openRelease(release.page),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(tr(context, 'Страница релиза', 'Release page')),
                    style: M3EButtonStyle.text,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Release text remains selectable; headings and bullet lists get readable spacing.
class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes({super.key, required this.notes});
  final String notes;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final block in notes.trim().split(RegExp(r'\n\s*\n')))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SelectableText(
            block
                .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
                .replaceAll(RegExp(r'^[-*]\s+', multiLine: true), '• ')
                .replaceAll('**', ''),
            style: block.startsWith('#')
                ? Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)
                : TextStyle(
                    fontSize: 14,
                    height: 1.65,
                    color: context.palette.ink,
                  ),
          ),
        ),
    ],
  );
}
