package com.chandra.chittilata

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The channel "your turn" pushes arrive on (Settings can mute it).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "turns",
                "Your turn",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply { description = "Your turn, nudges and new rounds in games you're playing" }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
