import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import 'campus_design.dart';
import 'frontend/command_bar.dart';
import 'frontend/page_layout.dart';
import 'l10n.dart';
import 'server_api.dart';
import 'server_nfc_page.dart';
import 'server_workspace.dart' show ServerMessage, serverError;

class ServerPassesPage extends StatefulWidget {
  const ServerPassesPage({super.key, required this.api, required this.active});
  final AaServerApi api;
  final bool active;
  @override
  State<ServerPassesPage> createState() => ServerPassesPageState();
}

class ServerPassesPageState extends State<ServerPassesPage> {
  Map<String, dynamic>? _mine, _received;
  bool _busy = false, _own = true, _routeOpen = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.active) refresh();
  }

  @override
  void didUpdateWidget(ServerPassesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) refresh();
  }

  Future<void> refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = await Future.wait([
        widget.api.myPass(),
        widget.api.passes(),
      ]);
      if (mounted) {
        setState(() {
          _mine = data[0];
          _received = data[1];
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = serverError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(
    Future<Map<String, dynamic>> Function() action, {
    required bool own,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await action();
      if (mounted) {
        setState(() {
          if (own) {
            _mine = data;
          } else {
            _received = data;
          }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = serverError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.updateAccount(passAllowed: value);
      final mine = await widget.api.myPass();
      if (mounted) setState(() => _mine = mine);
    } catch (error) {
      if (mounted) setState(() => _error = serverError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _find() async {
    if (_busy || _routeOpen) return;
    _routeOpen = true;
    final own = _own;
    String? id;
    try {
      id = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => ServerPersonSearchPage(api: widget.api),
        ),
      );
    } finally {
      _routeOpen = false;
    }
    if (!mounted || id == null) return;
    final selectedId = id;
    await _change(
      () => own
          ? widget.api.grant(selectedId)
          : widget.api.requestPass(selectedId),
      own: own,
    );
  }

  Future<void> _openNfc() async {
    if (_busy || _routeOpen) return;
    _routeOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => ServerNfcPassPage(api: widget.api)),
      );
    } finally {
      _routeOpen = false;
    }
    if (mounted) await refresh();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: CampusRefresh(
          onRefresh: refresh,
          child: ListView(
            padding: AaPageLayout.insets(context),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              BrockmannSegmentedControl<bool>(
                options: const [true, false],
                value: _own,
                labelFor: (own) => own
                    ? tr(context, 'Мой пропуск', 'My pass')
                    : tr(context, 'Доступные мне', 'Shared with me'),
                onChanged: (value) => setState(() => _own = value),
              ),
              const SizedBox(height: 12),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CampusProgress.compact(),
                ),
              if (_error != null) ServerMessage(message: _error!),
              if (_own && _mine != null) ...[
                CampusListItem(
                  showDivider: false,
                  headline: tr(
                    context,
                    'Разрешить доступ',
                    'Allow pass access',
                  ),
                  supportingText: tr(
                    context,
                    'Общий переключатель вашего пропуска',
                    'Master switch for your pass',
                  ),
                  trailing: CampusSwitch(
                    label: tr(context, 'Разрешить доступ', 'Allow pass access'),
                    value: _mine!['pass_allowed'] == true,
                    onChanged: _busy ? null : _toggle,
                  ),
                ),
                if (serverRows(_mine!['requests']).isNotEmpty)
                  AaSectionHeading(title: tr(context, 'Запросы', 'Requests')),
                for (final person in serverRows(_mine!['requests']))
                  CampusListItem(
                    headline: '${person['label'] ?? person['username'] ?? '—'}',
                    supportingText: '${person['group_name'] ?? ''}',
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        CampusButton.text(
                          onPressed: _busy
                              ? null
                              : () => _change(
                                  () => widget.api.decide(
                                    '${person['id']}',
                                    true,
                                  ),
                                  own: true,
                                ),
                          child: Text(tr(context, 'Разрешить', 'Allow')),
                        ),
                        CampusButton.text(
                          onPressed: _busy
                              ? null
                              : () => _change(
                                  () => widget.api.decide(
                                    '${person['id']}',
                                    false,
                                  ),
                                  own: true,
                                ),
                          child: Text(tr(context, 'Отклонить', 'Deny')),
                        ),
                      ],
                    ),
                  ),
                AaSectionHeading(
                  title: tr(context, 'Кому разрешено', 'People with access'),
                ),
                for (final person in serverRows(_mine!['people']))
                  CampusListItem(
                    headline: '${person['label'] ?? person['username'] ?? '—'}',
                    supportingText: '${person['group_name'] ?? ''}',
                    trailing: CampusButton.text(
                      onPressed: _busy
                          ? null
                          : () => _change(
                              () => widget.api.revoke('${person['id']}'),
                              own: true,
                            ),
                      child: Text(tr(context, 'Отозвать', 'Revoke')),
                    ),
                  ),
                if (serverRows(_mine!['people']).isEmpty)
                  BrockmannText(
                    tr(
                      context,
                      'Доступ пока никому не выдан',
                      'No access granted yet',
                    ),
                    color: context.brockmann.secondary,
                  ),
              ],
              if (!_own && _received != null) ...[
                AaSectionHeading(
                  title: tr(context, 'Доступные пропуска', 'Shared passes'),
                ),
                for (final person in serverRows(_received!['passes']))
                  CampusListItem(
                    headline: '${person['label'] ?? person['username'] ?? '—'}',
                    supportingText: [
                      if ('${person['group_name'] ?? ''}'.trim().isNotEmpty)
                        '${person['group_name']}',
                      person['pass_allowed'] == true
                          ? tr(context, 'Разрешён', 'Allowed')
                          : tr(
                              context,
                              'Выключен владельцем',
                              'Disabled by owner',
                            ),
                    ].join(' · '),
                  ),
                if (serverRows(_received!['passes']).isEmpty)
                  BrockmannText(
                    tr(
                      context,
                      'Вам пока не открыли доступ',
                      'No passes shared with you yet',
                    ),
                    color: context.brockmann.secondary,
                  ),
                if (serverRows(_received!['requests']).isNotEmpty)
                  AaSectionHeading(
                    title: tr(context, 'Мои запросы', 'Your requests'),
                  ),
                for (final person in serverRows(_received!['requests']))
                  CampusListItem(
                    headline: '${person['label'] ?? person['username'] ?? '—'}',
                    supportingText: tr(
                      context,
                      'Ожидает решения владельца',
                      'Waiting for the owner',
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      CampusCommandBar(
        active: widget.active,
        commands: [
          CampusCommand(
            icon: Icons.nfc_rounded,
            label: tr(context, 'NFC-пропуска', 'NFC passes'),
            onPressed: _busy ? null : _openNfc,
          ),
          CampusCommand(
            icon: Icons.person_add_rounded,
            label: _own
                ? tr(context, 'Разрешить', 'Grant access')
                : tr(context, 'Запросить', 'Request access'),
            onPressed: _busy ? null : _find,
          ),
          CampusCommand(
            icon: Icons.refresh_rounded,
            label: tr(context, 'Обновить', 'Refresh'),
            onPressed: _busy ? null : refresh,
          ),
        ],
      ),
    ],
  );
}

class ServerPersonSearchPage extends StatefulWidget {
  const ServerPersonSearchPage({super.key, required this.api});
  final AaServerApi api;
  @override
  State<ServerPersonSearchPage> createState() => _ServerPersonSearchPageState();
}

class _ServerPersonSearchPageState extends State<ServerPersonSearchPage> {
  final _query = TextEditingController();
  List<Map<String, dynamic>>? _people;
  String? _error;
  bool _busy = false;
  int _generation = 0;
  @override
  void dispose() {
    ++_generation;
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_busy) return;
    final query = _query.text
        .trim()
        .replaceFirst(RegExp(r'^@'), '')
        .toLowerCase();
    if (query.isEmpty || query.length > 60) return;
    FocusScope.of(context).unfocus();
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _people = null;
    });
    try {
      final data = await widget.api.people(query);
      if (mounted && generation == _generation) {
        setState(() => _people = serverRows(data['people']));
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = serverError(context, error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CampusScaffold(
    appBar: CampusAppBar(
      title: Text(tr(context, 'Найти человека', 'Find a person')),
    ),
    body: ListView(
      padding: AaPageLayout.insets(context),
      children: [
        CampusTextField(
          controller: _query,
          label: tr(context, 'Точный username', 'Exact username'),
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          onChanged: (_) {
            ++_generation;
            setState(() {
              _people = null;
              _error = null;
              _busy = false;
            });
          },
        ),
        CampusButton.filled(
          onPressed:
              _busy ||
                  _query.text.trim().replaceFirst(RegExp(r'^@'), '').isEmpty
              ? null
              : _search,
          child: Text(tr(context, 'Найти', 'Search')),
        ),
        if (_busy) const CampusProgress.compact(),
        if (_error != null) ServerMessage(message: _error!),
        if (_people?.isEmpty == true)
          BrockmannText(tr(context, 'Ничего не найдено', 'No matches found')),
        for (final person in _people ?? <Map<String, dynamic>>[])
          CampusReveal(
            key: ValueKey(person['account_id']),
            child: CampusListItem(
              headline: '${person['label'] ?? person['username'] ?? '—'}',
              supportingText: [
                if ('${person['username'] ?? ''}'.isNotEmpty)
                  '@${person['username']}',
                if ('${person['group_name'] ?? ''}'.trim().isNotEmpty)
                  '${person['group_name']}',
              ].join(' · '),
              onTap: () => Navigator.of(context).pop('${person['account_id']}'),
            ),
          ),
      ],
    ),
  );
}
