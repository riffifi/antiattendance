import 'dart:async';

import 'package:flutter/services.dart';

abstract final class AppHaptics {
  static void selection() => _send(HapticFeedback.selectionClick());
  static void navigation() => _send(HapticFeedback.lightImpact());
  static void action({required bool primary}) => _send(
    primary ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick(),
  );

  static void _send(Future<void> feedback) {
    // Unsupported devices must not interrupt an action.
    unawaited(feedback.catchError((Object _) {}));
  }
}
