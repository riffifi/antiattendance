import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_theme.dart';
import 'l10n.dart';
import 'editorial_controls.dart';
import 'icons/campus_icon.dart';
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
  const CampusPageBody({super.key, required this.child, this.maxWidth = 640});
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
  });
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            const SizedBox(width: 12),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: context.palette.muted),
        ),
      ],
    ),
  );
}

/// Fast local feedback; dragging a scroll view cancels the pressed state.
class CampusPressable extends StatefulWidget {
  const CampusPressable({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<CampusPressable> createState() => _CampusPressableState();
}

class _CampusPressableState extends State<CampusPressable> {
  Offset? _origin;
  bool _pressed = false;
  void _release() {
    _origin = null;
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  void didUpdateWidget(CampusPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _pressed = false;
      _origin = null;
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: widget.enabled
        ? (event) {
            _origin = event.position;
            setState(() => _pressed = true);
          }
        : null,
    onPointerMove: (event) {
      if (_origin != null && (event.position - _origin!).distance > 8) {
        _release();
      }
    },
    onPointerUp: (_) => _release(),
    onPointerCancel: (_) => _release(),
    child: AnimatedScale(
      scale: _pressed ? .975 : 1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Duration(milliseconds: _pressed ? 80 : 150),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}

class CampusPanel extends StatelessWidget {
  const CampusPanel({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final Color? color;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    foregroundDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: context.palette.line, width: .5),
        bottom: BorderSide(color: context.palette.line, width: .5),
      ),
    ),
    child: Material(
      color: color ?? context.palette.paper,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class CampusSectionTitle extends StatelessWidget {
  const CampusSectionTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(letterSpacing: 1.2),
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
  Widget build(BuildContext context) {
    return EditorialAction(
      onPressed: onPressed,
      filled:
          style == CampusButtonStyle.filled || style == CampusButtonStyle.tonal,
      outlined: style == CampusButtonStyle.outlined,
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: DefaultTextStyle.merge(
          textAlign: TextAlign.center,
          child: child,
        ),
      ),
    );
  }
}

class CampusNavigation extends StatefulWidget {
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
  State<CampusNavigation> createState() => _CampusNavigationState();
}

class _CampusNavigationState extends State<CampusNavigation> {
  double? _dragPosition;
  void _track(double x, double width) => setState(() {
    _dragPosition = (x / (width / widget.labels.length) - .5).clamp(
      0.0,
      widget.labels.length - 1.0,
    );
  });
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ClipRRect(
            borderRadius: BorderRadius.zero,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.palette.paper,
                borderRadius: BorderRadius.zero,
                border: Border.all(
                  color: context.palette.line.withValues(alpha: .65),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: LayoutBuilder(
                    builder: (context, constraints) => GestureDetector(
                      onHorizontalDragStart: (details) => _track(
                        details.localPosition.dx,
                        constraints.maxWidth,
                      ),
                      onHorizontalDragUpdate: (details) => _track(
                        details.localPosition.dx,
                        constraints.maxWidth,
                      ),
                      onHorizontalDragCancel: () =>
                          setState(() => _dragPosition = null),
                      onHorizontalDragEnd: (_) {
                        final index =
                            (_dragPosition ?? widget.selectedIndex.toDouble())
                                .round();
                        setState(() => _dragPosition = null);
                        widget.onDestinationSelected(index);
                      },
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(
                                end:
                                    _dragPosition ??
                                    widget.selectedIndex.toDouble(),
                              ),
                              duration:
                                  _dragPosition != null ||
                                      MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              builder: (context, position, child) => Align(
                                alignment: Alignment(
                                  -1 +
                                      2 * position / (widget.labels.length - 1),
                                  0,
                                ),
                                child: FractionallySizedBox(
                                  widthFactor: 1 / widget.labels.length,
                                  heightFactor: 1,
                                  child: child,
                                ),
                              ),
                              child: DecoratedBox(
                                key: const ValueKey('navigation-pill'),
                                decoration: BoxDecoration(
                                  color: context.palette.selectionSurface,
                                  borderRadius: BorderRadius.zero,
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              for (
                                var index = 0;
                                index < widget.labels.length;
                                index++
                              )
                                Expanded(
                                  child: Semantics(
                                    selected: widget.selectedIndex == index,
                                    button: true,
                                    child: InkWell(
                                      borderRadius: BorderRadius.zero,
                                      onTap: () =>
                                          widget.onDestinationSelected(index),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 8,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              widget.labels[index],
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    widget.selectedIndex ==
                                                        index
                                                    ? context.palette.ink
                                                    : context.palette.muted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
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
  });
  final String headline;
  final String? supportingText;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Semantics(
      selected: selected,
      child: Column(
        children: [
          EditorialAction(
            onPressed: onTap,
            invertOnInteraction: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (supportingText != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          supportingText!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.palette.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: bounds.maxWidth * .42,
                    ),
                    child: trailing!,
                  ),
                ],
                if (trailing == null && selected) ...[
                  const SizedBox(width: 8),
                  const CampusIcon(Icons.check_rounded, size: 18),
                ],
              ],
            ),
          ),
          Divider(height: .5, thickness: .5, color: context.palette.line),
        ],
      ),
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
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.textCapitalization = TextCapitalization.none,
    this.textAlign = TextAlign.start,
    this.suffixText,
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
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization textCapitalization;
  final TextAlign textAlign;
  final String? suffixText;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (label != null)
        Text(label!, style: Theme.of(context).textTheme.labelMedium),
      if (label != null) const SizedBox(height: 6),
      TextField(
        controller: controller,
        autofocus: autofocus,
        obscureText: obscureText,
        enabled: enabled,
        maxLength: maxLength,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textCapitalization: textCapitalization,
        textAlign: textAlign,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: placeholder,
          border: UnderlineInputBorder(
            borderSide: BorderSide(color: context.palette.line, width: .5),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.palette.line, width: .5),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.palette.ink),
          ),
          prefixIcon: leading,
          suffixIcon: trailing,
          suffixText: suffixText,
        ),
      ),
    ],
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

class CampusAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CampusAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.leadingWidth,
  });
  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;
  final double? leadingWidth;
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
