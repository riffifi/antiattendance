import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'pulse_api.dart';

class PulseLoginPage extends StatefulWidget {
  const PulseLoginPage({super.key});

  @override
  State<PulseLoginPage> createState() => _PulseLoginPageState();
}

class _PulseLoginPageState extends State<PulseLoginPage> {
  bool _ready = false;
  bool _finished = false;
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Войти через МИРЭА')),
    body: _error != null
        ? Center(child: Text(_error!))
        : !_ready
        ? const Center(child: CircularProgressIndicator())
        : InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(pulseLoginUrl)),
            onLoadStart: (controller, url) => unawaited(_checkSession(url)),
            onLoadStop: (controller, url) => unawaited(_checkSession(url)),
            onReceivedError: (controller, request, error) {
              if (request.isForMainFrame == true && mounted) {
                setState(() => _error = 'Не удалось открыть страницу входа.');
              }
            },
          ),
  );
}
