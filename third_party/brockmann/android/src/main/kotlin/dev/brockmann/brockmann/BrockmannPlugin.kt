package dev.brockmann.brockmann

import android.app.Activity
import android.os.Build
import android.view.HapticFeedbackConstants
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Optional, preloaded sonification. No audio focus or permissions are requested. */
class BrockmannPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private var activity: Activity? = null
    private var hapticGeneration = 0
    private lateinit var channel: MethodChannel
    private lateinit var binding: FlutterPlugin.FlutterPluginBinding
    private lateinit var workerThread: HandlerThread
    private lateinit var worker: Handler
    private val main = Handler(Looper.getMainLooper())
    private var pool: SoundPool? = null
    private val samples = mutableMapOf<String, Int>()
    private val pending = mutableListOf<MethodChannel.Result>()
    private var ready = false
    private var generation = 0
    private val cues = listOf("activate", "select", "toggle-on", "toggle-off", "open", "close", "confirm", "reject")

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        workerThread = HandlerThread("BrockmannSoundAssets").also { it.start() }
        worker = Handler(workerThread.looper)
        channel = MethodChannel(binding.binaryMessenger, "dev.brockmann/feedback")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "haptics.play" -> result.success(haptic(call.argument<String>("cue")))
            "haptics.cancel" -> { hapticGeneration++; result.success(null) }
            "prepare" -> prepare(result)
            "play" -> {
                val cue = call.argument<String>("cue")
                val gain = call.argument<Number>("gain")?.toFloat() ?: 0f
                if (ready && gain.isFinite() && cue in samples) {
                    pool?.play(samples.getValue(cue!!), gain.coerceIn(0f, 1f), gain.coerceIn(0f, 1f), 1, 0, 1f)
                }
                result.success(null)
            }
            "stop" -> { release(); result.success(null) }
            "preferences.read" -> result.success(preferences().all)
            "preferences.write" -> {
                val editor = preferences().edit()
                (call.arguments as? Map<*, *>)?.forEach { (key, value) ->
                    if (key is String) when (value) {
                        is Boolean -> editor.putBoolean(key, value)
                        is String -> editor.putString(key, value)
                        is Int -> editor.putLong(key, value.toLong())
                        is Long -> editor.putLong(key, value)
                        is Double -> if (value.isFinite()) editor.putFloat(key, value.toFloat())
                        null -> editor.remove(key)
                    }
                }
                editor.apply()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun haptic(cue: String?): Boolean {
        val view = activity?.window?.decorView ?: return false
        if (!view.isAttachedToWindow || !view.hasWindowFocus()) return false
        val token = ++hapticGeneration
        val effect = when (cue) {
            "lift" -> if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.DRAG_START else HapticFeedbackConstants.LONG_PRESS
            "land" -> HapticFeedbackConstants.CLOCK_TICK
            "toggle-on" -> if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.TOGGLE_ON else HapticFeedbackConstants.CONTEXT_CLICK
            "toggle-off" -> if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.TOGGLE_OFF else HapticFeedbackConstants.CLOCK_TICK
            "select" -> if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.SEGMENT_TICK else HapticFeedbackConstants.CLOCK_TICK
            "activate" -> HapticFeedbackConstants.CONTEXT_CLICK
            "open" -> if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.GESTURE_START else HapticFeedbackConstants.VIRTUAL_KEY
            "close" -> if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.GESTURE_END else HapticFeedbackConstants.VIRTUAL_KEY_RELEASE
            "confirm", "reject" -> HapticFeedbackConstants.CLOCK_TICK
            else -> return false
        }
        // Short authored rhythms made from device-tuned ticks. Never bypass user settings.
        val played = view.performHapticFeedback(effect)
        val delays = when (cue) { "confirm" -> listOf(60L); "reject" -> listOf(70L, 140L); else -> emptyList() }
        if (played) delays.forEach { delay -> main.postDelayed({
            if (token == hapticGeneration && activity?.window?.decorView === view && view.isAttachedToWindow && view.hasWindowFocus()) {
                view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
            }
        }, delay) }
        return played
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { hapticGeneration++; activity = null }
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    private fun preferences() = binding.applicationContext.getSharedPreferences("brockmann", Context.MODE_PRIVATE)

    private fun prepare(result: MethodChannel.Result) {
        if (ready) { result.success(true); return }
        pending.add(result)
        if (pool != null) return
        val token = ++generation
        val soundPool = SoundPool.Builder().setMaxStreams(4).setAudioAttributes(
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        ).build()
        pool = soundPool
        var loaded = 0
        var failed = false
        soundPool.setOnLoadCompleteListener { _, _, status ->
            main.post {
                if (token == generation) {
                    failed = failed || status != 0
                    loaded++
                    if (loaded == cues.size) {
                        ready = !failed
                        val waiting = pending.toList(); pending.clear()
                        waiting.forEach { it.success(ready) }
                        if (failed) release()
                    }
                }
            }
        }
        worker.post {
            try {
                val ids = mutableMapOf<String, Int>()
                for (cue in cues) {
                    val path = binding.flutterAssets.getAssetFilePathByName("assets/sounds/$cue.wav", "brockmann")
                    val file = File(binding.applicationContext.cacheDir, "brockmann-$cue.wav")
                    binding.applicationContext.assets.open(path).use { input -> file.outputStream().use { input.copyTo(it) } }
                    val id = soundPool.load(file.path, 1)
                    check(id != 0) { "Sample could not be loaded" }
                    ids[cue] = id
                }
                main.post { if (token == generation) samples.putAll(ids) }
            } catch (_: Exception) {
                main.post { if (token == generation) release() }
            }
        }
    }

    private fun release() {
        generation++
        ready = false
        samples.clear()
        val old = pool; pool = null
        // Release after any current worker load; never race load against release.
        worker.post { old?.release() }
        val waiting = pending.toList(); pending.clear()
        waiting.forEach { it.success(false) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        hapticGeneration++
        activity = null
        channel.setMethodCallHandler(null)
        release()
        workerThread.quitSafely()
    }
}
