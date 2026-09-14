package cn.edu.ubaa.repository

import com.russhwolf.settings.MapSettings
import com.russhwolf.settings.Settings
import kotlin.test.*

class ScheduleSnapshotStorageTest {
  @Test
  fun `大快照可以重新加载且账号和代理对保持完整`() {
    val backing = MapSettings()
    val settings =
        object : Settings by backing {
          override fun putString(key: String, value: String) {
            require(value.length <= 8192)
            // 模拟只接受完整 Unicode 字符的持久化后端。
            backing.putString(key, value.encodeToByteArray().decodeToString())
          }
        }
    val first = "课".repeat(4095) + "🧪" + "程".repeat(9000)
    val store = ScheduleSnapshotStorage(settings)
    store.write("A", first)
    store.write("B", "另一个账号")
    assertEquals(first, ScheduleSnapshotStorage(settings).read("A"))
    store.write("B", "第二版")
    assertEquals(first, store.read("A"))
    assertEquals("第二版", store.read("B"))
    assertTrue(backing.keys.all { backing.getString(it, "").length <= 8192 })
  }

  @Test
  fun `分块或索引写入失败时保留旧快照并清理未发布数据`() {
    for (failAt in listOf(2, 4)) {
      val backing = MapSettings()
      var writes = 0
      var fail = false
      val settings =
          object : Settings by backing {
            override fun putString(key: String, value: String) {
              if (fail && ++writes == failAt) error("模拟存储空间不足")
              backing.putString(key, value)
            }
          }
      val store = ScheduleSnapshotStorage(settings)
      store.write("A", "原有课表")
      val previous = backing.keys.associateWith { backing.getString(it, "") }
      fail = true
      assertFails { store.write("A", "新".repeat(9000)) }
      assertEquals("原有课表", store.read("A"))
      assertEquals(previous, backing.keys.associateWith { backing.getString(it, "") })
    }
  }

  @Test
  fun `读取旧缓存不写入且成功更新后迁移为分块格式`() {
    val settings = MapSettings()
    settings.putString("schedule_v1_A", "旧版 JSON")
    val store = ScheduleSnapshotStorage(settings)
    assertEquals("旧版 JSON", store.read("A"))
    assertEquals(setOf("schedule_v1_A"), settings.keys)
    store.write("A", "新版 JSON".repeat(2000))
    assertEquals("新版 JSON".repeat(2000), store.read("A"))
    assertFalse(settings.hasKey("schedule_v1_A"))
  }

  @Test
  fun `读取途中发布新版时重试完整快照`() {
    val backing = MapSettings()
    val writer = ScheduleSnapshotStorage(backing)
    writer.write("A", "旧课表")
    var publish = true
    val reader =
        ScheduleSnapshotStorage(
            object : Settings by backing {
              override fun getStringOrNull(key: String): String? {
                val value = backing.getStringOrNull(key)
                if (publish) {
                  publish = false
                  writer.write("A", "完整新课表")
                }
                return value
              }
            }
        )
    assertEquals("完整新课表", reader.read("A"))
  }

  @Test
  fun `清理旧分块失败不影响已发布快照`() {
    val backing = MapSettings()
    val settings =
        object : Settings by backing {
          override fun remove(key: String) = error("模拟清理失败")
        }
    val store = ScheduleSnapshotStorage(settings)
    store.write("A", "旧课表")
    store.write("A", "新课表")
    assertEquals("新课表", store.read("A"))
  }
}
