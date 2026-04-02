package com.example.safescan

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Telephony
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.LinkedHashSet

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

        if (isDuplicateSms(context, sender, body, timestamp)) {
            return
        }

        val pendingResult = goAsync()
        Thread {
            try {
                val status = scanSmsWithBackend(context, body)
                showResultNotification(context, sender, body, timestamp, status)
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    private fun isDuplicateSms(context: Context, sender: String, body: String, timestamp: Long): Boolean {
        val prefs = context.getSharedPreferences("sms_scan_state", Context.MODE_PRIVATE)
        val smsHash = ("$sender|$timestamp|$body").hashCode().toString()
        val lastHash = prefs.getString("last_sms_hash", "")
        if (smsHash == lastHash) {
            return true
        }
        prefs.edit().putString("last_sms_hash", smsHash).apply()
        return false
    }

    private fun scanSmsWithBackend(context: Context, messageBody: String): String {
        val payload = JSONObject().put("sms", messageBody).toString()
        val candidates = getBackendCandidates(context)

        for (baseUrl in candidates) {
            try {
                val status = requestScanStatus(baseUrl, payload)
                if (status != null) {
                    return status
                }
            } catch (_: Exception) {
                // Try the next candidate URL.
            }
        }

        return "safe"
    }

    private fun requestScanStatus(baseUrl: String, payload: String): String? {
        val url = URL("$baseUrl/scan/sms")
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 8_000
            readTimeout = 8_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
        }

        OutputStreamWriter(connection.outputStream).use { writer ->
            writer.write(payload)
            writer.flush()
        }

        if (connection.responseCode !in 200..299) {
            return null
        }

        val response = connection.inputStream.bufferedReader().use { it.readText() }
        val status = JSONObject(response).optString("status", "safe")
        return when (status) {
            "danger" -> "danger"
            "suspicious" -> "suspicious"
            else -> "safe"
        }
    }

    private fun getBackendCandidates(context: Context): List<String> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val configured = prefs?.getStringSet(BACKEND_CANDIDATES_KEY, null)
        if (!configured.isNullOrEmpty()) {
            return configured.toList()
        }

        val defaults = LinkedHashSet<String>()
        defaults.add("http://10.0.2.2:8000")
        defaults.add("http://127.0.0.1:8000")
        return defaults.toList()
    }

    private fun showResultNotification(
        context: Context,
        sender: String,
        body: String,
        timestamp: Long,
        status: String
    ) {
        createChannel(context)

        val title = when (status) {
            "danger" -> "SafeScan: Threat SMS"
            "suspicious" -> "SafeScan: Suspicious SMS"
            else -> "SafeScan: SMS is Safe"
        }

        val tapIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            action = "SMS_SCAN_RESULT"
            putExtra("scan_status", status)
            putExtra("scan_sms_body", body)
            putExtra("scan_sender", sender)
            putExtra("scan_timestamp", timestamp)
        }

        val pendingIntentFlags =
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        val pendingIntent = android.app.PendingIntent.getActivity(
            context,
            (timestamp % Int.MAX_VALUE).toInt(),
            tapIntent,
            pendingIntentFlags
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText("$sender: ${body.take(60)}")
            .setStyle(NotificationCompat.BigTextStyle().bigText("$sender\n\n$body"))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ActivityCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        NotificationManagerCompat.from(context).notify((timestamp % Int.MAX_VALUE).toInt(), notification)
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "SMS Safety Alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alerts with SafeScan analysis of incoming SMS messages"
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "sms_scan_results"
        private const val PREFS_NAME = "sms_scan_config"
        private const val BACKEND_CANDIDATES_KEY = "backend_candidates"
    }
}
