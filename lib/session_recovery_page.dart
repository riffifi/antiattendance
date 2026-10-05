import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import 'accounts.dart';
import 'app_theme.dart';
import 'campus_design.dart';
import 'l10n.dart';
import 'pulse_login.dart';
import 'session_check.dart';

typedef SessionLogin = Future<SavedAccount?> Function(
  BuildContext,
  SavedAccount,
);

class SessionRecoveryPage extends StatefulWidget {
  const SessionRecoveryPage({
    super.key,
    required this.accounts,
    required this.onSave,
    this.onExpired,
    this.checker = checkSession,
    this.login = openRecoveryLogin,
  });
  final List<SavedAccount> accounts;
  final Future<void> Function(SavedAccount, SavedAccount) onSave;
  final Future<void> Function(SavedAccount)? onExpired;
  final Future<SessionCheckResult> Function(SavedAccount) checker;
  final SessionLogin login;

  static Future<SavedAccount?> openRecoveryLogin(
    BuildContext context,
    SavedAccount account,
  ) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      M3ESnackbar.show(
        context,
        message: tr(
          context,
          'Вход через МИРЭА доступен на Android и iOS.',
          'MIREA sign-in is available on Android and iOS.',
        ),
      );
      return null;
    }
    return Navigator.of(context).push<SavedAccount>(
      MaterialPageRoute(
        builder: (_) => PulseLoginPage(accountLabel: account.label),
      ),
    );
  }

  @override
  State<SessionRecoveryPage> createState() => _SessionRecoveryPageState();
}

class _SessionRecoveryPageState extends State<SessionRecoveryPage> {
  late final List<SavedAccount> _accounts = List.of(widget.accounts);
  final _states = <String, SessionCheckState>{};
  final _checking = <String>{};
  final _restored = <String>{};
  final _skipped = <String>{};
  bool _busy = false;
  bool _paused = false;
  String? _activeId;
  String? _error;
  Future<void> _persistence = Future.value();

  Future<void> _persist(Future<void> Function() action) {
    final next = _persistence.then((_) => action());
    _persistence = next.catchError((Object _) {});
    return next;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAll());
  }

  Future<void> _check(SavedAccount account) async {
    if (!mounted) return;
    setState(() => _checking.add(account.id));
    try {
      final result = await widget.checker(account);
      if (!mounted) return;
      if (result.state == SessionCheckState.expired) {
        await _persist(() async => widget.onExpired?.call(account));
      }
      if (result.state == SessionCheckState.valid &&
          account.isExpiredAt(DateTime.now())) {
        final next = SavedAccount(
          id: account.id,
          label: account.label,
          cookie: account.cookie,
          expiresAt:
              account.expiresAt != null &&
                  account.expiresAt!.isAfter(DateTime.now())
              ? account.expiresAt
              : null,
          groupId: account.groupId,
          groupName: account.groupName,
        );
        await _persist(() => widget.onSave(account, next));
        if (mounted) {
          _accounts[_accounts.indexWhere((a) => a.id == account.id)] = next;
        }
      }
      if (mounted) {
        setState(() {
          _states[account.id] = result.state;
          if (result.state != SessionCheckState.valid) {
            _restored.remove(account.id);
          }
          if (result.state == SessionCheckState.valid) {
            _skipped.remove(account.id);
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _states[account.id] = SessionCheckState.unavailable);
      }
    } finally {
      if (mounted) setState(() => _checking.remove(account.id));
    }
  }

  Future<void> _checkAll() async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var index = 0;
    // Bound concurrency for large groups without making the user wait for each timeout.
    Future<void> worker() async {
      while (mounted && index < _accounts.length) {
        final account = _accounts[index++];
        await _check(account);
      }
    }

    await Future.wait(
      List.generate(
        _accounts.length < 4 ? _accounts.length : 4,
        (_) => worker(),
      ),
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restore(SavedAccount account) async {
    if (!mounted) return;
    setState(() {
      _activeId = account.id;
      _error = null;
    });
    try {
      final session = await widget.login(context, account);
      if (!mounted) return;
      if (session == null) {
        setState(() {
          _skipped.add(account.id);
          _paused = true;
        });
        return;
      }
      final check = await widget.checker(session);
      if (!mounted) return;
      if (check.state != SessionCheckState.valid) {
        setState(
          () => _error = tr(
            context,
            'Новый вход не удалось подтвердить. Старый аккаунт сохранён; повторите позже.',
            'Could not confirm the new sign-in. Your saved account is kept; try again later.',
          ),
        );
        return;
      }
      final next = SavedAccount(
        id: account.id,
        label: account.label,
        cookie: session.cookie,
        expiresAt: session.expiresAt,
        groupId: account.groupId,
        groupName: account.groupName,
      );
      await widget.onSave(account, next);
      if (!mounted) return;
      setState(() {
        _accounts[_accounts.indexWhere((a) => a.id == account.id)] = next;
        _states[account.id] = SessionCheckState.valid;
        _restored.add(account.id);
        _skipped.remove(account.id);
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(
            context,
            'Не удалось сохранить новый вход. Повторите для этого аккаунта.',
            'Could not save the new sign-in. Retry this account.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _activeId = null);
    }
  }

  Future<void> _restoreAll() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _paused = false;
    });
    final pending = _accounts
        .where((a) => _states[a.id] == SessionCheckState.expired)
        .toList();
    final ordered = [
      ...pending.where((a) => !_skipped.contains(a.id)),
      ...pending.where((a) => _skipped.contains(a.id)),
    ];
    for (final account in ordered) {
      if (!mounted) return;
      await _restore(account);
      // A failed validation/save needs attention before opening another login.
      if (_error != null || _paused) break;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restoreOne(SavedAccount account) async {
    setState(() => _busy = true);
    await _restore(account);
    if (mounted) setState(() => _busy = false);
  }

  String _status(SavedAccount account) {
    if (_checking.contains(account.id)) {
      return tr(context, 'Проверяем сессию…', 'Checking session…');
    }
    if (_restored.contains(account.id)) {
      return tr(context, 'Вход восстановлен', 'Sign-in restored');
    }
    if (_skipped.contains(account.id)) {
      return tr(
        context,
        'Пропущен — можно продолжить позже',
        'Skipped — resume later',
      );
    }
    if (!_states.containsKey(account.id)) {
      return tr(context, 'Подождите…', 'Please wait…');
    }
    return switch (_states[account.id]) {
      SessionCheckState.valid => tr(
        context,
        'Сессия действительна',
        'Session is valid',
      ),
      SessionCheckState.expired => tr(
        context,
        'Нужно войти снова',
        'Sign-in needed',
      ),
      SessionCheckState.forbidden => tr(
        context,
        'Доступ к сервису запрещён',
        'Service access denied',
      ),
      _ => tr(
        context,
        'Не удалось проверить сессию.',
        'Could not check the session.',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final expired = _accounts
        .where((a) => _states[a.id] == SessionCheckState.expired)
        .length;
    final valid = _accounts
        .where((a) => _states[a.id] == SessionCheckState.valid)
        .length;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Восстановить вход', 'Restore sessions')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trf(
                              context,
                              'Готовы: {valid} · Требуют входа: {expired}',
                              'Ready: {valid} · Need sign-in: {expired}',
                              {'valid': valid, 'expired': expired},
                            ),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr(
                              context,
                              'Проверим выбранные аккаунты и восстановим только истёкшие сессии. Имена, группы и история сохранятся. Закройте вход, чтобы пропустить владельца. При необходимости NFC-пропуск подключается отдельно.',
                              'Check selected accounts and restore only expired sessions. Names, groups, and history stay saved. Close a login to skip its owner. NFC passes are enrolled separately when needed.',
                            ),
                            style: TextStyle(color: context.palette.muted),
                          ),
                          if (_busy) ...[
                            const SizedBox(height: 12),
                            const M3EProgressIndicator.linearWavy(),
                          ],
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList.builder(
                      itemCount: _accounts.length,
                      itemBuilder: (context, index) {
                        final account = _accounts[index];
                        final state = _states[account.id];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: M3EListItem(
                            leading: Icon(
                              _restored.contains(account.id) ||
                                      state == SessionCheckState.valid
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.person_outline_rounded,
                              color: state == SessionCheckState.valid
                                  ? context.palette.success
                                  : context.palette.muted,
                            ),
                            headline: account.label,
                            supportingText:
                                '${account.groupName == null ? '' : '${account.groupName}\n'}${_status(account)}',
                            trailing: state == SessionCheckState.expired
                                ? CampusButton.text(
                                    onPressed: _busy
                                        ? null
                                        : () => _restoreOne(account),
                                    child: Text(
                                      tr(
                                        context,
                                        'Войти снова',
                                        'Sign in again',
                                      ),
                                    ),
                                  )
                                : state != SessionCheckState.valid &&
                                      !_checking.contains(account.id)
                                ? CampusButton.text(
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                            setState(() => _busy = true);
                                            await _check(account);
                                            if (mounted) {
                                              setState(() => _busy = false);
                                            }
                                          },
                                    child: Text(
                                      tr(context, 'Повторить', 'Retry'),
                                    ),
                                  )
                                : null,
                            selected: account.id == _activeId,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: CampusButton.filled(
                      onPressed: _busy || expired == 0 ? null : _restoreAll,
                      child: Text(
                        trf(
                          context,
                          'Восстановить входы: {count}',
                          'Restore sign-ins: {count}',
                          {'count': expired},
                        ),
                      ),
                    ),
                  ),
                  CampusButton.text(
                    onPressed: _busy ? null : _checkAll,
                    child: Text(tr(context, 'Проверить снова', 'Check again')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
