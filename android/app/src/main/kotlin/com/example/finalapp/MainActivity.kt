package com.example.finalapp

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
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
