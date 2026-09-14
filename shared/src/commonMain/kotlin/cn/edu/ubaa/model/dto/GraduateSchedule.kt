package cn.edu.ubaa.model.dto

import kotlinx.datetime.LocalDate
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.*

/** 只移除已确认的 WebVPN 引导脚本，不删除普通 HTML 或其他脚本。 */
internal fun removeGraduateWebVpnScripts(body: String): String =
    Regex("<script\\b[^>]*>[\\s\\S]*?</script\\s*>", RegexOption.IGNORE_CASE).replace(body) { match
      ->
      val script = match.value
      val bootstrap =
          script.contains("var __vpn_hostname_data =") &&
              script.contains("var __vpn_js_file =") &&
              script.contains("/wengine-vpn/js/main.js")
      val loader =
          Regex(
                  """<script\s+[^>]*\bsrc\s*=\s*["']/wengine-vpn/js/main\.js(?:\?[^"']*)?["'][^>]*>\s*</script\s*>""",
                  RegexOption.IGNORE_CASE,
              )
              .matches(script)
      if (bootstrap || loader) "" else script
    }

/** 将 GSMIS 规范化排课或历史 YJSXK 样本转换为周课表，仅读取排课所需字段。 */
class GraduateSchedule
private constructor(
    private val rows: List<JsonObject>,
    private val courses: List<JsonObject>,
    private val dates: List<JsonObject>,
    private val sectionTimes: List<SectionTime>,
    private val availableTerms: List<Term>? = null,
    private val semesterStart: LocalDate? = null,
) {
  internal fun withCalendar(terms: List<Term>, start: LocalDate?) =
      GraduateSchedule(rows, courses, dates, sectionTimes, terms, start)

  fun terms(): List<Term> =
      availableTerms
          ?: (courses + rows)
              .map { it.text("XNXQDM") }
              .distinct()
              .sortedDescending()
              .mapIndexed { i, code ->
                Term(
                    code,
                    courses.firstOrNull { it.text("XNXQDM") == code }?.optional("XNXQMC") ?: code,
                    i == 0,
                    i,
                )
              }

  fun weekly(termCode: String, week: Int): WeeklySchedule {
    val term = terms().firstOrNull { it.itemCode == termCode } ?: error("研究生课表中没有所选学期，请刷新学期列表")
    require(week > 0) { "周次必须大于零" }
    val selected =
        rows.filter { it.text("XNXQDM") == termCode && it.text("ZCBH").getOrNull(week - 1) == '1' }
    // 按教学班、地点、教师与周次合并相邻节次；不跨空档或合并同名的不同教学班。
    val classes =
        selected
            .groupBy {
              listOf(
                  it.text("BJDM"),
                  it.text("KCDM"),
                  it.text("XQ"),
                  it.optional("JASMC"),
                  it.optional("JSXM")?.split(',')?.sorted()?.joinToString(","),
                  it.text("ZCBH"),
                  it.optional("JCFADM"),
              )
            }
            .values
            .flatMap { group ->
              val merged = mutableListOf<CourseClass>()
              group
                  .distinctBy {
                    listOf(it.text("KSJCDM"), it.text("JSJCDM"), it.text("KSSJ"), it.text("JSSJ"))
                  }
                  .sortedBy { it.number("KSJCDM") }
                  .forEach { row ->
                    val item =
                        CourseClass(
                            courseCode = row.text("KCDM"),
                            courseName = row.text("KCMC"),
                            courseSerialNo = row.text("BJDM"),
                            credit =
                                courses
                                    .firstOrNull { it.text("BJDM") == row.text("BJDM") }
                                    ?.optional("XF"),
                            beginTime = time(row.number("KSSJ")),
                            endTime = time(row.number("JSSJ")),
                            beginSection = row.number("KSJCDM"),
                            endSection = row.number("JSJCDM"),
                            placeName = row.optional("JASMC"),
                            weeksAndTeachers =
                                listOfNotNull(row.optional("ZCMC"), row.optional("JSXM"))
                                    .joinToString(" "),
                            teachingTarget = null,
                            color = null,
                            dayOfWeek = row.number("XQ"),
                        )
                    val previous = merged.lastOrNull()
                    if (previous != null && previous.endSection!! + 1 == item.beginSection) {
                      merged[merged.lastIndex] =
                          previous.copy(endSection = item.endSection, endTime = item.endTime)
                    } else merged.add(item)
                  }
              merged
            }
            .sortedWith(compareBy({ it.dayOfWeek }, { it.beginSection }, { it.courseCode }))
    return WeeklySchedule(classes, term.itemCode, term.itemName, sectionTimes)
  }

  fun weeks(termCode: String, today: LocalDate): List<Week> {
    val termRows = rows.filter { it.text("XNXQDM") == termCode }
    if (termRows.isEmpty()) return emptyList()
    val start = semesterStart ?: firstMonday(termRows)
    // ponytail: 位图给出可查询周次范围，不能把位图长度当成学校公布的学期长度。
    return (1..termRows.maxOf { it.text("ZCBH").length }).map { week ->
      val from = LocalDate.fromEpochDays(start.toEpochDays() + 7 * (week - 1))
      val to = LocalDate.fromEpochDays(from.toEpochDays() + 6)
      Week(from.toString(), to.toString(), termCode, today in from..to, week, "第${week}周")
    }
  }

  fun today(today: LocalDate): List<TodayClass> =
      terms().flatMap { term ->
        val week =
            weeks(term.itemCode, today).firstOrNull { it.curWeek } ?: return@flatMap emptyList()
        weekly(term.itemCode, week.serialNumber)
            .arrangedList
            .filter { it.dayOfWeek == today.dayOfWeek.ordinal + 1 }
            .map {
              TodayClass(
                  it.courseName,
                  it.placeName,
                  "${it.beginTime}-${it.endTime}",
                  it.courseName,
              )
            }
      }

  private fun firstMonday(termRows: List<JsonObject>): LocalDate {
    val candidates =
        termRows
            .flatMap { row ->
              val weeks = row.text("ZCBH").mapIndexedNotNull { i, c -> (i + 1).takeIf { c == '1' } }
              val actualDates =
                  dates
                      .filter {
                        it.text("bjdm") == row.text("BJDM") &&
                            it.number("kssj") == row.number("KSSJ") &&
                            it.number("jssj") == row.number("JSSJ")
                      }
                      .flatMap {
                        it.getValue("rqs").jsonArray.map { day ->
                          LocalDate.parse(day.jsonPrimitive.content)
                        }
                      }
                      .distinct()
                      .sorted()
              // 同一班级同一节次可能有多段周次；仅用一一对应的记录校验校历。
              if (weeks.size != actualDates.size) emptyList()
              else
                  weeks.zip(actualDates).map { (week, date) ->
                    LocalDate.fromEpochDays(
                        date.toEpochDays() - 7 * (week - 1) - (row.number("XQ") - 1)
                    )
                  }
            }
            .distinct()
    // 不猜开学日期。调课或上游字段变化导致冲突时，需要实际校历接口。
    check(candidates.size == 1 && candidates.single().dayOfWeek.ordinal == 0) {
      "研究生课表日期与周次无法一致对应，请核对官方校历"
    }
    return candidates.single()
  }

  companion object {
    fun parse(body: String): GraduateSchedule {
      val root =
          try {
            Json.parseToJsonElement(body).jsonObject
          } catch (original: SerializationException) {
            // WebVPN 将网页引导脚本插入 PKSJDDMS 的字符串中，未转义的引号破坏 JSON。
            // 仅在解析失败时修复此已知传输污染；合法 JSON 原样读取。
            val cleaned = removeGraduateWebVpnScripts(body)
            if (cleaned == body) throw original
            try {
              Json.parseToJsonElement(cleaned).jsonObject
            } catch (_: SerializationException) {
              throw original
            }
          }
      fun objects(key: String) = root.getValue(key).jsonArray.map { it.jsonObject }
      val sourceCourses = objects("xkjgList")
      sourceCourses.forEach {
        require(it.optional("SFYXXKJG") in setOf("0", "1")) { "研究生课表缺少有效的预选/已选标识" }
      }
      // 与官网“已选课程课表”一致：0 为正式已选，1 为预选，按教学班号关联排课。
      val selectedClasses =
          sourceCourses.filter { it.text("SFYXXKJG") == "0" }.map { it.text("BJDM") }.toSet()
      val rows = objects("results").filter { it.text("BJDM") in selectedClasses }
      val courses =
          // 学期元数据仍保留；同一教学班有两种记录时，正式已选的学分优先。
          sourceCourses
              .sortedBy { it.text("SFYXXKJG") }
              .map { row ->
                JsonObject(row.filterKeys { it in setOf("BJDM", "XNXQDM", "XNXQMC", "XF") })
              }
      val dates = objects("rqpkjgallList").filter { it.text("bjdm") in selectedClasses }
      rows.forEach { row ->
        listOf("BJDM", "KCDM", "KCMC", "XNXQDM").forEach { row.text(it) }
        require(row.number("XQ") in 1..7)
        require(row.number("KSJCDM") > 0 && row.number("JSJCDM") >= row.number("KSJCDM"))
        require(row.text("ZCBH").all { it == '0' || it == '1' })
        time(row.number("KSSJ"))
        time(row.number("JSSJ"))
        require(row.number("KSSJ") < row.number("JSSJ"))
      }
      courses.forEach {
        it.text("XNXQDM")
        it.text("BJDM")
      }
      val slots =
          root["skjcList"]?.let {
            if (it is JsonPrimitive) runCatching { Json.parseToJsonElement(it.content) }.getOrNull()
            else it
          } as? JsonArray
      val schemes = rows.mapNotNull { it.optional("JCFADM") }.toSet()
      val times =
          slots
              .orEmpty()
              .mapNotNull { value ->
                runCatching {
                      val slot = value.jsonObject
                      if (schemes.isNotEmpty() && slot.optional("JCFADM") !in schemes)
                          return@runCatching null
                      val section = slot.number("DM")
                      require(section > 0 && slot.number("KSSJ") < slot.number("JSSJ"))
                      SectionTime(section, time(slot.number("KSSJ")), time(slot.number("JSSJ")))
                    }
                    .getOrNull()
              }
              .distinct()
      return GraduateSchedule(rows, courses, dates, times)
    }

    private fun time(value: Int): String {
      require(value / 100 in 0..23 && value % 100 in 0..59)
      return "${(value / 100).toString().padStart(2, '0')}:${(value % 100).toString().padStart(2, '0')}"
    }

    private fun JsonObject.optional(key: String) = (get(key) as? JsonPrimitive)?.contentOrNull

    private fun JsonObject.text(key: String) =
        optional(key)?.takeIf { it.isNotBlank() } ?: error("研究生课表缺少字段 $key")

    private fun JsonObject.number(key: String) = text(key).toInt()
  }
}
