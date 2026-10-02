package cn.edu.ubaa.ubaa_flutter.widgets

import android.appwidget.AppWidgetManager
import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.AndroidJUnit4
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WidgetRenderTest {
    @Test
    fun 三种组件已注册且点击同周离线视图可渲染() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val providers =
            AppWidgetManager.getInstance(context).installedProviders.filter {
                it.provider.packageName == context.packageName
            }
        assertEquals(3, providers.size)
        assertTrue(providers.all { it.updatePeriodMillis == 1800000 })
        val date = ScheduleWidgetProvider.today()
        val monday = date.minusDays((date.dayOfWeek.value - 1).toLong())
        val weeks = JSONArray()
        for (number in 1..2) {
            val start = monday.plusDays(((number - 1) * 7).toLong())
            val courses = JSONArray()
            for (day in 1..7) courses.put(
                JSONObject()
                    .put("name", "合成课程$number-$day")
                    .put("day", day)
                    .put("begin", 1)
                    .put("end", 2)
                    .put("startTime", "08:00")
                    .put("endTime", "09:35")
                    .put("place", "合成教室")
            )
            val times = JSONArray()
            for (section in 1..12) times.put(
                JSONObject()
                    .put("section", section)
                    .put("start", JSONObject.NULL)
                    .put("end", JSONObject.NULL)
            )
            weeks.put(
                JSONObject()
                    .put("number", number)
                    .put("name", "第${number}周")
                    .put("start", start.toString())
                    .put("end", start.plusDays(6).toString())
                    .put("courses", courses)
                    .put("times", times)
            )
        }
        val snapshot =
            JSONObject()
                .put("version", 1)
                .put("owner", "synthetic-render")
                .put(
                    "semesters",
                    JSONArray()
                        .put(
                            JSONObject()
                                .put("term", "synthetic-term")
                                .put("updatedAt", date.toString())
                                .put("weeks", weeks)
                        ),
                )
        WidgetStore.begin(context, null)
        assertTrue(
            WidgetStore.publish(context, WidgetStore.begin(context, "synthetic-render"), snapshot)
        )
        val parsed = parseWidgetSnapshot(snapshot)
        val selected = selectSavedScheduleWeek(parsed.semesters, date, "synthetic-term", 2)!!
        assertEquals(2, selected.week.serialNumber)
        for ((name, width, height) in
            listOf(Triple("week-wide", 500, 600), Triple("week-compact", 180, 150))) {
            val bitmap = renderScheduleWidget(selected.week, selected.week, width, height)
            context.openFileOutput("widget-$name.png", 0).use {
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }
            bitmap.recycle()
        }
        for (days in listOf(1, 3)) {
            val bitmap = renderAgendaWidget(savedAgenda(parsed.semesters, date, days), 320, 300)
            context.openFileOutput("widget-agenda-$days.png", 0).use {
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }
            bitmap.recycle()
        }
        val activity =
            instrumentation.startActivitySync(
                Intent(context, ScheduleWidgetActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    .putExtra("owner", "synthetic-render")
                    .putExtra("term", "synthetic-term")
                    .putExtra("week", 2)
            )
        instrumentation.waitForIdleSync()
        assertEquals("离线课表 · 第2周", activity.title.toString())
        fun texts(view: android.view.View): List<android.widget.TextView> =
            when (view) {
                is android.view.ViewGroup ->
                    (0 until view.childCount).flatMap { texts(view.getChildAt(it)) }
                is android.widget.TextView -> listOf(view)
                else -> emptyList()
            }
        instrumentation.runOnMainSync {
            val labels = texts(activity.window.decorView)
            assertTrue(labels.any { it.text == "今日课程 · 离线查看" })
            assertTrue(labels.any { it.text == "synthetic-term" })
            labels.single { it.text == "上一周" }.performClick()
            assertEquals("离线课表 · 第1周", activity.title.toString())
            texts(activity.window.decorView).single { it.text == "下一周" }.performClick()
            assertEquals("离线课表 · 第2周", activity.title.toString())
        }
        Thread.sleep(500)
        instrumentation.uiAutomation.takeScreenshot().also { bitmap ->
            context.openFileOutput("widget-offline-activity.png", 0).use {
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }
            bitmap.recycle()
        }
        instrumentation.runOnMainSync { activity.finish() }
        val wrong =
            instrumentation.startActivitySync(
                Intent(context, ScheduleWidgetActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    .putExtra("owner", "other-account")
            )
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync {
            val labels = texts(wrong.window.decorView)
            assertTrue(labels.any { it.text.toString().contains("账号已变化") })
            assertFalse(labels.any { it.text.toString().contains("合成课程") })
            wrong.finish()
        }
        ScheduleWidgetProvider.refreshAll(context)
        // 留下合成投影供同一专用模拟器Launcher检查，不读取真实账号或网络。
    }
}
