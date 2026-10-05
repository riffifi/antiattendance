package com.example.antiattendance

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject

internal object StudySummaryScheduler {
    const val ACTION_OPEN = "com.example.antiattendance.OPEN_STUDY_SUMMARY"
    const val JOB = 7401
    private fun today() = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
        .apply { timeZone = java.util.TimeZone.getTimeZone("Europe/Moscow") }.format(java.util.Date())
    private const val CHANNEL = "study_summary"
    fun prefs(context: Context) = context.getSharedPreferences("study_summary", Context.MODE_PRIVATE)
    private fun pending(context: Context, id: String) = PendingIntent.getBroadcast(context, 0,
        Intent(context, StudySummaryReceiver::class.java).setAction("com.example.antiattendance.SUMMARY")
            .setData(android.net.Uri.parse("antiattendance://summary/$id")).putExtra("id", id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    @Synchronized fun configure(context: Context, enabled: Boolean, tasks: List<*>?) {
        val prefs = prefs(context)
        val previous = JSONArray(prefs.getString("tasks", "[]"))
        val manager = context.getSystemService(AlarmManager::class.java)
        for (index in 0 until previous.length()) manager.cancel(pending(context, previous.getJSONObject(index).getString("id")))
        prefs.edit().putBoolean("enabled", enabled).apply()
        if (!enabled) {
            prefs.edit().remove("tasks").apply()
            context.getSystemService(JobScheduler::class.java).cancel(JOB)
            return
        }
        if (tasks != null) prefs.edit().putString("tasks", JSONArray(tasks).toString()).apply()
        schedule(context)
        val scheduler = context.getSystemService(JobScheduler::class.java)
        if (scheduler.getPendingJob(JOB) == null) scheduler.schedule(
            JobInfo.Builder(JOB, ComponentName(context, StudySummaryJob::class.java))
                .setPeriodic(24 * 60 * 60 * 1000L).setPersisted(true)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).build())
    }

    @Synchronized fun schedule(context: Context) {
        val prefs = prefs(context)
        if (!prefs.getBoolean("enabled", false)) return
        val tasks = JSONArray(prefs.getString("tasks", "[]"))
        val alarms = context.getSystemService(AlarmManager::class.java)
        for (index in 0 until tasks.length()) {
            val task = tasks.getJSONObject(index)
            val id = task.getString("id")
            if (prefs.getBoolean("sent_$id", false)) continue
            val at = task.getLong("at")
            // Don't replay notifications from earlier study days after reboot or enabling.
            val today = today()
            if (id < today) continue
            val trigger = maxOf(at, System.currentTimeMillis() + 1000)
            if (Build.VERSION.SDK_INT >= 23) alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pending(context, id))
            else alarms.set(AlarmManager.RTC_WAKEUP, trigger, pending(context, id))
        }
    }

    @Synchronized fun show(context: Context, id: String) {
        val prefs = prefs(context)
        if (!prefs.getBoolean("enabled", false) || prefs.getBoolean("sent_$id", false)) return
        val tasks = JSONArray(prefs.getString("tasks", "[]"))
        val task = (0 until tasks.length()).map { tasks.getJSONObject(it) }.firstOrNull { it.getString("id") == id } ?: return
        if (System.currentTimeMillis() < task.getLong("at")) { schedule(context); return }
        if (id != today()) return
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
        val people = task.getJSONArray("people")
        val lines = mutableListOf<String>()
        for (index in 0 until people.length()) {
            val person = people.getJSONObject(index)
            val expiry = if (person.isNull("sessionExpiresAt")) null else person.optLong("sessionExpiresAt")
            val expired = person.optBoolean("sessionExpired") || (expiry != null && expiry <= System.currentTimeMillis())
            lines.add("${person.getString("name")}: ${person.getString("counts")} ${task.getString("recorded")}${if (expired) " · ${task.getString("sessionReminder")}" else ""}")
            val classes = person.getJSONArray("lines")
            for (c in 0 until classes.length()) lines.add(classes.getString(c))
            lines.add("")
        }
        val title = task.getString("title")
        if (Build.VERSION.SDK_INT >= 26) context.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(NotificationChannel(CHANNEL, title, NotificationManager.IMPORTANCE_DEFAULT))
        val launch = PendingIntent.getActivity(context, 7402, Intent(context, MainActivity::class.java)
            .setAction(ACTION_OPEN).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val text = lines.joinToString("\n")
        val notice = NotificationCompat.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_update_notification)
            .setContentTitle("$title · $id").setContentText(lines.firstOrNull() ?: title)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text.take(16000)))
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).setContentIntent(launch)
            .setAutoCancel(true).setOnlyAlertOnce(true).build()
        try {
            NotificationManagerCompat.from(context).notify(7402, notice)
            prefs.edit().putBoolean("sent_$id", true).putString("last", task.toString()).apply()
        } catch (_: SecurityException) { }
    }
}

class StudySummaryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED -> StudySummaryScheduler.schedule(context)
            else -> intent.getStringExtra("id")?.let { StudySummaryScheduler.show(context, it) }
        }
    }
}
