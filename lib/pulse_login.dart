import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'l10n.dart';
import 'accounts.dart';
import 'app_theme.dart';
import 'pulse_api.dart';
import 'pulse_session.dart';
import 'session_expiry.dart';
import 'login_qr.dart';
import 'campus_design.dart';
import 'expressive.dart';

import 'package:qr_flutter/qr_flutter.dart';

class PulseLoginPage extends StatefulWidget {
  const PulseLoginPage({super.key, this.accountLabel});
  final String? accountLabel;

  @override
  State<PulseLoginPage> createState() => _PulseLoginPageState();
}

class _PulseLoginPageState extends State<PulseLoginPage> {
  bool _ready = false;
  bool _finished = false;
  bool _zooming = false;
  bool _pageReady = false;
  double _zoom = 1.0;
  InAppWebViewController? _webView;
  String? _error;
  String? _qrLink;
  bool _showBrowser = false;
  bool _readingLogin = false;
  Timer? _loginTimer;
  int _loginEpoch = 0;
  bool _checkingSession = false;
  String? _sessionMessage;
  List<String> _cookieNames = [];
  PulseSessionState? _sessionState;
  String? _lastCandidate;
  DateTime? _lastCandidateCheck;

  @override
  void initState() {
    super.initState();
    _prepare();
    _loginTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_readLogin()),
    );
  }

  @override
  void dispose() {
    _loginTimer?.cancel();
    super.dispose();
  }

  Future<void> _readLogin() async {
    final controller = _webView;
    if (controller == null || _readingLogin || _finished) return;
    _readingLogin = true;
    final epoch = _loginEpoch;
    try {
      // Cookies can arrive during a redirect before the WebView reports its URL.
      await _checkSession();
      if (!mounted || _finished || !_pageReady) return;
      final url = await controller.getUrl();
      if (url?.host == pulseHost) {
        if (mounted && _qrLink != null) {
          setState(() {
            _qrLink = null;
            _showBrowser = true;
          });
        }
        await _checkSession();
        return;
      }
      if (url?.scheme != 'https' || url?.host != 'sso.mirea.ru') return;
      final raw = await controller.evaluateJavascript(
        source: mireaLoginQrScript,
      );
      final data = raw is String ? jsonDecode(raw) : null;
      final qr = data is Map ? mireaLoginQr(data['qr']) : null;
      if (mounted && epoch == _loginEpoch && qr != _qrLink) {
        setState(() => _qrLink = qr);
      }
    } catch (_) {
      // Redirects can destroy the JS context. Keep the original page available.
    } finally {
      _readingLogin = false;
    }
  }

  Future<void> _refreshLogin() async {
    setState(() {
      _loginEpoch++;
      _qrLink = null;
      _pageReady = false;
    });
    try {
      await _webView?.loadUrl(
        urlRequest: URLRequest(url: WebUri(pulseLoginUrl)),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Не удалось открыть страницу входа.');
      }
    }
  }

  Widget _loginQr() => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.accountLabel ??
                    tr(context, 'Вход по QR-коду', 'Sign in with QR'),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                tr(
                  context,
                  'Отсканируйте код другим устройством и подтвердите вход в МИРЭА. Приложение дождётся подтверждения.',
                  'Scan with another device and confirm your MIREA sign-in. This app will wait for confirmation.',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Semantics(
                label: tr(
                  context,
                  'QR-код для входа в МИРЭА',
                  'MIREA sign-in QR code',
                ),
                image: true,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: QrImageView(
                    data: _qrLink!,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const CampusProgress.linear(),
              const SizedBox(height: 12),
              CampusButton.text(
                onPressed: _refreshLogin,
                child: Text(tr(context, 'Обновить QR-код', 'Refresh QR code')),
              ),
              CampusButton.text(
                onPressed: () => setState(() => _showBrowser = true),
                child: Text(
                  tr(context, 'Другой способ входа', 'Other sign-in options'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _prepare() async {
    try {
      // This app uses one browser cookie jar. Saved account sessions live in
      // secure storage, so clearing the jar prevents the next login from
      // silently selecting the previous account.
      await CookieManager.instance().deleteAllCookies();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось подготовить вход.');
    }
  }

  Future<void> _checkSession({bool force = false}) async {
    if (_finished || !mounted || _checkingSession || !_ready) return;
    _checkingSession = true;
    final epoch = _loginEpoch;
    try {
      // Cookie paths matter: an authenticated RPC cookie need not be visible at
      // '/'. The profile endpoint is also what Pulse uses to identify its user.
      final manager = CookieManager.instance();
      final cookies = [
        ...await manager.getCookies(url: WebUri('https://$pulseHost/')),
        ...await manager.getCookies(url: WebUri(pulseProfileUrl)),
      ];
      final values = <String, String>{};
      for (final cookie in cookies) {
        if (cookie.value is String) {
          values[cookie.name] = cookie.value as String;
        }
      }
      final session = pulseSessionCookie(values);
      if (!mounted || _finished || epoch != _loginEpoch) return;
      final names =
          session
              .split('; ')
              .map((part) => part.substring(0, part.indexOf('=')))
              .toList()
            ..sort();
      if (!force &&
          session == _lastCandidate &&
          _lastCandidateCheck != null &&
          DateTime.now().difference(_lastCandidateCheck!) <
              const Duration(seconds: 8)) {
        return;
      }
      _lastCandidate = session;
      _lastCandidateCheck = DateTime.now();
      final state = await probePulseSession(session);
      if (!mounted || _finished || epoch != _loginEpoch) return;
      _sessionState = state;
      _cookieNames = names;
      if (state != PulseSessionState.valid) {
        final url = await _webView?.getUrl();
        if (mounted && url?.host == pulseHost) {
          setState(() {
            _qrLink = null;
            _showBrowser = true;
            _sessionMessage = tr(
              context,
              'Пульс открыт, но сессия пока не подтверждена. Повторите проверку; данные аккаунта не заменены.',
              'Pulse is open, but the session is not confirmed yet. Retry the check; the saved account has not been replaced.',
            );
          });
        }
        return;
      }
      final expiry = sessionCookieExpiry(
        session,
        cookieExpiries: {
          for (final cookie in cookies)
            if (cookie.value == values[cookie.name])
              cookie.name: cookie.expiresDate,
        },
      );
      _finished = true;
      Navigator.of(context).pop(
        SavedAccount(
          id: '',
          label: '',
          cookie: session,
          expiresAt: expiry != null && expiry.isAfter(DateTime.now())
              ? expiry
              : null,
        ),
      );
    } on FormatException {
      // Incomplete cookies during SSO redirects are retried after navigation.
      final url = await _webView?.getUrl();
      if (mounted &&
          epoch == _loginEpoch &&
          url?.host == pulseHost &&
          _pageReady) {
        setState(() {
          _qrLink = null;
          _showBrowser = true;
          _cookieNames = [];
          _sessionMessage = tr(
            context,
            'Ожидаем сессионные cookies Пульса. Если вход уже выполнен, повторите проверку.',
            'Waiting for Pulse session cookies. If you have signed in, retry the check.',
          );
        });
      }
    } catch (_) {
      // A redirect may destroy the current WebView cookie context.
    } finally {
      _checkingSession = false;
    }
  }

  Future<void> _showSessionDetails() => showExpressiveSheet<void>(
    context: context,
    compact: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'Проверка входа', 'Sign-in check'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text('GetMeInfo: ${_sessionState?.name ?? 'waiting'}'),
          const SizedBox(height: 8),
          SelectableText(
            'Cookie names: ${_cookieNames.isEmpty ? 'none' : _cookieNames.join(', ')}',
          ),
          const SizedBox(height: 12),
          Text(
            tr(
              context,
              'Показаны только названия cookies. Значения сессии скрыты.',
              'Only cookie names are shown. Session values are hidden.',
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _applyZoom(
    InAppWebViewController controller,
    double scale,
  ) async {
    final value = scale.toStringAsFixed(2);
    await controller.evaluateJavascript(
      source:
          '''
      (function () {
        var body = document.body;
        if (!body) return;
        if (window.CSS && CSS.supports && CSS.supports('zoom', '$value')) {
          body.style.setProperty('zoom', '$value', 'important');
          body.style.removeProperty('transform');
          body.style.removeProperty('transform-origin');
          body.style.removeProperty('width');
        } else {
          body.style.removeProperty('zoom');
          body.style.setProperty('transform-origin', 'top left', 'important');
          body.style.setProperty('transform', 'scale($value)', 'important');
          body.style.setProperty('width', '${(100 / scale).toStringAsFixed(2)}%', 'important');
        }
      })();
    ''',
    );
  }

  Future<void> _changeZoom(double next) async {
    final controller = _webView;
    if (controller == null || _zooming || !_pageReady) return;
    final target = next.clamp(0.5, 2.0);
    if (target == _zoom) return;
    setState(() => _zooming = true);
    try {
      await _applyZoom(controller, target);
      if (mounted) setState(() => _zoom = target);
    } catch (_) {
      if (mounted) {
        CampusNotice.show(
          context,
          message: tr(
            context,
            'Масштаб недоступен на этом устройстве.',
            'Zoom is unavailable on this device.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _zooming = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: CampusAppBar(
      title: Text(
        widget.accountLabel ??
            tr(context, 'Войти через МИРЭА', 'Sign in through MIREA'),
      ),
      automaticallyImplyLeading: true,
    ),
    body: SafeArea(
      top: false,
      child: _error != null
          ? Center(child: Text(trMessage(context, _error!)))
          : !_ready
          ? const Center(child: CampusProgress.compact())
          : Column(
              children: [
                if (_sessionMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _sessionMessage!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            CampusButton.text(
                              onPressed: () => _checkSession(force: true),
                              child: Text(
                                tr(
                                  context,
                                  'Проверить сессию',
                                  'Check session',
                                ),
                              ),
                            ),
                            CampusButton.text(
                              onPressed: _showSessionDetails,
                              child: Text(
                                tr(context, 'Проверка входа', 'Sign-in check'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: InAppWebView(
                          initialUrlRequest: URLRequest(
                            url: WebUri(pulseLoginUrl),
                          ),
                          initialSettings: InAppWebViewSettings(
                            supportZoom: true,
                            builtInZoomControls: true,
                            displayZoomControls: false,
                          ),
                          onWebViewCreated: (controller) {
                            if (mounted) setState(() => _webView = controller);
                          },
                          onLoadStart: (controller, url) {
                            _loginEpoch++;
                            if (mounted) setState(() => _pageReady = false);
                            if (mounted) setState(() => _qrLink = null);
                            unawaited(_checkSession());
                          },
                          onLoadStop: (controller, url) {
                            if (mounted) setState(() => _pageReady = true);
                            unawaited(
                              _applyZoom(
                                controller,
                                _zoom,
                              ).catchError((Object _) {}),
                            );
                            unawaited(_checkSession());
                            unawaited(_readLogin());
                          },
                          onUpdateVisitedHistory: (controller, url, isReload) {
                            unawaited(_checkSession());
                          },
                          onReceivedError: (controller, request, error) {
                            if (request.isForMainFrame == true && mounted) {
                              setState(
                                () => _error =
                                    'Не удалось открыть страницу входа.',
                              );
                            }
                          },
                        ),
                      ),
                      if (_qrLink != null && !_showBrowser)
                        Positioned.fill(child: _loginQr()),
                    ],
                  ),
                ),
                if (_qrLink == null || _showBrowser)
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: context.palette.surface,
                        border: Border(
                          top: BorderSide(color: context.palette.line),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr(context, 'Масштаб страницы', 'Page zoom'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          CampusTextAction(
                            onPressed:
                                _zooming ||
                                    !_pageReady ||
                                    _webView == null ||
                                    _zoom <= 0.5
                                ? null
                                : () => _changeZoom(_zoom - 0.15),
                            tooltip: tr(context, 'Уменьшить', 'Zoom out'),
                            label: tr(context, 'Уменьшить', 'Zoom out'),
                          ),
                          SizedBox(
                            width: 52,
                            child: Text(
                              '${(_zoom * 100).round()}%',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          CampusTextAction(
                            onPressed:
                                _zooming ||
                                    !_pageReady ||
                                    _webView == null ||
                                    _zoom >= 2.0
                                ? null
                                : () => _changeZoom(_zoom + 0.15),
                            tooltip: tr(context, 'Увеличить', 'Zoom in'),
                            label: tr(context, 'Увеличить', 'Zoom in'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    ),
  );
}
