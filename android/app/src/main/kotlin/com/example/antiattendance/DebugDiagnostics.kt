package com.example.antiattendance

import android.Manifest
import android.app.ActivityManager
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.os.Build
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature

/** A read-only snapshot; never returns identifiers, account data or tokens. */
object DebugDiagnostics {
    fun snapshot(context: Context): Map<String, Any?> {
        val memory = ActivityManager.MemoryInfo()
        (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
        val storage = StatFs(context.filesDir.absolutePath)
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val adapter = NfcAdapter.getDefaultAdapter(context)
        val widgets = AppWidgetManager.getInstance(context)
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "android_release" to Build.VERSION.RELEASE,
            "android_sdk" to Build.VERSION.SDK_INT,
            "supported_abis" to Build.SUPPORTED_ABIS.toList(),
            "device_uptime_ms" to SystemClock.elapsedRealtime(),
            "app_uptime_ms" to (if (Build.VERSION.SDK_INT >= 24) SystemClock.elapsedRealtime() - android.os.Process.getStartElapsedRealtime() else null),
            "memory_available_bytes" to memory.availMem,
            "memory_total_bytes" to memory.totalMem,
            "low_memory" to memory.lowMemory,
            "storage_available_bytes" to storage.availableBytes,
            "storage_total_bytes" to storage.totalBytes,
            "camera_permission" to (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED),
            "notifications_enabled" to NotificationManagerCompat.from(context).areNotificationsEnabled(),
            "battery_optimization_exempt" to (Build.VERSION.SDK_INT >= 23 && power.isIgnoringBatteryOptimizations(context.packageName)),
            "power_save_mode" to power.isPowerSaveMode,
            "nfc_available" to (adapter != null),
            "nfc_enabled" to (adapter?.isEnabled == true),
            "hce_supported" to context.packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION),
            "widget_pinning_supported" to (Build.VERSION.SDK_INT >= 26 && widgets.isRequestPinAppWidgetSupported),
            "webview_multi_profile" to WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE),
            "webview_version" to WebViewCompat.getCurrentWebViewPackage(context)?.versionName,
            "queue" to mapOf("armed" to PassQueue.armed),
        )
    }
}
