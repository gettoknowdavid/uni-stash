import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: const FHeader(title: Text('Home')),
      child: Center(
        child: FButton(
          onPress: () => di<AuthViewModel>().unauthenticate(),
          child: const Text('Logout'),
        ),
      ),
    );
  }
}
