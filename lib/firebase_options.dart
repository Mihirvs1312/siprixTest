import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

/// ---------------------------------------------------------------
/// PLACEHOLDER — Replace this file by running:
///   flutterfire configure
/// This will auto-generate the correct values for your project.
/// ---------------------------------------------------------------
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // TODO: Replace with your actual Firebase project values
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCqdzzsf47rqUAeIfLoWMzsU6V7bomiY4w',
    appId: '1:80031395699:android:532902cbacfca22b7a5f06',
    messagingSenderId: '80031395699',
    projectId: 'teamlocus-sip',
    storageBucket: 'teamlocus-sip.firebasestorage.app',
  );

  // TODO: Replace with your actual Firebase project values
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR-IOS-API-KEY',
    appId: 'YOUR-IOS-APP-ID',
    messagingSenderId: 'YOUR-SENDER-ID',
    projectId: 'YOUR-PROJECT-ID',
    storageBucket: 'YOUR-PROJECT-ID.firebasestorage.app',
    iosBundleId: 'com.app.teamlocusSip',
  );
}
