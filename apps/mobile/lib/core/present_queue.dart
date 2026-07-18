import 'dart:convert';
import 'dart:math';

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
      'attempts': 0,
      'next_retry_at': DateTime.now().toIso8601String(),
    });
    await _save(items);
  }

  Future<void> remove(String sessionId) async {
    final items = await load();
    items.removeWhere((e) => e['session_id'] == sessionId);
    await _save(items);
  }

  Future<bool> isQueued(String sessionId) async {
    final items = await load();
    return items.any((e) => e['session_id'] == sessionId);
  }

  Future<int> flush(
    Future<void> Function(String sessionId, String clientId) send,
  ) async {
    final items = await load();
    if (items.isEmpty) return 0;
    final remaining = <Map<String, dynamic>>[];
    var flushed = 0;
    final now = DateTime.now();
    for (final item in items) {
      final nextRetryRaw = item['next_retry_at']?.toString();
      final nextRetry = nextRetryRaw == null
          ? null
          : DateTime.tryParse(nextRetryRaw);
      if (nextRetry != null && nextRetry.isAfter(now)) {
        remaining.add(item);
        continue;
      }
      try {
        await send(
          item['session_id'] as String,
          item['client_id'] as String,
        );
        flushed++;
      } catch (_) {
        final attempts = ((item['attempts'] as num?)?.toInt() ?? 0) + 1;
        final delaySeconds = min(300, 1 << min(attempts, 8));
        remaining.add({
          ...item,
          'attempts': attempts,
          'next_retry_at':
              now.add(Duration(seconds: delaySeconds)).toIso8601String(),
        });
      }
    }
    await _save(remaining);
    return flushed;
  }
}
