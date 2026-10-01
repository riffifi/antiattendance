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
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        const val ACTION_SCAN_ALL = "com.example.antiattendance.SCAN_ALL"
    }

    private var widgetChannel: MethodChannel? = null
    private var pendingWidgetScan = false
    private var nfcChannel: MethodChannel? = null
    private var readerRequested = false
    private var readerActive = false
    private var turnstileChannel: MethodChannel? = null
    private var turnstileRequested = false
    private var turnstileActive = false

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingWidgetScan = intent?.action == ACTION_SCAN_ALL
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antiattendance/launcher_widget")
        widgetChannel?.setMethodCallHandler { call, result ->
            if (call.method == "takeScanAllRequest") {
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
                        !packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION) ||
                            !adapter.isObserveModeSupported -> result.error("OBSERVE_UNAVAILABLE", "Observe Mode is not supported", null)
                        else -> {
                            turnstileRequested = true
                            try {
                                startTurnstileProbe(adapter)
                                result.success(null)
                            } catch (error: Exception) {
                                turnstileRequested = false
                                stopTurnstileProbe()
                                result.error("OBSERVE_ERROR", error.message, null)
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
    }

    override fun onNewIntent(newIntent: Intent) {
        super.onNewIntent(newIntent)
        setIntent(newIntent)
        if (newIntent.action != ACTION_SCAN_ALL) return
        pendingWidgetScan = true
        widgetChannel?.invokeMethod("scanAll", null, object : MethodChannel.Result {
            override fun success(result: Any?) {
                pendingWidgetScan = false
                newIntent.action = Intent.ACTION_MAIN
            }

            override fun error(code: String, message: String?, details: Any?) = Unit
            override fun notImplemented() = Unit
        })
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
            throw IllegalStateException("Could not select the NFC diagnostic service")
        }
        val enabled = try {
            adapter.setObserveModeEnabled(true)
        } catch (error: Exception) {
            emulation.unsetPreferredService(this)
            throw error
        }
        if (!enabled) {
            emulation.unsetPreferredService(this)
            throw IllegalStateException("Could not enable NFC Observe Mode")
        }
        TurnstileProbeBridge.onFrames = { frames ->
            runOnUiThread {
                if (turnstileActive) turnstileChannel?.invokeMethod("frames", frames)
            }
        }
        turnstileActive = true
    }

    private fun stopTurnstileProbe() {
        TurnstileProbeBridge.onFrames = null
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
        disableDiagnosticsReader()
        stopTurnstileProbe()
        super.onPause()
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
                    startTurnstileProbe(it)
                } catch (_: Exception) {
                    turnstileRequested = false
                }
            }
        }
    }
}
