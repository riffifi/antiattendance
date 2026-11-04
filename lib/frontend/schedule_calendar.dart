import 'dart:math' as math;

import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import '../campus_design.dart';
import '../expressive.dart';
import '../l10n.dart';

/// A controlled calendar. It has no API, persistence or attendance dependencies.
class ScheduleCalendar extends StatelessWidget {
  const ScheduleCalendar({
    super.key,
    required this.day,
    required this.today,
    required this.groups,
    required this.groupId,
    required this.lessonDays,
    required this.onDayChanged,
    required this.onGroupChanged,
    required this.onMaps,
    required this.onRefresh,
    required this.loading,
  });
  final DateTime day, today;
  final Map<int, String> groups;
  final int? groupId;
  final Set<DateTime> lessonDays;
  final ValueChanged<DateTime> onDayChanged;
  final ValueChanged<int> onGroupChanged;
  final VoidCallback onMaps, onRefresh;
  final bool loading;
  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  @override
  Widget build(BuildContext context) {
    final week = DateTime.utc(
      day.year,
      day.month,
      day.day,
    ).subtract(Duration(days: day.weekday - 1));
    final names = [
      tr(context, 'Пн', 'Mon'),
      tr(context, 'Вт', 'Tue'),
      tr(context, 'Ср', 'Wed'),
      tr(context, 'Чт', 'Thu'),
      tr(context, 'Пт', 'Fri'),
      tr(context, 'Сб', 'Sat'),
      tr(context, 'Вс', 'Sun'),
    ];
    final localizations = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (groups.isNotEmpty)
          AppPassPicker(
            enabled: true,
            hint: tr(context, 'Группа', 'Group'),
            items: [
              for (final group in groups.entries)
                PassPickerItem(
                  value: '${group.key}',
                  label: group.value,
                  selected: groupId == group.key,
                ),
            ],
            onChanged: (items) => onGroupChanged(int.parse(items.first.value)),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CampusButton.text(
              onPressed: onMaps,
              child: Text(tr(context, 'Карты кампусов', 'Campus maps')),
            ),
            CampusTextAction(
              icon: Icons.refresh_rounded,
              onPressed: groups.isEmpty || loading ? null : onRefresh,
              tooltip: tr(context, 'Обновить', 'Refresh'),
              label: tr(context, 'Обновить', 'Refresh'),
            ),
            if (!_same(day, today))
              CampusButton.text(
                onPressed: () => onDayChanged(today),
                child: Text(tr(context, 'Сегодня', 'Today')),
              ),
          ],
        ),
        if (groups.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              CampusTextAction(
                icon: Icons.chevron_left_rounded,
                onPressed: () =>
                    onDayChanged(day.subtract(const Duration(days: 7))),
                tooltip: tr(context, 'Предыдущая неделя', 'Previous week'),
                label: tr(context, 'назад', 'previous'),
              ),
              Expanded(
                child: CampusButton.text(
                  onPressed: () async {
                    final chosen = await showBrockmannDatePicker(
                      context,
                      initialDate: DateTime(day.year, day.month, day.day),
                      firstDate: DateTime(today.year - 1),
                      lastDate: DateTime(today.year + 2),
                    );
                    if (chosen != null) {
                      onDayChanged(
                        DateTime.utc(chosen.year, chosen.month, chosen.day),
                      );
                    }
                  },
                  child: Text(
                    localizations.formatMonthYear(
                      DateTime(day.year, day.month),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              CampusTextAction(
                icon: Icons.chevron_right_rounded,
                onPressed: () => onDayChanged(day.add(const Duration(days: 7))),
                tooltip: tr(context, 'Следующая неделя', 'Next week'),
                label: tr(context, 'вперёд', 'next'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              final cellWidth = math.max(
                c.maxWidth / 7,
                48.0 *
                    math.min(
                      MediaQuery.textScalerOf(context).scale(14) / 14,
                      2.0,
                    ),
              );
              return BrockmannInteractionRegion(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < 7; i++)
                        SizedBox(
                          width: cellWidth,
                          child: _CalendarDay(
                            day: week.add(Duration(days: i)),
                            label: names[i],
                            selected: _same(week.add(Duration(days: i)), day),
                            today: _same(week.add(Duration(days: i)), today),
                            hasLessons: lessonDays.any(
                              (d) => _same(d, week.add(Duration(days: i))),
                            ),
                            onTap: () =>
                                onDayChanged(week.add(Duration(days: i))),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.day,
    required this.label,
    required this.selected,
    required this.today,
    required this.hasLessons,
    required this.onTap,
  });
  final DateTime day;
  final String label;
  final bool selected, today, hasLessons;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return Semantics(
      label: MaterialLocalizations.of(context)
          .formatFullDate(DateTime(day.year, day.month, day.day)),
      selected: selected,
      child: BrockmannPressable(
        label: '',
        excludeSemantics: false,
        selected: selected,
        onPressed: onTap,
        builder: (context, pressed) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? t.foreground
                : pressed
                ? t.surface
                : null,
            border: Border(
              bottom: BorderSide(
                color: today && !selected ? t.foreground : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: ExcludeSemantics(
            child: Column(
              children: [
                BrockmannText(
                  label,
                  role: BrockmannType.caption,
                  color: selected ? t.background : t.secondary,
                ),
                const SizedBox(height: 4),
                BrockmannText(
                  '${day.day}',
                  role: BrockmannType.value,
                  color: selected ? t.background : t.foreground,
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 3,
                  width: 12,
                  child: ColoredBox(
                    color: hasLessons
                        ? selected
                              ? t.background
                              : t.foreground
                        : Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
