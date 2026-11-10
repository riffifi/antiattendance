import 'dart:async';

import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import 'aa_id.dart';
import 'campus_design.dart';
import 'l10n.dart';
import 'server_login_page.dart';

/// Shows [child] only to a phone signed in to AA ID.
class AaIdGate extends StatefulWidget {
  const AaIdGate({super.key, required this.child});
  final Widget child;
  @override
  State<AaIdGate> createState() => _AaIdGateState();
}

class _AaIdGateState extends State<AaIdGate> {
  StreamSubscription<void>? _changes;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _changes = AaId.changes.listen((_) {
      if (mounted) setState(() {});
    });
    AaId.initialize().catchError((Object _) {}).whenComplete(() {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const CampusScaffold(body: SizedBox.expand());
    return AaId.signedIn ? widget.child : const AaIdSignInPage();
  }
}

class AaIdSignInPage extends StatefulWidget {
  const AaIdSignInPage({super.key});
  @override
  State<AaIdSignInPage> createState() => _AaIdSignInPageState();
}

class _AaIdSignInPageState extends State<AaIdSignInPage> {
  final _url = TextEditingController(text: AaId.url);
  bool _busy = false, _customServer = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    final String address;
    try {
      address = AaIdClient.validateAddress(_url.text).toString();
    } on FormatException {
      setState(
        () => _error = tr(
          context,
          'Проверьте адрес AA ID.',
          'Check the AA ID address.',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => ServerLoginPage(address: address)),
      );
    } catch (error) {
      if (!mounted) return;
      final status = error is AaIdException ? error.status : null;
      setState(
        () => _error = switch (status) {
          401 => tr(
            context,
            'МИРЭА не подтвердил вход. Войдите ещё раз.',
            'MIREA did not confirm the sign-in. Sign in again.',
          ),
          403 => tr(
            context,
            'Этот AA ID заблокирован.',
            'This AA ID is blocked.',
          ),
          429 => tr(
            context,
            'Слишком много попыток. Подождите минуту.',
            'Too many attempts. Wait a minute.',
          ),
          _ => tr(
            context,
            'Не удалось связаться с AA ID. Проверьте подключение.',
            'Could not reach AA ID. Check your connection.',
          ),
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CampusScaffold(
    body: SafeArea(
      child: CampusPageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          children: [
            BrockmannText(
              'ANTIATTENDANCE',
              role: BrockmannType.label,
              color: context.brockmann.secondary,
            ),
            const SizedBox(height: 48),
            CampusHeader(
              title: 'AA ID',
              subtitle: tr(
                context,
                'Один аккаунт на человека',
                'One account per person',
              ),
            ),
            BrockmannText(
              tr(
                context,
                'Войдите с помощью QR-кода МИРЭА. Сессия университета хранится на сервере, на телефоне — только токены AA ID.',
                'Sign in with a MIREA QR code. Your university session stays on the server; this phone keeps only AA ID tokens.',
              ),
            ),
            const SizedBox(height: 12),
            if (_customServer) ...[
              const SizedBox(height: 20),
              CampusTextField(
                controller: _url,
                label: tr(context, 'Адрес AA ID', 'AA ID address'),
                placeholder: defaultAaIdUrl,
                keyboardType: TextInputType.url,
                enabled: !_busy,
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 32),
            CampusButton.filled(
              onPressed: _busy ? null : _signIn,
              child: Text(
                _busy
                    ? tr(context, 'Подождите…', 'Please wait…')
                    : tr(context, 'Войти через МИРЭА', 'Sign in with MIREA'),
              ),
            ),
            if (!_customServer)
              CampusButton.text(
                onPressed: _busy
                    ? null
                    : () => setState(() => _customServer = true),
                child: Text(tr(context, 'Другой сервер', 'Other server')),
              ),
          ],
        ),
      ),
    ),
  );
}

/// The signed-in AA ID: group, devices and sign-out.
class AaIdAccountPage extends StatefulWidget {
  const AaIdAccountPage({super.key});
  @override
  State<AaIdAccountPage> createState() => _AaIdAccountPageState();
}

class _AaIdAccountPageState extends State<AaIdAccountPage> {
  List<AaIdDevice>? _devices;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final devices = await AaId.devices();
      if (mounted) setState(() => _devices = devices);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(
            context,
            'Не удалось связаться с AA ID. Проверьте подключение.',
            'Could not reach AA ID. Check your connection.',
          ),
        );
      }
    }
  }

  Future<void> _revoke(AaIdDevice device) async {
    setState(() => _busy = true);
    try {
      await AaId.revoke(device.id);
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(
            context,
            'Не удалось связаться с AA ID. Проверьте подключение.',
            'Could not reach AA ID. Check your connection.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await AaId.signOut();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final session = AaId.session;
    final localizations = MaterialLocalizations.of(context);
    return CampusScaffold(
      appBar: const CampusAppBar(title: Text('AA ID')),
      body: CampusPageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          children: [
            BrockmannText(
              tr(
                context,
                'Привязан к аккаунту МИРЭА',
                'Bound to a MIREA account',
              ),
              role: BrockmannType.value,
              weight: 400,
            ),
            if (session?.groupName != null) ...[
              const SizedBox(height: 8),
              BrockmannText(session!.groupName!),
            ],
            const SizedBox(height: 8),
            BrockmannText(
              AaId.url,
              role: BrockmannType.caption,
              color: context.brockmann.secondary,
            ),
            const SizedBox(height: 20),
            CampusSectionTitle(tr(context, 'Устройства', 'Devices')),
            if (_devices == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CampusProgress.compact()),
              ),
            for (final device in _devices ?? const <AaIdDevice>[])
              CampusListItem(
                headline: device.current
                    ? '${device.device} · ${tr(context, 'этот телефон', 'this phone')}'
                    : device.device,
                supportingText:
                    '${localizations.formatShortDate(device.lastUsed)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(device.lastUsed))}',
                trailing: device.current
                    ? null
                    : CampusButton.text(
                        onPressed: _busy ? null : () => _revoke(device),
                        child: Text(tr(context, 'Выйти', 'Sign out')),
                      ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            CampusButton.text(
              onPressed: _busy ? null : _signOut,
              child: Text(tr(context, 'Выйти из AA ID', 'Sign out of AA ID')),
            ),
          ],
        ),
      ),
    );
  }
}
