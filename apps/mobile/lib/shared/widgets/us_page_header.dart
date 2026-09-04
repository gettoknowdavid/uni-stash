import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

const double kUsPageHeaderHeight = 56;

/// ---------------------------------------------------------------------
/// UsPageHeader
/// ---------------------------------------------------------------------
/// A stateless header widget: bottom hairline border, themed background,
/// and slots for leading/title/actions. Shows a back button automatically
/// when the route can be popped, unless [leading] or
/// [automaticallyImplyLeading] says otherwise — mirroring Material's
/// `AppBar` default behavior.
class UsPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const UsPageHeader({
    super.key,
    this.title,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.actions = const [],
    this.centerTitle = false,
    this.height = kUsPageHeaderHeight,
    this.border = false,
    this.backgroundColor,
    this.padding = const .symmetric(horizontal: 16),
    this.onBack,
  });

  /// Usually a [Text] widget. Styled with `ShadTheme.textTheme.h4` if it's
  /// a plain Text and no explicit style was set.
  final Widget? title;

  /// Explicit leading widget. If null and [automaticallyImplyLeading] is
  /// true and the current route can be popped, a back button is shown.
  final Widget? leading;

  /// If true (default) and [leading] is null, shows a back button when
  /// `Navigator.canPop(context)` is true.
  final bool automaticallyImplyLeading;

  /// Trailing row of icon buttons / menus.
  final List<Widget> actions;

  /// Whether to center the title horizontally.
  final bool centerTitle;

  /// The height of the app bar.
  final double height;

  /// Whether to draw the bottom hairline border.
  final bool border;

  /// The background color of the app bar.
  final Color? backgroundColor;

  /// The padding of the app bar.
  final EdgeInsetsGeometry padding;

  /// Called when the back button is tapped, instead of the default
  /// `Navigator.pop(context)`.
  final VoidCallback? onBack;

  @override
  Size get preferredSize => Size.fromHeight(height);

  Widget? _resolveLeading(BuildContext context) {
    if (leading != null) return leading;
    if (!automaticallyImplyLeading) return null;
    if (!Navigator.canPop(context)) return null;
    return const UsBackButton();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final resolvedLeading = _resolveLeading(context);

    var titleWidget = title ?? const SizedBox.shrink();
    if (title is Text) {
      titleWidget = DefaultTextStyle.merge(
        style: theme.textTheme.h4,
        child: title! as Text,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.background,
        border: border
            ? Border(bottom: BorderSide(color: theme.colorScheme.border))
            : null,
      ),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              if (resolvedLeading != null) ...[
                resolvedLeading,
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Align(
                  alignment: centerTitle ? .center : .centerLeft,
                  child: titleWidget,
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: .min,
                  children: _withGaps(actions, 4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

List<Widget> _withGaps(List<Widget> children, double gap) {
  final result = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    if (i > 0) result.add(SizedBox(width: gap));
    result.add(children[i]);
  }
  return result;
}
