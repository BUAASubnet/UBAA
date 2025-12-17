package cn.edu.ubaa.model.dto

import kotlinx.serialization.Serializable

/** 博雅课程状态 */
object BykcCourseStatus {
        const val EXPIRED = "过期"
        const val SELECTED = "已选"
        const val PREVIEW = "预告"
        const val ENDED = "结束"
        const val FULL = "满员"
        const val AVAILABLE = "可选"
}

/** 博雅课程列表项 DTO（用于客户端展示） */
@Serializable
data class BykcCourseDto(
        val id: Long,
        val courseName: String,
        val coursePosition: String? = null,
        val courseTeacher: String? = null,
        val courseStartDate: String? = null,
        val courseEndDate: String? = null,
        val courseSelectStartDate: String? = null,
        val courseSelectEndDate: String? = null,
        val courseMaxCount: Int = 0,
        val courseCurrentCount: Int = 0,
        val category: String? = null,
        val subCategory: String? = null,
        val status: String,
        val selected: Boolean = false,
        val courseDesc: String? = null
)

/** 博雅课程详情 DTO */
@Serializable
data class BykcCourseDetailDto(
        val id: Long,
        val courseName: String,
        val coursePosition: String? = null,
        val courseContact: String? = null,
        val courseContactMobile: String? = null,
        val courseTeacher: String? = null,
        val courseStartDate: String? = null,
        val courseEndDate: String? = null,
        val courseSelectStartDate: String? = null,
        val courseSelectEndDate: String? = null,
        val courseCancelEndDate: String? = null,
        val courseMaxCount: Int = 0,
        val courseCurrentCount: Int = 0,
        val category: String? = null,
        val subCategory: String? = null,
        val status: String,
        val selected: Boolean = false,
        val courseDesc: String? = null,
        val signConfig: BykcSignConfigDto? = null
)

/** 已选博雅课程 DTO */
@Serializable
data class BykcChosenCourseDto(
        val id: Long,
        val courseId: Long, // 课程本身的 ID（用于查询课程详情）
        val courseName: String,
        val coursePosition: String? = null,
        val courseTeacher: String? = null,
        val courseStartDate: String? = null,
        val courseEndDate: String? = null,
        val selectDate: String? = null,
        val category: String? = null,
        val subCategory: String? = null,
        val checkin: Int = 0,
        val score: Int? = null,
        val pass: Int = 0,
        val canSign: Boolean = false,
        val canSignOut: Boolean = false,
        val signConfig: BykcSignConfigDto? = null,
        val courseSignType: Int? = null,
        val homework: String? = null,
        val homeworkAttachmentName: String? = null,
        val homeworkAttachmentPath: String? = null,
        val signInfo: String? = null
)

/** 签到配置 DTO */
@Serializable
data class BykcSignConfigDto(
        val signStartDate: String? = null,
        val signEndDate: String? = null,
        val signOutStartDate: String? = null,
        val signOutEndDate: String? = null,
        val signPoints: List<BykcSignPointDto> = emptyList()
)

/** 签到地点 DTO */
@Serializable
data class BykcSignPointDto(val lat: Double, val lng: Double, val radius: Double = 0.0)

/** 博雅课程用户信息 DTO */
@Serializable
data class BykcUserProfileDto(
        val id: Long,
        val employeeId: String,
        val realName: String,
        val studentNo: String? = null,
        val studentType: String? = null,
        val classCode: String? = null,
        val collegeName: String? = null,
        val termName: String? = null
)

/** 选课请求 */
@Serializable data class BykcSelectRequest(val courseId: Long)

/** 签到请求 */
@Serializable
data class BykcSignRequest(
        val courseId: Long,
        val lat: Double? = null,
        val lng: Double? = null,
        /** 1=签到, 2=签退 */
        val signType: Int
)

/** 博雅课程列表响应 */
@Serializable data class BykcCoursesResponse(val courses: List<BykcCourseDto>, val total: Int)

/** 操作成功响应 */
@Serializable data class BykcSuccessResponse(val message: String)
