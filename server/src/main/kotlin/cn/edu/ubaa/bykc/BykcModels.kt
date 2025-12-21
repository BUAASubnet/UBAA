package cn.edu.ubaa.bykc

import kotlinx.serialization.Serializable

/** BYKC API 响应包装类 */
@Serializable
data class BykcApiResponse<T>(
        val status: String,
        val errmsg: String,
        val token: String? = null,
        val data: T? = null
) {
        val isSuccess: Boolean
                get() = status == "0"
}

/** 用户信息 */
@Serializable
data class BykcUserProfile(
        val id: Long,
        val employeeId: String,
        val realName: String,
        val term: BykcTerm? = null,
        val college: BykcCollege? = null,
        val role: BykcRole? = null,
        val studentNo: String? = null,
        val studentType: String? = null,
        val classCode: String? = null,
        val noticeSwitch: Boolean? = null,
        val delFlag: Int = 0
)

/** 学期信息 */
@Serializable
data class BykcTerm(
        val id: Long,
        val termName: String,
        val planId: Int = 0,
        val grade: String? = null,
        val graduation: Boolean = false,
        val delFlag: Int = 0
)

/** 学院信息 */
@Serializable
data class BykcCollege(
        val id: Long,
        val collegeName: String,
        val openCoursePermission: Boolean = true,
        val collegeCode: String? = null,
        val delFlag: Int = 0
)

/** 角色信息 */
@Serializable data class BykcRole(val id: Long, val roleName: String, val delFlag: Int = 0)

/** 课程分类 */
@Serializable
data class BykcCourseKind(
        val id: Long,
        val kindName: String,
        val parentId: Long = 0,
        val delFlag: Int = 0
)

/** 课程信息（列表项） */
@Serializable
data class BykcCourse(
        val id: Long,
        val courseName: String,
        val coursePosition: String? = null,
        val courseContact: String? = null,
        val courseContactMobile: String? = null,
        val courseTeacher: String? = null,
        val courseCreateDate: String? = null,
        val courseStartDate: String? = null,
        val courseEndDate: String? = null,
        val courseSelectStartDate: String? = null,
        val courseSelectEndDate: String? = null,
        val courseCancelEndDate: String? = null,
        val courseNewKind1: BykcCourseKind? = null,
        val courseNewKind2: BykcCourseKind? = null,
        val courseNewKind3: BykcCourseKind? = null,
        val courseMaxCount: Int = 0,
        val courseCurrentCount: Int? = null,
        val courseCampus: String? = null,
        val courseDesc: String? = null,
        val courseSignType: Int? = null,
        val courseSignConfig: String? = null,
        val selected: Boolean? = null,
        val delFlag: Int = 0
)

/** 课程分页查询结果 */
@Serializable
data class BykcCoursePageResult(
        val content: List<BykcCourse> = emptyList(),
        val totalElements: Int = 0,
        val totalPages: Int = 0,
        val size: Int = 0,
        val number: Int = 0,
        val numberOfElements: Int = 0
)

/** 已选课程信息 */
@Serializable
data class BykcChosenCourse(
        val id: Long,
        val userInfo: BykcUserProfile? = null,
        val courseInfo: BykcCourse? = null,
        val selectDate: String? = null,
        val homework: String? = null,
        val homeworkAttachmentName: String? = null,
        val homeworkAttachmentPath: String? = null,
        val checkin: Int? = null,
        val score: Int? = null,
        val pass: Int? = null,
        val signInfo: String? = null
)

/** 已选课程列表接口的数据包装 */
@Serializable
data class BykcChosenCoursePayload(val courseList: List<BykcChosenCourse> = emptyList())

/** 系统配置 */
@Serializable
data class BykcAllConfig(
        val campus: List<BykcCampus> = emptyList(),
        val college: List<BykcCollege> = emptyList(),
        val role: List<BykcRole> = emptyList(),
        val semester: List<BykcSemester> = emptyList(),
        val term: List<BykcTerm> = emptyList()
)

/** 校区信息 */
@Serializable data class BykcCampus(val id: Long, val campusName: String, val delFlag: Int = 0)

/** 学期详细信息 */
@Serializable
data class BykcSemester(
        val id: Long,
        val semesterName: String? = null,
        val semesterStartDate: String? = null,
        val semesterEndDate: String? = null,
        val delFlag: Int = 0
)

/** 签到请求 */
@Serializable
data class BykcSignRequest(
        val courseId: Long,
        val signLat: Double? = null,
        val signLng: Double? = null,
        /** 1=签到, 2=签退 */
        val signType: Int
)

/** 签到配置（从courseSignConfig字段解析） */
@Serializable
data class BykcSignConfig(
        val signStartDate: String? = null,
        val signEndDate: String? = null,
        val signOutStartDate: String? = null,
        val signOutEndDate: String? = null,
        val signPointList: List<BykcSignPoint> = emptyList()
)

/** 选课/退选响应数据 */
@Serializable data class BykcCourseActionResult(val courseCurrentCount: Int? = null)

/** 签到响应数据 */
@Serializable
data class BykcSignResult(
        val id: Long? = null,
        val userInfo: BykcUserProfile? = null,
        val courseInfo: BykcCourse? = null
)

/** 签到地点 */
@Serializable data class BykcSignPoint(val lat: Double, val lng: Double, val radius: Double = 0.0)

/** 统计信息数据 */
@Serializable
data class BykcStatisticsData(
        val statistical: Map<String, Map<String, BykcSubCategoryStats>> = emptyMap(),
        val validCount: Int = 0
)

/** 子类统计信息 */
@Serializable
data class BykcSubCategoryStats(
        val assessmentCount: Int = 0,
        val selectAssessmentCount: Int = 0,
        val completeAssessmentCount: Int = 0,
        val failAssessmentCount: Int = 0,
        val undoneAssessmentCount: Int = 0,
        val courseUserList: List<BykcChosenCourse> = emptyList()
)

// ============ 内部枚举（用于服务端状态计算） ============

/** 课程状态枚举（服务端内部使用） */
enum class BykcCourseStatusEnum(val displayName: String) {
        EXPIRED("过期"),
        SELECTED("已选"),
        PREVIEW("预告"),
        ENDED("结束"),
        FULL("满员"),
        AVAILABLE("可选")
}
