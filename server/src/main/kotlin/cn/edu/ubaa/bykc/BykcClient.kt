package cn.edu.ubaa.bykc

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import java.util.Base64
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

/**
 * 博雅系统原始 API 客户端。 负责与博雅系统进行协议层通信，包括鉴权令牌提取、请求加密 (RSA/AES)、响应解密以及原始数据解析。
 *
 * @param username 关联的用户名。
 */
class BykcClient(private val username: String) {

  private val log = LoggerFactory.getLogger(BykcClient::class.java)
  private val sessionManager: SessionManager = GlobalSessionManager.instance
  private var session: SessionManager.UserSession? = null
  private val json = Json { ignoreUnknownKeys = true }

  // 博雅系统特有的 auth_token，从 SSO 重定向 URL 中提取
  private var bykcToken: String? = null
  private var lastLoginMillis: Long = 0L

  /** 确保当前用户存在活跃的后台会话。 */
  private suspend fun ensureSession(): SessionManager.UserSession {
    session = sessionManager.getSession(username)
    return session ?: throw IllegalStateException("No active session for $username")
  }

  /**
   * 执行博雅系统的“二次登录”以获取 auth_token。
   *
   * 该过程会访问博雅登录入口，跟随 SSO 重定向并捕获 URL 中的令牌。
   *
   * @param forceRefresh 是否强制重新获取令牌。
   * @return 登录是否成功。
   * @throws IllegalStateException 当没有活跃会话时抛出。
   */
  suspend fun login(forceRefresh: Boolean = false): Boolean {

    if (!forceRefresh && bykcToken != null) return true

    val s = ensureSession()

    val client = s.client

    val resp = client.get(VpnCipher.toVpnUrl("https://bykc.buaa.edu.cn/sscv/cas/login"))

    val finalUrl = resp.request.url.toString()

    val token =
      if (finalUrl.contains("?token=")) {

        finalUrl.substringAfter("?token=")
      } else {

        resp.headers["Location"]?.let {
          if (it.contains("?token=")) it.substringAfter("?token=") else null
        }
      }

    if (token != null) {

      bykcToken = token

      lastLoginMillis = System.currentTimeMillis()

      return true
    }

    try {

      client.get(VpnCipher.toVpnUrl("https://bykc.buaa.edu.cn/cas-login?token="))
    } catch (_: Exception) {}

    lastLoginMillis = System.currentTimeMillis()

    return true
  }

  /**
   * 调用博雅系统的加密 API。
   *
   * 封装了自动重试（登录失效时自动重新 login）逻辑。
   *
   * @throws RuntimeException 当请求失败且重试无效时抛出。
   */
  private suspend fun callApiRaw(apiName: String, requestJson: String): String {

    return try {

      doCallApiRaw(apiName, requestJson)
    } catch (e: Exception) {

      log.warn("API call failed, retrying after login: {}", e.message)

      login(forceRefresh = true)

      doCallApiRaw(apiName, requestJson)
    }
  }

  /**
   * 执行具体的加密请求与解密响应逻辑。
   *
   * @throws BykcSessionExpiredException 当会话已失效时抛出。
   * @throws RuntimeException 当服务器响应非 200 或解码失败时抛出。
   */
  private suspend fun doCallApiRaw(apiName: String, requestJson: String): String {

    val s = ensureSession()

    val client = s.client

    // 1. 请求加密 (生成 ak, sk, ts)

    val enc = BykcCrypto.encryptRequest(requestJson)

    val httpResponse: HttpResponse =
      client.post(VpnCipher.toVpnUrl("https://bykc.buaa.edu.cn/sscv/$apiName")) {
        contentType(ContentType.Application.Json.withCharset(Charsets.UTF_8))

        accept(ContentType.Application.Json)

        header(
          HttpHeaders.Referrer,
          VpnCipher.toVpnUrl("https://bykc.buaa.edu.cn/system/course-select"),
        )

        header(HttpHeaders.Origin, VpnCipher.toVpnUrl("https://bykc.buaa.edu.cn"))

        // 携带认证令牌

        bykcToken?.let {
          header("auth_token", it)

          header("authtoken", it)
        }

        header("ak", enc.ak)
        header("sk", enc.sk)
        header("ts", enc.ts)

        setBody(enc.encryptedData)
      }

    val respBodyText =
      try {
        httpResponse.bodyAsText()
      } catch (_: Exception) {
        ""
      }

    if (httpResponse.status != HttpStatusCode.OK) {

      throw RuntimeException("BYKC server returned http ${httpResponse.status}: $respBodyText")
    }

    // 2. 响应解密

    val respBase64 =
      try {
        json.decodeFromString<String>(respBodyText)
      } catch (_: Exception) {
        respBodyText
      }

    val decoded =
      try {

        val b = Base64.getDecoder().decode(respBase64)

        String(BykcCrypto.aesDecrypt(b, enc.aesKey), Charsets.UTF_8)
      } catch (e: Exception) {
        respBase64
      }

    if (decoded.contains("会话已失效") || decoded.contains("未登录")) throw BykcSessionExpiredException()

    return decoded
  }

  /**
   * 获取用户资料。
   *
   * @throws RuntimeException 当 API 调用失败或返回数据为空时抛出。
   */
  suspend fun getUserProfile(): BykcUserProfile {

    val raw = callApiRaw("getUserProfile", "{}").trim()

    val apiResp = json.decodeFromString<BykcApiResponse<BykcUserProfile>>(raw)

    if (!apiResp.isSuccess || apiResp.data == null)
      throw RuntimeException("BYKC getUserProfile failed: ${apiResp.errmsg}")

    return apiResp.data
  }

  /**
   * 分页查询学期课程。
   *
   * @throws RuntimeException 当 API 调用失败时抛出。
   */
  suspend fun queryStudentSemesterCourseByPage(
    pageNumber: Int,
    pageSize: Int,
  ): BykcCoursePageResult {

    val req = "{\"pageNumber\":$pageNumber,\"pageSize\":$pageSize}"

    val raw = callApiRaw("queryStudentSemesterCourseByPage", req)

    val apiResp = json.decodeFromString<BykcApiResponse<BykcCoursePageResult>>(raw)

    if (!apiResp.isSuccess || apiResp.data == null)
      throw RuntimeException("BYKC query courses failed: ${apiResp.errmsg}")

    return apiResp.data
  }

  /**
   * 选课。
   *
   * @throws RuntimeException 当选课操作失败（如人数已满、时间冲突）时抛出。
   */
  suspend fun choseCourse(courseId: Long): BykcApiResponse<BykcCourseActionResult> {

    val req = "{\"courseId\":$courseId}"

    val raw = callApiRaw("choseCourse", req)

    return json.decodeFromString<BykcApiResponse<BykcCourseActionResult>>(raw).also {
      if (!it.isSuccess) throw RuntimeException("Bykc choose failed: ${it.errmsg}")
    }
  }

  /**
   * 退选。
   *
   * @throws BykcSelectException 当退选失败（如超过退选时间）时抛出。
   * @throws RuntimeException 当发生其他未知错误时抛出。
   */
  suspend fun delChosenCourse(chosenCourseId: Long): BykcApiResponse<BykcCourseActionResult> {

    val req = "{\"id\":$chosenCourseId}"

    val raw = callApiRaw("delChosenCourse", req)

    val apiResp = json.decodeFromString<BykcApiResponse<BykcCourseActionResult>>(raw)

    if (!apiResp.isSuccess) {

      if (apiResp.errmsg.contains("退选失败")) throw BykcSelectException(apiResp.errmsg)

      throw RuntimeException("Bykc del chosen failed: ${apiResp.errmsg}")
    }

    return apiResp
  }

  /**
   * 获取系统所有配置。
   *
   * @throws RuntimeException 当获取配置失败时抛出。
   */
  suspend fun getAllConfig(): BykcAllConfig {

    val raw = callApiRaw("getAllConfig", "{}")

    val apiResp = json.decodeFromString<BykcApiResponse<BykcAllConfig>>(raw)

    if (!apiResp.isSuccess || apiResp.data == null)
      throw RuntimeException("BYKC getAllConfig failed: ${apiResp.errmsg}")

    return apiResp.data
  }

  /**
   * 查询指定日期范围内的已选课程。
   *
   * @throws RuntimeException 当查询失败时抛出。
   */
  suspend fun queryChosenCourse(startDate: String, endDate: String): List<BykcChosenCourse> {

    val req = "{\"startDate\":\"$startDate\",\"endDate\":\"$endDate\"}"

    val raw = callApiRaw("queryChosenCourse", req)

    val apiResp = json.decodeFromString<BykcApiResponse<BykcChosenCoursePayload>>(raw)

    if (!apiResp.isSuccess || apiResp.data == null)
      throw RuntimeException("BYKC queryChosenCourse failed: ${apiResp.errmsg}")

    return apiResp.data.courseList
  }

  /**
   * 按 ID 查询课程详情。
   *
   * @throws RuntimeException 当查询失败时抛出。
   */
  suspend fun queryCourseById(id: Long): BykcCourse {

    val req = "{\"id\":$id}"

    val raw = callApiRaw("queryCourseById", req)

    val apiResp = json.decodeFromString<BykcApiResponse<BykcCourse>>(raw)

    if (!apiResp.isSuccess || apiResp.data == null)
      throw RuntimeException("BYKC queryCourseById failed: ${apiResp.errmsg}")

    return apiResp.data
  }

  /**
   * 提交签到/签退请求。
   *
   * @throws BykcException 当签到/签退失败（如不在范围内、不在时间内）时抛出。
   */
  suspend fun signCourse(
    courseId: Long,
    lat: Double,
    lng: Double,
    signType: Int,
  ): BykcApiResponse<BykcSignResult> {

    val req = "{\"courseId\":$courseId,\"signLat\":$lat,\"signLng\":$lng,\"signType\":$signType}"

    val raw = callApiRaw("signCourseByUser", req)

    val apiResp = json.decodeFromString<BykcApiResponse<BykcSignResult>>(raw)

    if (!apiResp.isSuccess) throw BykcException("签到失败: ${apiResp.errmsg}")

    return apiResp
  }

  /**
   * 查询用户累计修读统计。
   *
   * @throws RuntimeException 当查询失败时抛出。
   */
  suspend fun queryStatisticByUserId(): BykcStatisticsData {

    val raw = callApiRaw("queryStatisticByUserId", "{}")

    val apiResp = json.decodeFromString<BykcApiResponse<BykcStatisticsData>>(raw)

    if (!apiResp.isSuccess || apiResp.data == null)
      throw RuntimeException("BYKC queryStatisticByUserId failed: ${apiResp.errmsg}")

    return apiResp.data
  }
}
