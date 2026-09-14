package cn.edu.ubaa.repository

import com.russhwolf.settings.Settings
import kotlin.random.Random

/** 分块保存整学期 JSON；最后发布索引，写入失败时仍可读取上一版。 */
internal class ScheduleSnapshotStorage(private val settings: Settings) {
  fun read(account: String): String? {
    val key = indexKey(account)
    repeat(3) {
      val index = settings.getStringOrNull(key)
      val content = runCatching {
        if (index == null) settings.getStringOrNull(legacyKey(account))
        else {
          val snapshot = Snapshot.parse(index)
          buildString {
            repeat(snapshot.parts) { part ->
              append(
                  checkNotNull(settings.getStringOrNull(snapshot.partKey(part))) {
                    "本地课表不完整，请重新更新课表"
                  }
              )
            }
          }
        }
      }
      // 更新期间旧分块可能被清理；索引变化时重新读取完整的新版本。
      if (settings.getStringOrNull(key) == index) return content.getOrThrow()
    }
    error("课表正在更新，请稍后重试")
  }

  fun write(account: String, content: String) {
    val key = indexKey(account)
    val previous = settings.getStringOrNull(key)?.let(Snapshot::parse)
    val parts = split(content)
    val snapshot =
        Snapshot(
            Random.nextBytes(16).joinToString("") { it.toUByte().toString(16).padStart(2, '0') },
            parts.size,
        )
    try {
      parts.forEachIndexed { index, part -> settings.putString(snapshot.partKey(index), part) }
      settings.putString(key, snapshot.index())
    } catch (error: Exception) {
      // 清理失败不能掩盖原始写入错误，也不能删除已发布的新版本。
      runCatching { if (settings.getStringOrNull(key) != snapshot.index()) remove(snapshot) }
      throw error
    }
    previous?.let(::remove)
    runCatching { settings.remove(legacyKey(account)) }
  }

  private fun remove(snapshot: Snapshot) {
    repeat(snapshot.parts) { part -> runCatching { settings.remove(snapshot.partKey(part)) } }
  }

  private fun split(content: String): List<String> {
    if (content.isEmpty()) return listOf("")
    return buildList {
      var start = 0
      while (start < content.length) {
        var end = minOf(start + PART_LENGTH, content.length)
        // 不能将表情等补充平面字符的 UTF-16 代理对拆到两个存储值中。
        if (
            end < content.length &&
                content[end - 1].isHighSurrogate() &&
                content[end].isLowSurrogate()
        ) {
          end--
        }
        add(content.substring(start, end))
        start = end
      }
    }
  }

  private data class Snapshot(val generation: String, val parts: Int) {
    fun index(): String = "$generation:$parts"

    fun partKey(part: Int): String = "schedule_part_${generation}_$part"

    companion object {
      fun parse(index: String): Snapshot {
        val fields = index.split(':')
        val parts = fields.getOrNull(1)?.toIntOrNull()
        check(
            fields.size == 2 &&
                Regex("[0-9a-f]{32}").matches(fields[0]) &&
                parts != null &&
                parts > 0
        ) {
          "本地课表索引无效，请重新更新课表"
        }
        return Snapshot(fields[0], parts)
      }
    }
  }

  private fun indexKey(account: String): String = "schedule_v2_$account"

  private fun legacyKey(account: String): String = "schedule_v1_$account"

  private companion object {
    // JVM Preferences 单值最多 8192 个字符；保留余量并兼容其他 Settings 后端。
    const val PART_LENGTH = 4096
  }
}
