import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uni_stash_mobile/features/listings/data/_data.dart' show SearchHistoryRepository;
import 'package:uni_stash_mobile/features/listings/data/search_history_repository.dart' show SearchHistoryRepository;

/// A saved search: the user's current search criteria, persisted locally
/// (frontend-only — no backend routes). Tapping one re-runs the search.
class SavedSearch {
  const SavedSearch({
    required this.id,
    required this.name,
    required this.query,
    required this.createdAt,
    this.categoryId,
    this.minPrice,
    this.maxPrice,
  });

  factory SavedSearch.fromJson(Map<String, dynamic> json) => SavedSearch(
    id: json['id'] as String,
    name: json['name'] as String,
    query: json['query'] as String? ?? '',
    categoryId: json['category_id'] as int?,
    minPrice: json['min_price'] as int?,
    maxPrice: json['max_price'] as int?,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  final String id;

  /// User-visible label, e.g. `\"mini fridge · under ₦40,000\"`.
  final String name;

  /// Free-text query (may be empty when only filters are set).
  final String query;
  final int? categoryId;
  final int? minPrice;
  final int? maxPrice;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'query': query,
    'category_id': categoryId,
    'min_price': minPrice,
    'max_price': maxPrice,
    'created_at': createdAt.toIso8601String(),
  };
}

/// Persists saved searches locally (max 20, newest first). Stored in secure
/// storage as a JSON array, mirroring [SearchHistoryRepository]. All
/// operations are best-effort-safe: a corrupt payload reads as empty.
class SavedSearchesRepository {
  SavedSearchesRepository(this._storage);

  final FlutterSecureStorage _storage;

  static const String _key = 'saved_searches';
  static const int _maxEntries = 20;

  Future<List<SavedSearch>> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(SavedSearch.fromJson)
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  /// Adds [search] to the front (an entry with the identical criteria
  /// replaces the old one) and returns the updated list.
  Future<List<SavedSearch>> add(SavedSearch search) async {
    final current = await load();
    final updated = <SavedSearch>[
      search,
      for (final entry in current)
        if (!_sameCriteria(entry, search)) entry,
    ].take(_maxEntries).toList(growable: false);
    await _write(updated);
    return updated;
  }

  Future<List<SavedSearch>> remove(String id) async {
    final updated = [
      for (final entry in await load()) if (entry.id != id) entry,
    ];
    await _write(updated);
    return updated;
  }

  Future<void> _write(List<SavedSearch> entries) =>
      _storage.write(key: _key, value: jsonEncode(entries));

  bool _sameCriteria(SavedSearch a, SavedSearch b) =>
      a.query.trim().toLowerCase() == b.query.trim().toLowerCase() &&
      a.categoryId == b.categoryId &&
      a.minPrice == b.minPrice &&
      a.maxPrice == b.maxPrice;
}
