package com.example.japanese_learn

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews

class KotabiDictionarySearchWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, buildViews(context)) }
    }

    private fun buildViews(context: Context): RemoteViews =
        RemoteViews(context.packageName, R.layout.kotabi_dictionary_search_widget).apply {
            val openDictionary = openIntent(context)
            setOnClickPendingIntent(R.id.dictionary_search_widget, openDictionary)
            setOnClickPendingIntent(R.id.dictionary_search_bar, openDictionary)
            setOnClickPendingIntent(R.id.dictionary_search_mic, openDictionary)
        }

    private fun openIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse("kotabi://dictionary"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getActivity(context, 3001, intent, flags)
    }
}
