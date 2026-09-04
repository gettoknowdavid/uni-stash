import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uni_stash_mobile/shared/widgets/auth_page_shell.dart';
import 'package:uni_stash_mobile/theme/us_typography.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('AuthPageShell', () {
    testWidgets('renders title, subtitle, description, and body', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestApp(
          child: const AuthPageShell(
            title: Text('SHELL TITLE'),
            subtitle: Text('SHELL SUBTITLE'),
            description: Text('SHELL DESCRIPTION'),
            body: Text('form content'),
          ),
        ),
      );

      expect(find.text('SHELL TITLE'), findsOneWidget);
      expect(find.text('SHELL SUBTITLE'), findsOneWidget);
      expect(find.text('SHELL DESCRIPTION'), findsOneWidget);
      expect(find.text('form content'), findsOneWidget);
    });

    testWidgets('renders footer when provided', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: const AuthPageShell(
            title: Text('SHELL TITLE'),
            body: Text('form content'),
            footer: Text('footer content'),
          ),
        ),
      );

      expect(find.text('footer content'), findsOneWidget);
      expect(find.text('form content'), findsOneWidget);
    });

    testWidgets('does not render footer when null', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: const AuthPageShell(
            title: Text('SHELL TITLE'),
            body: Text('form content'),
          ),
        ),
      );

      expect(find.text('form content'), findsOneWidget);
      expect(find.text('footer content'), findsNothing);
    });

    testWidgets('applies the brutalist box shadow decoration', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: const AuthPageShell(
            title: Text('SHELL TITLE'),
            body: Text('content'),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AuthPageShell),
              matching: find.byType(Container),
            )
            .first,
      );

      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.boxShadow, hasLength(1));
      expect(decoration.boxShadow!.single.offset, const Offset(4, 4));
      expect(decoration.boxShadow!.single.color, const Color(0xFF15140F));

      final border = decoration.border! as Border;
      expect(border.top.width, 2);
      expect(border.left.width, 2);
      expect(border.right.width, 2);
      expect(border.bottom.width, 2);
    });

    testWidgets('has correct margin and padding', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: const AuthPageShell(
            title: Text('SHELL TITLE'),
            body: Text('content'),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AuthPageShell),
              matching: find.byType(Container),
            )
            .first,
      );

      expect(container.margin, const EdgeInsets.fromLTRB(16, 0, 16, 0));
      expect(container.padding, const EdgeInsets.fromLTRB(24, 24, 24, 24));
    });

    testWidgets('styles the title with the display heading style', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestApp(
          child: const AuthPageShell(
            title: Text('SHELL TITLE'),
            body: Text('content'),
          ),
        ),
      );

      final titleStyle = DefaultTextStyle.of(
        tester.element(find.text('SHELL TITLE')),
      ).style;

      expect(titleStyle.fontFamily, UsFontFamily.display);
      expect(titleStyle.fontSize, 32);
      expect(titleStyle.fontWeight, FontWeight.w700);
      expect(titleStyle.letterSpacing, -1.6);
    });

    testWidgets('styles the subtitle with the mono label style', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestApp(
          child: const AuthPageShell(
            title: Text('SHELL TITLE'),
            subtitle: Text('SHELL SUBTITLE'),
            body: Text('content'),
          ),
        ),
      );

      final subtitleStyle = DefaultTextStyle.of(
        tester.element(find.text('SHELL SUBTITLE')),
      ).style;

      expect(subtitleStyle.fontFamily, UsFontFamily.mono);
      expect(subtitleStyle.fontSize, 12);
      expect(subtitleStyle.fontWeight, FontWeight.bold);
      expect(subtitleStyle.decoration, TextDecoration.underline);
      expect(subtitleStyle.decorationThickness, 2);
    });
  });
}
