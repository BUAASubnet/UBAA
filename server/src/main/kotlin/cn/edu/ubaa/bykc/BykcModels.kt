package cn.edu.ubaa.bykc

import kotlinx.serialization.Serializable

/** 博雅 API 响应通用包装。 */
@Serializable
data class BykcApiResponse<T>(
        val status: String,
        val success: Boolean? = null,
        val data: T? = null,
        val msg: String? = null,
        val errmsg: String = ""
) {
    /** 判断业务是否成功（由 status="0" 决定）。 */
    val isSuccess: Boolean get() = status == "0"
}

/** 博雅系统用户信息模型。 */
@Serializable
data class BykcUserProfile(
        val id: Long,
        val employeeId: String,
        val realName: String,
        val studentNo: String? = null,
        val studentType: String? = null,
        val classCode: String? = null,
        val college: BykcCollege? = null,
        val term: BykcTerm? = null,
        val roleList: List<BykcRole> = emptyList()
)

/** 学期信息。 */
@Serializable data class BykcTerm(val id: Long, val termName: String, val current: Int = 0)

/** 学院信息。 */
@Serializable data class BykcCollege(val id: Long, val collegeName: String)

/** 角色信息。 */
@Serializable data class BykcRole(val id: Long, val roleName: String, val delFlag: Int = 0)

/** 课程类别。 */
@Serializable data class BykcCourseKind(val id: Long, val kindName: String)

/**
 * 博雅课程原始模型。
 */
@Serializable
data class BykcCourse(
        val id: Long,
        val courseName: String,
        val coursePosition: String? = null,
        val courseTeacher: String? = null,
        val courseStartDate: String? = null,
        val courseEndDate: String? = null,
        val courseSelectStartDate: String? = null,
        val courseSelectEndDate: String? = null,
        val courseCancelEndDate: String? = null,
        val courseMaxCount: Int,
        val courseCurrentCount: Int? = null,
        val courseNewKind1: BykcCourseKind? = null,
        val courseNewKind2: BykcCourseKind? = null,
        val selected: Boolean? = null,
        val courseDesc: String? = null,
        val courseContact: String? = null,
        val courseContactMobile: String? = null,
        val courseSignConfig: String? = null, // JSON 字符串
        val courseSignType: Int? = null
)

/** 课程分页查询结果。 */
@Serializable
data class BykcCoursePageResult(
        val content: List<BykcCourse>,
        val totalElements: Int,
        val totalPages: Int,
        val size: Int,
        val number: Int
)

/** 选课记录模型。 */
@Serializable
data class BykcChosenCourse(
        val id: Long,
        val selectDate: String? = null,
        val courseInfo: BykcCourse? = null,
        val checkin: Int? = null,
        val score: Int? = null,
        val pass: Int? = null,
        val homework: String? = null,
        val signInfo: String? = null
)

/** 系统全局配置项。 */
@Serializable
data class BykcAllConfig(
        val campus: List<BykcCampus> = emptyList(),
        val semester: List<BykcSemester> = emptyList()
)

/** 校区信息。 */
@Serializable data class BykcCampus(val id: Long, val campusName: String, val delFlag: Int = 0)

/** 学期时间配置。 */
@Serializable
data class BykcSemester(
        val id: Long,
        val semesterName: String,
        val semesterStartDate: String? = null,
        val semesterEndDate: String? = null
)

/** 签到配置模型。 */
@Serializable
data class BykcSignConfig(
        val signStartDate: String? = null,
        val signEndDate: String? = null,
        val signOutStartDate: String? = null,
        val signOutEndDate: String? = null,
        val signPointList: List<BykcSignPoint> = emptyList()
)

/** 签到地点坐标。 */
@Serializable data class BykcSignPoint(val lat: Double, val lng: Double, val radius: Double = 0.0)

/** 课程详情负载。 */
@Serializable data class BykcChosenCoursePayload(val courseList: List<BykcChosenCourse> = emptyList())

/** 操作执行结果。 */
@Serializable data class BykcCourseActionResult(val courseCurrentCount: Int? = null)

/** 签到结果。 */
@Serializable data class BykcSignResult(val signType: Int, val result: String = "")

/** 修读统计汇总数据。 */
@Serializable
data class BykcStatisticsData(
        val validCount: Int,
        val statistical: Map<String, Map<String, BykcSubCategoryStats>> = emptyMap()
)

/** 分类修读明细。 */
@Serializable
data class BykcSubCategoryStats(
        val assessmentCount: Int,
        val completeAssessmentCount: Int
)

/** 课程状态枚举。 */
enum class BykcCourseStatusEnum(val displayName: String) {
    EXPIRED("已过期"),
    SELECTED("已选"),
    PREVIEW("预告"),
    ENDED("已结束"),
    FULL("人数已满"),
    AVAILABLE("可选")
}