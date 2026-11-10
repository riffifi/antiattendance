import 'dart:async';

import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'campus_design.dart';
import 'l10n.dart';
import 'server_sessions.dart';
import 'session_server_sync.dart';

class SessionServerPage extends StatefulWidget {
  const SessionServerPage({super.key});
  @override
  State<SessionServerPage> createState() => _SessionServerPageState();
}

class _SessionServerPageState extends State<SessionServerPage> {
  final _url = TextEditingController();
  bool _busy = false, _ready = false;
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
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    SessionServerClient? candidate;
    try {
      candidate = SessionServerClient(_url.text.trim());
      await ServerSessions.connect(candidate);
      candidate = null;
      if (mounted) {
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
    setState(() => _busy = true);
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
        ),
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
  );
  @override
  Widget build(BuildContext context) {
    final server = ServerSessions.active;
    return CampusScaffold(
      appBar: CampusAppBar(
        title: Text(tr(context, 'Сервер сессий', 'Session server')),
      ),
      body: CampusPageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          children: [
            BrockmannText(
              server == null
                  ? tr(
                      context,
                      'Подключите общий сервер',
                      'Connect your shared server',
                    )
                  : tr(context, 'Сервер настроен', 'Server configured'),
              role: BrockmannType.value,
              weight: 400,
            ),
            const SizedBox(height: 8),
            BrockmannText(
              tr(
                context,
                'Сессии университета хранятся на сервере. Телефон входит через AA ID и получает разрешённые вам данные.',
                'University sessions stay on the server. This phone uses AA ID to synchronize your permitted data.',
              ),
              color: context.brockmann.secondary,
            ),
            if (server != null) ...[
              const SizedBox(height: 12),
              BrockmannText('${server.base}', role: BrockmannType.monoValue),
              const SizedBox(height: 8),
              _status(context, server),
            ],
            const SizedBox(height: 20),
            CampusTextField(
              controller: _url,
              label: tr(context, 'Адрес сервера', 'Server address'),
              placeholder: defaultSessionServerUrl,
              keyboardType: TextInputType.url,
              enabled: _ready && !_busy,
            ),
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
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: BrockmannText(_error!, color: context.brockmann.danger),
              ),
            const SizedBox(height: 20),
            CampusButton.filled(
              onPressed: !_ready || _busy ? null : _connect,
              child: Text(
                _busy
                    ? tr(context, 'Подождите…', 'Please wait…')
                    : tr(context, 'Проверить и подключить', 'Test and connect'),
              ),
            ),
            if (server != null) ...[
              const SizedBox(height: 12),
              CampusButton.text(
                onPressed: _busy ? null : SessionAutoSync.request,
                child: Text(tr(context, 'Синхронизировать сейчас', 'Sync now')),
              ),
              CampusButton.text(
                onPressed: _busy
                    ? null
                    : () async {
                        try {
                          final opened = await launchUrl(
                            server.base,
                            mode: LaunchMode.externalApplication,
                          );
                          if (!opened && mounted) {
                            setState(
                              () => _error = tr(
                                context,
                                'Не удалось открыть панель.',
                                'Could not open the panel.',
                              ),
                            );
                          }
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
                        }
                      },
                child: Text(tr(context, 'Открыть сайт', 'Open website')),
              ),
              CampusButton.text(
                onPressed: _busy ? null : _disconnect,
                child: Text(
                  tr(context, 'Отключить сервер', 'Disconnect server'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
