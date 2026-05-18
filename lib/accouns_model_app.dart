import 'dart:io';
import 'dart:math';

//import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:siprix_voip_sdk/accounts_model.dart';
import 'package:siprix_voip_sdk/siprix_voip_sdk.dart';

import 'firebase_util.dart';
import 'sip_repository.dart';

/// Accounts list model (contains app level code of managing accіounts)
class AppAccountsModel extends AccountsModel {
  AppAccountsModel([this._logs]) : super(_logs);
  final ILogsModel? _logs;

  static const _deviceIdPrefsKey = 'siprix_app_device_id';

  static String get _deviceType {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return Platform.operatingSystem;
  }

  /// RFC 4122 version 4 UUID (random), 128 bits from [Random.secure].
  static String _newDeviceId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    const hex = '0123456789abcdef';
    String h(int x) => '${hex[x >> 4]}${hex[x & 0xf]}';
    return '${h(b[0])}${h(b[1])}${h(b[2])}${h(b[3])}-'
        '${h(b[4])}${h(b[5])}-'
        '${h(b[6])}${h(b[7])}-'
        '${h(b[8])}${h(b[9])}-'
        '${h(b[10])}${h(b[11])}${h(b[12])}${h(b[13])}${h(b[14])}${h(b[15])}';
  }

  /// Same id as SIP `Contact` / push registration (`device_id` in API payloads).
  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdPrefsKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _newDeviceId();
    await prefs.setString(_deviceIdPrefsKey, id);
    return id;
  }

  Future<String> _getOrCreateDeviceId() => getOrCreateDeviceId();

  Future<void> _saveTokenToBackend(String extension) async {
    try {
      final String? token;
      if (Platform.isIOS) {
        token = await SiprixVoipSdk().getPushKitToken();
      } else if (Platform.isAndroid) {
        token = await FirebaseUtil.getStoredFcmToken() ??
            await FirebaseUtil.generateFcmToken();
      } else {
        token = await FirebaseUtil.getStoredFcmToken() ??
            await FirebaseUtil.generateFcmToken();
      }
      if (token == null) return;

      final deviceId = await _getOrCreateDeviceId();
      final result = await SipRepository.saveToken({
        'extension': extension,
        'device_type': _deviceType,
        'device_id': deviceId,
        'token': token,
      });
      if (result.status != 'ok') {
        _logs?.print('Save token API: ${result.message ?? result.status}');
      }
    } catch (e) {
      _logs?.print('Save token failed: $e');
    }
  }

  Future<void> _deleteTokenFromBackend(String extension) async {
    try {
      if (extension.isEmpty) return;
      final deviceId = await _getOrCreateDeviceId();
      final result = await SipRepository.deleteToken({
        'extension': extension,
        'device_id': deviceId,
      });
      if (result.status != 'ok') {
        _logs?.print('Delete token API: ${result.message ?? result.status}');
      }
    } catch (e) {
      _logs?.print('Delete token failed: $e');
    }
  }

  @override
  Future<void> deleteAccount(int index) async {
    final ext = this[index].sipExtension;
    await _deleteTokenFromBackend(ext);
    await super.deleteAccount(index);
  }

  @override
  Future<void> addAccount(AccountModel acc, {bool saveChanges=true}) async {
    String? token;
    if(Platform.isIOS) {
      token = await SiprixVoipSdk().getPushKitToken();//iOS - get PushKit VoIP token
      print('[PushKit] addAccount fetched token: ${token ?? "null"}');
      _logs?.print('[PushKit] addAccount fetched token: ${token ?? "null"}');
    }else if(Platform.isAndroid) {
     // token = await FirebaseMessaging.instance.getToken();//Android - get Firebase token
    }

    final deviceId = await _getOrCreateDeviceId();
    acc.xContactUriParams = {
      'pn-prid': deviceId,
      'pn-provider': _deviceType,
    };

    //When resolved - put token into SIP REGISTER request
    if (token != null) {
      _logs?.print('AddAccount with push token: $token');
      acc.xheaders = {'X-Token': token};
    }
    final ext = acc.sipExtension;
    if (ext.isNotEmpty) {
      await _saveTokenToBackend(ext);
    }
    await super.addAccount(acc, saveChanges: saveChanges);
  }

  /// Awaits each native [registerAccount] call. The base [AccountsModel.refreshRegistration]
  /// does not await, which can surface unhandled [PlatformException]s on Android.
  @override
  Future<void> refreshRegistration() async {
    try {
      for (var i = 0; i < length; i++) {
        final acc = this[i];
        final int expireSec = (acc.expireTime == null) ? 300 : acc.expireTime!;
        if (expireSec != 0) {
          await SiprixVoipSdk().registerAccount(acc.myAccId, expireSec);
        }
      }
    } on PlatformException catch (err) {
      _logs?.print(
          'Can\'t refresh accounts registration: ${err.code} ${err.message}');
      return Future.error(
        err.message == null ? err.code : err.message!,
      );
    }
  }

}
