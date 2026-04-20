@file:UseSerializers(cn.edu.ubaa.model.dto.BykcLocalDateTimeSerializer::class)

package cn.edu.ubaa.model.dto

import kotlinx.datetime.LocalDateTime
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

/** 博雅课程一级分类。 */
@Serializable
enum class BykcCourseCategory(val displayName: String) {
  @SerialName("博雅课程") BOYA("博雅课程"),
  @SerialName("未知分类") UNKNOWN("未知分类");

  companion object {
    fun fromDisplayName(value: String?): BykcCourseCategory? {
      val normalized = value?.trim()?.takeIf { it.isNotEmpty() } ?: return null
      return entries.firstOrNull { it.displayName == normalized } ?: UNKNOWN
    }
  }
}

/** 博雅课程二级分类。 */
@Serializable
enum class BykcCourseSubCategory(val displayName: String) {
  @SerialName("德育") MORAL("德育"),
  @SerialName("美育") AESTHETIC("美育"),
  @SerialName("劳动教育") LABOR("劳动教育"),
  @SerialName("安全健康") SAFETY_HEALTH("安全健康"),
  @SerialName("其他方面") OTHER("其他方面"),
  @SerialName("未知类型") UNKNOWN("未知类型");

  companion object {
    fun fromDisplayName(value: String?): BykcCourseSubCategory? {
      val normalized = value?.trim()?.takeIf { it.isNotEmpty() } ?: return null
      return entries.firstOrNull { it.displayName == normalized } ?: UNKNOWN
    }
  }
}

/** 博雅课程状态。 */
@Serializable
enum class BykcCourseStatus(val displayName: String) {
  @SerialName("已过期") EXPIRED("已过期"),
  @SerialName("已选") SELECTED("已选"),
  @SerialName("预告") PREVIEW("预告"),
  @SerialName("选课结束") ENDED("选课结束"),
  @SerialName("人数已满") FULL("人数已满"),
  @SerialName("可选") AVAILABLE("可选"),
  ;

  override fun toString(): String = displayName
}

/**
 * 博雅课程列表项 DTO。
 *
 * 仅保留课程广场列表与卡片展示真正需要的字段，避免把详情态、签到态、原始兼容字段一并暴露到前端。
 */
@Serializable
data class BykcCourseDto(
    val id: Long,
    val courseName: String,
    val coursePosition: String? = null,
    val courseTeacher: String? = null,
    val courseStartDate: LocalDateTime? = null,
    val courseEndDate: LocalDateTime? = null,
    val courseSelectStartDate: LocalDateTime? = null,
    val courseSelectEndDate: LocalDateTime? = null,
    val courseCancelEndDate: LocalDateTime? = null,
    val courseMaxCount: Int = 0,
    /**
     * 当前报名人数。
     *
     * 列表接口通常会返回该值；若上游未返回，则保留为 `null`，避免把缺失信息误写成 `0`。
     */
    val courseCurrentCount: Int? = null,
    /** BYKC 新版一级分类，如“博雅课程”。 */
    val category: BykcCourseCategory? = null,
    /** BYKC 新版二级分类，如“德育/美育/劳动教育/安全健康/其他方面”。 */
    val subCategory: BykcCourseSubCategory? = null,
    /** 允许报名的校区范围文本。 */
    val audienceCampuses: List<String> = emptyList(),
    /** 是否存在基于地点的签到点配置。 */
    val hasSignPoints: Boolean = false,
    /** 服务端统一计算后的课程状态。 */
    val status: BykcCourseStatus,
    /** 当前用户是否已选择该课程。 */
    val selected: Boolean = false,
)

/**
 * 博雅课程详情 DTO。
 *
 * 字段设计上保持为 [BykcCourseDto] 的超集：列表页已有的展示字段在详情页仍然可用， 仅额外补充正文、联系方式、受众范围、签到信息等详情专属数据。
 */
@Serializable
data class BykcCourseDetailDto(
    val id: Long,
    val courseName: String,
    val coursePosition: String? = null,
    val courseTeacher: String? = null,
    val courseStartDate: LocalDateTime? = null,
    val courseEndDate: LocalDateTime? = null,
    val courseSelectStartDate: LocalDateTime? = null,
    val courseSelectEndDate: LocalDateTime? = null,
    val courseCancelEndDate: LocalDateTime? = null,
    val courseMaxCount: Int = 0,
    val courseCurrentCount: Int? = null,
    val category: BykcCourseCategory? = null,
    val subCategory: BykcCourseSubCategory? = null,
    val hasSignPoints: Boolean = false,
    val status: BykcCourseStatus,
    val selected: Boolean = false,
    /** 课程联系人。 */
    val courseContact: String? = null,
    /** 课程联系人电话。 */
    val courseContactMobile: String? = null,
    /** 开课单位名称。 */
    val organizerCollegeName: String? = null,
    /** 课程简介；BYKC 原始返回中通常为 HTML 片段。 */
    val courseDesc: String? = null,
    /** 允许报名的校区范围文本。 */
    val audienceCampuses: List<String> = emptyList(),
    /** 允许报名的学院范围文本。 */
    val audienceColleges: List<String> = emptyList(),
    /** 允许报名的年级范围文本。 */
    val audienceTerms: List<String> = emptyList(),
    /** 允许报名的人群范围文本，如“本科”。 */
    val audienceGroups: List<String> = emptyList(),
    /** 解析后的签到配置。 */
    val signConfig: BykcSignConfigDto? = null,
    /** 当前用户的签到状态。 */
    val checkin: Int? = null,
    /** 当前用户的考核状态。 */
    val pass: Int? = null,
    /** 当前是否可执行签到。 */
    val canSign: Boolean = false,
    /** 当前是否可执行签退。 */
    val canSignOut: Boolean = false,
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
 * @property courseCancelEndDate 退选截止时间。
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
    val courseStartDate: LocalDateTime? = null,
    val courseEndDate: LocalDateTime? = null,
    val selectDate: LocalDateTime? = null,
    val courseCancelEndDate: LocalDateTime? = null,
    val category: BykcCourseCategory? = null,
    val subCategory: BykcCourseSubCategory? = null,
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
    val signStartDate: LocalDateTime? = null,
    val signEndDate: LocalDateTime? = null,
    val signOutStartDate: LocalDateTime? = null,
    val signOutEndDate: LocalDateTime? = null,
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
