package com.example.safescan

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
	private var pendingScanResult: HashMap<String, Any>? = null
	private var pendingApkScanRequest: HashMap<String, Any>? = null
	private var autoSmsChannel: MethodChannel? = null
	private var lastHandledApkUri: String? = null

	override fun onCreate(savedInstanceState: android.os.Bundle?) {
		super.onCreate(savedInstanceState)
		consumeSmsResultIntent(intent)
		consumeIncomingApkIntent(intent)
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
		consumeSmsResultIntent(intent)
		consumeIncomingApkIntent(intent)
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
		autoSmsChannel = channel
		channel.setMethodCallHandler { call, result ->
				if (call.method == "getInitialSmsScanResult") {
					result.success(pendingScanResult)
					pendingScanResult = null
				} else if (call.method == "getInitialIncomingApkScanRequest") {
					result.success(pendingApkScanRequest)
					pendingApkScanRequest = null
				} else if (call.method == "copyApkUriToCache") {
					val rawMap = call.arguments as? Map<*, *>
					val uriString = rawMap?.get("uri") as? String
					if (uriString.isNullOrBlank()) {
						result.error("INVALID_URI", "Missing APK uri", null)
						return@setMethodCallHandler
					}

					val filePath = copyApkUriToCache(uriString)
					if (filePath == null) {
						result.error("COPY_FAILED", "Unable to copy APK into app cache", null)
					} else {
						result.success(filePath)
					}
				} else if (call.method == "installApkFromUri") {
					val rawMap = call.arguments as? Map<*, *>
					val uriString = rawMap?.get("uri") as? String
					if (uriString.isNullOrBlank()) {
						result.error("INVALID_URI", "Missing APK uri", null)
						return@setMethodCallHandler
					}

					result.success(launchPackageInstaller(uriString))
				} else if (call.method == "startMonitor") {
					getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
						.edit()
						.putBoolean(AUTO_SCAN_ENABLED_KEY, true)
						.apply()

					val hasAccess = NotificationManagerCompat
						.getEnabledListenerPackages(this)
						.contains(packageName)

					if (!hasAccess) {
						val settingsIntent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
							flags = Intent.FLAG_ACTIVITY_NEW_TASK
						}
						startActivity(settingsIntent)
					}
					result.success(hasAccess)
				} else if (call.method == "stopMonitor") {
					getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
						.edit()
						.putBoolean(AUTO_SCAN_ENABLED_KEY, false)
						.apply()
					result.success(true)
				} else if (call.method == "isNotificationListenerEnabled") {
					val hasAccess = NotificationManagerCompat
						.getEnabledListenerPackages(this)
						.contains(packageName)
					result.success(hasAccess)
				} else if (call.method == "setBackendCandidates") {
					val rawMap = call.arguments as? Map<*, *>
					val rawCandidates = rawMap?.get("candidates") as? List<*>
					val candidates = rawCandidates
						?.filterIsInstance<String>()
						?.filter { it.isNotBlank() }
						?: emptyList()

					if (candidates.isNotEmpty()) {
						getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
							.edit()
							.putStringSet(BACKEND_CANDIDATES_KEY, candidates.toSet())
							.apply()
					}
					result.success(true)
				} else {
					result.notImplemented()
				}
			}
	}

	private fun consumeSmsResultIntent(intent: Intent?) {
		if (intent?.action != "SMS_SCAN_RESULT") {
			return
		}

		val status = intent.getStringExtra("scan_status") ?: return
		val smsStatus = intent.getStringExtra("scan_sms_status") ?: status
		val smsBody = intent.getStringExtra("scan_sms_body") ?: ""
		val sender = intent.getStringExtra("scan_sender") ?: "Unknown Sender"
		val timestamp = intent.getLongExtra("scan_timestamp", 0L)
		val sourceApp = intent.getStringExtra("scan_source_app") ?: "android.sms"
		val sourceType = intent.getStringExtra("scan_source_type") ?: "sms_broadcast"
		val urls = intent.getStringArrayListExtra("scan_urls") ?: arrayListOf()
		val urlStatuses = intent.getStringArrayListExtra("scan_url_statuses") ?: arrayListOf()

		pendingScanResult = hashMapOf(
			"status" to status,
			"smsStatus" to smsStatus,
			"smsBody" to smsBody,
			"sender" to sender,
			"timestamp" to timestamp,
			"sourceApp" to sourceApp,
			"sourceType" to sourceType,
			"urls" to urls,
			"urlStatuses" to urlStatuses,
		)

		runOnUiThread {
			autoSmsChannel?.invokeMethod("onSmsScanResult", pendingScanResult)
		}
	}

	private fun consumeIncomingApkIntent(intent: Intent?) {
		if (!isApkViewIntent(intent)) {
			return
		}

		val uri = intent?.data ?: return
		val uriString = uri.toString()
		if (uriString == lastHandledApkUri) {
			return
		}
		lastHandledApkUri = uriString

		val displayName = extractDisplayName(uri)
		val timestamp = System.currentTimeMillis()

		pendingApkScanRequest = hashMapOf(
			"uri" to uriString,
			"displayName" to displayName,
			"timestamp" to timestamp,
		)

		runOnUiThread {
			autoSmsChannel?.invokeMethod("onIncomingApkForScan", pendingApkScanRequest)
		}
	}

	private fun isApkViewIntent(intent: Intent?): Boolean {
		if (intent == null) return false
		if (intent.action != Intent.ACTION_VIEW) return false
		val uri = intent.data ?: return false
		val mime = intent.type ?: ""

		if (mime == APK_MIME_TYPE) return true

		val lowerPath = uri.toString().lowercase()
		return lowerPath.endsWith(".apk")
	}

	private fun extractDisplayName(uri: Uri): String {
		val fallback = uri.lastPathSegment?.substringAfterLast('/') ?: "Incoming APK"
		return if (fallback.isBlank()) "Incoming APK" else fallback
	}

	private fun copyApkUriToCache(uriString: String): String? {
		return try {
			val uri = Uri.parse(uriString)

			if (uri.scheme == "file") {
				val path = uri.path
				if (!path.isNullOrBlank()) {
					return path
				}
			}

			val input = contentResolver.openInputStream(uri) ?: return null
			val tempFile = File(cacheDir, "incoming_${System.currentTimeMillis()}.apk")
			input.use { source ->
				FileOutputStream(tempFile).use { target ->
					source.copyTo(target)
				}
			}
			tempFile.absolutePath
		} catch (_: Exception) {
			null
		}
	}

	private fun launchPackageInstaller(uriString: String): Boolean {
		return try {
			val uri = Uri.parse(uriString)
			val installIntent = Intent(Intent.ACTION_VIEW).apply {
				setDataAndType(uri, APK_MIME_TYPE)
				addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
				addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
			}
			startActivity(installIntent)
			true
		} catch (_: ActivityNotFoundException) {
			false
		} catch (_: SecurityException) {
			false
		}
	}

	companion object {
		private const val CHANNEL_NAME = "com.example.safescan/auto_sms"
		private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
		private const val PREFS_NAME = "sms_scan_config"
		private const val BACKEND_CANDIDATES_KEY = "backend_candidates"
		const val AUTO_SCAN_ENABLED_KEY = "auto_scan_enabled"
	}
}
