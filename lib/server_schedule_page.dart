import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import 'campus_design.dart';
import 'campus_maps_page.dart';
import 'frontend/command_bar.dart';
import 'frontend/page_layout.dart';
import 'group_picker_page.dart';
import 'l10n.dart';
import 'schedule_api.dart';
import 'server_api.dart';
import 'server_workspace.dart' show ServerMessage, serverError;

class ServerScheduleSearch extends ScheduleApi {
  ServerScheduleSearch(this.api);
  final AaServerApi api;
  @override
  Future<List<ScheduleGroup>> searchGroups(String query) async => [
    for (final row in serverRows((await api.searchGroups(query))['groups']))
      if (row['id'] is int && row['name'] is String)
        ScheduleGroup(id: row['id'] as int, name: row['name'] as String),
  ];
}

class ServerSchedulePage extends StatefulWidget {
  const ServerSchedulePage({
    super.key,
    required this.api,
    required this.active,
  });
  final AaServerApi api;
  final bool active;
  @override
  State<ServerSchedulePage> createState() => ServerSchedulePageState();
}

class ServerSchedulePageState extends State<ServerSchedulePage> {
  Map<String, dynamic>? _data;
  String? _error;
  int _week = 0, _day = 0;
  int? _group;
  bool _busy = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    if (widget.active) refresh();
  }

  @override
  void didUpdateWidget(ServerSchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) refresh();
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      final data = await widget.api.schedule(week: _week, group: _group);
      if (!mounted || generation != _generation) return;
      final days = serverRows(data['days']);
      setState(() {
        _data = data;
        _error = null;
        if (_week == 0 && days.any((d) => d['today'] == true)) {
          _day = days.indexWhere((d) => d['today'] == true);
        }
        _day = _day.clamp(0, days.isEmpty ? 0 : days.length - 1);
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = serverError(context, error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _chooseGroup() async {
    final search = ServerScheduleSearch(widget.api);
    try {
      final group = await Navigator.of(context).push<ScheduleGroup>(
        MaterialPageRoute(builder: (_) => GroupPickerPage(api: search)),
      );
      if (mounted && group != null) {
        setState(() {
          _group = group.id;
          _week = 0;
        });
        await refresh();
      }
    } finally {
      search.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = serverRows(_data?['days']);
    final lessons = days.isEmpty
        ? <Map<String, dynamic>>[]
        : serverRows(days[_day]['lessons']);
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: AaPageLayout.insets(context),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                CampusListItem(
                  showDivider: false,
                  headline:
                      '${_data?['group_name'] ?? tr(context, 'Выбрать группу', 'Choose a group')}',
                  supportingText: tr(
                    context,
                    'Нажмите, чтобы выбрать расписание',
                    'Choose which schedule to view',
                  ),
                  onTap: _chooseGroup,
                ),
                Row(
                  children: [
                    CampusTextAction(
                      icon: Icons.chevron_left_rounded,
                      label: tr(context, 'Предыдущая неделя', 'Previous week'),
                      tooltip: tr(
                        context,
                        'Предыдущая неделя',
                        'Previous week',
                      ),
                      onPressed: _busy || _week <= -30
                          ? null
                          : () {
                              setState(() => _week--);
                              refresh();
                            },
                    ),
                    Expanded(
                      child: BrockmannText(
                        _data?['monday'] is String
                            ? MaterialLocalizations.of(context)
                                  .formatMediumDate(
                                    DateTime.parse(_data!['monday'] as String),
                                  )
                            : '',
                        role: BrockmannType.value,
                      ),
                    ),
                    CampusTextAction(
                      icon: Icons.chevron_right_rounded,
                      label: tr(context, 'Следующая неделя', 'Next week'),
                      tooltip: tr(context, 'Следующая неделя', 'Next week'),
                      onPressed: _busy || _week >= 30
                          ? null
                          : () {
                              setState(() => _week++);
                              refresh();
                            },
                    ),
                  ],
                ),
                if (_busy) const CampusProgress.compact(),
                if (_error != null) ServerMessage(message: _error!),
                if (_data?['schedule_error'] != null)
                  ServerMessage(message: '${_data!['schedule_error']}'),
                if (days.isNotEmpty) ...[
                  BrockmannPicker(
                    label: tr(context, 'День', 'Day'),
                    options: [
                      for (final day in days)
                        MaterialLocalizations.of(context)
                            .formatMediumDate(DateTime.parse('${day['date']}')),
                    ],
                    selected: _day,
                    onChanged: (value) => setState(() => _day = value),
                  ),
                  const SizedBox(height: 20),
                  for (final (i, lesson) in lessons.indexed)
                    BrockmannFeather(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BrockmannText(
                              '${lesson['start']}–${lesson['end']}',
                              role: BrockmannType.monoValue,
                              color: lesson['state'] == 'now'
                                  ? context.brockmann.accentText
                                  : context.brockmann.secondary,
                            ),
                            const SizedBox(height: 8),
                            BrockmannText(
                              '${lesson['subject']}',
                              role: BrockmannType.heading,
                            ),
                            const SizedBox(height: 8),
                            BrockmannText(
                              '${lesson['type'] ?? ''} · ${lesson['teacher'] ?? ''}',
                              color: context.brockmann.secondary,
                            ),
                            if ('${lesson['location'] ?? ''}'.isNotEmpty)
                              CampusButton.text(
                                onPressed: () => Navigator.of(context)
                                    .push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => CampusMapsPage(
                                          room: '${lesson['location']}',
                                        ),
                                      ),
                                    ),
                                child: Text('${lesson['location']}'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (lessons.isEmpty &&
                      !_busy &&
                      _data?['schedule_error'] == null)
                    AaEmptyState(
                      title: tr(context, 'Свободный день', 'A free day'),
                      detail: tr(
                        context,
                        'На этот день занятий нет.',
                        'No classes on this day.',
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
              icon: Icons.today_outlined,
              label: tr(context, 'Сегодня', 'Today'),
              onPressed: () {
                setState(() {
                  _week = 0;
                  _group = null;
                });
                refresh();
              },
            ),
            CampusCommand(
              icon: Icons.map_outlined,
              label: tr(context, 'Карты', 'Maps'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const CampusMapsPage()),
              ),
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
}
