import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ShadSpinner extends StatelessWidget {
  const ShadSpinner({
    this.height = 20,
    this.width = 20,
    this.iconSize = 24,
    super.key,
  });

  final double height;
  final double width;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: Icon(LucideIcons.loader2, size: iconSize)
          .animate(onPlay: (controller) => controller.repeat())
          .rotate(duration: 1.seconds, curve: Curves.linear),
    );
  }
}
