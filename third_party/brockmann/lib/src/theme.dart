import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;

import 'feedback.dart';
import 'layout.dart';

/// Achromatic chrome with one content-independent accent.
@immutable
class BrockmannThemeData extends ThemeExtension<BrockmannThemeData> {
  const BrockmannThemeData({
    this.brightness = Brightness.dark,
    this.accent = const Color(0xff00aba9),
    this.reduceMotion = false,
    this.tilt = true,
    this.motionScale = 1,
  });
  final Brightness brightness;
  final Color accent;
  final bool reduceMotion, tilt;
  final double motionScale;
  bool get light => brightness == Brightness.light;
  Color get background => light ? Colors.white : Colors.black;
  Color get surface =>
      light ? const Color(0xfff2f2f2) : const Color(0xff121212);
  Color get foreground => light ? Colors.black : Colors.white;
  Color get secondary =>
      light ? const Color(0xff5a5a5a) : const Color(0xffa6a6a6);
  Color get disabled =>
      light ? const Color(0xffa8a8a8) : const Color(0xff5c5c5c);
  Color get line => light ? const Color(0xffbdbdbd) : const Color(0xff3a3a3a);
  Color get lineStrong =>
      light ? const Color(0xff4a4a4a) : const Color(0xff8a8a8a);
  Color get danger => const Color(0xffe51400);
  static double contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
  }

  Color get onAccent =>
      contrast(Colors.white, accent) >= 4.5 ? Colors.white : Colors.black;
  Color get accentText {
    double score(Color c) => contrast(c, background) < contrast(c, surface)
        ? contrast(c, background)
        : contrast(c, surface);
    if (score(accent) >= 4.5) return accent;
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 24; i++) {
      final t = (lo + hi) / 2;
      if (score(Color.lerp(accent, foreground, t)!) >= 4.5) {
        hi = t;
      } else {
        lo = t;
      }
    }
    return Color.lerp(accent, foreground, hi)!;
  }

  bool motionReduced(BuildContext context) =>
      reduceMotion || MediaQuery.disableAnimationsOf(context);
  Duration duration(BuildContext context, int milliseconds) => Duration(
    milliseconds: (motionReduced(context) ? 100 : milliseconds * motionScale)
        .round(),
  );
  @override
  BrockmannThemeData copyWith({
    Brightness? brightness,
    Color? accent,
    bool? reduceMotion,
    bool? tilt,
    double? motionScale,
  }) => BrockmannThemeData(
    brightness: brightness ?? this.brightness,
    accent: accent ?? this.accent,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    tilt: tilt ?? this.tilt,
    motionScale: motionScale ?? this.motionScale,
  );
  @override
  BrockmannThemeData lerp(covariant BrockmannThemeData? other, double t) =>
      other == null ? this : _BlendedTheme(this, other, t);
  ThemeData get material => ThemeData(
    brightness: brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: background,
    canvasColor: background,
    fontFamily: 'packages/brockmann/Geist',
    colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
        .copyWith(
          primary: accent,
          onPrimary: onAccent,
          surface: background,
          onSurface: foreground,
        ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    extensions: [this],
    dividerColor: line,
    disabledColor: disabled,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: accent.withValues(alpha: .25),
      selectionHandleColor: accent,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
  );
}

class _BlendedTheme extends BrockmannThemeData {
  _BlendedTheme(this.from, this.to, this.fraction)
    : super(
        brightness: to.brightness,
        accent: Color.lerp(from.accent, to.accent, fraction)!,
        reduceMotion: to.reduceMotion,
        tilt: to.tilt,
        motionScale: to.motionScale,
      );
  final BrockmannThemeData from, to;
  final double fraction;
  Color blend(Color a, Color b) => Color.lerp(a, b, fraction)!;
  @override
  Color get background => blend(from.background, to.background);
  @override
  Color get surface => blend(from.surface, to.surface);
  @override
  Color get foreground => blend(from.foreground, to.foreground);
  @override
  Color get secondary => blend(from.secondary, to.secondary);
  @override
  Color get disabled => blend(from.disabled, to.disabled);
  @override
  Color get line => blend(from.line, to.line);
  @override
  Color get lineStrong => blend(from.lineStrong, to.lineStrong);
  @override
  Color get danger => blend(from.danger, to.danger);
}

extension BrockmannContext on BuildContext {
  BrockmannThemeData get brockmann =>
      Theme.of(this).extension<BrockmannThemeData>() ??
      const BrockmannThemeData();
}

/// The sole bundled type system. Sans/Mono expose their variable weight axis.
enum BrockmannType {
  display,
  title,
  heading,
  value,
  body,
  label,
  caption,
  monoValue,
  monoLarge,
  pixelSquare,
  pixelCircle,
  pixelGrid,
  pixelLine,
  pixelTriangle;

  TextStyle style({Color? color, double? weight}) {
    final (family, size, line, w, tracking) = switch (this) {
      display => ('Geist', 72.0, 72.0, 200.0, -1.44),
      title => ('Geist', 40.0, 44.0, 300.0, -.4),
      heading => ('Geist', 24.0, 28.0, 400.0, 0.0),
      value => ('Geist', 20.0, 24.0, 500.0, 0.0),
      body => ('Geist', 14.0, 20.0, 400.0, 0.0),
      label => ('Geist', 12.0, 16.0, 400.0, .5),
      caption => ('Geist', 11.0, 16.0, 400.0, .2),
      monoValue => ('Geist Mono', 14.0, 20.0, 400.0, 0.0),
      monoLarge => ('Geist Mono', 32.0, 36.0, 300.0, 0.0),
      pixelSquare => ('Geist Pixel Square', 64.0, 72.0, 400.0, 0.0),
      pixelCircle => ('Geist Pixel Circle', 64.0, 72.0, 400.0, 0.0),
      pixelGrid => ('Geist Pixel Grid', 64.0, 72.0, 400.0, 0.0),
      pixelLine => ('Geist Pixel Line', 64.0, 72.0, 400.0, 0.0),
      pixelTriangle => ('Geist Pixel Triangle', 64.0, 72.0, 400.0, 0.0),
    };
    return TextStyle(
      decoration: TextDecoration.none,
      fontFamily: family,
      package: 'brockmann',
      fontSize: size,
      height: line / size,
      color: color,
      letterSpacing: tracking,
      fontWeight:
          FontWeight.values[((weight ?? w) / 100).round().clamp(1, 9) - 1],
      fontVariations: family == 'Geist' || family == 'Geist Mono'
          ? [FontVariation('wght', weight ?? w)]
          : null,
      fontFeatures: family == 'Geist Mono'
          ? [const FontFeature.tabularFigures()]
          : null,
    );
  }
}

class BrockmannText extends StatelessWidget {
  const BrockmannText(
    this.text, {
    super.key,
    this.role = BrockmannType.body,
    this.color,
    this.weight,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
    this.semanticsLabel,
  });
  final String text;
  final BrockmannType role;
  final Color? color;
  final double? weight;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;
  final String? semanticsLabel;
  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: maxLines,
    overflow: overflow,
    textAlign: textAlign,
    softWrap: softWrap,
    semanticsLabel: semanticsLabel,
    style: role.style(
      color: color ?? context.brockmann.foreground,
      weight: weight,
    ),
  );
}

class BrockmannScrollBehavior extends MaterialScrollBehavior {
  const BrockmannScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => StretchingOverscrollIndicator(
    axisDirection: details.direction,
    child: child,
  );
}

/// Installs themes, localization/navigation infrastructure and Android scrolling.
class BrockmannApp extends StatelessWidget {
  const BrockmannApp({
    super.key,
    required this.home,
    this.theme = const BrockmannThemeData(),
    this.feedback,
    this.title = 'Brockmann',
    this.navigatorKey,
  });
  final Widget home;
  final BrockmannThemeData theme;
  final BrockmannSoundController? feedback;
  final String title;
  final GlobalKey<NavigatorState>? navigatorKey;
  @override
  Widget build(BuildContext context) => BrockmannFeedbackScope(
    controller: feedback,
    child: MaterialApp(
      title: title,
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: theme.material,
      themeAnimationDuration: theme.reduceMotion
          ? const Duration(milliseconds: 100)
          : const Duration(milliseconds: 200),
      scrollBehavior: const BrockmannScrollBehavior(),
      home: home,
    ),
  );
}

/// Safe-area shell. Headers and footers remain outside the scrolling content.
///
/// The content inset adapts to the width (24 dp on phones, 48 dp from
/// 600 dp), and [maxContentWidth] keeps lines readable on tablets and
/// desktops. Supply [title] for a large typographic page header that
/// scrolls with the content.
class BrockmannPage extends StatelessWidget {
  const BrockmannPage({
    super.key,
    required this.child,
    this.header,
    this.footer,
    this.scroll = true,
    this.padding,
    this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.maxContentWidth = 960,
    this.controller,
  });
  final Widget child;
  final Widget? header, footer;
  final bool scroll;
  final EdgeInsetsGeometry? padding;
  final String? title, subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;

  /// Maximum width of the content column. Null fills the window.
  final double? maxContentWidth;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: true,
    backgroundColor: context.brockmann.background,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, c) {
          final inset = c.maxWidth < 600 ? 24.0 : 48.0;
          Widget body = child;
          if (title != null) {
            body = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: scroll ? MainAxisSize.min : MainAxisSize.max,
              children: [
                BrockmannPageHeader(
                  title: title!,
                  subtitle: subtitle,
                  onBack: onBack,
                  actions: actions,
                ),
                const SizedBox(height: 32),
                scroll ? child : Expanded(child: child),
              ],
            );
          }
          if (maxContentWidth != null) {
            body = Align(
              alignment: Alignment.topCenter,
              heightFactor: scroll ? 1 : null,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth!),
                child: body,
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?header,
              Expanded(
                child: scroll
                    ? SingleChildScrollView(
                        key: const PageStorageKey('page-scroll'),
                        controller: controller,
                        padding:
                            padding ??
                            EdgeInsets.fromLTRB(inset, 24, inset, 32),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        child: body,
                      )
                    : Padding(
                        padding:
                            padding ??
                            EdgeInsets.fromLTRB(
                              inset,
                              title == null ? 0 : 24,
                              inset,
                              0,
                            ),
                        child: body,
                      ),
              ),
              ?footer,
            ],
          );
        },
      ),
    ),
  );
}
