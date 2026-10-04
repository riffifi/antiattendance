package com.example.antiattendance

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.Locale

internal object UpdateNotifier {
    const val ACTION_OPEN = "com.example.antiattendance.OPEN_UPDATES"
    private const val CHANNEL = "app_updates"
    private const val JOB = 7301
    private const val NOTIFICATION = 7302
    fun preferences(context: Context) = context.getSharedPreferences("update_notifications", Context.MODE_PRIVATE)
    fun configure(context: Context, language: String?) {
        preferences(context).edit().putString("language", language).apply()
        val scheduler = context.getSystemService(JobScheduler::class.java)
        if (scheduler.getPendingJob(JOB) == null) {
            scheduler.schedule(JobInfo.Builder(JOB, ComponentName(context, UpdateCheckJob::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPeriodic(12 * 60 * 60 * 1000L)
                .setPersisted(true)
                .build())
        }
    }
    fun localized(context: Context): Context {
        val language = preferences(context).getString("language", null) ?: return context
        val config = Configuration(context.resources.configuration)
        config.setLocale(Locale.forLanguageTag(language))
        return context.createConfigurationContext(config)
    }
    @Suppress("DEPRECATION")
    fun isNewer(context: Context, tag: String): Boolean {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val build = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        return ReleaseVersion.isNewer(tag, info.versionName ?: return false, build)
    }
    @Synchronized
    fun show(context: Context, tag: String): Boolean {
        if (!isNewer(context, tag)) return false
        val prefs = preferences(context)
        if (prefs.getString("last_notified", null) == tag) return false
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return false
        val textContext = localized(context)
        if (Build.VERSION.SDK_INT >= 26) {
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL, textContext.getString(R.string.updates_channel), NotificationManager.IMPORTANCE_DEFAULT))
        }
        val intent = Intent(context, MainActivity::class.java).setAction(ACTION_OPEN)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = PendingIntent.getActivity(context, NOTIFICATION, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_update_notification)
            .setContentTitle(textContext.getString(R.string.update_available))
            .setContentText(textContext.getString(R.string.update_version_available, tag))
            .setContentIntent(pending).setAutoCancel(true).setOnlyAlertOnce(true).build()
        return try {
            manager.notify(NOTIFICATION, notification)
            prefs.edit().putString("last_notified", tag).apply()
            true
        } catch (_: SecurityException) { false }
    }
}

internal object ReleaseVersion {
    private fun parts(value: String): List<Long?>? {
        val match = Regex("^v?(\\d+)\\.(\\d+)\\.(\\d+)(?:\\+(\\d+))?$").matchEntire(value) ?: return null
        return (1..4).map { match.groupValues[it].toLongOrNull() }
    }
    fun isNewer(tag: String, installed: String, build: Long): Boolean {
        val release = parts(tag) ?: return false
        val current = parts(installed) ?: return false
        for (i in 0..2) {
            val left = release[i] ?: return false
            val right = current[i] ?: return false
            if (left != right) return left > right
        }
        return release[3]?.let { it > build } ?: false
    }
}
