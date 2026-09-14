package cn.edu.ubaa.model.dto

import kotlinx.datetime.LocalDate
import kotlinx.serialization.json.*

/** GSMIS 我的课表；只将排课字段转换为现有离线课表模型。 */
internal fun parseGsmisTerms(body: String): List<Term> {
  val root = Json.parseToJsonElement(body).jsonObject
  require(root["code"]?.jsonPrimitive?.content == "0") { "研究生学期列表返回失败" }
  val data = root.getValue("datas").jsonObject.getValue("kfdxnxqcx").jsonObject
  val rows = data.getValue("rows").jsonArray.map { it.jsonObject }
  require(data["totalSize"]?.jsonPrimitive?.int == rows.size) { "研究生学期列表不完整" }
  return rows
      .map { row ->
        val code = row.getValue("XNXQDM").jsonPrimitive.content
        require(Regex("\\d{4}[123]").matches(code)) { "研究生学期代码无效" }
        code to row.getValue("XNXQDM_DISPLAY").jsonPrimitive.content
      }
      .distinctBy { it.first }
      .sortedByDescending { it.first }
      .mapIndexed { i, (code, name) -> Term(code, name, i == 0, i) }
}

internal fun parseGsmisSchedule(
    body: String,
    terms: List<Term>,
    termCode: String,
): GraduateSchedule {
  val term = terms.single { it.itemCode == termCode }
  val root = Json.parseToJsonElement(body).jsonObject
  require(root["code"]?.jsonPrimitive?.content == "1") { "GSMIS 课表返回失败" }
  val rows = root.getValue("jgList").jsonArray.map { it.jsonObject }
  val courses = root.getValue("rwList").jsonArray.map { it.jsonObject }
  val slots =
      root.getValue("jcfaList").jsonArray.flatMap {
        it.jsonObject.getValue("skjcList").jsonArray.map { slot -> slot.jsonObject }
      }
  fun JsonObject.text(key: String) = get(key)?.jsonPrimitive?.contentOrNull
  require(courses.all { it.text("XNXQDM") == termCode }) { "GSMIS 返回了其他学期课程" }
  val courseIds = courses.map { requireNotNull(it.text("BJDM")) }.toSet()
  require(rows.all { it.text("BJDM") in courseIds }) { "GSMIS 排课缺少课程信息" }
  // SCSKRQ 是该教学班首次上课日期；减去最早排课的周/星期偏移，交叉核验学期起点。
  val starts =
      courses
          .mapNotNull { course ->
            val firstDate =
                course.text("SCSKRQ")?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val offsets =
                rows
                    .filter { it.text("BJDM") == course.text("BJDM") }
                    .mapNotNull {
                      val mask = requireNotNull(it.text("ZCBH"))
                      require(mask.isNotEmpty() && mask.all { c -> c == '0' || c == '1' })
                      val day = requireNotNull(it.text("XQ")).toInt()
                      require(day in 1..7)
                      mask
                          .indexOf('1')
                          .takeIf { index -> index >= 0 }
                          ?.let { index -> 7 * index + day - 1 }
                    }
            offsets.minOrNull()?.let {
              LocalDate.fromEpochDays(LocalDate.parse(firstDate).toEpochDays() - it)
            }
          }
          .distinct()
  require(rows.isEmpty() || (starts.size == 1 && starts.single().dayOfWeek.ordinal == 0)) {
    "GSMIS 课表日期与周次无法一致对应"
  }
  val normalizedRows =
      rows.map { row ->
        fun slot(key: String): JsonObject {
          val section = requireNotNull(row.text(key)).toInt()
          return slots.single {
            it.text("JCFADM") == row.text("JCFADM") && it.text("DM")?.toInt() == section
          }
        }
        JsonObject(
            row +
                mapOf(
                    "XNXQDM" to JsonPrimitive(termCode),
                    "JSXM" to (row["JGJSXM"] ?: JsonNull),
                    "KSSJ" to slot("KSJCDM").getValue("KSSJ"),
                    "JSSJ" to slot("JSJCDM").getValue("JSSJ"),
                )
        )
      }
  // 复用已验证的节次校验、相邻课程合并和周视图转换，不复用选课系统网络接口。
  val normalized = buildJsonObject {
    put("results", JsonArray(normalizedRows))
    put(
        "xkjgList",
        JsonArray(
            courses.map { course ->
              buildJsonObject {
                put("BJDM", course.getValue("BJDM"))
                put("XNXQDM", termCode)
                put("XNXQMC", term.itemName)
                put("SFYXXKJG", "0")
              }
            }
        ),
    )
    put("rqpkjgallList", JsonArray(emptyList()))
    put("skjcList", JsonArray(slots))
  }
  return GraduateSchedule.parse(normalized.toString()).withCalendar(terms, starts.singleOrNull())
}
