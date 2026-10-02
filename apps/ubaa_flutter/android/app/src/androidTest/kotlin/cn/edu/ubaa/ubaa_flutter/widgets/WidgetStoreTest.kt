package cn.edu.ubaa.ubaa_flutter.widgets

import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.AndroidJUnit4
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
    fun 系统加密读回撤销和清理闭环() {
        // 只在专用模拟器运行；使用随机合成owner，没有账户和学校网络。
        WidgetStore.begin(context, null)
        val owner = "synthetic-owner-" + java.util.UUID.randomUUID()
        val a = WidgetStore.begin(context, owner)
        assertTrue(WidgetStore.publish(context, a, snapshot(owner)))
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
        WidgetStore.begin(context, null)
        assertNull(WidgetStore.read(context))
    }
}
