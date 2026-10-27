import 'campus_design.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'accounts.dart';
import 'l10n.dart';
import 'nearby_transfer.dart';

class NearbyReceivePage extends StatefulWidget {
  const NearbyReceivePage({super.key});

  @override
  State<NearbyReceivePage> createState() => _NearbyReceivePageState();
}

class _NearbyReceivePageState extends State<NearbyReceivePage> {
  var _receiver = NearbyReceiver();
  StreamSubscription<List<SavedAccount>>? _subscription;
  List<SavedAccount>? _incoming;
  bool _ready = false;
  bool _failed = false;

  Future<void> _retry() async {
    setState(() {
      _failed = false;
      _ready = false;
    });
    await _subscription?.cancel();
    await _receiver.stop();
    if (!mounted) return;
    _receiver = NearbyReceiver();
    await _start();
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    _subscription = _receiver.incoming.listen((accounts) {
      if (mounted) setState(() => _incoming = accounts);
    });
    try {
      await _receiver.start();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_receiver.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: CampusAppBar(
      title: Text(tr(context, 'Получить рядом', 'Receive nearby')),
      automaticallyImplyLeading: true,
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _failed
                ? SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tr(
                            context,
                            'Не удалось начать передачу. Проверьте Wi‑Fi и доступ к локальной сети.',
                            'Could not start receiving. Check Wi‑Fi and local network permission.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        CampusButton.text(
                          onPressed: _retry,
                          child: Text(tr(context, 'Повторить', 'Retry')),
                        ),
                      ],
                    ),
                  )
                : _incoming != null
                ? ListView(
                    children: [
                      Text(
                        tr(context, 'Получены сессии', 'Sessions received'),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr(
                          context,
                          'Проверьте аккаунты перед импортом.',
                          'Review the accounts before importing.',
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final account in _incoming!)
                        CampusListItem(headline: (account.label)),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: CampusButton.filled(
                          onPressed: () => Navigator.of(context).pop(_incoming),
                          child: Text(tr(context, 'Импортировать', 'Import')),
                        ),
                      ),
                      CampusButton.text(
                        onPressed: () {
                          _receiver.clearPending();
                          setState(() => _incoming = null);
                        },
                        child: Text(tr(context, 'Отклонить', 'Decline')),
                      ),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _ready
                              ? tr(
                                  context,
                                  'Ждём отправителя',
                                  'Waiting for sender',
                                )
                              : tr(
                                  context,
                                  'Готовим соединение…',
                                  'Starting receiver…',
                                ),
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          tr(
                            context,
                            'Оба телефона должны быть в одной Wi‑Fi сети. На телефоне отправителя выберите это устройство и проверьте код.',
                            'Both phones must be on the same Wi‑Fi network. Select this device on the sender and check the code.',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        if (_ready)
                          SelectableText(
                            _receiver.code!,
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 4,
                            ),
                          )
                        else
                          const CampusProgress.compact(),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
}
