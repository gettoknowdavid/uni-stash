import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_stash_mobile/shared/widgets/spinner.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('ShadSpinner', () {
    testWidgets('keeps rotating after the first full turn', (tester) async {
      await tester.pumpWidget(
        buildTestApp(child: const ShadSpinner()),
      );

      // Snapshot the rotation matrix applied by the animate()/rotate() chain.
      List<double> rotationMatrix() {
        final transform = tester.widget<Transform>(
          find
              .descendant(
                of: find.byType(ShadSpinner),
                matching: find.byType(Transform),
              )
              .first,
        );
        return transform.transform.storage.toList();
      }

      // Midway through the first turn the spinner must be rotating.
      await tester.pump(const Duration(milliseconds: 300));
      final midFirstTurn = rotationMatrix();

      // Both samples below are past the 1s single-spin window. A one-shot
      // animation would be frozen (identical matrices); a looping one keeps
      // changing the angle between the two samples.
      await tester.pump(const Duration(milliseconds: 900));
      final justAfterFirstTurn = rotationMatrix();
      await tester.pump(const Duration(milliseconds: 200));
      final laterInSecondTurn = rotationMatrix();

      expect(
        midFirstTurn,
        isNot(equals(justAfterFirstTurn)),
        reason: 'spinner should be rotating during its first turn',
      );
      expect(
        justAfterFirstTurn,
        isNot(equals(laterInSecondTurn)),
        reason: 'spinner should keep rotating past one full turn',
      );
    });
  });
}
