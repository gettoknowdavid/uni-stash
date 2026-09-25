import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/config/page_scope.dart';
import 'package:uni_stash_mobile/features/listings/data/reports_api.dart';
import 'package:uni_stash_mobile/features/listings/view_models/_view_models.dart';
import 'package:uni_stash_mobile/router/us_routes.dart';
import 'package:uni_stash_mobile/shared/widgets/_widgets.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// MY REPORTS (profile menu): the reports the signed-in user filed.
/// Open reports can be edited (reason) or withdrawn; reports already
/// under moderation are read-only.
class MyReportsPage extends StatefulWidget {
  const MyReportsPage({super.key});

  @override
  State<MyReportsPage> createState() => _MyReportsPageState();
}

class _MyReportsPageState extends State<MyReportsPage> {
  /// Unique per-visit GetIt scope name; popped in [dispose].
  String? _scopeName;

  @override
  void initState() {
    super.initState();
    _scopeName = pushPageScope(
      baseName: 'myReports',
      init: (getIt) {
        getIt.registerLazySingleton<MyReportsViewModel>(
          () => MyReportsViewModel(di()),
          dispose: (model) => model.dispose(),
        );
      },
    );
    di<MyReportsViewModel>().fetch();
  }

  @override
  void dispose() {
    // popScope() is async but dispose() is sync, so the pop is fired,
    // not awaited — see [popPageScope].
    final scopeName = _scopeName;
    _scopeName = null;
    if (scopeName != null) unawaited(popPageScope(scopeName));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const UsPage(
      gutters: .zero,
      header: UsPageHeader(title: Text('MY REPORTS')),
      body: _ReportsBody(),
    );
  }
}

class _ReportsBody extends SignalWidget {
  const _ReportsBody();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<MyReportsViewModel>();
    final reports = model.reports.value;
    final isLoading = model.isLoading.value;
    final error = model.error.value;

    if (isLoading && reports.isEmpty) {
      return const Center(child: Spinner());
    }

    if (error != null && reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: .min,
          children: [
            Text(error, style: theme.textTheme.muted, textAlign: .center),
            const SizedBox(height: 16),
            ShadButton.outline(
              onPressed: model.fetch,
              child: const Text('RETRY'),
            ),
          ],
        ),
      );
    }

    if (reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: .min,
          children: [
            Icon(
              LucideIcons.flag,
              size: 48,
              color: theme.colorScheme.mutedForeground,
            ),
            const SizedBox(height: UsSpacing.md),
            Text(
              'No reports filed',
              style: theme.textTheme.muted,
            ),
            const SizedBox(height: UsSpacing.sm),
            Text(
              'Reports you file on listings will show up here.',
              textAlign: .center,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      );
    }

    return SignalEffect(
      effect: (context) {
        // Surface action failures (e.g. withdrawing a locked report).
        final message = model.error.value;
        if (message == null || reports.isEmpty) return;
        model.error.value = null;
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Something went wrong'),
            description: Text(message),
          ),
        );
      },
      child: ListView.separated(
        padding: const .all(UsSpacing.lg),
        itemCount: reports.length,
        separatorBuilder: (_, _) => const SizedBox(height: UsSpacing.md),
        itemBuilder: (context, index) {
          final report = reports[index];
          return _ReportCard(report: report);
        },
      ),
    );
  }
}

class _ReportCard extends SignalWidget {
  const _ReportCard({required this.report});

  final ReportResponse report;

  bool get _isOpen => report.status == 'open';

  Future<void> _confirmWithdraw(BuildContext context) async {
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (dialogContext) => Padding(
        padding: const .all(16),
        child: ShadDialog.alert(
          title: const Text('WITHDRAW REPORT?'),
          description: const Text(
            'This will remove your report from the moderation queue. '
            'You can file a new report later if needed.',
          ),
          actions: [
            ShadButton.outline(
              onPressed: () => dialogContext.pop(false),
              child: const Text('CANCEL'),
            ),
            ShadButton.destructive(
              onPressed: () => dialogContext.pop(true),
              child: const Text('WITHDRAW'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !context.mounted) return;
    final model = di<MyReportsViewModel>();
    final ok = await model.withdraw(report.id);
    if (!context.mounted) return;
    if (ok) {
      ShadToaster.of(context).show(
        const ShadToast(
          title: Text('Report withdrawn'),
          description: Text('Your report has been removed.'),
        ),
      );
    }
  }

  Future<void> _editReason(BuildContext context) async {
    final controller = TextEditingController(text: report.reason ?? '');
    final saved = await showShadDialog<bool>(
      context: context,
      builder: (dialogContext) => ShadDialog(
        title: const Text('EDIT REPORT'),
        description: const Text('Update the reason for this report.'),
        actions: [
          ShadButton.outline(
            onPressed: () => dialogContext.pop(false),
            child: const Text('CANCEL'),
          ),
          ShadButton(
            onPressed: () => dialogContext.pop(true),
            child: const Text('SAVE'),
          ),
        ],
        child: ShadInput(
          controller: controller,
          placeholder: const Text('What is wrong with this listing?'),
          maxLines: 3,
          minLines: 2,
        ),
      ),
    );

    if (saved != true || !context.mounted) return;
    final model = di<MyReportsViewModel>();
    final ok = await model.updateReason(
      report.id,
      controller.text.trim(),
    );
    if (!context.mounted) return;
    if (ok) {
      ShadToaster.of(context).show(
        const ShadToast(
          title: Text('Report updated'),
          description: Text('Your report has been updated.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final model = di<MyReportsViewModel>();
    final busy = model.busyReportId.value == report.id;

    return ShadCard(
      padding: const .symmetric(horizontal: 16, vertical: 12),
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Report • ${timeago.format(report.createdAt)}',
              style: theme.textTheme.p.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          _StatusBadge(status: report.status),
        ],
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Text(
            report.reason?.isNotEmpty == true
                ? report.reason!
                : 'No reason provided.',
            style: theme.textTheme.muted,
          ),
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              await context.push(
                UsRoutes.listingDetailsRoute(report.listingId),
              );
              di<MyReportsViewModel>().fetch();
            },
            child: Row(
              mainAxisSize: .min,
              children: [
                Text(
                  'View listing',
                  style: theme.textTheme.small.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  LucideIcons.arrowUpRight,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
          if (_isOpen) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ShadButton.outline(
                    height: 32,
                    enabled: !busy,
                    onPressed: () => unawaited(_editReason(context)),
                    child: busy
                        ? const Spinner(
                            iconSize: 14,
                            height: 14,
                            width: 14,
                          )
                        : const Text('EDIT'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ShadButton.destructive(
                    height: 32,
                    enabled: !busy,
                    onPressed: () => unawaited(_confirmWithdraw(context)),
                    child: const Text('WITHDRAW'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    final (label, background, foreground) = switch (status) {
      'open' => (
          'OPEN',
          theme.colorScheme.statusWarningBg,
          theme.colorScheme.statusWarning,
        ),
      'reviewing' => (
          'IN REVIEW',
          theme.colorScheme.statusInfoBg,
          theme.colorScheme.statusInfo,
        ),
      'resolved' => (
          'RESOLVED',
          theme.colorScheme.statusSuccessBg,
          theme.colorScheme.statusSuccess,
        ),
      _ => (
          'DISMISSED',
          theme.colorScheme.muted,
          theme.colorScheme.mutedForeground,
        ),
    };

    return Container(
      padding: const .symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: .circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSm.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }
}
