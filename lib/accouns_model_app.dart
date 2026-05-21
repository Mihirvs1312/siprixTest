import 'dart:io';

//import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:mobile_device_identifier/mobile_device_identifier.dart';
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

  /// Same id as SIP `Contact` / push registration (`device_id` in API payloads).
  ///
  /// Uses [MobileDeviceIdentifier] on Android/iOS (persisted across reinstalls per
  /// the plugin). Replaces any previously stored random UUID on first successful read.
  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    if (Platform.isAndroid || Platform.isIOS) {
      final id = await MobileDeviceIdentifier().getDeviceId();
      if (id != null && id.isNotEmpty) {
        await prefs.setString(_deviceIdPrefsKey, id);
        return id;
      }
      throw StateError('Could not obtain mobile device identifier.');
    }
    final existing = prefs.getString(_deviceIdPrefsKey);
    if (existing != null && existing.isNotEmpty) return existing;
    throw UnsupportedError(
      'getOrCreateDeviceId is only supported on Android and iOS.',
    );
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
    if (Platform.isIOS) {
      try {
        token = await SiprixVoipSdk().getPushKitToken();
        print('[PushKit] addAccount fetched token: ${token ?? "null"}');
        _logs?.print('[PushKit] addAccount fetched token: ${token ?? "null"}');
      } catch (e) {
        _logs?.print(
            '[PushKit] addAccount getPushKitToken failed (account still saved): $e');
      }
    } else if (Platform.isAndroid) {
     // token = await FirebaseMessaging.instance.getToken();//Android - get Firebase token
    }

    // RFC 8599 Contact params for push correlation (pn-prid / pn-provider). Values must match
    // what YOUR SIP server expects; many stacks use `apns`/`fcm` instead of `ios`/`android`.
    //
    // IMPORTANT: `_getOrCreateDeviceId()` must not abort registration — if it throws (simulator,
    // permission, plugin failure), skipping params still lets the account register.
    try {
      if (Platform.isIOS || Platform.isAndroid) {
        final deviceId = await _getOrCreateDeviceId();
        acc.xContactUriParams = {
          'pn-prid': deviceId,
          // Must match what your SIP/PBX expects (RFC 8599 often uses apns/fcm).
          'pn-provider': _deviceType,
        };
      }
    } catch (e, st) {
      _logs?.print(
          'xContactUriParams skipped (registration continues): $e\n$st');
    }

    //When resolved - put token into SIP REGISTER request
    if (token != null) {
      _logs?.print('AddAccount with push token: $token');
      acc.xheaders = {'X-Token': token};
    }
    // [AccountsModel.loadFromJson] replays each saved account via [addAccount(...,
    // saveChanges: false)]. Only the real "Add account" flow uses saveChanges:true,
    // so we register the push token with the backend once per user add — not on every
    // cold start / push wake / reload.
    final ext = acc.sipExtension;
    if (saveChanges && ext.isNotEmpty) {
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
