import 'package:material_ui/material_ui.dart';

import 'l10n.dart';

/// The app's screens in menu order. The developer screen stays hidden until
/// it is revealed.
abstract final class Screens {
  static const attendance = 0;
  static const today = 1;
  static const schedule = 2;
  static const passes = 3;
  static const aaId = 4;
  static const settings = 5;
  static const developer = 6;

  /// The screens in the menu, without the developer one.
  static const count = 6;

  static const names = [
    'attendance',
    'today',
    'schedule',
    'passes',
    'aa_id',
    'settings',
    'developer',
  ];

  static List<String> labels(BuildContext context) => [
    tr(context, 'Посещаемость', 'Attendance'),
    tr(context, 'Сегодня', 'Today'),
    tr(context, 'Расписание', 'Schedule'),
    tr(context, 'Пропуска', 'Passes'),
    'AA ID',
    tr(context, 'Настройки', 'Settings'),
    tr(context, 'Разработчик', 'Developer'),
  ];
}
