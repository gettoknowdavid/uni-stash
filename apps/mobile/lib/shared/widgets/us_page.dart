import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// ---------------------------------------------------------------------
/// UsPage
/// ---------------------------------------------------------------------
/// Pure structural layout: app bar on top, body filling the remaining
/// space, optional bottom bar, optional floating action button. No drawer,
/// no messenger, no inherited controller — just page shape.
class UsPage extends StatelessWidget {
  const UsPage({
    super.key,
    this.body,
    this.header,
    this.footer,
    this.floatingActionButton,
    this.floatingActionButtonAlignment = .bottomRight,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
    this.safeArea = true,
    this.gutters = const .symmetric(horizontal: 16),
  });

  /// The app bar to display at the top of the scaffold.
  final PreferredSizeWidget? header;

  /// The body of the scaffold.
  final Widget? body;

  /// Sits below [body], above the bottom safe area (e.g. a bottom nav bar
  /// or an action button row).
  final Widget? footer;

  /// The floating action button to display at the bottom of the scaffold.
  final Widget? floatingActionButton;

  /// The alignment of the floating action button.
  final Alignment floatingActionButtonAlignment;

  /// The background color of the scaffold.
  final Color? backgroundColor;

  /// If true, body shrinks when the keyboard opens.
  final bool resizeToAvoidBottomInset;

  /// If true, the scaffold is wrapped in a [SafeArea].
  final bool safeArea;

  /// The gutters (padding) to apply to the scaffold.
  final EdgeInsets gutters;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final bg = backgroundColor ?? theme.colorScheme.background;
    final bottomInset = resizeToAvoidBottomInset
        ? MediaQuery.of(context).viewInsets.bottom
        : 0.0;

    Widget content = Column(
      children: [
        ?header,
        Expanded(
          child: Padding(
            padding: gutters,
            child: body ?? const SizedBox.shrink(),
          ),
        ),
        ?footer,
      ],
    );

    if (safeArea) content = SafeArea(child: content);

    return DecoratedBox(
      decoration: BoxDecoration(color: bg),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: .only(bottom: bottomInset),
        child: Stack(
          children: [
            Positioned.fill(child: content),
            if (floatingActionButton != null)
              Positioned.fill(
                child: Align(
                  alignment: floatingActionButtonAlignment,
                  child: Padding(
                    padding: const .all(16),
                    child: floatingActionButton,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
