import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:brockmann/brockmann.dart';

import 'app_haptics.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'app_theme.dart';
import 'frontend/page_layout.dart';
import 'l10n.dart';
import 'editorial_controls.dart';
export 'editorial_controls.dart';
export 'campus_models.dart';
import 'campus_models.dart';

/// Compact, outlined lettermark that remains readable in every appearance.
class CampusBrand extends StatelessWidget {
  const CampusBrand({
    super.key,
    this.width = 84,
    this.height = 38,
    this.label = 'AntiAttendance',
  });
  final double width;
  final double height;
  final String label;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'icon/brand.svg',
    width: width,
    height: height,
    fit: BoxFit.contain,
    colorFilter: ColorFilter.mode(context.palette.ink, BlendMode.srcIn),
    semanticsLabel: label,
  );
}

/// Keeps supporting screens on the same reading column, including safe insets.
class CampusPageBody extends StatelessWidget {
  const CampusPageBody({super.key, required this.child, this.maxWidth = 960});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}

// Shared typographic layout primitives.
class CampusHeader extends StatelessWidget {
  const CampusHeader({
    super.key,
    required this.title,
    this.subtitle = '',
    this.trailing,
    this.fitTitle = false,
  });
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool fitTitle;

  @override
  Widget build(BuildContext context) {
    final sharedHeading =
        BrockmannNavigationScope.of(context)?.headingVisible ?? false;
    return Padding(
      padding: EdgeInsets.only(
        left: AaPageLayout.titleNudge(context),
        right: AaPageLayout.titleNudge(context),
        bottom: sharedHeading
            ? (subtitle.isEmpty && trailing == null ? 0 : 20)
            : 32,
      ),
      child: BrockmannPageHeader(
        title: title.toLowerCase(),
        reuseNavigationHeading: true,
        subtitle: subtitle.isEmpty ? null : subtitle,
        actions: trailing == null ? const [] : [trailing!],
      ),
    );
  }
}

/// Press feedback for content whose inner controls own the action callbacks.
class CampusPressable extends StatefulWidget {
  const CampusPressable({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<CampusPressable> createState() => _CampusPressableState();
}

class _CampusPressableState extends State<CampusPressable> {
  bool _pressed = false;
  Offset? _origin;
  void _release() {
    _origin = null;
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: !widget.enabled
        ? null
        : (event) {
            _origin = event.position;
            setState(() => _pressed = true);
          },
    onPointerMove: (event) {
      if (_origin != null && (event.position - _origin!).distance > 8) {
        _release();
      }
    },
    onPointerUp: (_) => _release(),
    onPointerCancel: (_) => _release(),
    child: BrockmannMotion(
      value: _pressed && widget.enabled ? 1 : 0,
      milliseconds: _pressed ? 60 : 160,
      builder: (context, value) =>
          Transform.scale(scale: 1 - .015 * value, child: widget.child),
    ),
  );
}

class CampusPanel extends StatelessWidget {
  const CampusPanel({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(24),
  });
  final Widget child;
  final Color? color;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: color == null ? child : ColoredBox(color: color!, child: child),
  );
}

class CampusDisclosure extends StatefulWidget {
  const CampusDisclosure({
    super.key,
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;
  @override
  State<CampusDisclosure> createState() => _CampusDisclosureState();
}

class _CampusDisclosureState extends State<CampusDisclosure> {
  bool? _open;
  Object get _storageIdentifier =>
      ('campus-disclosure-expanded', widget.key ?? widget.title);
  bool get _expanded {
    if (_open != null) return _open!;
    return PageStorage.maybeOf(context)
            ?.readState(context, identifier: _storageIdentifier) ==
        true;
  }

  void _toggle() {
    final next = !_expanded;
    BrockmannFeedbackScope.play(
      context,
      next ? BrockmannSound.open : BrockmannSound.close,
    );
    setState(() => _open = next);
    PageStorage.maybeOf(context)
        ?.writeState(context, next, identifier: _storageIdentifier);
  }

  @override
  Widget build(BuildContext context) {
    final open = _expanded;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: open,
          child: BrockmannPressable(
            label: widget.title,
            onPressed: _toggle,
            builder: (context, pressed) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: BrockmannText(
                      widget.title,
                      role: BrockmannType.value,
                      weight: 400,
                      color: pressed
                          ? context.brockmann.accent
                          : context.brockmann.foreground,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ExcludeSemantics(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 14,
                            height: 1.5,
                            color: context.brockmann.foreground,
                          ),
                          AnimatedContainer(
                            key: const ValueKey('disclosure-vertical-stroke'),
                            duration: context.brockmann.motionReduced(context)
                                ? Duration.zero
                                : context.brockmann.duration(context, 160),
                            curve: Curves.easeInOutCubic,
                            width: 1.5,
                            height: open ? 0 : 14,
                            color: context.brockmann.foreground,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (context.brockmann.motionReduced(context)) ...[
          if (open) ...widget.children,
        ] else
          AnimatedSize(
            duration: context.brockmann.duration(context, 160),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: open
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.children,
                  )
                : const SizedBox(width: double.infinity),
          ),
      ],
    );
  }
}

/// Small state-label changes, without duplicate accessibility announcements.
class CampusValueTransition extends StatelessWidget {
  const CampusValueTransition(
    this.text, {
    super.key,
    this.role = BrockmannType.body,
    this.color,
  });
  final String text;
  final BrockmannType role;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    if (context.brockmann.motionReduced(context)) {
      return BrockmannText(text, role: role, color: color);
    }
    final duration = context.brockmann.duration(context, 140);
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: double.infinity,
        child: AnimatedSwitcher(
          duration: duration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, .08),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          layoutBuilder: (current, previous) => Stack(
            clipBehavior: Clip.none,
            alignment: AlignmentDirectional.topStart,
            children: [
              for (final child in previous)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ExcludeSemantics(child: IgnorePointer(child: child)),
                ),
              ?current,
            ],
          ),
          child: BrockmannText(
            text,
            key: ValueKey(text),
            role: role,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// Search results enter once; ordinary rebuilds do not replay their animation.
class CampusReveal extends StatelessWidget {
  const CampusReveal({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (context.brockmann.motionReduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: context.brockmann.duration(context, 140),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 4 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

class CampusSectionTitle extends StatelessWidget {
  const CampusSectionTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Semantics(
      header: true,
      child: BrockmannText(
        title.toLowerCase(),
        role: BrockmannType.value,
        weight: 400,
        color: context.brockmann.accent,
      ),
    ),
  );
}

class CampusButton extends StatelessWidget {
  const CampusButton.filled({
    super.key,
    required this.onPressed,
    required this.child,
  }) : style = CampusButtonStyle.filled;
  const CampusButton.text({
    super.key,
    required this.onPressed,
    required this.child,
  }) : style = CampusButtonStyle.text;
  const CampusButton.action({
    super.key,
    required this.onPressed,
    required Widget label,
    this.style = CampusButtonStyle.filled,
  }) : child = label;
  final VoidCallback? onPressed;
  final Widget child;
  final CampusButtonStyle style;

  @override
  Widget build(BuildContext context) => BrockmannButton(
    label: child is Text ? (child as Text).data ?? '' : '',
    alignment: Alignment.center,
    style: switch (style) {
      CampusButtonStyle.filled => BrockmannButtonStyle.primary,
      CampusButtonStyle.tonal ||
      CampusButtonStyle.outlined => BrockmannButtonStyle.secondary,
      CampusButtonStyle.text => BrockmannButtonStyle.text,
    },
    onPressed: onPressed == null
        ? null
        : () {
            AppHaptics.action(primary: style == CampusButtonStyle.filled);
            onPressed!();
          },
    child: DefaultTextStyle.merge(textAlign: TextAlign.center, child: child),
  );
}

class CampusNavigation extends StatelessWidget {
  const CampusNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.labels,
  });
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<String> labels;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: BrockmannPivot(
          options: labels,
          selected: selectedIndex,
          compact: true,
          onChanged: onDestinationSelected,
        ),
      ),
    ),
  );
}

class CampusListItem extends StatelessWidget {
  const CampusListItem({
    super.key,
    required this.headline,
    this.supportingText,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.showDivider = true,
    this.navigation = false,
  });
  final String headline;
  final String? supportingText;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected, showDivider;
  final bool navigation;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Column(
      children: [
        Row(
          children: [
            if (leading != null)
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: leading!,
              ),
            Expanded(
              child: BrockmannListItem(
                label: headline,
                secondary: supportingText,
                selected: selected,
                chevron: navigation,
                onPressed: onTap == null
                    ? null
                    : () {
                        AppHaptics.navigation();
                        onTap!();
                      },
              ),
            ),
            if (trailing != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: bounds.maxWidth * .42),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 12),
                  child: trailing!,
                ),
              ),
          ],
        ),
        if (showDivider && !context.brockmann.windowsPhone)
          Divider(height: .5, thickness: .5, color: context.brockmann.line),
      ],
    ),
  );
}

class CampusTextField extends StatelessWidget {
  const CampusTextField({
    super.key,
    this.controller,
    this.label,
    this.placeholder,
    this.leading,
    this.trailing,
    this.autofocus = false,
    this.obscureText = false,
    this.enabled = true,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.textCapitalization = TextCapitalization.none,
    this.textAlign = TextAlign.start,
    this.suffixText,
    this.error,
  });
  final TextEditingController? controller;
  final String? label;
  final String? placeholder;
  final Widget? leading;
  final Widget? trailing;
  final bool autofocus;
  final bool obscureText;
  final bool enabled;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization textCapitalization;
  final TextAlign textAlign;
  final String? suffixText;
  final String? error;
  @override
  Widget build(BuildContext context) => BrockmannTextField(
    label: label ?? '',
    controller: controller,
    placeholder: placeholder,
    leading: leading,
    trailing: trailing,
    autofocus: autofocus,
    obscureText: obscureText,
    enabled: enabled,
    maxLength: maxLength,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    inputFormatters: inputFormatters,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    textCapitalization: textCapitalization,
    textAlign: textAlign,
    suffixText: suffixText,
    error: error,
  );
}

class CampusScanFrame extends StatelessWidget {
  const CampusScanFrame({
    super.key,
    required this.size,
    required this.color,
    this.child,
  });
  final double size;
  final Color color;
  final Widget? child;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(foregroundPainter: _ScanCorners(color), child: child),
  );
}

class _ScanCorners extends CustomPainter {
  const _ScanCorners(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const inset = 2.0;
    final length = size.shortestSide * .17;
    for (final corner in [
      Offset(inset, inset),
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      Offset(size.width - inset, size.height - inset),
    ]) {
      final dx = corner.dx < size.width / 2 ? 1.0 : -1.0;
      final dy = corner.dy < size.height / 2 ? 1.0 : -1.0;
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx, corner.dy + dy * length)
          ..lineTo(corner.dx, corner.dy + dy * 10)
          ..quadraticBezierTo(
            corner.dx,
            corner.dy,
            corner.dx + dx * 10,
            corner.dy,
          )
          ..lineTo(corner.dx + dx * length, corner.dy),
        pen,
      );
    }
  }

  @override
  bool shouldRepaint(_ScanCorners oldDelegate) => oldDelegate.color != color;
}

/// A route is a typographic page, with a quiet command row above its title.
/// Feature pages own their scrolling and domain state; this frame owns insets.
class CampusScaffold extends StatelessWidget {
  const CampusScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
  });
  final CampusAppBar? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: backgroundColor ?? context.brockmann.background,
    resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    bottomNavigationBar: bottomNavigationBar,
    body: SafeArea(
      top: appBar != null,
      bottom: false,
      child: LayoutBuilder(
        builder: (context, bounds) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (appBar case final bar?)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: bounds.maxHeight * .45),
                child: SingleChildScrollView(
                  child: _CampusRouteHeader(bar: bar),
                ),
              ),
            Expanded(child: body),
          ],
        ),
      ),
    ),
  );
}

class _CampusRouteHeader extends StatelessWidget {
  const _CampusRouteHeader({required this.bar});
  final CampusAppBar bar;
  @override
  Widget build(BuildContext context) {
    final title = bar.title;
    if (bar.compact) {
      return Padding(
        padding: EdgeInsets.fromLTRB(12, 8, context.brockmannLayout.inset, 12),
        child: Row(
          children: [
            if (bar.leading != null)
              bar.leading!
            else if (bar.automaticallyImplyLeading &&
                Navigator.of(context).canPop())
              CampusTextAction(
                icon: Icons.arrow_back_rounded,
                label: tr(context, 'Назад', 'Back'),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: title is Text && title.data != null
                  ? Semantics(
                      header: true,
                      child: BrockmannText(
                        bar.preserveTitleCase
                            ? title.data!
                            : title.data!.toLowerCase(),
                        role: BrockmannType.heading,
                      ),
                    )
                  : title ?? const SizedBox(),
            ),
            ...?bar.actions,
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.brockmannLayout.inset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (bar.leading != null)
                bar.leading!
              else if (bar.automaticallyImplyLeading &&
                  Navigator.of(context).canPop())
                Transform.translate(
                  offset: const Offset(-12, 0),
                  child: CampusTextAction(
                    icon: Icons.arrow_back_rounded,
                    label: tr(context, 'Назад', 'Back'),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              if (bar.actions?.isNotEmpty == true)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: BrockmannButtonBar(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      children: bar.actions!,
                    ),
                  ),
                )
              else
                const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          if (title is Text && title.data != null)
            Semantics(
              header: true,
              child: BrockmannText(
                bar.preserveTitleCase ? title.data! : title.data!.toLowerCase(),
                role: BrockmannType.title,
              ),
            )
          else
            ?title,
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class CampusAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CampusAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.leadingWidth,
    this.preserveTitleCase = false,
    this.compact = false,
  });
  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;
  final double? leadingWidth;
  final bool preserveTitleCase;
  final bool compact;
  @override
  Size get preferredSize => const Size.fromHeight(64);
  @override
  Widget build(BuildContext context) => AppBar(
    title: title,
    actions: actions,
    leadingWidth: leadingWidth ?? 56,
    automaticallyImplyLeading: false,
    leading:
        leading ??
        (automaticallyImplyLeading && Navigator.of(context).canPop()
            ? CampusTextAction(
                icon: Icons.arrow_back_rounded,
                label: tr(context, 'Назад', 'Back'),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null),
  );
}
