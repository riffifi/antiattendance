import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:brockmann/brockmann.dart';

import 'app_haptics.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'app_theme.dart';
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
    this.fitTitle = false,
  });
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool fitTitle;

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
              child: fitTitle
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                    )
                  : Text(
                      title,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
            ),
            if (trailing != null) const SizedBox(width: 12),
            ?trailing,
          ],
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: context.palette.muted),
          ),
        ],
      ],
    ),
  );
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
        constraints: const BoxConstraints(maxWidth: 640),
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
  });
  final String headline;
  final String? supportingText;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
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
                onPressed: onTap,
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
    inputFormatters: inputFormatters,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    textCapitalization: textCapitalization,
    textAlign: textAlign,
    suffixText: suffixText,
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
