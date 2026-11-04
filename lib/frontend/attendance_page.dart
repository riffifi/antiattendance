import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import '../accounts.dart';
import '../attendance_log.dart';
import '../campus_design.dart';
import '../expressive.dart';
import '../l10n.dart';
import '../pulse_api.dart';
import 'attendance_account_row.dart';
import 'page_layout.dart';

enum AttendanceAction { share, receive, group, restore }

/// Presentation only. Storage, authentication and submission stay with the host.
class AttendancePage extends StatefulWidget {
  const AttendancePage({
    super.key,
    required this.accounts,
    required this.selected,
    required this.groupId,
    required this.counts,
    required this.results,
    required this.errors,
    required this.sessionChecks,
    required this.checkingSessions,
    required this.busy,
    required this.submitting,
    required this.legacyMode,
    required this.onRefresh,
    required this.onAdd,
    required this.onReceive,
    required this.onManage,
    required this.onGroupChanged,
    required this.onToggle,
    required this.onToggleAll,
    required this.onCheckSession,
    required this.onReauth,
    required this.onRename,
    required this.onGroup,
    required this.onRemove,
  });
  final List<SavedAccount> accounts;
  final Set<String> selected, checkingSessions;
  final int? groupId;
  final Map<String, AttendanceCounts>? counts;
  final Map<String, ApprovalResult> results;
  final Map<String, String> errors, sessionChecks;
  final bool busy, submitting, legacyMode;
  final Future<void> Function() onRefresh;
  final VoidCallback onAdd, onReceive;
  final ValueChanged<AttendanceAction> onManage;
  final ValueChanged<int?> onGroupChanged;
  final ValueChanged<SavedAccount> onToggle,
      onCheckSession,
      onReauth,
      onRename,
      onGroup,
      onRemove;
  final ValueChanged<Set<String>> onToggleAll;
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final _search = TextEditingController();
  String _query = '';
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupAccounts = widget.accounts
        .where(
          (a) =>
              widget.groupId == null ||
              (widget.groupId == 0
                  ? a.groupId == null
                  : a.groupId == widget.groupId),
        )
        .toList();
    final visible = groupAccounts
        .where(
          (a) =>
              '${a.label} ${a.groupName ?? ''}'.toLowerCase().contains(_query),
        )
        .toList();
    final visibleIds = visible.map((a) => a.id).toSet();
    final allSelected =
        visibleIds.isNotEmpty && visibleIds.every(widget.selected.contains);
    final expired = groupAccounts
        .where((a) => a.isExpiredAt(DateTime.now()))
        .length;
    final groups = <int, String>{
      for (final a in widget.accounts)
        if (a.groupId != null) a.groupId!: a.groupName ?? '${a.groupId}',
    };
    final manage = <CampusMenuEntry>[
      if (widget.legacyMode)
        CampusMenuEntry(
          value: AttendanceAction.share,
          label: tr(context, 'Передать', 'Share'),
        ),
      if (widget.legacyMode)
        CampusMenuEntry(
          value: AttendanceAction.receive,
          label: tr(context, 'Получить', 'Receive'),
        ),
      if (widget.selected.isNotEmpty)
        CampusMenuEntry(
          value: AttendanceAction.group,
          label: tr(context, 'Назначить группу', 'Assign group'),
        ),
      if (widget.accounts.any(
        (a) => widget.selected.contains(a.id) && a.isExpiredAt(DateTime.now()),
      ))
        CampusMenuEntry(
          value: AttendanceAction.restore,
          label: tr(context, 'Восстановить вход', 'Restore sessions'),
        ),
    ];
    return RefreshIndicator(
      onRefresh: widget.busy ? () async {} : widget.onRefresh,
      child: CustomScrollView(
        key: const PageStorageKey('attendance-tab'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: AaPageLayout.insets(context).copyWith(bottom: 0),
            sliver: SliverList.list(
              children: [
                CampusHeader(
                  title: tr(context, 'Ваши аккаунты', 'Your accounts'),
                  subtitle: tr(
                    context,
                    'Выберите аккаунты и сканируйте QR-код.',
                    'Choose accounts, then scan a QR.',
                  ),
                ),
                if (widget.accounts.isNotEmpty) ...[
                  AppPassPicker(
                    enabled: !widget.busy,
                    hint: tr(context, 'Группа', 'Group'),
                    items: [
                      PassPickerItem(
                        value: '',
                        label: tr(context, 'Все группы', 'All groups'),
                        selected: widget.groupId == null,
                      ),
                      for (final group in groups.entries)
                        PassPickerItem(
                          value: '${group.key}',
                          label: group.value,
                          selected: widget.groupId == group.key,
                        ),
                      if (widget.accounts.any((a) => a.groupId == null))
                        PassPickerItem(
                          value: '0',
                          label: tr(context, 'Без группы', 'No group'),
                          selected: widget.groupId == 0,
                        ),
                    ],
                    onChanged: (items) =>
                        widget.onGroupChanged(int.tryParse(items.first.value)),
                  ),
                  if (expired > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: BrockmannText(
                        trf(
                          context,
                          'Нужен повторный вход: {count}',
                          'Sign-in needed: {count}',
                          {'count': expired},
                        ),
                        role: BrockmannType.caption,
                        color: context.brockmann.danger,
                      ),
                    ),
                ],
                AaSectionHeading(
                  title: tr(context, 'Аккаунты', 'Accounts'),
                  action: CampusButton.text(
                    onPressed: widget.busy ? null : widget.onAdd,
                    child: Text(tr(context, 'Добавить', 'Add')),
                  ),
                ),
                if (widget.accounts.isEmpty)
                  AaEmptyState(
                    title: tr(context, 'Пока нет аккаунтов', 'No accounts yet'),
                    detail: widget.legacyMode
                        ? tr(
                            context,
                            'Добавьте первый аккаунт через МИРЭА.',
                            'Add your first account through MIREA.',
                          )
                        : tr(
                            context,
                            'Подключите сервер в настройках и добавьте аккаунт на сервере.',
                            'Connect a server in Settings and add an account on the server.',
                          ),
                    action: widget.legacyMode
                        ? CampusButton.text(
                            onPressed: widget.busy ? null : widget.onReceive,
                            child: Text(tr(context, 'Получить', 'Receive')),
                          )
                        : null,
                  )
                else ...[
                  if (groupAccounts.length > 5 || _query.isNotEmpty) ...[
                    CampusTextField(
                      controller: _search,
                      label: tr(
                        context,
                        'Найти аккаунт или группу',
                        'Search accounts or groups',
                      ),
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                      trailing: _query.isEmpty
                          ? null
                          : CampusTextAction(
                              tooltip: tr(
                                context,
                                'Очистить поиск',
                                'Clear search',
                              ),
                              label: tr(context, 'очистить', 'clear'),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    children: [
                      CampusButton.text(
                        onPressed: widget.busy || visibleIds.isEmpty
                            ? null
                            : () => widget.onToggleAll(visibleIds),
                        child: Text(
                          allSelected
                              ? tr(context, 'Снять выбор', 'Clear selection')
                              : tr(context, 'Выбрать все', 'Select all'),
                        ),
                      ),
                      if (manage.isNotEmpty)
                        AppActionMenu(
                          entries: manage,
                          onSelected: (value) =>
                              widget.onManage(value as AttendanceAction),
                          anchorBuilder: (context, open) => CampusButton.text(
                            onPressed: widget.busy ? null : open,
                            child: Text(tr(context, 'Управление', 'Manage')),
                          ),
                        ),
                    ],
                  ),
                  if (widget.submitting) ...[
                    const SizedBox(height: 12),
                    const CampusProgress.linear(),
                    BrockmannText(
                      tr(
                        context,
                        'Отправляем отметки…',
                        'Submitting attendance…',
                      ),
                      role: BrockmannType.caption,
                    ),
                  ],
                  if (visible.isEmpty)
                    AaEmptyState(
                      title: tr(
                        context,
                        'Ничего не найдено.',
                        'No matches found.',
                      ),
                      detail: tr(
                        context,
                        'Измените поиск или выберите другую группу.',
                        'Change your search or choose another group.',
                      ),
                    ),
                ],
              ],
            ),
          ),
          SliverPadding(
            padding: AaPageLayout.insets(context).copyWith(top: 0),
            sliver: SliverList.builder(
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final account = visible[index];
                return AttendanceAccountRow(
                  key: ValueKey(account.id),
                  account: account,
                  counts: widget.counts == null
                      ? null
                      : widget.counts![account.id] ?? AttendanceCounts.zero,
                  selected: widget.selected.contains(account.id),
                  busy: widget.busy,
                  result: widget.results[account.id],
                  error: widget.errors[account.id],
                  sessionCheck: widget.sessionChecks[account.id],
                  checkingSession: widget.checkingSessions.contains(account.id),
                  onTap: () => widget.onToggle(account),
                  onCheckSession: () => widget.onCheckSession(account),
                  onReauth: () => widget.onReauth(account),
                  onRename: () => widget.onRename(account),
                  onGroup: () => widget.onGroup(account),
                  onRemove: () => widget.onRemove(account),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AttendanceActionBar extends StatelessWidget {
  const AttendanceActionBar({
    super.key,
    required this.selectedCount,
    required this.busy,
    required this.onScan,
    required this.onPaste,
  });
  final int selectedCount;
  final bool busy;
  final VoidCallback onScan, onPaste;
  @override
  Widget build(BuildContext context) => BrockmannInteractionRegion(
    child: Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AaPageLayout.maxWidth),
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.brockmann.line)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scan = CampusButton.action(
                onPressed: busy || selectedCount == 0 ? null : onScan,
                label: Text(
                  trf(
                    context,
                    'Сканировать QR · {count}',
                    'Scan QR · {count}',
                    {'count': selectedCount},
                  ),
                ),
              );
              final paste = CampusTextAction(
                onPressed: busy || selectedCount == 0 ? null : onPaste,
                tooltip: tr(context, 'Вставить ссылку', 'Paste link'),
                label: tr(context, 'вставить', 'paste'),
              );
              if (constraints.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(16) > 24) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [scan, paste],
                );
              }
              return Row(
                children: [
                  Expanded(child: scan),
                  const SizedBox(width: 8),
                  paste,
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
