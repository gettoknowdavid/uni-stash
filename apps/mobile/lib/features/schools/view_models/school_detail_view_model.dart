import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/schools/data/schools_repository.dart';
import 'package:uni_stash_mobile/features/schools/models/models.dart';

/// Page-scoped ViewModel for a single school's detail view.
class SchoolDetailViewModel implements Disposable {
  SchoolDetailViewModel(this._repository) {
    _init();
  }

  final SchoolsRepository _repository;

  final Signal<School?> school = signal(null);
  final Signal<bool> isLoading = signal(false);
  final Signal<String?> error = signal(null);

  late final void Function(String id) fetch;

  Future<void> _fetch(String id) async {
    isLoading.value = true;
    error.value = null;

    final result = await _repository.getSchool(id);
    switch (result) {
      case Success(:final value):
        school.value = value;
      case Failure(:final message):
        error.value = message;
    }

    isLoading.value = false;
  }

  void _init() {
    fetch = action1<String, void>((id) async {
      await _fetch(id);
    });
  }

  void reset() {
    school.value = null;
    isLoading.value = false;
    error.value = null;
  }

  void dispose() {
    school.dispose();
    isLoading.dispose();
    error.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
