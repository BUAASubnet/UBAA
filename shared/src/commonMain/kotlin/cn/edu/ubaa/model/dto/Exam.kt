package cn.edu.ubaa.model.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ExamResponse(
    val code: String,
    val msg: String? = null,
    val datas: List<Exam> = emptyList()
)

@Serializable
data class ExamArrangementData(
    val stuInfo: ExamStudentInfo? = null,
    val arranged: List<Exam> = emptyList(),
    val notArranged: List<Exam> = emptyList()
)

@Serializable
data class ExamStudentInfo(
    val name: String? = null,
    val studentId: String? = null,
    val department: String? = null,
    val major: String? = null,
    val grade: String? = null
)

@Serializable
data class Exam(
    val courseName: String, // 课程名
    val courseNo: String? = null, // 课程号
    val examTimeDescription: String? = null, // 考试时间描述
    val examDate: String? = null, // 考试日期
    val startTime: String? = null, // 开始时间
    val endTime: String? = null, // 结束时间
    val examPlace: String? = null, // 考场地点
    val examSeatNo: String? = null, // 座位号
    val week: Int? = null, // 周次
    val examStatus: Int? = null, // 状态
    val examType: String? = null, // 考试类型
    val taskId: String? = null
)