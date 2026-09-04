// import 'package:flutter/material.dart';
// import 'package:flutter_test/flutter_test.dart';
// import 'package:uni_stash_mobile/shared/widgets/auth_page_shell.dart';

// import '../../helpers/test_helpers.dart';

// void main() {
//   group('AuthPageShell', () {
//     testWidgets('renders title and subtitle', (tester) async {
//       await tester.pumpWidget(
//         buildTestApp(
//           child: const AuthPageShell(
//             title: 'SHELL TITLE',
//             body: Text('form content'),
//           ),
//         ),
//       );

//       expect(find.text('UNI·STASH'), findsOneWidget);
//       expect(find.text('Campus Bulletin Board'), findsOneWidget);
//       expect(find.text('form content'), findsOneWidget);
//     });

//     testWidgets('renders child widget', (tester) async {
//       await tester.pumpWidget(
//         buildTestApp(
//           child: const AuthPageShell(
//             title: 'SHELL TITLE',
//             body: Text('custom child'),
//           ),
//         ),
//       );

//       expect(find.text('custom child'), findsOneWidget);
//     });

//     testWidgets('renders footer when provided', (tester) async {
//       await tester.pumpWidget(
//         buildTestApp(
//           child: const AuthPageShell(
//             title: 'SHELL TITLE',
//             body: Text('form content'),
//             footer: Text('footer content'),
//           ),
//         ),
//       );

//       expect(find.text('footer content'), findsOneWidget);
//       expect(find.text('form content'), findsOneWidget);
//     });

//     testWidgets('does not render footer when null', (tester) async {
//       await tester.pumpWidget(
//         buildTestApp(
//           child: const AuthPageShell(
//             title: 'SHELL TITLE',
//             body: Text('form content'),
//           ),
//         ),
//       );

//       expect(find.text('form content'), findsOneWidget);
//       // No footer widget should be present
//       expect(find.byType(AuthPageShell), findsOneWidget);
//     });

//     testWidgets('applies brutalist box shadow decoration', (tester) async {
//       await tester.pumpWidget(
//         buildTestApp(
//           child: const AuthPageShell(
//             title: 'SHELL TITLE',
//             body: Text('content'),
//           ),
//         ),
//       );

//       final container = tester.widget<Container>(
//         find
//             .descendant(
//               of: find.byType(AuthPageShell),
//               matching: find.byType(Container),
//             )
//             .first,
//       );

//       final decoration = container.decoration as BoxDecoration?;
//       expect(decoration, isNotNull);
//       expect(decoration!.boxShadow, isNotNull);
//       expect(decoration.boxShadow!.length, 1);
//     });

//     testWidgets('has correct margin and padding', (tester) async {
//       await tester.pumpWidget(
//         buildTestApp(
//           child: const AuthPageShell(
//             title: 'SHELL TITLE',
//             body: Text('content'),
//           ),
//         ),
//       );

//       final container = tester.widget<Container>(
//         find
//             .descendant(
//               of: find.byType(AuthPageShell),
//               matching: find.byType(Container),
//             )
//             .first,
//       );

//       expect(container.margin, const EdgeInsets.fromLTRB(16, 0, 16, 0));
//       expect(container.padding, const EdgeInsets.fromLTRB(24, 24, 24, 24));
//     });

//     testWidgets('renders title with correct text styling', (tester) async {
//       await tester.pumpWidget(
//         buildTestApp(
//           child: const AuthPageShell(
//             title: 'SHELL TITLE',
//             body: Text('content'),
//           ),
//         ),
//       );

//       final titleWidget = tester.widget<Text>(find.text('UNI·STASH'));
//       final style = titleWidget.style;
//       expect(style, isNotNull);
//     });
//   });
// }
