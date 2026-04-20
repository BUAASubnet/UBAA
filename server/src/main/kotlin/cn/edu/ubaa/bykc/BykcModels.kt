package cn.edu.ubaa.bykc

import kotlinx.serialization.Serializable

/** 博雅 API 响应通用包装。 */
@Serializable
data class BykcApiResponse<T>(
    val status: String,
    val success: Boolean? = null,
    val data: T? = null,
    val msg: String? = null,
    val errmsg: String = "",
) {
  /** 判断业务是否成功（由 status="0" 决定）。 */
  val isSuccess: Boolean
    get() = status == "0"
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
    val roleList: List<BykcRole> = emptyList(),
)

/** 学期信息。 */
@Serializable
data class BykcTerm(
    val id: Long,
    val termName: String,
    val planId: Long? = null,
    val grade: String? = null,
    val graduation: Boolean? = null,
    /** 0=有效，1=删除（推测） */
    val delFlag: Int? = null,
    /** 当前学期标记：1=当前，0=非当前（仅部分接口返回） */
    val current: Int = 0,
)

/** 学院信息。 */
@Serializable
data class BykcCollege(
    val id: Long,
    val collegeName: String,
    /** 是否允许开课（仅部分接口返回） */
    val openCoursePermission: Boolean? = null,
    /** 院系代码，例如 "10600" */
    val collegeCode: String? = null,
    /** 0=有效，1=删除（推测） */
    val delFlag: Int? = null,
)

/** 角色信息。 */
@Serializable
data class BykcRole(
    val id: Long,
    val roleName: String,
    /** 0=有效，1=删除（推测） */
    val delFlag: Int = 0,
)

/** 课程类别。 */
@Serializable
data class BykcCourseKind(
    val id: Long,
    val kindName: String,
    /** 父级类别 ID；顶级类别通常为 0 */
    val parentId: Long? = null,
    /** 0=有效，1=删除（推测） */
    val delFlag: Int? = null,
)

/** 课程发布方/选课人用户信息（BYKC 原始结构）。 */
@Serializable
data class BykcRawUser(
    val id: Long,
    val employeeId: String? = null,
    val realName: String? = null,
    val term: BykcTerm? = null,
    val college: BykcCollege? = null,
    val role: BykcRole? = null,
    val studentNo: String? = null,
    /** 常见值：`BENKE`/`SHUOSHI`/`BOSHI` 等 */
    val studentType: String? = null,
    val classCode: String? = null,
    /** 辅导员/管理员负责的学院 */
    val instructCollege: BykcCollege? = null,
    /** 辅导员/管理员负责的班级代码列表（逗号分隔字符串） */
    val instructClassCode: String? = null,
    /** 辅导员/管理员负责的学生类型代码（逗号分隔字符串） */
    val instructStudentType: String? = null,
    /** 是否开启通知（仅部分接口返回） */
    val noticeSwitch: Boolean? = null,
    /** 0=有效，1=删除（推测） */
    val delFlag: Int? = null,
    val ipAddress: String? = null,
)

/** 博雅课程原始模型。 */
@Serializable
data class BykcRawCourse(
    /** 课程 ID（BYKC 内部主键） */
    val id: Long,
    /** 课程名称 */
    val courseName: String,
    /** 开课单位（发布课程的学院/部门） */
    val courseBelongCollege: BykcCollege? = null,
    /** 发布人信息（管理员/辅导员等） */
    val courseBelongUser: BykcRawUser? = null,
    /** 上课地点 */
    val coursePosition: String? = null,
    /** 联系人 */
    val courseContact: String? = null,
    /** 联系电话 */
    val courseContactMobile: String? = null,
    /** 授课教师 */
    val courseTeacher: String? = null,
    /** 课程创建时间，格式 `yyyy-MM-dd HH:mm:ss` */
    val courseCreateDate: String? = null,
    /** 课程开始时间，格式 `yyyy-MM-dd HH:mm:ss` */
    val courseStartDate: String? = null,
    /** 课程结束时间，格式 `yyyy-MM-dd HH:mm:ss` */
    val courseEndDate: String? = null,
    /** 选课模式；已见值 `"1"`（其余取值待确认） */
    val courseSelectType: String? = null,
    /** 选课开始时间 */
    val courseSelectStartDate: String? = null,
    /** 选课结束时间 */
    val courseSelectEndDate: String? = null,
    /** 退选截止时间 */
    val courseCancelEndDate: String? = null,
    /** 最大选课人数 */
    val courseMaxCount: Int,
    /** 当前选课人数；有时为 null */
    val courseCurrentCount: Int? = null,
    /** 通过人数（部分接口返回） */
    val coursePassCount: Int? = null,
    /** 未通过人数（部分接口返回） */
    val courseUnPassCount: Int? = null,
    /** 新版课程大类（如“博雅课程”） */
    val courseNewKind1: BykcCourseKind? = null,
    /** 新版课程子类（如“德育/美育/劳动教育/安全健康”） */
    val courseNewKind2: BykcCourseKind? = null,
    /** 新版课程三级分类（通常为空） */
    val courseNewKind3: BykcCourseKind? = null,
    /** 旧版分类字段（兼容历史数据，通常为空） */
    val courseKind1: BykcCourseKind? = null,
    /** 旧版分类字段（兼容历史数据，通常为空） */
    val courseKind2: BykcCourseKind? = null,
    /** 旧版分类字段（兼容历史数据，通常为空） */
    val courseKind3: BykcCourseKind? = null,
    /** 校区范围；常见值：`ALL`、`[1]`、`[2]` */
    val courseCampus: String? = null,
    /** 校区范围文本列表；例如 `["学院路校区"]` / `["全部校区"]` */
    val courseCampusList: List<String>? = null,
    /** 学院范围；常见值：`ALL`、`[学院ID,...]` */
    val courseCollege: String? = null,
    /** 学院范围文本列表；例如 `["全部学院"]` */
    val courseCollegeList: List<String>? = null,
    /** 年级范围；常见值：`ALL`、`[termId,...]` */
    val courseTerm: String? = null,
    /** 年级范围文本列表；例如 `["全部年级"]` */
    val courseTermList: List<String>? = null,
    /** 人群范围；常见值：`ALL`、`[BENKE]` */
    val courseGroup: String? = null,
    /** 人群范围文本列表；例如 `["全部人群"]` / `["本科"]` */
    val courseGroupList: List<String>? = null,
    /** 是否包含作业：0=无，1=有（推测） */
    val courseHomework: Int? = null,
    /** 作业开放时间 */
    val courseHomeworkStartDate: String? = null,
    /** 作业截止时间 */
    val courseHomeworkEndDate: String? = null,
    /** 作业要求 */
    val courseHomeworkRequirement: String? = null,
    /** 课程简介/说明 */
    val courseDesc: String? = null,
    /** 审核状态（取值语义待确认，常见 0） */
    val courseAudit: Int? = null,
    /** 是否发送通知：0=否，1=是（推测） */
    val courseNotice: Int? = null,
    /** 签到类型：1=仅签到，2=签到+签退（基于现网观察） */
    val courseSignType: Int? = null,
    /** 签到配置，JSON 字符串；也可能为空字符串 */
    val courseSignConfig: String? = null,
    /** 课程业务状态（BYKC 原始数值，语义待确认；已观察值：`null`、`3`） */
    val status: Int? = null,
    /** 删除标记：0=有效，1=删除（推测） */
    val delFlag: Int? = null,
    /** 当前用户是否已选该课；已观察值：`true`/`false`/`null` */
    val selected: Boolean? = null,
)

/** 课程分页查询结果。 */
@Serializable
data class BykcCoursePageResult(
    val content: List<BykcRawCourse>,
    val totalElements: Int,
    val totalPages: Int,
    val size: Int,
    val number: Int,
)

/** 选课记录模型。 */
@Serializable
data class BykcChosenCourse(
    /** 选课记录 ID */
    val id: Long,
    /** 选课人信息 */
    val userInfo: BykcRawUser? = null,
    /** 选课时间 */
    val selectDate: String? = null,
    /** 对应课程完整信息 */
    val courseInfo: BykcRawCourse? = null,
    /** 签到状态（常见：0=未签，1=已签到） */
    val checkin: Int? = null,
    /** 分数（具体范围待确认） */
    val score: Int? = null,
    /** 是否通过（常见：0/1） */
    val pass: Int? = null,
    /** 作业文本内容 */
    val homework: String? = null,
    /** 作业附件名 */
    val homeworkAttachmentName: String? = null,
    /** 作业附件路径 */
    val homeworkAttachmentPath: String? = null,
    /** 签到备注信息 */
    val signInfo: String? = null,
)

/** 系统全局配置项。 */
@Serializable
data class BykcAllConfig(
    val college: List<BykcCollege> = emptyList(),
    val role: List<BykcRole> = emptyList(),
    val campus: List<BykcCampus> = emptyList(),
    val term: List<BykcTerm> = emptyList(),
    val semester: List<BykcSemester> = emptyList(),
)

/** 校区信息。 */
@Serializable data class BykcCampus(val id: Long, val campusName: String, val delFlag: Int = 0)

/** 学期时间配置。 */
@Serializable
data class BykcSemester(
    val id: Long,
    val semesterName: String,
    val semesterStartDate: String? = null,
    val semesterEndDate: String? = null,
)

/** 签到配置模型。 */
@Serializable
data class BykcSignConfig(
    val signStartDate: String? = null,
    val signEndDate: String? = null,
    val signOutStartDate: String? = null,
    val signOutEndDate: String? = null,
    val signPointList: List<BykcSignPoint> = emptyList(),
)

/** 签到地点坐标。 */
@Serializable data class BykcSignPoint(val lat: Double, val lng: Double, val radius: Double = 0.0)

/** 课程详情负载。 */
@Serializable
data class BykcChosenCoursePayload(val courseList: List<BykcChosenCourse> = emptyList())

/** 操作执行结果。 */
@Serializable data class BykcCourseActionResult(val courseCurrentCount: Int? = null)

/** 修读统计汇总数据。 */
@Serializable
data class BykcStatisticsData(
    val validCount: Int,
    val statistical: Map<String, Map<String, BykcSubCategoryStats>> = emptyMap(),
)

/** 分类修读明细。 */
@Serializable
data class BykcSubCategoryStats(val assessmentCount: Int, val completeAssessmentCount: Int)
