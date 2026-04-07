import 'dart:io';

//import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:siprix_voip_sdk/accounts_model.dart';
import 'package:siprix_voip_sdk/siprix_voip_sdk.dart';

import 'firebase_util.dart';
import 'sip_repository.dart';

/// Accounts list model (contains app level code of managing accіounts)
class AppAccountsModel extends AccountsModel {
  AppAccountsModel([this._logs]) : super(_logs);
  final ILogsModel? _logs;

  static String get _deviceType {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return Platform.operatingSystem;
  }

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

      final result = await SipRepository.saveToken({
        'extension': extension,
        'device_type': _deviceType,
        'token': token,
      });
      if (result.status != 'ok') {
        _logs?.print('Save token API: ${result.message ?? result.status}');
      }
    } catch (e) {
      _logs?.print('Save token failed: $e');
    }
  }

  @override
  Future<void> addAccount(AccountModel acc, {bool saveChanges=true}) async {
    String? token;
    if(Platform.isIOS) {
      token = await SiprixVoipSdk().getPushKitToken();//iOS - get PushKit VoIP token
    }else if(Platform.isAndroid) {
     // token = await FirebaseMessaging.instance.getToken();//Android - get Firebase token
    }

    //When resolved - put token into SIP REGISTER request
    if(token != null) {
      _logs?.print('AddAccount with push token: $token');
      acc.xheaders = {"X-Token" : token};//Put token into separate header
      //acc.xContactUriParams = {"X-Token" : token};//put token into ContactUriParams
    }
    final ext = acc.sipExtension;
      if (ext.isNotEmpty) {
        await _saveTokenToBackend(ext);
      }
    await super.addAccount(acc, saveChanges:saveChanges);
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