import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum BrockmannSound {
  activate,
  select,
  toggleOn,
  toggleOff,
  open,
  close,
  confirm,
  reject;

  String get assetName => switch (this) {
    toggleOn => 'toggle-on',
    toggleOff => 'toggle-off',
    _ => name,
  };
  int get priority => switch (this) {
    reject => 6,
    confirm => 5,
    toggleOn || toggleOff => 4,
    select => 3,
    open || close => 2,
    activate => 1,
  };
  bool get essential =>
      this == toggleOn ||
      this == toggleOff ||
      this == confirm ||
      this == reject;
}

enum BrockmannSoundMode { off, essential, subtle }

enum BrockmannSoundStatus { disabled, starting, ready, unavailable }

abstract class BrockmannSoundBackend {
  Future<bool> prepare();
  Future<void> play(BrockmannSound cue, double gain);
  Future<void> stop();
  Future<void> dispose();
}

class AndroidSoundBackend implements BrockmannSoundBackend {
  static const channel = MethodChannel('dev.brockmann/feedback');
  @override
  Future<bool> prepare() async {
    try {
      return await channel.invokeMethod<bool>('prepare') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> play(BrockmannSound cue, double gain) async {
    try {
      await channel.invokeMethod<void>('play', {
        'cue': cue.assetName,
        'gain': gain,
      });
    } on PlatformException {
      /* Device loss is silent. */
    } on MissingPluginException {
      /* Widgets also run off Android. */
    }
  }

  @override
  Future<void> stop() async {
    try {
      await channel.invokeMethod<void>('stop');
    } on PlatformException {
      /* Already stopped. */
    } on MissingPluginException {
      /* No native backend. */
    }
  }

  @override
  Future<void> dispose() => stop();
}

enum BrockmannHapticMode { off, essential, subtle }

abstract class BrockmannHapticBackend {
  Future<void> play(BrockmannSound cue);
  Future<void> cancel();
  Future<void> gesture({required bool lifting}) async {}
}

/// Android view haptics honor system touch-feedback settings without permissions.
class AndroidHapticBackend implements BrockmannHapticBackend {
  @override
  Future<void> play(BrockmannSound cue) async {
    try {
      await AndroidSoundBackend.channel.invokeMethod<bool>('haptics.play', {
        'cue': cue.assetName,
      });
    } on PlatformException {
      /* Optional feedback. */
    } on MissingPluginException {
      /* No Android view. */
    }
  }

  @override
  Future<void> gesture({required bool lifting}) async {
    try {
      await AndroidSoundBackend.channel.invokeMethod<bool>('haptics.play', {
        'cue': lifting ? 'lift' : 'land',
      });
    } on PlatformException {
      /* Optional feedback. */
    } on MissingPluginException {
      /* No Android view. */
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await AndroidSoundBackend.channel.invokeMethod<void>('haptics.cancel');
    } on PlatformException {
      /* Already stopped. */
    } on MissingPluginException {
      /* No Android view. */
    }
  }
}

/// Semantic feedback with independent audio and haptic preferences.
/// Audio is off by default; essential haptics defer to Android's user setting.
class BrockmannFeedbackController extends ChangeNotifier
    with WidgetsBindingObserver {
  BrockmannFeedbackController({
    BrockmannSoundBackend? backend,
    BrockmannHapticBackend? hapticBackend,
  }) : _backend = backend ?? AndroidSoundBackend(),
       _haptics = hapticBackend ?? AndroidHapticBackend() {
    WidgetsBinding.instance.addObserver(this);
  }
  final BrockmannSoundBackend _backend;
  final BrockmannHapticBackend _haptics;
  BrockmannHapticMode _hapticMode = BrockmannHapticMode.essential;
  BrockmannHapticMode get hapticMode => _hapticMode;
  bool allowsHaptic(BrockmannSound cue) =>
      _foreground &&
      _hapticMode != BrockmannHapticMode.off &&
      (_hapticMode == BrockmannHapticMode.subtle || cue.essential);
  final _clock = Stopwatch()..start();
  BrockmannSoundMode _mode = BrockmannSoundMode.off;
  double _volume = .35;
  BrockmannSoundStatus _status = BrockmannSoundStatus.disabled;
  BrockmannSound? _pending, _last;
  int _lastAt = -1000000, _generation = 0;
  bool _scheduled = false, _disposed = false, _foreground = true;
  BrockmannSoundMode get mode => _mode;
  double get volume => _volume;
  BrockmannSoundStatus get status => _status;
  bool allows(BrockmannSound cue) =>
      _foreground &&
      _mode != BrockmannSoundMode.off &&
      _volume > 0 &&
      (_mode == BrockmannSoundMode.subtle || cue.essential);
  Future<void> configure({
    BrockmannSoundMode? mode,
    double? volume,
    BrockmannHapticMode? haptics,
  }) async {
    if (_disposed) return;
    _hapticMode = haptics ?? _hapticMode;
    if (_hapticMode == BrockmannHapticMode.off || !_foreground) {
      await _haptics.cancel();
    }
    if (_disposed) return;
    _mode = mode ?? _mode;
    _volume = volume == null
        ? _volume
        : volume.isFinite
        ? volume.clamp(0, 1)
        : 0;
    if (_mode == BrockmannSoundMode.off || _volume == 0 || !_foreground) {
      _generation++;
      _pending = null;
      _status = BrockmannSoundStatus.disabled;
      notifyListeners();
      await _backend.stop();
      return;
    }
    if (_status == BrockmannSoundStatus.ready ||
        _status == BrockmannSoundStatus.starting) {
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    _status = BrockmannSoundStatus.starting;
    notifyListeners();
    final ready = await _backend.prepare();
    if (_disposed || generation != _generation) return;
    _status = ready
        ? BrockmannSoundStatus.ready
        : BrockmannSoundStatus.unavailable;
    notifyListeners();
  }

  void play(BrockmannSound cue) {
    if (_disposed ||
        (!(allows(cue) && _status == BrockmannSoundStatus.ready) &&
            !allowsHaptic(cue))) {
      return;
    }
    if (_pending == null || cue.priority >= _pending!.priority) _pending = cue;
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      final sound = _pending;
      _pending = null;
      if (_disposed ||
          sound == null ||
          (!allows(sound) && !allowsHaptic(sound))) {
        return;
      }
      final now = _clock.elapsedMilliseconds;
      final higher =
          sound.priority >= 5 &&
          (_last == null || sound.priority > _last!.priority);
      if (!higher && now - _lastAt < (sound == _last ? 100 : 45)) return;
      _last = sound;
      _lastAt = now;
      if (allows(sound) && _status == BrockmannSoundStatus.ready) {
        unawaited(_backend.play(sound, _volume));
      }
      if (allowsHaptic(sound)) unawaited(_haptics.play(sound));
    });
  }

  int _selectionAt = -1000;

  /// A restrained, haptic-only detent for deliberate picker changes.
  void selection() {
    if (_disposed || !_foreground || _hapticMode == BrockmannHapticMode.off) {
      return;
    }
    final now = _clock.elapsedMilliseconds;
    if (now - _selectionAt < 80) return;
    _selectionAt = now;
    unawaited(_haptics.play(BrockmannSound.select));
  }

  /// One tick at pickup / landing; never emit ticks for intermediate drag moves.
  void gesture({required bool lifting}) {
    if (_disposed || !_foreground || _hapticMode == BrockmannHapticMode.off) {
      return;
    }
    if ((_last?.priority ?? 0) >= 5 &&
        _clock.elapsedMilliseconds - _lastAt < 200) {
      return;
    }
    unawaited(_haptics.gesture(lifting: lifting));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    unawaited(configure());
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _pending = null;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_backend.dispose());
    unawaited(_haptics.cancel());
    super.dispose();
  }
}

/// Compatibility name for applications using the original audio-only API.
typedef BrockmannSoundController = BrockmannFeedbackController;

class BrockmannFeedbackScope extends InheritedWidget {
  const BrockmannFeedbackScope({
    super.key,
    required super.child,
    this.controller,
  });
  final BrockmannSoundController? controller;
  static BrockmannSoundController? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<BrockmannFeedbackScope>()
      ?.controller;
  static void play(BuildContext context, BrockmannSound cue) =>
      of(context)?.play(cue);
  @override
  bool updateShouldNotify(BrockmannFeedbackScope oldWidget) =>
      oldWidget.controller != controller;
}

/// App-owned preferences; native storage is optional outside Android.
class BrockmannPreferences {
  static Future<Map<String, dynamic>> read() async {
    try {
      return Map<String, dynamic>.from(
        await AndroidSoundBackend.channel.invokeMapMethod<String, dynamic>(
              'preferences.read',
            ) ??
            {},
      );
    } on PlatformException {
      return {};
    } on MissingPluginException {
      return {};
    }
  }

  static Future<void> write(Map<String, dynamic> values) async {
    try {
      await AndroidSoundBackend.channel.invokeMethod<void>(
        'preferences.write',
        values,
      );
    } on PlatformException {
      /* App can supply another persistence layer. */
    } on MissingPluginException {
      /* No persistence backend on this platform. */
    }
  }
}
