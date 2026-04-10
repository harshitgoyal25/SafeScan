package com.example.safescan

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class SafeScanNotificationListenerService : NotificationListenerService() {
    private val smsLikePackages = setOf(
        "com.google.android.apps.messaging",
        "com.android.mms",
        "com.samsung.android.messaging",
        "com.whatsapp",
        "org.telegram.messenger",
        "com.facebook.orca",
    )

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) {
            return
        }
        if (!AutoScanEngine.shouldAutoScan(this)) {
            return
        }
        if (sbn.packageName == packageName) {
            return
        }

        val notification = sbn.notification ?: return
        val extracted = extractNotificationText(notification)
        if (extracted.body.isBlank()) {
            return
        }

        if (!looksScannable(sbn.packageName, extracted.body)) {
            return
        }

        val dedupeKey = "notif|${sbn.packageName}|${extracted.title}|${extracted.body}"
        if (AutoScanEngine.isDuplicateEvent(this, dedupeKey)) {
            return
        }

        Thread {
            val outcome = AutoScanEngine.scanMessage(this, extracted.body)
            AutoScanEngine.showResultNotification(
                context = this,
                sender = extracted.sender,
                messageBody = extracted.body,
                timestamp = sbn.postTime,
                outcome = outcome,
                sourcePackage = sbn.packageName,
                sourceType = "notification",
            )
        }.start()
    }

    private fun looksScannable(packageName: String, body: String): Boolean {
        val lower = body.lowercase()
        if (lower.contains("http://") || lower.contains("https://") || lower.contains("www.")) {
            return true
        }
        if (smsLikePackages.contains(packageName)) {
            return true
        }
        return lower.contains("otp") || lower.contains("urgent") || lower.contains("verify")
    }

    private fun extractNotificationText(notification: Notification): ExtractedNotification {
        val extras = notification.extras
        val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val bigText = extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim().orEmpty()
        val body = listOf(text, bigText)
            .filter { it.isNotBlank() }
            .joinToString("\n")
            .trim()
            .take(2_000)

        val sender = if (title.isNotBlank()) title else "Notification"
        return ExtractedNotification(
            title = title,
            sender = sender,
            body = body,
        )
    }
}

private data class ExtractedNotification(
    val title: String,
    val sender: String,
    val body: String,
)