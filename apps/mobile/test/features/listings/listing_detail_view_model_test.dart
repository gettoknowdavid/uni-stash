import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uni_stash_mobile/core/config/di.dart';
import 'package:uni_stash_mobile/core/result/result.dart';
import 'package:uni_stash_mobile/features/chats/data/chats_repository.dart';
import 'package:uni_stash_mobile/features/chats/data/realtime_client.dart';
import 'package:uni_stash_mobile/features/listings/data/listings_repository.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';
import 'package:uni_stash_mobile/features/listings/view_models/listing_detail_view_model.dart';

class MockListingsRepository extends Mock implements ListingsRepository {}

class MockChatsRepository extends Mock implements ChatsRepository {}

class MockRealtimeClient extends Mock implements RealtimeClient {}

ListingDetailResponse buildDetail({ListingStatus? status}) {
  return ListingDetailResponse(
    id: 'l1',
    title: 'Mini Fridge',
    description: 'Barely used',
    condition: Condition.used,
    status: status ?? ListingStatus.active,
    createdAt: DateTime(2026),
    seller: const Seller(
      id: 'u2',
      displayName: 'Ada Seller',
      emailVerified: true,
      domain: 'unilag.edu.ng',
    ),
    category: const Category(
      id: 1,
      slug: 'electronics',
      label: 'Electronics',
    ),
    images: const [],
    price: Money.fromMajor(1500),
  );
}

Listing buildListing({ListingStatus? status, String? reservedBy}) {
  return Listing(
    id: 'l1',
    sellerId: 'u2',
    categoryId: 1,
    title: 'Mini Fridge',
    description: 'Barely used',
    condition: Condition.used,
    status: status ?? ListingStatus.active,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026, 1, 2),
    reservedBy: reservedBy,
    price: Money.fromMajor(1500),
  );
}

void main() {
  late MockListingsRepository listings;
  late MockChatsRepository chats;
  late MockRealtimeClient realtime;
  late ListingDetailViewModel model;

  setUp(() {
    listings = MockListingsRepository();
    chats = MockChatsRepository();
    realtime = MockRealtimeClient();
    // The VM subscribes to the listing channel after a successful fetch;
    // tests run without the realtime stack, so stub a no-op subscription.
    when(
      () => realtime.subscribeToListing(
        any(),
        onListingUpdated: any(named: 'onListingUpdated'),
      ),
    ).thenAnswer((_) async => RealtimeSubscription.none());
    di.pushNewScope();
    di.registerLazySingleton<RealtimeClient>(() => realtime);
    model = ListingDetailViewModel(listings, chats);
  });

  tearDown(() async {
    model.dispose();
    await di.popScope();
  });

  /// Performs the initial load (the only getListing these tests allow).
  Future<void> loadDetail() async {
    when(() => listings.getListing('l1')).thenAnswer(
      (_) async => Result.success(buildDetail()),
    );
    model.fetch('l1');
    await pumpEventQueue();
    expect(model.detail.value, isNotNull);
  }

  group('mutations fold into detail without refetching', () {
    test('reserve', () async {
      await loadDetail();
      when(() => listings.reserve('l1')).thenAnswer(
        (_) async => Result.success(
          buildListing(
            status: ListingStatus.reserved,
            reservedBy: 'me',
          ),
        ),
      );

      model.reserve('l1');
      await pumpEventQueue();

      expect(model.detail.value?.status, ListingStatus.reserved);
      expect(model.detail.value?.reservedBy, 'me');
      expect(model.feedback.value?.kind, ListingFeedbackKind.reserved);
      expect(model.pendingAction.value, isNull);
      // Only the initial load — the mutation response was folded in.
      verify(() => listings.getListing('l1')).called(1);
    });

    test('unreserve clears reservedBy, including the null value', () async {
      when(() => listings.getListing('l1')).thenAnswer(
        (_) async => Result.success(
          buildDetail(status: ListingStatus.reserved),
        ),
      );
      model.fetch('l1');
      await pumpEventQueue();

      when(() => listings.unreserve('l1')).thenAnswer(
        (_) async => Result.success(buildListing()),
      );

      model.unreserve('l1');
      await pumpEventQueue();

      expect(model.detail.value?.status, ListingStatus.active);
      expect(model.detail.value?.reservedBy, isNull);
      expect(model.feedback.value?.kind, ListingFeedbackKind.unreserved);
      verify(() => listings.getListing('l1')).called(1);
    });

    test('markAsSold', () async {
      await loadDetail();
      when(() => listings.markAsSold('l1')).thenAnswer(
        (_) async => Result.success(buildListing(status: .sold)),
      );

      model.markAsSold('l1');
      await pumpEventQueue();

      expect(model.detail.value?.status, ListingStatus.sold);
      expect(model.feedback.value?.kind, ListingFeedbackKind.sold);
      verify(() => listings.getListing('l1')).called(1);
    });

    test('reserve re-fetches only on a 409 conflict', () async {
      await loadDetail();
      when(() => listings.reserve('l1')).thenAnswer(
        (_) async => const Result.failure(
          'This item is no longer available.',
          code: 'conflict',
        ),
      );

      model.reserve('l1');
      await pumpEventQueue();

      expect(model.feedback.value?.kind, ListingFeedbackKind.unavailable);
      // Initial load + the conflict refresh.
      verify(() => listings.getListing('l1')).called(2);
      expect(model.pendingAction.value, isNull);
    });

    test('reserve surfaces email_not_verified as a verify prompt', () async {
      await loadDetail();
      when(() => listings.reserve('l1')).thenAnswer(
        (_) async => const Result.failure(
          'Email not verified',
          code: 'email_not_verified',
        ),
      );

      model.reserve('l1');
      await pumpEventQueue();

      expect(model.feedback.value?.kind, ListingFeedbackKind.verifyEmail);
      expect(model.detail.value?.status, ListingStatus.active);
      verify(() => listings.getListing('l1')).called(1);
    });

    test('a failed mutation reports failure feedback', () async {
      await loadDetail();
      when(() => listings.reserve('l1')).thenAnswer(
        (_) async => const Result.failure('Network error'),
      );

      model.reserve('l1');
      await pumpEventQueue();

      final feedback = model.feedback.value;
      expect(feedback?.kind, ListingFeedbackKind.failure);
      expect(feedback?.message, 'Network error');
      expect(model.pendingAction.value, isNull);
    });
  });

  group('createChat', () {
    test('exposes the created chat id as a one-shot signal', () async {
      await loadDetail();
      when(() => chats.createChat('l1')).thenAnswer(
        (_) async => const Result.success('c1'),
      );

      model.createChat();
      await pumpEventQueue();

      expect(model.createdChatId.value, 'c1');
      expect(model.isCreatingChat.value, isFalse);

      model.consumeChatResult();
      expect(model.createdChatId.value, isNull);
    });

    test('failures surface through feedback', () async {
      await loadDetail();
      when(() => chats.createChat('l1')).thenAnswer(
        (_) async => const Result.failure('boom'),
      );

      model.createChat();
      await pumpEventQueue();

      expect(model.feedback.value?.kind, ListingFeedbackKind.failure);
      expect(model.feedback.value?.title, 'Chat Failed');
      expect(model.createdChatId.value, isNull);
    });
  });
}
