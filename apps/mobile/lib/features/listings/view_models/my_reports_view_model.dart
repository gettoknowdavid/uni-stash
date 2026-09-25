import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/listings/data/reports_api.dart';
import 'package:uni_stash_mobile/features/listings/data/reports_repository.dart';

/// Page-scoped ViewModel driving MY REPORTS (profile menu): the reports
/// the signed-in user filed, with update (reason) and withdraw actions.
/// Only `open` reports are editable/withdrawable — ones already picked up
/// by moderation are locked and the UI reflects that.
class MyReportsViewModel implements Disposable {
  MyReportsViewModel(this._repository) {
    fetch = action0(() async {
      isLoading.value = true;
      error.value = null;

      final result = await _repository.mine();
      if (_disposed) return;

      switch (result) {
        case Success(:final value):
          reports.value = value;
        case Failure(:final message):
          error.value = message;
      }

      isLoading.value = false;
    });
  }

  final ReportsRepository _repository;

  final Signal<List<ReportResponse>> reports = signal([]);
  final Signal<bool> isLoading = signal(false);
  final Signal<String?> error = signal(null);

  /// Id of the report with an action in flight (spinner target).
  final Signal<String?> busyReportId = signal(null);

  bool _disposed = false;

  late final void Function() fetch;

  /// Updates the reason on an open report, replacing it in the list.
  Future<bool> updateReason(String reportId, String reason) async {
    if (busyReportId.value != null) return false;
    busyReportId.value = reportId;
    final result = await _repository.update(reportId, reason: reason);
    if (_disposed) return false;
    busyReportId.value = null;

    switch (result) {
      case Success(:final value):
        reports.value = [
          for (final report in reports.value)
            if (report.id == reportId) value else report,
        ];
        return true;
      case Failure(:final message):
        error.value = message;
        return false;
    }
  }

  /// Withdraws an open report, removing it from the list.
  Future<bool> withdraw(String reportId) async {
    if (busyReportId.value != null) return false;
    busyReportId.value = reportId;
    final result = await _repository.delete(reportId);
    if (_disposed) return false;
    busyReportId.value = null;

    switch (result) {
      case Success():
        reports.value = [
          for (final report in reports.value)
            if (report.id != reportId) report,
        ];
        return true;
      case Failure(:final message):
        error.value = message;
        return false;
    }
  }

  void dispose() {
    _disposed = true;
    reports.dispose();
    isLoading.dispose();
    error.dispose();
    busyReportId.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
