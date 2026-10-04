package com.example.antiattendance

import android.content.ClipData
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Build
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.cardemulation.CardEmulation
import android.nfc.tech.IsoDep
import android.nfc.tech.NfcA
import android.os.SystemClock
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private class ObserveStartException(val code: String, message: String) : IllegalStateException(message)

    companion object {
        const val ACTION_SCAN_ALL = "com.example.antiattendance.SCAN_ALL"
        const val ACTION_NFC_PASSES = "com.example.antiattendance.NFC_PASSES"
    }

    private var updatesChannel: MethodChannel? = null
    private var pendingUpdateOpen = false
    private var pendingUpdateTag: String? = null
    private var widgetChannel: MethodChannel? = null
    private var pendingWidgetScan = false
    private var pendingNfcPassRequest = false
    private var nfcChannel: MethodChannel? = null
    private var readerRequested = false
    private var readerActive = false
    private var turnstileChannel: MethodChannel? = null
    private var turnstileRequested = false
    private var turnstileActive = false
    private var fieldCallback: CardEmulation.NfcEventCallback? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingUpdateOpen = intent?.action == UpdateNotifier.ACTION_OPEN
        pendingWidgetScan = intent?.action == ACTION_SCAN_ALL
        pendingNfcPassRequest = intent?.action == ACTION_NFC_PASSES
        super.onCreate(savedInstanceState)
        stopPassQueue()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        updatesChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antiattendance/updates")
        updatesChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    UpdateNotifier.configure(this, call.argument<String>("language"))
                    result.success(null)
                }
                "takeOpenRequest" -> {
                    result.success(pendingUpdateOpen)
                    pendingUpdateOpen = false
                }
                "notify" -> {
                    val tag = call.argument<String>("tag")
                    if (tag != null && UpdateNotifier.isNewer(this, tag)) {
                        val prefs = UpdateNotifier.preferences(this)
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
                            !prefs.getBoolean("permission_requested", false)) {
                            prefs.edit().putBoolean("permission_requested", true).apply()
                            pendingUpdateTag = tag
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 7303)
                        } else UpdateNotifier.show(this, tag)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antiattendance/nfc_pass").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "openNfcSettings" -> {
                        startActivity(Intent(android.provider.Settings.ACTION_NFC_SETTINGS))
                        result.success(null)
                    }
                    "pinNfcWidget" -> {
                        val manager = android.appwidget.AppWidgetManager.getInstance(this)
                        if (Build.VERSION.SDK_INT < 26 || !manager.isRequestPinAppWidgetSupported) {
                            result.success(false)
                        } else {
                            val provider = if (call.argument<Boolean>("compact") == true)
                                NfcPassCompactWidgetProvider::class.java else NfcPassWidgetProvider::class.java
                            result.success(manager.requestPinAppWidget(ComponentName(this, provider), null, null))
                        }
                    }
                    "start" -> {
                        val adapter = NfcAdapter.getDefaultAdapter(this)
                        if (adapter == null) {
                            result.error("NFC_UNAVAILABLE", "NFC is unavailable", null)
                            return@setMethodCallHandler
                        }
                        if (!adapter.isEnabled) {
                            result.error("NFC_DISABLED", "NFC is disabled", null)
                            return@setMethodCallHandler
                        }
                        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION)) {
                            result.error("NFC_HCE_UNAVAILABLE", "NFC card emulation is unavailable", null)
                            return@setMethodCallHandler
                        }
                        check(!readerRequested && !turnstileRequested) { "Close NFC diagnostics first." }
                        val raw = call.argument<List<Map<String, Any>>>("passes") ?: error("Missing passes")
                        val values = raw.map {
                            PassQueue.Pass(
                                it["accountId"] as String,
                                (it["number"] as String).toLong(),
                                (it["expiresAt"] as Number).toLong(),
                            )
                        }
                        val emulation = CardEmulation.getInstance(adapter)
                        val service = ComponentName(this, DigitalPassService::class.java)
                        try {
                            check(emulation.registerAidsForService(service, CardEmulation.CATEGORY_OTHER, listOf("F222222222"))) {
                                "Android could not register the campus NFC application."
                            }
                            check(emulation.setPreferredService(this, service)) {
                                "Android could not select this app for NFC."
                            }
                            PassQueue.start(values, call.argument<Int>("intervalSeconds") ?: 60)
                            window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } catch (error: Exception) {
                            stopPassQueue()
                            throw error
                        }
                        result.success(PassQueue.status())
                    }
                    "status" -> result.success(PassQueue.status())
                    "stop" -> {
                        stopPassQueue()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("NFC_PASS_ERROR", error.message, null)
            }
        }
        widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antiattendance/launcher_widget")
        widgetChannel?.setMethodCallHandler { call, result ->
            if (call.method == "setWidgetLanguage") {
                val language = call.argument<String>("language")
                getSharedPreferences("launcher_widgets", MODE_PRIVATE).edit().apply {
                    if (language == null) remove("language") else putString("language", language)
                }.apply()
                val manager = android.appwidget.AppWidgetManager.getInstance(this)
                val providers = listOf(
                    ScanAllWidgetProvider(), ScanAllCompactWidgetProvider(), NfcPassWidgetProvider(), NfcPassCompactWidgetProvider(),
                )
                for (provider in providers) {
                    val ids = manager.getAppWidgetIds(ComponentName(this, provider.javaClass))
                    if (ids.isNotEmpty()) provider.onUpdate(this, manager, ids)
                }
                result.success(null)
            } else if (call.method == "takeNfcPassRequest") {
                val requested = pendingNfcPassRequest || intent?.action == ACTION_NFC_PASSES
                pendingNfcPassRequest = false
                if (requested) intent?.action = Intent.ACTION_MAIN
                result.success(requested)
            } else if (call.method == "takeScanAllRequest") {
                val requested = pendingWidgetScan || intent?.action == ACTION_SCAN_ALL
                pendingWidgetScan = false
                if (requested) intent?.action = Intent.ACTION_MAIN
                result.success(requested)
            } else {
                result.notImplemented()
            }
        }
        nfcChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antiattendance/nfc_diagnostics")
        nfcChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val adapter = NfcAdapter.getDefaultAdapter(this)
                    when {
                        adapter == null -> result.error("NFC_UNAVAILABLE", "This device has no NFC reader", null)
                        !adapter.isEnabled -> result.error("NFC_DISABLED", "NFC is turned off", null)
                        else -> {
                            readerRequested = true
                            try {
                                enableDiagnosticsReader(adapter)
                                result.success(null)
                            } catch (error: Exception) {
                                readerRequested = false
                                result.error("NFC_ERROR", error.message, null)
                            }
                        }
                    }
                }
                "stop" -> {
                    readerRequested = false
                    disableDiagnosticsReader()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        turnstileChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antiattendance/turnstile_probe")
        turnstileChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val adapter = NfcAdapter.getDefaultAdapter(this)
                    when {
                        adapter == null -> result.error("NFC_UNAVAILABLE", "This device has no NFC", null)
                        !adapter.isEnabled -> result.error("NFC_DISABLED", "NFC is turned off", null)
                        Build.VERSION.SDK_INT < 35 -> result.error("OBSERVE_UNAVAILABLE", "Requires Android 15 or newer", null)
                        !packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION) ->
                            result.error("OBSERVE_UNAVAILABLE", "This device has no NFC host card emulation", null)
                        else -> {
                            turnstileRequested = true
                            try {
                                result.success(startTurnstileProbeOrFallback(adapter))
                            } catch (error: Exception) {
                                turnstileRequested = false
                                stopTurnstileProbe()
                                result.error(
                                    (error as? ObserveStartException)?.code ?: "OBSERVE_ERROR",
                                    error.message,
                                    null,
                                )
                            }
                        }
                    }
                }
                "stop" -> {
                    turnstileRequested = false
                    stopTurnstileProbe()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antiattendance/monet")
            .setMethodCallHandler { call, result ->
                if (call.method != "getSeedColor") {
                    result.notImplemented()
                } else if (Build.VERSION.SDK_INT < 31) {
                    result.success(null)
                } else {
                    result.success(runCatching {
                        getColor(android.R.color.system_accent1_500)
                    }.getOrNull())
                }
            }
    }

    override fun onNewIntent(newIntent: Intent) {
        super.onNewIntent(newIntent)
        setIntent(newIntent)
        if (newIntent.action == UpdateNotifier.ACTION_OPEN) {
            pendingUpdateOpen = true
            stopPassQueue()
            updatesChannel?.invokeMethod("openUpdates", null, object : MethodChannel.Result {
                override fun success(result: Any?) { pendingUpdateOpen = false; newIntent.action = Intent.ACTION_MAIN }
                override fun error(code: String, message: String?, details: Any?) = Unit
                override fun notImplemented() = Unit
            })
            return
        }
        val nfcRequest = newIntent.action == ACTION_NFC_PASSES
        if (!nfcRequest && newIntent.action != ACTION_SCAN_ALL) return
        pendingWidgetScan = !nfcRequest
        pendingNfcPassRequest = nfcRequest
        widgetChannel?.invokeMethod(if (nfcRequest) "nfcPasses" else "scanAll", null, object : MethodChannel.Result {
            override fun success(result: Any?) {
                pendingWidgetScan = false
                pendingNfcPassRequest = false
                newIntent.action = Intent.ACTION_MAIN
            }

            override fun error(code: String, message: String?, details: Any?) = Unit
            override fun notImplemented() = Unit
        })
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7303) {
            val tag = pendingUpdateTag
            pendingUpdateTag = null
            if (tag != null && grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) UpdateNotifier.show(this, tag)
        }
    }

    private fun enableDiagnosticsReader(adapter: NfcAdapter) {
        if (readerActive) return
        val flags = NfcAdapter.FLAG_READER_NFC_A or
            NfcAdapter.FLAG_READER_NFC_B or
            NfcAdapter.FLAG_READER_NFC_F or
            NfcAdapter.FLAG_READER_NFC_V or
            NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK
        adapter.enableReaderMode(this, { tag -> reportTag(tag) }, flags, null)
        readerActive = true
    }

    private fun disableDiagnosticsReader() {
        if (!readerActive) return
        NfcAdapter.getDefaultAdapter(this)?.disableReaderMode(this)
        readerActive = false
    }

    private fun startTurnstileProbe(adapter: NfcAdapter) {
        if (turnstileActive || Build.VERSION.SDK_INT < 35) return
        val emulation = CardEmulation.getInstance(adapter)
        val service = ComponentName(this, TurnstileProbeService::class.java)
        if (!emulation.setPreferredService(this, service)) {
            throw ObserveStartException(
                "OBSERVE_PREFERENCE_FAILED",
                "Android could not select the NFC diagnostic service",
            )
        }
        val enabled = try {
            adapter.setObserveModeEnabled(true)
        } catch (error: Exception) {
            emulation.unsetPreferredService(this)
            throw ObserveStartException(
                if (adapter.isObserveModeSupported) "OBSERVE_ERROR" else "OBSERVE_DISABLED_BY_SYSTEM",
                error.message ?: "Android rejected NFC Observe Mode",
            )
        }
        if (!enabled) {
            emulation.unsetPreferredService(this)
            throw ObserveStartException(
                if (adapter.isObserveModeSupported) "OBSERVE_ERROR" else "OBSERVE_DISABLED_BY_SYSTEM",
                "Android rejected NFC Observe Mode",
            )
        }
        TurnstileProbeBridge.onFrames = { frames ->
            runOnUiThread {
                if (turnstileActive) turnstileChannel?.invokeMethod("frames", frames)
            }
        }
        turnstileActive = true
    }

    private fun startTurnstileProbeOrFallback(adapter: NfcAdapter): String {
        if (fieldCallback != null) return "field"
        if (turnstileActive) return "observe"
        try {
            startTurnstileProbe(adapter)
            return "observe"
        } catch (error: ObserveStartException) {
            if (error.code != "OBSERVE_DISABLED_BY_SYSTEM" || Build.VERSION.SDK_INT < 36) {
                throw error
            }
            // Field callbacks can work when the NFC stack rejects polling-frame Observe Mode.
            startFieldProbe(adapter)
            return "field"
        }
    }

    private fun startFieldProbe(adapter: NfcAdapter) {
        val emulation = CardEmulation.getInstance(adapter)
        val callback = object : CardEmulation.NfcEventCallback {
            override fun onRemoteFieldChanged(isDetected: Boolean) {
                if (fieldCallback !== this || !turnstileRequested) return
                turnstileChannel?.invokeMethod(
                    "fieldChanged",
                    mapOf(
                        "detected" to isDetected,
                        "timestampUs" to SystemClock.elapsedRealtimeNanos() / 1000,
                    ),
                )
            }
        }
        emulation.registerNfcEventCallback(mainExecutor, callback)
        fieldCallback = callback
    }

    private fun stopTurnstileProbe() {
        TurnstileProbeBridge.onFrames = null
        fieldCallback?.let { callback ->
            NfcAdapter.getDefaultAdapter(this)?.let { adapter ->
                runCatching { CardEmulation.getInstance(adapter).unregisterNfcEventCallback(callback) }
            }
            fieldCallback = null
        }
        if (!turnstileActive || Build.VERSION.SDK_INT < 35) return
        val adapter = NfcAdapter.getDefaultAdapter(this)
        if (adapter != null && adapter.isEnabled) {
            adapter.setObserveModeEnabled(false)
            CardEmulation.getInstance(adapter).unsetPreferredService(this)
        }
        turnstileActive = false
    }

    private fun reportTag(tag: Tag) {
        // Only cached protocol metadata is exposed. No identifier, APDU, or pass data is read.
        val data = mutableMapOf<String, Any>(
            "technologies" to tag.techList.map { it.substringAfterLast('.') },
        )
        NfcA.get(tag)?.let { nfcA ->
            data["atqa"] = nfcA.atqa.joinToString("") { "%02X".format(it.toInt() and 0xFF) }
            data["sak"] = "%02X".format(nfcA.sak)
        }
        IsoDep.get(tag)?.let { isoDep ->
            data["historicalBytesLength"] = isoDep.historicalBytes?.size ?: 0
            data["hiLayerResponseLength"] = isoDep.hiLayerResponse?.size ?: 0
            data["maxTransceiveLength"] = isoDep.maxTransceiveLength
            data["extendedApduSupported"] = isoDep.isExtendedLengthApduSupported
        }
        runOnUiThread {
            if (readerRequested) nfcChannel?.invokeMethod("tagDetected", data)
        }
    }

    override fun onPause() {
        stopPassQueue()
        disableDiagnosticsReader()
        stopTurnstileProbe()
        super.onPause()
    }

    private fun stopPassQueue() {
        PassQueue.stop()
        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        NfcAdapter.getDefaultAdapter(this)?.let {
            if (packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION)) {
                try { CardEmulation.getInstance(it).unsetPreferredService(this) } catch (_: Exception) { }
                try {
                    CardEmulation.getInstance(it).removeAidsForService(
                        ComponentName(this, DigitalPassService::class.java), CardEmulation.CATEGORY_OTHER,
                    )
                } catch (_: Exception) { }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (readerRequested) {
            NfcAdapter.getDefaultAdapter(this)?.takeIf { it.isEnabled }?.let {
                enableDiagnosticsReader(it)
            }
        }
        if (turnstileRequested && Build.VERSION.SDK_INT >= 35) {
            NfcAdapter.getDefaultAdapter(this)?.takeIf { it.isEnabled }?.let {
                try {
                    val mode = startTurnstileProbeOrFallback(it)
                    turnstileChannel?.invokeMethod("modeChanged", mode)
                } catch (_: Exception) {
                    turnstileRequested = false
                }
            }
        }
    }
}
