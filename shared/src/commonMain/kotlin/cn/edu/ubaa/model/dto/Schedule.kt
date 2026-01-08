package cn.edu.ubaa.model.dto

import kotlinx.serialization.Serializable

/**
 * 学期信息 DTO。
 *
 * @property itemCode 学期代码（如 "2024-2025-1"）。
 * @property itemName 学期名称（如 "2024-2025学年第一学期"）。
 * @property selected 是否为当前选中的学期。
 * @property itemIndex 学期索引。
 */
@Serializable
data class Term(
  val itemCode: String,
  val itemName: String,
  val selected: Boolean,
  val itemIndex: Int,
)

/**
 * 周次信息 DTO。
 *
 * @property startDate 周开始日期（yyyy-MM-dd）。
 * @property endDate 周结束日期（yyyy-MM-dd）。
 * @property term 所属学期代码。
 * @property curWeek 是否为当前周。
 * @property serialNumber 周次序号。
 * @property name 周次名称（如 "第1周"）。
 */
@Serializable
data class Week(
  val startDate: String,
  val endDate: String,
  val term: String,
  val curWeek: Boolean,
  val serialNumber: Int,
  val name: String,
)

/**
 * 课程班级/排课信息 DTO。
 *
 * @property courseCode 课程代码。
 * @property courseName 课程名称。
 * @property courseSerialNo 课程序列号。
 * @property credit 学分。
 * @property beginTime 开始时间（HH:mm）。
 * @property endTime 结束时间（HH:mm）。
 * @property beginSection 开始节次。
 * @property endSection 结束节次。
 * @property placeName 上课地点。
 * @property weeksAndTeachers 上课周次与教师信息描述。
 * @property teachingTarget 教学对象。
 * @property color UI 显示颜色（十六进制）。
 * @property dayOfWeek 星期几（1-7）。
 */
@Serializable
data class CourseClass(
  val courseCode: String,
  val courseName: String,
  val courseSerialNo: String?,
  val credit: String?,
  val beginTime: String?,
  val endTime: String?,
  val beginSection: Int?,
  val endSection: Int?,
  val placeName: String?,
  val weeksAndTeachers: String?,
  val teachingTarget: String?,
  val color: String?,
  val dayOfWeek: Int?,
)

/**
 * 周课表信息 DTO。
 *
 * @property arrangedList 该周的所有排课列表。
 * @property code 学期代码。
 * @property name 学期名称。
 */
@Serializable
data class WeeklySchedule(val arrangedList: List<CourseClass>, val code: String, val name: String)

/**
 * 今日课程摘要 DTO。
 *
 * @property bizName 课程/业务名称。
 * @property place 上课地点。
 * @property time 上课时间描述。
 * @property shortName 课程简称。
 */
@Serializable
data class TodayClass(
  val bizName: String,
  val place: String?,
  val time: String?,
  val shortName: String?,
)

/** 上游 API 学期列表响应包装类。 */
@Serializable data class TermResponse(val datas: List<Term>, val code: String, val msg: String?)

/** 上游 API 周次列表响应包装类。 */
@Serializable data class WeekResponse(val datas: List<Week>, val code: String, val msg: String?)

/** 上游 API 周课表响应包装类。 */
@Serializable
data class WeeklyScheduleResponse(val datas: WeeklySchedule, val code: String, val msg: String?)

/** 上游 API 今日课表响应包装类。 */
@Serializable
data class TodayScheduleResponse(val datas: List<TodayClass>, val code: String, val msg: String?)
