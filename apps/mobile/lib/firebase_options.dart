// Placeholder — replace by running:
//   dart pub global activate flutterfire_cli
//   flutterfire configure
// See docs/fcm-setup.md
//
// Until then DefaultFirebaseOptions.isConfigured is false and FCM is a no-op
// so web/local builds work without google-services.json.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  /// Flip to true after pasting real values from FlutterFire.
  static const bool isConfigured = false;

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'REPLACE',
    appId: 'REPLACE',
    messagingSenderId: 'REPLACE',
    projectId: 'REPLACE',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'REPLACE',
    appId: 'REPLACE',
    messagingSenderId: 'REPLACE',
    projectId: 'REPLACE',
    storageBucket: 'REPLACE',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'REPLACE',
    appId: 'REPLACE',
    messagingSenderId: 'REPLACE',
    projectId: 'REPLACE',
    storageBucket: 'REPLACE',
    iosBundleId: 'org.swamysharnam.swamySharanam',
  );
}
