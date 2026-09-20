import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/features/profile/view_models/_view_models.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final ProfileViewModel _model;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _model = di<ProfileViewModel>();
    _nameController = TextEditingController(
      text: _model.profile.value?.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UsPage(
      header: UsPageHeader(
        title: const Text('EDIT PROFILE'),
        leading: ShadIconButton.ghost(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: _EditProfileBody(
        model: _model,
        nameController: _nameController,
      ),
    );
  }
}

class _EditProfileBody extends StatefulWidget {
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
  void initState() {
    super.initState();
    // Listen for successful updates using effect.
    _setupSuccessListener();
  }

  void _setupSuccessListener() {
    // Use effect to reactively listen for updateSuccess changes.
    effect(() {
      final success = widget.model.updateSuccess.value;
      if (success && mounted) {
        ShadToaster.of(context).show(
          const ShadToast(
            title: Text('Profile Updated'),
            description: Text('Your profile has been updated successfully.'),
          ),
        );
        context.pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isUpdating = widget.model.isUpdating.value;
    final updateError = widget.model.updateError.value;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),

          // Display Name field
          Text(
            'DISPLAY NAME',
            style: theme.textTheme.labelSm.copyWith(
              color: theme.colorScheme.mutedForeground,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ShadInput(
            controller: widget.nameController,
            placeholder: const Text('Enter your display name'),
          ),

          const SizedBox(height: 32),

          // Error message
          if (updateError != null) ...[
            ShadAlert.destructive(
              description: Text(updateError),
            ),
            const SizedBox(height: 16),
          ],

          // Save button
          ShadButton(
            onPressed: isUpdating ? null : _save,
            child: isUpdating
                ? const ShadSpinner()
                : const Text('SAVE CHANGES'),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _save() {
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
    unawaited(widget.model.updateProfile(displayName: name));
  }
}
