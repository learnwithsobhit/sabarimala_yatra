import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Queues Present taps when offline; flush when network returns (NFR-R2).
class PresentQueue {
  static const _key = 'present_queue_v1';

  Future<List<Map<String, dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items));
  }

  Future<void> enqueue({
    required String sessionId,
    required String clientId,
  }) async {
    final items = await load();
    // One pending mark per session
    items.removeWhere((e) => e['session_id'] == sessionId);
    items.add({
      'session_id': sessionId,
      'client_id': clientId,
      'queued_at': DateTime.now().toIso8601String(),
    });
    await _save(items);
  }

  Future<void> remove(String sessionId) async {
    final items = await load();
    items.removeWhere((e) => e['session_id'] == sessionId);
    await _save(items);
  }

  Future<int> flush(
    Future<void> Function(String sessionId, String clientId) send,
  ) async {
    final items = await load();
    if (items.isEmpty) return 0;
    final remaining = <Map<String, dynamic>>[];
    var flushed = 0;
    for (final item in items) {
      try {
        await send(
          item['session_id'] as String,
          item['client_id'] as String,
        );
        flushed++;
      } catch (_) {
        remaining.add(item);
      }
    }
    await _save(remaining);
    return flushed;
  }
}
