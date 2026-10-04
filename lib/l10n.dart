import 'package:material_ui/material_ui.dart';

import 'translations.dart';

String tr(BuildContext context, String ru, String en) {
  final language = Localizations.localeOf(context).languageCode;
  if (language == 'ru') return ru;
  final translation = translations[en];
  return switch (language) {
    'fr' => translation?.$1 ?? en,
    'pt' => translation?.$2 ?? en,
    'zh' => translation?.$3 ?? en,
    _ => en,
  };
}

String trf(
  BuildContext context,
  String ru,
  String en,
  Map<String, Object> values,
) {
  var result = tr(context, ru, en);
  for (final entry in values.entries) {
    result = result.replaceAll('{${entry.key}}', '${entry.value}');
  }
  return result;
}

String classCountLabel(BuildContext context, int count) {
  final language = Localizations.localeOf(context).languageCode;
  return switch (language) {
    'ru' =>
      '$count ${count % 10 == 1 && count % 100 != 11
          ? 'занятие'
          : count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 12 || count % 100 > 14)
          ? 'занятия'
          : 'занятий'}',
    'fr' => '$count cours',
    'pt' => '$count ${count == 1 ? 'aula' : 'aulas'}',
    'zh' => '$count 节课',
    _ => '$count ${count == 1 ? 'class' : 'classes'}',
  };
}

String trMessage(BuildContext context, String message) {
  const russianCopy = {
    'Присутствие подтверждено': 'Отметка подтверждена',
    'Ожидается подтверждение': 'Ждём подтверждения',
    'Аккаунт не записан на занятие': 'Аккаунт не записан на эту пару',
    'Журнал занятия в архиве': 'Занятие уже в архиве',
    'Пульс не подтвердил присутствие': 'Пульс не подтвердил отметку',
    'Сессия истекла. Войдите в аккаунт снова.':
        'Сессия истекла. Войдите снова.',
  };
  const messages = {
    'Присутствие подтверждено': 'Attendance confirmed',
    'Отправка…': 'Submitting…',
    'Сессия сохранена': 'Session saved',
    'Не удалось подготовить вход.': 'Could not prepare sign-in.',
    'Не удалось открыть страницу входа.': 'Could not open the sign-in page.',
    'Неверный или просроченный QR-код': 'Invalid or expired QR code',
    'Ожидается подтверждение': 'Waiting for confirmation',
    'Аккаунт не записан на занятие': 'Account is not enrolled in this class',
    'Журнал занятия в архиве': 'Class record is archived',
    'Присутствие в кампусе не подтверждено': 'Campus presence is not confirmed',
    'Указано уважительное отсутствие': 'Excused absence recorded',
    'Указано нарушение распорядка': 'Conduct violation recorded',
    'Пульс не подтвердил присутствие': 'Pulse did not confirm attendance',
    'Сессия истекла. Войдите в аккаунт снова.':
        'Session expired. Sign in again.',
    'Ошибка сети. Попробуйте снова.': 'Network error. Try again.',
    'Пульс не вернул результат.': 'Pulse did not return a result.',
    'Неизвестный результат Пульса.': 'Unknown Pulse result.',
    'Некорректный ответ Пульса.': 'Invalid Pulse response.',
    'Неподдерживаемый ответ Пульса.': 'Unsupported Pulse response.',
    'Некорректный protobuf-ответ.': 'Invalid protobuf response.',
    'Неподдерживаемый protobuf-ответ.': 'Unsupported protobuf response.',
    'Ответ Пульса слишком большой.': 'Pulse response is too large.',
    'Это не ссылка на посещаемость Пульса.':
        'This is not a Pulse attendance link.',
    'В QR-коде нет корректного токена занятия.':
        'The QR code has no valid class token.',
    'Сессия Пульса не найдена.': 'Pulse session not found.',
    'Некорректная сессия Пульса.': 'Invalid Pulse session.',
    'Сессия Пульса неполная.': 'Incomplete Pulse session.',
  };
  final english = messages[message];
  if (english != null) {
    return tr(context, russianCopy[message] ?? message, english);
  }
  if (message.startsWith('Пульс вернул HTTP ')) {
    return message.replaceFirst(
      'Пульс вернул HTTP ',
      tr(context, 'Пульс вернул HTTP ', 'Pulse returned HTTP '),
    );
  }
  if (message.startsWith('Пульс отклонил запрос (gRPC ')) {
    return message
        .replaceFirst(
          'Пульс отклонил запрос (gRPC ',
          tr(
            context,
            'Пульс отклонил запрос (gRPC ',
            'Pulse rejected the request (gRPC ',
          ),
        )
        .replaceFirst('формат', tr(context, 'формат', 'format'));
  }
  return message;
}
