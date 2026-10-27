import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';
import 'feedback.dart';
import 'foundation.dart';
import 'navigation.dart';
import 'interaction.dart';

/// A localized, typography-led calendar. Selection is controlled by its owner;
/// the dialog helper keeps it as a draft until the user chooses "use date".
class BrockmannCalendar extends StatefulWidget {
  BrockmannCalendar({
    super.key,
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.onChanged,
  }) : assert(
         !DateUtils.dateOnly(lastDate).isBefore(DateUtils.dateOnly(firstDate)),
       );
  final DateTime value, firstDate, lastDate;
  final ValueChanged<DateTime> onChanged;
  @override
  State<BrockmannCalendar> createState() => _BrockmannCalendarState();
}

class _BrockmannCalendarState extends State<BrockmannCalendar> {
  late DateTime _month = DateTime(widget.value.year, widget.value.month);
  @override
  void didUpdateWidget(BrockmannCalendar old) {
    super.didUpdateWidget(old);
    if (!DateUtils.isSameDay(widget.value, old.value)) {
      _month = DateTime(widget.value.year, widget.value.month);
    }
  }

  void move(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann, locale = MaterialLocalizations.of(context);
    final first = DateUtils.dateOnly(widget.firstDate),
        last = DateUtils.dateOnly(widget.lastDate);
    final previous = DateTime(_month.year, _month.month, 0),
        next = DateTime(_month.year, _month.month + 1);
    final offset = (_month.weekday % 7 - locale.firstDayOfWeekIndex + 7) % 7;
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final weeks = ((offset + days) / 7).ceil();
    final cellHeight = math.max(
      48.0,
      MediaQuery.textScalerOf(context).scale(16) + 16,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrockmannText(
          locale.formatMonthYear(_month),
          role: BrockmannType.heading,
        ),
        Row(
          children: [
            BrockmannIconButton(
              icon: BrockmannIcon.caretLeft,
              label: locale.previousMonthTooltip,
              onPressed: previous.isBefore(first) ? null : () => move(-1),
            ),
            const Spacer(),
            BrockmannIconButton(
              icon: BrockmannIcon.caretRight,
              label: locale.nextMonthTooltip,
              onPressed: next.isAfter(last) ? null : () => move(1),
            ),
          ],
        ),
        BrockmannPicker(
          label: locale.selectYearSemanticsLabel,
          options: [for (var y = first.year; y <= last.year; y++) '$y'],
          selected: _month.year - first.year,
          presentation: BrockmannPickerPresentation.anchored,
          onChanged: (i) => setState(() {
            final year = first.year + i;
            var month = _month.month;
            if (year == first.year) month = math.max(month, first.month);
            if (year == last.year) month = math.min(month, last.month);
            _month = DateTime(year, month);
          }),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: BrockmannText(
                    locale.narrowWeekdays[(i + locale.firstDayOfWeekIndex) % 7],
                    role: BrockmannType.caption,
                    color: t.secondary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < weeks; row++)
          Row(
            children: [
              for (var column = 0; column < 7; column++)
                Expanded(
                  child: Builder(
                    builder: (c) {
                      final day = row * 7 + column - offset + 1;
                      if (day < 1 || day > days) {
                        return SizedBox(height: cellHeight);
                      }
                      final date = DateTime(_month.year, _month.month, day);
                      final enabled =
                          !date.isBefore(first) && !date.isAfter(last);
                      final selected = DateUtils.isSameDay(date, widget.value);
                      return Semantics(
                        selected: selected,
                        child: BrockmannPressable(
                          label: locale.formatFullDate(date),
                          onPressed: enabled
                              ? () {
                                  if (!DateUtils.isSameDay(
                                    date,
                                    widget.value,
                                  )) {
                                    BrockmannFeedbackScope.of(context)
                                        ?.selection();
                                    widget.onChanged(date);
                                  }
                                }
                              : null,
                          builder: (c, p) => AnimatedContainer(
                            key: ValueKey(
                              'brockmann-date-${date.year}-${date.month}-$day',
                            ),
                            duration: t.duration(c, 160),
                            height: cellHeight,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? t.foreground
                                  : Colors.transparent,
                              border: Border.all(
                                color: DateUtils.isSameDay(date, DateTime.now())
                                    ? t.lineStrong
                                    : Colors.transparent,
                              ),
                            ),
                            child: BrockmannText(
                              locale.formatDecimal(day),
                              role: BrockmannType.body,
                              color: !enabled
                                  ? t.disabled
                                  : selected
                                  ? t.background
                                  : t.foreground,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// A controlled 24-hour time editor. Numerals, selection rules and scroll
/// position communicate the choice; no clock-face icons or Material dial.
class BrockmannTimePicker extends StatelessWidget {
  const BrockmannTimePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrockmannText(
          MaterialLocalizations.of(context)
              .formatTimeOfDay(value, alwaysUse24HourFormat: true),
          role: BrockmannType.monoLarge,
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _NumberWheel(
                label: 'hour',
                value: value.hour,
                count: 24,
                onChanged: (v) =>
                    onChanged(TimeOfDay(hour: v, minute: value.minute)),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _NumberWheel(
                label: 'minute',
                value: value.minute,
                count: 60,
                onChanged: (v) =>
                    onChanged(TimeOfDay(hour: value.hour, minute: v)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NumberWheel extends StatefulWidget {
  const _NumberWheel({
    required this.label,
    required this.value,
    required this.count,
    required this.onChanged,
  });
  final String label;
  final int value, count;
  final ValueChanged<int> onChanged;
  @override
  State<_NumberWheel> createState() => _NumberWheelState();
}

class _NumberWheelState extends State<_NumberWheel> {
  int? _scrollStart;
  void _step(int value) {
    BrockmannFeedbackScope.of(context)?.selection();
    widget.onChanged(value);
  }

  late final _controller = FixedExtentScrollController(
    initialItem: widget.value,
  );
  @override
  void didUpdateWidget(_NumberWheel old) {
    super.didUpdateWidget(old);
    if (_controller.hasClients && _controller.selectedItem != widget.value) {
      _controller.jumpToItem(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    final height = math.max(
      64.0,
      MediaQuery.textScalerOf(context).scale(36) + 16,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrockmannText(
          widget.label,
          role: BrockmannType.label,
          color: t.secondary,
        ),
        const SizedBox(height: 8),
        Semantics(
          label: widget.label,
          value: widget.value.toString().padLeft(2, '0'),
          slider: true,
          increasedValue: math
              .min(widget.count - 1, widget.value + 1)
              .toString()
              .padLeft(2, '0'),
          decreasedValue: math
              .max(0, widget.value - 1)
              .toString()
              .padLeft(2, '0'),
          onIncrease: widget.value < widget.count - 1
              ? () => _step(widget.value + 1)
              : null,
          onDecrease: widget.value > 0 ? () => _step(widget.value - 1) : null,
          child: BrockmannInteractionRegion(
            child: SizedBox(
              height: height * 3,
              child: Stack(
                children: [
                  Positioned(
                    top: height,
                    left: 0,
                    right: 0,
                    height: height,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.symmetric(
                          horizontal: BorderSide(color: t.lineStrong),
                        ),
                      ),
                    ),
                  ),
                  ExcludeSemantics(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n is ScrollStartNotification &&
                            n.dragDetails != null) {
                          _scrollStart = widget.value;
                        }
                        if (n is ScrollEndNotification &&
                            _scrollStart != null) {
                          if (_scrollStart != widget.value) {
                            BrockmannFeedbackScope.of(context)?.selection();
                          }
                          _scrollStart = null;
                        }
                        return false;
                      },
                      child: ListWheelScrollView.useDelegate(
                        key: ValueKey('brockmann-time-${widget.label}'),
                        controller: _controller,
                        itemExtent: height,
                        physics: const FixedExtentScrollPhysics(),
                        diameterRatio: 1.5,
                        perspective: .002,
                        overAndUnderCenterOpacity: .35,
                        onSelectedItemChanged: (v) {
                          if (v != widget.value) widget.onChanged(v);
                        },
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: widget.count,
                          builder: (c, i) => Center(
                            child: BrockmannText(
                              i.toString().padLeft(2, '0'),
                              role: BrockmannType.monoLarge,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
