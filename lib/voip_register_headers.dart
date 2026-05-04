import 'dart:io';
import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kPrefsDeviceIdFallback = 'voip_install_device_id';

/// SIP REGISTER extra headers: platform label and stable device/installation id.
Future<Map<String, String>> buildVoipRegisterHeaders({
  String? pushToken,
  Map<String, String>? mergeFrom,
}) async {
  final headers = <String, String>{
    ...?mergeFrom,
    'X-Device-Type': voipDeviceTypeLabel(),
    'X-Device-Id': await resolveVoipDeviceId(),
  };
  if (pushToken != null && pushToken.isNotEmpty) {
    headers['X-Token'] = pushToken;
  }
  return headers;
}

String voipDeviceTypeLabel() {
  if (Platform.isIOS) return 'ios';
  if (Platform.isAndroid) return 'android';
  return Platform.operatingSystem;
}

String? _cachedDeviceId;

Future<String> resolveVoipDeviceId() async {
  final cached = _cachedDeviceId;
  if (cached != null && cached.isNotEmpty) return cached;

  try {
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      const androidIdPlugin = AndroidId();
      final id = await androidIdPlugin.getId() ?? '';
      if (id.isNotEmpty) {
        _cachedDeviceId = id;
        return id;
      }
    } else if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      final id = info.identifierForVendor ?? '';
      if (id.isNotEmpty) {
        _cachedDeviceId = id;
        return id;
      }
    }
  } catch (_) {
    // Fall through to prefs-backed id.
  }

  final prefs = await SharedPreferences.getInstance();
  var fallback = prefs.getString(_kPrefsDeviceIdFallback);
  if (fallback == null || fallback.isEmpty) {
    fallback =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    await prefs.setString(_kPrefsDeviceIdFallback, fallback);
  }
  _cachedDeviceId = fallback;
  return fallback;
}
