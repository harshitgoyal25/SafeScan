package com.example.safescan

import io.flutter.embedding.android.FlutterActivity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private var pendingScanResult: HashMap<String, Any>? = null
	private var autoSmsChannel: MethodChannel? = null

	override fun onCreate(savedInstanceState: android.os.Bundle?) {
		super.onCreate(savedInstanceState)
		consumeSmsResultIntent(intent)
		startService(Intent(this, ApkObserverService::class.java))
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
		consumeSmsResultIntent(intent)
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		autoSmsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
		autoSmsChannel
			.setMethodCallHandler { call, result ->
				if (call.method == "getInitialSmsScanResult") {
					result.success(pendingScanResult)
					pendingScanResult = null
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
		val smsBody = intent.getStringExtra("scan_sms_body") ?: ""
		val sender = intent.getStringExtra("scan_sender") ?: "Unknown Sender"
		val timestamp = intent.getLongExtra("scan_timestamp", 0L)

		pendingScanResult = hashMapOf(
			"status" to status,
			"smsBody" to smsBody,
			"sender" to sender,
			"timestamp" to timestamp,
		)

		runOnUiThread {
			autoSmsChannel?.invokeMethod("onSmsScanResult", pendingScanResult)
		}
	}

	companion object {
		private const val CHANNEL_NAME = "com.example.safescan/auto_sms"
		private const val PREFS_NAME = "sms_scan_config"
		private const val BACKEND_CANDIDATES_KEY = "backend_candidates"
	}
}
