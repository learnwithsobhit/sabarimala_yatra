import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Offline trip pack — hydrate on Wi‑Fi, read when network is dead (NFR-O1 / R1).
class TripPackStore {
  static const _key = 'trip_pack_v1';
  static const _syncedAtKey = 'trip_pack_synced_at';

  /// Merge [updates] into the existing pack so Home refresh does not wipe packing.
  Future<void> save(Map<String, dynamic> updates) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await load() ?? <String, dynamic>{};
    existing.addAll(updates);
    await prefs.setString(_key, jsonEncode(existing));
    await prefs.setString(_syncedAtKey, DateTime.now().toIso8601String());
  }

  Future<Map<String, dynamic>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> syncedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_syncedAtKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }
}
