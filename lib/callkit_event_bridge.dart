/// Wire [AppCallsModel] into [callkit_incoming_fallback] without circular imports.
typedef CallKitHangupSync = void Function(int sipCallId, String? callKitUuid);
typedef SipCallIdForCallKitUuid = int? Function(String? callKitUuid);

CallKitHangupSync? onCallKitUserHangupSync;
SipCallIdForCallKitUuid? resolveSipCallIdForCallKitUuid;
