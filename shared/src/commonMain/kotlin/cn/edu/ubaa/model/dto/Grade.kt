package cn.edu.ubaa.model.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/** 成绩查询原始响应体。 */
@Serializable
data class GradeResponse(
    val code: String,
    val msg: String? = null,
    val datas: GradeResponseDatas = GradeResponseDatas(),
)

@Serializable data class GradeResponseDatas(val cxwdcj: GradeRows = GradeRows())

@Serializable
data class GradeRows(
    val totalSize: Int = 0,
    val pageSize: Int = 0,
    val rows: List<Grade> = emptyList(),
)

/** 指定学期的成绩列表。 */
@Serializable
data class GradeData(
    val termCode: String,
    val grades: List<Grade> = emptyList(),
)

/** 单门课程成绩。 */
@Serializable
data class Grade(
    @SerialName("WID") val id: String? = null,
    @SerialName("XNXQDM") val termCode: String? = null,
    @SerialName("XNXQDM_DISPLAY") val termName: String? = null,
    @SerialName("KCM") val courseName: String? = null,
    @SerialName("KCH") val courseCode: String? = null,
    @SerialName("TDKCM") val replacementCourseName: String? = null,
    @SerialName("TDKCH") val replacementCourseCode: String? = null,
    @SerialName("XF") val credit: Double? = null,
    @SerialName("XSZCJ") val score: String? = null,
    @SerialName("JD") val gradePoint: String? = null,
    @SerialName("KCLBDM_DISPLAY") val courseCategory: String? = null,
    @SerialName("XGXKLBDM_DISPLAY") val courseGroup: String? = null,
    @SerialName("KCXZDM_DISPLAY") val courseAttribute: String? = null,
    @SerialName("KSLXDM_DISPLAY") val examType: String? = null,
    @SerialName("CXCKDM_DISPLAY") val examAttempt: String? = null,
    @SerialName("SFJG_DISPLAY") val passed: String? = null,
    @SerialName("SFYX_DISPLAY") val effective: String? = null,
    @SerialName("CJRDFSDM_DISPLAY") val recognitionType: String? = null,
)

/** 北航成绩应用响应体。 */
@Serializable
data class BuaaScoreResponse(
    @SerialName("e") val code: Int = 0,
    @SerialName("m") val message: String? = null,
    @SerialName("d") val data: Map<String, BuaaScoreCourse> = emptyMap(),
)

/** 北航成绩应用中的单门课程成绩。 */
@Serializable
data class BuaaScoreCourse(
    @SerialName("kcmc") val courseName: String? = null,
    @SerialName("kch") val courseCode: String? = null,
    @SerialName("xf") val credit: JsonElement? = null,
    @SerialName("kccj") val score: JsonElement? = null,
    @SerialName("fslx") val scoreType: String? = null,
    @SerialName("kclx") val courseType: String? = null,
)

data class BuaaScoreTerm(val year: String, val semester: Int)

fun parseBuaaScoreTermCode(termCode: String): BuaaScoreTerm {
  val match =
      Regex("""^(\d{4}-\d{4})-(\d+)$""").matchEntire(termCode.trim())
          ?: throw IllegalArgumentException("Unsupported term code: $termCode")
  val semester =
      match.groupValues[2].toIntOrNull()
          ?: throw IllegalArgumentException("Unsupported term code: $termCode")
  return BuaaScoreTerm(year = match.groupValues[1], semester = semester)
}

fun BuaaScoreCourse.toGrade(termCode: String): Grade =
    Grade(
        termCode = termCode,
        termName = termCode,
        courseName = courseName.cleanText(),
        courseCode = courseCode.cleanText(),
        credit = credit.asText()?.toDoubleOrNull(),
        score = score.asText(),
        courseAttribute = courseType.cleanText(),
        recognitionType = scoreType.cleanText(),
        gradePoint = null,
    )

private fun JsonElement?.asText(): String? =
    (this as? JsonPrimitive)?.contentOrNull?.cleanText()

private fun String?.cleanText(): String? = this?.trim()?.takeIf { it.isNotEmpty() }
