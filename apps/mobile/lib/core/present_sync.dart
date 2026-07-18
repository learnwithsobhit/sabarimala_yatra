import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'present_queue.dart';
import 'trip_pack_store.dart';

/// Shared Present mark + offline queue flush used by Home and Count.
class PresentSync {
  PresentSync({
    PresentQueue? queue,
    TripPackStore? pack,
    Uuid? uuid,
  })  : _queue = queue ?? PresentQueue(),
        _pack = pack ?? TripPackStore(),
        _uuid = uuid ?? const Uuid();

  final PresentQueue _queue;
  final TripPackStore _pack;
  final Uuid _uuid;

  Future<int> flush(ApiClient api) {
    return _queue.flush((sessionId, clientId) async {
      await api.post(
        '/count/sessions/$sessionId/present',
        body: {'client_id': clientId},
      );
    });
  }

  Future<void> cacheOpenSession(Map<String, dynamic>? session) async {
    if (session == null) {
      await _pack.save({
        'open_count_session': null,
        'open_count_session_id': null,
      });
      return;
    }
    await _pack.save({
      'open_count_session': session,
      'open_count_session_id': session['id']?.toString(),
    });
  }

  Future<Map<String, dynamic>?> cachedOpenSession() async {
    final pack = await _pack.load();
    final session = pack?['open_count_session'];
    if (session is Map) {
      return Map<String, dynamic>.from(session);
    }
    final id = pack?['open_count_session_id']?.toString();
    if (id == null || id.isEmpty) return null;
    return {'id': id};
  }

  /// Marks Present online, or queues offline. Returns `queued` when offline.
  Future<({bool queued, String sessionId})> markPresent(
    ApiClient api, {
    required String sessionId,
  }) async {
    final clientId = _uuid.v4();
    try {
      await api.post(
        '/count/sessions/$sessionId/present',
        body: {'client_id': clientId},
      );
      await _queue.remove(sessionId);
      return (queued: false, sessionId: sessionId);
    } catch (_) {
      await _queue.enqueue(sessionId: sessionId, clientId: clientId);
      return (queued: true, sessionId: sessionId);
    }
  }

  Future<bool> isQueued(String sessionId) => _queue.isQueued(sessionId);
}
