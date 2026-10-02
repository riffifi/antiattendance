import 'dart:async';

import 'package:flutter/foundation.dart';

import 'accounts.dart';
import 'pulse_api.dart';

typedef ApproveAccount = Future<ApprovalResult> Function(
  SavedAccount account,
  String token,
);

class AttendanceQueue extends ChangeNotifier {
  AttendanceQueue({required this.accounts, required this.approve});

  final List<SavedAccount> accounts;
  final ApproveAccount approve;
  final results = <String, ApprovalResult>{};
  final errors = <String, String>{};
  final confirmed = <String>{};

  String? _queuedToken;
  String? _activeToken;
  DateTime? _activeAt;
  bool _processing = false;
  bool _stopped = false;

  bool get processing => _processing;
  bool get hasScanned => _activeToken != null || _queuedToken != null;
  int get remaining => accounts.length - confirmed.length;

  void accept(String raw) {
    if (_stopped || remaining == 0) return;
    final String token;
    try {
      token = attendanceTokenFromQr(raw);
    } on FormatException {
      return;
    }
    if (token == _queuedToken) return;
    if (token == _activeToken) {
      // A stationary QR may be detected on many frames. Retry it only after
      // a short pause, while allowing every new rotating token immediately.
      if (_processing ||
          DateTime.now().difference(_activeAt!) < const Duration(seconds: 2)) {
        return;
      }
    }
    _queuedToken = token;
    if (!_processing) unawaited(_drain());
  }

  Future<void> _drain() async {
    _processing = true;
    notifyListeners();
    while (!_stopped && _queuedToken != null && remaining > 0) {
      final token = _queuedToken!;
      _queuedToken = null;
      _activeToken = token;
      _activeAt = DateTime.now();
      final pending = accounts.where((a) => !confirmed.contains(a.id)).toList();
      for (final account in pending) {
        errors.remove(account.id);
      }
      notifyListeners();
      // Start all pending requests together because the token may expire soon.
      await Future.wait(
        pending.map((account) async {
          try {
            final result = await approve(account, token);
            if (_stopped) return;
            results[account.id] = result;
            if (result.state == ApprovalState.approved) {
              confirmed.add(account.id);
            }
          } catch (error) {
            if (_stopped) return;
            errors[account.id] = error is PulseApiException
                ? error.message
                : 'Ошибка сети. Попробуйте снова.';
          }
          if (!_stopped) notifyListeners();
        }),
      );
    }
    _processing = false;
    if (!_stopped) notifyListeners();
  }

  void stop() {
    _stopped = true;
    _queuedToken = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
