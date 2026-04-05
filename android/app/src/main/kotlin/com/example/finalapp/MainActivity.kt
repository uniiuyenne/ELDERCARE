package com.example.finalapp

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.net.Uri
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val phoneChannelName = "eldercare/phone"
	private val requestCallPhoneCode = 9101
	private var pendingCallNumber: String? = null
	private var pendingResult: MethodChannel.Result? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, phoneChannelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"directCall" -> {
						val number = (call.argument<String>("number") ?: "").trim()
						if (number.isEmpty()) {
							result.success(false)
							return@setMethodCallHandler
						}

						tryDirectCallOrRequestPermission(number, result)
					}
					else -> result.notImplemented()
				}
			}
	}

	private fun tryDirectCallOrRequestPermission(number: String, result: MethodChannel.Result) {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
			result.success(tryStartDirectCall(number))
			return
		}

		val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) ==
			PackageManager.PERMISSION_GRANTED
		if (granted) {
			result.success(tryStartDirectCall(number))
			return
		}

		// Request permission, then continue.
		pendingCallNumber = number
		pendingResult = result
		ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CALL_PHONE), requestCallPhoneCode)
	}

	private fun tryStartDirectCall(number: String): Boolean {
		return try {
			val intent = Intent(Intent.ACTION_CALL).apply {
				data = Uri.parse("tel:$number")
				addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
			}
			startActivity(intent)
			true
		} catch (_: Throwable) {
			false
		}
	}

	override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
		super.onRequestPermissionsResult(requestCode, permissions, grantResults)
		if (requestCode != requestCallPhoneCode) return

		val result = pendingResult
		val number = pendingCallNumber
		pendingResult = null
		pendingCallNumber = null

		if (result == null || number == null) return
		val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
		if (!granted) {
			result.success(false)
			return
		}

		result.success(tryStartDirectCall(number))
	}

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		ensureSilentBackgroundChannel()
	}

	private fun ensureSilentBackgroundChannel() {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

		val manager = getSystemService(NotificationManager::class.java) ?: return
		val channelId = "eldercare_bg_silent"
		val channelName = "Elder Care Background"
		val channel = NotificationChannel(
			channelId,
			channelName,
			NotificationManager.IMPORTANCE_MIN
		).apply {
			description = "Dich vu nen Elder Care"
			setSound(null, null)
			enableVibration(false)
			setShowBadge(false)
			lockscreenVisibility = android.app.Notification.VISIBILITY_SECRET
		}
		manager.createNotificationChannel(channel)
	}
}
