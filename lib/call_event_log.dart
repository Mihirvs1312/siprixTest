import 'dart:convert';

import 'accouns_model_app.dart';

/// Structured call lifecycle payload for analytics / backend sync.
///
/// [sipCallId] is mapped to JSON string [callId] as `call-<id>` (e.g. `call-12345`).
class CallEventLog {
  CallEventLog._();

  static String callIdFromSip(int sipCallId) => 'call-$sipCallId';

  static Future<Map<String, dynamic>> build({
    required String type,
    required int sipCallId,
    required String callerName,
    required String callerNumber,
    required String receiverNumber,
  }) async {
    final deviceId = await AppAccountsModel.getOrCreateDeviceId();
    return {
      'callId': callIdFromSip(sipCallId),
      'caller_name': callerName,
      'caller_number': callerNumber,
      'receiver_number': receiverNumber,
      'type': type,
      'device_id': deviceId,
    };
  }

  static String toPrettyJson(Map<String, dynamic> payload) =>
      const JsonEncoder.withIndent('  ').convert(payload);
}
