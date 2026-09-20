import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:uni_stash_mobile/core/config/di.dart';

/// Per-base-name visit counter used to build unique scope names.
///
/// get_it asserts that a pushed scope name is not already in use. Pages
/// previously pushed hard-coded names ('loginPage', 'listingEditorPage',
/// …) in `initState` and never popped them, so the *second* visit to any
/// of those pages crashed with "You already have used the scope name X".
/// Unique names make every visit independent; popping on dispose (see
/// [popPageScope]) keeps the stack from growing without bound.
///
/// Counters grow monotonically: a stale count (e.g. after the logout flow
/// pops scopes in bulk) only produces a fresh unique name, never a reuse
/// that could collide with a still-registered scope.
final Map<String, int> _pageScopeCounts = {};

/// Pushes a GetIt scope for a single page visit and returns its unique
/// scope name.
///
/// Store the returned name and pass it to [popPageScope] from the page
/// State's `dispose`. The [init] callback registers the page-scoped
/// ViewModels, exactly like the `init` of `di.pushNewScope` it wraps.
String pushPageScope({
  required String baseName,
  required void Function(GetIt getIt) init,
}) {
  final visit = (_pageScopeCounts[baseName] ?? 0) + 1;
  _pageScopeCounts[baseName] = visit;
  final scopeName = visit == 1 ? baseName : '$baseName-$visit';
  di.pushNewScope(scopeName: scopeName, init: init);
  return scopeName;
}

/// Pops a page scope previously created by [pushPageScope].
///
/// Intended to be fired (unawaited) from a page State's `dispose`:
///
/// ```dart
/// @override
/// void dispose() {
///   final scopeName = _scopeName;
///   _scopeName = null;
///   if (scopeName != null) unawaited(popPageScope(scopeName));
///   super.dispose();
/// }
/// ```
///
/// `popScope()` is async (dispose callbacks may await), while `dispose()`
/// is sync — so the pop is fired, not awaited. Widgets are unmounted
/// before `dispose` runs, so their signal subscriptions are already torn
/// down by the time the ViewModels are disposed here.
///
/// If scopes above this one were never popped (an orphaned child page),
/// they are popped too — their owning pages have already been disposed,
/// so their registrations are garbage either way.
Future<void> popPageScope(String scopeName) async {
  // Only pop when this scope is still the topmost one. If a navigation
  // replacement (e.g. `context.go(login)` from a page being disposed) has
  // already pushed a new page's scope on top, popping "till" ours would
  // also dispose the new page's live registrations. In that case the
  // orphaned scope is reclaimed later by a bulk cleanup (the logout flow
  // pops scopes till root); a stale unique name is harmless.
  if (di.currentScopeName != scopeName) return;

  try {
    await di.popScope();
  } on Object catch (error) {
    // The scope may already be gone (double dispose, or a bulk cleanup
    // such as logout popped it first). Nothing to recover — log in debug.
    assert(
      () {
        debugPrint('[page_scope] pop "$scopeName" failed: $error');
        return true;
      }(),
      'page_scope: failed to pop "$scopeName"',
    );
  }
}
