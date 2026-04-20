package cn.edu.ubaa.bykc

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.model.dto.BykcCategoryStatisticsDto
import cn.edu.ubaa.model.dto.BykcChosenCourseDto
import cn.edu.ubaa.model.dto.BykcCourseCategory
import cn.edu.ubaa.model.dto.BykcCourseDetailDto
import cn.edu.ubaa.model.dto.BykcCourseDto
import cn.edu.ubaa.model.dto.BykcCoursePage
import cn.edu.ubaa.model.dto.BykcCourseStatus
import cn.edu.ubaa.model.dto.BykcCourseSubCategory
import cn.edu.ubaa.model.dto.BykcSignConfigDto
import cn.edu.ubaa.model.dto.BykcSignPointDto
import cn.edu.ubaa.model.dto.BykcStatisticsDto
import cn.edu.ubaa.utils.withUpstreamDeadline
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random
import kotlin.time.Clock
import kotlin.time.Duration.Companion.seconds
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

/**
 * 博雅课程业务服务类。 封装了复杂的业务逻辑，包括：
 * 1. 自动维护用户的博雅系统登录会话。
 * 2. 课程状态计算（可选、已满、结束、过期等）。
 * 3. 选课与退选流程处理。
 * 4. 签到逻辑，包括签到点地理位置随机生成（模拟真实坐标）。
 * 5. 课程统计信息的汇总与分类处理。
 */
class BykcService(
    private val sessionManager: SessionManager = GlobalSessionManager.instance,
    private val clientProvider: (String) -> BykcClient = ::BykcClient,
    private val nowProvider: () -> LocalDateTime = {
      Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
    },
) {
  private val log = LoggerFactory.getLogger(BykcService::class.java)
  private val json = Json { ignoreUnknownKeys = true }

  private data class CachedClient(
      val client: BykcClient,
      @Volatile var lastAccessAt: Long,
  )

  private data class AttendanceAvailability(
      val canSign: Boolean,
      val canSignOut: Boolean,
  )

  private val clientCache = ConcurrentHashMap<String, CachedClient>()

  /** 获取或创建用户专属的博雅客户端。 */
  private fun getClient(username: String): BykcClient {
    val now = System.currentTimeMillis()
    val cached =
        clientCache.compute(username) { _, existing ->
          existing?.also { it.lastAccessAt = now }
              ?: CachedClient(
                  clientProvider(username).also {
                    log.debug("Created new BykcClient for user: {}", username)
                  },
                  now,
              )
        }!!
    return cached.client
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
    return withBykcDeadline("博雅资料加载超时") {
      ensureBykcLogin(username)
      getClient(username).getUserProfile()
    }
  }

  /** 查询当前可选或已开始的博雅课程列表。 会自动计算每门课程的状态并进行分页。 */
  suspend fun getCourses(
      username: String,
      pageNumber: Int = 1,
      pageSize: Int = 20,
  ): BykcCoursePage {
    return withBykcDeadline("博雅课程列表加载超时") {
      ensureBykcLogin(username)
      val client = getClient(username)
      val result = client.queryStudentSemesterCourseByPage(pageNumber, pageSize)

      val courses =
          result.content.mapNotNull { course ->
            try {
              val status = calculateCourseStatus(course)
              if (status == BykcCourseStatus.EXPIRED || status == BykcCourseStatus.ENDED)
                  return@mapNotNull null

              course.toCourseDto(status)
            } catch (e: Exception) {
              null
            }
          }

      BykcCoursePage(courses, result.totalElements, result.totalPages, pageNumber, pageSize)
    }
  }

  /** 获取所有博雅课程（包括选课结束和已过期的）。 */
  suspend fun getAllCourses(username: String, pageNumber: Int, pageSize: Int): BykcCoursePage {
    return withBykcDeadline("博雅全部课程加载超时") {
      ensureBykcLogin(username)
      val client = getClient(username)
      val result = client.queryStudentSemesterCourseByPage(pageNumber, pageSize)

      val courses =
          result.content.map { course ->
            val status = calculateCourseStatus(course)
            course.toCourseDto(status)
          }
      BykcCoursePage(courses, result.totalElements, result.totalPages, pageNumber, pageSize)
    }
  }

  /** 选课。 */
  suspend fun selectCourse(username: String, courseId: Long): Result<String> {
    return try {
      ensureBykcLogin(username)
      getClient(username).choseCourse(courseId)
      Result.success("选课成功")
    } catch (e: Exception) {
      Result.failure(e)
    }
  }

  /** 退选。 */
  suspend fun deselectCourse(username: String, courseId: Long): Result<String> {
    return try {
      ensureBykcLogin(username)
      getClient(username).delChosenCourse(courseId)
      Result.success("退选成功")
    } catch (e: Exception) {
      Result.failure(e)
    }
  }

  /** 获取当前用户已报名并待修读或已完成的课程列表。 */
  suspend fun getChosenCourses(username: String): List<BykcChosenCourseDto> {
    return withBykcDeadline("博雅已选课程加载超时") {
      ensureBykcLogin(username)
      val client = getClient(username)
      val config = client.getAllConfig()
      val now = nowProvider()
      val semester = resolveCurrentSemester(config, now)
      val semesterStartDate = semester.semesterStartDate ?: throw BykcException("无法获取当前学期信息")
      val semesterEndDate = semester.semesterEndDate ?: throw BykcException("无法获取当前学期信息")

      val chosenCourses = client.queryChosenCourse(semesterStartDate, semesterEndDate)

      chosenCourses.map { chosen ->
        val course = chosen.courseInfo
        val signConfig = parseSignConfig(course?.courseSignConfig)
        val availability =
            resolveAttendanceAvailability(signConfig, chosen.checkin, chosen.pass, now)
        BykcChosenCourseDto(
            id = chosen.id,
            courseId = course?.id ?: 0L,
            courseName = course?.courseName ?: "未知课程",
            coursePosition = course?.coursePosition,
            courseTeacher = course?.courseTeacher,
            courseStartDate = course?.courseStartDate.toDtoLocalDateTime(),
            courseEndDate = course?.courseEndDate.toDtoLocalDateTime(),
            selectDate = chosen.selectDate.toDtoLocalDateTime(),
            courseCancelEndDate = course?.courseCancelEndDate.toDtoLocalDateTime(),
            category = BykcCourseCategory.fromDisplayName(course?.courseNewKind1?.kindName),
            subCategory = BykcCourseSubCategory.fromDisplayName(course?.courseNewKind2?.kindName),
            checkin = chosen.checkin ?: 0,
            score = chosen.score,
            pass = chosen.pass,
            canSign = availability.canSign,
            canSignOut = availability.canSignOut,
            signConfig = signConfig,
            courseSignType = course?.courseSignType,
            homework = chosen.homework,
            signInfo = chosen.signInfo,
        )
      }
    }
  }

  /** 获取博雅课程详情，包括状态和签到配置。 */
  suspend fun getCourseDetail(username: String, courseId: Long): BykcCourseDetailDto {
    return withBykcDeadline("博雅课程详情加载超时") {
      ensureBykcLogin(username)
      val client = getClient(username)
      val course = client.queryCourseById(courseId)
      val status = calculateCourseStatus(course)
      var signConfig = parseSignConfig(course.courseSignConfig)
      val now = nowProvider()

      var checkin: Int? = null
      var pass: Int? = null

      if (course.selected == true) {
        try {
          val chosen = findChosenCourseForCurrentSemester(client, courseId)
          if (signConfig == null) {
            signConfig = parseSignConfig(chosen?.courseInfo?.courseSignConfig)
          }
          checkin = chosen?.checkin
          pass = chosen?.pass
        } catch (_: Exception) {}
      }
      val availability = resolveAttendanceAvailability(signConfig, checkin, pass, now)

      course.toCourseDetailDto(
          status = status,
          signConfig = signConfig,
          checkin = checkin,
          pass = pass,
          availability = availability,
      )
    }
  }

  /** 签到。自动根据服务端配置的签到范围随机生成经纬度。 */
  suspend fun signIn(username: String, courseId: Long, lat: Double?, lng: Double?): Result<String> {
    return try {
      ensureBykcLogin(username)
      val client = getClient(username)
      val chosen = findChosenCourseForCurrentSemester(client, courseId)
      if (chosen == null) return Result.failure(BykcException("该课程未选，无法签到"))

      val signConfig =
          parseSignConfig(chosen.courseInfo?.courseSignConfig) ?: getSignConfig(client, courseId)
      val now = nowProvider()
      val availability = resolveAttendanceAvailability(signConfig, chosen.checkin, chosen.pass, now)
      if (!availability.canSign) {
        return Result.failure(
            BykcException(resolveSignInUnavailableReason(chosen.checkin, chosen.pass))
        )
      }

      val (finalLat, finalLng) = randomSignLocation(signConfig, lat, lng)
      client.signCourse(courseId, finalLat, finalLng, 1)
      Result.success("签到成功")
    } catch (e: Exception) {
      Result.failure(e)
    }
  }

  /** 签退。 */
  suspend fun signOut(
      username: String,
      courseId: Long,
      lat: Double?,
      lng: Double?,
  ): Result<String> {
    return try {
      ensureBykcLogin(username)
      val client = getClient(username)
      val chosen = findChosenCourseForCurrentSemester(client, courseId)
      if (chosen == null) return Result.failure(BykcException("该课程未选，无法签退"))

      val signConfig =
          parseSignConfig(chosen.courseInfo?.courseSignConfig) ?: getSignConfig(client, courseId)
      val now = nowProvider()
      val availability = resolveAttendanceAvailability(signConfig, chosen.checkin, chosen.pass, now)
      if (!availability.canSignOut) {
        return Result.failure(
            BykcException(resolveSignOutUnavailableReason(chosen.checkin, chosen.pass))
        )
      }

      val (finalLat, finalLng) = randomSignLocation(signConfig, lat, lng)
      client.signCourse(courseId, finalLat, finalLng, 2)
      Result.success("签退成功")
    } catch (e: Exception) {
      Result.failure(e)
    }
  }

  fun cleanupExpiredClients(maxIdleMillis: Long = 30 * 60 * 1000L): Int {
    val cutoff = System.currentTimeMillis() - maxIdleMillis
    var removed = 0
    for ((username, cached) in clientCache.entries.toList()) {
      if (cached.lastAccessAt >= cutoff) continue
      if (!clientCache.remove(username, cached)) continue
      cached.client.close()
      removed++
    }
    return removed
  }

  fun cacheSize(): Int = clientCache.size

  fun clearCache() {
    clientCache.values.forEach { it.client.close() }
    clientCache.clear()
  }

  internal fun cacheClientForTesting(
      username: String,
      client: BykcClient,
      lastAccessAt: Long = System.currentTimeMillis(),
  ) {
    clientCache[username] = CachedClient(client, lastAccessAt)
  }

  internal fun cachedClientForTesting(username: String): BykcClient? = clientCache[username]?.client

  private suspend fun findChosenCourseForCurrentSemester(
      client: BykcClient,
      courseId: Long,
  ): BykcChosenCourse? {
    val config = client.getAllConfig()
    val semester = resolveCurrentSemester(config, nowProvider())
    val semesterStartDate = semester.semesterStartDate ?: throw BykcException("无法获取当前学期信息")
    val semesterEndDate = semester.semesterEndDate ?: throw BykcException("无法获取当前学期信息")

    return client.queryChosenCourse(semesterStartDate, semesterEndDate).find {
      it.courseInfo?.id == courseId
    }
  }

  private suspend fun getSignConfig(client: BykcClient, courseId: Long): BykcSignConfigDto? {
    return try {
      parseSignConfig(client.queryCourseById(courseId).courseSignConfig)
    } catch (_: Exception) {
      null
    }
  }

  private fun parseSignConfig(configJson: String?): BykcSignConfigDto? {
    if (configJson.isNullOrBlank()) return null
    return try {
      val config = json.decodeFromString<BykcSignConfig>(configJson)
      BykcSignConfigDto(
          signStartDate = config.signStartDate.toDtoLocalDateTime(),
          signEndDate = config.signEndDate.toDtoLocalDateTime(),
          signOutStartDate = config.signOutStartDate.toDtoLocalDateTime(),
          signOutEndDate = config.signOutEndDate.toDtoLocalDateTime(),
          signPoints = config.signPointList.map { BykcSignPointDto(it.lat, it.lng, it.radius) },
      )
    } catch (_: Exception) {
      null
    }
  }

  private fun BykcRawCourse.toCourseDto(status: BykcCourseStatus): BykcCourseDto {
    // BYKC 的 `ALL` / `全部校区` 在课程列表里更接近“发布时未指定开课校区”，
    // 这里统一折叠为“未指定校区”，避免前端把它误解成真实的跨校区开课标签。
    val audienceCampuses = courseCampusList.toAudienceCampusLabels(courseCampus)
    return BykcCourseDto(
        id = id,
        courseName = courseName.trim(),
        coursePosition = coursePosition.normalizedOrNull(),
        courseTeacher = courseTeacher.normalizedOrNull(),
        courseStartDate = courseStartDate.toDtoLocalDateTime(),
        courseEndDate = courseEndDate.toDtoLocalDateTime(),
        courseSelectStartDate = courseSelectStartDate.toDtoLocalDateTime(),
        courseSelectEndDate = courseSelectEndDate.toDtoLocalDateTime(),
        courseCancelEndDate = courseCancelEndDate.toDtoLocalDateTime(),
        courseMaxCount = courseMaxCount,
        courseCurrentCount = courseCurrentCount,
        category = BykcCourseCategory.fromDisplayName(courseNewKind1?.kindName.normalizedOrNull()),
        subCategory =
            BykcCourseSubCategory.fromDisplayName(courseNewKind2?.kindName.normalizedOrNull()),
        audienceCampuses = audienceCampuses,
        hasSignPoints = parseSignConfig(courseSignConfig)?.signPoints?.isNotEmpty() == true,
        status = status,
        selected = selected == true,
    )
  }

  private fun BykcRawCourse.toCourseDetailDto(
      status: BykcCourseStatus,
      signConfig: BykcSignConfigDto?,
      checkin: Int?,
      pass: Int?,
      availability: AttendanceAvailability,
  ): BykcCourseDetailDto {
    val audienceCampuses = courseCampusList.toAudienceCampusLabels(courseCampus)
    return BykcCourseDetailDto(
        id = id,
        courseName = courseName.trim(),
        coursePosition = coursePosition.normalizedOrNull(),
        courseTeacher = courseTeacher.normalizedOrNull(),
        courseStartDate = courseStartDate.toDtoLocalDateTime(),
        courseEndDate = courseEndDate.toDtoLocalDateTime(),
        courseSelectStartDate = courseSelectStartDate.toDtoLocalDateTime(),
        courseSelectEndDate = courseSelectEndDate.toDtoLocalDateTime(),
        courseCancelEndDate = courseCancelEndDate.toDtoLocalDateTime(),
        courseMaxCount = courseMaxCount,
        courseCurrentCount = courseCurrentCount,
        category = BykcCourseCategory.fromDisplayName(courseNewKind1?.kindName.normalizedOrNull()),
        subCategory =
            BykcCourseSubCategory.fromDisplayName(courseNewKind2?.kindName.normalizedOrNull()),
        hasSignPoints = signConfig?.signPoints?.isNotEmpty() == true,
        status = status,
        selected = selected == true,
        courseContact = courseContact.normalizedOrNull(),
        courseContactMobile = courseContactMobile.normalizedOrNull(),
        organizerCollegeName = courseBelongCollege?.collegeName.normalizedOrNull(),
        courseDesc = courseDesc.normalizedOrNull(),
        audienceCampuses = audienceCampuses,
        audienceColleges = courseCollegeList.normalizedTextList(),
        audienceTerms = courseTermList.normalizedTextList(),
        audienceGroups = courseGroupList.normalizedTextList(),
        signConfig = signConfig,
        checkin = checkin,
        pass = pass,
        canSign = availability.canSign,
        canSignOut = availability.canSignOut,
    )
  }

  private fun String?.normalizedOrNull(): String? = this?.trim()?.takeIf { it.isNotEmpty() }

  private fun List<String>?.normalizedTextList(): List<String> =
      this.orEmpty().mapNotNull { it.normalizedOrNull() }

  private fun List<String>?.toAudienceCampusLabels(rawCampus: String?): List<String> {
    val normalizedLabels = normalizedTextList().map { if (it == "全部校区") "未指定校区" else it }.distinct()
    if (normalizedLabels.isNotEmpty()) return normalizedLabels
    return when (rawCampus.normalizedOrNull()) {
      "ALL" -> listOf("未指定校区")
      else -> emptyList()
    }
  }

  private fun String?.toDtoLocalDateTime(): LocalDateTime? {
    val normalized = normalizedOrNull() ?: return null
    return runCatching { LocalDateTime.parse(normalized.replace(" ", "T")) }.getOrNull()
  }

  private fun canSign(signConfig: BykcSignConfigDto?, now: LocalDateTime): Boolean {
    return isWithinWindow(signConfig?.signStartDate, signConfig?.signEndDate, now)
  }

  private fun canSignOut(signConfig: BykcSignConfigDto?, now: LocalDateTime): Boolean {
    return isWithinWindow(signConfig?.signOutStartDate, signConfig?.signOutEndDate, now)
  }

  private fun resolveCurrentSemester(
      config: BykcAllConfig,
      now: LocalDateTime,
  ): BykcSemester {
    val semesters = config.semester
    if (semesters.isEmpty()) throw BykcException("无法获取当前学期信息")

    semesters
        .firstOrNull { semester ->
          isWithinWindow(semester.semesterStartDate, semester.semesterEndDate, now)
        }
        ?.let {
          return it
        }

    log.warn(
        "Unable to match BYKC current semester by time window, falling back to latest semester"
    )
    return semesters.maxByOrNull {
      parseDateTime(it.semesterEndDate) ?: LocalDateTime.parse("1970-01-01T00:00:00")
    }
        ?: throw BykcException("无法获取当前学期信息")
  }

  /** 随机坐标生成：在合法的签到半径内随机化，提高安全性。 */
  private fun randomSignLocation(
      signConfig: BykcSignConfigDto?,
      fallbackLat: Double?,
      fallbackLng: Double?,
  ): Pair<Double, Double> {
    val point = signConfig?.signPoints?.randomOrNull()
    if (point != null && point.radius > 0.0) {
      val dist = point.radius * sqrt(Random.nextDouble())
      val angle = Random.nextDouble() * 2 * Math.PI
      return destinationPoint(point.lat, point.lng, dist, angle)
    }
    if (fallbackLat != null && fallbackLng != null) return fallbackLat to fallbackLng
    throw BykcException("未提供签到坐标且后端未返回签到范围")
  }

  private fun destinationPoint(
      lat: Double,
      lng: Double,
      dist: Double,
      angle: Double,
  ): Pair<Double, Double> {
    val r = dist / 6_371_000.0
    val lr = Math.toRadians(lat)
    val gr = Math.toRadians(lng)
    val dLat = asin(sin(lr) * cos(r) + cos(lr) * sin(r) * cos(angle))
    val dLng = gr + atan2(sin(angle) * sin(r) * cos(lr), cos(r) - sin(lr) * sin(dLat))
    return Math.toDegrees(dLat) to Math.toDegrees(dLng)
  }

  /** 根据课程时间配置计算课程状态。 */
  private fun calculateCourseStatus(course: BykcRawCourse): BykcCourseStatus {
    val now = nowProvider()
    return try {
      val cs = parseDateTime(course.courseStartDate)
      val ss = parseDateTime(course.courseSelectStartDate)
      val se = parseDateTime(course.courseSelectEndDate)
      when {
        cs != null && now > cs -> BykcCourseStatus.EXPIRED
        course.selected == true -> BykcCourseStatus.SELECTED
        se != null && now > se -> BykcCourseStatus.ENDED
        course.courseCurrentCount != null && course.courseCurrentCount >= course.courseMaxCount ->
            BykcCourseStatus.FULL
        ss != null && now < ss -> BykcCourseStatus.PREVIEW
        else -> BykcCourseStatus.AVAILABLE
      }
    } catch (_: Exception) {
      BykcCourseStatus.AVAILABLE
    }
  }

  private fun resolveAttendanceAvailability(
      signConfig: BykcSignConfigDto?,
      checkin: Int?,
      pass: Int?,
      now: LocalDateTime,
  ): AttendanceAvailability {
    val canSign = pass != 1 && isUnsignedCheckin(checkin) && canSign(signConfig, now)
    val canSignOut = pass != 1 && isEligibleForSignOut(checkin) && canSignOut(signConfig, now)
    return AttendanceAvailability(canSign = canSign, canSignOut = canSignOut)
  }

  private fun resolveSignInUnavailableReason(checkin: Int?, pass: Int?): String =
      when {
        pass == 1 -> "课程已考核完成，无需签到"
        !isUnsignedCheckin(checkin) -> "当前考勤状态不可签到"
        else -> "当前不在签到时间窗口"
      }

  private fun resolveSignOutUnavailableReason(checkin: Int?, pass: Int?): String =
      when {
        pass == 1 -> "课程已考核完成，无需签退"
        !isEligibleForSignOut(checkin) -> "当前考勤状态不可签退"
        else -> "当前不在签退时间窗口"
      }

  private fun isUnsignedCheckin(checkin: Int?): Boolean = checkin == null || checkin == 0

  private fun isEligibleForSignOut(checkin: Int?): Boolean =
      isUnsignedCheckin(checkin) || isSignedAwaitingSignOut(checkin)

  private fun isSignedAwaitingSignOut(checkin: Int?): Boolean = checkin == 5 || checkin == 6

  private fun isWithinWindow(
      startDate: LocalDateTime?,
      endDate: LocalDateTime?,
      now: LocalDateTime,
  ): Boolean {
    val start = startDate ?: return false
    val end = endDate ?: return false
    return now >= start && now <= end
  }

  private fun isWithinWindow(
      startDate: String?,
      endDate: String?,
      now: LocalDateTime,
  ): Boolean {
    val start = parseDateTime(startDate) ?: return false
    val end = parseDateTime(endDate) ?: return false
    return now >= start && now <= end
  }

  private fun parseDateTime(dateTime: String?): LocalDateTime? {
    return dateTime.toDtoLocalDateTime()
  }

  /** 汇总修读统计。 */
  suspend fun getStatistics(username: String): BykcStatisticsDto {
    return withBykcDeadline("博雅统计加载超时") {
      ensureBykcLogin(username)
      val statsData = getClient(username).queryStatisticByUserId()
      val cats = mutableListOf<BykcCategoryStatisticsDto>()
      statsData.statistical.forEach { (catKey, subMap) ->
        val catName = catKey.substringAfter("|")
        subMap.forEach { (subKey, stats) ->
          cats.add(
              BykcCategoryStatisticsDto(
                  catName,
                  subKey.substringAfter("|"),
                  stats.assessmentCount,
                  stats.completeAssessmentCount,
                  stats.completeAssessmentCount >= stats.assessmentCount,
              )
          )
        }
      }
      BykcStatisticsDto(statsData.validCount, cats)
    }
  }

  private suspend fun <T> withBykcDeadline(message: String, block: suspend () -> T): T {
    return withUpstreamDeadline(9.seconds, message, "bykc_timeout", block)
  }
}

/** 全局博雅服务单例。 */
object GlobalBykcService {
  val instance: BykcService by lazy { BykcService() }
}
