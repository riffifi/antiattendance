import 'package:material_3_expressive/material_3_expressive.dart';

import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'l10n.dart';
import 'accounts.dart';
import 'app_theme.dart';
import 'pulse_api.dart';
import 'login_qr.dart';
import 'campus_design.dart';

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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.accountLabel ??
                  tr(context, 'Вход по QR-коду', 'Sign in with QR'),
              style: Theme.of(context).textTheme.headlineSmall,
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
            const M3EProgressIndicator.linearWavy(),
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

  Future<void> _checkSession() async {
    if (_finished || !mounted) return;
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri('https://$pulseHost/'),
      );
      final values = <String, String>{};
      for (final cookie in cookies) {
        final value = cookie.value;
        if (value is String) values[cookie.name] = value;
      }
      final session = pulseSessionCookie(values);
      if (!mounted || _finished) return;
      _finished = true;
      final expiryDates =
          cookies
              .where(
                (cookie) => session
                    .split('; ')
                    .any((part) => part.startsWith('${cookie.name}=')),
              )
              .map((cookie) => cookie.expiresDate)
              .whereType<int>()
              .toList()
            ..sort();
      Navigator.of(context).pop(
        SavedAccount(
          id: '',
          label: '',
          cookie: session,
          expiresAt: expiryDates.isEmpty
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  expiryDates.first,
                  isUtc: true,
                ),
        ),
      );
    } on FormatException {
      // The login redirects through pages before the Pulse cookie is set.
    } catch (_) {
      // Cookie reads can fail while WebView moves between redirect pages.
      // A later page load will check the session again.
    }
  }

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
        M3ESnackbar.show(
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
    appBar: AppBar(
      title: Text(
        widget.accountLabel ??
            tr(context, 'Войти через МИРЭА', 'Sign in through MIREA'),
      ),
      automaticallyImplyLeading: true,
    ),
    body: _error != null
        ? Center(child: Text(trMessage(context, _error!)))
        : !_ready
        ? const Center(child: M3EProgressIndicator.circularWavy())
        : Column(
            children: [
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
                              () =>
                                  _error = 'Не удалось открыть страницу входа.',
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
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        M3EIconButton(
                          suppressInk: true,
                          onPressed:
                              _zooming ||
                                  !_pageReady ||
                                  _webView == null ||
                                  _zoom <= 0.5
                              ? null
                              : () => _changeZoom(_zoom - 0.15),
                          icon: const Icon(Icons.remove_rounded),
                          tooltip: tr(context, 'Уменьшить', 'Zoom out'),
                          variant: M3EIconButtonVariant.filled,
                        ),
                        SizedBox(
                          width: 52,
                          child: Text(
                            '${(_zoom * 100).round()}%',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        M3EIconButton(
                          suppressInk: true,
                          onPressed:
                              _zooming ||
                                  !_pageReady ||
                                  _webView == null ||
                                  _zoom >= 2.0
                              ? null
                              : () => _changeZoom(_zoom + 0.15),
                          icon: const Icon(Icons.add_rounded),
                          tooltip: tr(context, 'Увеличить', 'Zoom in'),
                          variant: M3EIconButtonVariant.filled,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );
}
