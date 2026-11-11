import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import 'aa_id.dart';
import 'aa_id_page.dart';
import 'frontend/command_bar.dart';
import 'server_login_page.dart';
import 'campus_design.dart';
import 'frontend/page_layout.dart';
import 'l10n.dart';
import 'server_api.dart';
import 'server_workspace.dart' show ServerMessage, serverError;

class ServerProfilePage extends StatefulWidget {
  const ServerProfilePage({super.key, required this.api});
  final AaServerApi api;
  @override
  State<ServerProfilePage> createState() => _ServerProfilePageState();
}

class _ServerProfilePageState extends State<ServerProfilePage> {
  final _name = TextEditingController(), _username = TextEditingController();
  bool _loading = true, _busy = false;
  String? _error, _group;
  String _savedName = '', _savedUsername = '';
  bool _connected = false, _hasAccount = false;
  bool _usernameRefreshPending = false;
  bool get _dirty =>
      _usernameRefreshPending ||
      (_hasAccount && _name.text.trim() != _savedName) ||
      _username.text.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase() !=
          _savedUsername;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final idApi = AaId.client();
    try {
      final token = await AaId.accessToken();
      final data = await Future.wait([
        widget.api.account(),
        idApi.profile(token),
      ]);
      if (!mounted) return;
      setState(() {
        _error = null;
        _name.text = '${data[0]['label'] ?? ''}';
        _username.text = '${data[1]['username'] ?? ''}';
        _group = (data[1]['group_name'] ?? data[0]['group_name']) as String?;
        _connected = data[0]['connected'] == true;
        _hasAccount = data[0]['account'] == true;
        _savedName = _name.text;
        _savedUsername = _username.text;
      });
    } catch (error) {
      if (mounted) setState(() => _error = serverError(context, error));
    } finally {
      idApi.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_dirty || _loading) return;
    final name = _name.text.trim(),
        username = _username.text
            .trim()
            .replaceFirst(RegExp(r'^@'), '')
            .toLowerCase();
    if ((_hasAccount && (name.isEmpty || name.length > 60)) ||
        (username != _savedUsername &&
            !RegExp(r'^[a-z][a-z0-9_]{2,23}$').hasMatch(username))) {
      setState(
        () => _error = tr(
          context,
          'Введите имя и username: 3–24 латинских символа, цифры или подчёркивание; первый символ — буква.',
          'Enter a name and a username: 3–24 Latin letters, digits or underscores, starting with a letter.',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final idApi = AaId.client();
    try {
      if (username != _savedUsername) {
        await idApi.setUsername(await AaId.accessToken(), username);
        _savedUsername = username;
        _usernameRefreshPending = true;
      }
      if (_usernameRefreshPending) {
        await AaId.refreshAccessToken();
        _usernameRefreshPending = false;
      }
      if (_hasAccount && name != _savedName) {
        await widget.api.updateAccount(label: name);
        _savedName = name;
      }
      if (mounted) {
        setState(() {});
        BrockmannFeedbackScope.play(context, BrockmannSound.confirm);
        CampusNotice.show(
          context,
          message: tr(context, 'Профиль обновлён', 'Profile updated'),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AaIdException && error.status == 409
              ? tr(
                  context,
                  'Этот username уже занят.',
                  'This username is already taken.',
                )
              : serverError(context, error),
        );
      }
    } finally {
      idApi.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _savedName.isNotEmpty
        ? _savedName
        : _savedUsername.isNotEmpty
        ? '@$_savedUsername'
        : 'AA ID';
    final initials =
        (_savedName.isNotEmpty
                ? _savedName
                : _savedUsername.isNotEmpty
                ? _savedUsername
                : 'AA')
            .split(RegExp(r'\s+'))
            .where((v) => v.isNotEmpty)
            .take(2)
            .map((v) => v.characters.first.toUpperCase())
            .join();
    return CampusScaffold(
      appBar: CampusAppBar(
        title: Text(tr(context, 'Мой профиль', 'My profile')),
      ),
      bottomNavigationBar: CampusCommandBar(
        commands: [
          CampusCommand(
            icon: Icons.check_rounded,
            label: tr(context, 'Сохранить', 'Save'),
            onPressed: _loading || _busy || !_dirty ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: AaPageLayout.insets(context),
        children: [
          if (_loading)
            const CampusProgress.compact()
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  color: context.brockmann.surface,
                  alignment: Alignment.center,
                  child: ExcludeSemantics(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: BrockmannText(
                        initials,
                        role: BrockmannType.heading,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BrockmannText(displayName, role: BrockmannType.heading),
                      if (_savedUsername.isNotEmpty && _savedName.isNotEmpty)
                        BrockmannText(
                          '@$_savedUsername',
                          color: context.brockmann.secondary,
                        ),
                      if (_group?.isNotEmpty == true)
                        BrockmannText(
                          _group!,
                          role: BrockmannType.caption,
                          color: context.brockmann.secondary,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            CampusListItem(
              headline: 'MIREA',
              supportingText: _connected
                  ? tr(
                      context,
                      'Привязан к аккаунту МИРЭА',
                      'Bound to a MIREA account',
                    )
                  : tr(context, 'Нужен повторный вход', 'Sign-in needed'),
              trailing: _connected
                  ? null
                  : CampusButton.text(
                      onPressed: _busy
                          ? null
                          : () async {
                              await Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ServerLoginPage(address: AaId.url),
                                ),
                              );
                              if (mounted) await _load();
                            },
                      child: Text(tr(context, 'Войти снова', 'Sign in again')),
                    ),
            ),
            CampusDisclosure(
              key: const PageStorageKey('profile-editor'),
              title: tr(context, 'Имя и username', 'Name and username'),
              children: [
                if (_hasAccount)
                  CampusTextField(
                    controller: _name,
                    label: tr(context, 'Имя', 'Name'),
                    maxLength: 60,
                    enabled: !_busy,
                    onChanged: (_) => setState(() {}),
                  ),
                const SizedBox(height: 16),
                CampusTextField(
                  controller: _username,
                  label: 'Username',
                  maxLength: 24,
                  enabled: !_busy,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                BrockmannText(
                  tr(
                    context,
                    'По этому username друзья смогут найти вас.',
                    'Friends can find you by this username.',
                  ),
                  role: BrockmannType.caption,
                  color: context.brockmann.secondary,
                ),
                const SizedBox(height: 16),
              ],
            ),
            CampusListItem(
              headline: tr(context, 'Устройства', 'Devices'),
              navigation: true,
              supportingText: tr(
                context,
                'Ваш аккаунт, устройства и выход',
                'Your account, devices and sign-out',
              ),
              onTap: _busy
                  ? null
                  : () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const AaIdAccountPage(),
                      ),
                    ),
            ),
          ],
          if (_busy) const CampusProgress.compact(),
          if (_error != null) ...[
            ServerMessage(message: _error!),
            if (!_loading && _savedName.isEmpty && _savedUsername.isEmpty)
              CampusButton.text(
                onPressed: _load,
                child: Text(tr(context, 'Повторить', 'Retry')),
              ),
          ],
        ],
      ),
    );
  }
}
