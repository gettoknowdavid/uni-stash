import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Locally persisted saved (bookmarked) listings, keyed by listing id.
///
/// There is no saved-items backend yet (the profile stats endpoint reports
/// saved as "not yet implemented"), so bookmarks live in secure storage on
/// the device and survive app restarts.
class SavedItemsRepository {
  SavedItemsRepository(this._storage);

  final FlutterSecureStorage _storage;

  static const String _key = 'saved_listings';

  /// Returns the saved listing ids, newest first. Never throws — a corrupt
  /// or unreadable payload just reads as an empty list.
  Future<List<String>> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList(growable: false);
    } on Object {
      return const [];
    }
  }

  /// Saves [listingId], moving it to the front if already present.
  Future<List<String>> add(String listingId) async {
    final current = await load();
    final updated = <String>[
      listingId,
      ...current.where((id) => id != listingId),
    ];
    await _write(updated);
    return updated;
  }

  /// Removes [listingId]. Returns the updated list.
  Future<List<String>> remove(String listingId) async {
    final updated = (await load()).where((id) => id != listingId).toList();
    await _write(updated);
    return updated;
  }

  /// Toggles [listingId]: removes it when saved, saves it when not.
  /// Returns the updated list and whether the listing is now saved.
  Future<(List<String>, bool)> toggle(String listingId) async {
    final current = await load();
    if (current.contains(listingId)) {
      final updated = await remove(listingId);
      return (updated, false);
    }
    final updated = await add(listingId);
    return (updated, true);
  }

  Future<void> _write(List<String> ids) =>
      _storage.write(key: _key, value: jsonEncode(ids));
}
