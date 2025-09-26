package cn.edu.ubaa.model.dto

import kotlinx.serialization.Serializable

@Serializable
data class Term(
    val itemCode: String,
    val itemName: String,
    val selected: Boolean,
    val itemIndex: Int
)

@Serializable
data class Week(
    val startDate: String,
    val endDate: String,
    val term: String,
    val curWeek: Boolean,
    val serialNumber: Int,
    val name: String
)

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
    val dayOfWeek: Int?
)

@Serializable
data class WeeklySchedule(
    val arrangedList: List<CourseClass>,
    val code: String,
    val name: String
)

@Serializable
data class TodayClass(
    val bizName: String,
    val place: String?,
    val time: String?,
    val shortName: String?
)

// Response wrappers for upstream API format
@Serializable
data class TermResponse(
    val datas: List<Term>,
    val code: String,
    val msg: String?
)

@Serializable
data class WeekResponse(
    val datas: List<Week>,
    val code: String,
    val msg: String?
)

@Serializable
data class WeeklyScheduleResponse(
    val datas: WeeklySchedule,
    val code: String,
    val msg: String?
)

@Serializable
data class TodayScheduleResponse(
    val datas: List<TodayClass>,
    val code: String,
    val msg: String?
)