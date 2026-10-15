import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';

class ThemeCrossfade extends StatefulWidget {
  const ThemeCrossfade({super.key, required this.mode, required this.child});

  final AppThemeMode mode;
  final Widget child;

  @override
  State<ThemeCrossfade> createState() => _ThemeCrossfadeState();
}

class _ThemeCrossfadeState extends State<ThemeCrossfade>
    with SingleTickerProviderStateMixin {
  final _surface = GlobalKey();
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
  )..addStatusListener(_finished);
  late final _opacity = _fade
      .drive(CurveTween(curve: Curves.easeOutCubic))
      .drive(Tween<double>(begin: 1, end: 0));
  ui.Image? _previous;

  void _retire(ui.Image? image) {
    if (image == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  }

  void _finished(AnimationStatus status) {
    if (status != AnimationStatus.completed || _previous == null) return;
    final image = _previous;
    setState(() => _previous = null);
    _retire(image);
  }

  @override
  void didUpdateWidget(ThemeCrossfade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode == widget.mode) return;
    _retire(_previous);
    _previous = null;
    if (MediaQuery.disableAnimationsOf(context)) {
      _fade.value = 1;
      return;
    }
    final boundary = _surface.currentContext?.findRenderObject();
    if (boundary is! _ThemeBoundary || !boundary.hasSize) return;
    try {
      _previous = boundary.capture(
        MediaQuery.devicePixelRatioOf(context).clamp(1.0, 1.5),
      );
      if (_previous == null) return;
      _fade.forward(from: 0);
    } catch (_) {
      // Theme changes still work when a surface cannot be captured.
      _fade.value = 1;
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _retire(_previous);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      _ThemeSurface(key: _surface, child: widget.child),
      if (_previous != null)
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: FadeTransition(
                opacity: _opacity,
                child: RawImage(image: _previous, fit: BoxFit.fill),
              ),
            ),
          ),
        ),
    ],
  );
}

class _ThemeSurface extends SingleChildRenderObjectWidget {
  const _ThemeSurface({super.key, required super.child});
  @override
  RenderRepaintBoundary createRenderObject(BuildContext context) =>
      _ThemeBoundary();
}

class _ThemeBoundary extends RenderRepaintBoundary {
  ui.Image? capture(double pixelRatio) {
    final painted = layer;
    if (painted is! OffsetLayer || size.isEmpty) return null;
    // Capture the previous paint, before the new theme is laid out.
    return painted.toImageSync(Offset.zero & size, pixelRatio: pixelRatio);
  }
}
