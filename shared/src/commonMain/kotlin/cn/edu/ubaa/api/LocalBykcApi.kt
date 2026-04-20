package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.BykcCategoryStatisticsDto
import cn.edu.ubaa.model.dto.BykcChosenCourseDto
import cn.edu.ubaa.model.dto.BykcCourseCategory
import cn.edu.ubaa.model.dto.BykcCourseDetailDto
import cn.edu.ubaa.model.dto.BykcCourseDto
import cn.edu.ubaa.model.dto.BykcCourseStatus
import cn.edu.ubaa.model.dto.BykcCourseSubCategory
import cn.edu.ubaa.model.dto.BykcCoursesResponse
import cn.edu.ubaa.model.dto.BykcSignConfigDto
import cn.edu.ubaa.model.dto.BykcSignPointDto
import cn.edu.ubaa.model.dto.BykcStatisticsDto
import cn.edu.ubaa.model.dto.BykcSuccessResponse
import cn.edu.ubaa.model.dto.BykcUserProfileDto
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import kotlin.math.PI
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random
import kotlin.time.Clock
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

internal class LocalBykcApiBackend(
    private val nowProvider: () -> LocalDateTime = {
      Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
    },
) : BykcApiBackend {
  private val clientMutex = Mutex()
  private val clientCache = mutableMapOf<String, LocalBykcClient>()
  private val json = Json { ignoreUnknownKeys = true }

  override suspend fun getProfile(): Result<BykcUserProfileDto> =
      execute("博雅资料加载失败，请稍后重试") { _, client ->
        client.login()
        client.getUserProfile().toDto()
      }

  override suspend fun getCourses(
      page: Int,
      size: Int,
      all: Boolean,
  ): Result<BykcCoursesResponse> =
      execute("博雅课程列表加载失败，请稍后重试") { _, client ->
        client.login()
        val result = client.queryStudentSemesterCourseByPage(page, size)
        val courses =
            result.content.mapNotNull { course ->
              val status = calculateCourseStatus(course, nowProvider())
              if (
                  !all && (status == BykcCourseStatus.EXPIRED || status == BykcCourseStatus.ENDED)
              ) {
                null
              } else {
                course.toCourseDto(status)
              }
            }
        BykcCoursesResponse(
            courses = courses,
            total = result.totalElements,
            totalPages = result.totalPages,
            currentPage = page,
            pageSize = size,
        )
      }

  override suspend fun getCourseDetail(courseId: Long): Result<BykcCourseDetailDto> =
      execute("课程详情加载失败，请稍后重试") { _, client ->
        client.login()
        val course = client.queryCourseById(courseId)
        val status = calculateCourseStatus(course, nowProvider())
        var signConfig = parseSignConfig(course.courseSignConfig)
        var checkin: Int? = null
        var pass: Int? = null

        if (course.selected == true) {
          val chosen = findChosenCourseForCurrentSemester(client, courseId)
          if (signConfig == null) {
            signConfig = parseSignConfig(chosen?.courseInfo?.courseSignConfig)
          }
          checkin = chosen?.checkin
          pass = chosen?.pass
        }

        val availability = resolveAttendanceAvailability(signConfig, checkin, pass, nowProvider())
        course.toCourseDetailDto(status, signConfig, checkin, pass, availability)
      }

  override suspend fun getChosenCourses(): Result<List<BykcChosenCourseDto>> =
      execute("博雅已选课程加载失败，请稍后重试") { _, client ->
        client.login()
        val semester = resolveCurrentSemester(client.getAllConfig(), nowProvider())
        val semesterStartDate = semester.semesterStartDate ?: throw LocalBykcException("无法获取当前学期信息")
        val semesterEndDate = semester.semesterEndDate ?: throw LocalBykcException("无法获取当前学期信息")

        client.queryChosenCourse(semesterStartDate, semesterEndDate).map { chosen ->
          val course = chosen.courseInfo
          val signConfig = parseSignConfig(course?.courseSignConfig)
          val availability =
              resolveAttendanceAvailability(signConfig, chosen.checkin, chosen.pass, nowProvider())
          BykcChosenCourseDto(
              id = chosen.id,
              courseId = course?.id ?: 0L,
              courseName = course?.courseName ?: "未知课程",
              coursePosition = course?.coursePosition.normalizedOrNull(),
              courseTeacher = course?.courseTeacher.normalizedOrNull(),
              courseStartDate = course?.courseStartDate.toDtoLocalDateTime(),
              courseEndDate = course?.courseEndDate.toDtoLocalDateTime(),
              selectDate = chosen.selectDate.toDtoLocalDateTime(),
              courseCancelEndDate = course?.courseCancelEndDate.toDtoLocalDateTime(),
              category =
                  BykcCourseCategory.fromDisplayName(
                      course?.courseNewKind1?.kindName.normalizedOrNull()
                  ),
              subCategory =
                  BykcCourseSubCategory.fromDisplayName(
                      course?.courseNewKind2?.kindName.normalizedOrNull()
                  ),
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

  override suspend fun getStatistics(): Result<BykcStatisticsDto> =
      execute("博雅统计加载失败，请稍后重试") { _, client ->
        client.login()
        val statistics = client.queryStatisticByUserId()
        val categories = mutableListOf<BykcCategoryStatisticsDto>()
        statistics.statistical.forEach { (categoryKey, subCategoryMap) ->
          val categoryName = categoryKey.substringAfter("|", categoryKey)
          subCategoryMap.forEach { (subCategoryKey, entry) ->
            categories +=
                BykcCategoryStatisticsDto(
                    categoryName = categoryName,
                    subCategoryName = subCategoryKey.substringAfter("|", subCategoryKey),
                    requiredCount = entry.assessmentCount,
                    passedCount = entry.completeAssessmentCount,
                    isQualified = entry.completeAssessmentCount >= entry.assessmentCount,
                )
          }
        }
        BykcStatisticsDto(totalValidCount = statistics.validCount, categories = categories)
      }

  override suspend fun selectCourse(courseId: Long): Result<BykcSuccessResponse> =
      execute("选课失败，请稍后重试") { _, client ->
        client.login()
        try {
          client.choseCourse(courseId)
          BykcSuccessResponse("选课成功")
        } catch (error: Exception) {
          throw selectActionException(error)
        }
      }

  override suspend fun deselectCourse(courseId: Long): Result<BykcSuccessResponse> =
      execute("退选失败，请稍后重试") { _, client ->
        client.login()
        try {
          client.delChosenCourse(courseId)
          BykcSuccessResponse("退选成功")
        } catch (error: Exception) {
          throw LocalBykcActionException(
              "deselect_failed",
              HttpStatusCode.BadRequest,
              error.message,
          )
        }
      }

  override suspend fun signCourse(
      courseId: Long,
      lat: Double?,
      lng: Double?,
      signType: Int,
  ): Result<BykcSuccessResponse> =
      execute("签到失败，请稍后重试") { _, client ->
        client.login()
        try {
          if (signType == 1) {
            signIn(client, courseId, lat, lng)
            BykcSuccessResponse("签到成功")
          } else {
            signOut(client, courseId, lat, lng)
            BykcSuccessResponse("签退成功")
          }
        } catch (error: Exception) {
          throw LocalBykcActionException("sign_failed", HttpStatusCode.BadRequest, error.message)
        }
      }

  private suspend fun signIn(
      client: LocalBykcClient,
      courseId: Long,
      lat: Double?,
      lng: Double?,
  ) {
    val chosen =
        findChosenCourseForCurrentSemester(client, courseId)
            ?: throw LocalBykcException("该课程未选，无法签到")
    val signConfig =
        parseSignConfig(chosen.courseInfo?.courseSignConfig) ?: getSignConfig(client, courseId)
    val availability =
        resolveAttendanceAvailability(signConfig, chosen.checkin, chosen.pass, nowProvider())
    if (!availability.canSign) {
      throw LocalBykcException(resolveSignInUnavailableReason(chosen.checkin, chosen.pass))
    }

    val (finalLat, finalLng) = randomSignLocation(signConfig, lat, lng)
    client.signCourse(courseId, finalLat, finalLng, 1)
  }

  private suspend fun signOut(
      client: LocalBykcClient,
      courseId: Long,
      lat: Double?,
      lng: Double?,
  ) {
    val chosen =
        findChosenCourseForCurrentSemester(client, courseId)
            ?: throw LocalBykcException("该课程未选，无法签退")
    val signConfig =
        parseSignConfig(chosen.courseInfo?.courseSignConfig) ?: getSignConfig(client, courseId)
    val availability =
        resolveAttendanceAvailability(signConfig, chosen.checkin, chosen.pass, nowProvider())
    if (!availability.canSignOut) {
      throw LocalBykcException(resolveSignOutUnavailableReason(chosen.checkin, chosen.pass))
    }

    val (finalLat, finalLng) = randomSignLocation(signConfig, lat, lng)
    client.signCourse(courseId, finalLat, finalLng, 2)
  }

  private suspend fun getSignConfig(
      client: LocalBykcClient,
      courseId: Long,
  ): BykcSignConfigDto? =
      runCatching { parseSignConfig(client.queryCourseById(courseId).courseSignConfig) }.getOrNull()

  private suspend fun findChosenCourseForCurrentSemester(
      client: LocalBykcClient,
      courseId: Long,
  ): LocalBykcChosenCourse? {
    val semester = resolveCurrentSemester(client.getAllConfig(), nowProvider())
    val semesterStartDate = semester.semesterStartDate ?: throw LocalBykcException("无法获取当前学期信息")
    val semesterEndDate = semester.semesterEndDate ?: throw LocalBykcException("无法获取当前学期信息")
    return client.queryChosenCourse(semesterStartDate, semesterEndDate).find {
      it.courseInfo?.id == courseId
    }
  }

  private suspend fun currentClient(username: String): LocalBykcClient =
      clientMutex.withLock { clientCache.getOrPut(username) { LocalBykcClient(username) } }

  private suspend fun <T> execute(
      defaultMessage: String,
      block: suspend (String, LocalBykcClient) -> T,
  ): Result<T> {
    val session =
        LocalAuthSessionStore.get() ?: return Result.failure(localUnauthenticatedApiException())
    val username = session.user.schoolid.ifBlank { session.username }
    if (username.isBlank()) {
      return Result.failure(localUnauthenticatedApiException())
    }
    return try {
      Result.success(block(username, currentClient(username)))
    } catch (error: Exception) {
      Result.failure(mapFailure(error, defaultMessage))
    }
  }

  private fun mapFailure(error: Exception, defaultMessage: String): Exception =
      when (error) {
        is LocalBykcUnauthenticatedException,
        is LocalBykcSessionExpiredException -> {
          clearLocalConnectionSession()
          localUnauthenticatedApiException()
        }
        is LocalBykcActionException ->
            ApiCallException(
                message = userFacingMessageForCode(error.code, error.status),
                status = error.status,
                code = error.code,
            )
        is LocalBykcException ->
            ApiCallException(
                message = defaultMessage,
                status = HttpStatusCode.BadGateway,
                code = "bykc_error",
            )
        else -> error.toUserFacingApiException(defaultMessage)
      }

  private fun selectActionException(error: Exception): LocalBykcActionException {
    val message = error.message.orEmpty()
    val code =
        when {
          "重复报名" in message || "已报名" in message -> "already_selected"
          "人数已满" in message -> "course_full"
          "不可选择" in message || "不可报名" in message -> "course_not_selectable"
          else -> "select_failed"
        }
    return LocalBykcActionException(code, HttpStatusCode.Conflict, message)
  }
}

private class LocalBykcClient(
    private val username: String,
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
  private val loginMutex = Mutex()
  private var bykcToken: String? = null

  suspend fun login(forceRefresh: Boolean = false): Boolean {
    LocalAuthSessionStore.get() ?: throw LocalBykcUnauthenticatedException()
    if (!forceRefresh && !bykcToken.isNullOrBlank()) return true

    return loginMutex.withLock {
      if (!forceRefresh && !bykcToken.isNullOrBlank()) return@withLock true
      bykcToken = null
      val noRedirectClient = LocalUpstreamClientProvider.newNoRedirectClient()
      try {
        var currentUrl = loginUrl()
        repeat(MAX_LOGIN_REDIRECTS) {
          val response = noRedirectClient.get(currentUrl)
          val responseUrl = response.call.request.url.toString()
          val body = runCatching { response.bodyAsText() }.getOrNull().orEmpty()
          extractToken(responseUrl)?.let {
            bykcToken = it
            return@withLock true
          }
          if (isBykcLoginRedirect(response.status, responseUrl, body)) {
            clearLocalConnectionSession()
            throw LocalBykcUnauthenticatedException()
          }
          val location = response.headers[HttpHeaders.Location] ?: return@repeat
          currentUrl = resolveRedirectUrl(response.call.request.url, location)
        }
        runCatching { LocalUpstreamClientProvider.shared().get(casLoginUrl()) }
        true
      } finally {
        noRedirectClient.close()
      }
    }
  }

  suspend fun getUserProfile(): LocalBykcUserProfile =
      decodeData(callApiRaw("getUserProfile", "{}"), "博雅资料加载失败")

  suspend fun queryStudentSemesterCourseByPage(
      pageNumber: Int,
      pageSize: Int,
  ): LocalBykcCoursePageResult =
      decodeData(
          callApiRaw(
              "queryStudentSemesterCourseByPage",
              json.encodeToString(LocalBykcPageRequest(pageNumber, pageSize)),
          ),
          "博雅课程列表加载失败",
      )

  suspend fun queryCourseById(id: Long): LocalBykcRawCourse =
      decodeData(
          callApiRaw("queryCourseById", json.encodeToString(LocalBykcIdRequest(id))),
          "博雅课程详情加载失败",
      )

  suspend fun getAllConfig(): LocalBykcAllConfig =
      decodeData(callApiRaw("getAllConfig", "{}"), "博雅配置加载失败")

  suspend fun queryChosenCourse(startDate: String, endDate: String): List<LocalBykcChosenCourse> =
      decodeData<LocalBykcChosenCoursePayload>(
              callApiRaw(
                  "queryChosenCourse",
                  json.encodeToString(LocalBykcChosenCourseQueryRequest(startDate, endDate)),
              ),
              "博雅已选课程加载失败",
          )
          .courseList

  suspend fun queryStatisticByUserId(): LocalBykcStatisticsData =
      decodeData(callApiRaw("queryStatisticByUserId", "{}"), "博雅统计加载失败")

  suspend fun choseCourse(courseId: Long) {
    decodeData<LocalBykcCourseActionResult>(
        callApiRaw("choseCourse", json.encodeToString(LocalBykcCourseIdRequest(courseId))),
        "选课失败",
    )
  }

  suspend fun delChosenCourse(id: Long) {
    decodeData<LocalBykcCourseActionResult>(
        callApiRaw("delChosenCourse", json.encodeToString(LocalBykcIdRequest(id))),
        "退选失败",
    )
  }

  suspend fun signCourse(
      courseId: Long,
      lat: Double,
      lng: Double,
      signType: Int,
  ) {
    val raw =
        callApiRaw(
            "signCourseByUser",
            json.encodeToString(LocalBykcSignCourseRequest(courseId, lat, lng, signType)),
        )
    val response = json.decodeFromString<LocalBykcApiResponse<JsonElement>>(raw)
    if (!response.isSuccess) {
      throw LocalBykcException(response.errmsg.ifBlank { "签到失败" })
    }
  }

  private suspend fun callApiRaw(apiName: String, requestJson: String): String =
      try {
        doCallApiRaw(apiName, requestJson)
      } catch (error: LocalBykcUnauthenticatedException) {
        throw error
      } catch (error: Exception) {
        login(forceRefresh = true)
        doCallApiRaw(apiName, requestJson)
      }

  @OptIn(ExperimentalEncodingApi::class)
  private suspend fun doCallApiRaw(apiName: String, requestJson: String): String {
    val encrypted = LocalBykcCrypto.encryptRequest(requestJson)
    val response =
        LocalUpstreamClientProvider.shared().post(
            localUpstreamUrl("https://bykc.buaa.edu.cn/sscv/$apiName")
        ) {
          header(HttpHeaders.ContentType, "application/json; charset=UTF-8")
          header(HttpHeaders.Accept, ContentType.Application.Json.toString())
          header(
              HttpHeaders.Referrer,
              localUpstreamUrl("https://bykc.buaa.edu.cn/system/course-select"),
          )
          header(HttpHeaders.Origin, localUpstreamUrl("https://bykc.buaa.edu.cn"))
          bykcToken?.let {
            header("auth_token", it)
            header("authtoken", it)
          }
          header("ak", encrypted.ak)
          header("sk", encrypted.sk)
          header("ts", encrypted.ts)
          setBody(encrypted.encryptedData)
        }
    val responseBody = runCatching { response.bodyAsText() }.getOrNull().orEmpty()
    if (isBykcLoginRedirect(response.status, response.call.request.url.toString(), responseBody)) {
      throw LocalBykcUnauthenticatedException()
    }
    if (response.status != HttpStatusCode.OK) {
      throw LocalBykcException("BYKC server returned ${response.status}")
    }

    val encodedPayload =
        runCatching { json.decodeFromString<String>(responseBody) }.getOrNull() ?: responseBody
    val decoded =
        runCatching {
              LocalBykcCrypto.aesDecrypt(Base64.decode(encodedPayload), encrypted.aesKey)
                  .decodeToString()
            }
            .getOrElse { encodedPayload }
    if (decoded.contains("会话已失效") || decoded.contains("未登录")) {
      bykcToken = null
      throw LocalBykcSessionExpiredException()
    }
    return decoded
  }

  private inline fun <reified T> decodeData(raw: String, fallbackMessage: String): T {
    val response = json.decodeFromString<LocalBykcApiResponse<T>>(raw)
    if (!response.isSuccess || response.data == null) {
      throw LocalBykcException(response.errmsg.ifBlank { fallbackMessage })
    }
    return response.data
  }

  private fun extractToken(url: String): String? =
      Regex("""[?&]token=([^&]+)""").find(url)?.groupValues?.getOrNull(1)?.takeIf {
        it.isNotBlank()
      }

  private fun resolveRedirectUrl(currentUrl: Url, location: String): String {
    if (location.startsWith("http://") || location.startsWith("https://")) {
      return localUpstreamUrl(location)
    }
    if (location.startsWith("//")) {
      return localUpstreamUrl("${currentUrl.protocol.name}:$location")
    }
    val authority =
        "${currentUrl.protocol.name}://${currentUrl.host}${if (currentUrl.specifiedPort != currentUrl.protocol.defaultPort) ":${currentUrl.specifiedPort}" else ""}"
    if (location.startsWith("/")) {
      return "$authority$location"
    }
    val basePath = currentUrl.encodedPath.substringBeforeLast('/', "")
    val separator = if (basePath.endsWith("/")) "" else "/"
    return "$authority$basePath$separator$location"
  }

  private fun loginUrl(): String = localUpstreamUrl("https://bykc.buaa.edu.cn/sscv/cas/login")

  private fun casLoginUrl(): String = localUpstreamUrl("https://bykc.buaa.edu.cn/cas-login?token=")

  companion object {
    private const val MAX_LOGIN_REDIRECTS = 10
  }
}

private fun LocalBykcUserProfile.toDto(): BykcUserProfileDto =
    BykcUserProfileDto(
        id = id,
        employeeId = employeeId,
        realName = realName,
        studentNo = studentNo,
        studentType = studentType,
        classCode = classCode,
        collegeName = college?.collegeName,
        termName = term?.termName,
    )

private fun LocalBykcRawCourse.toCourseDto(status: BykcCourseStatus): BykcCourseDto {
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

private fun LocalBykcRawCourse.toCourseDetailDto(
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

private fun calculateCourseStatus(
    course: LocalBykcRawCourse,
    now: LocalDateTime = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()),
): BykcCourseStatus =
    try {
      val courseStart = parseDateTime(course.courseStartDate)
      val selectStart = parseDateTime(course.courseSelectStartDate)
      val selectEnd = parseDateTime(course.courseSelectEndDate)
      when {
        courseStart != null && now > courseStart -> BykcCourseStatus.EXPIRED
        course.selected == true -> BykcCourseStatus.SELECTED
        selectEnd != null && now > selectEnd -> BykcCourseStatus.ENDED
        course.courseCurrentCount != null && course.courseCurrentCount >= course.courseMaxCount ->
            BykcCourseStatus.FULL
        selectStart != null && now < selectStart -> BykcCourseStatus.PREVIEW
        else -> BykcCourseStatus.AVAILABLE
      }
    } catch (_: Exception) {
      BykcCourseStatus.AVAILABLE
    }

private fun parseSignConfig(configJson: String?): BykcSignConfigDto? {
  if (configJson.isNullOrBlank()) return null
  val json = Json { ignoreUnknownKeys = true }
  return runCatching { json.decodeFromString<LocalBykcSignConfig>(configJson) }
      .getOrNull()
      ?.let { config ->
        BykcSignConfigDto(
            signStartDate = config.signStartDate.toDtoLocalDateTime(),
            signEndDate = config.signEndDate.toDtoLocalDateTime(),
            signOutStartDate = config.signOutStartDate.toDtoLocalDateTime(),
            signOutEndDate = config.signOutEndDate.toDtoLocalDateTime(),
            signPoints = config.signPointList.map { BykcSignPointDto(it.lat, it.lng, it.radius) },
        )
      }
}

private fun resolveCurrentSemester(
    config: LocalBykcAllConfig,
    now: LocalDateTime,
): LocalBykcSemester {
  val semesters = config.semester
  if (semesters.isEmpty()) throw LocalBykcException("无法获取当前学期信息")
  semesters
      .firstOrNull { isWithinWindow(it.semesterStartDate, it.semesterEndDate, now) }
      ?.let {
        return it
      }
  return semesters.maxByOrNull {
    parseDateTime(it.semesterEndDate) ?: LocalDateTime.parse("1970-01-01T00:00:00")
  } ?: throw LocalBykcException("无法获取当前学期信息")
}

private data class AttendanceAvailability(
    val canSign: Boolean,
    val canSignOut: Boolean,
)

private fun resolveAttendanceAvailability(
    signConfig: BykcSignConfigDto?,
    checkin: Int?,
    pass: Int?,
    now: LocalDateTime,
): AttendanceAvailability {
  val canSign =
      pass != 1 &&
          isUnsignedCheckin(checkin) &&
          isWithinWindow(signConfig?.signStartDate, signConfig?.signEndDate, now)
  val canSignOut =
      pass != 1 &&
          isEligibleForSignOut(checkin) &&
          isWithinWindow(signConfig?.signOutStartDate, signConfig?.signOutEndDate, now)
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

private fun randomSignLocation(
    signConfig: BykcSignConfigDto?,
    fallbackLat: Double?,
    fallbackLng: Double?,
): Pair<Double, Double> {
  val point = signConfig?.signPoints?.randomOrNull()
  if (point != null && point.radius > 0.0) {
    val dist = point.radius * sqrt(Random.nextDouble())
    val angle = Random.nextDouble() * 2 * PI
    return destinationPoint(point.lat, point.lng, dist, angle)
  }
  if (fallbackLat != null && fallbackLng != null) return fallbackLat to fallbackLng
  throw LocalBykcException("未提供签到坐标且后端未返回签到范围")
}

private fun destinationPoint(
    lat: Double,
    lng: Double,
    dist: Double,
    angle: Double,
): Pair<Double, Double> {
  val r = dist / 6_371_000.0
  val latRadians = degreesToRadians(lat)
  val lngRadians = degreesToRadians(lng)
  val destinationLat = asin(sin(latRadians) * cos(r) + cos(latRadians) * sin(r) * cos(angle))
  val destinationLng =
      lngRadians +
          atan2(
              sin(angle) * sin(r) * cos(latRadians),
              cos(r) - sin(latRadians) * sin(destinationLat),
          )
  return radiansToDegrees(destinationLat) to radiansToDegrees(destinationLng)
}

private fun degreesToRadians(value: Double): Double = value * PI / 180.0

private fun radiansToDegrees(value: Double): Double = value * 180.0 / PI

private fun isUnsignedCheckin(checkin: Int?): Boolean = checkin == null || checkin == 0

private fun isEligibleForSignOut(checkin: Int?): Boolean =
    isUnsignedCheckin(checkin) || checkin == 5 || checkin == 6

private fun isWithinWindow(
    startDate: LocalDateTime?,
    endDate: LocalDateTime?,
    now: LocalDateTime,
): Boolean {
  val start = startDate ?: return false
  val end = endDate ?: return false
  return now >= start && now <= end
}

private fun isWithinWindow(startDate: String?, endDate: String?, now: LocalDateTime): Boolean {
  val start = parseDateTime(startDate) ?: return false
  val end = parseDateTime(endDate) ?: return false
  return now >= start && now <= end
}

private fun parseDateTime(text: String?): LocalDateTime? = text.toDtoLocalDateTime()

private fun String?.normalizedOrNull(): String? = this?.trim()?.takeIf { it.isNotEmpty() }

private fun List<String>?.normalizedTextList(): List<String> =
    this.orEmpty().mapNotNull { it.normalizedOrNull() }

private fun List<String>?.toAudienceCampusLabels(rawCampus: String?): List<String> {
  val normalized = normalizedTextList().map { if (it == "全部校区") "未指定校区" else it }.distinct()
  if (normalized.isNotEmpty()) return normalized
  return when (rawCampus.normalizedOrNull()) {
    "ALL" -> listOf("未指定校区")
    else -> emptyList()
  }
}

private fun String?.toDtoLocalDateTime(): LocalDateTime? {
  val value = normalizedOrNull() ?: return null
  return runCatching { LocalDateTime.parse(value.replace(" ", "T")) }.getOrNull()
}

private fun isBykcLoginRedirect(
    status: HttpStatusCode,
    finalUrl: String,
    body: String,
): Boolean {
  if (status == HttpStatusCode.Unauthorized) return true
  if (localIsSsoUrl(finalUrl)) return true
  val trimmed = body.trimStart()
  if (
      trimmed.startsWith("<!DOCTYPE html", ignoreCase = true) ||
          trimmed.startsWith("<html", ignoreCase = true)
  ) {
    return body.contains("input name=\"execution\"") || body.contains("统一身份认证", ignoreCase = true)
  }
  return false
}

private class LocalBykcException(message: String) : Exception(message)

private class LocalBykcUnauthenticatedException : Exception()

private class LocalBykcSessionExpiredException : Exception()

private class LocalBykcActionException(
    val code: String,
    val status: HttpStatusCode,
    rawMessage: String?,
) : Exception(rawMessage)

@Serializable
private data class LocalBykcApiResponse<T>(
    val status: String,
    val success: Boolean? = null,
    val data: T? = null,
    val msg: String? = null,
    val errmsg: String = "",
) {
  val isSuccess: Boolean
    get() = status == "0"
}

@Serializable
private data class LocalBykcUserProfile(
    val id: Long,
    val employeeId: String,
    val realName: String,
    val studentNo: String? = null,
    val studentType: String? = null,
    val classCode: String? = null,
    val college: LocalBykcCollege? = null,
    val term: LocalBykcTerm? = null,
)

@Serializable
private data class LocalBykcTerm(
    val id: Long,
    val termName: String,
    val current: Int = 0,
)

@Serializable
private data class LocalBykcCollege(
    val id: Long,
    val collegeName: String,
)

@Serializable
private data class LocalBykcCourseKind(
    val id: Long,
    val kindName: String,
)

@Serializable
private data class LocalBykcRawCourse(
    val id: Long,
    val courseName: String,
    val courseBelongCollege: LocalBykcCollege? = null,
    val coursePosition: String? = null,
    val courseContact: String? = null,
    val courseContactMobile: String? = null,
    val courseTeacher: String? = null,
    val courseStartDate: String? = null,
    val courseEndDate: String? = null,
    val courseSelectStartDate: String? = null,
    val courseSelectEndDate: String? = null,
    val courseCancelEndDate: String? = null,
    val courseMaxCount: Int,
    val courseCurrentCount: Int? = null,
    val courseNewKind1: LocalBykcCourseKind? = null,
    val courseNewKind2: LocalBykcCourseKind? = null,
    val courseCampus: String? = null,
    val courseCampusList: List<String>? = null,
    val courseCollegeList: List<String>? = null,
    val courseTermList: List<String>? = null,
    val courseGroupList: List<String>? = null,
    val courseDesc: String? = null,
    val courseSignType: Int? = null,
    val courseSignConfig: String? = null,
    val selected: Boolean? = null,
)

@Serializable
private data class LocalBykcCoursePageResult(
    val content: List<LocalBykcRawCourse>,
    val totalElements: Int,
    val totalPages: Int,
    val size: Int,
    val number: Int,
)

@Serializable
private data class LocalBykcChosenCourse(
    val id: Long,
    val selectDate: String? = null,
    val courseInfo: LocalBykcRawCourse? = null,
    val checkin: Int? = null,
    val score: Int? = null,
    val pass: Int? = null,
    val homework: String? = null,
    val signInfo: String? = null,
)

@Serializable
private data class LocalBykcAllConfig(
    val semester: List<LocalBykcSemester> = emptyList(),
)

@Serializable
private data class LocalBykcSemester(
    val id: Long,
    val semesterName: String,
    val semesterStartDate: String? = null,
    val semesterEndDate: String? = null,
)

@Serializable
private data class LocalBykcSignConfig(
    val signStartDate: String? = null,
    val signEndDate: String? = null,
    val signOutStartDate: String? = null,
    val signOutEndDate: String? = null,
    val signPointList: List<LocalBykcSignPoint> = emptyList(),
)

@Serializable
private data class LocalBykcSignPoint(
    val lat: Double,
    val lng: Double,
    val radius: Double = 0.0,
)

@Serializable
private data class LocalBykcChosenCoursePayload(
    val courseList: List<LocalBykcChosenCourse> = emptyList(),
)

@Serializable
private data class LocalBykcCourseActionResult(
    val courseCurrentCount: Int? = null,
)

@Serializable
private data class LocalBykcStatisticsData(
    val validCount: Int,
    val statistical: Map<String, Map<String, LocalBykcSubCategoryStats>> = emptyMap(),
)

@Serializable
private data class LocalBykcSubCategoryStats(
    val assessmentCount: Int,
    val completeAssessmentCount: Int,
)

@Serializable
private data class LocalBykcPageRequest(
    val pageNumber: Int,
    val pageSize: Int,
)

@Serializable
private data class LocalBykcCourseIdRequest(
    val courseId: Long,
)

@Serializable
private data class LocalBykcIdRequest(
    val id: Long,
)

@Serializable
private data class LocalBykcChosenCourseQueryRequest(
    val startDate: String,
    val endDate: String,
)

@Serializable
private data class LocalBykcSignCourseRequest(
    val courseId: Long,
    val signLat: Double,
    val signLng: Double,
    val signType: Int,
)
