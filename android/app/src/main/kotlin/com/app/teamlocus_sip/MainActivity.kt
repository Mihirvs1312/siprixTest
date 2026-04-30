package com.app.teamlocus_sip

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Keep Activity#getIntent() in sync when answering from a notification
        // while this task already exists (singleTop).
        setIntent(intent)
    }
}
