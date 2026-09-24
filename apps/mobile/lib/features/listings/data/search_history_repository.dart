import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the search page's recent query terms locally (max 10, deduped,
/// most-recent-first) so they survive app restarts.
class SearchHistoryRepository {
  SearchHistoryRepository(this._storage);

  final FlutterSecureStorage _storage;

  static const String _key = 'search_history';
  static const int _maxEntries = 10;

  /// Returns the stored terms, newest first. Never throws — a corrupt or
  /// unreadable payload just reads as an empty history.
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

  /// Adds [term] to the front of the history (case-insensitively deduped,
  /// capped at [_maxEntries]) and returns the updated list.
  Future<List<String>> add(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return load();

    final current = await load();
    final lowered = trimmed.toLowerCase();
    final updated = <String>[
      trimmed,
      for (final entry in current)
        if (entry.toLowerCase() != lowered) entry,
    ].take(_maxEntries).toList(growable: false);

    await _storage.write(key: _key, value: jsonEncode(updated));
    return updated;
  }

  /// Removes every stored term.
  Future<void> clear() => _storage.delete(key: _key);
}
