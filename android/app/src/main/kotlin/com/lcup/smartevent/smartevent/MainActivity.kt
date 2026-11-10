package com.lcup.smartevent.smartevent

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
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

        // Swapping the launcher icon; see lib/state/app_icon.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smartevent/icon")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "current" -> result.success(currentIcon())
                    "set" -> try {
                        setIcon(call.arguments as String)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("icon", e.message, null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // The aliases declared in AndroidManifest.xml, by the names Dart uses.
    //
    // A function rather than a property: packageName reads through the
    // base context, which is attached after the constructor runs, so
    // building these as field initializers evaluates them too early.
    private val iconNames = listOf("navy", "light")

    private fun componentFor(name: String) = when (name) {
        "navy" -> ComponentName(this, "$packageName.IconNavy")
        "light" -> ComponentName(this, "$packageName.IconLight")
        else -> null
    }

    private fun currentIcon(): String =
        iconNames.firstOrNull { name ->
            packageManager.getComponentEnabledSetting(componentFor(name)!!) ==
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        }
        // DEFAULT, not ENABLED, is what the manifest's enabled="true"
        // reads as until something has been set explicitly — so nothing
        // matching above means nobody has chosen yet, which is navy.
            ?: "navy"

    private fun setIcon(name: String) {
        val wanted = componentFor(name)
            ?: throw IllegalArgumentException("unknown icon: $name")
        // Enable first, disable after. The other order leaves a moment
        // with no launcher component enabled at all, and a launcher that
        // looks in that moment drops the app off the home screen.
        packageManager.setComponentEnabledSetting(
            wanted,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        for (other in iconNames) {
            if (other == name) continue
            packageManager.setComponentEnabledSetting(
                componentFor(other)!!,
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }
}

/// Its own class so the merged manifest cannot confuse it with the file
/// providers that image_picker and share_plus declare.
class UpdateFileProvider : FileProvider()
