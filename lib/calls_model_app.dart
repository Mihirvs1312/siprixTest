// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:siprix_voip_sdk/calls_model.dart';
import 'package:siprix_voip_sdk/cdrs_model.dart';
import 'package:siprix_voip_sdk/siprix_voip_sdk.dart';

import 'callkit_incoming_fallback.dart';

/// Helper class used to keep different ids of the same call
class CallMatcher {
  static const String kStubPushHint = 'stubPushHint';

  ///Id assigned by CallKit when push notification received
  String callkit_CallUUID;
  ///Some data received in push payload (put by remote SIP server)
  ///This field is using to identify/match push and SIP calls
  /// each aplication may use its own way
  String push_Hint;
  ///Id assigned by library when SIP INVITE received
  int    sip_CallId;
  ///Timestamp when this item has been created
  DateTime timestamp = DateTime.now();

  CallMatcher(this.callkit_CallUUID, this.push_Hint, [this.sip_CallId=0]);
}


/// Calls list model (contains app level code of managing calls)
/// Copy this class into own app and redesign as you need
class AppCallsModel extends CallsModel {
  AppCallsModel(IAccountsModel accounts, [this._logs, CdrsModel? cdrs]) :
    super(accounts, _logs, cdrs);

  final ILogsModel? _logs;
  final List<CallMatcher> _callMatchers=[];//iOS PushKit specific impl
  Timer? _pushNotifTimer;

  /// Accepts the first incoming call that is still ringing (list order).
  Future<void> acceptFirstRingingIncoming() async {
    for (final c in this) {
      if (!c.isIncoming || c.state != CallState.ringing) continue;
      try {
        await c.accept(c.hasVideo);
      } catch (e) {
        _logs?.print('acceptFirstRingingIncoming callId:${c.myCallId} $e');
      }
      return;
    }
  }

  /// Rejects every incoming call that is still ringing.
  Future<void> rejectAllRingingIncoming() async {
    final targets = <CallModel>[];
    for (final c in this) {
      if (!c.isIncoming || c.state != CallState.ringing) continue;
      targets.add(c);
    }
    for (final c in targets) {
      try {
        await c.reject();
      } catch (e) {
        _logs?.print('rejectAllRingingIncoming callId:${c.myCallId} $e');
      }
    }
  }

   /// Handle iOS Pushkit notification received by library (parse payload, update CallKit window, store data from push payload)
  @override
  void onIncomingPush(String callkit_CallUUID, Map<String, dynamic> pushPayload) {
    _logs?.print('onIncomingPush callkit_CallUUID:$callkit_CallUUID $pushPayload');
    //Get data from 'pushPayload', which contains app specific details
    Map<String, dynamic>? apsPayload;
    try {
      apsPayload = Map<String, dynamic>.from(pushPayload["aps"]);
    } catch (err) {
      _logs?.print('onIncomingPush get payload err: $err');
    }

    // String pushHint = apsPayload?["pushHint"] ?? CallMatcher.kStubPushHint;
    String pushHint = pushPayload?["caller_number"];
    // Docs/curl samples use callerId; some servers send callerNumber.
    final dynamic handleRaw = pushPayload?["caller_number"] ?? pushPayload?["callerNumber"] ?? pushPayload?["callerId"];
    String genericHandle = handleRaw?.toString() ?? "genericHandle";
    final dynamic nameRaw = pushPayload?["caller_number"];
    String localizedCallerName = nameRaw?.toString() ?? "callerName";
    bool withVideo = pushPayload?["withVideo"] ?? false;
    int? sipCallId = null;

    int index = _callMatchers.indexWhere((c) => c.push_Hint == pushHint);
    if(index!=-1) {
      //Case: SIP already received
      sipCallId = _callMatchers[index].sip_CallId;
    }
    else {
      //Case: SIP hasn't received yet
      _callMatchers.add(CallMatcher(callkit_CallUUID, pushHint));
    }

    //Update CallKit
    SiprixVoipSdk().updateCallKitCallDetails(callkit_CallUUID, sipCallId, localizedCallerName, genericHandle, withVideo);

    //Start timer which cleanups CallKit calls when SIP not received
    _startPushNotifTimer();
  }

  String? getExtensionNumber(String sipString) {
  // Regular expression to match digits after 'sip:' and before '@'
  RegExp regExp = RegExp(r'sip:(\d+)@');
  Match? match = regExp.firstMatch(sipString);

  // If match found, return the captured group (extension number)
  if (match != null) {
    return match.group(1);
  }
  return null; // Return null if no extension number is found
}

  /// RFC 4122 version 4 UUID for synthetic CallKit / notification correlation.
  static String _randomCallUuidV4() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20, 32)}';
  }

  @override
  void onIncomingSip(int callId, int accId, bool withVideo, String hdrFrom, String hdrTo) async {
    super.onIncomingSip(callId, accId, withVideo, hdrFrom, hdrTo);

    try {
      final String? fullSip =
          await SiprixVoipSdk().getSipHeader(callId, '');
      final String buf = 'onIncomingSip SIP message callId:$callId accId:$accId '
          'withVideo:$withVideo hdrFrom:$hdrFrom hdrTo:$hdrTo\n'
          '${fullSip != null && fullSip.isNotEmpty ? fullSip : "(no data — empty hdrName not supported or INVITE not exposed)"}';
      _logs?.print(buf);
      print(buf);
    } catch (e, st) {
      _logs?.print('onIncomingSip getSipHeader full message failed: $e\n$st');
      print('onIncomingSip getSipHeader full message failed: $e');
    }

    if(Platform.isIOS) {
      // Match CallKit push flow with SIP INVITE using a shared hint (PBX should set X-PushHint to match push payload).
      
      // String pushHint = await SiprixVoipSdk().getSipHeader(callId, "X-PushHint")?? CallMatcher.kStubPushHint;
      String? extensionNumber = getExtensionNumber(hdrFrom);
      print('extensionNumber: $extensionNumber');
      String pushHint = extensionNumber ?? CallMatcher.kStubPushHint;
      _logs?.print('onIncomingSip callId:$callId pushHint:$pushHint hdrFrom:$hdrFrom hdrTo:$hdrTo');

      //Searchs is there CallKit call which matches this one
      int index = _callMatchers.indexWhere((c) => c.push_Hint == pushHint);
      if(index != -1) {
        _logs?.print('onIncomingSip match call:${_callMatchers[index].callkit_CallUUID} <=> $callId');

        //Update CallKit with 'callId'
        _callMatchers[index].sip_CallId = callId;
        SiprixVoipSdk().updateCallKitCallDetails(_callMatchers[index].callkit_CallUUID, callId, null, null, null);
      }
      else {
        //Case - there is no CallKit call (push notif hasn't received yet)
        final String stubCallUuid = _randomCallUuidV4();
        _callMatchers.add(CallMatcher(stubCallUuid, pushHint, callId));
        final String nameCaller = CallsModel.parseDisplayName(hdrFrom);
        final String handle = CallsModel.parseExt(hdrFrom);
        await showIncomingSipFallbackCallKit(
          id: stubCallUuid,
          sipCallId: callId,
          withVideo: withVideo,
          nameCaller:
              nameCaller.isNotEmpty ? nameCaller : (extensionNumber ?? 'Caller'),
          handle: handle.isNotEmpty ? handle : pushHint,
        );
      }
    }
  }

  @override
  void onTerminated(int callId, int statusCode) {
    super.onTerminated(callId, statusCode);

    if(Platform.isIOS) {
      int index =_callMatchers.indexWhere((c) => c.sip_CallId==callId);
      if(index != -1) {
        final uuid = _callMatchers[index].callkit_CallUUID;
        _logs?.print('onTerminated removed call:$uuid');
        _callMatchers.removeAt(index);
        if (uuid.isNotEmpty) {
          FlutterCallkitIncoming.endCall(uuid).catchError((_) {});
        }
      }
    }
  }

  void _startPushNotifTimer() {
    if(_pushNotifTimer != null) return;

    const Duration kTimerDelay = Duration(seconds: 1);
    const Duration kEndCallDelay = Duration(seconds: 15);

    _pushNotifTimer = Timer.periodic(kTimerDelay, (Timer timer) {
      DateTime now = DateTime.now();
      for(int i = _callMatchers.length-1; i>=0; --i) {
        //End CallKit call when SIP INVITE hasn't received during kEndCallDelay
        CallMatcher cm = _callMatchers[i];
        if((cm.sip_CallId==0) && now.difference(cm.timestamp) > kEndCallDelay) {
          SiprixVoipSdk().endCallKitCall(cm.callkit_CallUUID);
          if (cm.callkit_CallUUID.isNotEmpty) {
            FlutterCallkitIncoming.endCall(cm.callkit_CallUUID).catchError((_) {});
          }
          _callMatchers.removeAt(i);
        }
      }

      if(_callMatchers.isEmpty) {
        _pushNotifTimer?.cancel();
        _pushNotifTimer = null;
      }
    });
  }
}

/*
class AppCdrsModel extends CdrsModel {
  AppCdrsModel() : super(maxItems:0);

  @override
  void add(CallModel c) {
    CdrModel cdr = CdrModel.fromCall(c.myCallId, c.accUri, c.remoteExt, c.isIncoming, c.hasVideo);
    cdrItems.insert(0, cdr);

    notifyListeners();
  }

  @override
  void setConnected(int callId, String from, String to, bool hasVideo) {
    int index = cdrItems.indexWhere((c) => c.myCallId==callId);
    if(index == -1) return;

    CdrModel cdr = cdrItems[index];
    cdr.hasVideo = hasVideo;
    cdr.connected = true;
    notifyListeners();
  }

  @override
  void setTerminated(int callId, int statusCode, String displName, String duration) {
    int index = cdrItems.indexWhere((c) => c.myCallId==callId);
    if(index == -1) return;

    CdrModel cdr = cdrItems[index];
    cdr.displName = displName;
    cdr.statusCode = statusCode;
    cdr.duration = duration;

    notifyListeners();

    Future.delayed(Duration.zero, () {
      storeData();
    });
  }

  @override
  void remove(int index) {
    if((index>=0)&&(index < length)) {
      cdrItems.removeAt(index);
      notifyListeners();
    }
  }

  void loadSavedData() {
    //TODO own impl here
  }

  void storeData() {
    //TODO own impl here
  }
}*/