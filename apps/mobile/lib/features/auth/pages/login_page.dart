import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const FScaffold(
      header: FHeader(title: Text('Login')),
      child: Text('Login'),
    );
  }
}
