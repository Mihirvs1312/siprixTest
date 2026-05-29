import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:siprix_voip_sdk/accounts_model.dart';
import 'package:siprix_voip_sdk/logs_model.dart';
import 'package:siprix_voip_sdk/siprix_voip_sdk.dart';

import 'voip_ios_config.dart';

Future<void>? _siprixInitFuture;

/// Single entry for Siprix native init (foreground boot, VoIP push, FCM background).
Future<void> initializeSiprixApp({LogsModel? logs}) async {
  if (_siprixInitFuture != null) {
    return _siprixInitFuture!;
  }
  final future = _initializeSiprixAppOnce(logs);
  _siprixInitFuture = future;
  try {
    await future;
  } catch (e) {
    _siprixInitFuture = null;
    rethrow;
  }
}

Future<void> _initializeSiprixAppOnce(LogsModel? logs) async {
  debugPrint('Initialize siprix');
  final iniData = InitData()
    ..logLevelFile = LogLevel.debug
    ..logLevelIde = LogLevel.info
    ..license =
        'LicensedTo[DeepFoodsInc]_Platforms[WIN_ANDR_IOS_OSX_LIN]_Features[V_MC_MA_MSG]_SupportTill[20260718]_UpdatesTill[20260718]_Key[MC0CFEJxwm005R6H9wtzpH3irCTyGx3rAhUAwjVi3+UwgFgmA1YtHkRqjH85NuA=]';

  if (Platform.isIOS) {
    iniData.enableCallKit = true;
    iniData.enablePushKit = kIosUsePushKit;
    iniData.unregOnDestroy = false;
    debugPrint(
        '[PushKit] iOS init: enablePushKit=${iniData.enablePushKit} enableCallKit=${iniData.enableCallKit}');
  }
  if (Platform.isAndroid) {
    iniData.listenTelState = true;
    iniData.listenVolChange = true;
  }

  await SiprixVoipSdk().initialize(iniData, logs);

  if (Platform.isIOS && kIosUsePushKit) {
    try {
      final token = await SiprixVoipSdk().getPushKitToken();
      debugPrint('[PushKit] Connected/initialized. token: ${token ?? "null"}');
    } catch (e) {
      debugPrint('[PushKit] Initialized, but token fetch failed: $e');
    }
  }
}
