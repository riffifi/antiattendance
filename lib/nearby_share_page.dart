import 'campus_design.dart';

import 'package:material_3_expressive/material_3_expressive.dart';

import 'dart:async';
import 'dart:convert';

import 'package:bonsoir/bonsoir.dart';
import 'package:material_ui/material_ui.dart';

import 'accounts.dart';
import 'l10n.dart';
import 'nearby_transfer.dart';

class NearbySharePage extends StatefulWidget {
  const NearbySharePage({super.key, required this.accounts});
  final List<SavedAccount> accounts;

  @override
  State<NearbySharePage> createState() => _NearbySharePageState();
}

class _Peer {
  const _Peer(this.service, this.code);
  final BonsoirService service;
  final String code;
}

class _NearbySharePageState extends State<NearbySharePage> {
  final _discovery = BonsoirDiscovery(
    type: nearbyServiceType,
    printLogs: false,
  );
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  final _peers = <String, _Peer>{};
  final _selected = <String>{};
  final _outcomes = <String, bool>{};
  bool _ready = false;
  bool _failed = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await _discovery.initialize();
      if (!mounted) return;
      _subscription = _discovery.eventStream!.listen((event) {
        if (event is BonsoirDiscoveryServiceFoundEvent) {
          event.service.resolve(_discovery.serviceResolver);
        } else if (event is BonsoirDiscoveryServiceResolvedEvent ||
            event is BonsoirDiscoveryServiceUpdatedEvent) {
          final service = event is BonsoirDiscoveryServiceResolvedEvent
              ? event.service
              : (event as BonsoirDiscoveryServiceUpdatedEvent).service;
          unawaited(_add(service));
        } else if (event is BonsoirDiscoveryServiceLostEvent) {
          if (mounted) {
            setState(() {
              _peers.remove(event.service.name);
              _selected.remove(event.service.name);
              _outcomes.remove(event.service.name);
            });
          }
        }
      });
      await _discovery.start();
      if (mounted) {
        setState(() => _ready = true);
      } else {
        await _shutdown();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _add(BonsoirService service) async {
    final key = service.attributes['pk'];
    if (key == null ||
        service.port <= 0 ||
        service.hostAddress == null && service.hostname == null) {
      return;
    }
    try {
      final bytes = base64Url.decode(key);
      if (bytes.length != 32) return;
      final code = await receiverCode(bytes);
      if (mounted) setState(() => _peers[service.name] = _Peer(service, code));
    } catch (_) {
      // Ignore unrelated or malformed network services.
    }
  }

  Future<void> _send() async {
    if (_sending || _selected.isEmpty) return;
    final targets = _peers.entries
        .where((entry) => _selected.contains(entry.key))
        .toList();
    setState(() {
      _sending = true;
      _outcomes.clear();
    });
    await Future.wait(
      targets.map((entry) async {
        var success = false;
        try {
          await sendNearby(entry.value.service, widget.accounts);
          success = true;
        } catch (_) {
          // Show a per-receiver failure so the user can retry.
        }
        if (mounted) setState(() => _outcomes[entry.key] = success);
      }),
    );
    if (mounted) setState(() => _sending = false);
  }

  @override
  void dispose() {
    unawaited(_shutdown());
    super.dispose();
  }

  Future<void> _shutdown() async {
    await _subscription?.cancel();
    try {
      if (_discovery.isReady && !_discovery.isStopped) {
        await _discovery.stop();
      }
    } catch (_) {
      // The platform may already have stopped discovery.
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, 'Передать рядом', 'Share nearby')),
      automaticallyImplyLeading: true,
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            CampusHeader(
              title: tr(context, 'Выберите получателей', 'Select receivers'),
              subtitle: tr(
                context,
                'Откройте «Получить рядом» на других телефонах в той же Wi‑Fi сети. Сверьте код каждого устройства перед отправкой.',
                'Open “Receive nearby” on the other phones on the same Wi‑Fi. Match each device code before sending.',
              ),
              icon: Icons.wifi_tethering_rounded,
            ),
            if (_failed)
              Text(
                tr(
                  context,
                  'Не удалось найти устройства. Проверьте Wi‑Fi и разрешение локальной сети.',
                  'Could not discover devices. Check Wi‑Fi and local network permission.',
                ),
              )
            else if (_peers.isEmpty)
              CampusListItem(
                leading: _ready
                    ? const Icon(Icons.wifi_find_rounded)
                    : const M3EProgressIndicator.circularWavy(),
                headline: (tr(
                  context,
                  'Ищем получателей…',
                  'Looking for receivers…',
                )),
              ),
            for (final entry in _peers.entries)
              CheckboxListTile(
                value: _selected.contains(entry.key),
                onChanged: _sending
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          _selected.add(entry.key);
                        } else {
                          _selected.remove(entry.key);
                        }
                      }),
                title: Text(entry.value.service.name),
                subtitle: Text(
                  '${tr(context, 'Код', 'Code')}: ${entry.value.code}'
                  '${_outcomes[entry.key] == true
                      ? tr(context, ' · Отправлено', ' · Sent')
                      : _outcomes[entry.key] == false
                      ? tr(context, ' · Ошибка отправки', ' · Send failed')
                      : ''}',
                ),
              ),
            const SizedBox(height: 16),
            CampusButton.filled(
              onPressed: _selected.isEmpty || _sending ? null : _send,
              child: Text(
                _sending
                    ? tr(context, 'Отправляем…', 'Sending…')
                    : tr(context, 'Передать выбранным', 'Send to selected'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
