package com.lcup.smartevent.smartevent

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity, not FlutterActivity: local_auth shows the
// system biometric prompt as a fragment, and it has nowhere to attach
// on a plain Activity.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Opens Android's own install screen for a downloaded update; see
        // lib/state/app_update.dart. An app outside the Play Store cannot
        // install itself without it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smartevent/update")
            .setMethodCallHandler { call, result ->
                if (call.method != "install") return@setMethodCallHandler result.notImplemented()
                try {
                    val apk = File(call.arguments as String)
                    val uri = FileProvider.getUriForFile(this, "$packageName.update", apk)
                    startActivity(
                        Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                } catch (e: Exception) {
                    result.error("install", e.message, null)
                }
            }
    }
}

/// Its own class so the merged manifest cannot confuse it with the file
/// providers that image_picker and share_plus declare.
class UpdateFileProvider : FileProvider()
