import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';
import 'foundation.dart';
import 'feedback.dart';
import 'controls.dart';
import 'interaction.dart';

@immutable
class BrockmannColorScheme {
  const BrockmannColorScheme(
    this.name,
    this.primary, {
    this.companions = const [],
  });
  final String name;
  final Color primary;
  final List<Color> companions;
  String get hex => colorHex(primary);
}

String colorHex(Color color) =>
    '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';

enum BrockmannPaletteVariant { ribbon, swatches, grid }

List<BrockmannColorScheme> windows8Palette() {
  const colors = <String, int>{
    'gold': 0xc6b324,
    'olive': 0x718c31,
    'slate blue': 0x375c9c,
    'wine': 0x8e243d,
    'plum': 0x682d73,
    'brick': 0x9c332c,
    'rust': 0xb94b18,
    'ruby': 0xbe2044,
    'berry': 0x8c147c,
    'indigo': 0x48249a,
    'navy': 0x183c78,
    'ocean': 0x16739d,
    'forest': 0x13834b,
    'green': 0x38a029,
    'lime': 0x88bf24,
    'tangerine': 0xf89619,
    'coral': 0xee5035,
    'fuchsia': 0xde3986,
    'purple': 0x9c42cb,
    'cobalt': 0x4266cb,
    'sky': 0x239bd5,
    'cyan': 0x2bb7d0,
    'turquoise': 0x34c5be,
    'mint': 0x70c391,
    'chartreuse': 0xc4d53b,
    'yellow': 0xf2c627,
    'orange': 0xe99a32,
    'salmon': 0xdb7465,
    'orchid': 0xc87ba9,
    'periwinkle': 0x8a90d0,
    'sea': 0x4eaaa6,
    'terracotta': 0xc56143,
  };
  return colors.entries
      .map((e) {
        final c = Color(0xff000000 | e.value);
        return BrockmannColorScheme(
          e.key,
          c,
          companions: [
            Color.lerp(c, Colors.white, .5)!,
            Color.lerp(c, Colors.black, .45)!,
            Color.from(alpha: 1, red: c.b, green: c.r, blue: c.g),
          ],
        );
      })
      .toList(growable: false);
}

/// A curated palette with balanced lightness and distinct hue families.
List<BrockmannColorScheme> brockmannPalette() => [
  for (final (name, hex) in const [
    ('ink', 0xff24282d),
    ('stone', 0xff858b92),
    ('paper', 0xffe6e1d8),
    ('rose', 0xffdf6679),
    ('vermilion', 0xffe16b45),
    ('amber', 0xffd9a441),
    ('citron', 0xffb7c95a),
    ('fern', 0xff62a67c),
    ('lagoon', 0xff39a6a0),
    ('azure', 0xff529dcc),
    ('iris', 0xff8275ca),
    ('orchid', 0xffba77af),
  ])
    BrockmannColorScheme(
      name,
      Color(hex),
      companions: [
        Color.lerp(Color(hex), Colors.white, .55)!,
        Color.lerp(Color(hex), Colors.black, .45)!,
      ],
    ),
];

/// Animated colour tiles. [BrockmannPaletteVariant.ribbon] is retained as an
/// alias for the scrolling strip; historical Windows styling is no longer used.
class BrockmannColorPicker extends StatelessWidget {
  const BrockmannColorPicker({
    super.key,
    required this.label,
    required this.schemes,
    required this.selected,
    required this.onChanged,
    this.variant = BrockmannPaletteVariant.grid,
    this.axis = Axis.horizontal,
    this.companionCount = 0,
    this.verticalExtent = 320,
  }) : assert(selected >= 0),
       assert(companionCount >= 0 && companionCount <= 3);
  final String label;
  final List<BrockmannColorScheme> schemes;
  final int selected, companionCount;
  final ValueChanged<int>? onChanged;
  final BrockmannPaletteVariant variant;
  final Axis axis;
  final double verticalExtent;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    final current = schemes.isEmpty
        ? null
        : schemes[selected.clamp(0, schemes.length - 1)];
    Widget tile(int i, double width) {
      final scheme = schemes[i], active = identical(current, scheme);
      final ink =
          BrockmannThemeData.contrast(Colors.white, scheme.primary) >= 4.5
          ? Colors.white
          : Colors.black;
      return SizedBox(
        width: width,
        height: 64,
        child: Semantics(
          selected: active,
          inMutuallyExclusiveGroup: true,
          child: BrockmannPressable(
            label: '${scheme.name} ${scheme.hex}',
            onPressed: onChanged == null
                ? null
                : () {
                    if (!active) {
                      BrockmannFeedbackScope.play(
                        context,
                        BrockmannSound.select,
                      );
                      onChanged!(i);
                    }
                  },
            builder: (c, pressed) => Center(
              child: AnimatedContainer(
                key: ValueKey('brockmann-colour-tile-$i'),
                width: active ? 58 : 50,
                height: active ? 58 : 50,
                duration: t.duration(c, 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: active ? t.foreground : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(
                      alpha: onChanged == null ? .4 : 1,
                    ),
                  ),
                  child: Center(
                    child: active
                        ? BrockmannGlyph(
                            BrockmannIcon.check,
                            color: ink,
                            size: 20,
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrockmannText(label, role: BrockmannType.label, color: t.secondary),
        const SizedBox(height: 8),
        Row(
          children: [
            if (current != null) ...[
              Container(width: 24, height: 24, color: current.primary),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: BrockmannText(
                current == null
                    ? 'No colours'
                    : '${current.name} / ${current.hex}',
                role: BrockmannType.monoValue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (current != null)
          LayoutBuilder(
            builder: (c, box) {
              if (variant == BrockmannPaletteVariant.grid) {
                final columns = math.max(1, (box.maxWidth / 64).floor());
                return Wrap(
                  children: [
                    for (var i = 0; i < schemes.length; i++)
                      tile(i, box.maxWidth / columns),
                  ],
                );
              }
              return SizedBox(
                height: axis == Axis.vertical ? verticalExtent : 64,
                child: SingleChildScrollView(
                  scrollDirection: axis,
                  child: axis == Axis.vertical
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < schemes.length; i++)
                              tile(i, 64),
                          ],
                        )
                      : Row(
                          children: [
                            for (var i = 0; i < schemes.length; i++)
                              tile(i, 64),
                          ],
                        ),
                ),
              );
            },
          ),
        if (current != null && companionCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 8,
              children: [
                for (final colour in current.companions.take(companionCount))
                  Semantics(
                    label: 'Companion ${colorHex(colour)}',
                    child: Container(width: 32, height: 32, color: colour),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Arbitrary colour input with a saturation/value plane, hue and optional alpha.
/// Direct input is immediate; external value changes move the marker over 180ms.
class BrockmannColorField extends StatefulWidget {
  const BrockmannColorField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.showAlpha = false,
  });
  final String label;
  final Color value;
  final ValueChanged<Color>? onChanged;
  final bool showAlpha;
  @override
  State<BrockmannColorField> createState() => _BrockmannColorFieldState();
}

class _BrockmannColorFieldState extends State<BrockmannColorField> {
  double _hue = 0;
  bool _direct = false;
  HSVColor get hsv {
    final c = HSVColor.fromColor(widget.value);
    return c.withHue(c.saturation < .001 ? _hue : c.hue);
  }

  void emit(HSVColor colour) {
    _hue = colour.hue;
    widget.onChanged?.call(colour.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final colour = hsv,
        t = context.brockmann,
        enabled = widget.onChanged != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.value,
                border: Border.all(color: t.line),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BrockmannText(widget.label, role: BrockmannType.label),
                  BrockmannText(
                    colorHex(widget.value),
                    role: BrockmannType.monoValue,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (c, box) {
            void set(Offset p) {
              setState(() => _direct = true);
              emit(
                colour
                    .withSaturation((p.dx / box.maxWidth).clamp(0, 1))
                    .withValue((1 - p.dy / 192).clamp(0, 1)),
              );
            }

            return Semantics(
              label: '${widget.label} saturation and brightness',
              child: BrockmannInteractionRegion(
                enabled: enabled,
                child: GestureDetector(
                  key: const ValueKey('brockmann-colour-plane'),
                  onTapUp: enabled
                      ? (_) => setState(() => _direct = false)
                      : null,
                  behavior: HitTestBehavior.opaque,
                  onTapDown: enabled ? (d) => set(d.localPosition) : null,
                  onPanStart: enabled ? (d) => set(d.localPosition) : null,
                  onPanUpdate: enabled ? (d) => set(d.localPosition) : null,
                  onPanEnd: enabled
                      ? (_) => setState(() => _direct = false)
                      : null,
                  onPanCancel: enabled
                      ? () => setState(() => _direct = false)
                      : null,
                  child: SizedBox(
                    height: 192,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: HSVColor.fromAHSV(
                                1,
                                colour.hue,
                                1,
                                1,
                              ).toColor(),
                              gradient: const LinearGradient(
                                colors: [Colors.white, Colors.transparent],
                              ),
                            ),
                          ),
                        ),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black],
                              ),
                            ),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: _direct
                              ? Duration.zero
                              : t.duration(c, 180),
                          curve: Curves.easeOutCubic,
                          left: colour.saturation * (box.maxWidth - 24),
                          top: (1 - colour.value) * 168,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(color: Colors.black, spreadRadius: 1),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        BrockmannSlider(
          label: 'hue',
          value: colour.hue / 360,
          onChanged: enabled ? (v) => emit(colour.withHue(v * 359.999)) : null,
          trackGradient: const LinearGradient(
            colors: [
              Color(0xffff0000),
              Color(0xffffff00),
              Color(0xff00ff00),
              Color(0xff00ffff),
              Color(0xff0000ff),
              Color(0xffff00ff),
              Color(0xffff0000),
            ],
          ),
        ),
        BrockmannSlider(
          label: 'saturation',
          value: colour.saturation,
          onChanged: enabled ? (v) => emit(colour.withSaturation(v)) : null,
        ),
        BrockmannSlider(
          label: 'brightness',
          value: colour.value,
          onChanged: enabled ? (v) => emit(colour.withValue(v)) : null,
        ),
        if (widget.showAlpha)
          BrockmannSlider(
            label: 'opacity',
            value: widget.value.a,
            onChanged: enabled
                ? (v) => widget.onChanged!(widget.value.withValues(alpha: v))
                : null,
          ),
      ],
    );
  }
}
