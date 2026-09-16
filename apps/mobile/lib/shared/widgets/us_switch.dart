import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// A brutalist box-style switch that matches the UniStash design system.
///
/// Unlike the default pill-shaped switch, this uses a rectangular box
/// with a thin border and a simple square thumb.
///
/// Colors are derived from [ShadSwitchTheme] and [ShadColorScheme],
/// so switching between light/dark themes will work automatically.
///
/// ```dart
/// UsSwitch(
///   value: isOn,
///   onChanged: (v) => setState(() => isOn = v),
/// )
/// ```
class UsSwitch extends StatelessWidget {
  const UsSwitch({
    required this.value,
    this.onChanged,
    this.enabled = true,
    this.height = 20,
    this.width = 34,
    this.border,
    this.showBorder = true,
    super.key,
  });

  /// Whether the switch is currently on.
  final bool value;

  /// Called when the user taps the switch. Null disables interaction.
  final ValueChanged<bool>? onChanged;

  /// Whether the switch is enabled (not disabled/busy).
  final bool enabled;

  /// Total height of the switch track.
  final double height;

  /// Total width of the switch track.
  final double width;

  /// Border for the track.
  ///
  /// Defaults to a 1px border using the theme's borderStrong color.
  final BorderSide? border;

  /// Whether to show the border around the track.
  final bool showBorder;

  bool get _interactive => onChanged != null && enabled;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final borderSide =
        border ?? BorderSide(color: theme.colorScheme.borderStrong, width: 1.5);
    final thumbInset = borderSide.width;
    final thumbSize = height - thumbInset * 4;

    return GestureDetector(
      onTap: _interactive ? () => onChanged!(!value) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: value
              ? theme.switchTheme.checkedTrackColor
              : theme.switchTheme.uncheckedTrackColor,
          border: showBorder
              ? Border.all(width: borderSide.width, color: borderSide.color)
              : null,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? .centerRight : .centerLeft,
          child: Container(
            margin: .all(thumbInset * 2),
            width: thumbSize,
            height: thumbSize,
            color: theme.switchTheme.thumbColor,
          ),
        ),
      ),
    );
  }
}
