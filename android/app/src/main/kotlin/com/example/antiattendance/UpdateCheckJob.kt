package com.example.antiattendance

import android.app.job.JobParameters
import android.app.job.JobService
import android.os.Build
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.Future

class UpdateCheckJob : JobService() {
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private var work: Future<*>? = null
    @Volatile private var connection: HttpURLConnection? = null
    private var generation = 0
    override fun onStartJob(params: JobParameters): Boolean {
        val current = ++generation
        work = executor.submit {
            var retry = false
            var active: HttpURLConnection? = null
            try {
                val url = URL("https://api.github.com/repos/riffifi/antiattendance/releases/latest")
                val request = ((if (Build.VERSION.SDK_INT >= 28) params.network?.openConnection(url) else null)
                    ?: url.openConnection()) as HttpURLConnection
                active = request
                connection = request
                request.connectTimeout = 10000
                request.readTimeout = 10000
                request.setRequestProperty("Accept", "application/vnd.github+json")
                request.setRequestProperty("X-GitHub-Api-Version", "2022-11-28")
                request.setRequestProperty("User-Agent", "AntiAttendance-update-check")
                if (request.responseCode == 200) {
                    val bytes = request.inputStream.use { input ->
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            require(output.size() + count <= 1024 * 1024)
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    }
                    val release = JSONObject(String(bytes, Charsets.UTF_8))
                    val tag = release.getString("tag_name")
                    if (!Thread.currentThread().isInterrupted) UpdateNotifier.show(applicationContext, tag)
                } else if (request.responseCode != 404) retry = true
            } catch (_: Exception) { retry = true }
            finally { active?.disconnect(); if (connection === active) connection = null }
            handler.post { if (generation == current) jobFinished(params, retry) }
        }
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean {
        ++generation
        work?.cancel(true)
        connection?.disconnect()
        return true
    }
    override fun onDestroy() { executor.shutdownNow(); super.onDestroy() }
}
