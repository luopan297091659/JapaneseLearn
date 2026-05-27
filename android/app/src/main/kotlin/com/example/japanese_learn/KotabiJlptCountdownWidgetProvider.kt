package com.example.japanese_learn

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import java.time.LocalDate
import java.time.temporal.ChronoUnit

class KotabiJlptCountdownWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, buildViews(context)) }
    }

    private fun buildViews(context: Context): RemoteViews {
        val exam = nextExam()
        val days = ChronoUnit.DAYS.between(LocalDate.now(), exam.date).coerceAtLeast(0)
        return RemoteViews(context.packageName, R.layout.kotabi_jlpt_countdown_widget).apply {
            setTextViewText(R.id.jlpt_countdown_badge, exam.label)
            setTextViewText(R.id.jlpt_countdown_days, days.toString())
            setTextViewText(R.id.jlpt_countdown_unit, if (days == 0L) "今天考试" else "天后考试")
            setTextViewText(
                R.id.jlpt_countdown_date,
                "${exam.date.year}.${exam.date.monthValue.toString().padStart(2, '0')}.${exam.date.dayOfMonth.toString().padStart(2, '0')}"
            )
            setOnClickPendingIntent(R.id.jlpt_countdown_widget, openStudyPlanIntent(context))
        }
    }

    private fun openStudyPlanIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse("kotabi://study-plan"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getActivity(context, 4001, intent, flags)
    }

    private fun nextExam(): JlptExam {
        val today = LocalDate.now()
        val exams = listOf(
            JlptExam("JLPT 7月", LocalDate.of(2026, 7, 5)),
            JlptExam("JLPT 12月", LocalDate.of(2026, 12, 6)),
        )
        return exams.firstOrNull { !it.date.isBefore(today) } ?: nextJuly(today.year + 1)
    }

    private fun nextJuly(year: Int): JlptExam {
        var date = LocalDate.of(year, 7, 1)
        while (date.dayOfWeek.value != 7) {
            date = date.plusDays(1)
        }
        return JlptExam("JLPT 7月", date)
    }

    private data class JlptExam(val label: String, val date: LocalDate)
}
