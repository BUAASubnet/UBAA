package cn.edu.ubaa.model.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** 考试查询原始响应体。 */
@Serializable
data class ExamResponse(
    val code: String,
    val msg: String? = null,
    val datas: List<Exam> = emptyList()
)

/**
 * 考试安排数据汇总。
 * @property stuInfo 学生的考籍信息。
 * @property arranged 已确定时间的考试安排。
 * @property notArranged 尚未排定或无需排定的考试。
 */
@Serializable
data class ExamArrangementData(
    val stuInfo: ExamStudentInfo? = null,
    val arranged: List<Exam> = emptyList(),
    val notArranged: List<Exam> = emptyList()
)

/** 学生考籍与学籍基本信息。 */
@Serializable
data class ExamStudentInfo(
    val name: String? = null,
    val studentId: String? = null,
    val department: String? = null,
    val major: String? = null,
    val grade: String? = null
)

/**
 * 具体的考试安排信息。
 * @property courseName 课程名。
 * @property courseNo 课程号。
 * @property examTimeDescription 考试时间描述。
 * @property examDate 考试日期。
 * @property startTime 开始时间。
 * @property endTime 结束时间。
 * @property examPlace 考场地点。
 * @property examSeatNo 座位号。
 * @property week 周次。
 * @property examStatus 状态。
 * @property examType 考试类型。
 * @property taskId 关联的任务 ID。
 */
@Serializable
data class Exam(
    val courseName: String,
    val courseNo: String? = null,
    val examTimeDescription: String? = null,
    val examDate: String? = null,
    val startTime: String? = null,
    val endTime: String? = null,
    val examPlace: String? = null,
    val examSeatNo: String? = null,
    val week: Int? = null,
    val examStatus: Int? = null,
    val examType: String? = null,
    val taskId: String? = null
)