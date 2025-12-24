package cn.edu.ubaa.bykc

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.model.dto.BykcCategoryStatisticsDto
import cn.edu.ubaa.model.dto.BykcChosenCourseDto
import cn.edu.ubaa.model.dto.BykcCourseDetailDto
import cn.edu.ubaa.model.dto.BykcCourseDto
import cn.edu.ubaa.model.dto.BykcCoursePage
import cn.edu.ubaa.model.dto.BykcSignConfigDto
import cn.edu.ubaa.model.dto.BykcSignPointDto
import cn.edu.ubaa.model.dto.BykcStatisticsDto
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

/** 博雅课程服务，封装 BykcClient，提供课程、选课、签到等业务逻辑 */
class BykcService(private val sessionManager: SessionManager = GlobalSessionManager.instance) {
    private val log = LoggerFactory.getLogger(BykcService::class.java)
    private val json = Json { ignoreUnknownKeys = true }

    // 缓存用户 BykcClient，提升复用
    private val clientCache = mutableMapOf<String, BykcClient>()

    /** 获取或创建用户 BykcClient */
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

    /** 获取用户博雅课程信息 */
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
     * @return 课程分页结果（带状态计算）
     */
    suspend fun getCourses(
            username: String,
            pageNumber: Int = 1,
            pageSize: Int = 20
    ): BykcCoursePage {
        ensureBykcLogin(username)
        val client = getClient(username)
        val result = client.queryStudentSemesterCourseByPage(pageNumber, pageSize)

        val courses =
                result.content.mapNotNull { course ->
                    try {
                        val status = calculateCourseStatus(course)
                        // 过滤掉已过期和已结束的课程（可选）
                        if (status == BykcCourseStatusEnum.EXPIRED ||
                                        status == BykcCourseStatusEnum.ENDED
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

        return BykcCoursePage(
                courses = courses,
                totalElements = result.totalElements,
                totalPages = result.totalPages,
                currentPage = pageNumber,
                pageSize = pageSize
        )
    }

    /** 获取所有课程（包括已过期的） */
    suspend fun getAllCourses(
            username: String,
            pageNumber: Int = 1,
            pageSize: Int = 20
    ): BykcCoursePage {
        ensureBykcLogin(username)
        val client = getClient(username)
        val result = client.queryStudentSemesterCourseByPage(pageNumber, pageSize)

        val courses =
                result.content.map { course ->
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

        return BykcCoursePage(
                courses = courses,
                totalElements = result.totalElements,
                totalPages = result.totalPages,
                currentPage = pageNumber,
                pageSize = pageSize
        )
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
                    courseId = course?.id ?: 0L, // 课程本身的 ID
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
                    pass = chosen.pass,
                    canSign = canSign(signConfig, now),
                    canSignOut = canSignOut(signConfig, now),
                    signConfig = signConfig,
                    courseSignType = course?.courseSignType,
                    homework = chosen.homework,
                    homeworkAttachmentName = chosen.homeworkAttachmentName,
                    homeworkAttachmentPath = chosen.homeworkAttachmentPath,
                    signInfo = chosen.signInfo
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

        var checkin: Int? = null
        var pass: Int? = null

        if (course.selected == true) {
            // 已选课程尝试从 queryChosenCourse 结果获取状态
            // 需复用 queryChosenCourse 的日期范围逻辑，后续应优化为缓存查询
            try {
                // 暂需全量拉取列表
                // 依赖 getChosenCourses 中计算好的日期范围
                val config = client.getAllConfig()
                val semester = config.semester.firstOrNull()
                if (semester?.semesterStartDate != null && semester.semesterEndDate != null) {
                    val chosenList =
                            client.queryChosenCourse(
                                    semester.semesterStartDate,
                                    semester.semesterEndDate
                            )
                    val chosen = chosenList.find { it.courseInfo?.id == courseId }
                    if (chosen != null) {
                        checkin = chosen.checkin
                        pass = chosen.pass
                    }
                }
            } catch (e: Exception) {
                log.warn("Failed to fetch chosen status for course detail: {}", e.message)
            }
        }

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
                signConfig = signConfig,
                checkin = checkin,
                pass = pass
        )
    }

    /** 签到 */
    suspend fun signIn(
            username: String,
            courseId: Long,
            lat: Double? = null,
            lng: Double? = null
    ): Result<String> {
        return try {
            ensureBykcLogin(username)
            val client = getClient(username)
            val signConfig = getSignConfig(client, courseId)
            val now = LocalDateTime.now()
            if (!canSign(signConfig, now)) {
                return Result.failure(BykcException("当前不在签到时间窗口"))
            }

            val (finalLat, finalLng) = randomSignLocation(signConfig, lat, lng)
            client.signCourse(courseId, finalLat, finalLng, 1) // signType=1 签到
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
            lat: Double? = null,
            lng: Double? = null
    ): Result<String> {
        return try {
            ensureBykcLogin(username)
            val client = getClient(username)
            val signConfig = getSignConfig(client, courseId)
            val now = LocalDateTime.now()
            if (!canSignOut(signConfig, now)) {
                return Result.failure(BykcException("当前不在签退时间窗口"))
            }

            val (finalLat, finalLng) = randomSignLocation(signConfig, lat, lng)
            client.signCourse(courseId, finalLat, finalLng, 2) // signType=2 签退
            log.info("User {} signed out for course {}", username, courseId)
            Result.success("签退成功")
        } catch (e: Exception) {
            log.error("User {} failed to sign out for course {}: {}", username, courseId, e.message)
            Result.failure(e)
        }
    }

    /** 获取课程的签到配置（如果解析失败返回 null） */
    private suspend fun getSignConfig(client: BykcClient, courseId: Long): BykcSignConfigDto? {
        return try {
            val course = client.queryCourseById(courseId)
            parseSignConfig(course.courseSignConfig)
        } catch (e: Exception) {
            log.warn("Failed to load sign config for course {}: {}", courseId, e.message)
            null
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

    /** 在指定签到点半径内随机生成坐标；若没有配置则使用客户端传入的坐标 */
    private fun randomSignLocation(
            signConfig: BykcSignConfigDto?,
            fallbackLat: Double?,
            fallbackLng: Double?,
            random: Random = Random
    ): Pair<Double, Double> {
        val point = signConfig?.signPoints?.takeIf { it.isNotEmpty() }?.random(random)
        if (point != null && point.radius > 0.0) {
            val distance = point.radius * sqrt(random.nextDouble()) // 在圆内均匀分布
            val angle = random.nextDouble() * 2 * Math.PI
            return destinationPoint(point.lat, point.lng, distance, angle)
        }

        if (fallbackLat != null && fallbackLng != null) {
            return fallbackLat to fallbackLng
        }

        throw BykcException("未提供签到坐标且后端未返回签到范围")
    }

    /** 依据距离与方位角计算目标坐标 */
    private fun destinationPoint(
            lat: Double,
            lng: Double,
            distanceMeters: Double,
            bearingRad: Double
    ): Pair<Double, Double> {
        val angularDistance = distanceMeters / EARTH_RADIUS_METERS
        val latRad = Math.toRadians(lat)
        val lngRad = Math.toRadians(lng)

        val destLat =
                asin(
                        sin(latRad) * cos(angularDistance) +
                                cos(latRad) * sin(angularDistance) * cos(bearingRad)
                )
        val destLng =
                lngRad +
                        atan2(
                                sin(bearingRad) * sin(angularDistance) * cos(latRad),
                                cos(angularDistance) - sin(latRad) * sin(destLat)
                        )

        return Math.toDegrees(destLat) to Math.toDegrees(destLng)
    }

    companion object {
        private const val EARTH_RADIUS_METERS = 6_371_000.0
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

    /** 获取课程统计信息 */
    suspend fun getStatistics(username: String): BykcStatisticsDto {
        ensureBykcLogin(username)
        val client = getClient(username)
        val statsData = client.queryStatisticByUserId()

        val categories = mutableListOf<BykcCategoryStatisticsDto>()

        statsData.statistical.forEach { (categoryKey, subMap) ->
            // categoryKey format: "60|博雅课程"
            val categoryName = categoryKey.substringAfter("|")

            subMap.forEach { (subKey, stats) ->
                // subKey format: "55|德育"
                val subCategoryName = subKey.substringAfter("|")

                categories.add(
                        BykcCategoryStatisticsDto(
                                categoryName = categoryName,
                                subCategoryName = subCategoryName,
                                requiredCount = stats.assessmentCount,
                                passedCount = stats.completeAssessmentCount,
                                isQualified = stats.completeAssessmentCount >= stats.assessmentCount
                        )
                )
            }
        }

        return BykcStatisticsDto(totalValidCount = statsData.validCount, categories = categories)
    }
}

/** 全局 BykcService 单例 */
object GlobalBykcService {
    val instance: BykcService by lazy { BykcService() }
}
