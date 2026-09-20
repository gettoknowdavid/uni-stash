import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/profile/view_models/_view_models.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

class EditProfilePage extends SignalStatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: model.profile.value?.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  ProfileViewModel get model => di<ProfileViewModel>();

  @override
  Widget build(BuildContext context) {
    return UsPage(
      gutters: .zero,
      header: const UsPageHeader(title: Text('EDIT PROFILE')),
      body: SignalEffect(
        effect: (context) {
          final success = model.updateSuccess.value;
          if (success) {
            ShadToaster.of(context).show(
              const ShadToast(
                title: Text('Profile Updated'),
                description: Text(
                  'Your profile has been updated successfully.',
                ),
              ),
            );
            context.pop();
          }
        },
        child: _EditProfileBody(
          model: model,
          nameController: _nameController,
        ),
      ),
    );
  }
}

class _EditProfileBody extends SignalStatefulWidget {
  const _EditProfileBody({
    required this.model,
    required this.nameController,
  });

  final ProfileViewModel model;
  final TextEditingController nameController;

  @override
  State<_EditProfileBody> createState() => _EditProfileBodyState();
}

class _EditProfileBodyState extends State<_EditProfileBody> {
  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isUpdating = widget.model.isUpdating.value;
    final updateError = widget.model.updateError.value;

    return SingleChildScrollView(
      padding: const .all(UsSpacing.lg),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Text(
            'DISPLAY NAME',
            style: theme.textTheme.labelSm.copyWith(
              color: theme.colorScheme.mutedForeground,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: UsSpacing.sm),
          ShadInput(
            controller: widget.nameController,
            placeholder: const Text('Enter your display name'),
          ),
          const SizedBox(height: UsSpacing.xxl),
          if (updateError != null) ...[
            ShadAlert.destructive(description: Text(updateError)),
            const SizedBox(height: UsSpacing.lg),
          ],
          ShadButton(
            onPressed: isUpdating ? null : () async => _save(),
            child: isUpdating
                ? const ShadSpinner()
                : const Text('SAVE CHANGES'),
          ),
          const SizedBox(height: UsSpacing.lg),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = widget.nameController.text.trim();
    if (name.isEmpty) {
      ShadToaster.of(context).show(
        const ShadToast(
          title: Text('Error'),
          description: Text('Display name cannot be empty.'),
        ),
      );
      return;
    }
    await widget.model.updateProfile(displayName: name);
  }
}
