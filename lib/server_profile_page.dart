import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import 'aa_id.dart';
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
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final idApi = AaId.client();
    try {
      final token = await AaId.accessToken();
      final data = await Future.wait([
        widget.api.account(),
        idApi.profile(token),
      ]);
      if (!mounted) return;
      setState(() {
        _name.text = '${data[0]['label'] ?? ''}';
        _username.text = '${data[1]['username'] ?? ''}';
        _group = data[1]['group_name'] as String?;
      });
    } catch (error) {
      if (mounted) setState(() => _error = serverError(context, error));
    } finally {
      idApi.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final name = _name.text.trim(),
        username = _username.text
            .trim()
            .replaceFirst(RegExp(r'^@'), '')
            .toLowerCase();
    if (name.isEmpty ||
        name.length > 60 ||
        !RegExp(r'^[a-z][a-z0-9_]{2,23}$').hasMatch(username)) {
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
      await idApi.setUsername(await AaId.accessToken(), username);
      await AaId.refreshAccessToken();
      await widget.api.updateAccount(label: name);
      if (mounted) Navigator.of(context).pop();
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
  Widget build(BuildContext context) => CampusScaffold(
    appBar: CampusAppBar(title: Text(tr(context, 'Мой профиль', 'My profile'))),
    body: ListView(
      padding: AaPageLayout.insets(context),
      children: [
        if (_loading)
          const CampusProgress.compact()
        else ...[
          CampusTextField(
            controller: _name,
            label: tr(context, 'Имя', 'Name'),
            enabled: !_busy,
          ),
          const SizedBox(height: 20),
          CampusTextField(
            controller: _username,
            label: 'Username',
            enabled: !_busy,
          ),
          const SizedBox(height: 12),
          BrockmannText(
            tr(
              context,
              'По этому username друзья смогут найти вас.',
              'Friends can find you by this username.',
            ),
            role: BrockmannType.caption,
            color: context.brockmann.secondary,
          ),
          if (_group != null) ...[
            const SizedBox(height: 24),
            BrockmannText(_group!, role: BrockmannType.value),
          ],
          const SizedBox(height: 24),
          CampusButton.filled(
            onPressed: _busy ? null : _save,
            child: Text(tr(context, 'Сохранить', 'Save')),
          ),
        ],
        if (_error != null) ServerMessage(message: _error!),
      ],
    ),
  );
}
