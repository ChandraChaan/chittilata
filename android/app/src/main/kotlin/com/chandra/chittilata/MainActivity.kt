package com.chandra.chittilata

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.ContactsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPick: MethodChannel.Result? = null

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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Invite a friend from the address book without the contacts
        // permission: the system picker shows the contacts and hands back
        // only the one phone number the player chose (a one-time read grant).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chitplay/contacts")
            .setMethodCallHandler { call, result ->
                if (call.method != "pickPhone") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingPick != null) {
                    result.error("busy", "A contact picker is already open", null)
                    return@setMethodCallHandler
                }
                val intent = Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI)
                try {
                    pendingPick = result
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, PICK_PHONE)
                } catch (e: ActivityNotFoundException) {
                    pendingPick = null
                    result.error("unavailable", "No contacts app", null)
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_PHONE) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            contentResolver.query(
                uri,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.NUMBER,
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ),
                null,
                null,
                null,
            )?.use { c ->
                if (c.moveToFirst()) {
                    result.success(mapOf("number" to c.getString(0), "name" to c.getString(1)))
                } else {
                    result.success(null)
                }
            } ?: result.success(null)
        } catch (e: Exception) {
            result.error("read-failed", e.message, null)
        }
    }

    companion object {
        private const val PICK_PHONE = 4207
    }
}
