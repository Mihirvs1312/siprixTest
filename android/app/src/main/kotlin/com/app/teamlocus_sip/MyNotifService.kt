package com.app.teamlocus_sip

import android.util.Log
import com.siprix.voip_sdk.CallNotifService

// MyNotifService - customize incoming-call UI; keep Accept/Reject by delegating to the SDK
// base implementation (CallStyle + PendingIntents). Override here only if you need extra
// builder flags while still calling super, or copy super's CallStyle setup from CallNotifService.
class MyNotifService : CallNotifService() {
    private val tag = "MyNotifService"

    override fun displayIncomingCallNotification(
        callId: Int,
        accId: Int,
        withVideo: Boolean,
        hdrFrom: String?,
        hdrTo: String?,
    ) {
        Log.d(tag, "displayIncomingCallNotification $callId")
        super.displayIncomingCallNotification(callId, accId, withVideo, hdrFrom, hdrTo)
    }
}