import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/auth/view_models/auth_view_model.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return UsPage(
      header: const UsPageHeader(
        title: Text('UNI·STASH'),
      ),
      body: Center(
        child: ShadButton.outline(
          onPressed: () => di<AuthViewModel>().unauthenticate(),
          child: const Text('LOGOUT'),
        ),
      ),
    );
  }
}
