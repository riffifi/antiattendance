import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'accounts.dart';
import 'app_theme.dart';
import 'campus_design.dart';
import 'expressive.dart';
import 'l10n.dart';
import 'login_qr.dart';
import 'pulse_api.dart';
import 'pulse_session.dart';
import 'session_expiry.dart';

const _channel = MethodChannel('antiattendance/batch_login');

/// A named cookie/local-storage partition in the vendored Android WebView.
class BatchLoginSettings extends InAppWebViewSettings {
  BatchLoginSettings(this.profile) : super(supportZoom: true);
  final String profile;
  @override
  Map<String, dynamic> toMap() => {...super.toMap(), 'sessionProfile': profile};
}

// The university theme normally submits as soon as approval arrives. Batch
// mode deliberately waits for a real Continue tap in this browser instead.
const _holdApprovalScript = r'''
(() => {
  if (location.origin !== 'https://sso.mirea.ru') return;
  if (window.__aaBatchFetch) return;
  const original = window.fetch.bind(window);
  window.__aaBatchFetch = original;
  window.fetch = async (...args) => {
    const response = await original(...args);
    const url = new URL(typeof args[0] === 'string' ? args[0] : args[0].url, location.href);
    if (url.origin !== location.origin || url.pathname !== '/realms/mirea/qr-code-auth/check-status') return response;
    try {
      const data = await response.clone().json();
      if (data.authenticated === true) window.__aaBatchApproved = true;
      data.authenticated = false;
      return new Response(JSON.stringify(data), {status: response.status, headers: response.headers});
    } catch (_) { return response; }
  };
})();
''';

const _batchPollScript = r'''
(() => {
  if (location.origin !== 'https://sso.mirea.ru') return null;
  const c = typeof kcContext !== 'undefined' ? kcContext : window.kcContext;
  if (!c) return null;
  const session = c.sessionId || c.auth?.sessionId || c.login?.sessionId;
  const tab = c.tabId || new URLSearchParams(location.search).get('tab_id');
  const state = window.__aaBatchPollState || (window.__aaBatchPollState = {pending:false});
  if (session && tab && !window.__aaBatchApproved && !state.pending) {
    const url = new URL('/realms/mirea/qr-code-auth/check-status', location.origin);
    url.searchParams.set('sessionId', session); url.searchParams.set('tabId', tab);
    state.pending = true;
    (window.__aaBatchFetch || window.fetch)(url.href, {credentials:'same-origin',cache:'no-store',signal:AbortSignal.timeout(10000)})
      .then(response => response.ok ? response.json() : null)
      .then(data => {
        if (!data) return;
        state.status = data.status;
        if (data.authenticated === true) window.__aaBatchApproved = true;
      })
      .catch(() => {})
      .finally(() => {state.pending = false;});
  }
  if (window.__aaBatchApproved && c.url?.loginAction && c.QRauthExecId && !document.getElementById('aa-batch-continue')) {
    const action = new URL(c.url.loginAction, location.origin);
    if (action.origin === location.origin && action.pathname === '/realms/mirea/login-actions/authenticate') {
      const form = document.createElement('form'); form.method = 'post'; form.action = action.href;
      const input = document.createElement('input'); input.type = 'hidden'; input.name = 'authenticationExecution'; input.value = c.QRauthExecId;
      const button = document.createElement('button'); button.id = 'aa-batch-continue'; button.type = 'submit';
      button.textContent = document.documentElement.lang.startsWith('ru') ? 'Продолжить' : 'Continue';
      button.style.cssText = 'display:block;width:100%;padding:20px;background:#167847;color:white;border:0;border-radius:16px;font:bold 20px system-ui;margin:20px 0;';
      form.append(input, button); document.body.prepend(form);
    }
  }
  return JSON.stringify({qr:c.QRauthToken,approved:window.__aaBatchApproved===true,status:state.status,error:c.pageId==='error.ftl'||c.message?.type==='error'});
})()
''';

class BatchLoginEntry {
  BatchLoginEntry(this.profile, this.name);
  final String profile;
  final TextEditingController name;
  InAppWebViewController? browser;
  String? qr;
  String? error;
  bool approved = false;
  bool polling = false;
  bool saving = false;
  bool saved = false;
  bool showBrowser = false;
  int generation = 0;
}

class BatchLoginPage extends StatefulWidget {
  const BatchLoginPage({super.key, required this.count, required this.onSave});
  final int count;
  final Future<void> Function(SavedAccount account) onSave;

  static Future<bool> supported() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('supported') == true;
    } catch (_) {
      return false;
    }
  }

  @override
  State<BatchLoginPage> createState() => _BatchLoginPageState();
}

class _BatchLoginPageState extends State<BatchLoginPage> {
  late final List<BatchLoginEntry> _entries;
  Timer? _timer;
  int? _active;
  Future<void> _saveQueue = Future.value();

  @override
  void initState() {
    super.initState();
    final batch = DateTime.now().microsecondsSinceEpoch;
    _entries = List.generate(
      widget.count.clamp(1, 10),
      (i) => BatchLoginEntry('aa_batch_${batch}_$i', TextEditingController()),
    );
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      for (final entry in _entries) {
        unawaited(_poll(entry));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final entry in _entries) {
      entry.generation++;
      entry.name.dispose();
      unawaited(_cleanProfile(entry.profile));
    }
    super.dispose();
  }

  Future<void> _cleanProfile(String profile) async {
    // Platform views finish destruction after this route's dispose callback.
    for (var attempt = 0; attempt < 5; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        await _channel.invokeMethod('dispose', {'profile': profile});
        return;
      } catch (_) {}
    }
  }

  Future<void> _poll(BatchLoginEntry entry) async {
    if (!mounted ||
        entry.browser == null ||
        entry.polling ||
        entry.saved ||
        entry.saving ||
        entry.error != null) {
      return;
    }
    entry.polling = true;
    final generation = entry.generation;
    try {
      final url = await entry.browser!.getUrl();
      if (!mounted || generation != entry.generation) return;
      if (url?.host == 'sso.mirea.ru') {
        final raw = await entry.browser!.evaluateJavascript(
          source: _batchPollScript,
        );
        if (!mounted || generation != entry.generation) return;
        final result = raw is String ? jsonDecode(raw) : null;
        if (result is Map) {
          setState(() {
            entry.approved = result['approved'] == true;
            entry.qr = entry.approved ? null : mireaLoginQr(result['qr']);
            if (result['error'] == true ||
                [
                  'timeout',
                  'rejected',
                  'session_not_found',
                ].contains(result['status'])) {
              entry.qr = null;
              entry.approved = false;
              entry.error = tr(
                context,
                'Код истёк или вход отклонён. Обновите вход.',
                'QR expired or sign-in was rejected. Refresh this login.',
              );
            }
          });
        }
      } else if (url?.host == pulseHost) {
        final cookie = await _channel.invokeMethod<String>('cookies', {
          'profile': entry.profile,
        });
        if (cookie == null ||
            await probePulseSession(cookie) != PulseSessionState.valid) {
          return;
        }
        if (!mounted || generation != entry.generation) return;
        setState(() {
          entry.approved = true;
          entry.saving = true;
          entry.qr = null;
        });
        var metadata = <String, int?>{};
        try {
          final infos = await _channel.invokeListMethod<String>('cookieInfo', {
            'profile': entry.profile,
          });
          metadata = expiryMetadataFromCookieInfo(infos ?? []);
        } catch (_) {
          /* Older WebViews still support embedded session expiry. */
        }
        if (!mounted || generation != entry.generation) return;
        final expiry = sessionCookieExpiry(cookie, cookieExpiries: metadata);
        final label = entry.name.text.trim();
        final account = SavedAccount(
          id: entry.profile,
          label: label.isEmpty
              ? tr(
                  context,
                  'Пользователь ${_entries.indexOf(entry) + 1}',
                  'User ${_entries.indexOf(entry) + 1}',
                )
              : label,
          cookie: cookie,
          expiresAt: expiry != null && expiry.isAfter(DateTime.now())
              ? expiry
              : null,
        );
        // Two callbacks must never save over one another's account list.
        final saving = _saveQueue.then((_) => widget.onSave(account));
        _saveQueue = saving.catchError((Object _) {});
        try {
          await saving;
          if (mounted) {
            setState(() {
              entry.saved = true;
              entry.saving = false;
            });
          }
        } catch (_) {
          if (mounted) {
            setState(() {
              entry.saving = false;
              entry.error = tr(
                context,
                'Не удалось сохранить аккаунт: он уже добавлен или хранилище недоступно.',
                'Could not save: this account already exists or storage is unavailable.',
              );
            });
          }
        }
      }
    } catch (_) {
      // A callback may destroy the current JS context; retry after navigation.
    } finally {
      entry.polling = false;
    }
  }

  Future<void> _refresh(BatchLoginEntry entry) async {
    entry.generation++;
    setState(() {
      entry.error = null;
      entry.qr = null;
      entry.approved = false;
      entry.showBrowser = false;
    });
    try {
      await _channel.invokeMethod('clear', {'profile': entry.profile});
      await entry.browser?.loadUrl(
        urlRequest: URLRequest(url: WebUri(pulseLoginUrl)),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => entry.error = tr(
            context,
            'Не удалось обновить вход.',
            'Could not refresh sign-in.',
          ),
        );
      }
    }
  }

  String _status(BatchLoginEntry entry) =>
      entry.error ??
      (entry.saved
          ? tr(context, 'Аккаунт сохранён', 'Account saved')
          : entry.saving
          ? tr(context, 'Сохранение…', 'Saving…')
          : entry.approved
          ? tr(
              context,
              'Подтверждено · откройте и нажмите «Продолжить»',
              'Approved · open and tap Continue',
            )
          : entry.qr != null
          ? tr(context, 'Ожидаем сканирование', 'Waiting for scan')
          : tr(context, 'Подготовка QR-кода…', 'Preparing QR…'));

  Future<void> _leave() async {
    if (_active != null) {
      setState(() => _active = null);
      return;
    }
    if (_entries.any((e) => !e.saved)) {
      final close = await showExpressiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            tr(context, 'Закончить добавление?', 'Finish adding accounts?'),
          ),
          content: Text(
            tr(
              context,
              'Сохранённые аккаунты останутся. Незавершённые входы будут закрыты.',
              'Saved accounts will remain. Unfinished sign-ins will be closed.',
            ),
          ),
          actions: [
            CampusButton.text(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr(context, 'Остаться', 'Stay')),
            ),
            CampusButton.text(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr(context, 'Закончить', 'Finish')),
            ),
          ],
        ),
      );
      if (!mounted || close != true) return;
    }
    if (mounted) Navigator.pop(context);
  }

  Widget _card(BatchLoginEntry entry, int index) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.palette.surface,
      borderRadius: BorderRadius.zero,
      border: Border.all(
        color: entry.approved ? context.palette.success : context.palette.line,
      ),
    ),
    child: Column(
      children: [
        CampusTextField(
          controller: entry.name,
          enabled: !entry.saved && !entry.saving,
          label: tr(context, 'Имя ${index + 1}', 'Name ${index + 1}'),
          maxLength: 60,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.zero,
            onTap: () => _open(index),
            child: SizedBox.expand(
              child: Center(
                child: entry.approved
                    ? Text(
                        tr(context, 'Готово', 'Done'),
                        style: Theme.of(context).textTheme.headlineLarge,
                      )
                    : entry.qr != null
                    ? Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(8),
                        child: QrImageView(
                          data: entry.qr!,
                          size: 160,
                          backgroundColor: Colors.white,
                        ),
                      )
                    : entry.error != null
                    ? Text(tr(context, 'Повторить', 'Retry'))
                    : const CircularProgressIndicator(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(_status(entry), textAlign: TextAlign.center, maxLines: 3),
        if (entry.error != null)
          CampusButton.text(
            onPressed: () => _refresh(entry),
            child: Text(tr(context, 'Повторить', 'Retry')),
          ),
      ],
    ),
  );

  void _open(int index) {
    FocusScope.of(context).unfocus();
    setState(() => _active = index);
    if (_entries[index].approved) {
      unawaited(
        _entries[index].browser
            ?.evaluateJavascript(
              source: "document.getElementById('aa-batch-continue')?.scrollIntoView({block:'center'})",
            )
            .catchError((Object _) => null),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _active == null ? null : _entries[_active!];
    final saved = _entries.where((e) => e.saved).length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: CampusAppBar(
          leading: CampusTextAction(
            onPressed: _leave,
            label: tr(context, 'Назад', 'Back'),
          ),
          title: Text(
            active == null
                ? tr(context, 'Добавление группы', 'Add a group')
                : active.name.text.trim().isEmpty
                ? tr(
                    context,
                    'Пользователь ${_active! + 1}',
                    'User ${_active! + 1}',
                  )
                : active.name.text,
          ),
          actions: [
            if (active != null)
              CampusButton.text(
                onPressed: () => setState(() => _active = null),
                child: Text(tr(context, 'Обзор', 'Overview')),
              )
            else
              CampusButton.text(
                onPressed: _leave,
                child: Text(tr(context, 'Готово', 'Done')),
              ),
          ],
        ),
        body: Stack(
          children: [
            for (var i = 0; i < _entries.length; i++)
              Positioned.fill(
                child: Offstage(
                  offstage: _active != i,
                  child: InAppWebView(
                    key: ValueKey(_entries[i].profile),
                    initialUrlRequest: URLRequest(url: WebUri(pulseLoginUrl)),
                    initialSettings: BatchLoginSettings(_entries[i].profile),
                    initialUserScripts: UnmodifiableListView([
                      UserScript(
                        source: _holdApprovalScript,
                        injectionTime:
                            UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                    ]),
                    onWebViewCreated: (controller) {
                      _entries[i].browser = controller;
                    },
                    onLoadStop: (controller, url) =>
                        unawaited(_poll(_entries[i])),
                    onReceivedError: (controller, request, error) {
                      if (request.isForMainFrame == true && mounted) {
                        setState(
                          () => _entries[i].error = tr(
                            context,
                            'Страница входа недоступна. Повторите попытку.',
                            'Sign-in page unavailable. Retry.',
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
            if (active == null)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          tr(
                            context,
                            'Сохранено $saved из ${_entries.length}. Назовите карточки, отсканируйте коды, затем откройте зелёные карточки и нажмите «Продолжить».',
                            'Saved $saved of ${_entries.length}. Name the cards, scan the codes, then open green cards and tap Continue.',
                          ),
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => GridView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                            itemCount: _entries.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount:
                                      ((constraints.maxWidth - 28) / 232)
                                          .floor()
                                          .clamp(1, 3),
                                  mainAxisExtent:
                                      360 +
                                      100 *
                                          (MediaQuery.textScalerOf(context)
                                                          .scale(14) /
                                                      14 -
                                                  1)
                                              .clamp(0, 2),
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                            itemBuilder: (context, i) => _card(_entries[i], i),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (active != null &&
                !active.showBrowser &&
                !active.approved &&
                active.error == null &&
                !active.saved)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tr(context, 'Вход по QR-коду', 'Sign in with QR'),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 24),
                          if (active.qr != null)
                            Container(
                              padding: const EdgeInsets.all(16),
                              color: Colors.white,
                              child: QrImageView(
                                data: active.qr!,
                                size: 280,
                                backgroundColor: Colors.white,
                              ),
                            )
                          else ...[
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(
                              tr(
                                context,
                                'Подготовка QR-кода…',
                                'Preparing QR…',
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          Text(
                            tr(
                              context,
                              'Подтвердите вход на телефоне владельца. Затем нажмите «Продолжить» на странице МИРЭА.',
                              'Approve on the owner’s phone. Then tap Continue on the MIREA page.',
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          CampusButton.text(
                            onPressed: () =>
                                setState(() => active.showBrowser = true),
                            child: Text(
                              tr(
                                context,
                                'Открыть страницу входа',
                                'Open sign-in page',
                              ),
                            ),
                          ),
                          CampusButton.text(
                            onPressed: () => _refresh(active),
                            child: Text(
                              tr(context, 'Обновить QR-код', 'Refresh QR code'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (active != null && (active.error != null || active.saved))
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Material(
                  color: context.palette.surface,
                  borderRadius: BorderRadius.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_status(active)),
                        CampusButton.text(
                          onPressed: active.saved
                              ? () => setState(() => _active = null)
                              : () => _refresh(active),
                          child: Text(
                            active.saved
                                ? tr(context, 'К обзору', 'Back to overview')
                                : tr(context, 'Повторить', 'Retry'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
