package cn.edu.ubaa.ubaa_flutter.widgets

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import cn.edu.ubaa.ubaa_flutter.MainActivity
import cn.edu.ubaa.ubaa_flutter.R

private val rowSlots = intArrayOf(R.id.widget_slot_1, R.id.widget_slot_2, R.id.widget_slot_3)
private const val PENDING_FLAGS = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

internal fun widgetOpenIntent(context: Context, link: String?): Intent =
    Intent(context, MainActivity::class.java).setAction(WIDGET_OPEN)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        .apply { if (!link.isNullOrEmpty()) putExtra(WIDGET_LINK, link) }

private fun RemoteViews.open(context: Context, target: Int, id: Int, slot: Int, link: String?) {
    setOnClickPendingIntent(
        target,
        PendingIntent.getActivity(context, widgetRequestCode(id, slot), widgetOpenIntent(context, link), PENDING_FLAGS),
    )
}

private fun RemoteViews.show(view: Int, visible: Boolean) {
    setViewVisibility(view, if (visible) View.VISIBLE else View.GONE)
}

private fun RemoteViews.line(view: Int, text: String?) {
    setTextViewText(view, text)
    show(view, !text.isNullOrEmpty())
}

private fun RemoteViews.color(context: Context, view: Int, color: Int) {
    setTextColor(view, context.getColor(color))
}

private fun RemoteViews.scheduleMessage(context: Context, publication: WidgetPublication, segment: CardSegment?) {
    val missing = publication == WidgetPublication.Missing
    line(R.id.widget_message, segment?.message ?: context.getString(
        if (missing) R.string.widget_missing else R.string.widget_needs_update,
    ))
    line(R.id.widget_hint, when {
        missing -> context.getString(R.string.widget_load_schedule)
        segment == null || segment.state == "partial" -> context.getString(R.string.widget_update)
        else -> null
    })
}

internal fun renderUpNext(
    context: Context, id: Int, publication: WidgetPublication, now: Long, compact: Boolean,
): RemoteViews {
    val snapshot = (publication as? WidgetPublication.Available)?.snapshot
    val segment = snapshot?.segment(snapshot.upNext, now)
    val primary = segment?.primary
    return RemoteViews(context.packageName, if (compact) R.layout.widget_up_next_compact else R.layout.widget_up_next).apply {
        open(context, R.id.widget_root, id, 0, segment?.cardLink)
        show(R.id.widget_content, primary != null)
        if (primary == null) {
            scheduleMessage(context, publication, segment)
        } else {
            show(R.id.widget_message, false)
            show(R.id.widget_hint, false)
            val end = primary.endText?.takeIf { it.isNotEmpty() && primary.ongoing }
            setTextViewText(R.id.widget_time, end?.let { context.getString(R.string.widget_until, it) } ?: primary.timeText)
            color(context, R.id.widget_time, if (primary.ongoing) R.color.widget_accent else R.color.widget_ink)
            line(R.id.widget_place, primary.place)
            setTextViewText(R.id.widget_item_title, primary.title)
            if (!compact) {
                val extra = segment.extraCount
                show(R.id.widget_top, primary.ongoing || !primary.tag.isNullOrEmpty() || extra > 0)
                show(R.id.widget_ongoing, primary.ongoing)
                line(R.id.widget_tag, primary.tag)
                line(R.id.widget_extra, if (extra > 0) context.getString(R.string.widget_extra, extra) else null)
                val secondary = segment.secondary
                line(R.id.widget_secondary_line, secondary?.text)
                if (secondary != null) {
                    color(context, R.id.widget_secondary_line, if (secondary.kind == "exam") R.color.widget_accent else R.color.widget_tertiary)
                    open(context, R.id.widget_secondary_line, id, 1, secondary.link)
                }
            }
        }
    }
}

internal fun renderToday(
    context: Context, id: Int, publication: WidgetPublication, now: Long, visibleRows: Int,
): RemoteViews {
    val snapshot = (publication as? WidgetPublication.Available)?.snapshot
    val segment = snapshot?.segment(snapshot.today, now)
    val rows = segment?.rows.orEmpty()
    return RemoteViews(context.packageName, R.layout.widget_today).apply {
        open(context, R.id.widget_root, id, 0, segment?.cardLink)
        setTextViewText(R.id.widget_title, segment?.dayLabel?.takeIf { it.isNotEmpty() } ?: context.getString(R.string.widget_today))
        if (rows.isEmpty()) {
            line(R.id.widget_more, null)
            line(R.id.widget_due, null)
            scheduleMessage(context, publication, segment)
        } else {
            val more = rows.size - visibleRows
            line(R.id.widget_more, if (more > 0) context.getString(R.string.widget_more, more) else null)
            val due = segment?.dueLine?.takeIf { it.isNotEmpty() }
            line(R.id.widget_due, if (more > 0 && due != null) " · $due" else due)
            show(R.id.widget_message, false)
            show(R.id.widget_hint, false)
        }
        fillSlots(rows.take(visibleRows)) { row, slot ->
            RemoteViews(context.packageName, R.layout.widget_today_row).apply {
                open(context, R.id.widget_row, id, slot, row.link)
                setInt(R.id.widget_row, "setBackgroundResource", if (row.ongoing) R.drawable.widget_row_ongoing else 0)
                setTextViewText(R.id.widget_time, row.timeText)
                val end = row.endText?.takeIf { it.isNotEmpty() && !row.ongoing }
                setTextViewText(R.id.widget_end, end?.let { context.getString(R.string.widget_until, it) })
                setViewVisibility(R.id.widget_end, when {
                    row.ongoing -> View.GONE
                    end == null -> View.INVISIBLE
                    else -> View.VISIBLE
                })
                show(R.id.widget_ongoing, row.ongoing)
                line(R.id.widget_tag, row.tag)
                setTextViewText(R.id.widget_item_title, row.title)
                line(R.id.widget_place, row.place)
            }
        }
    }
}

private fun <Row> RemoteViews.fillSlots(rows: List<Row>, render: (Row, Int) -> RemoteViews) {
    rowSlots.forEachIndexed { index, target ->
        val row = rows.getOrNull(index)
        removeAllViews(target)
        show(target, row != null)
        if (row != null) addView(target, render(row, index + 1))
    }
}

internal fun renderTodo(
    context: Context, id: Int, publication: WidgetPublication, now: Long, small: Boolean,
): RemoteViews {
    val snapshot = (publication as? WidgetPublication.Available)?.snapshot
    val segment = snapshot?.segment(snapshot.todo, now)
    val layout = if (small) R.layout.widget_todo_small else R.layout.widget_todo_medium
    return RemoteViews(context.packageName, layout).apply {
        open(context, R.id.widget_root, id, 0, segment?.cardLink)
        val footer = if (small) segment?.smallFooter else segment?.mediumFooter
        line(R.id.widget_footer, listOfNotNull(footer, segment?.staleText).filter { it.isNotEmpty() }.joinToString(" · "))
        val items = segment?.state == "items"
        if (items) show(R.id.widget_message, false)
        else line(R.id.widget_message, segment?.message ?: context.getString(
            if (publication == WidgetPublication.Missing) R.string.widget_load_todo else R.string.widget_update,
        ))
        if (small) {
            show(R.id.widget_footer_spacer, !items)
            show(R.id.widget_content, items)
            segment?.smallRow?.let { row ->
                open(context, R.id.widget_content, id, 4, row.link)
                todoRow(context, row)
            }
        } else {
            fillSlots(segment?.mediumRows.orEmpty()) { row, slot ->
                RemoteViews(context.packageName, R.layout.widget_todo_row).apply {
                    open(context, R.id.widget_row, id, slot, row.link)
                    val bar = if (row.kind == "exam") R.color.widget_accent else R.color.widget_tertiary
                    setInt(R.id.widget_bar, "setBackgroundColor", context.getColor(bar))
                    todoRow(context, row)
                }
            }
        }
    }
}

private fun RemoteViews.todoRow(context: Context, row: TodoSegment.Row) {
    setTextViewText(R.id.widget_time, row.leftText)
    color(context, R.id.widget_time, if (row.urgent) R.color.widget_accent else R.color.widget_ink)
    setTextViewText(R.id.widget_item_title, row.title)
    line(R.id.widget_sub, row.sub)
}

internal fun renderWeek(
    context: Context, id: Int, publication: WidgetPublication, selected: SelectedWeek?, width: Int, height: Int,
    pixelBudget: Int = WEEK_BITMAP_PIXEL_LIMIT,
): RemoteViews = RemoteViews(context.packageName, R.layout.schedule_widget).apply {
    open(context, R.id.widget_root, id, 0, null)
    show(R.id.widget_grid, selected != null)
    val buttons = listOf(R.id.widget_previous to -1, R.id.widget_next to 1, R.id.widget_current to 0)
    buttons.forEach { (view, _) -> show(view, selected != null) }
    if (selected == null) {
        setTextViewText(R.id.widget_title, context.getString(R.string.widget_week))
        setImageViewBitmap(R.id.widget_grid, null)
        scheduleMessage(context, publication, null)
    } else {
        show(R.id.widget_message, false)
        show(R.id.widget_hint, false)
        buttons.forEach { (view, step) ->
            val intent = Intent(context, ScheduleWidgetProvider::class.java)
                .setAction(ScheduleWidgetProvider.ACTION_WEEK)
                .setData(Uri.parse("ubaa-widget://week/$id/$step"))
                .putExtra(android.appwidget.AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                .putExtra("step", step)
            setOnClickPendingIntent(view, PendingIntent.getBroadcast(context, id, intent, PENDING_FLAGS))
        }
        setBoolean(R.id.widget_previous, "setEnabled", selected.week != selected.semester.weeks.first())
        setBoolean(R.id.widget_next, "setEnabled", selected.week != selected.semester.weeks.last())
        setTextViewText(R.id.widget_title, "${selected.week.name} · ${selected.week.startDate.substring(5)}")
        setImageViewBitmap(R.id.widget_grid, renderScheduleWidget(context, selected.week, width, height, pixelBudget))
        setContentDescription(R.id.widget_grid, selected.week.name)
    }
}
