import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class UsBackButton extends StatelessWidget {
  const UsBackButton({this.size = 40, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return SizedBox.square(
      dimension: size,
      child: ShadIconButton(
        backgroundColor: theme.colorScheme.accent,
        foregroundColor: theme.colorScheme.foreground,
        hoverBackgroundColor: theme.colorScheme.muted,
        pressedBackgroundColor: theme.colorScheme.foreground,
        pressedForegroundColor: theme.colorScheme.accent,
        decoration: ShadDecoration(
          border: ShadBorder.all(
            color: theme.colorScheme.foreground,
            width: 2,
            radius: .zero,
          ),
        ),
        onPressed: () => ModalRoute.canPopOf(context) == true
            ? Navigator.maybePop(context)
            : null,
        icon: Icon(LucideIcons.chevronLeft, size: size * 0.7),
      ),
    );
  }
}
