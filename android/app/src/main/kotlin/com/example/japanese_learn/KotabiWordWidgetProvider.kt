package com.example.japanese_learn

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.time.LocalDate

class KotabiWordWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, buildViews(context)) }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_CHECKIN -> {
                val pending = goAsync()
                Thread {
                    try {
                        performCheckin(context)
                    } finally {
                        updateAll(context)
                        pending.finish()
                    }
                }.start()
            }
        }
    }

    companion object {
        private const val PREFS = "kotabi_word_widget"
        private const val ACTION_CHECKIN = "com.example.japanese_learn.word_widget.CHECKIN"

        fun savePayload(context: Context, args: Map<*, *>) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            prefs.edit()
                .putString("wordId", args["wordId"]?.toString().orEmpty())
                .putString("word", args["word"]?.toString().orEmpty())
                .putString("reading", args["reading"]?.toString().orEmpty())
                .putString("meaningZh", args["meaningZh"]?.toString().orEmpty())
                .putString("partOfSpeech", args["partOfSpeech"]?.toString().orEmpty())
                .putString("jlptLevel", args["jlptLevel"]?.toString().orEmpty())
                .putBoolean("checkedInToday", args["checkedInToday"] as? Boolean ?: false)
                .putInt("streakDays", (args["streakDays"] as? Number)?.toInt() ?: 0)
                .putString("baseUrl", args["baseUrl"]?.toString().orEmpty())
                .putString("accessToken", args["accessToken"]?.toString().orEmpty())
                .putString("updatedAt", args["updatedAt"]?.toString().orEmpty())
                .apply()
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, KotabiWordWidgetProvider::class.java))
            ids.forEach { manager.updateAppWidget(it, buildViews(context)) }
        }

        private fun buildViews(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val word = prefs.getString("word", "").orEmpty().ifBlank { "今日一词" }
            val reading = prefs.getString("reading", "").orEmpty()
            val meaning = prefs.getString("meaningZh", "").orEmpty().ifBlank { "打开 App 后会同步今日单词" }
            val pos = prefs.getString("partOfSpeech", "").orEmpty()
            val level = prefs.getString("jlptLevel", "").orEmpty()
            val checkedIn = prefs.getBoolean("checkedInToday", false)

            return RemoteViews(context.packageName, R.layout.kotabi_word_widget).apply {
                setTextViewText(R.id.widget_word, word)
                setTextViewText(R.id.widget_reading, reading)
                setTextViewText(R.id.widget_meaning, meaning)
                setTextViewText(R.id.widget_tags, listOf(level, pos).filter { it.isNotBlank() }.joinToString(" · "))
                setTextViewText(R.id.widget_checkin, if (checkedIn) "已签到" else "签到")
                setInt(
                    R.id.widget_checkin,
                    "setBackgroundResource",
                    if (checkedIn) R.drawable.widget_button_done else R.drawable.widget_action_tile_primary
                )
                setOnClickPendingIntent(R.id.widget_checkin, checkinIntent(context))
                setOnClickPendingIntent(R.id.widget_search, openIntent(context, "kotabi://dictionary"))
                setOnClickPendingIntent(R.id.widget_card, openIntent(context, "kotabi://home"))
            }
        }

        private fun checkinIntent(context: Context): PendingIntent {
            val intent = Intent(context, KotabiWordWidgetProvider::class.java).setAction(ACTION_CHECKIN)
            return PendingIntent.getBroadcast(context, 2001, intent, pendingFlags())
        }

        private fun openIntent(context: Context, uri: String): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .setData(Uri.parse(uri))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            return PendingIntent.getActivity(context, uri.hashCode(), intent, pendingFlags())
        }

        private fun pendingFlags(): Int =
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

        private fun performCheckin(context: Context) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (prefs.getBoolean("checkedInToday", false)) return
            val token = prefs.getString("accessToken", "").orEmpty()
            val baseUrl = prefs.getString("baseUrl", "").orEmpty()
            if (token.isBlank() || baseUrl.isBlank()) return

            val connection = (URL("$baseUrl/progress/checkin").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 10000
                readTimeout = 10000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer $token")
                setRequestProperty("X-Client-Date", LocalDate.now().toString())
            }
            OutputStreamWriter(connection.outputStream).use { it.write("{}") }
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (code in 200..299) {
                val data = JSONObject(body)
                prefs.edit()
                    .putBoolean("checkedInToday", true)
                    .putInt("streakDays", data.optInt("streak_days", prefs.getInt("streakDays", 0)))
                    .apply()
            }
            connection.disconnect()
        }
    }
}
