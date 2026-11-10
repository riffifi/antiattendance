import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import 'aa_id.dart';
import 'campus_design.dart';
import 'frontend/page_layout.dart';
import 'l10n.dart';

/// The server owns the browser and university credentials. This screen only
/// holds a short-lived login capability and claims AA ID tokens once.
class ServerLoginPage extends StatefulWidget {
  const ServerLoginPage({
    super.key,
    required this.address,
    this.expectedUserId,
  });
  final String address;
  final String? expectedUserId;
  @override
  State<ServerLoginPage> createState() => _ServerLoginPageState();
}

class _ServerLoginPageState extends State<ServerLoginPage>
    with WidgetsBindingObserver {
  late final _api = AaId.client(widget.address);
  Timer? _timer;
  int _generation = 0;
  String? _id, _token, _error;
  String _status = 'waiting';
  Uint8List? _qr;
  bool _polling = false, _claiming = false, _active = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    _timer?.cancel();
    setState(() {
      _error = null;
      _qr = null;
      _status = 'waiting';
      _claiming = false;
    });
    try {
      final job = await _api.startLogin();
      if (!mounted || generation != _generation) return;
      if (job['id'] is! String ||
          job['token'] is! String ||
          (job['id'] as String).isEmpty ||
          (job['token'] as String).isEmpty) {
        throw const FormatException('Invalid login job.');
      }
      _id = job['id'] as String;
      _token = job['token'] as String;
      await _poll();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = tr(
            context,
            'Не удалось начать вход. Повторите попытку.',
            'Could not start sign-in. Try again.',
          ),
        );
      }
    }
  }

  Future<void> _poll() async {
    if (_polling || _claiming || _id == null) return;
    _polling = true;
    final generation = _generation;
    try {
      final state = await _api.loginState(_id!, _token!);
      if (!mounted || generation != _generation) return;
      final status = state['status'] as String? ?? 'waiting';
      final png = state['qr_png'];
      Uint8List? qr;
      if (png is String &&
          png.startsWith('data:image/png;base64,') &&
          png.length < 2 * 1024 * 1024) {
        qr = base64Decode(png.substring('data:image/png;base64,'.length));
      }
      setState(() {
        _status = status;
        _qr = qr ?? _qr;
        _error = null;
      });
      if (status == 'complete') {
        _claiming = true;
        final grant = await _api.claimLogin(_id!, _token!);
        if (!mounted || generation != _generation) return;
        if (widget.expectedUserId != null &&
            grant.userId != widget.expectedUserId) {
          await _api.logout(grant.accessToken);
          if (mounted) {
            setState(
              () => _error = tr(
                context,
                'Войдите в свой аккаунт МИРЭА.',
                'Sign in to your own MIREA account.',
              ),
            );
          }
          return;
        }
        await AaId.acceptLogin(widget.address, grant);
        if (!mounted) return;
        if (!grant.linked) {
          setState(() {
            _claiming = false;
            _status = 'unlinked';
            _qr = null;
            _error = tr(
              context,
              'Вход в AA ID выполнен, но сессия МИРЭА не подключилась. Создайте новый код, чтобы повторить подключение.',
              'AA ID sign-in succeeded, but the MIREA session did not connect. Create a new code to retry.',
            );
          });
        } else {
          Navigator.of(context).pop();
        }
        return;
      }
      if (['failed', 'expired', 'cancelled'].contains(status)) {
        setState(
          () => _error = tr(
            context,
            'QR-вход завершён. Создайте новый код.',
            'This sign-in ended. Create a new code.',
          ),
        );
        return;
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(
        () => _error = _claiming
            ? tr(
                context,
                'Не удалось получить результат входа. Создайте новый код.',
                'Could not claim sign-in. Create a new code.',
              )
            : tr(
                context,
                'Связь прервана. Проверяем снова…',
                'Connection interrupted. Checking again…',
              ),
      );
    } finally {
      _polling = false;
      if (mounted &&
          generation == _generation &&
          !_claiming &&
          _active &&
          !['failed', 'expired', 'cancelled', 'unlinked'].contains(_status)) {
        _timer = Timer(const Duration(seconds: 2), _poll);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _active = true;
      _timer?.cancel();
      _poll();
    }
    if (state == AppLifecycleState.paused) {
      _active = false;
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CampusScaffold(
    appBar: CampusAppBar(title: Text(tr(context, 'Вход', 'Sign in'))),
    body: CampusPageBody(
      child: ListView(
        padding: AaPageLayout.insets(context),
        children: [
          BrockmannText(
            tr(
              context,
              'Подтвердите вход через МИРЭА',
              'Approve sign-in with MIREA',
            ),
            role: BrockmannType.heading,
          ),
          const SizedBox(height: 12),
          BrockmannText(
            tr(
              context,
              'Отсканируйте QR-код и подтвердите вход. Сервер завершит подключение автоматически.',
              'Scan the QR code and approve sign-in. The server will finish connecting automatically.',
            ),
          ),
          const SizedBox(height: 24),
          if (_qr != null && !_claiming && _status != 'finishing')
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ColoredBox(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Image.memory(
                        _qr!,
                        gaplessPlayback: true,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Center(child: Icon(Icons.broken_image)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if ((_qr == null || _claiming || _status == 'finishing') &&
              _status != 'unlinked' &&
              _error == null) ...[
            const Center(child: CampusProgress.compact()),
            const SizedBox(height: 16),
            BrockmannText(
              tr(
                context,
                'Завершаем вход на сервере…',
                'Completing sign-in on the server…',
              ),
            ),
          ],
          if (_status == 'unlinked')
            CampusButton.text(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr(context, 'Продолжить', 'Continue')),
            ),
          if (_error != null) ...[
            const SizedBox(height: 20),
            BrockmannText(_error!, color: context.brockmann.danger),
            const SizedBox(height: 12),
            CampusButton.filled(
              onPressed: _polling ? null : _start,
              child: Text(tr(context, 'Новый код', 'New code')),
            ),
          ],
        ],
      ),
    ),
  );
}
