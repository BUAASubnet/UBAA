package cn.edu.ubaa.ubaa_flutter.widgets

import android.content.ContextWrapper
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.AndroidJUnit4
import cn.edu.ubaa.ubaa_flutter.R
import java.io.File
import java.time.LocalDate
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WidgetStoreTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    private fun snapshot(owner: String) =
        JSONObject().put("version", 1).put("owner", owner).put("semesters", org.json.JSONArray())

    @Test
    fun 删除密文失败时撤销和换号都显示空态A() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val snapshot = instrumentation.context.assets.open("snapshot_v2.json")
            .bufferedReader().use { JSONObject(it.readText()) }
        val owner = snapshot.getString("owner")
        val directory = File(context.cacheDir, "widget-revoke-${java.util.UUID.randomUUID()}")
        assertTrue(directory.mkdir())
        val isolated = object : ContextWrapper(context) {
            override fun getNoBackupFilesDir() = directory
        }
        val file = directory.resolve("schedule-widgets.enc")
        try {
            for (replacement in listOf(null, "synthetic-replacement")) {
                val scope = WidgetStore.begin(isolated, owner)
                assertTrue(WidgetStore.publish(isolated, scope, snapshot))
                val original = file.readBytes()
                assertTrue(directory.setWritable(false))
                try {
                    assertFalse(file.delete())
                    assertTrue(runCatching { WidgetStore.begin(isolated, replacement) }.isFailure)
                    assertArrayEquals(original, file.readBytes())
                    val publication = WidgetStore.publication(isolated)
                    assertEquals(WidgetPublication.Missing, publication)
                    val selected = (publication as? WidgetPublication.Available)?.snapshot?.let {
                        selectSavedScheduleWeek(it.semesters, LocalDate.of(2026, 11, 16))
                    }
                    val views = renderWeek(isolated, 1, publication, selected, 360, 380)
                    val card = views.apply(isolated, FrameLayout(isolated))
                    assertEquals("还没有课表", card.findViewById<TextView>(R.id.widget_message).text)
                    assertEquals(View.GONE, card.findViewById<View>(R.id.widget_grid).visibility)
                } finally {
                    assertTrue(directory.setWritable(true))
                }
                val nextScope = WidgetStore.begin(isolated, "synthetic-next")
                assertTrue(WidgetStore.publish(isolated, nextScope, snapshot("synthetic-next")))
                assertFalse(WidgetStore.publish(isolated, scope, snapshot))
                WidgetStore.begin(isolated, null)
            }
        } finally {
            WidgetStore.begin(isolated, null)
            directory.deleteRecursively()
        }
    }

    @Test
    fun 系统加密读回撤销和清理闭环() {
        // 只在专用模拟器运行；使用随机合成owner，没有账户和学校网络。
        WidgetStore.begin(context, null)
        val owner = "synthetic-owner-" + java.util.UUID.randomUUID()
        val a = WidgetStore.begin(context, owner)
        assertEquals(WidgetPublication.Missing, WidgetStore.publication(context))
        assertTrue(WidgetStore.publish(context, a, snapshot(owner)))
        assertTrue(WidgetStore.publication(context) is WidgetPublication.Available)
        assertEquals(
            owner,
            WidgetStore.read(context)!!.getJSONObject("snapshot").getString("owner"),
        )
        val bytes = java.io.File(context.noBackupFilesDir, "schedule-widgets.enc").readBytes()
        assertFalse(String(bytes, Charsets.ISO_8859_1).contains(owner))
        val b = WidgetStore.begin(context, "synthetic-b")
        assertFalse(WidgetStore.publish(context, a, snapshot(owner)))
        assertNull(WidgetStore.read(context)!!.optJSONObject("snapshot"))
        assertTrue(WidgetStore.publish(context, b, snapshot("synthetic-b")))
        WidgetStore.begin(context, null)
        assertNull(WidgetStore.read(context))
        assertFalse(java.io.File(context.noBackupFilesDir, "schedule-widgets.enc").exists())
    }

    @Test
    fun 密文损坏不能回退明文或生成假成功() {
        WidgetStore.begin(context, null)
        val scope = WidgetStore.begin(context, "synthetic-corrupt")
        assertTrue(WidgetStore.publish(context, scope, snapshot("synthetic-corrupt")))
        val file = java.io.File(context.noBackupFilesDir, "schedule-widgets.enc")
        val bytes = file.readBytes()
        bytes[bytes.lastIndex] = (bytes.last().toInt() xor 1).toByte()
        file.writeBytes(bytes)
        assertTrue(runCatching { WidgetStore.read(context) }.isFailure)
        assertEquals(WidgetPublication.Unreadable, WidgetStore.publication(context))
        WidgetStore.begin(context, null)
        assertNull(WidgetStore.read(context))
        assertEquals(WidgetPublication.Missing, WidgetStore.publication(context))
    }
}
