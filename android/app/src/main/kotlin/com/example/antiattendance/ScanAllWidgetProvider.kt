package com.example.antiattendance

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import java.util.Locale
import android.widget.RemoteViews

open class ScanAllWidgetProvider : AppWidgetProvider() {
    protected open val layoutId: Int = R.layout.scan_all_widget
    protected open val launchAction: String = MainActivity.ACTION_SCAN_ALL
    protected open val requestCode: Int = 0
    protected open val titleResource: Int = R.string.scan_all_widget_wide_title
    protected open val descriptionResource: Int = R.string.scan_all_widget_description
    protected open val compact: Boolean = false

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val language = context.getSharedPreferences("launcher_widgets", Context.MODE_PRIVATE).getString("language", null)
        val strings = if (language == null) context else context.createConfigurationContext(
            Configuration(context.resources.configuration).apply { setLocale(Locale.forLanguageTag(language)) },
        )
        val launch = Intent(context, MainActivity::class.java).apply {
            action = launchAction
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            requestCode,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        for (id in ids) {
            val views = RemoteViews(context.packageName, layoutId)
            if (!compact) views.setTextViewText(R.id.widget_title, strings.getString(titleResource))
            views.setContentDescription(R.id.scan_all_widget, strings.getString(descriptionResource))
            views.setContentDescription(R.id.widget_icon, strings.getString(descriptionResource))
            views.setOnClickPendingIntent(R.id.scan_all_widget, pendingIntent)
            manager.updateAppWidget(id, views)
        }
    }
}

class ScanAllCompactWidgetProvider : ScanAllWidgetProvider() {
    override val layoutId: Int = R.layout.scan_all_widget_compact
    override val compact: Boolean = true
}

open class NfcPassWidgetProvider : ScanAllWidgetProvider() {
    override val layoutId: Int = R.layout.nfc_pass_widget
    override val launchAction: String = MainActivity.ACTION_NFC_PASSES
    override val requestCode: Int = 1
    override val titleResource: Int = R.string.nfc_pass_widget_title
    override val descriptionResource: Int = R.string.nfc_pass_widget_description
}

class NfcPassCompactWidgetProvider : NfcPassWidgetProvider() {
    override val layoutId: Int = R.layout.nfc_pass_widget_compact
    override val compact: Boolean = true
}
