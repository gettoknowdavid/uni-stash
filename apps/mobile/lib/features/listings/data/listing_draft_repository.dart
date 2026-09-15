import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_draft.dart';

/// Persists [ListingDraft] to local storage so that unfinished listing
/// submissions survive app crashes and restarts.
class ListingDraftRepository {
  ListingDraftRepository(this._storage);

  final FlutterSecureStorage _storage;

  static const _key = 'listing_draft';

  /// Saves [draft] to storage, overwriting any existing draft.
  Future<void> save(ListingDraft draft) async {
    await _storage.write(key: _key, value: draft.encode());
  }

  /// Returns the saved draft, or `null` if none exists or is corrupted.
  Future<ListingDraft?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    return ListingDraft.decode(raw);
  }

  /// Clears the saved draft. Called after successful submission or when the
  /// user explicitly discards it.
  Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}
