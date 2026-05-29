// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:siprix_voip_sdk/calls_model.dart';
import 'package:siprix_voip_sdk/cdrs_model.dart';
import 'package:siprix_voip_sdk/siprix_voip_sdk.dart';

import 'callkit_incoming_fallback.dart';
import 'voip_ios_config.dart';

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
  // final Set<int> _callStartLogged = {};
  //
  // CallModel? _callBySipId(int sipCallId) {
  //   for (final c in this) {
  //     if (c.myCallId == sipCallId) return c;
  //   }
  //   return null;
  // }

  void _endCallKitForSipCallId(int sipCallId) {
    if (!Platform.isIOS) return;
    // Remove every matcher for this SIP id (avoids duplicate rows after reconnects).
    for (var i = _callMatchers.length - 1; i >= 0; i--) {
      if (_callMatchers[i].sip_CallId != sipCallId) continue;
      final String uuid = _callMatchers[i].callkit_CallUUID;
      _callMatchers.removeAt(i);
      if (uuid.isEmpty) continue;
      SiprixVoipSdk().endCallKitCall(uuid);
      FlutterCallkitIncoming.endCall(uuid).catchError((_) {});
    }
  }

  /// When the SIP stack has no calls left, tear down any stray CallKit UI so the next VoIP push can present.
  void _resetIosCallKitWhenNoSipCalls() {
    if (!Platform.isIOS) return;
    if (isNotEmpty) return;

    for (final m in List<CallMatcher>.from(_callMatchers)) {
      if (m.callkit_CallUUID.isEmpty) continue;
      SiprixVoipSdk().endCallKitCall(m.callkit_CallUUID);
      FlutterCallkitIncoming.endCall(m.callkit_CallUUID).catchError((_) {});
    }
    _callMatchers.clear();
    _pushNotifTimer?.cancel();
    _pushNotifTimer = null;
    FlutterCallkitIncoming.endAllCalls().catchError((_) {});
  }

  /// Resolve SIP call id from our PushKit / fallback bookkeeping (for CallKit events).
  // int? findSipCallIdByCallKitUuid(String? uuid) {
  //   if (uuid == null || uuid.isEmpty) return null;
  //   for (final m in _callMatchers) {
  //     if (m.callkit_CallUUID == uuid) return m.sip_CallId;
  //   }
  //   return null;
  // }
  //
  // /// After the user declines or ends from CallKit / VoIP incoming UI: tear down native + plugin UI,
  // /// keep [_callMatchers] in sync, and hide Android full-screen call notification.
  // void syncAfterCallKitUserHangup(int sipCallId, String? callKitUuid) {
  //   if (Platform.isIOS) {
  //     if (sipCallId > 0) {
  //       _endCallKitForSipCallId(sipCallId);
  //     } else if (callKitUuid != null && callKitUuid.isNotEmpty) {
  //       for (var i = _callMatchers.length - 1; i >= 0; i--) {
  //         if (_callMatchers[i].callkit_CallUUID != callKitUuid) continue;
  //         _callMatchers.removeAt(i);
  //       }
  //     }
  //     if (callKitUuid != null && callKitUuid.isNotEmpty) {
  //       SiprixVoipSdk().endCallKitCall(callKitUuid);
  //       FlutterCallkitIncoming.endCall(callKitUuid).catchError((_) {});
  //     }
  //     _resetIosCallKitWhenNoSipCalls();
  //   } else if (Platform.isAndroid) {
  //     if (callKitUuid != null && callKitUuid.isNotEmpty) {
  //       FlutterCallkitIncoming.endCall(callKitUuid).catchError((_) {});
  //       hideAndroidCallkitIncomingForId(callKitUuid);
  //     }
  //     FlutterCallkitIncoming.endAllCalls().catchError((_) {});
  //   }
  // }

  /// Accepts the first incoming call that is still ringing (list order).
  Future<void> acceptFirstRingingIncoming() async {
    for (final c in this) {
      if (!c.isIncoming || c.state != CallState.ringing) continue;
      try {
        // In-app answer should also dismiss any matching iOS CallKit row.
        _endCallKitForSipCallId(c.myCallId);
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
        // In-app reject should also dismiss any matching iOS CallKit row.
        _endCallKitForSipCallId(c.myCallId);
        await c.reject();
      } catch (e) {
        _logs?.print('rejectAllRingingIncoming callId:${c.myCallId} $e');
      }
    }
  }

  /// Normalise a caller number used as `push_Hint` so the VoIP push side and the
  /// SIP INVITE side match even when one carries a leading `+`/spaces and the
  /// other doesn't. Twilio E.164 numbers (e.g. `+16467606640`) and PBX-stripped
  /// variants (e.g. `16467606640`) must collapse to the same key.
  ///
  /// Returns the digits-only form, or the trimmed input when no digits exist
  /// (so things like the stub hint stay intact).
  static String _normalizePhoneHint(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed == CallMatcher.kStubPushHint) return trimmed;
    final String digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? trimmed : digits;
  }

  /// `type` values the backend sends for a real incoming ring. Any other
  /// recognised end/cancel/missed marker is dismissed in [onIncomingPush].
  static const Set<String> _kRingingPushTypes = <String>{
    'start', 'incoming', 'invite', 'ring', 'ringing', 'call',
  };
  static const Set<String> _kEndPushTypes = <String>{
    'end', 'ended', 'end_call', 'endcall',
    'cancel', 'cancelled', 'canceled', 'cancel_call',
    'missed', 'missed_call', 'miss',
    'bye', 'terminated', 'terminate',
    'hangup', 'hang_up',
    'reject', 'rejected', 'decline', 'declined',
  };

  bool _isNonRingingPush(Map<String, dynamic> payload) {
    String norm(dynamic v) => v?.toString().trim().toLowerCase() ?? '';

    final candidates = <String>[
      norm(payload['type']),
      norm(payload['event']),
      norm(payload['action']),
      norm(payload['state']),
      norm(payload['call_status']),
      norm(payload['callStatus']),
    ];

    Map<String, dynamic>? nested;
    final nestedRaw = payload['data'] ?? payload['payload'];
    if (nestedRaw is Map) {
      nested = Map<String, dynamic>.from(nestedRaw);
      candidates.addAll([
        norm(nested['type']),
        norm(nested['event']),
        norm(nested['action']),
        norm(nested['state']),
      ]);
    }

    try {
      final aps = payload['aps'];
      if (aps is Map) {
        candidates.add(norm(aps['alert']));
      }
    } catch (_) {}

    for (final c in candidates) {
      if (c.isEmpty) continue;
      if (_kRingingPushTypes.contains(c)) return false;
      if (_kEndPushTypes.contains(c)) return true;
    }

    bool truthy(dynamic v) =>
        v == true || v == 1 || norm(v) == 'true' || norm(v) == '1';
    if (truthy(payload['endCall']) ||
        truthy(payload['end_call']) ||
        truthy(payload['isEnd']) ||
        truthy(payload['is_end']) ||
        truthy(payload['ended']) ||
        truthy(payload['cancelled']) ||
        truthy(payload['canceled'])) {
      return true;
    }
    if (payload['incoming'] == false) return true;

    return false;
  }

  void _dismissNonRingingPush(
      String callkit_CallUUID, Map<String, dynamic> pushPayload) {
    if (callkit_CallUUID.isNotEmpty) {
      SiprixVoipSdk().endCallKitCall(callkit_CallUUID);
      FlutterCallkitIncoming.endCall(callkit_CallUUID).catchError((_) {});
    }

    final dynamic hintRaw = pushPayload['caller_number'] ??
        pushPayload['callerNumber'] ??
        pushPayload['callerId'];
    final String rawHint = hintRaw?.toString().trim() ?? '';
    // Same digits-only normalisation as the start/incoming push so end-call
    // pushes for Twilio (E.164 with leading `+`) also dismiss the right row.
    final String pushHint = _normalizePhoneHint(rawHint);

    for (var i = _callMatchers.length - 1; i >= 0; i--) {
      final m = _callMatchers[i];
      final bool matchUuid = m.callkit_CallUUID.isNotEmpty &&
          m.callkit_CallUUID == callkit_CallUUID;
      final bool matchHint =
          pushHint.isNotEmpty && m.push_Hint == pushHint;
      if (!matchUuid && !matchHint) continue;

      final String staleUuid = m.callkit_CallUUID;
      _callMatchers.removeAt(i);
      if (staleUuid.isNotEmpty && staleUuid != callkit_CallUUID) {
        SiprixVoipSdk().endCallKitCall(staleUuid);
        FlutterCallkitIncoming.endCall(staleUuid).catchError((_) {});
      }
    }

    if (_callMatchers.isEmpty) {
      _pushNotifTimer?.cancel();
      _pushNotifTimer = null;
    }
    _resetIosCallKitWhenNoSipCalls();
  }

  /// Handle iOS Pushkit notification received by library (parse payload, update CallKit window, store data from push payload)
  @override
  void onIncomingPush(String callkit_CallUUID, Map<String, dynamic> pushPayload) {
    _logs?.print('onIncomingPush callkit_CallUUID:$callkit_CallUUID $pushPayload');
    debugPrint('[PushKit] Incoming VoIP push received. uuid:$callkit_CallUUID payload:$pushPayload');
    print('[PushKit] Incoming VoIP push received. uuid:$callkit_CallUUID');

    // Backend sends a second VoIP push with type:"End" when the caller hangs up.
    // iOS requires Siprix to report every VoIP push as CallKit incoming — dismiss
    // those end/cancel pushes immediately so the receiver does not ring again.
    if (_isNonRingingPush(pushPayload)) {
      _logs?.print(
          'onIncomingPush: non-ringing push (type=${pushPayload["type"]}), dismissing CallKit $callkit_CallUUID');
      debugPrint(
          '[PushKit] Non-ringing push (type=${pushPayload["type"]}). Dismissing CallKit $callkit_CallUUID');
      _dismissNonRingingPush(callkit_CallUUID, pushPayload);
      return;
    }

    //Get data from 'pushPayload', which contains app specific details
    Map<String, dynamic>? apsPayload;
    try {
      apsPayload = Map<String, dynamic>.from(pushPayload["aps"]);
    } catch (err) {
      _logs?.print('onIncomingPush get payload err: $err');
    }

    // Same keys as onIncomingSip / PBX docs so PushKit row matches SIP INVITE.
    final dynamic hintRaw = pushPayload?["caller_number"] ??
        pushPayload?["callerNumber"] ??
        pushPayload?["callerId"];
    final String rawPushHint = hintRaw?.toString().trim() ?? '';
    // Normalise digits-only so Twilio "+16467606640" pushes match the SIP From
    // user-part "+16467606640" / "16467606640" reported by the PBX.
    String pushHint = _normalizePhoneHint(rawPushHint);
    if (pushHint.isEmpty) pushHint = CallMatcher.kStubPushHint;
    // Docs/curl samples use callerId; some servers send callerNumber.
    final dynamic handleRaw = pushPayload?["caller_number"] ?? pushPayload?["callerNumber"] ?? pushPayload?["callerId"];
    String genericHandle = handleRaw?.toString() ?? "genericHandle";
    final dynamic nameRaw = pushPayload?["caller_number"];
    String localizedCallerName = nameRaw?.toString() ?? "callerName";
    bool withVideo = pushPayload?["withVideo"] ?? false;
    int? sipCallId = null;

    int index = _callMatchers.indexWhere((c) => c.push_Hint == pushHint);
    if (index != -1) {
      // SIP may have shown fallback CallKit with a random UUID; PushKit always carries the real id.
      sipCallId = _callMatchers[index].sip_CallId;
      final existing = _callMatchers[index];
      final oldUuid = existing.callkit_CallUUID;
      if (oldUuid.isNotEmpty &&
          callkit_CallUUID.isNotEmpty &&
          oldUuid != callkit_CallUUID) {
        SiprixVoipSdk().endCallKitCall(oldUuid);
        FlutterCallkitIncoming.endCall(oldUuid).catchError((_) {});
        existing.callkit_CallUUID = callkit_CallUUID;
      } else if (callkit_CallUUID.isNotEmpty) {
        existing.callkit_CallUUID = callkit_CallUUID;
      }
    } else {
      _callMatchers.add(CallMatcher(callkit_CallUUID, pushHint));
    }

    //Update CallKit
    SiprixVoipSdk().updateCallKitCallDetails(callkit_CallUUID, sipCallId, localizedCallerName, genericHandle, withVideo);

    //Start timer which cleanups CallKit calls when SIP not received
    _startPushNotifTimer();
  }

  /// Extract the SIP URI user-part from a header value such as
  /// `"Twilio" <sip:+16467606640@pbx>;tag=...` or `<sip:6001@host>`.
  ///
  /// Previously this used `RegExp(r'sip:(\d+)@')` which only matched bare
  /// digits — so Twilio E.164 numbers (`sip:+16467606640@...`) returned `null`
  /// and the PushKit ↔ SIP INVITE matcher fell through to the stub hint,
  /// leaving CallKit unlinked from the SIP call (no audio / never connects).
  String? getExtensionNumber(String sipString) {
    if (sipString.isEmpty) return null;

    // Prefer the SDK helper – it correctly handles `+`, letters, and other
    // URI-safe characters between `:` and `@`.
    final String fromSdk = CallsModel.parseExt(sipString).trim();
    if (fromSdk.isNotEmpty) return fromSdk;

    // Fallback for inputs that don't follow the `displName <sip:user@host>`
    // shape expected by `parseExt` (e.g. just `sip:user@host`).
    final RegExp regExp =
        RegExp(r'sip:([^@>;\s]+)@', caseSensitive: false);
    final Match? match = regExp.firstMatch(sipString);
    return match?.group(1);
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

  // @override
  // void onProceeding(int callId, String response) {
  //   super.onProceeding(callId, response);
  //   final c = _callBySipId(callId);
  //   if (c == null || c.isIncoming) return;
  //   if (_callStartLogged.contains(callId)) return;
  //   _callStartLogged.add(callId);
  //   final accExt = CallsModel.parseExt(c.accUri);
  //   final callerName =
  //       c.displName.isNotEmpty ? c.displName : (accExt.isNotEmpty ? accExt : c.remoteExt);
  // }

  @override
  void onConnected(int callId, String from, String to, bool withVideo) {
    final disp = CallsModel.parseDisplayName(from);
    final callerNum = CallsModel.parseExt(from);
    final recvNum = CallsModel.parseExt(to);
    final callerName = disp.isNotEmpty ? disp : callerNum;
    super.onConnected(callId, from, to, withVideo);
  }

  @override
  void onIncomingSip(int callId, int accId, bool withVideo, String hdrFrom, String hdrTo) async {
    super.onIncomingSip(callId, accId, withVideo, hdrFrom, hdrTo);

    // if (!_callStartLogged.contains(callId)) {
    //   _callStartLogged.add(callId);
    //   final callerNum = CallsModel.parseExt(hdrFrom);
    //   final recvNum = CallsModel.parseExt(hdrTo);
    //   final disp = CallsModel.parseDisplayName(hdrFrom);
    //   final callerName = disp.isNotEmpty ? disp : callerNum;
    // }

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

    if(Platform.isIOS && kIosUsePushKit) {
      // Match CallKit push flow with SIP INVITE using a shared hint (PBX should set X-PushHint to match push payload).
      //
      // Normalise to digits-only so a Twilio E.164 caller (`sip:+16467606640@host`)
      // matches the push payload's `caller_number` whether the PBX delivered it
      // with or without the leading `+`. Without this, the PushKit-presented
      // CallKit row never gets `updateCallKitCallDetails(uuid, sipCallId, ...)`
      // and answering the call does nothing (no audio, never connects).
      final String? extensionNumber = getExtensionNumber(hdrFrom);
      final String normalizedExt = (extensionNumber == null)
          ? ''
          : _normalizePhoneHint(extensionNumber);
      print('extensionNumber: $extensionNumber normalized: $normalizedExt');
      String pushHint =
          normalizedExt.isNotEmpty ? normalizedExt : CallMatcher.kStubPushHint;
      _logs?.print('onIncomingSip callId:$callId pushHint:$pushHint hdrFrom:$hdrFrom hdrTo:$hdrTo');

      //Searchs is there CallKit call which matches this one
      int index = _callMatchers.indexWhere((c) => c.push_Hint == pushHint);
      if(index != -1) {
        _logs?.print('onIncomingSip match call:${_callMatchers[index].callkit_CallUUID} <=> $callId');

        //Update CallKit with 'callId'
        _callMatchers[index].sip_CallId = callId;
        // Dismiss extra CallKit rows for the same push hint (e.g. double VoIP push / fallback + push).
        for (var j = _callMatchers.length - 1; j >= 0; j--) {
          if (j == index) continue;
          final other = _callMatchers[j];
          if (other.push_Hint != pushHint) continue;
          if (other.sip_CallId != 0 && other.sip_CallId != callId) continue;
          final String dupeUuid = other.callkit_CallUUID;
          _callMatchers.removeAt(j);
          if (j < index) index--;
          if (dupeUuid.isEmpty) continue;
          SiprixVoipSdk().endCallKitCall(dupeUuid);
          FlutterCallkitIncoming.endCall(dupeUuid).catchError((_) {});
        }
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
    if (Platform.isIOS) {
      _endCallKitForSipCallId(callId);
      // After the last SIP call ends, clear any orphan CallKit state so the next VoIP works.
      _resetIosCallKitWhenNoSipCalls();
    }
  }

  void _startPushNotifTimer() {
    if(_pushNotifTimer != null) return;

    const Duration kTimerDelay = Duration(seconds: 1);
    // After kill-state wake, SIP INVITE can lag behind PushKit while Flutter registers;
    // 15s was too aggressive and cleared CallKit (and the call) before INVITE matched.
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