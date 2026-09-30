import 'package:flutter/material.dart';

String tr(BuildContext context, String ru, String en) =>
    Localizations.localeOf(context).languageCode == 'ru' ? ru : en;

String trMessage(BuildContext context, String message) {
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
  };
  if (Localizations.localeOf(context).languageCode == 'ru') return message;
  if (messages.containsKey(message)) return messages[message]!;
  return message
      .replaceFirst('Пульс вернул HTTP ', 'Pulse returned HTTP ')
      .replaceFirst(
        'Пульс отклонил запрос (gRPC ',
        'Pulse rejected the request (gRPC ',
      )
      .replaceFirst('формат', 'format');
}
