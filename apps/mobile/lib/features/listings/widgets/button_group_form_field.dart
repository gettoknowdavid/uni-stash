// The controller's enabled setter is a trivial private-field write by design
// (see the doc comment on ShadButtonGroupController.enabled).
// ignore_for_file: unnecessary_getters_setters

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Signature for building the button that represents one option of a
/// [ShadButtonGroup].
typedef ShadButtonGroupItemBuilder<T> = Widget Function(
  BuildContext context, {
  required T value,
  required bool isSelected,
  required VoidCallback? onPressed,
  required ShadThemeData theme,
});

/// Controller for a single-selection [ShadButtonGroup].
class ShadButtonGroupController<T> extends ValueNotifier<T?> {
  ShadButtonGroupController({T? value, bool enabled = true})
    : _enabled = enabled,
      super(value);

  bool _enabled;
  bool get enabled => _enabled;

  /// Toggling enabled-ness intentionally does NOT notify listeners: option
  /// buttons read `enabled` from the widget tree on every parent rebuild.
  /// Notifying here fires the state's `_handleChanged` (and therefore the
  /// wrapping form field's `didChange` -> `setState`) synchronously from
  /// `didUpdateWidget`, which crashes with "setState() called during build"
  /// whenever `enabled` flips while the form is rebuilding (e.g. when the
  /// editor disables the form on submit).
  set enabled(bool value) {
    _enabled = value;
  }
}

/// Controller for a multiple-selection [ShadButtonGroup].
class ShadButtonGroupMultiController<T> extends ValueNotifier<Set<T>> {
  ShadButtonGroupMultiController({
    Set<T>? value,
    bool enabled = true,
    this.allowDeselection = true,
    this.maxSelections,
  }) : _enabled = enabled,
       super(value ?? <T>{});

  bool _enabled;
  bool get enabled => _enabled;

  /// See [ShadButtonGroupController.enabled] for why this does not notify.
  set enabled(bool value) {
    _enabled = value;
  }

  /// Whether tapping a selected option deselects it.
  bool allowDeselection;

  /// Maximum number of options that can be selected at once.
  int? maxSelections;
}

/// A group of buttons that behaves like a radio group.
///
/// By default only one option can be selected at a time (radio-like). Use
/// [ShadButtonGroup.multiple] to allow selecting several options at once.
class ShadButtonGroup<T> extends StatefulWidget {
  const ShadButtonGroup({
    required this.options,
    super.key,
    this.itemBuilder,
    this.initialValue,
    this.onChanged,
    this.enabled = true,
    this.spacing = 8,
    this.expand = true,
  }) : _multiple = false,
       allowDeselection = true,
       maxSelections = null;

  const ShadButtonGroup.multiple({
    required this.options,
    super.key,
    this.itemBuilder,
    this.initialValue,
    this.onChanged,
    this.enabled = true,
    this.spacing = 8,
    this.expand = true,
    this.allowDeselection = true,
    this.maxSelections,
  }) : _multiple = true;

  /// The selectable values, in display order.
  final List<T> options;

  /// Builds the button for each option. Defaults to a compact
  /// [ShadButton.outline] pill that highlights the selected option.
  final ShadButtonGroupItemBuilder<T>? itemBuilder;

  /// Single mode: the initially selected value (`T?`).
  /// Multiple mode: the initially selected values (`Set<T>`).
  final Object? initialValue;

  /// Single mode: a `ValueChanged<T?>` callback. Multiple mode: a
  /// `ValueChanged<Set<T>>` callback.
  final Object? onChanged;

  /// Whether the buttons are interactive.
  final bool enabled;

  /// Gap between the option buttons.
  final double spacing;

  /// Whether each option expands to share the row width equally.
  final bool expand;

  final bool _multiple;

  /// Whether tapping a selected option deselects it (multiple mode only).
  final bool allowDeselection;

  /// Maximum number of selectable options (multiple mode only).
  final int? maxSelections;

  @override
  State<ShadButtonGroup<T>> createState() => ShadButtonGroupState<T>();
}

class ShadButtonGroupState<T> extends State<ShadButtonGroup<T>> {
  ShadButtonGroupController<T>? _single;
  ShadButtonGroupMultiController<T>? _multi;

  /// Whether [didUpdateWidget] is currently syncing the controller from the
  /// widget config. Listener notifications fired during that sync are
  /// parent-driven (not user interaction) and would call `setState` on the
  /// wrapping form field while the build cascade is still descending through
  /// its subtree — an illegal "setState during build".
  bool _syncingFromWidget = false;

  bool get _isMultiple => widget._multiple;

  ValueListenable<Object?> get _listenable {
    if (_isMultiple) return _multi!;
    return _single!;
  }

  Set<T> get _initialMultiValue => (widget.initialValue as Set<T>?) ?? <T>{};

  @override
  void initState() {
    super.initState();
    if (_isMultiple) {
      _multi = ShadButtonGroupMultiController<T>(
        value: _initialMultiValue,
        enabled: widget.enabled,
        allowDeselection: widget.allowDeselection,
        maxSelections: widget.maxSelections,
      )..addListener(_handleChanged);
    } else {
      _single = ShadButtonGroupController<T>(
        value: widget.initialValue as T?,
        enabled: widget.enabled,
      )..addListener(_handleChanged);
    }
  }

  @override
  void didUpdateWidget(covariant ShadButtonGroup<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncingFromWidget = true;
    try {
      if (_isMultiple) {
        final multi = _multi!;
        final initial = _initialMultiValue;
        final same =
            multi.value.length == initial.length &&
            multi.value.containsAll(initial);
        if (!same) multi.value = initial;
        multi
          ..enabled = widget.enabled
          ..allowDeselection = widget.allowDeselection
          ..maxSelections = widget.maxSelections;
      } else {
        final single = _single!;
        if (single.value != widget.initialValue) {
          single.value = widget.initialValue as T?;
        }
        single.enabled = widget.enabled;
      }
    } finally {
      _syncingFromWidget = false;
    }
  }

  @override
  void dispose() {
    _single?.removeListener(_handleChanged);
    _single?.dispose();
    _multi?.removeListener(_handleChanged);
    _multi?.dispose();
    super.dispose();
  }

  void _handleChanged() {
    // Parent-driven syncs (value/enabled reconciliation in didUpdateWidget)
    // must not synchronously push changes into a wrapping form field: the
    // field would call setState mid-build. Value syncs still notify the
    // option items (they listen to the controller directly), so the UI stays
    // consistent.
    if (_syncingFromWidget) return;
    if (_isMultiple) {
      (widget.onChanged as ValueChanged<Set<T>>?)?.call(_multi!.value);
    } else {
      (widget.onChanged as ValueChanged<T?>?)?.call(_single!.value);
    }
  }

  void _select(T option) {
    if (!_isMultiple) {
      _single!.value = option;
      return;
    }
    final multi = _multi!;
    final next = Set<T>.of(multi.value);
    if (next.contains(option)) {
      if (!multi.allowDeselection) return;
      next.remove(option);
    } else {
      final max = multi.maxSelections;
      if (max != null && next.length >= max) return;
      next.add(option);
    }
    multi.value = next;
  }

  @override
  Widget build(BuildContext context) {
    final builder = widget.itemBuilder ?? defaultItemBuilder<T>;
    return Row(
      spacing: widget.spacing,
      children: [
        for (final option in widget.options) _buildItem(builder, option),
      ],
    );
  }

  Widget _buildItem(ShadButtonGroupItemBuilder<T> builder, T option) {
    final item = _ShadButtonGroupItem<T>(
      listenable: _listenable,
      value: option,
      enabled: widget.enabled,
      onPressed: () => _select(option),
      builder: builder,
    );
    if (widget.expand) return Expanded(child: item);
    return item;
  }

  /// Default option button: a compact outline pill that highlights the
  /// selected option, matching the listing editor's condition selector.
  static Widget defaultItemBuilder<T>(
    BuildContext context, {
    required T value,
    required bool isSelected,
    required VoidCallback? onPressed,
    required ShadThemeData theme,
  }) {
    return ShadButton.outline(
      height: 32,
      onPressed: onPressed,
      foregroundColor: isSelected
          ? theme.colorScheme.foreground
          : theme.colorScheme.mutedForeground,
      textStyle: theme.textTheme.small.copyWith(
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        letterSpacing: 0.5,
      ),
      padding: .zero,
      child: Text(value.toString()),
    );
  }
}

class _ShadButtonGroupItem<T> extends StatelessWidget {
  const _ShadButtonGroupItem({
    required this.listenable,
    required this.value,
    required this.enabled,
    required this.onPressed,
    required this.builder,
  });

  final ValueListenable<Object?> listenable;
  final T value;
  final bool enabled;
  final VoidCallback onPressed;
  final ShadButtonGroupItemBuilder<T> builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Object?>(
      valueListenable: listenable,
      builder: (context, current, _) {
        final theme = ShadTheme.of(context);
        final isSelected = current == value;
        return builder(
          context,
          value: value,
          isSelected: isSelected,
          onPressed: enabled ? onPressed : null,
          theme: theme,
        );
      },
    );
  }
}

/// A [ShadForm] form field wrapping a single-selection [ShadButtonGroup].
///
/// The form value is the selected option, or null when nothing is selected.
class ShadButtonGroupFormField<T> extends ShadFormBuilderField<T?> {
  ShadButtonGroupFormField({
    required List<T> options,
    super.key,
    ShadButtonGroupItemBuilder<T>? itemBuilder,
    super.id,
    super.label,
    super.description,
    super.initialValue,
    super.validator,
    super.autovalidateMode,
    super.onSaved,
    super.enabled = true,
    this.spacing = 8,
  }) : _options = options,
       _itemBuilder = itemBuilder,
       super(
         builder: (state) {
           final fieldState =
               state as ShadFormBuilderFieldState<ShadFormBuilderField<T?>, T?>;
           return ShadButtonGroup<T>(
             options: options,
             itemBuilder: itemBuilder,
             initialValue: fieldState.value ?? fieldState.initialValue,
             onChanged: fieldState.didChange,
             enabled: fieldState.enabled,
             spacing: spacing,
           );
         },
       );

  final List<T> _options;
  final ShadButtonGroupItemBuilder<T>? _itemBuilder;

  /// Gap between the option buttons.
  final double spacing;
}

/// Default validator for [ShadButtonGroupMultiFormField]: enforces the
/// minimum and maximum number of selected options.
String? _defaultMultiValidator<T>(
  List<T>? value, {
  required int minSelections,
  required int? maxSelections,
}) {
  final count = value?.length ?? 0;
  if (count < minSelections) {
    return 'Please select at least $minSelections.';
  }
  if (maxSelections != null && count > maxSelections) {
    return 'You can select up to $maxSelections.';
  }
  return null;
}

/// A [ShadForm] form field wrapping a multiple-selection [ShadButtonGroup].
///
/// The form value is the `List<T>` of selected options (may be empty).
class ShadButtonGroupMultiFormField<T> extends ShadFormBuilderField<List<T>> {
  ShadButtonGroupMultiFormField({
    required List<T> options,
    super.key,
    ShadButtonGroupItemBuilder<T>? itemBuilder,
    super.id,
    super.label,
    super.description,
    super.initialValue,
    FormFieldValidator<List<T>>? validator,
    super.autovalidateMode,
    super.onSaved,
    super.enabled = true,
    this.spacing = 8,
    this.allowDeselection = true,
    this.maxSelections,
    this.minSelections = 0,
  }) : super(
         validator:
             validator ??
             (value) => _defaultMultiValidator<T>(
               value,
               minSelections: minSelections,
               maxSelections: maxSelections,
             ),
         builder: (state) {
           final fieldState =
               state
                   as ShadFormBuilderFieldState<
                     ShadFormBuilderField<List<T>>,
                     List<T>
                   >;
           return ShadButtonGroup<T>.multiple(
             options: options,
             itemBuilder: itemBuilder,
             initialValue: Set<T>.of(
               fieldState.value ?? fieldState.initialValue ?? <T>[],
             ),
             onChanged: (Set<T> values) =>
                 fieldState.didChange(values.toList()),
             enabled: fieldState.enabled,
             spacing: spacing,
             allowDeselection: allowDeselection,
             maxSelections: maxSelections,
           );
         },
       );

  /// Gap between the option buttons.
  final double spacing;

  /// Whether tapping a selected option deselects it.
  final bool allowDeselection;

  /// Maximum number of selectable options.
  final int? maxSelections;

  /// Minimum number of options that must be selected.
  final int minSelections;
}
