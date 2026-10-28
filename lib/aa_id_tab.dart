import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'aa_id.dart';
import 'app_theme.dart';
import 'campus_design.dart';
import 'expressive.dart';
import 'external_links.dart';
import 'l10n.dart';
import 'pass_people.dart';
import 'server_sessions.dart';

/// The person's AA ID, as on the AA ID site: name and group, who may use the
/// pass and the requests for it, Telegram, devices and sign-out.
class AaIdPanel extends StatefulWidget {
  const AaIdPanel({super.key, this.active = true});

  /// Reloads when the screen becomes visible again.
  final bool active;

  @override
  State<AaIdPanel> createState() => _AaIdPanelState();
}

class _AaIdPanelState extends State<AaIdPanel> {
  Map<String, dynamic>? _account;
  Map<String, dynamic>? _pass;
  List<AaIdDevice>? _devices;
  String? _accountError;
  bool _noServer = false;
  String? _devicesError;
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(AaIdPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  Future<void> _load() async {
    unawaited(_loadDevices());
    final server = ServerSessions.active;
    if (server == null) {
      // Shown by build(): initState must not read the locale.
      _noServer = true;
      return;
    }
    try {
      final account = await server.myAccount();
      final pass = account['account'] == true
          ? await server.myPassList()
          : null;
      if (!mounted) return;
      setState(() {
        _account = account;
        _pass = pass;
        _accountError = account['account'] == true
            ? null
            : tr(
                context,
                'Ваш аккаунт МИРЭА не подключён к серверу AntiAttendance. Войдите в AA ID по QR ещё раз.',
                'Your MIREA account is not connected to the AntiAttendance server. Sign in to AA ID with a QR again.',
              );
      });
    } catch (error) {
      if (mounted) setState(() => _accountError = serverError(context, error));
    }
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await AaId.devices();
      if (mounted) setState(() => _devices = devices);
    } catch (_) {
      if (mounted) {
        setState(
          () => _devicesError = tr(
            context,
            'Не удалось связаться с AA ID. Проверьте подключение.',
            'Could not reach AA ID. Check your connection.',
          ),
        );
      }
    }
  }

  Future<void> _run(Future<void> Function() change) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await change();
      if (mounted) setState(() => _status = tr(context, 'Сохранено', 'Saved'));
    } catch (error) {
      if (mounted) setState(() => _status = serverError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename() async {
    final current = _account?['label'] as String?;
    final controller = TextEditingController(
      text: current == 'Без имени' ? '' : current,
    );
    final name = await showExpressiveDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr(context, 'Имя', 'Name')),
        content: CampusTextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          placeholder: tr(context, 'Имя и фамилия', 'Full name'),
        ),
        actions: [
          CampusButton.text(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          CampusButton.filled(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(tr(context, 'Сохранить', 'Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == current || !mounted) return;
    if (!await confirmPassChange(
      context,
      tr(context, 'Сохранить изменения?', 'Save changes?'),
      trf(
        context,
        'Имя: «{name}». Его видят люди на ваших парах.',
        'Name: “{name}”. People at your lessons see it.',
        {'name': name},
      ),
      tr(context, 'Подтвердить', 'Confirm'),
    )) {
      return;
    }
    await _run(() async {
      final account = await ServerSessions.active!.updateMyAccount(label: name);
      if (mounted) setState(() => _account = account);
    });
  }

  Future<void> _togglePass(bool allowed) async {
    if (!await confirmPassChange(
      context,
      tr(context, 'Сохранить изменения?', 'Save changes?'),
      allowed
          ? tr(
              context,
              'Пропуск смогут использовать люди из списка.',
              'People on the list will be able to use your pass.',
            )
          : tr(
              context,
              'Пропуск будет запрещён всем, даже людям из списка.',
              'Your pass will be off for everyone, the list included.',
            ),
      tr(context, 'Подтвердить', 'Confirm'),
    )) {
      return;
    }
    await _run(() async {
      final server = ServerSessions.active!;
      final account = await server.updateMyAccount(passAllowed: allowed);
      final pass = await server.myPassList();
      if (mounted) {
        setState(() {
          _account = account;
          _pass = pass;
        });
      }
    });
  }

  Future<void> _unshare(Map<String, dynamic> person) async {
    if (!await confirmPassChange(
      context,
      tr(context, 'Убрать из списка?', 'Remove from the list?'),
      trf(
        context,
        '«{name}» больше не сможет использовать ваш пропуск.',
        '“{name}” will no longer be able to use your pass.',
        {'name': personName(person)},
      ),
      tr(context, 'Убрать', 'Remove'),
    )) {
      return;
    }
    await _run(() async {
      final pass = await ServerSessions.active!.unsharePass(
        person['kind'] as String,
        person['id'] as String,
      );
      if (mounted) setState(() => _pass = pass);
    });
  }

  Future<void> _share() async {
    final server = ServerSessions.active;
    if (server == null) return;
    final listed = {
      for (final person in _people('people'))
        if (person['kind'] == 'aaid') person['account_id'] as String,
    };
    await showPersonSearch(
      context,
      title: tr(context, 'Разрешить пропуск', 'Allow your pass'),
      actionLabel: tr(context, 'Разрешить', 'Allow'),
      done: listed,
      doneLabel: tr(context, 'В списке', 'Listed'),
      onAction: (person) async {
        if (!await confirmPassChange(
          context,
          tr(context, 'Разрешить пропуск?', 'Allow your pass?'),
          trf(
            context,
            '«{name}» сможет использовать ваш пропуск.',
            '“{name}” will be able to use your pass.',
            {'name': personName(person)},
          ),
          tr(context, 'Разрешить', 'Allow'),
        )) {
          return false;
        }
        final pass = await server.sharePass(person['account_id'] as String);
        if (mounted) setState(() => _pass = pass);
        return true;
      },
    );
  }

  List<Map<String, dynamic>> _people(String key) => [
    for (final person in _pass?[key] as List? ?? const [])
      if (person is Map<String, dynamic>) person,
  ];

  Future<void> _revoke(AaIdDevice device) async {
    setState(() => _busy = true);
    try {
      await AaId.revoke(device.id);
      await _loadDevices();
    } catch (_) {
      if (mounted) {
        setState(
          () => _devicesError = tr(
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

  Future<void> _open(Uri url) async {
    if (!await openWebPage(url) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Не удалось открыть браузер.',
              'Could not open a browser.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final localizations = MaterialLocalizations.of(context);
    final account = _account;
    final label = account?['label'] as String?;
    final group = account?['group_name'] as String? ?? AaId.session?.groupName;
    final passAllowed = _pass?['pass_allowed'] == true;
    final people = _people('people');
    final server = ServerSessions.active;
    final accountError = _noServer
        ? tr(
            context,
            'Подключитесь к серверу AntiAttendance в настройках.',
            'Connect to the AntiAttendance server in Settings.',
          )
        : _accountError;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          CampusPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label == null || label == 'Без имени'
                      ? tr(context, 'Без имени', 'No name')
                      : label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    group ??
                        tr(context, 'группа не определена', 'group unknown'),
                    if (account?['connected'] == true)
                      tr(
                        context,
                        'сессия МИРЭА на сервере',
                        'MIREA session on the server',
                      )
                    else if (account?['account'] == true)
                      tr(
                        context,
                        'сессия МИРЭА истекла',
                        'MIREA session expired',
                      ),
                  ].join(' · '),
                  style: TextStyle(color: palette.muted),
                ),
                if (account?['account'] == true) ...[
                  const SizedBox(height: 12),
                  CampusButton.text(
                    onPressed: _busy ? null : _rename,
                    child: Text(tr(context, 'Изменить имя', 'Change name')),
                  ),
                ],
              ],
            ),
          ),
          if (accountError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                accountError,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_status!, style: TextStyle(color: palette.muted)),
            ),
          if (_pass != null) ...[
            const SizedBox(height: 24),
            CampusSectionTitle(tr(context, 'Пропуск', 'Pass')),
            CampusListItem(
              headline: passAllowed
                  ? tr(
                      context,
                      'Разрешён людям из списка',
                      'Allowed to people on the list',
                    )
                  : tr(context, 'Запрещён всем', 'Off for everyone'),
              supportingText: passAllowed
                  ? tr(
                      context,
                      'Выключите, чтобы запретить пропуск всем, даже людям из списка.',
                      'Turn off to block everyone, the list included.',
                    )
                  : tr(
                      context,
                      'Никто не может использовать ваш пропуск.',
                      'Nobody can use your pass.',
                    ),
              trailing: CampusSwitch(
                value: passAllowed,
                onChanged: _busy ? null : _togglePass,
              ),
            ),
            const SizedBox(height: 16),
            PassRequestsInbox(
              requests: _people('requests'),
              passAllowed: passAllowed,
              onChanged: (pass) => setState(() => _pass = pass),
            ),
            CampusSectionTitle(tr(context, 'Кому разрешено', 'Allowed to')),
            if (people.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  tr(context, 'Пока никому.', 'Nobody yet.'),
                  style: TextStyle(color: palette.muted),
                ),
              ),
            for (final person in people)
              CampusListItem(
                headline: personName(person),
                supportingText: person['kind'] == 'telegram'
                    ? tr(context, 'разрешено в Telegram', 'allowed in Telegram')
                    : person['group_name'] as String?,
                trailing: CampusTextAction(
                  onPressed: _busy ? null : () => _unshare(person),
                  label: tr(context, 'Убрать', 'Remove'),
                ),
              ),
            const SizedBox(height: 8),
            CampusButton.text(
              onPressed: _busy ? null : _share,
              child: Text(
                tr(
                  context,
                  'Найти человека и разрешить',
                  'Find a person and allow',
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          CampusSectionTitle('Telegram'),
          CampusListItem(
            headline: tr(context, 'Привязать Telegram', 'Link Telegram'),
            supportingText: tr(
              context,
              'Бот покажет ваш аккаунт и пришлёт уведомления о сессии.',
              'The bot shows your account and sends session alerts.',
            ),
            onTap: server == null
                ? null
                : () => _open(server.base.resolve('/tg/connect')),
          ),
          CampusListItem(
            headline: tr(context, 'Сайт AA ID', 'AA ID website'),
            supportingText: AaId.url,
            onTap: () => _open(Uri.parse(AaId.url)),
          ),
          const SizedBox(height: 24),
          CampusSectionTitle(tr(context, 'Устройства', 'Devices')),
          if (_devices == null && _devicesError == null)
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
                  : CampusTextAction(
                      onPressed: _busy ? null : () => _revoke(device),
                      label: tr(context, 'Выйти', 'Sign out'),
                    ),
            ),
          if (_devicesError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _devicesError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 24),
          CampusButton.text(
            onPressed: _busy ? null : _signOut,
            child: Text(tr(context, 'Выйти из AA ID', 'Sign out of AA ID')),
          ),
        ],
      ),
    );
  }
}
