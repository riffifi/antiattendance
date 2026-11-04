import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The route title can scroll independently at large text sizes. Exercise the
/// feature's content, rather than accidentally scrolling its title or pivot.
Finder bodyScroll() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .last;
