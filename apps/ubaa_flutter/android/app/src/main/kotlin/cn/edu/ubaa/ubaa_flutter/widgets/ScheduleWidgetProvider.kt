package cn.edu.ubaa.ubaa_flutter.widgets

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.widget.RemoteViews
import cn.edu.ubaa.ubaa_flutter.R
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.Executors
import org.json.JSONObject

open class ScheduleWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = runAsync {
        redraw(context, manager, ids)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        options: Bundle,
    ) = runAsync { redraw(context, manager, intArrayOf(id), options = options) }

    override fun onDeleted(context: Context, ids: IntArray) = runAsync {
        if (javaClass == ScheduleWidgetProvider::class.java) runCatching { WidgetStore.remove(context, ids) }
    }

    override fun onDisabled(context: Context) = runAsync {
        if (instances(context, AppWidgetManager.getInstance(context)).isEmpty()) {
            setRefresh(context, null)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_REFRESH -> runAsync { refreshAll(context) }
            ACTION_WEEK -> {
                val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
                val step = intent.getIntExtra("step", Int.MAX_VALUE)
                if (id >= 0 && step in -1..1) runAsync {
                    redraw(context, AppWidgetManager.getInstance(context), intArrayOf(id), step)
                }
            }
            else -> super.onReceive(context, intent)
        }
    }

    private fun runAsync(action: () -> Unit) {
        val pending = goAsync()
        executor.execute {
            try {
                action()
            } finally {
                pending?.finish()
            }
        }
    }

    companion object {
        internal val executor = Executors.newSingleThreadExecutor()
        internal const val ACTION_WEEK = "cn.edu.ubaa.ubaa_flutter.widgets.WEEK"
        private const val ACTION_REFRESH = "cn.edu.ubaa.widget.REFRESH"
        private const val REFRESH_REQUEST = 0
        private const val REFRESH_WINDOW_MS = 10 * 60 * 1_000L
        private val campusZone = ZoneId.of("Asia/Shanghai")
        private val providers = listOf(
            ScheduleWidgetProvider::class.java,
            TodayScheduleWidgetProvider::class.java,
            UpcomingScheduleWidgetProvider::class.java,
            TodoWidgetProvider::class.java,
        )

        private fun instances(context: Context, manager: AppWidgetManager): IntArray =
            providers.flatMap { manager.getAppWidgetIds(ComponentName(context, it)).asList() }.toIntArray()

        internal fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            redraw(context, manager, instances(context, manager))
        }

        private fun setRefresh(context: Context, next: Long?) {
            val intent = Intent(context, ScheduleWidgetProvider::class.java).setAction(ACTION_REFRESH)
            val alarm = context.getSystemService(AlarmManager::class.java)
            val pending = PendingIntent.getBroadcast(
                context, REFRESH_REQUEST, intent,
                PendingIntent.FLAG_IMMUTABLE or
                    if (next == null) PendingIntent.FLAG_NO_CREATE else PendingIntent.FLAG_UPDATE_CURRENT,
            ) ?: return
            if (next == null) alarm.cancel(pending)
            else alarm.setWindow(AlarmManager.RTC, next * 1_000, REFRESH_WINDOW_MS, pending)
        }

        private fun redraw(
            context: Context,
            manager: AppWidgetManager,
            ids: IntArray,
            step: Int? = null,
            options: Bundle? = null,
        ) {
            if (ids.isEmpty()) {
                setRefresh(context, null)
                return
            }
            val publication = WidgetStore.publication(context)
            val now = Instant.now().epochSecond
            val date = Instant.ofEpochSecond(now).atZone(campusZone).toLocalDate()
            ids.forEach { id ->
                val provider = manager.getAppWidgetInfo(id)?.provider ?: return@forEach
                val size = options ?: manager.getAppWidgetOptions(id)
                val views = if (provider.className == ScheduleWidgetProvider::class.java.name)
                    weekly(context, publication, date, id, size, step)
                else renderResponsiveCard(context, provider.className, id, publication, now, size) ?: return@forEach
                manager.updateAppWidget(id, views)
            }
            val next = (publication as? WidgetPublication.Available)?.snapshot?.nextRefresh(now)
            setRefresh(context, next)
        }

        private fun weekly(
            context: Context,
            publication: WidgetPublication,
            date: LocalDate,
            id: Int,
            options: Bundle,
            step: Int?,
        ): RemoteViews {
            val available = publication as? WidgetPublication.Available
            val snapshot = available?.snapshot
            val anchor = date.minusDays(date.dayOfWeek.value - 1L).toString()
            val choice = available?.choices?.optJSONObject(id.toString())
                ?.takeIf { step != 0 && it.optString("anchor") == anchor }
            val selected = selectSavedScheduleWeek(
                snapshot?.semesters.orEmpty(), date, choice?.optString("term"), choice?.optInt("week"),
            )?.let { current ->
                val weeks = current.semester.weeks
                current.copy(week = weeks.getOrNull(weeks.indexOf(current.week) + (step ?: 0)) ?: current.week)
            }
            if (selected != null && snapshot != null) {
                val saved = runCatching {
                    WidgetStore.select(context, id, snapshot.owner, anchor, selected.semester.termCode, selected.week.serialNumber)
                }
                if (saved.isFailure) return renderWeek(context, id, WidgetPublication.Unreadable, null, 250, 180)
            }
            return renderWeeklyLayouts(context, publication, selected, id, options)
        }
    }
}

internal fun renderResponsiveCard(
    context: Context, provider: String, id: Int, publication: WidgetPublication, now: Long, options: Bundle,
    sdkInt: Int = Build.VERSION.SDK_INT,
): RemoteViews? {
    fun responsive(small: SizeF, large: SizeF, byWidth: Boolean = false, render: (Boolean) -> RemoteViews): RemoteViews {
        if (sdkInt >= 31) return RemoteViews(mapOf(small to render(true), large to render(false)))
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, small.width.toInt())
        val maxWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, minWidth)
        val maxHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, large.height.toInt())
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, maxHeight)
        fun layout(width: Int, height: Int) = render(if (byWidth) width < large.width else height < large.height)
        return RemoteViews(layout(maxWidth, minHeight), layout(minWidth, maxHeight))
    }

    return when (provider) {
        TodayScheduleWidgetProvider::class.java.name -> responsive(
            SizeF(110f, 110f), SizeF(110f, 140f),
        ) { compact -> renderUpNext(context, id, publication, now, compact) }
        UpcomingScheduleWidgetProvider::class.java.name -> responsive(
            SizeF(250f, 110f), SizeF(250f, 160f),
        ) { compact -> renderToday(context, id, publication, now, if (compact) 2 else 3) }
        TodoWidgetProvider::class.java.name -> responsive(
            SizeF(110f, 80f), SizeF(250f, 80f), byWidth = true,
        ) { small -> renderTodo(context, id, publication, now, small) }
        else -> null
    }
}

internal fun renderWeeklyLayouts(
    context: Context, publication: WidgetPublication, selected: SelectedWeek?, id: Int, options: Bundle,
): RemoteViews {
    val portraitWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
    val portraitHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 380)
    val landscapeWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, portraitWidth)
    val landscapeHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, portraitHeight)
    if (selected == null || portraitWidth == landscapeWidth && portraitHeight == landscapeHeight) {
        return renderWeek(context, id, publication, selected, portraitWidth, portraitHeight)
    }
    val portraitSize = weekGridSize(context, portraitWidth, portraitHeight)
    val landscapeSize = weekGridSize(context, landscapeWidth, landscapeHeight)
    val portraitArea = portraitSize.width.toLong() * portraitSize.height
    val landscapeArea = landscapeSize.width.toLong() * landscapeSize.height
    val total = portraitArea + landscapeArea
    val portraitBudget = if (total <= WEEK_BITMAP_PIXEL_LIMIT) portraitArea.toInt() else
        (WEEK_BITMAP_PIXEL_LIMIT * (portraitArea.toDouble() / total)).toInt().coerceIn(1, WEEK_BITMAP_PIXEL_LIMIT - 1)
    val landscapeBudget = WEEK_BITMAP_PIXEL_LIMIT - portraitBudget
    return RemoteViews(
        renderWeek(context, id, publication, selected, landscapeWidth, landscapeHeight, landscapeBudget),
        renderWeek(context, id, publication, selected, portraitWidth, portraitHeight, portraitBudget),
    )
}

internal sealed interface WidgetPublication {
    data object Missing : WidgetPublication
    data object Unreadable : WidgetPublication
    data class Available(val snapshot: WidgetSnapshot, val choices: JSONObject? = null) : WidgetPublication
}

class TodayScheduleWidgetProvider : ScheduleWidgetProvider()
class UpcomingScheduleWidgetProvider : ScheduleWidgetProvider()
class TodoWidgetProvider : ScheduleWidgetProvider()
