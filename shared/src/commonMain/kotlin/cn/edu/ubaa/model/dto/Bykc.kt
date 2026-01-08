package cn.edu.ubaa.model.dto

import kotlinx.serialization.Serializable

/** 博雅课程状态常量定义。 */
object BykcCourseStatus {
  const val EXPIRED = "过期"
  const val SELECTED = "已选"
  const val PREVIEW = "预告"
  const val ENDED = "结束"
  const val FULL = "满员"
  const val AVAILABLE = "可选"
}

/**
 * 博雅课程简要信息 DTO。 用于课程列表展示。
 *
 * @property id 课程 ID。
 * @property courseName 课程名称。
 * @property coursePosition 上课地点。
 * @property courseTeacher 授课教师。
 * @property courseStartDate 课程开始时间。
 * @property courseEndDate 课程结束时间。
 * @property courseSelectStartDate 选课开始时间。
 * @property courseSelectEndDate 选课结束时间。
 * @property courseMaxCount 最大人数。
 * @property courseCurrentCount 当前已报名人数。
 * @property category 课程大类。
 * @property subCategory 课程小类。
 * @property status 课程当前状态描述（如“可选”、“已选”）。
 * @property selected 当前用户是否已选该课。
 * @property courseDesc 课程简介。
 */
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
  val courseDesc: String? = null,
)

/**
 * 博雅课程详细信息 DTO。
 *
 * @property id 课程 ID。
 * @property courseName 课程名称。
 * @property coursePosition 上课地点。
 * @property courseContact 联系人。
 * @property courseContactMobile 联系电话。
 * @property courseTeacher 授课教师。
 * @property courseStartDate 课程开始时间。
 * @property courseEndDate 课程结束时间。
 * @property courseSelectStartDate 选课开始时间。
 * @property courseSelectEndDate 选课结束时间。
 * @property courseCancelEndDate 退选截止时间。
 * @property courseMaxCount 最大人数。
 * @property courseCurrentCount 当前已报名人数。
 * @property category 课程大类。
 * @property subCategory 课程小类。
 * @property status 课程状态。
 * @property selected 是否已选。
 * @property courseDesc 课程详细描述。
 * @property signConfig 签到配置。
 * @property checkin 签到状态（通常 0 为未签，1 为已签）。
 * @property pass 是否通过考核。
 */
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
  val signConfig: BykcSignConfigDto? = null,
  val checkin: Int? = null,
  val pass: Int? = null,
)

/**
 * 用户已选博雅课程信息 DTO。
 *
 * @property id 选课记录 ID。
 * @property courseId 课程本体 ID。
 * @property courseName 课程名称。
 * @property coursePosition 上课地点。
 * @property courseTeacher 教师姓名。
 * @property courseStartDate 开始时间。
 * @property courseEndDate 结束时间。
 * @property selectDate 选课操作时间。
 * @property category 课程大类。
 * @property subCategory 课程小类。
 * @property checkin 签到状态。
 * @property score 成绩（若有）。
 * @property pass 考核是否合格。
 * @property canSign 当前是否可以执行签到。
 * @property canSignOut 当前是否可以执行签退。
 * @property signConfig 签到时间配置。
 * @property courseSignType 签到类型要求。
 * @property homework 作业要求描述。
 * @property homeworkAttachmentName 作业附件名。
 * @property homeworkAttachmentPath 作业附件下载路径。
 * @property signInfo 签到详细备注。
 */
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
  val pass: Int? = null,
  val canSign: Boolean = false,
  val canSignOut: Boolean = false,
  val signConfig: BykcSignConfigDto? = null,
  val courseSignType: Int? = null,
  val homework: String? = null,
  val homeworkAttachmentName: String? = null,
  val homeworkAttachmentPath: String? = null,
  val signInfo: String? = null,
)

/**
 * 签到时间配置 DTO。
 *
 * @property signStartDate 允许签到的起始时间。
 * @property signEndDate 允许签到的截止时间。
 * @property signOutStartDate 允许签退的起始时间。
 * @property signOutEndDate 允许签退的截止时间。
 * @property signPoints 允许签到的地理位置范围列表。
 */
@Serializable
data class BykcSignConfigDto(
  val signStartDate: String? = null,
  val signEndDate: String? = null,
  val signOutStartDate: String? = null,
  val signOutEndDate: String? = null,
  val signPoints: List<BykcSignPointDto> = emptyList(),
)

/**
 * 签到地理位置 DTO。
 *
 * @property lat 纬度。
 * @property lng 经度。
 * @property radius 允许误差半径（米）。
 */
@Serializable
data class BykcSignPointDto(val lat: Double, val lng: Double, val radius: Double = 0.0)

/**
 * 博雅课程系统用户信息 DTO。
 *
 * @property id 用户 ID。
 * @property employeeId 教职工/学生内部 ID。
 * @property realName 真实姓名。
 * @property studentNo 学号。
 * @property studentType 学生类别。
 * @property classCode 行政班级代码。
 * @property collegeName 学院名称。
 * @property termName 当前学期描述。
 */
@Serializable
data class BykcUserProfileDto(
  val id: Long,
  val employeeId: String,
  val realName: String,
  val studentNo: String? = null,
  val studentType: String? = null,
  val classCode: String? = null,
  val collegeName: String? = null,
  val termName: String? = null,
)

/**
 * 博雅课程修读统计汇总 DTO。
 *
 * @property totalValidCount 累计有效修读次数。
 * @property categories 各分类的详细统计信息。
 */
@Serializable
data class BykcStatisticsDto(
  val totalValidCount: Int,
  val categories: List<BykcCategoryStatisticsDto>,
)

/**
 * 博雅课程分类统计明细 DTO。
 *
 * @property categoryName 课程大类名称（如“博雅课程”）。
 * @property subCategoryName 课程小类名称（如“德育”）。
 * @property requiredCount 考核指标（要求的修读次数）。
 * @property passedCount 考核通过（已完成的修读次数）。
 * @property isQualified 是否已达到该类的考核要求。
 */
@Serializable
data class BykcCategoryStatisticsDto(
  val categoryName: String, // 大类 (e.g. "博雅课程")
  val subCategoryName: String, // 小类 (e.g. "德育")
  val requiredCount: Int, // 考核指标
  val passedCount: Int, // 考核通过
  val isQualified: Boolean, // 是否达标 (passed >= required)
)

/** 选课请求负载。 */
@Serializable data class BykcSelectRequest(val courseId: Long)

/**
 * 签到/签退请求负载。
 *
 * @property courseId 课程 ID。
 * @property lat 上传的纬度。
 * @property lng 上传的经度。
 * @property signType 操作类型：1=签到, 2=签退。
 */
@Serializable
data class BykcSignRequest(
  val courseId: Long,
  val lat: Double? = null,
  val lng: Double? = null,
  /** 1=签到, 2=签退 */
  val signType: Int,
)

/** 博雅课程分页查询结果。 */
@Serializable
data class BykcCoursePage(
  val courses: List<BykcCourseDto>,
  val totalElements: Int,
  val totalPages: Int,
  val currentPage: Int,
  val pageSize: Int,
)

/** 博雅课程列表 API 响应体。 */
@Serializable
data class BykcCoursesResponse(
  val courses: List<BykcCourseDto>,
  val total: Int,
  val totalPages: Int = 0,
  val currentPage: Int = 1,
  val pageSize: Int = 20,
)

/** 统一的操作成功响应消息。 */
@Serializable data class BykcSuccessResponse(val message: String)
