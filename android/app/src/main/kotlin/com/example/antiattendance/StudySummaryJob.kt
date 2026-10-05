package com.example.antiattendance

import android.app.job.JobParameters
import android.app.job.JobService
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class StudySummaryJob : JobService() {
    private var engine: FlutterEngine? = null
    private val handler = Handler(Looper.getMainLooper())
    private var generation = 0
    override fun onStartJob(params: JobParameters): Boolean {
        val current = ++generation
        if (!StudySummaryScheduler.prefs(this).getBoolean("enabled", false)) return false
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        val worker = FlutterEngine(applicationContext)
        engine = worker
        MethodChannel(worker.dartExecutor.binaryMessenger, "antiattendance/study_summary")
            .setMethodCallHandler { call, result ->
                if (current != generation) { result.success(null); return@setMethodCallHandler }
                when (call.method) {
                    "configure" -> {
                        // A disabled setting wins even if a refresh was already in flight.
                        if (StudySummaryScheduler.prefs(this).getBoolean("enabled", false))
                            StudySummaryScheduler.configure(this, call.argument<Boolean>("enabled") == true, call.argument<List<*>>("tasks"))
                        result.success(null)
                    }
                    "finished" -> {
                        result.success(null)
                        val retry = call.argument<Boolean>("success") != true
                        handler.post { if (current == generation) { engine?.destroy(); engine = null; jobFinished(params, retry) } }
                    }
                    else -> result.notImplemented()
                }
            }
        worker.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "studySummaryBackground"))
        handler.postDelayed({ if (current == generation && engine != null) {
            ++generation; engine?.destroy(); engine = null; jobFinished(params, true)
        } }, 120000)
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean {
        ++generation; engine?.destroy(); engine = null; return true
    }
    override fun onDestroy() {
        ++generation; engine?.destroy(); engine = null; handler.removeCallbacksAndMessages(null); super.onDestroy()
    }
}
