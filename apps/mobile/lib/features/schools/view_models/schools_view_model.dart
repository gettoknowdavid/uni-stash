import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/schools/data/schools_repository.dart';
import 'package:uni_stash_mobile/features/schools/models/models.dart';
import 'package:uni_stash_mobile/features/schools/models/school_dto.dart';

/// Page-scoped ViewModel that drives the paginated schools list.
class SchoolsViewModel implements Disposable {
  SchoolsViewModel(this._repository) {
    fetch = action0(() async {
      isLoading.value = true;
      error.value = null;
      _cursor = null;
      hasMore.value = true;

      final result = await _repository.list(ListSchoolsQuery(
        q: query.value.isEmpty ? null : query.value,
      ));

      switch (result) {
        case Success(:final value):
          schools.value = value.schools;
          _cursor = value.nextCursor;
          hasMore.value = value.nextCursor != null;
        case Failure(:final message):
          error.value = message;
      }

      isLoading.value = false;
    });

    loadMore = action0(() async {
      if (isLoadingMore.value || !hasMore.value || _cursor == null) return;

      isLoadingMore.value = true;
      error.value = null;

      final result = await _repository.list(ListSchoolsQuery(
        q: query.value.isEmpty ? null : query.value,
        cursor: _cursor,
      ));

      switch (result) {
        case Success(:final value):
          schools.value = [...schools.value, ...value.schools];
          _cursor = value.nextCursor;
          hasMore.value = value.nextCursor != null;
        case Failure(:final message):
          error.value = message;
      }

      isLoadingMore.value = false;
    });

    refresh = action0(() async {
      _cursor = null;
      hasMore.value = true;

      final result = await _repository.list(ListSchoolsQuery(
        q: query.value.isEmpty ? null : query.value,
      ));

      switch (result) {
        case Success(:final value):
          schools.value = value.schools;
          _cursor = value.nextCursor;
          hasMore.value = value.nextCursor != null;
        case Failure(:final message):
          error.value = message;
      }
    });
  }

  final SchoolsRepository _repository;

  final Signal<List<School>> schools = signal([]);
  final Signal<bool> isLoading = signal(false);
  final Signal<bool> isLoadingMore = signal(false);
  final Signal<String?> error = signal(null);
  final Signal<bool> hasMore = signal(true);

  String? _cursor;

  /// Current search query.
  final Signal<String> query = signal('');

  late final void Function() fetch;
  late final void Function() loadMore;
  late final void Function() refresh;

  void reset() {
    schools.value = [];
    isLoading.value = false;
    isLoadingMore.value = false;
    error.value = null;
    hasMore.value = true;
    _cursor = null;
    query.value = '';
  }

  void dispose() {
    schools.dispose();
    isLoading.dispose();
    isLoadingMore.dispose();
    error.dispose();
    hasMore.dispose();
    query.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
