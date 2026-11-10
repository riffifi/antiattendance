import 'dart:async';
import 'dart:io';

import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apk_update.dart';
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
  File? _downloadedApk;
  String? _downloadedTag;
  String? _downloadError;
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
      _downloadError = null;
    });
    try {
      final apk =
          _downloadedTag == release.tag &&
              _downloadedApk != null &&
              await _downloadedApk!.exists()
          ? _downloadedApk!
          : await (widget.downloadApk ?? _downloadApk)(release, (
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
                      (next * 100).floor() ==
                          (_downloadProgress! * 100).floor()) {
                return;
              }
              setState(() {
                _downloadProgress = next;
              });
            });
      _downloadedApk = apk;
      _downloadedTag = release.tag;
      if (!mounted) return;
      await (widget.installApk ?? openAndroidInstaller)(apk);
      if (!mounted) return;
      CampusNotice.show(
        context,
        message: tr(
          context,
          'Подтвердите установку в Android.',
          'Confirm installation in Android.',
        ),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(
        () => _downloadError = error.code == 'INSTALL_PERMISSION_REQUIRED'
            ? tr(
                context,
                'Разрешите установку из этого приложения в Android, затем вернитесь.',
                'Allow installs from this app in Android, then return.',
              )
            : tr(
                context,
                'APK скачан. Повторите установку.',
                'APK downloaded. Retry installation.',
              ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _downloadError = _downloadedTag == release.tag
            ? tr(
                context,
                'APK скачан. Повторите установку.',
                'APK downloaded. Retry installation.',
              )
            : tr(
                context,
                'Не удалось скачать обновление. Повторите.',
                'Could not download the update. Retry.',
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
        CampusNotice.show(
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
      return CampusScaffold(
        appBar: CampusAppBar(
          title: Text(tr(context, 'Обновления', 'Updates')),
          actions: [
            CampusTextAction(
              icon: Icons.refresh_rounded,
              onPressed: updates.checking || _downloading
                  ? null
                  : () => updates.check(),
              tooltip: tr(context, 'Обновить', 'Refresh'),
              label: tr(context, 'Обновить', 'Refresh'),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  if (updates.checking)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CampusProgress.compact(strokeWidth: 2),
                      ),
                    )
                  else if (available)
                    BrockmannText(release.tag, role: BrockmannType.heading),
                  if (!updates.checking) ...[
                    const SizedBox(height: 8),
                    BrockmannText(_updateStatus(updates)),
                  ],
                  if (updates.installedVersion != null) ...[
                    const SizedBox(height: 8),
                    BrockmannText(
                      trf(
                        context,
                        'Установлена версия {version}',
                        'Installed: {version}',
                        {'version': updates.installedVersion!},
                      ),
                      role: BrockmannType.caption,
                      color: context.brockmann.secondary,
                    ),
                  ],
                  if (release?.publishedAt != null) ...[
                    const SizedBox(height: 4),
                    BrockmannText(
                      MaterialLocalizations.of(context)
                          .formatMediumDate(release!.publishedAt!.toLocal()),
                      role: BrockmannType.caption,
                      color: context.brockmann.secondary,
                    ),
                  ],
                  if (_downloading) ...[
                    const SizedBox(height: 16),
                    CampusProgress.linear(value: _downloadProgress),
                  ],
                  if (_downloadError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: BrockmannText(
                          _downloadError!,
                          color: context.brockmann.danger,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  CampusButton.action(
                    onPressed: _downloading || updates.checking
                        ? null
                        : available
                        ? (Platform.isAndroid || widget.downloadApk != null) &&
                                  release.apk != null
                              ? () => _downloadAndInstall(release)
                              : () => _openRelease(release.page)
                        : () => updates.check(),
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
                          ? (Platform.isAndroid ||
                                        widget.downloadApk != null) &&
                                    release.apk != null
                                ? tr(
                                    context,
                                    'Установить обновление',
                                    'Install update',
                                  )
                                : tr(context, 'Открыть релиз', 'Open release')
                          : tr(context, 'Проверить', 'Check now'),
                    ),
                  ),
                  if (release != null) ...[
                    CampusSectionTitle(tr(context, 'Что нового', 'What’s new')),
                    ReleaseNotes(
                      notes: release.notes.isEmpty
                          ? tr(
                              context,
                              'В этом релизе нет описания изменений.',
                              'No release notes were provided.',
                            )
                          : release.notes,
                    ),
                    const SizedBox(height: 8),
                    CampusButton.action(
                      onPressed: () => _openRelease(release.page),
                      label: Text(
                        tr(context, 'Страница релиза', 'Release page'),
                      ),
                      style: CampusButtonStyle.text,
                    ),
                  ],
                ],
              ),
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
                ? BrockmannType.value.style(
                    color: context.brockmann.foreground,
                    weight: 400,
                  )
                : BrockmannType.body.style(color: context.brockmann.foreground),
          ),
        ),
    ],
  );
}
