import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

Widget _wrap(Widget child) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ShadTheme(
      data: usLightTheme,
      child: ShadForm(key: GlobalKey<ShadFormState>(), child: child),
    ),
  );
}

void main() {
  // Regression: flipping `enabled` on the form field (e.g. when the listing
  // editor disables the form while submitting) used to notify the controller's
  // listeners synchronously from `didUpdateWidget`, which routed into the form
  // field's `didChange` -> `setState` mid-build and crashed with
  // "setState() or markNeedsBuild() called during build".
  testWidgets('toggling enabled during a rebuild does not throw', (
    tester,
  ) async {
    var enabled = true;
    late StateSetter setOuterState;

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) {
            setOuterState = setState;
            return ShadButtonGroupFormField<Condition>(
              id: 'condition',
              options: Condition.values,
              initialValue: Condition.isNew,
              enabled: enabled,
            );
          },
        ),
      ),
    );
    await tester.pump();

    // The submit flow flips `enabled: !isSubmitting` while the tree rebuilds.
    setOuterState(() => enabled = false);
    await tester.pump();

    setOuterState(() => enabled = true);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('user taps still report the selected value to the form', (
    tester,
  ) async {
    final formKey = GlobalKey<ShadFormState>();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ShadTheme(
          data: usLightTheme,
          child: ShadForm(
            key: formKey,
            child: ShadButtonGroupFormField<Condition>(
              id: 'condition',
              options: Condition.values,
              initialValue: Condition.isNew,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(formKey.currentState!.value['condition'], Condition.isNew);

    // The item builder defaults to a Text of the enum's toString().
    await tester.tap(find.text('Condition.used'));
    await tester.pump();

    expect(formKey.currentState!.value['condition'], Condition.used);
  });
}
