import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:siprix_voip_sdk/siprix_voip_sdk.dart';

import 'callkit_event_bridge.dart';

const String _kSiprixFallbackExtraKey = 'siprixFallback';

bool _listenerRegistered = false;

/// Listen for accept / decline / end on calls shown by [showIncomingSipFallbackCallKit]
/// and forward them to Siprix.
void registerIncomingSipFallbackCallKitListener() {
  if (_listenerRegistered) return;
  _listenerRegistered = true;

  FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
    if (event == null) return;
    final raw = event.body;
    if (raw is! Map) return;
    final body = Map<String, dynamic>.from(raw);
    final String? callKitId =
        body['id'] as String? ?? body['uuid'] as String?;

    Map<String, dynamic>? extra;
    final extraRaw = body['extra'];
    if (extraRaw is Map) {
      extra = Map<String, dynamic>.from(extraRaw);
    }

    int sipCallId = (extra?['sipCallId'] as num?)?.toInt() ?? 0;
    if (sipCallId == 0 && callKitId != null) {
      sipCallId = resolveSipCallIdForCallKitUuid?.call(callKitId) ?? 0;
    }

    final bool withVideo = extra?['withVideo'] == true;

    // Decline / hang up from CallKit or VoIP incoming UI must clear SIP and dismiss all surfaces.
    var didUserHangUp = false;
    try {
      switch (event.event) {
        case Event.actionCallAccept:
          if (sipCallId <= 0) return;
          await SiprixVoipSdk().accept(sipCallId, withVideo);
          if (callKitId != null) {
            await FlutterCallkitIncoming.setCallConnected(callKitId);
          }
          break;
        case Event.actionCallDecline:
        case Event.actionCallTimeout:
          didUserHangUp = true;
          if (sipCallId > 0) {
            await SiprixVoipSdk().reject(sipCallId, 486);
          }
          break;
        case Event.actionCallEnded:
          didUserHangUp = true;
          if (sipCallId > 0) {
            await SiprixVoipSdk().bye(sipCallId);
          }
          break;
        default:
          break;
      }
    } catch (_) {
      // Siprix may already have moved state; avoid surfacing to user.
    } finally {
      if (didUserHangUp && (sipCallId > 0 || (callKitId != null && callKitId.isNotEmpty))) {
        onCallKitUserHangupSync?.call(sipCallId, callKitId);
      }
    }
  });
}

/// Android: hide full-screen incoming call UI / notification for this plugin call id.
Future<void> hideAndroidCallkitIncomingForId(String callKitUuid) {
  return FlutterCallkitIncoming.hideCallkitIncoming(CallKitParams(id: callKitUuid))
      .catchError((_) {});
}

/// Incoming SIP INVITE with no prior PushKit / Siprix CallKit match — show [flutter_callkit_incoming] UI.
///
/// See: https://pub.dev/packages/flutter_callkit_incoming
Future<void> showIncomingSipFallbackCallKit({
  required String id,
  required int sipCallId,
  required bool withVideo,
  required String nameCaller,
  required String handle,
}) async {
  final params = CallKitParams(
    id: id,
    nameCaller: nameCaller.isNotEmpty ? nameCaller : 'Incoming',
    appName: 'Siprix',
    handle: handle.isNotEmpty ? handle : 'Unknown',
    type: withVideo ? 1 : 0,
    duration: 60000,
    textAccept: 'Accept',
    textDecline: 'Decline',
    extra: <String, dynamic>{
      _kSiprixFallbackExtraKey: true,
      'sipCallId': sipCallId,
      'withVideo': withVideo,
    },
    missedCallNotification: const NotificationParams(
      showNotification: true,
      subtitle: 'Missed call',
    ),
    ios: IOSParams(
      iconName: 'CallKitIcon',
      handleType: 'generic',
      supportsVideo: withVideo,
      audioSessionMode: withVideo ? 'videoChat' : 'voiceChat',
      audioSessionActive: true,
    ),
    android: const AndroidParams(
      isCustomNotification: true,
      isShowCallID: true,
      incomingCallNotificationChannelName: 'Incoming SIP',
    ),
  );

  await FlutterCallkitIncoming.showCallkitIncoming(params);
}
