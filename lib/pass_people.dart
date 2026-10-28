import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';
import 'campus_design.dart';
import 'expressive.dart';
import 'l10n.dart';
import 'server_sessions.dart';

/// A person as the session server shows them to others: name, username, group.
String personName(Map<String, dynamic> person) {
  final label = person['label'] as String?;
  final username = person['username'] as String?;
  if (label != null && label.isNotEmpty && label != 'Без имени') {
    return username == null ? label : '$label (@$username)';
  }
  return username == null ? (label ?? '—') : '@$username';
}

String? personMeta(Map<String, dynamic> person) {
  final parts = [
    if (person['username'] is String) '@${person['username']}',
    if (person['group_name'] is String) person['group_name'] as String,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String serverError(BuildContext context, Object error) =>
    error is SessionServerException && error.message.runes.any((c) => c > 127)
    ? error.message
    : tr(
        context,
        'Сервер AntiAttendance недоступен. Попробуйте ещё раз.',
        'The AntiAttendance server is unreachable. Try again.',
      );

/// Asks before a change to who may use a pass; every such change is confirmed.
Future<bool> confirmPassChange(
  BuildContext context,
  String title,
  String text,
  String action,
) async =>
    await showExpressiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(text),
        actions: [
          CampusButton.text(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          CampusButton.filled(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// Finds people by username or name and offers one action for each: ask for
/// their pass, or allow them yours. [onAction] returns false when the person
/// cancelled it.
Future<void> showPersonSearch(
  BuildContext context, {
  required String title,
  required String actionLabel,
  required Future<bool> Function(Map<String, dynamic> person) onAction,
  Set<String> done = const {},
  String? doneLabel,
}) => showExpressiveSheet<void>(
  context: context,
  builder: (context) => _PersonSearch(
    title: title,
    actionLabel: actionLabel,
    onAction: onAction,
    done: done,
    doneLabel: doneLabel,
  ),
);

class _PersonSearch extends StatefulWidget {
  const _PersonSearch({
    required this.title,
    required this.actionLabel,
    required this.onAction,
    required this.done,
    this.doneLabel,
  });
  final String title;
  final String actionLabel;
  final Future<bool> Function(Map<String, dynamic> person) onAction;
  final Set<String> done;
  final String? doneLabel;

  @override
  State<_PersonSearch> createState() => _PersonSearchState();
}

class _PersonSearchState extends State<_PersonSearch> {
  final _query = TextEditingController();
  List<Map<String, dynamic>>? _people;
  late final Set<String> _done = {...widget.done};
  String? _status;
  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.replaceFirst('@', '').length < 2) {
      setState(
        () => _status = tr(
          context,
          'Введите хотя бы 2 символа',
          'Type at least 2 characters',
        ),
      );
      return;
    }
    final server = ServerSessions.active;
    if (server == null) return;
    setState(() => _busy = true);
    try {
      final people = await server.searchPeople(query);
      if (!mounted) return;
      setState(() {
        _people = people;
        _status = people.isEmpty
            ? tr(context, 'Никого не нашли', 'Nobody found')
            : null;
      });
    } catch (error) {
      if (mounted) setState(() => _status = serverError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(Map<String, dynamic> person) async {
    setState(() => _busy = true);
    try {
      if (!await widget.onAction(person)) return;
      if (mounted) {
        setState(() {
          _done.add(person['account_id'] as String);
          _status = tr(context, 'Готово', 'Done');
        });
      }
    } catch (error) {
      if (mounted) setState(() => _status = serverError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        CampusTextField(
          controller: _query,
          autofocus: true,
          maxLength: 60,
          placeholder: tr(context, 'Username или имя', 'Username or name'),
          onSubmitted: (_) => _search(),
          trailing: CampusTextAction(
            onPressed: _busy ? null : _search,
            label: tr(context, 'Найти', 'Search'),
          ),
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _status!,
              style: TextStyle(color: context.palette.muted),
            ),
          ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final person in _people ?? const <Map<String, dynamic>>[])
                CampusListItem(
                  headline: personName(person),
                  supportingText: person['group_name'] as String?,
                  trailing: _done.contains(person['account_id'])
                      ? Text(
                          widget.doneLabel ?? tr(context, 'Готово', 'Done'),
                          style: TextStyle(color: context.palette.muted),
                        )
                      : CampusTextAction(
                          onPressed: _busy ? null : () => _act(person),
                          label: widget.actionLabel,
                        ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Requests from other people to use the person's pass, each answered with
/// Allow or Deny. [onChanged] receives the server's new pass list.
class PassRequestsInbox extends StatelessWidget {
  const PassRequestsInbox({
    super.key,
    required this.requests,
    required this.passAllowed,
    required this.onChanged,
  });
  final List<Map<String, dynamic>> requests;
  final bool passAllowed;
  final ValueChanged<Map<String, dynamic>> onChanged;

  Future<void> _answer(
    BuildContext context,
    Map<String, dynamic> person,
    bool allow,
  ) async {
    final name = personName(person);
    final confirmed = await confirmPassChange(
      context,
      allow
          ? tr(context, 'Разрешить пропуск?', 'Allow your pass?')
          : tr(context, 'Отклонить запрос?', 'Deny the request?'),
      allow
          ? [
              trf(
                context,
                '«{name}» сможет использовать ваш пропуск.',
                '“{name}” will be able to use your pass.',
                {'name': name},
              ),
              if (!passAllowed)
                tr(
                  context,
                  'Сейчас пропуск запрещён всем: разрешение заработает, когда вы снова разрешите пропуск.',
                  'Your pass is off for everyone now: this works once you turn it back on.',
                ),
            ].join('\n\n')
          : trf(
              context,
              'Запрос «{name}» будет отклонён. Повторить его можно будет через сутки.',
              'The request from “{name}” will be denied. It can be sent again in a day.',
              {'name': name},
            ),
      allow
          ? tr(context, 'Разрешить', 'Allow')
          : tr(context, 'Запретить', 'Deny'),
    );
    if (!confirmed || !context.mounted) return;
    try {
      onChanged(
        await ServerSessions.active!.answerPassRequest(
          person['id'] as String,
          allow,
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(serverError(context, error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampusSectionTitle(
          tr(context, 'Запросы на ваш пропуск', 'Requests for your pass'),
        ),
        for (final person in requests)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CampusPanel(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    personName(person),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (person['group_name'] is String) ...[
                    const SizedBox(height: 4),
                    Text(
                      person['group_name'] as String,
                      style: TextStyle(color: context.palette.muted),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: CampusButton.filled(
                          onPressed: () => _answer(context, person, true),
                          child: Text(tr(context, 'Разрешить', 'Allow')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CampusButton.text(
                          onPressed: () => _answer(context, person, false),
                          child: Text(tr(context, 'Запретить', 'Deny')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// For the Passes tab: requests to the person's own pass, the passes other
/// people allowed, the person's open requests, and a search to ask for more.
class PassSharingSection extends StatefulWidget {
  const PassSharingSection({super.key});

  @override
  State<PassSharingSection> createState() => _PassSharingSectionState();
}

class _PassSharingSectionState extends State<PassSharingSection> {
  Map<String, dynamic>? _mine;
  Map<String, dynamic>? _theirs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final server = ServerSessions.active;
    if (server == null) return;
    try {
      final results = await Future.wait([
        server.myPassList(),
        server.myPasses(),
      ]);
      if (!mounted) return;
      setState(() {
        _mine = results[0];
        _theirs = results[1];
        _error = null;
      });
    } catch (error) {
      // Without a connected MIREA account there is nothing to share or ask.
      if (mounted) {
        setState(
          () => _error = error is SessionServerException && error.status == 404
              ? null
              : serverError(context, error),
        );
      }
    }
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic>? data, String key) => [
    for (final item in data?[key] as List? ?? const [])
      if (item is Map<String, dynamic>) item,
  ];

  Future<void> _ask() async {
    final server = ServerSessions.active;
    if (server == null) return;
    final asked = {
      for (final item in [
        ..._list(_theirs, 'passes'),
        ..._list(_theirs, 'requests'),
      ])
        item['account_id'] as String,
    };
    await showPersonSearch(
      context,
      title: tr(context, 'Запросить пропуск', 'Ask for a pass'),
      actionLabel: tr(context, 'Запросить', 'Ask'),
      done: asked,
      doneLabel: tr(context, 'Запрошено', 'Asked'),
      onAction: (person) async {
        final result = await server.requestPass(person['account_id'] as String);
        if (mounted) setState(() => _theirs = result);
        return true;
      },
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final passes = _list(_theirs, 'passes');
    final waiting = _list(_theirs, 'requests');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PassRequestsInbox(
          requests: _list(_mine, 'requests'),
          passAllowed: _mine?['pass_allowed'] == true,
          onChanged: (data) => setState(() => _mine = data),
        ),
        CampusSectionTitle(
          tr(context, 'Мне разрешили пропуск', 'Passes allowed to me'),
        ),
        if (_theirs != null && passes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              tr(
                context,
                'Пока никто. Найдите человека и запросите его пропуск.',
                'Nobody yet. Find a person and ask for their pass.',
              ),
              style: TextStyle(color: context.palette.muted),
            ),
          ),
        for (final person in passes)
          CampusListItem(
            headline: personName(person),
            supportingText: person['pass_allowed'] == true
                ? person['group_name'] as String?
                : tr(
                    context,
                    'Владелец сейчас запретил пропуск всем',
                    'The owner has turned the pass off for now',
                  ),
          ),
        for (final person in waiting)
          CampusListItem(
            headline: personName(person),
            supportingText: tr(context, 'Ждёт ответа', 'Waiting for an answer'),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        CampusButton.text(
          onPressed: ServerSessions.active == null ? null : _ask,
          child: Text(
            tr(
              context,
              'Найти человека и запросить пропуск',
              'Find a person and ask for their pass',
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
