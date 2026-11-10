import 'dart:async';

import 'package:flutter/services.dart';
import 'package:brockmann/brockmann.dart';

abstract final class AppHaptics {
  static BrockmannFeedbackController? controller;
  static void selection() {
    if (controller != null) {
      controller!.play(BrockmannSound.select);
    } else {
      _send(HapticFeedback.selectionClick());
    }
  }

  static void navigation() {
    if (controller != null) {
      controller!.play(BrockmannSound.open);
    } else {
      _send(HapticFeedback.lightImpact());
    }
  }

  static void action({required bool primary}) {
    if (controller != null) {
      controller!.play(
        primary ? BrockmannSound.activate : BrockmannSound.select,
      );
    } else {
      _send(
        primary
            ? HapticFeedback.mediumImpact()
            : HapticFeedback.selectionClick(),
      );
    }
  }

  static void _send(Future<void> feedback) {
    // Unsupported devices must not interrupt an action.
    unawaited(feedback.catchError((Object _) {}));
  }
}
