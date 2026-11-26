package cn.edu.ubaa.ubaa_flutter.widgets

// 绘制结构来自冻结UBAA旧版，MIT许可；仅替换本地模型与java.time日期适配。

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import androidx.core.graphics.ColorUtils
import cn.edu.ubaa.ubaa_flutter.R
import java.time.LocalDate
import kotlin.math.roundToInt
import kotlin.math.sqrt

internal const val WEEK_BITMAP_PIXEL_LIMIT = 1_500_000

internal fun weekGridSize(context: Context, widthDp: Int, heightDp: Int): android.util.Size {
    val resources = context.resources
    val density = resources.displayMetrics.density
    val padding = resources.getDimensionPixelSize(R.dimen.widget_padding)
    val header = resources.getDimensionPixelSize(R.dimen.widget_week_header_height)
    val widthPx = ((widthDp * density).roundToInt() - 2 * padding).coerceAtLeast(1)
    val heightPx = ((heightDp * density).roundToInt() - 2 * padding - header).coerceAtLeast(1)
    return android.util.Size(widthPx, heightPx)
}

/** 原生 Canvas 按位图预算绘制七天网格。 */
internal fun renderScheduleWidget(
    context: Context,
    week: WidgetWeek,
    widthDp: Int,
    heightDp: Int,
    pixelBudget: Int = WEEK_BITMAP_PIXEL_LIMIT,
): Bitmap {
    val resources = context.resources
    val density = resources.displayMetrics.density
    val size = weekGridSize(context, widthDp, heightDp)
    val reduction = sqrt(pixelBudget / (size.width.toDouble() * size.height)).coerceAtMost(1.0)
    val bitmapWidth = (size.width * reduction).toInt().coerceIn(1, pixelBudget)
    val bitmapHeight = (size.height * reduction).toInt().coerceIn(1, pixelBudget / bitmapWidth)
    val bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888)
    bitmap.density = Bitmap.DENSITY_NONE
    val dark = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
    val width = size.width / density
    val height = size.height / density
    val canvas = Canvas(bitmap)
    canvas.scale(bitmap.width / width, bitmap.height / height)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    val text =
        TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = context.getColor(R.color.widget_ink)
            textSize = 10f
        }
    val courses = week.arrangedList
    val times = week.times
    val periods = times.size
    val left = 38f
    val top = 30f
    val column = (width - left) / 7f
    val row = (height - top) / periods
    val start = LocalDate.parse(week.startDate)
    listOf("一", "二", "三", "四", "五", "六", "日").forEachIndexed { index, day ->
        val center = left + column * (index + 0.5f)
        text.textAlign = Paint.Align.CENTER
        canvas.drawText("周$day", center, 11f, text)
        canvas.drawText(start.plusDays(index.toLong()).toString().substring(5), center, 25f, text)
    }
    paint.color = if (dark) 0x1AFFFFFF else 0x12000000
    for (i in 0..periods) canvas.drawLine(
        left,
        top + i * row,
        width.toFloat(),
        top + i * row,
        paint,
    )
    for (i in 0..7) canvas.drawLine(
        left + i * column,
        top,
        left + i * column,
        height.toFloat(),
        paint,
    )
    times.forEachIndexed { i, slot ->
        val y = top + i * row
        text.textSize = 8f
        canvas.drawText(slot.section.toString(), 5f, y + row * 0.6f, text)
        text.textSize = 7f
        canvas.drawText(slot.start ?: "--:--", 25f, y + row * 0.42f, text)
        canvas.drawText(slot.end ?: "--:--", 25f, y + row * 0.92f, text)
    }
    text.textSize = 10f
    text.textAlign = Paint.Align.LEFT
    courses
        .groupBy { it.dayOfWeek }
        .forEach { (day, items) ->
            if (day == null || day !in 1..7) return@forEach
            val sorted = items.sortedWith(compareBy({ it.beginSection }, { it.endSection }))
            // 同时段的课程并排摆放，避免卡片互相覆盖。
            val lanes = mutableListOf<Int>()
            val placed =
                sorted.map { course ->
                    val begin = course.beginSection ?: 1
                    var lane = lanes.indexOfFirst { it < begin }
                    if (lane < 0) {
                        lane = lanes.size
                        lanes.add(0)
                    }
                    lanes[lane] = course.endSection ?: begin
                    course to lane
                }
            val laneWidth = column / lanes.size.coerceAtLeast(1)
            placed.forEach { (course, lane) ->
                val begin = (course.beginSection ?: 1).coerceIn(1, periods)
                val end = (course.endSection ?: begin).coerceIn(begin, periods)
                val rect =
                    RectF(
                        left + (day - 1) * column + lane * laneWidth + 1f,
                        top + (begin - 1) * row + 1f,
                        left + (day - 1) * column + (lane + 1) * laneWidth - 1f,
                        top + end * row - 1f,
                    )
                paint.color = courseTint(course.courseName, dark)
                text.color = if (dark) Color.rgb(245, 247, 250) else Color.rgb(31, 41, 56)
                canvas.drawRoundRect(rect, 4f, 4f, paint)
                val label =
                    "${course.courseName}\n${course.beginTime.orEmpty()}\n${course.placeName.orEmpty()}"
                val textWidth = (rect.width() - 4).toInt().coerceAtLeast(1)
                val maxLines = ((rect.height() - 4) / 12f).toInt().coerceAtLeast(1)
                val layout =
                    StaticLayout.Builder.obtain(label, 0, label.length, text, textWidth)
                        .setAlignment(Layout.Alignment.ALIGN_CENTER)
                        .setIncludePad(false)
                        .setMaxLines(maxLines)
                        .setEllipsize(TextUtils.TruncateAt.END)
                        .build()
                canvas.save()
                canvas.clipRect(rect)
                canvas.translate(rect.left + 2, rect.top + 2)
                layout.draw(canvas)
                canvas.restore()
            }
        }
    if (courses.isEmpty()) {
        text.textSize = 14f
        text.textAlign = Paint.Align.CENTER
        canvas.drawText(
            "本周没有已安排课程",
            width / 2f,
            height / 2f,
            text,
        )
    }
    return bitmap
}

private val courseHues = floatArrayOf(
    210f, 25f, 155f, 285f, 55f, 335f, 185f, 95f, 255f, 5f,
    130f, 310f, 235f, 75f, 175f, 45f, 270f, 355f, 115f, 195f,
)

private fun courseTint(name: String, dark: Boolean): Int {
    val seed = name.trim().codePoints().reduce(0) { result, scalar -> (result * 31 + scalar) and Int.MAX_VALUE }
    val hue = courseHues[seed % courseHues.size]
    return ColorUtils.HSLToColor(if (dark) floatArrayOf(hue, 0.42f, 0.30f) else floatArrayOf(hue, 0.62f, 0.82f))
}
