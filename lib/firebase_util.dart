import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirebaseUtil {
  FirebaseUtil._();

  static const String _prefsKeyFcm = 'fcm_token_cached';

  static Future<String?> getStoredFcmToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeyFcm);
  }

  static Future<void> _setStoredFcmToken(String? token) async {
    if (token == null || token.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyFcm, token);
  }

  /// Ensures Firebase is initialized, then returns the FCM registration token.
  static Future<String?> generateFcmToken() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    final token = await FirebaseMessaging.instance.getToken();
    await _setStoredFcmToken(token);
    return token;
  }
}
