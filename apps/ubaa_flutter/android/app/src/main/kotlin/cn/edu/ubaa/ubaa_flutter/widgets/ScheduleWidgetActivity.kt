package cn.edu.ubaa.ubaa_flutter.widgets

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** 组件点击的只读离线宿主；沿旧版学期、周次、今日摘要与课程详情，不启动网络恢复。 */
class ScheduleWidgetActivity : Activity() {
    private var snapshot: WidgetSnapshot? = null
    private var selected: SelectedWeek? = null
    private var owner: String? = null
    private var dialog: AlertDialog? = null
    private lateinit var root: LinearLayout
    private val padding
        get() = (16 * resources.displayMetrics.density).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        owner = intent.getStringExtra("owner")
        root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.setOnApplyWindowInsetsListener { view, insets ->
            view.setPadding(
                padding,
                insets.systemWindowInsetTop + padding,
                padding,
                insets.systemWindowInsetBottom,
            )
            insets
        }
        setContentView(root)
    }

    override fun onResume() {
        super.onResume()
        root.removeAllViews()
        try {
            val state = WidgetStore.read(this)
            val value = state?.optJSONObject("snapshot")?.let(::parseWidgetSnapshot)
            check(value != null && value.owner == owner && state.optString("owner") == owner)
            snapshot = value
            selected =
                selectSavedScheduleWeek(
                    value.semesters,
                    ScheduleWidgetProvider.today(),
                    selected?.semester?.termCode ?: intent.getStringExtra("term"),
                    selected?.week?.serialNumber ?: intent.getIntExtra("week", -1),
                )
            render()
        } catch (_: Exception) {
            snapshot = null
            selected = null
            root.addView(label("本地课表不可用或账号已变化，请返回应用重新保存。"))
            back()
        }
    }

    private fun label(value: String) =
        TextView(this).apply {
            text = value
            textSize = 14f
            setTextColor(android.graphics.Color.rgb(24, 48, 75))
        }

    private fun back() {
        root.addView(
            Button(this).apply {
                text = "返回"
                setOnClickListener { finish() }
            }
        )
    }

    private fun step(delta: Int) {
        val current = selected ?: return
        val weeks = current.semester.weeks
        selected =
            current.copy(
                week = weeks.getOrNull(weeks.indexOf(current.week) + delta) ?: current.week
            )
        render()
    }

    private fun courseDetails(course: WidgetCourse) {
        dialog?.dismiss()
        dialog =
            AlertDialog.Builder(this)
                .setTitle(course.courseName)
                .setMessage(
                    listOfNotNull(
                            course.placeName,
                            "${course.beginTime.orEmpty()}–${course.endTime.orEmpty()}",
                            course.weeksAndTeachers,
                        )
                        .joinToString("\n")
                )
                .setPositiveButton("关闭", null)
                .show()
    }

    private fun render() {
        root.removeAllViews()
        val current =
            selected
                ?: run {
                    root.addView(label("尚无已保存的完整学期课表"))
                    return back()
                }
        val saved = snapshot ?: return back()
        title = "离线课表 · ${current.week.name}"
        val today = savedAgenda(saved.semesters, ScheduleWidgetProvider.today(), 1)
        root.addView(label("今日课程 · 离线查看"))
        root.addView(
            ScrollView(this).apply {
                addView(
                    label(
                        today
                            .joinToString("\n") {
                                "${it.course.beginTime.orEmpty()}  ${it.course.courseName}  ${it.course.placeName.orEmpty()}"
                            }
                            .ifEmpty { "今天没有课程" }
                    )
                )
            },
            LinearLayout.LayoutParams(-1, (48 * resources.displayMetrics.density).toInt()),
        )
        val bar = LinearLayout(this)
        bar.addView(
            Button(this).apply {
                text = "上一周"
                isEnabled = current.week != current.semester.weeks.first()
                setOnClickListener { step(-1) }
            }
        )
        bar.addView(
            Button(this).apply {
                text = current.week.name
                setOnClickListener {
                    val weeks = current.semester.weeks
                    dialog =
                        AlertDialog.Builder(this@ScheduleWidgetActivity)
                            .setTitle("选择教学周")
                            .setItems(weeks.map { it.name }.toTypedArray()) { _, i ->
                                selected = current.copy(week = weeks[i])
                                render()
                            }
                            .show()
                }
            },
            LinearLayout.LayoutParams(0, -2, 1f),
        )
        bar.addView(
            Button(this).apply {
                text = "下一周"
                isEnabled = current.week != current.semester.weeks.last()
                setOnClickListener { step(1) }
            }
        )
        root.addView(bar)
        root.addView(
            Button(this).apply {
                text = current.semester.name
                contentDescription = "选择学期"
                setOnClickListener {
                    dialog =
                        AlertDialog.Builder(this@ScheduleWidgetActivity)
                            .setTitle("选择学期")
                            .setItems(saved.semesters.map { it.name }.toTypedArray()) { _, i ->
                                selected =
                                    selectSavedScheduleWeek(
                                        saved.semesters,
                                        ScheduleWidgetProvider.today(),
                                        saved.semesters[i].termCode,
                                    )
                                render()
                            }
                            .show()
                }
            }
        )
        root.addView(label("已本地化 · 更新于 ${current.semester.updatedAt}"))
        val width =
            ((resources.displayMetrics.widthPixels - 2 * padding) /
                    resources.displayMetrics.density)
                .toInt()
                .coerceIn(240, 700)
        val height = 700
        val image =
            ImageView(this).apply {
                adjustViewBounds = true
                scaleType = ImageView.ScaleType.FIT_CENTER
                contentDescription = "${current.week.name}，离线周课表"
            }
        image.setImageBitmap(renderScheduleWidget(current.week, current.week, width, height))
        val gestures =
            GestureDetector(
                this,
                object : GestureDetector.SimpleOnGestureListener() {
                    override fun onDown(e: MotionEvent) = true

                    override fun onFling(
                        start: MotionEvent?,
                        end: MotionEvent,
                        vx: Float,
                        vy: Float,
                    ): Boolean {
                        if (
                            start == null ||
                                kotlin.math.abs(end.x - start.x) <=
                                    kotlin.math.abs(end.y - start.y) ||
                                kotlin.math.abs(vx) < 100
                        )
                            return false
                        step(if (end.x < start.x) 1 else -1)
                        return true
                    }

                    override fun onSingleTapUp(e: MotionEvent): Boolean {
                        // 与Canvas七列/节次坐标保持一致；重叠课程先选择，避免吞掉同节课程。
                        val x = e.x / image.width * width
                        val y = e.y / image.height * height
                        if (x < 38 || y < 30) return false
                        val day = ((x - 38) / ((width - 38) / 7f)).toInt() + 1
                        val section =
                            ((y - 30) / ((height - 30f) / current.week.times.size)).toInt() + 1
                        val courses =
                            current.week.arrangedList.filter {
                                it.dayOfWeek == day &&
                                    section in
                                        (it.beginSection ?: 1)..(it.endSection
                                                ?: it.beginSection
                                                ?: 1)
                            }
                        if (courses.size == 1) courseDetails(courses.single())
                        else if (courses.isNotEmpty())
                            dialog =
                                AlertDialog.Builder(this@ScheduleWidgetActivity)
                                    .setTitle("选择课程")
                                    .setItems(courses.map { it.courseName }.toTypedArray()) { _, i
                                        ->
                                        courseDetails(courses[i])
                                    }
                                    .show()
                        return courses.isNotEmpty()
                    }
                },
            )
        image.setOnTouchListener { _, event -> gestures.onTouchEvent(event) }
        root.addView(
            ScrollView(this).apply { addView(image) },
            LinearLayout.LayoutParams(-1, 0, 1f),
        )
        back()
    }

    override fun onPause() {
        // 离开即移除可见课程，恢复时重新核对当前账号。
        dialog?.dismiss()
        dialog = null
        root.removeAllViews()
        super.onPause()
    }
}
