import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import '../accounts.dart';
import '../app_theme.dart';
import '../attendance_log.dart';
import '../campus_design.dart';
import '../expressive.dart';
import '../l10n.dart';
import '../pulse_api.dart';

class AttendanceAccountRow extends StatelessWidget {
  const AttendanceAccountRow({
    super.key,
    required this.account,
    required this.counts,
    required this.selected,
    required this.busy,
    required this.result,
    required this.error,
    required this.onTap,
    required this.onReauth,
    required this.onCheckSession,
    this.sessionCheck,
    this.checkingSession = false,
    required this.onRename,
    required this.onGroup,
    required this.onRemove,
  });

  final SavedAccount account;
  final AttendanceCounts? counts;
  final bool selected;
  final bool busy;
  final ApprovalResult? result;
  final String? error;
  final VoidCallback onTap;
  final VoidCallback onReauth;
  final VoidCallback onCheckSession;
  final String? sessionCheck;
  final bool checkingSession;
  final VoidCallback onRename;
  final VoidCallback onGroup;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final expired = account.isExpiredAt(DateTime.now());
    final expiry = account.expiresAt?.toLocal();
    final date = expiry == null
        ? null
        : '${MaterialLocalizations.of(context).formatMediumDate(expiry)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(expiry), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
    final sessionStatus = expired
        ? tr(
            context,
            'Сессия истекла. Войдите снова.',
            'Session expired. Sign in again.',
          )
        : date == null
        ? tr(
            context,
            'Срок действия сессии неизвестен',
            'Session expiry unknown',
          )
        : trf(context, 'Сессия истекает: {date}', 'Session expires: {date}', {
            'date': date,
          });
    final status =
        error ?? result?.message ?? (busy && selected ? 'Отправка…' : null);
    final color = error != null || result?.state == ApprovalState.rejected
        ? Theme.of(context).colorScheme.error
        : result?.state == ApprovalState.approved
        ? context.palette.success
        : context.palette.muted;
    final t = context.brockmann;
    return BrockmannPressable(
      label: '',
      excludeSemantics: false,
      selected: selected,
      onPressed: busy ? null : onTap,
      builder: (context, pressed) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: pressed ? t.surface : null,
          border: Border(bottom: BorderSide(color: t.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CampusCheckbox(
              value: selected,
              onChanged: busy ? null : (_) => onTap(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BrockmannText(account.label, role: BrockmannType.value, weight: 400),
                  if (account.groupName != null) ...[
                    const SizedBox(height: 4),
                    BrockmannText(
                      account.groupName!,
                      role: BrockmannType.caption,
                      color: t.secondary,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _countText(context, 'Сегодня', 'Today', counts?.today),
                      _countText(context, 'Неделя', 'Week', counts?.week),
                    ],
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 8),
                    BrockmannText(
                      trMessage(context, status),
                      role: BrockmannType.caption,
                      color: color,
                    ),
                  ],
                  if (expired) ...[
                    const SizedBox(height: 8),
                    BrockmannText(
                      sessionStatus,
                      role: BrockmannType.caption,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ],
                  if (sessionCheck != null &&
                      sessionCheck != sessionStatus) ...[
                    const SizedBox(height: 8),
                    BrockmannText(
                      sessionCheck!,
                      role: BrockmannType.caption,
                      color: t.secondary,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 48,
              child: AppActionMenu(
                title: account.label,
                entries: [
                  CampusMenuEntry(
                    value: 'details',
                    label: tr(context, 'Подробнее', 'Details'),
                  ),
                  CampusMenuEntry(
                    value: 'checkSession',
                    label: tr(context, 'Проверить сессию', 'Check session'),
                  ),
                  CampusMenuEntry(
                    value: 'rename',
                    label: tr(context, 'Переименовать', 'Rename'),
                  ),
                  CampusMenuEntry(
                    value: 'login',
                    label: tr(context, 'Войти снова', 'Sign in again'),
                  ),
                  CampusMenuEntry(
                    value: 'group',
                    label: tr(context, 'Выбрать группу', 'Choose group'),
                  ),
                  CampusMenuEntry(
                    value: 'remove',
                    label: tr(context, 'Удалить', 'Delete'),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'details') {
                    showExpressiveSheet<void>(
                      context: context,
                      compact: true,
                      builder: (context) => Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BrockmannText(
                              account.label,
                              role: BrockmannType.heading,
                              weight: 400,
                            ),
                            const SizedBox(height: 12),
                            BrockmannText(sessionStatus),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                _countText(
                                  context,
                                  'Сегодня',
                                  'Today',
                                  counts?.today,
                                ),
                                _countText(
                                  context,
                                  'Неделя',
                                  'Week',
                                  counts?.week,
                                ),
                                _countText(
                                  context,
                                  'Всего',
                                  'Total',
                                  counts?.total,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (value == 'checkSession' && !checkingSession) {
                    onCheckSession();
                  }
                  if (value == 'login') onReauth();
                  if (value == 'rename') onRename();
                  if (value == 'group') onGroup();
                  if (value == 'remove') onRemove();
                },
                anchorBuilder: (context, open) => CampusTextAction(
                  onPressed: (!busy) ? open : null,
                  tooltip: tr(
                    context,
                    'Действия с аккаунтом',
                    'Account actions',
                  ),
                  label: tr(context, 'действия', 'actions'),
                  icon: Icons.more_horiz_rounded,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countText(BuildContext context, String ru, String en, int? count) =>
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '${tr(context, ru, en)} '),
            TextSpan(
              text: '${count ?? '—'}',
              style: const TextStyle(
                fontFamily: 'GeistMono',
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        style: TextStyle(fontSize: 12, color: context.palette.muted),
      );
}
