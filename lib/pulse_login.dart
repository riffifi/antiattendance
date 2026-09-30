import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'l10n.dart';
import 'pulse_api.dart';

class PulseLoginPage extends StatefulWidget {
  const PulseLoginPage({super.key});

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

  @override
  void initState() {
    super.initState();
    _prepare();
  }

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

  Future<void> _checkSession(WebUri? url) async {
    if (_finished || url == null || url.host != pulseHost) return;
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
      Navigator.of(context).pop(session);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                'Масштаб недоступен на этом устройстве.',
                'Zoom is unavailable on this device.',
              ),
            ),
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
      title: Text(tr(context, 'Войти через МИРЭА', 'Sign in through MIREA')),
    ),
    body: _error != null
        ? Center(child: Text(trMessage(context, _error!)))
        : !_ready
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Expanded(
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(pulseLoginUrl)),
                  initialSettings: InAppWebViewSettings(
                    supportZoom: true,
                    builtInZoomControls: true,
                    displayZoomControls: false,
                  ),
                  onWebViewCreated: (controller) {
                    if (mounted) setState(() => _webView = controller);
                  },
                  onLoadStart: (controller, url) {
                    if (mounted) setState(() => _pageReady = false);
                    unawaited(_checkSession(url));
                  },
                  onLoadStop: (controller, url) {
                    if (mounted) setState(() => _pageReady = true);
                    unawaited(
                      _applyZoom(controller, _zoom).catchError((Object _) {}),
                    );
                    unawaited(_checkSession(url));
                  },
                  onReceivedError: (controller, request, error) {
                    if (request.isForMainFrame == true && mounted) {
                      setState(
                        () => _error = 'Не удалось открыть страницу входа.',
                      );
                    }
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE3E8EC))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr(context, 'Масштаб страницы', 'Page zoom'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed:
                            _zooming ||
                                !_pageReady ||
                                _webView == null ||
                                _zoom <= 0.5
                            ? null
                            : () => _changeZoom(_zoom - 0.15),
                        icon: const Icon(Icons.remove_rounded),
                        tooltip: tr(context, 'Уменьшить', 'Zoom out'),
                      ),
                      SizedBox(
                        width: 52,
                        child: Text(
                          '${(_zoom * 100).round()}%',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed:
                            _zooming ||
                                !_pageReady ||
                                _webView == null ||
                                _zoom >= 2.0
                            ? null
                            : () => _changeZoom(_zoom + 0.15),
                        icon: const Icon(Icons.add_rounded),
                        tooltip: tr(context, 'Увеличить', 'Zoom in'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
  );
}
