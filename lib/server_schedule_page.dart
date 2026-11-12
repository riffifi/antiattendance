import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import 'campus_design.dart';
import 'aa_id.dart';
import 'server_sessions.dart';
import 'server_schedule_cache.dart';
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
    this.cache,
    this.now,
  });
  final AaServerApi api;
  final bool active;
  final ServerScheduleCache? cache;
  final DateTime Function()? now;
  @override
  State<ServerSchedulePage> createState() => ServerSchedulePageState();
}

class ServerSchedulePageState extends State<ServerSchedulePage> {
  Map<String, dynamic>? _data;
  String? _error;
  int _day = 0;
  DateTime _currentMonday() {
    final now = (widget.now?.call() ?? DateTime.now()).toUtc().add(
      const Duration(hours: 3),
    );
    return DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
  }

  late DateTime _weekMonday = _currentMonday();
  int get _week => _weekMonday.difference(_currentMonday()).inDays ~/ 7;
  set _week(int value) =>
      _weekMonday = _currentMonday().add(Duration(days: value * 7));
  int? _group;
  bool _busy = false, _routeOpen = false;
  int _generation = 0;
  int? _loadedGroup;
  DateTime? _loadedMonday;
  DateTime? _cachedAt, _lastLoadedAt;
  late final _cache = widget.cache ?? ServerScheduleCache();
  String? get _cacheScope {
    final user = AaId.session;
    if (user == null) return null;
    return '${widget.api.client.base.origin}|${user.userId}|${user.groupId}|${_group ?? widget.api.client.groupId}';
  }

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

  Future<void> refresh({bool goToToday = false}) async {
    final previousDays = serverRows(_data?['days']);
    final previousDate = previousDays.isEmpty
        ? null
        : previousDays[_day]['date'];
    final sameContext = _loadedMonday == _weekMonday && _loadedGroup == _group;
    final generation = ++_generation;
    final scope = _cacheScope;
    final requestedWeek = _week;
    final requestedMonday = _weekMonday.toIso8601String().substring(0, 10);
    setState(() => _busy = true);
    try {
      if (scope != null && (_data == null || !sameContext)) {
        final saved = await _cache.load(
          scope,
          requestedWeek,
          monday: requestedMonday,
        );
        if (!mounted || generation != _generation) return;
        if (saved != null) {
          setState(() {
            _data = saved.data;
            _cachedAt = _lastLoadedAt = saved.savedAt;
            _loadedMonday = _weekMonday;
            _loadedGroup = _group;
            final cachedDays = serverRows(_data?['days']);
            final today = (widget.now?.call() ?? DateTime.now())
                .toUtc()
                .add(const Duration(hours: 3))
                .toIso8601String()
                .substring(0, 10);
            _day = cachedDays.indexWhere((d) => d['date'] == today);
            if (_day < 0) _day = 0;
          });
        }
      }
      final data = await widget.api.schedule(week: _week, group: _group);
      if (!mounted || generation != _generation) return;
      final days = serverRows(data['days']);
      setState(() {
        _data = data;
        _cachedAt = null;
        _lastLoadedAt = DateTime.now();
        _error = null;
        final retained = sameContext && !goToToday
            ? days.indexWhere((d) => d['date'] == previousDate)
            : -1;
        _day = retained >= 0
            ? retained
            : _week == 0 && days.any((d) => d['today'] == true)
            ? days.indexWhere((d) => d['today'] == true)
            : 0;
        _loadedMonday = _weekMonday;
        _loadedGroup = _group;
        _day = _day.clamp(0, days.isEmpty ? 0 : days.length - 1);
      });
      if (scope != null) {
        try {
          await _cache.save(
            scope,
            requestedWeek,
            data,
            monday: requestedMonday,
          );
        } catch (_) {}
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = serverError(context, error);
          if (error is SessionServerException &&
              [401, 403].contains(error.status)) {
            _data = null;
            _cachedAt = _lastLoadedAt = null;
          }
          if (_data != null) _cachedAt = _lastLoadedAt;
          // Existing lessons must keep the week/group they were loaded for.
          if (_data != null) {
            _weekMonday = _loadedMonday ?? _currentMonday();
            _group = _loadedGroup;
          }
        });
        if (scope != null &&
            error is SessionServerException &&
            [401, 403].contains(error.status)) {
          try {
            await _cache.clear(scope);
          } catch (_) {}
        }
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _chooseGroup() async {
    if (_busy || _routeOpen) return;
    _routeOpen = true;
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
      _routeOpen = false;
      search.close();
    }
  }

  Future<void> _openMap({String? room}) async {
    if (_routeOpen) return;
    _routeOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => CampusMapsPage(room: room ?? '')),
      );
    } finally {
      _routeOpen = false;
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
          child: CampusRefresh(
            onRefresh: refresh,
            child: ListView(
              padding: AaPageLayout.insets(context),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                CampusListItem(
                  showDivider: false,
                  headline:
                      '${_data?['group_name'] ?? tr(context, 'Выбрать группу', 'Choose a group')}',
                  navigation: true,
                  onTap: _busy ? null : _chooseGroup,
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
                      child: days.isEmpty
                          ? const SizedBox(height: 64)
                          : BrockmannPicker(
                              label: tr(context, 'День', 'Day'),
                              options: [
                                for (final day in days)
                                  _dateLabel(context, day['date']),
                              ],
                              selected: _day,
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() => _day = value),
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
                SizedBox(
                  height: 20,
                  child: _busy ? const CampusProgress.compact() : null,
                ),
                if (_cachedAt != null)
                  ServerMessage(
                    isError: false,
                    message: trf(
                      context,
                      'Сохранённое расписание · {time}. Потяните вниз, чтобы обновить.',
                      'Saved schedule · {time}. Pull down to refresh.',
                      {
                        'time':
                            '${MaterialLocalizations.of(context).formatShortDate(_cachedAt!.toLocal())} ${TimeOfDay.fromDateTime(_cachedAt!.toLocal()).format(context)}',
                      },
                    ),
                  ),
                if (_error != null && _cachedAt == null)
                  ServerMessage(message: _error!),
                if (_data?['schedule_error'] != null)
                  ServerMessage(message: '${_data!['schedule_error']}'),
                if (days.isNotEmpty) ...[
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
                            if ([lesson['type'], lesson['teacher']]
                                .whereType<String>()
                                .any((v) => v.trim().isNotEmpty))
                              BrockmannText(
                                [lesson['type'], lesson['teacher']]
                                    .whereType<String>()
                                    .where((v) => v.trim().isNotEmpty)
                                    .join(' · '),
                                color: context.brockmann.secondary,
                              ),
                            if ('${lesson['location'] ?? ''}'.isNotEmpty)
                              CampusButton.text(
                                onPressed: () =>
                                    _openMap(room: '${lesson['location']}'),
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
                });
                refresh(goToToday: true);
              },
            ),
            CampusCommand(
              icon: Icons.map_outlined,
              label: tr(context, 'Карты', 'Maps'),
              onPressed: _openMap,
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

String _dateLabel(BuildContext context, Object? value) {
  final date = value is String ? DateTime.tryParse(value) : null;
  return date == null
      ? '—'
      : MaterialLocalizations.of(context).formatMediumDate(date);
}
