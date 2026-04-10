package com.example.safescan

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.LinkedHashSet
import java.util.regex.Pattern

data class UrlScanResult(
    val url: String,
    val status: String,
)

data class ScanOutcome(
    val smsStatus: String,
    val urlResults: List<UrlScanResult>,
) {
    fun overallStatus(): String {
        val statuses = mutableListOf(smsStatus)
        statuses.addAll(urlResults.map { it.status })

        if (statuses.any { it == "danger" }) {
            return "danger"
        }
        if (statuses.any { it == "suspicious" }) {
            return "suspicious"
        }
        return "safe"
    }
}

object AutoScanEngine {
    private const val CHANNEL_ID = "auto_scan_results"
    private const val PREFS_NAME = "sms_scan_config"
    private const val BACKEND_CANDIDATES_KEY = "backend_candidates"
    private const val LAST_EVENT_HASH_KEY = "last_event_hash"
    private val URL_PATTERN: Pattern =
        Pattern.compile("((https?://|www\\.)[^\\s]+)", Pattern.CASE_INSENSITIVE)

    fun shouldAutoScan(context: Context): Boolean {
        return context
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(MainActivity.AUTO_SCAN_ENABLED_KEY, false)
    }

    fun isDuplicateEvent(context: Context, dedupeKey: String): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val hash = dedupeKey.hashCode().toString()
        val lastHash = prefs.getString(LAST_EVENT_HASH_KEY, null)

        if (hash == lastHash) {
            return true
        }

        prefs.edit().putString(LAST_EVENT_HASH_KEY, hash).apply()
        return false
    }

    fun scanMessage(context: Context, messageBody: String): ScanOutcome {
        val smsStatus = scanSmsWithBackend(context, messageBody)
        val urls = extractUrls(messageBody)

        val urlStatuses = urls.map { url ->
            UrlScanResult(url = url, status = scanUrlWithBackend(context, url))
        }

        return ScanOutcome(
            smsStatus = smsStatus,
            urlResults = urlStatuses,
        )
    }

    fun showResultNotification(
        context: Context,
        sender: String,
        messageBody: String,
        timestamp: Long,
        outcome: ScanOutcome,
        sourcePackage: String,
        sourceType: String,
    ) {
        createChannel(context)

        val overall = outcome.overallStatus()
        val suspiciousUrlCount = outcome.urlResults.count { it.status != "safe" }

        val title = when (overall) {
            "danger" -> "SafeScan: Threat Detected"
            "suspicious" -> "SafeScan: Suspicious Message"
            else -> "SafeScan: Message Looks Safe"
        }

        val preview = messageBody.replace("\n", " ").trim()
        val content = when {
            suspiciousUrlCount > 0 -> "$sender: $suspiciousUrlCount suspicious URL(s)"
            else -> "$sender: ${preview.take(60)}"
        }

        val tapIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            action = "SMS_SCAN_RESULT"
            putExtra("scan_status", overall)
            putExtra("scan_sms_status", outcome.smsStatus)
            putExtra("scan_sms_body", messageBody)
            putExtra("scan_sender", sender)
            putExtra("scan_timestamp", timestamp)
            putExtra("scan_source_app", sourcePackage)
            putExtra("scan_source_type", sourceType)
            putStringArrayListExtra(
                "scan_urls",
                ArrayList(outcome.urlResults.map { it.url }),
            )
            putStringArrayListExtra(
                "scan_url_statuses",
                ArrayList(outcome.urlResults.map { it.status }),
            )
        }

        val pendingIntentFlags =
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        val pendingIntent = android.app.PendingIntent.getActivity(
            context,
            (timestamp % Int.MAX_VALUE).toInt(),
            tapIntent,
            pendingIntentFlags,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(content)
            .setStyle(NotificationCompat.BigTextStyle().bigText("$sender\n\n$messageBody"))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        NotificationManagerCompat
            .from(context)
            .notify((timestamp % Int.MAX_VALUE).toInt(), notification)
    }

    private fun scanSmsWithBackend(context: Context, messageBody: String): String {
        val payload = JSONObject().put("sms", messageBody).toString()

        for (baseUrl in getBackendCandidates(context)) {
            try {
                requestScanStatus(baseUrl, "/scan/sms", payload)?.let { return it }
            } catch (_: Exception) {
                // Try next candidate.
            }
        }
        return "safe"
    }

    private fun scanUrlWithBackend(context: Context, url: String): String {
        val payload = JSONObject().put("url", url).toString()

        for (baseUrl in getBackendCandidates(context)) {
            try {
                requestScanStatus(baseUrl, "/scan/url", payload)?.let { return it }
            } catch (_: Exception) {
                // Try next candidate.
            }
        }
        return "safe"
    }

    private fun requestScanStatus(baseUrl: String, path: String, payload: String): String? {
        val url = URL("$baseUrl$path")
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
        return normalizeStatus(JSONObject(response).optString("status", "safe"))
    }

    private fun normalizeStatus(raw: String): String {
        return when (raw.lowercase()) {
            "danger" -> "danger"
            "suspicious" -> "suspicious"
            else -> "safe"
        }
    }

    private fun getBackendCandidates(context: Context): List<String> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val configured = prefs.getStringSet(BACKEND_CANDIDATES_KEY, null)

        if (!configured.isNullOrEmpty()) {
            return configured.toList()
        }

        val defaults = LinkedHashSet<String>()
        defaults.add("http://10.0.2.2:8000")
        defaults.add("http://127.0.0.1:8000")
        return defaults.toList()
    }

    private fun extractUrls(message: String): List<String> {
        val matcher = URL_PATTERN.matcher(message)
        val unique = LinkedHashSet<String>()

        while (matcher.find()) {
            val raw = matcher.group(1) ?: continue
            val normalized = normalizeUrl(raw)
            if (normalized.isNotBlank()) {
                unique.add(normalized)
            }
            if (unique.size >= 5) {
                break
            }
        }

        return unique.toList()
    }

    private fun normalizeUrl(raw: String): String {
        val cleaned = raw.trim().trimEnd('.', ',', ';', ':', ')', ']', '"', '\'')
        if (cleaned.startsWith("http://") || cleaned.startsWith("https://")) {
            return cleaned
        }
        if (cleaned.startsWith("www.")) {
            return "https://$cleaned"
        }
        return ""
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "SafeScan Auto Alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Auto analysis results for incoming messages and notification text"
        }
        manager.createNotificationChannel(channel)
    }
}