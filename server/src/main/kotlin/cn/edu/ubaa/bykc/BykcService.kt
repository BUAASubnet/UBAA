package cn.edu.ubaa.bykc

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.model.dto.BykcChosenCourseDto
import cn.edu.ubaa.model.dto.BykcCourseDetailDto
import cn.edu.ubaa.model.dto.BykcCourseDto
import cn.edu.ubaa.model.dto.BykcSignConfigDto
import cn.edu.ubaa.model.dto.BykcSignPointDto
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

/**
 * 博雅课程服务层
 *
 * 封装 BykcClient，提供高层业务逻辑，包括：
 * - 课程列表查询与状态计算
 * - 选课/退选
 * - 已选课程查询
 * - 签到/签退
 */
class BykcService(private val sessionManager: SessionManager = GlobalSessionManager.instance) {
    private val log = LoggerFactory.getLogger(BykcService::class.java)
    private val json = Json { ignoreUnknownKeys = true }

    // 缓存每个用户的 BykcClient 实例
    private val clientCache = mutableMapOf<String, BykcClient>()

    /** 获取或创建指定用户的 BykcClient */
    private fun getClient(username: String): BykcClient {
        return clientCache.getOrPut(username) {
            BykcClient(username).also { log.debug("Created new BykcClient for user: {}", username) }
        }
    }

    /** 确保用户已登录 BYKC 系统 */
    suspend fun ensureBykcLogin(username: String): Boolean {
        val client = getClient(username)
        return try {
            client.login()
            log.info("BYKC login successful for user: {}", username)
            true
        } catch (e: Exception) {
            log.error("BYKC login failed for user: {}", username, e)
            false
        }
    }

    /** 获取用户的博雅课程个人信息 */
    suspend fun getUserProfile(username: String): BykcUserProfile {
        ensureBykcLogin(username)
        val client = getClient(username)
        return client.getUserProfile()
    }

    /**
     * 查询当前学期的博雅课程列表
     *
     * @param username 用户名
     * @param pageNumber 页码（从1开始）
     * @param pageSize 每页数量
     * @return 课程列表（带状态计算）
     */
    suspend fun getCourses(
            username: String,
            pageNumber: Int = 1,
            pageSize: Int = 200
    ): List<BykcCourseDto> {
        ensureBykcLogin(username)
        val client = getClient(username)
        val result = client.queryStudentSemesterCourseByPage(pageNumber, pageSize)

        return result.content.mapNotNull { course ->
            try {
                val status = calculateCourseStatus(course)
                // 过滤掉已过期和已结束的课程（可选）
                if (status == BykcCourseStatusEnum.EXPIRED || status == BykcCourseStatusEnum.ENDED
                ) {
                    return@mapNotNull null
                }

                BykcCourseDto(
                        id = course.id,
                        courseName = course.courseName,
                        coursePosition = course.coursePosition,
                        courseTeacher = course.courseTeacher,
                        courseStartDate = course.courseStartDate,
                        courseEndDate = course.courseEndDate,
                        courseSelectStartDate = course.courseSelectStartDate,
                        courseSelectEndDate = course.courseSelectEndDate,
                        courseMaxCount = course.courseMaxCount,
                        courseCurrentCount = course.courseCurrentCount ?: 0,
                        category = course.courseNewKind1?.kindName,
                        subCategory = course.courseNewKind2?.kindName,
                        status = status.displayName,
                        selected = course.selected ?: false,
                        courseDesc = course.courseDesc
                )
            } catch (e: Exception) {
                log.warn("Failed to process course {}: {}", course.id, e.message)
                null
            }
        }
    }

    /** 获取所有课程（包括已过期的） */
    suspend fun getAllCourses(
            username: String,
            pageNumber: Int = 1,
            pageSize: Int = 200
    ): List<BykcCourseDto> {
        ensureBykcLogin(username)
        val client = getClient(username)
        val result = client.queryStudentSemesterCourseByPage(pageNumber, pageSize)

        return result.content.map { course ->
            val status = calculateCourseStatus(course)
            BykcCourseDto(
                    id = course.id,
                    courseName = course.courseName,
                    coursePosition = course.coursePosition,
                    courseTeacher = course.courseTeacher,
                    courseStartDate = course.courseStartDate,
                    courseEndDate = course.courseEndDate,
                    courseSelectStartDate = course.courseSelectStartDate,
                    courseSelectEndDate = course.courseSelectEndDate,
                    courseMaxCount = course.courseMaxCount,
                    courseCurrentCount = course.courseCurrentCount ?: 0,
                    category = course.courseNewKind1?.kindName,
                    subCategory = course.courseNewKind2?.kindName,
                    status = status.displayName,
                    selected = course.selected ?: false,
                    courseDesc = course.courseDesc
            )
        }
    }

    /** 选择课程 */
    suspend fun selectCourse(username: String, courseId: Long): Result<String> {
        return try {
            ensureBykcLogin(username)
            val client = getClient(username)
            val response = client.choseCourse(courseId)
            log.info("User {} selected course {}", username, courseId)
            Result.success("选课成功")
        } catch (e: Exception) {
            log.error("User {} failed to select course {}: {}", username, courseId, e.message)
            Result.failure(e)
        }
    }

    /** 退选课程 */
    suspend fun deselectCourse(username: String, courseId: Long): Result<String> {
        return try {
            ensureBykcLogin(username)
            val client = getClient(username)
            client.delChosenCourse(courseId)
            log.info("User {} deselected course {}", username, courseId)
            Result.success("退选成功")
        } catch (e: BykcSelectException) {
            log.warn("User {} failed to deselect course {}: {}", username, courseId, e.message)
            Result.failure(e)
        } catch (e: Exception) {
            log.error("User {} failed to deselect course {}: {}", username, courseId, e.message)
            Result.failure(e)
        }
    }

    /** 获取已选课程列表 */
    suspend fun getChosenCourses(username: String): List<BykcChosenCourseDto> {
        ensureBykcLogin(username)
        val client = getClient(username)

        // 获取当前学期的时间范围
        val config = client.getAllConfig()
        val semester = config.semester.firstOrNull() ?: throw BykcException("无法获取当前学期信息")

        val startDate = semester.semesterStartDate ?: throw BykcException("学期开始日期为空")
        val endDate = semester.semesterEndDate ?: throw BykcException("学期结束日期为空")

        val chosenCourses = client.queryChosenCourse(startDate, endDate)

        return chosenCourses.map { chosen ->
            val course = chosen.courseInfo
            val signConfig = parseSignConfig(course?.courseSignConfig)
            val now = LocalDateTime.now()

            BykcChosenCourseDto(
                    id = chosen.id,
                    courseName = course?.courseName ?: "未知课程",
                    coursePosition = course?.coursePosition,
                    courseTeacher = course?.courseTeacher,
                    courseStartDate = course?.courseStartDate,
                    courseEndDate = course?.courseEndDate,
                    selectDate = chosen.selectDate,
                    category = course?.courseNewKind1?.kindName,
                    subCategory = course?.courseNewKind2?.kindName,
                    checkin = chosen.checkin ?: 0,
                    score = chosen.score,
                    pass = chosen.pass ?: 0,
                    canSign = canSign(signConfig, now),
                    canSignOut = canSignOut(signConfig, now),
                    signConfig = signConfig
            )
        }
    }

    /** 获取课程详情 */
    suspend fun getCourseDetail(username: String, courseId: Long): BykcCourseDetailDto {
        ensureBykcLogin(username)
        val client = getClient(username)
        val course = client.queryCourseById(courseId)
        val status = calculateCourseStatus(course)
        val signConfig = parseSignConfig(course.courseSignConfig)

        return BykcCourseDetailDto(
                id = course.id,
                courseName = course.courseName,
                coursePosition = course.coursePosition,
                courseContact = course.courseContact,
                courseContactMobile = course.courseContactMobile,
                courseTeacher = course.courseTeacher,
                courseStartDate = course.courseStartDate,
                courseEndDate = course.courseEndDate,
                courseSelectStartDate = course.courseSelectStartDate,
                courseSelectEndDate = course.courseSelectEndDate,
                courseCancelEndDate = course.courseCancelEndDate,
                courseMaxCount = course.courseMaxCount,
                courseCurrentCount = course.courseCurrentCount ?: 0,
                category = course.courseNewKind1?.kindName,
                subCategory = course.courseNewKind2?.kindName,
                status = status.displayName,
                selected = course.selected ?: false,
                courseDesc = course.courseDesc,
                signConfig = signConfig
        )
    }

    /** 签到 */
    suspend fun signIn(username: String, courseId: Long, lat: Double, lng: Double): Result<String> {
        return try {
            ensureBykcLogin(username)
            val client = getClient(username)
            client.signCourse(courseId, lat, lng, 1) // signType=1 签到
            log.info("User {} signed in for course {}", username, courseId)
            Result.success("签到成功")
        } catch (e: Exception) {
            log.error("User {} failed to sign in for course {}: {}", username, courseId, e.message)
            Result.failure(e)
        }
    }

    /** 签退 */
    suspend fun signOut(
            username: String,
            courseId: Long,
            lat: Double,
            lng: Double
    ): Result<String> {
        return try {
            ensureBykcLogin(username)
            val client = getClient(username)
            client.signCourse(courseId, lat, lng, 2) // signType=2 签退
            log.info("User {} signed out for course {}", username, courseId)
            Result.success("签退成功")
        } catch (e: Exception) {
            log.error("User {} failed to sign out for course {}: {}", username, courseId, e.message)
            Result.failure(e)
        }
    }

    /** 解析签到配置 */
    private fun parseSignConfig(configJson: String?): BykcSignConfigDto? {
        if (configJson.isNullOrBlank()) return null
        return try {
            val config = json.decodeFromString<BykcSignConfig>(configJson)
            BykcSignConfigDto(
                    signStartDate = config.signStartDate,
                    signEndDate = config.signEndDate,
                    signOutStartDate = config.signOutStartDate,
                    signOutEndDate = config.signOutEndDate,
                    signPoints =
                            config.signPointList.map { BykcSignPointDto(it.lat, it.lng, it.radius) }
            )
        } catch (e: Exception) {
            log.warn("Failed to parse sign config: {}", e.message)
            null
        }
    }

    /** 判断当前是否可签到 */
    private fun canSign(signConfig: BykcSignConfigDto?, now: LocalDateTime): Boolean {
        if (signConfig == null) return false
        val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
        return try {
            val start = signConfig.signStartDate?.let { LocalDateTime.parse(it, formatter) }
            val end = signConfig.signEndDate?.let { LocalDateTime.parse(it, formatter) }
            start != null && end != null && now.isAfter(start) && now.isBefore(end)
        } catch (e: Exception) {
            false
        }
    }

    /** 判断当前是否可签退 */
    private fun canSignOut(signConfig: BykcSignConfigDto?, now: LocalDateTime): Boolean {
        if (signConfig == null) return false
        val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
        return try {
            val start = signConfig.signOutStartDate?.let { LocalDateTime.parse(it, formatter) }
            val end = signConfig.signOutEndDate?.let { LocalDateTime.parse(it, formatter) }
            start != null && end != null && now.isAfter(start) && now.isBefore(end)
        } catch (e: Exception) {
            false
        }
    }

    /** 计算课程状态 */
    private fun calculateCourseStatus(course: BykcCourse): BykcCourseStatusEnum {
        val now = LocalDateTime.now()
        val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")

        return try {
            val courseStartDate = course.courseStartDate?.let { LocalDateTime.parse(it, formatter) }
            val selectStartDate =
                    course.courseSelectStartDate?.let { LocalDateTime.parse(it, formatter) }
            val selectEndDate =
                    course.courseSelectEndDate?.let { LocalDateTime.parse(it, formatter) }

            when {
                // 课程已开始 -> 过期
                courseStartDate != null && now.isAfter(courseStartDate) ->
                        BykcCourseStatusEnum.EXPIRED
                // 已选
                course.selected == true -> BykcCourseStatusEnum.SELECTED
                // 选课尚未开始 -> 预告
                selectStartDate != null && now.isBefore(selectStartDate) ->
                        BykcCourseStatusEnum.PREVIEW
                // 选课已结束
                selectEndDate != null && now.isAfter(selectEndDate) -> BykcCourseStatusEnum.ENDED
                // 人数已满
                course.courseCurrentCount != null &&
                        course.courseCurrentCount >= course.courseMaxCount ->
                        BykcCourseStatusEnum.FULL
                // 可选
                else -> BykcCourseStatusEnum.AVAILABLE
            }
        } catch (e: Exception) {
            log.warn("Failed to calculate status for course {}: {}", course.id, e.message)
            BykcCourseStatusEnum.AVAILABLE
        }
    }

    /** 清理用户的 BYKC 客户端缓存 */
    fun clearClientCache(username: String) {
        clientCache.remove(username)
        log.debug("Cleared BykcClient cache for user: {}", username)
    }

    /** 清理所有客户端缓存 */
    fun clearAllClientCache() {
        clientCache.clear()
        log.debug("Cleared all BykcClient caches")
    }
}

/** 全局 BykcService 单例 */
object GlobalBykcService {
    val instance: BykcService by lazy { BykcService() }
}
