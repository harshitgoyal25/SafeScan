package com.example.safescan

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.os.FileObserver
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.LinkedHashSet
import kotlin.concurrent.thread

class ApkObserverService : Service() {

    private val observers = mutableListOf<FileObserver>()

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onCreate() {
        super.onCreate()
        Log.d("SafeScan", "ApkObserverService created")
        createChannel(this)
        startObserving()
    }

    override fun onDestroy() {
        super.onDestroy()
        observers.forEach { it.stopWatching() }
        observers.clear()
        Log.d("SafeScan", "ApkObserverService destroyed")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Run until explicitly stopped
        return START_STICKY
    }

    private fun startObserving() {
        val pathsToWatch = mutableListOf<String>()
        
        // 1. Standard Downloads
        val downloadsPath = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).absolutePath
        pathsToWatch.add(downloadsPath)

        // 2. WhatsApp Documents (Android 11+)
        val whatsappPath11 = "${Environment.getExternalStorageDirectory().absolutePath}/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Documents"
        pathsToWatch.add(whatsappPath11)

        // 3. WhatsApp Documents (Legacy)
        val whatsappPathLegacy = "${Environment.getExternalStorageDirectory().absolutePath}/WhatsApp/Media/WhatsApp Documents"
        pathsToWatch.add(whatsappPathLegacy)

        for (path in pathsToWatch) {
            val dir = File(path)
            if (dir.exists() && dir.isDirectory) {
                Log.d("SafeScan", "Watching: $path")
                // On modern Android, FileObserver requires API 29+ constructor if we want multiple events easily, 
                // but the old String constructor works well enough.
                val observer = object : FileObserver(path, CLOSE_WRITE or MOVED_TO) {
                    override fun onEvent(event: Int, pathFile: String?) {
                        if (pathFile != null && pathFile.endsWith(".apk", ignoreCase = true)) {
                            val fullPath = "$path/$pathFile"
                            Log.d("SafeScan", "New APK Detected: $fullPath")
                            handleNewApk(fullPath, pathFile)
                        }
                    }
                }
                observer.startWatching()
                observers.add(observer)
            }
        }
    }

    private val scannedFiles = mutableSetOf<String>()

    private fun handleNewApk(filePath: String, fileName: String) {
        if (scannedFiles.contains(filePath)) return
        scannedFiles.add(filePath)

        thread {
            try {
                val status = scanApkWithBackend(this, filePath, fileName)
                showResultNotification(this, fileName, status)
            } catch (e: Exception) {
                Log.e("SafeScan", "APK Scan failed", e)
                scannedFiles.remove(filePath) // Allow retry later
            }
        }
    }

    private fun scanApkWithBackend(context: Context, filePath: String, fileName: String): String {
        val candidates = getBackendCandidates(context)
        val file = File(filePath)
        if (!file.exists()) return "safe"

        val boundary = "==SafeScanBoundary=="

        for (baseUrl in candidates) {
            try {
                val url = URL("$baseUrl/scan/apk")
                val connection = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 15_000
                    readTimeout = 30_000
                    doOutput = true
                    setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
                }

                connection.outputStream.use { outputStream ->
                    val payload = ("--$boundary\r\n" +
                            "Content-Disposition: form-data; name=\"file\"; filename=\"$fileName\"\r\n" +
                            "Content-Type: application/vnd.android.package-archive\r\n\r\n").toByteArray()
                    outputStream.write(payload)

                    FileInputStream(file).use { fileInputStream ->
                        fileInputStream.copyTo(outputStream)
                    }

                    outputStream.write("\r\n--$boundary--\r\n".toByteArray())
                    outputStream.flush()
                }

                if (connection.responseCode in 200..299) {
                    val response = connection.inputStream.bufferedReader().use { it.readText() }
                    val status = JSONObject(response).optString("status", "safe")
                    return when (status) {
                        "danger" -> "danger"
                        "suspicious" -> "suspicious"
                        else -> "safe"
                    }
                }
            } catch (e: Exception) {
                Log.e("SafeScan", "Candidate $baseUrl failed for APK scan", e)
            }
        }
        return "safe"
    }

    private fun getBackendCandidates(context: Context): List<String> {
        val prefs = context.getSharedPreferences("sms_scan_config", Context.MODE_PRIVATE)
        val configured = prefs?.getStringSet("backend_candidates", null)
        if (!configured.isNullOrEmpty()) {
            return configured.toList()
        }

        val defaults = LinkedHashSet<String>()
        defaults.add("http://10.0.2.2:8000")
        defaults.add("http://127.0.0.1:8000")
        return defaults.toList()
    }

    private fun showResultNotification(context: Context, fileName: String, status: String) {
        val title = when (status) {
            "danger" -> "SafeScan: Threat APK Detected"
            "suspicious" -> "SafeScan: Suspicious APK"
            else -> "SafeScan: APK is Safe"
        }

        val tapIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val pendingIntent = android.app.PendingIntent.getActivity(
            context,
            fileName.hashCode(),
            tapIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, "sms_scan_results")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText("File: $fileName was scanned automatically.")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        NotificationManagerCompat.from(context).notify(fileName.hashCode(), notification)
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            "sms_scan_results",
            "SafeScan Alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply { description = "Alerts with SafeScan analysis of incoming threats" }
        manager.createNotificationChannel(channel)
    }
}
