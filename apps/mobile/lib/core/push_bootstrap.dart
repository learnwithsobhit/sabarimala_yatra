import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import '../firebase_options.dart';

/// Background isolate handler — must be top-level.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM background: ${message.messageId} ${message.data}');
}

String _platformLabel() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.android:
      return 'android';
    default:
      return 'other';
  }
}

/// Registers FCM token with the API when Firebase is configured.
/// No-ops on web and when options are placeholders.
class PushBootstrap {
  PushBootstrap(this._api);

  final ApiClient _api;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    if (kIsWeb) {
      debugPrint('FCM skipped on web');
      return;
    }

    if (!DefaultFirebaseOptions.isConfigured) {
      debugPrint('FCM skipped — see docs/fcm-setup.md');
      return;
    }

    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('FCM permission denied');
        return;
      }

      FirebaseMessaging.onMessage.listen((msg) {
        debugPrint('FCM foreground: ${msg.notification?.title}');
      });

      final token = await messaging.getToken();
      if (token != null && _api.token != null) {
        await _register(token);
      }

      messaging.onTokenRefresh.listen((t) {
        if (_api.token != null) {
          _register(t);
        }
      });
    } catch (e) {
      debugPrint('FCM init failed (ok without Firebase): $e');
    }
  }

  Future<void> registerIfLoggedIn() async {
    if (kIsWeb || !DefaultFirebaseOptions.isConfigured || _api.token == null) {
      return;
    }
    try {
      if (Firebase.apps.isEmpty) {
        await start();
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _register(token);
    } catch (e) {
      debugPrint('FCM register skipped: $e');
    }
  }

  Future<void> _register(String fcmToken) async {
    try {
      await _api.post(
        '/devices/register',
        body: {'fcm_token': fcmToken, 'platform': _platformLabel()},
      );
      debugPrint('FCM token registered');
    } catch (e) {
      debugPrint('FCM token register failed: $e');
    }
  }
}
