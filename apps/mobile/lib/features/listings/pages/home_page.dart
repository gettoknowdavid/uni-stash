import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return const FScaffold(
      header: FHeader(title: Text('Home')),
      child: Text('Home'),
    );
  }
}
