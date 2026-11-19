import 'package:flutter/material.dart';

/// Keeps track changes away from sliders, zooming and vertical scrolling.
class SwipeToChange extends StatefulWidget {
  const SwipeToChange({
    super.key,
    required this.child,
    required this.onNext,
    required this.onPrevious,
    this.enabled = true,
  });
  final Widget child;
  final VoidCallback onNext, onPrevious;
  final bool enabled;

  @override
  State<SwipeToChange> createState() => _SwipeToChangeState();
}

class _SwipeToChangeState extends State<SwipeToChange> {
  double distance = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onHorizontalDragStart: widget.enabled ? (_) => distance = 0 : null,
    onHorizontalDragUpdate: widget.enabled
        ? (event) => distance += event.delta.dx
        : null,
    onHorizontalDragEnd: widget.enabled
        ? (event) {
            final velocity = event.primaryVelocity ?? 0;
            if (distance.abs() < 54 && velocity.abs() < 450) return;
            final direction = distance.abs() >= 54 ? distance : velocity;
            final next = Directionality.of(context) == TextDirection.rtl
                ? direction > 0
                : direction < 0;
            if (next) {
              widget.onNext();
            } else {
              widget.onPrevious();
            }
            distance = 0;
          }
        : null,
    onHorizontalDragCancel: widget.enabled ? () => distance = 0 : null,
    child: widget.child,
  );
}
