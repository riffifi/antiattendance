import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import 'app_theme.dart';

// Custom design built on material 3 expressive
class CampusHeader extends StatelessWidget {
  const CampusHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
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
          style: TextStyle(
            color: context.palette.muted,
            fontSize: 14,
            height: 1.5,
          ),
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
  Widget build(BuildContext context) => Material(
    color: color ?? context.palette.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: context.palette.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class CampusSectionTitle extends StatelessWidget {
  const CampusSectionTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );
}

class CampusButton extends StatelessWidget {
  const CampusButton.filled({
    super.key,
    required this.onPressed,
    required this.child,
  }) : icon = null,
       style = M3EButtonStyle.filled;
  const CampusButton.text({
    super.key,
    required this.onPressed,
    required this.child,
  }) : icon = null,
       style = M3EButtonStyle.text;
  const CampusButton.icon({
    super.key,
    required this.onPressed,
    required Widget label,
    required this.icon,
    this.style = M3EButtonStyle.filled,
  }) : child = label;
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final M3EButtonStyle style;

  @override
  Widget build(BuildContext context) {
    final content = icon == null
        ? child
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon!,
              const SizedBox(width: 9),
              Flexible(child: child),
            ],
          );
    return CampusPressable(
      enabled: onPressed != null,
      child: switch (style) {
        M3EButtonStyle.text => ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * .48,
          ),
          child: TextButton(onPressed: onPressed, child: content),
        ),
        M3EButtonStyle.outlined => OutlinedButton(
          onPressed: onPressed,
          child: content,
        ),
        _ => FilledButton(onPressed: onPressed, child: content),
      },
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
  static const icons = [
    Icons.qr_code_scanner_rounded,
    Icons.calendar_today_outlined,
    Icons.nfc_rounded,
  ];
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.palette.surface.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(24),
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
                                        2 *
                                            position /
                                            (widget.labels.length - 1),
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
                                    color: context.palette.selected.withValues(
                                      alpha: .9,
                                    ),
                                    borderRadius: BorderRadius.circular(19),
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
                                        borderRadius: BorderRadius.circular(19),
                                        onTap: () =>
                                            widget.onDestinationSelected(index),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 12,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                CampusNavigation.icons[index],
                                                size: 22,
                                                color:
                                                    widget.selectedIndex ==
                                                        index
                                                    ? context.palette.blue
                                                    : context.palette.muted,
                                              ),
                                              const SizedBox(height: 5),
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
    this.expanded,
  });
  final String headline;
  final String? supportingText;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final M3EExpandableExpanded? expanded;
  @override
  Widget build(BuildContext context) {
    if (expanded != null) {
      return ExpansionTile(
        title: Text(headline),
        leading: leading,
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        children: [expanded!.child],
      );
    }
    return CampusPressable(
      enabled: onTap != null,
      child: ListTile(
        title: Text(
          headline,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -.2,
          ),
        ),
        subtitle: supportingText == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  supportingText!,
                  style: TextStyle(
                    color: context.palette.muted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ),
        leading: leading == null
            ? null
            : Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.palette.paper,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: leading,
              ),
        trailing: trailing,
        onTap: onTap,
        selected: selected,
        selectedColor: context.palette.ink,
      ),
    );
  }
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
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    enabled: enabled,
    maxLength: maxLength,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    textCapitalization: textCapitalization,
    textAlign: textAlign,
    decoration: InputDecoration(
      labelText: label,
      hintText: placeholder,
      prefixIcon: leading,
      suffixIcon: trailing,
      suffixText: suffixText,
    ),
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
