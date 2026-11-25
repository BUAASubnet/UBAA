package cn.edu.ubaa.ubaa_flutter.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.RemoteViews
import android.widget.TextView
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.AndroidJUnit4
import cn.edu.ubaa.ubaa_flutter.MainActivity
import cn.edu.ubaa.ubaa_flutter.R
import java.io.File
import java.time.LocalDate
import kotlin.math.roundToInt
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WidgetRenderTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val target = instrumentation.targetContext
    private val date = LocalDate.of(2026, 11, 16)

    private data class Scenario(val name: String, val now: Long, val publication: WidgetPublication)

    private data class Layout(
        val component: String,
        val name: String,
        val width: Int,
        val height: Int,
        val render: (Context, Scenario) -> RemoteViews,
    )

    private fun fixture() = instrumentation.context.assets.open("snapshot_v2.json")
        .bufferedReader().use { JSONObject(it.readText()) }

    private fun context(dark: Boolean): Context {
        val config = Configuration(target.resources.configuration)
        config.uiMode = (config.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
            if (dark) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
        config.fontScale = 1f
        return target.createConfigurationContext(config)
    }

    private fun inflate(context: Context, views: RemoteViews, width: Int, height: Int): FrameLayout {
        val frame = FrameLayout(context)
        frame.addView(views.apply(context, frame), FrameLayout.LayoutParams(-1, -1))
        val density = context.resources.displayMetrics.density
        val widthPx = (width * density).roundToInt()
        val heightPx = (height * density).roundToInt()
        frame.measure(
            View.MeasureSpec.makeMeasureSpec(widthPx, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(heightPx, View.MeasureSpec.EXACTLY),
        )
        frame.layout(0, 0, widthPx, heightPx)
        return frame
    }

    private fun visibleLabels(view: View): List<String> = when {
        view.visibility != View.VISIBLE -> emptyList()
        view is TextView -> {
            assertFalse(view.includeFontPadding)
            listOf(view.text.toString())
        }
        view is ViewGroup -> (0 until view.childCount).flatMap { visibleLabels(view.getChildAt(it)) }
        else -> emptyList()
    }

    private fun orientationContext(orientation: Int): Context = target.createConfigurationContext(
        Configuration(target.resources.configuration).apply { this.orientation = orientation },
    )

    @Test
    fun 横竖周课表按面积共享位图上限() {
        val portrait = orientationContext(Configuration.ORIENTATION_PORTRAIT)
        val landscape = orientationContext(Configuration.ORIENTATION_LANDSCAPE)
        val snapshot = parseWidgetSnapshot(fixture())
        val selected = selectSavedScheduleWeek(snapshot.semesters, date)!!
        val options = Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 640)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 900)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 1000)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 400)
        }
        val views = renderWeeklyLayouts(portrait, WidgetPublication.Available(snapshot), selected, 42, options)
        fun area(context: Context): Int {
            val grid = views.apply(context, FrameLayout(context)).findViewById<ImageView>(R.id.widget_grid)
            assertEquals(ImageView.ScaleType.FIT_CENTER, grid.scaleType)
            val bitmap = (grid.drawable as BitmapDrawable).bitmap
            if (context == portrait) assertTrue(bitmap.width < bitmap.height)
            else assertTrue(bitmap.width > bitmap.height)
            return bitmap.width * bitmap.height
        }
        val portraitArea = area(portrait)
        val landscapeArea = area(landscape)
        assertTrue(portraitArea + landscapeArea <= 1_500_000)
        val resources = portrait.resources
        val density = resources.displayMetrics.density
        val padding = resources.getDimensionPixelSize(R.dimen.widget_padding)
        val header = resources.getDimensionPixelSize(R.dimen.widget_week_header_height)
        fun originalArea(width: Int, height: Int) = ((width * density).roundToInt() - 2 * padding).toDouble() *
            ((height * density).roundToInt() - 2 * padding - header)
        assertEquals(originalArea(640, 900) / originalArea(1000, 400), portraitArea.toDouble() / landscapeArea, 0.01)
    }

    @Test
    fun 待办大小布局同时生成时各行请求码唯一() {
        val snapshot = parseWidgetSnapshot(fixture())
        val first = snapshot.todo!!.first()
        val rows = List(3) { index -> first.mediumRows.first().copy(link = "${WIDGET_LINK_PREFIX}row=$index") }
        val publication = WidgetPublication.Available(snapshot.copy(todo = listOf(first.copy(mediumRows = rows))))
        val id = 4362
        fun pending(slot: Int) = PendingIntent.getActivity(
            target, id * 16 + slot, widgetOpenIntent(target, null),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE,
        )
        try {
            renderTodo(target, id, publication, first.from, true)
            renderTodo(target, id, publication, first.from, false)
            val clicks = (0..4).map(::pending)
            assertTrue(clicks.all { it != null })
            assertEquals(5, clicks.toSet().size)
        } finally {
            (0..4).forEach { pending(it)?.cancel() }
        }
    }

    @Test
    fun 无链接的组件入口清空待处理链接且普通启动保留() {
        val inbox = WidgetLaunchInbox()
        val first = "${WIDGET_LINK_PREFIX}target=home"
        val second = "${WIDGET_LINK_PREFIX}target=today"
        val linked = widgetOpenIntent(target, first)
        assertNull(inbox.receive(linked))
        assertFalse(linked.hasExtra(WIDGET_LINK))
        val noLink = widgetOpenIntent(target, null)
        assertEquals(WIDGET_OPEN, noLink.action)
        assertFalse(noLink.hasExtra(WIDGET_LINK))
        assertNull(inbox.receive(noLink))
        assertNull(inbox.take())
        inbox.awaitTake()
        inbox.receive(widgetOpenIntent(target, first))
        inbox.receive(widgetOpenIntent(target, second))
        inbox.receive(Intent(Intent.ACTION_MAIN).putExtra(WIDGET_LINK, first))
        assertEquals(second, inbox.take())
        assertEquals(first, inbox.receive(widgetOpenIntent(target, first)))
    }

    @Test
    fun 旧版旋转按横竖各自尺寸选档并重算剩余项() {
        val portrait = orientationContext(Configuration.ORIENTATION_PORTRAIT)
        val landscape = orientationContext(Configuration.ORIENTATION_LANDSCAPE)
        val snapshot = parseWidgetSnapshot(fixture())
        val publication = WidgetPublication.Available(snapshot)
        val options = Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 170)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 170)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 360)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 120)
        }
        val now = snapshot.upNext!!.first { it.primary?.ongoing == true }.from
        fun labels(provider: Class<*>): Pair<List<String>, List<String>> {
            val views = renderResponsiveCard(portrait, provider.name, 43, publication, now, options, 30)!!
            return visibleLabels(inflate(landscape, views, 360, 120)) to visibleLabels(inflate(portrait, views, 170, 170))
        }
        val (todayLandscape, todayPortrait) = labels(UpcomingScheduleWidgetProvider::class.java)
        assertTrue("还有 2 项" in todayLandscape)
        assertFalse("研讨室预约" in todayLandscape)
        assertTrue("还有 1 项" in todayPortrait)
        assertTrue("研讨室预约" in todayPortrait)
        val (nextLandscape, nextPortrait) = labels(TodayScheduleWidgetProvider::class.java)
        assertFalse("进行中" in nextLandscape)
        assertTrue("进行中" in nextPortrait)
        val todo = renderResponsiveCard(portrait, TodoWidgetProvider::class.java.name, 44, publication, now, options, 30)!!
        assertNotNull(todo.apply(landscape, FrameLayout(landscape)).findViewById<View>(R.id.widget_slot_1))
        assertNull(todo.apply(portrait, FrameLayout(portrait)).findViewById<View>(R.id.widget_slot_1))
    }

    @Test
    fun 今天头行仅在两段都存在时显示分隔符() {
        val snapshot = parseWidgetSnapshot(fixture())
        val first = snapshot.today!!.first()
        val context = context(false)
        fun header(rowCount: Int, due: String?): Pair<String?, String?> {
            val segment = first.copy(rows = first.rows.take(rowCount), dueLine = due)
            val publication = WidgetPublication.Available(snapshot.copy(today = listOf(segment)))
            val card = inflate(context, renderToday(context, 45, publication, first.from, 3), 360, 170)
            fun visibleText(id: Int) = card.findViewById<TextView>(id).takeIf { it.visibility == View.VISIBLE }?.text?.toString()
            return visibleText(R.id.widget_more) to visibleText(R.id.widget_due)
        }
        val due = "今天 1 项截止"
        assertEquals("还有 1 项" to " · $due", header(4, due))
        assertEquals("还有 1 项" to null, header(4, null))
        assertEquals(null to due, header(3, due))
        assertEquals(null to null, header(3, null))
    }

    @Test
    fun 清单尺寸预览和应用入口符合组件定义() {
        val providers = AppWidgetManager.getInstance(target).getInstalledProvidersForPackage(target.packageName, null)
            .associateBy { it.provider.className }
        val expected = listOf(
            Triple(TodayScheduleWidgetProvider::class.java, "接下来", 2 to 2),
            Triple(UpcomingScheduleWidgetProvider::class.java, "今天", 4 to 2),
            Triple(TodoWidgetProvider::class.java, "待办", 2 to 2),
            Triple(ScheduleWidgetProvider::class.java, "周课表", 4 to 4),
        )
        assertEquals(expected.size, providers.size)
        expected.forEach { (receiver, label, cells) ->
            val info = providers.getValue(receiver.name)
            val packageManager = target.packageManager
            assertFalse(packageManager.getReceiverInfo(info.provider, 0).exported)
            assertEquals(label, info.loadLabel(packageManager))
            assertEquals(1_800_000, info.updatePeriodMillis)
            if (Build.VERSION.SDK_INT >= 31) {
                assertEquals(cells, info.targetCellWidth to info.targetCellHeight)
                assertTrue(info.previewLayout != 0)
                assertFalse(info.loadDescription(target).isNullOrEmpty())
            }
        }
        val activity = ComponentName(target, MainActivity::class.java)
        val link = "ubaa://widget/open?owner=synthetic&target=home"
        val intent = widgetOpenIntent(target, link)
        assertEquals(activity, intent.component)
        assertEquals(WIDGET_OPEN, intent.action)
        assertNull(intent.data)
        assertEquals(link, intent.getStringExtra(WIDGET_LINK))
        assertFalse(widgetOpenIntent(target, null).hasExtra(WIDGET_LINK))
        assertEquals(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP, intent.flags)
    }

    @Test
    fun 四种组件各档布局的浅深色渲染() {
        val snapshot = parseWidgetSnapshot(fixture())
        val available = WidgetPublication.Available(snapshot)
        val first = snapshot.upNext!!.first().from
        val partialRaw = fixture()
        partialRaw.getJSONArray("upNext").getJSONObject(0)
            .put("state", "partial").put("message", "部分课表未载入").put("primary", JSONObject.NULL)
        partialRaw.getJSONArray("today").getJSONObject(0)
            .put("state", "partial").put("message", "部分课表未载入").put("rows", JSONArray())
            .put("dayLabel", JSONObject.NULL)
        val noDataRaw = fixture()
        noDataRaw.getJSONArray("todo").getJSONObject(snapshot.todo!!.lastIndex)
            .put("state", "noData").put("message", "打开 UBAA 载入待办")
        val scenarios = listOf(
            Scenario("ongoing", 1794787200, available),
            Scenario("between_classes", 1794792900, available),
            Scenario("tomorrow", 1794834000, available),
            Scenario("exam_secondary", 1794844800, available),
            Scenario("partial", first, WidgetPublication.Available(parseWidgetSnapshot(partialRaw))),
            Scenario("term_end", 1794931200, available),
            Scenario("empty_a", first, WidgetPublication.Missing),
            Scenario("empty_b", first, WidgetPublication.Unreadable),
            Scenario("todo_exam", first, available),
            Scenario("todo_empty", snapshot.todo.last().from, available),
            Scenario("todo_no_data", snapshot.todo.last().from, WidgetPublication.Available(parseWidgetSnapshot(noDataRaw))),
            Scenario("stale", 1794832200, available),
        )
        val layouts = listOf(
            Layout("up_next", "compact", 170, 170) { context, state -> renderUpNext(context, 1, state.publication, state.now, true) },
            Layout("up_next", "full", 170, 170) { context, state -> renderUpNext(context, 1, state.publication, state.now, false) },
            Layout("today", "two_rows", 360, 170) { context, state -> renderToday(context, 2, state.publication, state.now, 2) },
            Layout("today", "three_rows", 360, 170) { context, state -> renderToday(context, 2, state.publication, state.now, 3) },
            Layout("todo", "small", 170, 170) { context, state -> renderTodo(context, 3, state.publication, state.now, true) },
            Layout("todo", "medium", 360, 170) { context, state -> renderTodo(context, 3, state.publication, state.now, false) },
            Layout("week", "grid", 360, 380) { context, state ->
                val selected = (state.publication as? WidgetPublication.Available)
                    ?.let { selectSavedScheduleWeek(it.snapshot.semesters, date) }
                renderWeek(context, 4, state.publication, selected, 360, 380)
            },
        )
        val output = File(requireNotNull(target.getExternalFilesDir(null)), "widget_renders").apply { mkdirs() }
        for (dark in listOf(false, true)) {
            val context = context(dark)
            for (layout in layouts) {
                for (scenario in scenarios) {
                    val file = File(output, "${layout.component}_${layout.name}_${scenario.name}_${if (dark) "dark" else "light"}.png")
                    val frame = inflate(context, layout.render(context, scenario), layout.width, layout.height)
                    val labels = visibleLabels(frame)
                    assertTrue(file.name, labels.isNotEmpty())
                    assertScenario(layout, scenario, labels)
                    val bitmap = Bitmap.createBitmap(frame.width, frame.height, Bitmap.Config.ARGB_8888)
                    frame.draw(Canvas(bitmap))
                    assertEquals(context.getColor(R.color.widget_canvas), bitmap.getPixel(10, frame.height / 2))
                    file.outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
                    bitmap.recycle()
                }
            }
        }
    }

    private fun assertScenario(layout: Layout, scenario: Scenario, labels: List<String>) {
        when (scenario.name) {
            "empty_a" -> assertTrue(if (layout.component == "todo") "打开 UBAA 载入待办" in labels
                else "还没有课表" in labels && "打开 UBAA 载入课表" in labels)
            "empty_b" -> {
                assertTrue("打开 UBAA 更新" in labels)
                assertEquals(layout.component != "todo", "需要更新" in labels)
            }
            "partial" -> if (layout.component in listOf("up_next", "today")) {
                assertTrue("部分课表未载入" in labels && "打开 UBAA 更新" in labels)
            }
            "term_end" -> if (layout.component in listOf("up_next", "today")) {
                assertTrue("本学期课程已结束" in labels)
                assertFalse("打开 UBAA 更新" in labels)
            }
            "ongoing" -> if (layout.component == "up_next") {
                assertTrue("至 9:35" in labels)
                assertEquals(layout.name == "full", "进行中" in labels)
            }
            "between_classes" -> if (layout.component == "up_next") assertTrue("10:10" in labels)
            "tomorrow" -> if (layout.component == "today") assertEquals("明天", labels.first())
            "exam_secondary" -> if (layout.component == "up_next") {
                assertEquals(layout.name == "full", labels.any { it.contains("今天有考试") })
            }
            "todo_exam" -> when (layout.component) {
                "todo" -> assertTrue("合成考试" in labels)
                "today" -> assertTrue((if (layout.name == "two_rows") "还有 2 项" else "还有 1 项") in labels)
            }
            "todo_empty", "todo_no_data", "stale" -> if (layout.component == "todo") {
                assertTrue(labels.any { it.contains("截至 ") })
                if (scenario.name == "todo_empty") assertTrue("近期没有待办" in labels)
                if (scenario.name == "todo_no_data") assertTrue("打开 UBAA 载入待办" in labels)
            }
        }
    }

    @Test
    fun 缺表和过期仅降级对应卡面且周网格按像素绘制() {
        val context = context(false)
        val snapshot = parseWidgetSnapshot(fixture())
        val missingTables = WidgetPublication.Available(snapshot.copy(upNext = null, today = null, todo = null))
        val available = WidgetPublication.Available(snapshot)
        val end = snapshot.horizonEnd!!
        for ((publication, now) in listOf(available to end, missingTables to end - 1)) {
            val upNext = inflate(context, renderUpNext(context, 1, publication, now, false), 170, 170)
            val today = inflate(context, renderToday(context, 2, publication, now, 3), 360, 170)
            val todo = inflate(context, renderTodo(context, 3, publication, now, true), 170, 170)
            assertEquals(listOf("需要更新", "打开 UBAA 更新"), visibleLabels(upNext))
            assertEquals(listOf("今天", "需要更新", "打开 UBAA 更新"), visibleLabels(today))
            assertEquals(listOf("待办", "打开 UBAA 更新"), visibleLabels(todo))
        }
        val selected = selectSavedScheduleWeek(snapshot.semesters, date)!!
        val light = renderScheduleWidget(context, selected.week, 360, 380)
        val dark = renderScheduleWidget(context(true), selected.week, 360, 380)
        val metrics = context.resources.displayMetrics
        assertEquals((360 * metrics.density).roundToInt() - 2 * context.resources.getDimensionPixelSize(R.dimen.widget_padding), light.width)
        assertEquals(light.width, dark.width)
        assertFalse(light.sameAs(dark))
        val large = renderScheduleWidget(context, selected.week, 2000, 2000)
        assertTrue(large.width * large.height <= 1_500_000)
        val week = inflate(context, renderWeek(context, 4, available, selected, 360, 380), 360, 380)
        val grid = week.findViewById<ImageView>(R.id.widget_grid)
        assertEquals(ImageView.ScaleType.FIT_CENTER, grid.scaleType)
        assertEquals(light.width, (grid.drawable as BitmapDrawable).bitmap.width)
        assertFalse(week.findViewById<View>(R.id.widget_previous).isEnabled)
        assertFalse(week.findViewById<View>(R.id.widget_next).isEnabled)
        assertTrue(week.findViewById<View>(R.id.widget_current).isEnabled)
    }
}
