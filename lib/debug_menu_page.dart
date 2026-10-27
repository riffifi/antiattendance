import 'package:brockmann/brockmann.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:ui' show FrameTiming;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'accounts.dart';
import 'app_settings.dart';
import 'app_theme.dart';
import 'campus_design.dart';
import 'l10n.dart';
import 'nfc_diagnostics_page.dart';
import 'nfc_pass.dart';
import 'server_sessions.dart';
import 'session_server_page.dart';
import 'session_server_sync.dart';
import 'turnstile_probe_page.dart';
import 'update_service.dart';
import 'updates_page.dart';
import 'expressive.dart';

/// A bounded, in-memory sample for investigating jank without collecting logs.
abstract final class DebugFrameMonitor {
  static final _frames = Queue<FrameTiming>();
  static bool _installed = false;

  static void start() {
    if (_installed) return;
    _installed = true;
    WidgetsBinding.instance.addTimingsCallback(_record);
  }

  static void stop() {
    if (!_installed) return;
    WidgetsBinding.instance.removeTimingsCallback(_record);
    _installed = false;
    _frames.clear();
  }

  static void _record(List<FrameTiming> timings) {
    _frames.addAll(timings);
    while (_frames.length > 120) {
      _frames.removeFirst();
    }
  }

  static Map<String, Object?> snapshot(double refreshRate) {
    final budget = 1000 / (refreshRate > 0 ? refreshRate : 60);
    final builds =
        _frames.map((f) => f.buildDuration.inMicroseconds / 1000).toList()
          ..sort();
    final rasters =
        _frames.map((f) => f.rasterDuration.inMicroseconds / 1000).toList()
          ..sort();
    double? average(List<double> values) => values.isEmpty
        ? null
        : double.parse(
            (values.reduce((a, b) => a + b) / values.length).toStringAsFixed(2),
          );
    double? percentile(List<double> values) => values.isEmpty
        ? null
        : values[((values.length * .95).ceil() - 1).clamp(
            0,
            values.length - 1,
          )];
    return {
      'sampled_frames': _frames.length,
      'sample_limit': 120,
      'refresh_rate_hz': refreshRate,
      'frame_budget_ms': double.parse(budget.toStringAsFixed(2)),
      'average_build_ms': average(builds),
      'average_raster_ms': average(rasters),
      'p95_build_ms': percentile(builds),
      'p95_raster_ms': percentile(rasters),
      'frames_over_budget': _frames
          .where(
            (f) =>
                f.buildDuration.inMicroseconds / 1000 > budget ||
                f.rasterDuration.inMicroseconds / 1000 > budget,
          )
          .length,
      'measurement_note': 'Profile or release builds give representative timings; debug builds add overhead.',
    };
  }
}

/// Uses explicit fields rather than serializing account or native state objects.
/// Reports never contain session cookies, token values, pass numbers or names.
class DebugReportCollector {
  DebugReportCollector({
    Future<PackageInfo> Function()? packageInfo,
    Future<Map<String, dynamic>?> Function()? nativeSnapshot,
    NfcPassStore? passes,
  }) : _packageInfo = packageInfo ?? PackageInfo.fromPlatform,
       _nativeSnapshot =
           nativeSnapshot ??
           (() =>
               const MethodChannel('antiattendance/debug')
                   .invokeMapMethod<String, dynamic>('snapshot')),
       _passes = passes ?? NfcPassStore();

  final Future<PackageInfo> Function() _packageInfo;
  final Future<Map<String, dynamic>?> Function() _nativeSnapshot;
  final NfcPassStore _passes;

  Future<Object?> _read(Future<Object?> Function() read) async {
    try {
      return await read().timeout(const Duration(seconds: 4));
    } on MissingPluginException {
      return 'Not available on this platform';
    } on TimeoutException {
      return 'Timed out';
    } catch (_) {
      // Plugin/server exception messages can include request data.
      return 'Could not read diagnostics';
    }
  }

  Future<Map<String, Object?>> collect({
    required List<SavedAccount> accounts,
    required Set<String> selected,
    required Map<String, Object?> appState,
    required Map<String, Object?> display,
    required AppSettingsStore settings,
    UpdateController? updates,
  }) async {
    final now = DateTime.now().toUtc();
    final readings = await Future.wait([
      _read(_packageInfo),
      _read(_nativeSnapshot),
      _read(settings.loadDaySummaryEnabled),
      _read(_passes.settings),
      for (final account in accounts)
        _read(() async {
          final remote = serverAccountId(account.cookie);
          final number = remote == null
              ? await _passes.number(account)
              : ServerSessions.active?.passNumber(remote);
          return number != null;
        }),
    ]);
    final package = readings[0];
    final native = readings[1];
    final preferences = readings[3];
    final sync = SessionAutoSync.status.value;
    final server = ServerSessions.active;
    return {
      'App': {
        if (package is PackageInfo) ...{
          'name': package.appName,
          'package': package.packageName,
          'version': package.version,
          'build': package.buildNumber,
          'installer': package.installerStore,
        } else
          'package_info': package,
        'build_mode': kReleaseMode
            ? 'release'
            : kProfileMode
            ? 'profile'
            : 'debug',
        'captured_at_utc': now.toIso8601String(),
        ...appState,
      },
      'Device': {
        'platform': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'dart_version': Platform.version.split(' ').first,
        'processor_count': Platform.numberOfProcessors,
        'process_memory_bytes': ProcessInfo.currentRss,
        'peak_process_memory_bytes': ProcessInfo.maxRss,
        'local_timezone': DateTime.now().timeZoneName,
        'utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
        if (native is Map) ...{
          for (final key in [
            'manufacturer',
            'model',
            'android_release',
            'android_sdk',
            'supported_abis',
            'device_uptime_ms',
            'app_uptime_ms',
            'memory_available_bytes',
            'memory_total_bytes',
            'low_memory',
            'storage_available_bytes',
            'storage_total_bytes',
            'camera_permission',
            'notifications_enabled',
            'battery_optimization_exempt',
            'power_save_mode',
            'widget_pinning_supported',
            'webview_multi_profile',
            'webview_version',
          ])
            if (native.containsKey(key)) key: native[key],
        } else
          'native_diagnostics': native,
      },
      'Display & accessibility': display,
      'Performance': DebugFrameMonitor.snapshot(
        (display['refresh_rate_hz'] as num?)?.toDouble() ?? 60,
      ),
      'Accounts & sessions': {
        'total': accounts.length,
        'selected': accounts.where((a) => selected.contains(a.id)).length,
        'expired': accounts.where((a) => a.isExpiredAt(now)).length,
        'unknown_expiry': accounts
            .where((a) => a.expiresAt == null && !a.sessionExpired)
            .length,
        'enrolled_passes': readings
            .skip(4)
            .where((value) => value == true)
            .length,
        'accounts': [
          for (final (index, account) in accounts.indexed)
            {
              'account': index + 1,
              'selected': selected.contains(account.id),
              'source': serverAccountId(account.cookie) == null
                  ? 'local'
                  : 'server',
              'expired': account.isExpiredAt(now),
              'expires_at_utc': account.expiresAt?.toUtc().toIso8601String(),
              'group_assigned': account.groupId != null,
              'pass_enrolled': readings[index + 4],
            },
        ],
      },
      'Session server': {
        'connected': server != null,
        'origin': server?.base.origin,
        'cached_accounts': server?.accounts.length ?? 0,
        'sync_running': sync.running,
        'pending_changes': sync.pending,
        'last_success_utc': sync.lastSuccess?.toUtc().toIso8601String(),
        'sync_failed': sync.failed,
      },
      'NFC & widgets': {
        if (native is Map)
          for (final key in [
            'nfc_available',
            'nfc_enabled',
            'hce_supported',
            'nfc_reader_requested',
            'nfc_reader_active',
            'turnstile_probe_active',
          ])
            if (native.containsKey(key)) key: native[key],
        'queue_preferences': preferences is Map
            ? {
                'delay_seconds': preferences['seconds'],
                'mode': preferences['mode'] ?? 'queue',
                'own_account_configured': preferences['ownAccountId'] != null,
                'selected_count': preferences['selectedIds'] is List
                    ? (preferences['selectedIds'] as List).length
                    : null,
              }
            : preferences,
        if (native is Map && native['queue'] is Map)
          'queue': {
            for (final key in [
              'armed',
              'mode',
              'presented',
              'total',
              'responded',
              'remainingMillis',
              'expired',
            ])
              if ((native['queue'] as Map).containsKey(key))
                key: (native['queue'] as Map)[key],
          },
        'day_summary_enabled': readings[2],
      },
      'Updates': {
        'controller_available': updates != null,
        'checking': updates?.checking,
        'checked': updates?.checked,
        'installed_version': updates?.installedVersion,
        'latest_version': updates?.release?.tag,
        'update_available': updates?.updateAvailable,
        'last_checked_utc': updates?.lastCheckedAt?.toUtc().toIso8601String(),
        'check_failed': updates?.error != null,
      },
    };
  }
}

class DebugMenuPage extends StatefulWidget {
  const DebugMenuPage({
    super.key,
    required this.loadReport,
    this.updates,
    this.embedded = false,
  });
  final Future<Map<String, Object?>> Function(BuildContext) loadReport;
  final UpdateController? updates;
  final bool embedded;

  @override
  State<DebugMenuPage> createState() => _DebugMenuPageState();
}

class _DebugMenuPageState extends State<DebugMenuPage> {
  Map<String, Object?>? _report;
  bool _loading = false;
  bool _failed = false;
  bool _testingBusy = false;
  StreamSubscription<void>? _serverChanges;

  Future<void> _changePassTesting(bool enabled) async {
    final server = ServerSessions.active;
    if (server == null || _testingBusy) return;
    if (!enabled) {
      await server.disablePassTesting();
      ServerSessions.notify();
      SessionAutoSync.request();
      setState(() {});
      return;
    }
    final password = await showExpressiveDialog<String>(
      context: context,
      builder: (_) => const _PassTestingDialog(),
    );
    if (password == null ||
        !mounted ||
        !identical(server, ServerSessions.active)) {
      return;
    }
    setState(() => _testingBusy = true);
    try {
      await server.enablePassTesting(password);
      if (!identical(server, ServerSessions.active)) return;
      await server.fetch();
      ServerSessions.notify();
      SessionAutoSync.request();
    } catch (_) {
      await server.disablePassTesting();
      if (mounted) {
        CampusNotice.show(
          context,
          message: tr(
            context,
            'Не удалось включить тестирование. Проверьте ежедневный пароль в панели сервера.',
            'Could not enable testing. Check the daily password in the server panel.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _testingBusy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _serverChanges = ServerSessions.changes.listen((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    unawaited(_serverChanges?.cancel());
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final report = await widget.loadReport(context);
      if (mounted) setState(() => _report = report);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(
        ClipboardData(
          text: const JsonEncoder.withIndent('  ').convert(_report),
        ),
      );
      if (mounted) {
        CampusNotice.show(
          context,
          message: tr(context, 'Отчёт скопирован.', 'Report copied.'),
        );
      }
    } catch (_) {
      if (mounted) {
        CampusNotice.show(
          context,
          message: tr(
            context,
            'Не удалось скопировать отчёт.',
            'Could not copy report.',
          ),
        );
      }
    }
  }

  void _open(Widget page) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: CampusAppBar(
      automaticallyImplyLeading: !widget.embedded,
      title: Text(
        widget.embedded
            ? tr(context, 'Разработчик', 'Developer')
            : tr(context, 'Меню отладки', 'Debug menu'),
      ),
      actions: [
        CampusTextAction(
          icon: Icons.refresh_rounded,
          onPressed: _loading ? null : _refresh,
          tooltip: tr(context, 'Обновить', 'Refresh'),
          label: tr(context, 'Обновить', 'Refresh'),
        ),
        CampusTextAction(
          icon: Icons.content_copy_rounded,
          onPressed: _report == null || _loading ? null : _copy,
          tooltip: tr(context, 'Копировать отчёт', 'Copy report'),
          label: tr(context, 'Копировать отчёт', 'Copy report'),
        ),
      ],
    ),
    body: CampusPageBody(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            tr(
              context,
              'Диагностика приложения. Пароли, сессии и номера пропусков не включены в отчёт.',
              'App diagnostics. Credentials and pass numbers are excluded from the report.',
            ),
            style: TextStyle(color: context.palette.muted),
          ),
          const SizedBox(height: 16),
          if (_loading) const BrockmannProgress(label: ''),
          if (_failed) ...[
            Text(
              tr(
                context,
                'Не удалось загрузить диагностику.',
                'Could not load diagnostics.',
              ),
            ),
            CampusButton.text(
              onPressed: _refresh,
              child: Text(tr(context, 'Повторить', 'Retry')),
            ),
          ],
          if (_report != null)
            for (final section in _report!.entries) ...[
              const SizedBox(height: 16),
              CampusPanel(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  trailing: const Text(
                    '+',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300),
                  ),
                  key: PageStorageKey('debug-${section.key}'),
                  title: Text(
                    section.key,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        // ExpansionTile stores a bool in PageStorage; the text's
                        // internal scroll position needs a separate entry.
                        key: PageStorageKey('debug-content-${section.key}'),
                        const JsonEncoder.withIndent('  ')
                            .convert(section.value),
                        style: TextStyle(
                          fontFamily: 'GeistMono',
                          fontSize: 12,
                          color: context.palette.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          const SizedBox(height: 24),
          CampusSectionTitle(
            tr(context, 'Тестирование пропусков', 'Pass testing'),
          ),
          CampusListItem(
            headline: tr(
              context,
              'Без проверки согласия',
              'Skip agreement for testing',
            ),
            supportingText: ServerSessions.active == null
                ? tr(
                    context,
                    'Подключите сервер в настройках.',
                    'Connect to a server in Settings.',
                  )
                : tr(
                    context,
                    'Ежедневный пароль доступен в панели администратора. Режим действует до полуночи по Москве; сохранённые согласия не меняются.',
                    'The daily password is in the admin panel. Testing lasts until midnight in Moscow; saved agreements stay unchanged.',
                  ),
            trailing: CampusSwitch(
              value: ServerSessions.active?.passTestingActive ?? false,
              onChanged: ServerSessions.active == null || _testingBusy
                  ? null
                  : _changePassTesting,
            ),
          ),
          const SizedBox(height: 24),
          CampusSectionTitle(
            tr(context, 'Инструменты диагностики', 'Diagnostic tools'),
          ),
          CampusListItem(
            headline: tr(context, 'Проверка NFC', 'NFC diagnostics'),
            onTap: () => _open(const NfcDiagnosticsPage()),
          ),
          CampusListItem(
            headline: tr(context, 'Сигнал турникета', 'Turnstile signal'),
            onTap: () => _open(const TurnstileProbePage()),
          ),
          CampusListItem(
            headline: tr(context, 'Сервер сессий', 'Session server'),
            onTap: () => _open(const SessionServerPage()),
          ),
          if (widget.updates != null)
            CampusListItem(
              headline: tr(context, 'Обновления', 'Updates'),
              onTap: () => _open(UpdatesPage(updates: widget.updates!)),
            ),
        ],
      ),
    ),
  );
}

class _PassTestingDialog extends StatefulWidget {
  const _PassTestingDialog();
  @override
  State<_PassTestingDialog> createState() => _PassTestingDialogState();
}

class _PassTestingDialogState extends State<_PassTestingDialog> {
  final _password = TextEditingController();
  void _submit() {
    if (_password.text.trim().isNotEmpty) {
      Navigator.pop(context, _password.text.trim());
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BrockmannDialog(
    scrollable: true,
    title: Text(tr(context, 'Тестирование пропусков', 'Pass testing')),
    content: CampusTextField(
      controller: _password,
      autofocus: true,
      obscureText: true,
      label: tr(
        context,
        'Ежедневный пароль администратора',
        'Daily admin testing password',
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      CampusButton.text(
        onPressed: () => Navigator.pop(context),
        child: Text(tr(context, 'Отмена', 'Cancel')),
      ),
      CampusButton.filled(
        onPressed: _password.text.trim().isEmpty ? null : _submit,
        child: Text(tr(context, 'Включить тестирование', 'Enable testing')),
      ),
    ],
  );
}
