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

class BykcClient(private val username: String) {

    private val log = LoggerFactory.getLogger(BykcClient::class.java)
    private val sessionManager: SessionManager = GlobalSessionManager.instance
    private var session: SessionManager.UserSession? = null

    private val json = Json { ignoreUnknownKeys = true }

    // BYKC Token，登录时从 CAS 重定向获取
    private var bykcToken: String? = null
    private var lastLoginMillis: Long = 0L

    private suspend fun ensureSession(): SessionManager.UserSession {
        session = sessionManager.getSession(username)
        return session ?: throw IllegalStateException("No active session for $username")
    }

    /** 完成 BYKC 登录并提取 token */
    suspend fun login(forceRefresh: Boolean = false): Boolean {
        // 快速路径：若已有 Token 且不强制刷新，则复用
        // 依赖下游请求失败来触发刷新机制
        if (!forceRefresh && bykcToken != null) {
            return true
        }

        val s = ensureSession()
        val client = s.client

        // 发起 CAS 登录请求（跟随重定向），最终 URL 中通常包含 ?token=xxx
        val resp = client.get(VpnCipher.toVpnUrl("https://bykc.buaa.edu.cn/sscv/cas/login"))
        val finalUrl = resp.request.url.toString()
        val token =
                if (finalUrl.contains("?token=")) {
                    finalUrl.substringAfter("?token=")
                } else {
                    // 某些情况下 token 可能在重定向响应头中，尝试从 headers 中查找 Location
                    val location = resp.headers["Location"]
                    if (location != null && location.contains("?token="))
                            location.substringAfter("?token=")
                    else null
                }

        if (token != null) {
            bykcToken = token
            lastLoginMillis = System.currentTimeMillis()
            return true
        }

        // 如果没有直接获取 token，尝试访问 cas-login 路径以触发会话检查
        try {
            client.get(VpnCipher.toVpnUrl("https://bykc.buaa.edu.cn/cas-login?token="))
        } catch (_: Exception) {}
        // token 未能提取，但客户端的 cookie 可能已建立，会话可用
        lastLoginMillis = System.currentTimeMillis()
        return true
    }

    private suspend fun callApiRaw(apiName: String, requestJson: String): String {
        return try {
            // 初次尝试
            doCallApiRaw(apiName, requestJson)
        } catch (e: Exception) {
            // 简单重试策略：若失败则强制登录并重试一次
            // BYKC 接口错误信息多样，统一重试以增强鲁棒性
            log.warn("API call failed, retrying after login: {}", e.message)
            login(forceRefresh = true)
            doCallApiRaw(apiName, requestJson)
        }
    }

    private suspend fun doCallApiRaw(apiName: String, requestJson: String): String {
        val s = ensureSession()
        val client = s.client

        // 加密请求
        val enc = BykcCrypto.encryptRequest(requestJson)

        val httpResponse: HttpResponse =
                client.post(VpnCipher.toVpnUrl("https://bykc.buaa.edu.cn/sscv/$apiName")) {
                    contentType(ContentType.Application.Json.withCharset(Charsets.UTF_8))
                    accept(ContentType.Application.Json)
                    header(
                            HttpHeaders.Referrer,
                            VpnCipher.toVpnUrl("https://bykc.buaa.edu.cn/system/course-select")
                    )
                    header(HttpHeaders.Origin, VpnCipher.toVpnUrl("https://bykc.buaa.edu.cn"))
                    // 模拟浏览器 Headers 避免被 WAF 拦截
                    header(
                            "sec-ch-ua",
                            "\"Microsoft Edge\";v=\"143\", \"Chromium\";v=\"143\", \"Not A(Brand\";v=\"24\""
                    )
                    header("sec-ch-ua-mobile", "?0")
                    header("sec-ch-ua-platform", "\"Windows\"")

                    // 禁用 Expect: 100-continue 避免延迟
                    headers.remove(HttpHeaders.Expect)

                    bykcToken?.let {
                        header("auth_token", it)
                        header("authtoken", it)
                    }
                    header("ak", enc.ak)
                    header("sk", enc.sk)
                    header("ts", enc.ts)
                    setBody(enc.encryptedData)
                }

        // 先读取响应体以便在非 200 时包含更多调试信息
        val respBytes = httpResponse.readRawBytes()
        val respBodyText =
                try {
                    String(respBytes, Charsets.UTF_8)
                } catch (_: Exception) {
                    ""
                }

        if (httpResponse.status != HttpStatusCode.OK) {
            throw RuntimeException(
                    "BYKC server returned http ${httpResponse.status}: $respBodyText"
            )
        }

        val respBase64 =
                try {
                    // 部分接口直接返回字符串形式的 base64，因此先按 JSON 字符串解析
                    json.decodeFromString(respBodyText)
                } catch (_: Exception) {
                    respBodyText
                }
        // 部分接口返回 Base64 编码数据 — 尝试解码
        val decoded =
                try {
                    val b = Base64.getDecoder().decode(respBase64)
                    String(BykcCrypto.aesDecrypt(b, enc.aesKey), Charsets.UTF_8)
                } catch (e: Exception) {
                    // 如果不是 base64，则直接尝试按 UTF-8 解码
                    try {
                        respBase64
                    } catch (e2: Exception) {
                        throw RuntimeException("Failed to decode BYKC response: $e")
                    }
                }

        // 响应内容的通用鉴权失败检查
        if (decoded.contains("会话已失效") || decoded.contains("未登录")) {
            throw BykcSessionExpiredException()
        }

        return decoded
    }

    suspend fun getUserProfile(): BykcUserProfile {
        val raw = callApiRaw("getUserProfile", "{}").trim()
        val apiResp = json.decodeFromString<BykcApiResponse<BykcUserProfile>>(raw)
        if (!apiResp.isSuccess || apiResp.data == null)
                throw RuntimeException("BYKC getUserProfile failed: ${apiResp.errmsg}")
        return apiResp.data
    }

    suspend fun queryStudentSemesterCourseByPage(
            pageNumber: Int,
            pageSize: Int
    ): BykcCoursePageResult {
        val req = "{\"pageNumber\":$pageNumber,\"pageSize\":$pageSize}"
        val raw = callApiRaw("queryStudentSemesterCourseByPage", req)
        val apiResp = json.decodeFromString<BykcApiResponse<BykcCoursePageResult>>(raw)
        if (!apiResp.isSuccess || apiResp.data == null)
                throw RuntimeException("BYKC query courses failed: ${apiResp.errmsg}")
        return apiResp.data
    }

    suspend fun choseCourse(courseId: Long): BykcApiResponse<BykcCourseActionResult> {
        val req = "{\"courseId\":$courseId}"
        val raw = callApiRaw("choseCourse", req)
        val apiResp = json.decodeFromString<BykcApiResponse<BykcCourseActionResult>>(raw)
        if (!apiResp.isSuccess) throw RuntimeException("Bykc choose failed: ${apiResp.errmsg}")
        return apiResp
    }

    /** 退选课程 */
    suspend fun delChosenCourse(chosenCourseId: Long): BykcApiResponse<BykcCourseActionResult> {
        val req = "{\"id\":$chosenCourseId}"
        val raw = callApiRaw("delChosenCourse", req)
        val apiResp = json.decodeFromString<BykcApiResponse<BykcCourseActionResult>>(raw)
        if (!apiResp.isSuccess) {
            if (apiResp.errmsg.contains("退选失败")) {
                throw BykcSelectException(apiResp.errmsg)
            }
            throw RuntimeException("Bykc del chosen failed: ${apiResp.errmsg}")
        }
        return apiResp
    }

    /** 获取系统配置（学期、校区等） */
    suspend fun getAllConfig(): BykcAllConfig {
        val raw = callApiRaw("getAllConfig", "{}")
        val apiResp = json.decodeFromString<BykcApiResponse<BykcAllConfig>>(raw)
        if (!apiResp.isSuccess || apiResp.data == null)
                throw RuntimeException("BYKC getAllConfig failed: ${apiResp.errmsg}")
        return apiResp.data
    }

    /** 查询已选课程 */
    suspend fun queryChosenCourse(startDate: String, endDate: String): List<BykcChosenCourse> {
        val req = "{\"startDate\":\"$startDate\",\"endDate\":\"$endDate\"}"
        val raw = callApiRaw("queryChosenCourse", req)
        val apiResp = json.decodeFromString<BykcApiResponse<BykcChosenCoursePayload>>(raw)
        if (!apiResp.isSuccess || apiResp.data == null)
                throw RuntimeException("BYKC queryChosenCourse failed: ${apiResp.errmsg}")
        return apiResp.data.courseList
    }

    /** 根据 ID 查询课程详情 */
    suspend fun queryCourseById(id: Long): BykcCourse {
        val req = "{\"id\":$id}"
        val raw = callApiRaw("queryCourseById", req)
        val apiResp = json.decodeFromString<BykcApiResponse<BykcCourse>>(raw)
        if (!apiResp.isSuccess || apiResp.data == null)
                throw RuntimeException("BYKC queryCourseById failed: ${apiResp.errmsg}")
        return apiResp.data
    }

    /** 签到/签退 */
    suspend fun signCourse(
            courseId: Long,
            lat: Double,
            lng: Double,
            signType: Int
    ): BykcApiResponse<BykcSignResult> {
        val req =
                "{\"courseId\":$courseId,\"signLat\":$lat,\"signLng\":$lng,\"signType\":$signType}"
        val raw = callApiRaw("signCourseByUser", req)
        val apiResp = json.decodeFromString<BykcApiResponse<BykcSignResult>>(raw)
        if (!apiResp.isSuccess) {
            throw BykcException("签到失败: ${apiResp.errmsg}")
        }
        return apiResp
    }

    /** 查询课程统计信息 */
    suspend fun queryStatisticByUserId(): BykcStatisticsData {
        val raw = callApiRaw("queryStatisticByUserId", "{}")
        val apiResp = json.decodeFromString<BykcApiResponse<BykcStatisticsData>>(raw)
        if (!apiResp.isSuccess || apiResp.data == null)
                throw RuntimeException("BYKC queryStatisticByUserId failed: ${apiResp.errmsg}")
        return apiResp.data
    }
}
