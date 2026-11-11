import 'dart:async';

import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'campus_design.dart';
import 'l10n.dart';
import 'frontend/command_bar.dart';
import 'frontend/page_layout.dart';
import 'server_sessions.dart';
import 'session_server_sync.dart';

class SessionServerPage extends StatefulWidget {
  const SessionServerPage({super.key});
  @override
  State<SessionServerPage> createState() => _SessionServerPageState();
}

class _SessionServerPageState extends State<SessionServerPage> {
  final _url = TextEditingController();
  bool _busy = false, _ready = false, _opening = false;
  String? _error;
  StreamSubscription<void>? _updates;
  @override
  void initState() {
    super.initState();
    SessionAutoSync.install();
    _updates = ServerSessions.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _restore();
  }

  Future<void> _restore() async {
    try {
      await ServerSessions.initialize();
      if (!mounted) return;
      _url.text =
          ServerSessions.active?.base.toString() ?? defaultSessionServerUrl;
    } catch (_) {
      if (mounted) {
        _error = tr(
          context,
          'Не удалось прочитать настройки.',
          'Could not read connection settings.',
        );
      }
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    _updates?.cancel();
    _url.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy || !_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    FocusScope.of(context).unfocus();
    SessionServerClient? candidate;
    try {
      candidate = SessionServerClient(_url.text.trim());
      await ServerSessions.connect(candidate);
      candidate = null;
      if (mounted) {
        _url.text = ServerSessions.active!.base.toString();
        CampusNotice.show(
          context,
          message: tr(context, 'Сервер подключён.', 'Server connected.'),
        );
      }
    } catch (error) {
      candidate?.close();
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? tr(
                  context,
                  'Проверьте адрес HTTP(S) без пути и обновите сервер до новой версии.',
                  'Check the HTTP(S) address without a path and update the server to the latest version.',
                )
              : tr(
                  context,
                  'Не удалось подключиться. Проверьте адрес и доступность сервера.',
                  'Could not connect. Check the address and server availability.',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ServerSessions.disconnect();
    } catch (_) {
      if (mounted) {
        _error = tr(
          context,
          'Не удалось удалить настройки.',
          'Could not remove connection settings.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _status(
    BuildContext context,
    SessionServerClient server,
  ) => ValueListenableBuilder<SessionSyncStatus>(
    valueListenable: SessionAutoSync.status,
    builder: (context, state, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BrockmannText(
          state.running
              ? tr(context, 'Синхронизация…', 'Synchronizing…')
              : state.failed
              ? tr(
                  context,
                  'Повторим автоматически при восстановлении связи.',
                  'Will retry automatically when the connection is restored.',
                )
              : tr(
                  context,
                  'Автоматическая синхронизация включена',
                  'Automatic synchronization is on',
                ),
          color: state.failed ? Theme.of(context).colorScheme.error : null,
        ),
        const SizedBox(height: 20),
        CampusDisclosure(
          key: const PageStorageKey('server-sync-details'),
          title: tr(context, 'Подробности', 'Details'),
          children: [
            if (state.pending > 0)
              BrockmannText(
                trf(
                  context,
                  'Ожидает отправки: {count}',
                  'Waiting to upload: {count}',
                  {'count': state.pending},
                ),
                role: BrockmannType.caption,
                color: context.brockmann.secondary,
              ),
            if (state.lastSuccess != null)
              BrockmannText(
                trf(
                  context,
                  'Последняя синхронизация: {time}',
                  'Last synchronized: {time}',
                  {
                    'time': MaterialLocalizations.of(context).formatTimeOfDay(
                      TimeOfDay.fromDateTime(state.lastSuccess!.toLocal()),
                    ),
                  },
                ),
                role: BrockmannType.caption,
                color: context.brockmann.secondary,
              ),
            BrockmannText(
              trf(context, 'Аккаунтов: {count}', 'Accounts: {count}', {
                'count': server.accounts.length,
              }),
              role: BrockmannType.caption,
              color: context.brockmann.secondary,
            ),
          ],
        ),
      ],
    ),
  );
  Future<void> _openWebsite(SessionServerClient server) async {
    if (_opening || _busy) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final opened = await launchUrl(
        server.base,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('Could not open website');
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(
            context,
            'Не удалось открыть панель.',
            'Could not open the panel.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Widget _address(BuildContext context) => CampusTextField(
    controller: _url,
    label: tr(context, 'Адрес сервера', 'Server address'),
    placeholder: defaultSessionServerUrl,
    keyboardType: TextInputType.url,
    textInputAction: TextInputAction.go,
    onSubmitted: (_) => _connect(),
    onChanged: (_) => setState(() => _error = null),
    enabled: _ready && !_busy,
  );

  @override
  Widget build(BuildContext context) {
    final server = ServerSessions.active;
    return PopScope(
      canPop: !_busy,
      child: CampusScaffold(
        appBar: CampusAppBar(
          title: Text(tr(context, 'Сервер сессий', 'Session server')),
        ),
        bottomNavigationBar: ValueListenableBuilder<SessionSyncStatus>(
          valueListenable: SessionAutoSync.status,
          builder: (context, state, _) => CampusCommandBar(
            commands: [
              if (server == null)
                CampusCommand(
                  icon: Icons.link_rounded,
                  label: tr(context, 'Подключить', 'Connect'),
                  onPressed: !_ready || _busy || _url.text.trim().isEmpty
                      ? null
                      : _connect,
                ),
              if (server != null) ...[
                CampusCommand(
                  icon: Icons.sync_rounded,
                  label: tr(context, 'Синхронизировать сейчас', 'Sync now'),
                  onPressed: _busy || state.running
                      ? null
                      : SessionAutoSync.request,
                ),
                CampusCommand(
                  icon: Icons.open_in_new_rounded,
                  label: tr(context, 'Открыть сайт', 'Open website'),
                  onPressed: _busy || _opening
                      ? null
                      : () => _openWebsite(server),
                ),
              ],
            ],
          ),
        ),
        body: CampusPageBody(
          child: ListView(
            padding: AaPageLayout.insets(context).copyWith(
              left: AaPageLayout.gutter(context, title: true),
              right: AaPageLayout.gutter(context, title: true),
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (!_ready || _busy) const CampusProgress.compact(),
              if (server == null) ...[
                BrockmannText(
                  tr(
                    context,
                    'Подключите общий сервер',
                    'Connect your shared server',
                  ),
                  role: BrockmannType.heading,
                ),
                const SizedBox(height: 12),
                BrockmannText(
                  tr(
                    context,
                    'Введите адрес сервера для синхронизации аккаунтов и пропусков.',
                    'Enter your server address to synchronize accounts and passes.',
                  ),
                  color: context.brockmann.secondary,
                ),
                const SizedBox(height: 24),
                _address(context),
              ] else ...[
                BrockmannText(
                  tr(context, 'Сервер настроен', 'Server configured'),
                  role: BrockmannType.caption,
                  color: context.brockmann.secondary,
                ),
                const SizedBox(height: 8),
                BrockmannText(
                  server.base.authority,
                  role: BrockmannType.heading,
                ),
                const SizedBox(height: 16),
                _status(context, server),
                const SizedBox(height: 12),
                CampusDisclosure(
                  key: const PageStorageKey('server-connection-settings'),
                  title: tr(
                    context,
                    'Настройки подключения',
                    'Connection settings',
                  ),
                  children: [
                    _address(context),
                    const SizedBox(height: 12),
                    BrockmannText(
                      tr(
                        context,
                        'Ваш AA ID определяет доступные аккаунты и разрешения на пропуска.',
                        'Your AA ID determines which accounts and pass permissions are available.',
                      ),
                      role: BrockmannType.caption,
                      color: context.brockmann.secondary,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        CampusButton.text(
                          onPressed:
                              !_ready || _busy || _url.text.trim().isEmpty
                              ? null
                              : _connect,
                          child: Text(
                            tr(
                              context,
                              'Проверить и подключить',
                              'Test and connect',
                            ),
                          ),
                        ),
                        CampusButton.text(
                          onPressed: _busy ? null : _disconnect,
                          child: Text(
                            tr(
                              context,
                              'Отключить сервер',
                              'Disconnect server',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: BrockmannText(
                      _error!,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
