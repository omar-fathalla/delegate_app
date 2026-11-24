package com.tashil.delegate

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    // TAS-261: device_info_plus' androidInfo.id is Build.ID (a build number
    // shared by many phones). Settings.Secure.ANDROID_ID is unique per device,
    // app signing key and user, and survives reinstalls.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tashil/device_id")
            .setMethodCallHandler { call, result ->
                if (call.method == "androidId") {
                    val id = try {
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                    } catch (e: Exception) {
                        null
                    }
                    result.success(id ?: "")
                } else {
                    result.notImplemented()
                }
            }
    }
}
