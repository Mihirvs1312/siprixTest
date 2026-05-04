import 'package:flutter/foundation.dart';

class AppSettings {
  AppSettings._();

  // static const String baseUrlSip = 'https://beta-sip.teamlocus.com';
  // static const String baseUrlSip = 'http://192.168.75.174:3000';

  static const String baseUrlSip = 'https://beta-sip-api-notify.teamlocus.com';

  /// When true, Sip HTTP calls are traced (debug console and optional [LogsModel] UI).
  static bool enableApiLog = kDebugMode;
}
