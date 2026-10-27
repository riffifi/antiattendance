import 'dart:async';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_ui/material_ui.dart';

import 'aa_id.dart';
import 'accounts.dart';
import 'campus_design.dart';
import 'l10n.dart';
import 'pulse_login.dart';

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
    if (!_ready) return const Scaffold(body: SizedBox.expand());
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
    if (!Platform.isAndroid && !Platform.isIOS) {
      setState(
        () => _error = tr(
          context,
          'Вход через МИРЭА доступен на Android и iOS.',
          'MIREA sign-in is available on Android and iOS.',
        ),
      );
      return;
    }
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
      final session = await Navigator.of(context).push<SavedAccount>(
        MaterialPageRoute(builder: (_) => const PulseLoginPage()),
      );
      if (!mounted || session == null) return;
      try {
        await AaId.signIn(address, session.cookie);
      } finally {
        // The MIREA session only proved who you are; do not leave it on the phone.
        await CookieManager.instance().deleteAllCookies().catchError(
          (Object _) => false,
        );
      }
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
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: CampusPageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
          children: [
            CampusHeader(
              title: 'AA ID',
              subtitle: tr(
                context,
                'Один аккаунт на человека',
                'One account per person',
              ),
            ),
            CampusPanel(
              child: Text(
                tr(
                  context,
                  'Войдите через МИРЭА, чтобы подтвердить, что это вы. AA ID привязывается к вашему аккаунту МИРЭА навсегда, и без него приложение не работает. Пароль и сессия МИРЭА не сохраняются.',
                  'Sign in with MIREA to confirm it is you. AA ID is permanently bound to your MIREA account, and the app does not work without it. Your MIREA password and session are not saved.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                context,
                'Не входите чужим аккаунтом МИРЭА и не давайте свой: вход на новом телефоне выводит из AA ID самый давний.',
                'Do not sign in with someone else’s MIREA account or share yours: signing in on a new phone signs out the oldest one.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
            const SizedBox(height: 20),
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
    return Scaffold(
      appBar: const CampusAppBar(title: Text('AA ID')),
      body: CampusPageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            CampusPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(
                      context,
                      'Привязан к аккаунту МИРЭА',
                      'Bound to a MIREA account',
                    ),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (session?.groupName != null) ...[
                    const SizedBox(height: 8),
                    Text(session!.groupName!),
                  ],
                  const SizedBox(height: 8),
                  Text(AaId.url, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 20),
            CampusSectionTitle(tr(context, 'Устройства', 'Devices')),
            if (_devices == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
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
