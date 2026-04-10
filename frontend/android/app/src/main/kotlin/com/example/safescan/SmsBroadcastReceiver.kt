package com.example.safescan

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

class SmsBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isEmpty()) {
            return
        }

        val sender = messages.firstOrNull()?.originatingAddress ?: "Unknown Sender"
        val body = messages.joinToString(separator = "") { it.messageBody ?: "" }.trim()
        val timestamp = messages.firstOrNull()?.timestampMillis ?: System.currentTimeMillis()

        if (body.isEmpty()) {
            return
        }

        if (!AutoScanEngine.shouldAutoScan(context)) {
            return
        }

        val dedupeKey = "sms|$sender|$body"
        if (AutoScanEngine.isDuplicateEvent(context, dedupeKey)) {
            return
        }

        val pendingResult = goAsync()
        Thread {
            try {
                val outcome = AutoScanEngine.scanMessage(context, body)
                AutoScanEngine.showResultNotification(
                    context = context,
                    sender = sender,
                    messageBody = body,
                    timestamp = timestamp,
                    outcome = outcome,
                    sourcePackage = "android.sms",
                    sourceType = "sms_broadcast",
                )
            } finally {
                pendingResult.finish()
            }
        }.start()
    }
}
