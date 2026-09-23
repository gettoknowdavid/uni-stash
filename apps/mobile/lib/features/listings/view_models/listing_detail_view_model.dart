import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/chats/data/chats_repository.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';

/// A mutation a buyer/seller can run against the current listing.
///
/// Exposed through [ListingDetailViewModel.pendingAction] so buttons can
/// show a spinner for the action that is actually in flight.
enum ListingAction { reserve, unreserve, markAsSold }

/// The kind of one-shot UX outcome produced by a view model action.
///
/// The page reacts to these exactly once (toast, dialog) and then calls
/// the matching consume method, mirroring the `deletedId` pattern.
enum ListingFeedbackKind {
  /// Reservation succeeded.
  reserved,

  /// Un-reservation succeeded.
  unreserved,

  /// Listing marked as sold.
  sold,

  /// Reserve hit a 409 conflict — the listing was taken by someone else
  /// and the detail has already been re-fetched by the view model.
  unavailable,

  /// Reserve rejected because the user's email is not verified — the
  /// page should prompt verification.
  verifyEmail,

  /// Any other action failure; [ListingFeedback.message] carries the
  /// human-readable reason and [ListingFeedback.title] an optional
  /// toast title.
  failure,
}

/// One-shot feedback emitted by an action, consumed by the page via
/// [ListingDetailViewModel.consumeFeedback] so it is shown only once.
class ListingFeedback {
  const ListingFeedback(this.kind, {this.title, this.message});

  final ListingFeedbackKind kind;

  /// Toast title override, only used for [ListingFeedbackKind.failure].
  final String? title;

  /// Human-readable failure message (null for success kinds).
  final String? message;
}

/// Page-scoped ViewModel for a single listing's detail view.
///
/// Drives fetching, reserving, un-reserving, marking-as-sold, deleting
/// and opening a chat with the seller. All repository calls live here —
/// views/widgets only read signals and invoke these actions.
///
/// State model:
/// - [detail] is the single source of truth for listing status. Mutations
///   return the updated `Listing`, which is folded back into `detail`
///   (`_applyListing`) instead of re-fetching the whole detail response.
/// - [pendingAction] tracks the in-flight mutation for button spinners.
/// - [feedback] carries one-shot toasts/dialog triggers (consumed once).
class ListingDetailViewModel implements Disposable {
  ListingDetailViewModel(this._repository, this._chatsRepository) {
    _init();
  }

  final ListingsRepository _repository;
  final ChatsRepository _chatsRepository;

  final Signal<ListingDetailResponse?> detail = signal(null);
  final Signal<bool> isLoading = signal(false);
  final Signal<String?> error = signal(null);
  final Signal<bool> isDeleting = signal(false);

  /// The mutation currently in flight, or null when idle.
  final Signal<ListingAction?> pendingAction = signal(null);

  /// One-shot outcome of the last action; consumed by the page.
  final Signal<ListingFeedback?> feedback = signal(null);

  /// Whether a create-chat request is in flight (chat button spinner).
  final Signal<bool> isCreatingChat = signal(false);

  /// Set to the created/fetched chat id after a successful "chat with
  /// seller". The page navigates then calls [consumeChatResult].
  final Signal<String?> createdChatId = signal(null);

  /// Set to the deleted listing's id after a successful delete. The page
  /// reacts by navigating back; the view model cannot pop routes itself.
  final Signal<String?> deletedId = signal(null);

  /// Set when a delete fails. Separate from [error] so the page can toast
  /// deletion failures without also toasting fetch errors, which the page
  /// already surfaces inline.
  final Signal<String?> deleteError = signal(null);

  late final void Function(String id) fetch;
  late final void Function(String id) reserve;
  late final void Function(String id) unreserve;
  late final void Function(String id) markAsSold;
  late final void Function(String id) delete;
  late final void Function() createChat;

  bool _disposed = false;

  /// Core fetch logic, used for the initial load and the rare cases where
  /// local state is genuinely stale (e.g. a 409 reserve conflict).
  Future<void> _fetch(String id) async {
    isLoading.value = true;
    error.value = null;

    final result = await _repository.getListing(id);
    if (_disposed) return;

    switch (result) {
      case Success(:final value):
        detail.value = value;
      case Failure(:final message):
        error.value = message;
    }

    isLoading.value = false;
  }

  /// Folds the mutation endpoint's updated [Listing] into the cached
  /// detail so reserve/unreserve/markAsSold never re-fetch the whole
  /// `ListingDetailResponse`.
  void _applyListing(Listing updated) {
    final current = detail.value;
    if (current == null || current.id != updated.id) return;
    detail.value = current.copyWith(
      status: updated.status,
      reservedBy: updated.reservedBy,
      reservedAt: updated.reservedAt,
    );
  }

  void _init() {
    fetch = action1<String, void>((id) async {
      await _fetch(id);
    });

    reserve = action1<String, void>((id) async {
      if (pendingAction.value != null) return;
      pendingAction.value = .reserve;

      final result = await _repository.reserve(id);
      if (_disposed) return;

      switch (result) {
        case Success(:final value):
          _applyListing(value);
          feedback.value = const ListingFeedback(.reserved);
        case Failure(:final message, :final code):
          if (code == 'email_not_verified') {
            feedback.value = const ListingFeedback(.verifyEmail);
          } else if (_isTakenMessage(message)) {
            // 409 conflict: another buyer already reseved, so our cached
            // detail IS stale — this is the one case worth refetching.
            await _fetch(id);
            if (_disposed) return;
            feedback.value = const ListingFeedback(.unavailable);
          } else {
            feedback.value = ListingFeedback(
              .failure,
              title: 'Reserve Failed',
              message: message,
            );
          }
      }

      pendingAction.value = null;
    });

    unreserve = action1<String, void>((id) async {
      if (pendingAction.value != null) return;
      pendingAction.value = .unreserve;

      final result = await _repository.unreserve(id);
      if (_disposed) return;

      switch (result) {
        case Success(:final value):
          _applyListing(value);
          feedback.value = const ListingFeedback(.unreserved);
        case Failure(:final message):
          feedback.value = ListingFeedback(
            .failure,
            title: 'Failed',
            message: message,
          );
      }

      pendingAction.value = null;
    });

    markAsSold = action1<String, void>((id) async {
      if (pendingAction.value != null) return;
      pendingAction.value = .markAsSold;

      final result = await _repository.markAsSold(id);
      if (_disposed) return;

      switch (result) {
        case Success(:final value):
          _applyListing(value);
          feedback.value = const ListingFeedback(.sold);
        case Failure(:final message):
          feedback.value = ListingFeedback(
            .failure,
            title: 'Failed',
            message: message,
          );
      }

      pendingAction.value = null;
    });

    createChat = action0(() async {
      if (isCreatingChat.value) return;
      final listingId = detail.value?.id;
      if (listingId == null) return;

      isCreatingChat.value = true;

      final result = await _chatsRepository.createChat(listingId);
      if (_disposed) return;

      switch (result) {
        case Success(:final value):
          createdChatId.value = value;
        case Failure(:final message):
          feedback.value = ListingFeedback(
            .failure,
            title: 'Chat Failed',
            message: message,
          );
      }

      isCreatingChat.value = false;
    });

    delete = action1<String, void>((id) async {
      // Re-entrancy guard, set before the first await so a double-tap
      // cannot fire two DELETE requests.
      if (isDeleting.value) return;
      isDeleting.value = true;
      deleteError.value = null;

      final result = await _repository.delete(id);
      if (_disposed) return;

      switch (result) {
        case Success():
          // `detail` is intentionally left as-is: the page pops straight
          // back on `deletedId`, so clearing it here would only flash the
          // "Listing not found" state for a frame.
          deletedId.value = id;
        case Failure(:final message):
          deleteError.value = message;
      }

      isDeleting.value = false;
    });
  }

  /// Backend 409 conflict message for a taken/reserved listing.
  bool _isTakenMessage(String message) =>
      message.toLowerCase().contains('no longer available');

  void reset() {
    detail.value = null;
    isLoading.value = false;
    error.value = null;
    isDeleting.value = false;
    pendingAction.value = null;
    feedback.value = null;
    isCreatingChat.value = false;
    createdChatId.value = null;
    deletedId.value = null;
    deleteError.value = null;
  }

  /// Clears one-shot delete state after the UI has reacted to it.
  void consumeDeleteResult() {
    deletedId.value = null;
    deleteError.value = null;
  }

  /// Clears one-shot action feedback after the UI has reacted to it.
  void consumeFeedback() {
    feedback.value = null;
  }

  /// Clears the created chat id after the UI has navigated to it.
  void consumeChatResult() {
    createdChatId.value = null;
  }

  void dispose() {
    _disposed = true;
    detail.dispose();
    isLoading.dispose();
    error.dispose();
    isDeleting.dispose();
    pendingAction.dispose();
    feedback.dispose();
    isCreatingChat.dispose();
    createdChatId.dispose();
    deletedId.dispose();
    deleteError.dispose();
  }

  @override
  FutureOr<dynamic> onDispose() {
    dispose();
  }
}
