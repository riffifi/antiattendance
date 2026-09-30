import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'accounts.dart';
import 'app_theme.dart';
import 'l10n.dart';
import 'pulse_api.dart';
import 'pulse_login.dart';
import 'qr_scan_page.dart';
import 'queue_scan_page.dart';
import 'session_import_page.dart';
import 'session_share_page.dart';

void main() => runApp(const AntiattendanceApp());

class AntiattendanceApp extends StatelessWidget {
  const AntiattendanceApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pulse attendance',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    supportedLocales: const [Locale('ru'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.store, this.api, this.scanQr});

  final AccountStore? store;
  final PulseApi? api;
  final Future<String?> Function(BuildContext context)? scanQr;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AccountStore _store = widget.store ?? AccountStore();
  late final PulseApi _api = widget.api ?? PulseApi();
  final _selected = <String>{};
  final _results = <String, ApprovalResult>{};
  final _errors = <String, String>{};
  List<SavedAccount> _accounts = [];
  bool _loading = true;
  bool _loadError = false;
  bool _scanning = false;
  bool _submitting = false;

  bool get _busy => _scanning || _submitting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_loading && mounted) setState(() => _loading = true);
    try {
      final accounts = await _store.load();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _selected.addAll(accounts.map((account) => account.id));
        _loading = false;
        _loadError = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = true;
        });
      }
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(trMessage(context, message))));
  }

  Future<String?> _askText({
    required String title,
    required String hint,
    required String action,
    String? initial,
    int? maxLength,
  }) => showDialog<String>(
    context: context,
    builder: (_) => _TextInputDialog(
      title: title,
      hint: hint,
      action: action,
      initial: initial,
      maxLength: maxLength,
    ),
  );

  Future<void> _login({SavedAccount? replace}) async {
    if (_busy) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      _message(tr(context, 'Вход через МИРЭА доступен на Android и iOS.', 'MIREA sign-in is available on Android and iOS.'));
      return;
    }
    final cookie = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const PulseLoginPage()));
    if (!mounted || cookie == null) return;
    final label = await _askText(
      title: tr(context, 'Имя аккаунта', 'Account name'),
      hint: tr(context, 'Например, имя друга', 'For example, a friend’s name'),
      action: tr(context, 'Сохранить', 'Save'),
      initial: replace?.label,
      maxLength: 60,
    );
    if (!mounted || label == null) return;
    if (_accounts.any(
      (item) => item.id != replace?.id && item.cookie == cookie,
    )) {
      _message(tr(context, 'Этот аккаунт уже добавлен.', 'This account is already added.'));
      return;
    }
    final id = replace?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final next = [
      ..._accounts.where((item) => item.id != id),
      SavedAccount(id: id, label: label, cookie: cookie),
    ];
    try {
      await _store.save(next);
      if (mounted) {
        setState(() {
          _accounts = next;
          _selected.add(id);
          _results.remove(id);
          _errors.remove(id);
        });
      }
    } catch (_) {
      if (mounted) _message(tr(context, 'Не удалось сохранить аккаунт.', 'Could not save the account.'));
    }
  }

  Future<void> _remove(SavedAccount account) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'Удалить ${account.label}?', 'Delete ${account.label}?')),
        content: Text(tr(context, 'Сохранённая сессия будет удалена с устройства.', 'The saved session will be removed from this device.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Отмена', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Удалить', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final next = _accounts.where((item) => item.id != account.id).toList();
    try {
      await _store.save(next);
      if (mounted) {
        setState(() {
          _accounts = next;
          _selected.remove(account.id);
          _results.remove(account.id);
          _errors.remove(account.id);
        });
      }
    } catch (_) {
      if (mounted) _message(tr(context, 'Не удалось удалить аккаунт.', 'Could not delete the account.'));
    }
  }

  Future<void> _scan() async {
    if (_busy) return;
    if (_selected.isEmpty) {
      _message(tr(context, 'Сначала выберите аккаунты.', 'Select accounts first.'));
      return;
    }
    if (widget.scanQr == null && !Platform.isAndroid && !Platform.isIOS) {
      _message(tr(context, 'Камера доступна на Android и iOS. Для проверки вставьте ссылку.', 'The camera is available on Android and iOS. Paste a link to test here.'));
      return;
    }
    setState(() => _scanning = true);
    String? raw;
    try {
      raw = widget.scanQr == null
          ? await Navigator.of(context).push<String>(
              MaterialPageRoute(builder: (_) => const QrScanPage()),
            )
          : await widget.scanQr!(context);
    } catch (_) {
      if (mounted) _message(tr(context, 'Не удалось открыть камеру.', 'Could not open the camera.'));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
    if (mounted && raw != null) await _submitLink(raw);
  }

  Future<void> _scanQueue() async {
    if (_busy) return;
    final accounts = _accounts
        .where((account) => _selected.contains(account.id))
        .toList();
    if (accounts.isEmpty) {
      _message(tr(context, 'Сначала выберите аккаунты.', 'Select accounts first.'));
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      _message(tr(context, 'Камера доступна на Android и iOS.', 'The camera is available on Android and iOS.'));
      return;
    }
    setState(() {
      _scanning = true;
      _results.clear();
      _errors.clear();
    });
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => QueueScanPage(
            accounts: accounts,
            api: _api,
            onUpdate: (queue) {
              if (!mounted) return;
              setState(() {
                _results
                  ..clear()
                  ..addAll(queue.results);
                _errors
                  ..clear()
                  ..addAll(queue.errors);
              });
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted) _message(tr(context, 'Не удалось открыть камеру.', 'Could not open the camera.'));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _shareSessions() async {
    if (_busy) return;
    final accounts = _accounts.where((a) => _selected.contains(a.id)).toList();
    if (accounts.isEmpty) {
      _message(tr(context, 'Сначала выберите аккаунты.', 'Select accounts first.'));
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => SessionSharePage(accounts: accounts)),
    );
  }

  Future<void> _importSessions() async {
    if (_busy) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      _message(tr(context, 'Импорт через камеру доступен на Android и iOS.', 'Camera import is available on Android and iOS.'));
      return;
    }
    final imported = await Navigator.of(context).push<List<SavedAccount>>(
      MaterialPageRoute(builder: (_) => const SessionImportPage()),
    );
    if (!mounted || imported == null) return;
    final known = _accounts.map((a) => a.cookie).toSet();
    final added = <SavedAccount>[];
    final base = DateTime.now().microsecondsSinceEpoch;
    for (final account in imported) {
      if (!known.add(account.cookie)) continue;
      added.add(SavedAccount(
        id: '${base}_${added.length}',
        label: account.label,
        cookie: account.cookie,
      ));
    }
    if (added.isEmpty) {
      _message(tr(context, 'Все эти аккаунты уже сохранены.', 'All these accounts are already saved.'));
      return;
    }
    final next = [..._accounts, ...added];
    try {
      await _store.save(next);
      if (!mounted) return;
      setState(() {
        _accounts = next;
        _selected.addAll(added.map((a) => a.id));
      });
      _message(tr(context, 'Импортировано: ${added.length}', 'Imported: ${added.length}'));
    } catch (_) {
      if (mounted) _message(tr(context, 'Не удалось сохранить аккаунты.', 'Could not save accounts.'));
    }
  }

  Future<void> _pasteLink() async {
    if (_busy) return;
    if (_selected.isEmpty) {
      _message(tr(context, 'Сначала выберите аккаунты.', 'Select accounts first.'));
      return;
    }
    final raw = await _askText(
      title: tr(context, 'Ссылка QR-кода', 'QR code link'),
      hint: 'https://pulse.mirea.ru/...?token=...',
      action: tr(context, 'Отправить', 'Submit'),
    );
    if (mounted && raw != null) await _submitLink(raw);
  }

  Future<void> _submitLink(String raw) async {
    if (_submitting) return;
    final String token;
    try {
      token = attendanceTokenFromQr(raw);
    } on FormatException catch (error) {
      _message(error.message);
      return;
    }
    final accounts = _accounts
        .where((account) => _selected.contains(account.id))
        .toList();
    if (accounts.isEmpty) {
      _message(tr(context, 'Сначала выберите аккаунты.', 'Select accounts first.'));
      return;
    }
    setState(() {
      _submitting = true;
      _results.clear();
      _errors.clear();
    });
    // Every request starts immediately: the lecture QR token can rotate quickly.
    await Future.wait(
      accounts.map((account) async {
        try {
          final result = await _api.approve(token, account.cookie);
          if (mounted) setState(() => _results[account.id] = result);
        } catch (error) {
          if (mounted) {
            setState(
              () => _errors[account.id] = error is PulseApiException
                  ? error.message
                  : 'Ошибка сети. Попробуйте снова.',
            );
          }
        }
      }),
    );
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Пульс', style: TextStyle(fontWeight: FontWeight.w700)),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 20),
          child: Center(
            child: Text(
              '${_selected.length} выбрано',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Не удалось открыть сохранённые аккаунты.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                children: [
                  const Text(
                    'Посещаемость',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Сканируйте QR — отметки отправятся сразу.',
                    style: TextStyle(color: AppColors.muted, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _scan,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('Сканировать QR'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _scanQueue,
                      icon: const Icon(Icons.repeat_rounded, size: 20),
                      label: const Text('Режим очереди'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _pasteLink,
                      icon: const Icon(Icons.link_rounded, size: 20),
                      label: const Text('Вставить ссылку'),
                    ),
                  ),
                  if (_submitting) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    const Text(
                      'Отправляем отметки…',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: _busy ? null : _shareSessions,
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          label: Text(tr(context, 'Передать сессии', 'Share sessions')),
                        ),
                      ),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: _busy ? null : _importSessions,
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: Text(tr(context, 'Импорт сессий', 'Import sessions')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Аккаунты',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : () => _login(),
                        icon: const Icon(Icons.add_rounded, size: 19),
                        label: const Text('Добавить'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_accounts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Text(
                        'Добавьте первый аккаунт через МИРЭА.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                  for (final account in _accounts)
                    _AccountRow(
                      account: account,
                      selected: _selected.contains(account.id),
                      busy: _submitting,
                      result: _results[account.id],
                      error: _errors[account.id],
                      onTap: () => setState(() {
                        if (!_selected.add(account.id)) {
                          _selected.remove(account.id);
                        }
                      }),
                      onReauth: () => _login(replace: account),
                      onRemove: () => _remove(account),
                    ),
                ],
              ),
      ),
    ),
  );
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.selected,
    required this.busy,
    required this.result,
    required this.error,
    required this.onTap,
    required this.onReauth,
    required this.onRemove,
  });

  final SavedAccount account;
  final bool selected;
  final bool busy;
  final ApprovalResult? result;
  final String? error;
  final VoidCallback onTap;
  final VoidCallback onReauth;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final status =
        error ??
        result?.message ??
        (busy && selected ? 'Отправка…' : 'Сессия сохранена');
    final color = error != null || result?.state == ApprovalState.rejected
        ? Theme.of(context).colorScheme.error
        : result?.state == ApprovalState.approved
        ? const Color(0xFF238664)
        : AppColors.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 9, 4, 9),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? AppColors.blue : AppColors.muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: color),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  enabled: !busy,
                  tooltip: 'Действия с аккаунтом',
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: AppColors.muted,
                  ),
                  onSelected: (value) {
                    if (value == 'login') onReauth();
                    if (value == 'remove') onRemove();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'login', child: Text('Войти снова')),
                    PopupMenuItem(value: 'remove', child: Text('Удалить')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.hint,
    required this.action,
    this.initial,
    this.maxLength,
  });
  final String title;
  final String hint;
  final String action;
  final String? initial;
  final int? maxLength;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: widget.maxLength,
      decoration: InputDecoration(hintText: widget.hint),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () {
          final value = _controller.text.trim();
          if (value.isNotEmpty) Navigator.pop(context, value);
        },
        child: Text(widget.action),
      ),
    ],
  );
}
