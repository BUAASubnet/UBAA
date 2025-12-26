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

/**
 * 博雅课程业务服务类。
 * 封装了复杂的业务逻辑，包括：
 * 1. 自动维护用户的博雅系统登录会话。
 * 2. 课程状态计算（可选、已满、结束、过期等）。
 * 3. 选课与退选流程处理。
 * 4. 签到逻辑，包括签到点地理位置随机生成（模拟真实坐标）。
 * 5. 课程统计信息的汇总与分类处理。
 */
class BykcService(private val sessionManager: SessionManager = GlobalSessionManager.instance) {
    private val log = LoggerFactory.getLogger(BykcService::class.java)
    private val json = Json { ignoreUnknownKeys = true }

    // 缓存用户 BykcClient，提升复用
    private val clientCache = mutableMapOf<String, BykcClient>()

    /** 获取或创建用户专属的博雅客户端。 */
    private fun getClient(username: String): BykcClient {
        return clientCache.getOrPut(username) {
            BykcClient(username).also { log.debug("Created new BykcClient for user: {}", username) }
        }
    }

    /** 确保用户已在博雅系统中完成登录。 */
    suspend fun ensureBykcLogin(username: String): Boolean {
        val client = getClient(username)
        return try {
            client.login()
            true
        } catch (e: Exception) {
            log.error("BYKC login failed for user: {}", username, e)
            false
        }
    }

    /** 获取用户的博雅个人资料。 */
    suspend fun getUserProfile(username: String): BykcUserProfile {
        ensureBykcLogin(username)
        return getClient(username).getUserProfile()
    }

    /**
     * 查询当前可选或已开始的博雅课程列表。
     * 会自动计算每门课程的状态并进行分页。
     */
    suspend fun getCourses(
            username: String,
            pageNumber: Int = 1,
            pageSize: Int = 20
    ): BykcCoursePage {
        ensureBykcLogin(username)
        val client = getClient(username)
        val result = client.queryStudentSemesterCourseByPage(pageNumber, pageSize)

        val courses = result.content.mapNotNull { course ->
            try {
                val status = calculateCourseStatus(course)
                // 默认过滤掉已过期的课程
                if (status == BykcCourseStatusEnum.EXPIRED || status == BykcCourseStatusEnum.ENDED) return@mapNotNull null

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
            } catch (e: Exception) { null }
        }

        return BykcCoursePage(courses, result.totalElements, result.totalPages, pageNumber, pageSize)
    }

    /** 获取所有博雅课程（包括已结束和过期的）。 */
    suspend fun getAllCourses(username: String, pageNumber: Int, pageSize: Int): BykcCoursePage {
        ensureBykcLogin(username)
        val client = getClient(username)
        val result = client.queryStudentSemesterCourseByPage(pageNumber, pageSize)

        val courses = result.content.map { course ->
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
        return BykcCoursePage(courses, result.totalElements, result.totalPages, pageNumber, pageSize)
    }

    /** 选课。 */
    suspend fun selectCourse(username: String, courseId: Long): Result<String> {
        return try {
            ensureBykcLogin(username)
            getClient(username).choseCourse(courseId)
            Result.success("选课成功")
        } catch (e: Exception) { Result.failure(e) }
    }

    /** 退选。 */
    suspend fun deselectCourse(username: String, courseId: Long): Result<String> {
        return try {
            ensureBykcLogin(username)
            getClient(username).delChosenCourse(courseId)
            Result.success("退选成功")
        } catch (e: Exception) { Result.failure(e) }
    }

    /** 获取当前用户已报名并待修读或已完成的课程列表。 */
    suspend fun getChosenCourses(username: String): List<BykcChosenCourseDto> {
        ensureBykcLogin(username)
        val client = getClient(username)
        val config = client.getAllConfig()
        val semester = config.semester.firstOrNull() ?: throw BykcException("无法获取当前学期信息")
        
        val chosenCourses = client.queryChosenCourse(semester.semesterStartDate!!, semester.semesterEndDate!!)
        val now = LocalDateTime.now()

        return chosenCourses.map { chosen ->
            val course = chosen.courseInfo
            val signConfig = parseSignConfig(course?.courseSignConfig)
            BykcChosenCourseDto(
                    id = chosen.id,
                    courseId = course?.id ?: 0L,
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
                    signInfo = chosen.signInfo
            )
        }
    }

    /** 获取博雅课程详情，包括状态和签到配置。 */
    suspend fun getCourseDetail(username: String, courseId: Long): BykcCourseDetailDto {
        ensureBykcLogin(username)
        val client = getClient(username)
        val course = client.queryCourseById(courseId)
        val status = calculateCourseStatus(course)
        val signConfig = parseSignConfig(course.courseSignConfig)

        var checkin: Int? = null
        var pass: Int? = null

        if (course.selected == true) {
            try {
                val config = client.getAllConfig()
                val semester = config.semester.firstOrNull()
                if (semester?.semesterStartDate != null && semester.semesterEndDate != null) {
                    val chosen = client.queryChosenCourse(semester.semesterStartDate, semester.semesterEndDate).find { it.courseInfo?.id == courseId }
                    checkin = chosen?.checkin
                    pass = chosen?.pass
                }
            } catch (_: Exception) {}
        }

        return BykcCourseDetailDto(
                id = course.id,
                courseName = course.courseName,
                coursePosition = course.coursePosition,
                courseTeacher = course.courseTeacher,
                courseStartDate = course.courseStartDate,
                courseEndDate = course.courseEndDate,
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

    /** 签到。自动根据服务端配置的签到范围随机生成经纬度。 */
    suspend fun signIn(username: String, courseId: Long, lat: Double?, lng: Double?): Result<String> {
        return try {
            ensureBykcLogin(username)
            val client = getClient(username)
            val signConfig = getSignConfig(client, courseId)
            if (!canSign(signConfig, LocalDateTime.now())) return Result.failure(BykcException("当前不在签到时间窗口"))

            val (finalLat, finalLng) = randomSignLocation(signConfig, lat, lng)
            client.signCourse(courseId, finalLat, finalLng, 1)
            Result.success("签到成功")
        } catch (e: Exception) { Result.failure(e) }
    }

    /** 签退。 */
    suspend fun signOut(username: String, courseId: Long, lat: Double?, lng: Double?): Result<String> {
        return try {
            ensureBykcLogin(username)
            val client = getClient(username)
            val signConfig = getSignConfig(client, courseId)
            if (!canSignOut(signConfig, LocalDateTime.now())) return Result.failure(BykcException("当前不在签退时间窗口"))

            val (finalLat, finalLng) = randomSignLocation(signConfig, lat, lng)
            client.signCourse(courseId, finalLat, finalLng, 2)
            Result.success("签退成功")
        } catch (e: Exception) { Result.failure(e) }
    }

    private suspend fun getSignConfig(client: BykcClient, courseId: Long): BykcSignConfigDto? {
        return try { parseSignConfig(client.queryCourseById(courseId).courseSignConfig) } catch (_: Exception) { null }
    }

    private fun parseSignConfig(configJson: String?): BykcSignConfigDto? {
        if (configJson.isNullOrBlank()) return null
        return try {
            val config = json.decodeFromString<BykcSignConfig>(configJson)
            BykcSignConfigDto(
                    signStartDate = config.signStartDate,
                    signEndDate = config.signEndDate,
                    signOutStartDate = config.signOutStartDate,
                    signOutEndDate = config.signOutEndDate,
                    signPoints = config.signPointList.map { BykcSignPointDto(it.lat, it.lng, it.radius) }
            )
        } catch (_: Exception) { null }
    }

    private fun canSign(signConfig: BykcSignConfigDto?, now: LocalDateTime): Boolean {
        if (signConfig == null) return false
        val f = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
        return try {
            val s = signConfig.signStartDate?.let { LocalDateTime.parse(it, f) }
            val e = signConfig.signEndDate?.let { LocalDateTime.parse(it, f) }
            s != null && e != null && now.isAfter(s) && now.isBefore(e)
        } catch (_: Exception) { false }
    }

    private fun canSignOut(signConfig: BykcSignConfigDto?, now: LocalDateTime): Boolean {
        if (signConfig == null) return false
        val f = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
        return try {
            val s = signConfig.signOutStartDate?.let { LocalDateTime.parse(it, f) }
            val e = signConfig.signOutEndDate?.let { LocalDateTime.parse(it, f) }
            s != null && e != null && now.isAfter(s) && now.isBefore(e)
        } catch (_: Exception) { false }
    }

    /** 随机坐标生成：在合法的签到半径内随机化，提高安全性。 */
    private fun randomSignLocation(signConfig: BykcSignConfigDto?, fallbackLat: Double?, fallbackLng: Double?): Pair<Double, Double> {
        val point = signConfig?.signPoints?.randomOrNull()
        if (point != null && point.radius > 0.0) {
            val dist = point.radius * sqrt(Random.nextDouble())
            val angle = Random.nextDouble() * 2 * Math.PI
            return destinationPoint(point.lat, point.lng, dist, angle)
        }
        if (fallbackLat != null && fallbackLng != null) return fallbackLat to fallbackLng
        throw BykcException("未提供签到坐标且后端未返回签到范围")
    }

    private fun destinationPoint(lat: Double, lng: Double, dist: Double, angle: Double): Pair<Double, Double> {
        val r = dist / 6_371_000.0
        val lr = Math.toRadians(lat); val gr = Math.toRadians(lng)
        val dLat = asin(sin(lr) * cos(r) + cos(lr) * sin(r) * cos(angle))
        val dLng = gr + atan2(sin(angle) * sin(r) * cos(lr), cos(r) - sin(lr) * sin(dLat))
        return Math.toDegrees(dLat) to Math.toDegrees(dLng)
    }

    /** 根据课程时间配置计算课程状态。 */
    private fun calculateCourseStatus(course: BykcCourse): BykcCourseStatusEnum {
        val now = LocalDateTime.now(); val f = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
        return try {
            val cs = course.courseStartDate?.let { LocalDateTime.parse(it, f) }
            val ss = course.courseSelectStartDate?.let { LocalDateTime.parse(it, f) }
            val se = course.courseSelectEndDate?.let { LocalDateTime.parse(it, f) }
            when {
                cs != null && now.isAfter(cs) -> BykcCourseStatusEnum.EXPIRED
                course.selected == true -> BykcCourseStatusEnum.SELECTED
                ss != null && now.isBefore(ss) -> BykcCourseStatusEnum.PREVIEW
                se != null && now.isAfter(se) -> BykcCourseStatusEnum.ENDED
                course.courseCurrentCount != null && course.courseCurrentCount >= course.courseMaxCount -> BykcCourseStatusEnum.FULL
                else -> BykcCourseStatusEnum.AVAILABLE
            }
        } catch (_: Exception) { BykcCourseStatusEnum.AVAILABLE }
    }

    /** 汇总修读统计。 */
    suspend fun getStatistics(username: String): BykcStatisticsDto {
        ensureBykcLogin(username)
        val statsData = getClient(username).queryStatisticByUserId()
        val cats = mutableListOf<BykcCategoryStatisticsDto>()
        statsData.statistical.forEach { (catKey, subMap) ->
            val catName = catKey.substringAfter("|")
            subMap.forEach { (subKey, stats) ->
                cats.add(BykcCategoryStatisticsDto(catName, subKey.substringAfter("|"), stats.assessmentCount, stats.completeAssessmentCount, stats.completeAssessmentCount >= stats.assessmentCount))
            }
        }
        return BykcStatisticsDto(statsData.validCount, cats)
    }
}

/** 全局博雅服务单例。 */
object GlobalBykcService {
    val instance: BykcService by lazy { BykcService() }
}