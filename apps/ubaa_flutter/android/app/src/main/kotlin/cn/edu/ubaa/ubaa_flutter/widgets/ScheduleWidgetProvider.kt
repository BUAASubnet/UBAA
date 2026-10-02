package cn.edu.ubaa.ubaa_flutter.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import cn.edu.ubaa.ubaa_flutter.MainActivity
import cn.edu.ubaa.ubaa_flutter.R
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.Executors

open class ScheduleWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = runAsync {
        ids.forEach { update(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        options: Bundle,
    ) = runAsync { update(context, manager, id) }

    override fun onDeleted(context: Context, ids: IntArray) = runAsync {
        WidgetStore.remove(context, ids)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_WEEK) {
            val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
            val step = intent.getIntExtra("step", 0)
            if (step in -1..1)
                runAsync { update(context, AppWidgetManager.getInstance(context), id, step) }
        }
    }

    private fun runAsync(action: () -> Unit) {
        val pending = goAsync()
        executor.execute {
            try {
                action()
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        internal val executor = Executors.newSingleThreadExecutor()
        private const val ACTION_WEEK = "cn.edu.ubaa.ubaa_flutter.widgets.WEEK"
        private val providers =
            listOf(
                ScheduleWidgetProvider::class.java,
                TodayScheduleWidgetProvider::class.java,
                UpcomingScheduleWidgetProvider::class.java,
            )

        internal fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            providers.forEach { p ->
                manager.getAppWidgetIds(ComponentName(context, p)).forEach {
                    update(context, manager, it)
                }
            }
        }

        internal fun today(): LocalDate = LocalDate.now(ZoneId.of("Asia/Shanghai"))

        internal fun update(
            context: Context,
            manager: AppWidgetManager,
            id: Int,
            step: Int? = null,
        ) {
            val provider = manager.getAppWidgetInfo(id)?.provider ?: return
            if (providers.none { it.name == provider.className }) return
            val days =
                when (provider.className) {
                    TodayScheduleWidgetProvider::class.java.name -> 1
                    UpcomingScheduleWidgetProvider::class.java.name -> 3
                    else -> 0
                }
            val date = today()
            val anchor = date.minusDays((date.dayOfWeek.value - 1).toLong()).toString()
            val result = runCatching {
                val state = WidgetStore.read(context)
                val snapshot = state?.optJSONObject("snapshot")?.let(::parseWidgetSnapshot)
                val owner = state?.optString("owner")
                check(snapshot == null || snapshot.owner == owner)
                val choice = state?.optJSONObject("choices")?.optJSONObject(id.toString())
                val keep = days == 0 && step != 0 && choice?.optString("anchor") == anchor
                var selected =
                    selectSavedScheduleWeek(
                        snapshot?.semesters.orEmpty(),
                        date,
                        if (keep) choice?.optString("term") else null,
                        if (keep) choice?.optInt("week") else null,
                    )
                if (selected != null && days == 0 && step in listOf(-1, 1)) {
                    val weeks = selected.semester.weeks
                    selected =
                        selected.copy(
                            week =
                                weeks.getOrNull(weeks.indexOf(selected.week) + step!!)
                                    ?: selected.week
                        )
                }
                Triple(owner, snapshot, selected)
            }
            val owner = result.getOrNull()?.first
            val snapshot = result.getOrNull()?.second
            val selected = result.getOrNull()?.third
            val views = RemoteViews(context.packageName, R.layout.schedule_widget)
            val open =
                if (selected == null) Intent(context, MainActivity::class.java)
                else
                    Intent(context, ScheduleWidgetActivity::class.java)
                        .putExtra("owner", owner)
                        .putExtra("term", selected.semester.termCode)
                        .putExtra("week", selected.week.serialNumber)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getActivity(
                    context,
                    id,
                    open,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            listOf(R.id.widget_previous to -1, R.id.widget_next to 1, R.id.widget_current to 0)
                .forEach { (view, delta) ->
                    val intent =
                        Intent()
                            .setComponent(provider)
                            .setAction(ACTION_WEEK)
                            .setData(Uri.parse("ubaa-widget://week/$id/$delta"))
                            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                            .putExtra("step", delta)
                    views.setOnClickPendingIntent(
                        view,
                        PendingIntent.getBroadcast(
                            context,
                            id,
                            intent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        ),
                    )
                    views.setViewVisibility(view, if (days == 0) View.VISIBLE else View.GONE)
                }
            if (selected == null) {
                views.setViewVisibility(R.id.widget_grid, View.GONE)
                views.setImageViewBitmap(R.id.widget_grid, null)
                views.setViewVisibility(R.id.widget_message, View.VISIBLE)
                views.setTextViewText(
                    R.id.widget_title,
                    when (days) {
                        1 -> "今日课程"
                        3 -> "近日课程"
                        else -> "UBAA 周课表"
                    },
                )
                views.setTextViewText(
                    R.id.widget_message,
                    if (result.isFailure) "本地课表读取失败，请打开应用重新更新" else "请先打开 UBAA，登录并保存整个学期",
                )
                views.setTextViewText(R.id.widget_footer, "本地课表 · 点击打开应用")
                views.setBoolean(R.id.widget_previous, "setEnabled", false)
                views.setBoolean(R.id.widget_next, "setEnabled", false)
            } else {
                try {
                    WidgetStore.select(
                        context,
                        id,
                        owner!!,
                        anchor,
                        selected.semester.termCode,
                        selected.week.serialNumber,
                    )
                } catch (_: Exception) {
                    return updateUnavailable(context, manager, id, views)
                }
                val options = manager.getAppWidgetOptions(id)
                val width =
                    options
                        .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 320)
                        .coerceIn(110, 700) - 16
                val height =
                    options
                        .getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 400)
                        .coerceIn(100, 900) - 64
                if (days == 0 && width < 220)
                    views.setViewVisibility(R.id.widget_current, View.GONE)
                views.setTextViewText(
                    R.id.widget_title,
                    when (days) {
                        1 -> "今日课程 · ${date.toString().substring(5)}"
                        3 -> "近日课程 · 今天起三天"
                        else -> "${selected.week.name} · ${selected.week.startDate.substring(5)}"
                    },
                )
                views.setTextViewText(
                    R.id.widget_footer,
                    "本地课表 · 更新于 ${selected.semester.updatedAt}",
                )
                views.setViewVisibility(R.id.widget_message, View.GONE)
                views.setViewVisibility(R.id.widget_grid, View.VISIBLE)
                views.setImageViewBitmap(
                    R.id.widget_grid,
                    if (days == 0) renderScheduleWidget(selected.week, selected.week, width, height)
                    else
                        renderAgendaWidget(
                            savedAgenda(snapshot!!.semesters, date, days),
                            width,
                            height,
                        ),
                )
                views.setContentDescription(R.id.widget_grid, "${selected.week.name}，点击打开离线周课表。")
                views.setBoolean(
                    R.id.widget_previous,
                    "setEnabled",
                    selected.week != selected.semester.weeks.first(),
                )
                views.setBoolean(
                    R.id.widget_next,
                    "setEnabled",
                    selected.week != selected.semester.weeks.last(),
                )
            }
            manager.updateAppWidget(id, views)
        }

        private fun updateUnavailable(
            context: Context,
            manager: AppWidgetManager,
            id: Int,
            views: RemoteViews,
        ) {
            views.setViewVisibility(R.id.widget_grid, View.GONE)
            views.setImageViewBitmap(R.id.widget_grid, null)
            views.setViewVisibility(R.id.widget_message, View.VISIBLE)
            views.setTextViewText(R.id.widget_message, "本地课表更新失败，请打开应用重试")
            manager.updateAppWidget(id, views)
        }
    }
}

class TodayScheduleWidgetProvider : ScheduleWidgetProvider()

class UpcomingScheduleWidgetProvider : ScheduleWidgetProvider()
