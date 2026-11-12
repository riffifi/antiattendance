import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import 'campus_design.dart';
import 'frontend/page_layout.dart';
import 'l10n.dart';
import 'server_api.dart';
import 'server_sessions.dart';
import 'server_workspace.dart' show ServerMessage, serverError;
import 'today_summary.dart';

class ServerTodayPage extends StatefulWidget {
  const ServerTodayPage({super.key, required this.api});
  final AaServerApi api;
  @override
  State<ServerTodayPage> createState() => _ServerTodayPageState();
}

class _ServerTodayPageState extends State<ServerTodayPage> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false, _attentionOnly = false;
  final _search = TextEditingController();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = await widget.api.today();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = serverError(context, error);
          // Revoked access must never leave somebody else's results on screen.
          if (error is SessionServerException &&
              [401, 403].contains(error.status)) {
            _data = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _person(TodayPersonSummary summary) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampusDisclosure(
          key: ValueKey('today-${_data?['date']}-${summary.id}'),
          title: summary.name,
          subtitle: [
            trf(
              context,
              'Подтверждено {count} из {total}',
              '{count} of {total} confirmed',
              {'count': summary.confirmations, 'total': summary.lessons.length},
            ),
            if (summary.signInNeeded)
              tr(context, 'Нужен повторный вход', 'Sign-in needed'),
            if ('${summary.person['group_name'] ?? ''}'.isNotEmpty)
              '${summary.person['group_name']}',
          ].join(' · '),
          children: [
            for (final lesson in summary.lessons)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BrockmannText(
                      '${lesson['start']}–${lesson['end']} · ${lesson['subject']}',
                      role: BrockmannType.body,
                    ),
                    const SizedBox(height: 6),
                    BrockmannText(
                      summary.mark(lesson) == null
                          ? lesson['state'] == 'future'
                                ? tr(context, 'Позже сегодня', 'Later today')
                                : '—'
                          : trMessage(
                              context,
                              '${summary.mark(lesson)?['message'] ?? summary.mark(lesson)?['state'] ?? '—'}',
                            ),
                      role: BrockmannType.caption,
                      color: summary.confirmed(lesson)
                          ? context.brockmann.accentText
                          : context.brockmann.secondary,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final lessons = serverRows(_data?['lessons']);
    final summaries = serverRows(_data?['people'])
        .map((p) => TodayPersonSummary(p, lessons))
        .toList();
    final attention = summaries.where((p) => p.needsAttention).length;
    final visible = summaries
        .where(
          (p) =>
              (!_attentionOnly || p.needsAttention) && p.matches(_search.text),
        )
        .toList();
    final header = <Widget>[
      SizedBox(
        height: 20,
        child: _busy ? const CampusProgress.compact() : null,
      ),
      if (_error != null) ServerMessage(message: _error!),
      if (_error != null && _data != null)
        ServerMessage(
          isError: false,
          message: tr(
            context,
            'Показаны предыдущие результаты.',
            'Showing earlier results.',
          ),
        ),
      if (_error != null || _data?['schedule_error'] != null)
        Align(
          alignment: Alignment.centerLeft,
          child: CampusButton.text(
            onPressed: _busy ? null : _load,
            child: Text(tr(context, 'Повторить', 'Retry')),
          ),
        ),
      if (_data?['schedule_error'] != null)
        ServerMessage(
          message: trMessage(context, '${_data!['schedule_error']}'),
        ),
      if (_data != null) ...[
        BrockmannText(
          [
            _data!['group_name'],
            _data!['date'],
          ].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
          role: BrockmannType.value,
        ),
        if (lessons.isNotEmpty) ...[
          const SizedBox(height: 12),
          BrockmannText(
            classCountLabel(context, lessons.length),
            color: context.brockmann.secondary,
          ),
          const SizedBox(height: 16),
          BrockmannText(
            tr(
              context,
              'Раскройте имя, чтобы увидеть занятия. «—» означает, что результата пока нет.',
              'Open a name to see classes. “—” means no result is available yet.',
            ),
            role: BrockmannType.caption,
            color: context.brockmann.secondary,
          ),
        ],
        if (lessons.isEmpty && _data?['schedule_error'] == null)
          AaEmptyState(
            title: tr(context, 'Занятий нет', 'No classes'),
            detail: tr(
              context,
              'На сегодня занятия не найдены.',
              'No classes were found for today.',
            ),
          ),
        if (summaries.isEmpty && lessons.isNotEmpty)
          AaEmptyState(
            title: tr(
              context,
              'Нет аккаунтов для итогов',
              'No accounts to summarize',
            ),
            detail: tr(
              context,
              'Доступные аккаунты этой группы появятся здесь.',
              'Accounts available for this group will appear here.',
            ),
          ),
        if (summaries.isNotEmpty && lessons.isNotEmpty) ...[
          const SizedBox(height: 24),
          CampusTextField(
            key: const ValueKey('today-search'),
            controller: _search,
            label: tr(context, 'Поиск людей', 'Search people'),
            leading: const Icon(Icons.search),
            trailing: _search.text.isEmpty
                ? const SizedBox(width: 48, height: 48)
                : CampusTextAction(
                    icon: Icons.close,
                    label: tr(context, 'Очистить поиск', 'Clear search'),
                    onPressed: () => setState(() => _search.clear()),
                  ),
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          BrockmannSegmentedControl<bool>(
            value: _attentionOnly,
            options: const [false, true],
            labelFor: (attentionOnly) => attentionOnly
                ? trf(context, 'Проверить · {count}', 'Review · {count}', {
                    'count': attention,
                  })
                : trf(context, 'Все · {count}', 'All · {count}', {
                    'count': summaries.length,
                  }),
            onChanged: (value) => setState(() => _attentionOnly = value),
          ),
          if (visible.isEmpty)
            AaEmptyState(
              title: _search.text.trim().isNotEmpty
                  ? tr(context, 'Никого не найдено', 'No people found')
                  : tr(context, 'Всё проверено', 'All caught up'),
              detail: _search.text.trim().isNotEmpty
                  ? tr(
                      context,
                      'Попробуйте другое имя или группу.',
                      'Try another name or group.',
                    )
                  : tr(
                      context,
                      'Нет неподтверждённых прошедших занятий или истёкших сессий.',
                      'No unconfirmed past classes or expired sessions.',
                    ),
            ),
        ],
      ],
    ];
    final showPeople = lessons.isNotEmpty;
    return CampusScaffold(
      appBar: CampusAppBar(title: Text(tr(context, 'За день', 'Today'))),
      body: CampusRefresh(
        onRefresh: _load,
        child: ListView.builder(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: AaPageLayout.insets(context),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: header.length + (showPeople ? visible.length : 0),
          itemBuilder: (context, index) => index < header.length
              ? header[index]
              : _person(visible[index - header.length]),
        ),
      ),
    );
  }
}
