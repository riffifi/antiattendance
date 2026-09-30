package com.example.antiattendance

import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antiattendance/installer")
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val path = call.argument<String>("path")
                        ?: throw IllegalArgumentException("Missing APK path")
                    val allowedDirectory = File(cacheDir, "updates").canonicalFile
                    val apk = File(path).canonicalFile
                    if (apk.parentFile != allowedDirectory || !apk.isFile ||
                        apk.name != "antiattendance-update.apk") {
                        throw IllegalArgumentException("Invalid update file")
                    }
                    val uri = FileProvider.getUriForFile(
                        this,
                        "$packageName.update_provider",
                        apk,
                    )
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        clipData = ClipData.newRawUri("update", uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(intent)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("INSTALLER_UNAVAILABLE", error.message, null)
                }
            }
    }
}
