package cn.edu.ubaa.widget

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import cn.edu.ubaa.model.dto.Week
import cn.edu.ubaa.model.dto.WeeklySchedule
import cn.edu.ubaa.model.dto.scheduleSectionTimes
import cn.edu.ubaa.repository.SavedAgendaItem
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.LocalDate
import kotlinx.datetime.plus

/** 原生 Canvas 绘制七天网格，RemoteViews 只携带一张有尺寸上限的图片。 */
internal fun renderScheduleWidget(
    week: Week,
    schedule: WeeklySchedule?,
    width: Int,
    height: Int,
): Bitmap {
  if (height < 230 || width < 240) return renderCompactWeek(week, schedule, width, height)
  val scale = 1.5f
  val bitmap =
      Bitmap.createBitmap(
          (width * scale).toInt(),
          (height * scale).toInt(),
          Bitmap.Config.ARGB_8888,
      )
  val canvas = Canvas(bitmap)
  canvas.scale(scale, scale)
  val paint = Paint(Paint.ANTI_ALIAS_FLAG)
  val text =
      TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(40, 58, 80)
        textSize = 10f
      }
  val courses = schedule?.arrangedList.orEmpty()
  val times = scheduleSectionTimes(listOfNotNull(schedule))
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
    canvas.drawText(start.plus(index, DateTimeUnit.DAY).toString().substring(5), center, 25f, text)
  }
  paint.color = Color.rgb(220, 229, 241)
  for (i in 0..periods) canvas.drawLine(left, top + i * row, width.toFloat(), top + i * row, paint)
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
          paint.color = Color.rgb(222, 234, 253)
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
  if (schedule == null || courses.isEmpty()) {
    text.textSize = 14f
    text.textAlign = Paint.Align.CENTER
    canvas.drawText(
        if (schedule == null) "此周数据缺失，请在应用内更新" else "本周没有已安排课程",
        width / 2f,
        height / 2f,
        text,
    )
  }
  return bitmap
}

private fun drawWidgetText(
    canvas: Canvas,
    value: String,
    x: Float,
    y: Float,
    width: Int,
    height: Int,
    size: Float,
) {
  val paint =
      TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(35, 57, 82)
        textSize = size
      }
  val layout =
      StaticLayout.Builder.obtain(value, 0, value.length, paint, width.coerceAtLeast(1))
          .setIncludePad(false)
          .setMaxLines((height / (size * 1.2f)).toInt().coerceAtLeast(1))
          .setEllipsize(TextUtils.TruncateAt.END)
          .build()
  canvas.save()
  canvas.clipRect(x, y, x + width, y + height)
  canvas.translate(x, y)
  layout.draw(canvas)
  canvas.restore()
}

private fun renderCompactWeek(
    week: Week,
    schedule: WeeklySchedule?,
    width: Int,
    height: Int,
): Bitmap {
  val bitmap = Bitmap.createBitmap(width * 2, height * 2, Bitmap.Config.ARGB_8888)
  val canvas = Canvas(bitmap).apply { scale(2f, 2f) }
  val column = width / 2
  val row = height / 4
  val start = LocalDate.parse(week.startDate)
  for (day in 1..7) {
    val classes =
        schedule?.arrangedList.orEmpty().filter { it.dayOfWeek == day }.sortedBy { it.beginTime }
    val date = start.plus(day - 1, DateTimeUnit.DAY).toString().substring(5)
    val label =
        "周${"一二三四五六日"[day - 1]} $date · ${classes.size}门\n" +
            classes
                .joinToString(" / ") { "${it.beginTime.orEmpty()} ${it.courseName}" }
                .ifEmpty { "无课" }
    drawWidgetText(
        canvas,
        label,
        ((day - 1) % 2 * column + 2).toFloat(),
        ((day - 1) / 2 * row).toFloat(),
        column - 6,
        row - 2,
        10f,
    )
  }
  drawWidgetText(
      canvas,
      "点击查看整周\n拉高显示时间网格",
      (column + 2).toFloat(),
      (row * 3).toFloat(),
      column - 6,
      row - 2,
      10f,
  )
  return bitmap
}

internal fun renderAgendaWidget(items: List<SavedAgendaItem>, width: Int, height: Int): Bitmap {
  val bitmap = Bitmap.createBitmap(width * 2, height * 2, Bitmap.Config.ARGB_8888)
  val canvas = Canvas(bitmap).apply { scale(2f, 2f) }
  if (items.isEmpty()) {
    drawWidgetText(canvas, "没有已安排课程", 4f, 8f, width - 8, height - 8, 13f)
    return bitmap
  }
  val rows = ((height - 16) / 44).coerceAtLeast(1)
  items.take(rows).forEachIndexed { index, item ->
    val course = item.course
    drawWidgetText(
        canvas,
        "${item.date.toString().substring(5)} ${course.beginTime.orEmpty()}–${course.endTime.orEmpty()}\n${course.courseName}  ${course.placeName.orEmpty()}",
        4f,
        (index * 44).toFloat(),
        width - 8,
        42,
        12f,
    )
  }
  if (items.size > rows)
      drawWidgetText(
          canvas,
          "另 ${items.size - rows} 门 · 点击查看",
          4f,
          (height - 15).toFloat(),
          width - 8,
          15,
          10f,
      )
  return bitmap
}
