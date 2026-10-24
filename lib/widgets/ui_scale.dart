import 'package:flutter/material.dart';

/// How much the whole interface is shrunk: the compact size.
const double kUiScale = 0.9;

/// Draws the whole interface at [kUiScale].
///
/// The app is laid out as if the screen were `1 / scale` times larger and then
/// drawn scaled down to fit, so text, icons and spacing all shrink together,
/// like lowering the phone's display size. Touch input maps through the same
/// transform, and the keyboard / system-bar insets are scaled to match.
class UiScale extends StatelessWidget {
  final Widget child;
  const UiScale({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    const scale = kUiScale;
    final mq = MediaQuery.of(context);
    final size = mq.size / scale;
    return MediaQuery(
      data: mq.copyWith(
        size: size,
        padding: mq.padding / scale,
        viewPadding: mq.viewPadding / scale,
        viewInsets: mq.viewInsets / scale,
        systemGestureInsets: mq.systemGestureInsets / scale,
      ),
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: size.width,
        maxWidth: size.width,
        minHeight: size.height,
        maxHeight: size.height,
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(size: size, child: child),
        ),
      ),
    );
  }
}
