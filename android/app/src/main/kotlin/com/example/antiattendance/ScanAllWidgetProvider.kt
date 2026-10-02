package com.example.antiattendance

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

open class ScanAllWidgetProvider : AppWidgetProvider() {
    protected open val layoutId: Int = R.layout.scan_all_widget

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val launch = Intent(context, MainActivity::class.java).apply {
            action = MainActivity.ACTION_SCAN_ALL
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        for (id in ids) {
            val views = RemoteViews(context.packageName, layoutId)
            views.setOnClickPendingIntent(R.id.scan_all_widget, pendingIntent)
            manager.updateAppWidget(id, views)
        }
    }
}

class ScanAllCompactWidgetProvider : ScanAllWidgetProvider() {
    override val layoutId: Int = R.layout.scan_all_widget_compact
}
