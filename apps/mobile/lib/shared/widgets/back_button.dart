import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class UsBackButton extends StatelessWidget {
  const UsBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return SizedBox.square(
      dimension: 40,
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
        onPressed: () => ModalRoute.of(context)?.canPop == true
            ? Navigator.pop(context)
            : null,
        icon: const Icon(LucideIcons.chevronLeft),
      ),
    );
  }
}
