package cn.edu.ubaa.signin

import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.model.dto.SigninClassDto
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.client.request.forms.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import java.security.cert.X509Certificate
import javax.net.ssl.X509TrustManager
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*

/**
 * 课堂签到系统 (iclass) 原始 API 客户端。 负责 iclass 系统的独立登录、课堂列表获取及签到指令提交。
 *
 * @param studentId 学号。
 */
class SigninClient(private val studentId: String) {
  private val json = Json { ignoreUnknownKeys = true }

  /** 创建专用于 iclass 的 HttpClient，配置较宽松的 SSL 验证。 */
  private val client =
          HttpClient(CIO) {
            install(ContentNegotiation) { json(json) }
            install(HttpTimeout) { requestTimeoutMillis = 30000 }
            engine {
              https {
                trustManager =
                        object : X509TrustManager {
                          override fun checkClientTrusted(
                                  c: Array<out X509Certificate>?,
                                  a: String?
                          ) {}

                          override fun checkServerTrusted(
                                  c: Array<out X509Certificate>?,
                                  a: String?
                          ) {}

                          override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
                        }
              }
            }
          }

  private var userId: String? = null
  private var sessionId: String? = null
  private val loginMutex = Mutex()

  /** 执行 iclass 登录。目前 iclass 支持学号直接登录（无密码模式或特定逻辑）。 */
  private suspend fun login(): Boolean {
    if (userId != null && sessionId != null) return true
    return loginMutex.withLock {
      if (userId != null && sessionId != null) return@withLock true

      try {
        AppObservability.observeUpstreamRequest("iclass", "login") {
          val response =
                  client.get(
                          VpnCipher.toVpnUrl(
                                  "https://iclass.buaa.edu.cn:8347/app/user/login.action"
                          )
                  ) {
                    parameter("password", "")
                    parameter("phone", studentId)
                    parameter("userLevel", "1")
                    parameter("verificationType", "2")
                    parameter("verificationUrl", "")
                  }
          if (!response.status.isSuccess()) {
            markUnauthenticated()
            return@observeUpstreamRequest false
          }
          val body = response.bodyAsText()
          val jsonResponse = json.parseToJsonElement(body).jsonObject
          if (jsonResponse["STATUS"]?.jsonPrimitive?.intOrNull != 0) {
            markUnauthenticated()
            return@observeUpstreamRequest false
          }

          val result = jsonResponse["result"]?.jsonObject
          userId = result?.get("id")?.jsonPrimitive?.content
          sessionId = result?.get("sessionId")?.jsonPrimitive?.content
          userId != null && sessionId != null
        }
      } catch (_: Exception) {
        false
      }
    }
  }

  /** 获取指定日期的课程排课及签到状态。 */
  suspend fun getClasses(dateStr: String): List<SigninClassDto> {
    if (userId == null || sessionId == null) if (!login()) return emptyList()
    return try {
      AppObservability.observeUpstreamRequest("iclass", "get_today") {
        val response =
                client.get(
                        VpnCipher.toVpnUrl(
                                "https://iclass.buaa.edu.cn:8347/app/course/get_stu_course_sched.action"
                        )
                ) {
                  header("sessionId", sessionId)
                  parameter("id", userId)
                  parameter("dateStr", dateStr)
                }
        val body = response.bodyAsText()
        val result =
                json.parseToJsonElement(body).jsonObject["result"]?.jsonArray
                        ?: return@observeUpstreamRequest emptyList()
        result.map {
          val obj = it.jsonObject
          SigninClassDto(
                  courseId = obj["id"]?.jsonPrimitive?.content ?: "",
                  courseName = obj["courseName"]?.jsonPrimitive?.content ?: "",
                  classBeginTime = obj["classBeginTime"]?.jsonPrimitive?.content ?: "",
                  classEndTime = obj["classEndTime"]?.jsonPrimitive?.content ?: "",
                  signStatus = obj["signStatus"]?.jsonPrimitive?.intOrNull ?: 0,
          )
        }
      }
    } catch (_: Exception) {
      emptyList()
    }
  }

  /** 提交签到请求。 */
  suspend fun signIn(courseId: String): Pair<Boolean, String> {
    if (userId == null || sessionId == null) if (!login()) return false to "登录失败"
    return try {
      val serverTimestamp =
              AppObservability.observeUpstreamRequest("iclass", "get_timestamp") {
                client.get(
                                VpnCipher.toVpnUrl(
                                        "http://iclass.buaa.edu.cn:8081/app/common/get_timestamp.action"
                                )
                        )
                        .body<JsonObject>()
                        .get("timestamp")
                        ?.jsonPrimitive
                        ?.content
              }
                      ?: return false to "获取服务器时间失败"

      AppObservability.observeUpstreamRequest("iclass", "sign_in") {
        val response =
                client.post(
                        VpnCipher.toVpnUrl(
                                "http://iclass.buaa.edu.cn:8081/app/course/stu_scan_sign.action"
                        )
                ) {
                  parameter("courseSchedId", courseId)
                  parameter("timestamp", serverTimestamp)
                  setBody(FormDataContent(Parameters.build { append("id", userId!!) }))
                }
        val jsonResponse = json.parseToJsonElement(response.bodyAsText()).jsonObject
        val success =
                jsonResponse["STATUS"]?.jsonPrimitive?.intOrNull == 0 &&
                        jsonResponse["result"]?.jsonObject?.get("stuSignStatus")
                                ?.jsonPrimitive
                                ?.intOrNull == 1
        if (!success) {
          markError()
        }
        success to sanitizeSignInMessage(success, jsonResponse["ERRMSG"]?.jsonPrimitive?.content)
      }
    } catch (e: Exception) {
      false to "签到失败，请稍后重试"
    }
  }

  internal fun sanitizeSignInMessage(success: Boolean, rawMessage: String?): String {
    if (success) return rawMessage?.takeIf { it.isNotBlank() } ?: "签到成功"
    val message = rawMessage.orEmpty()
    return when {
      "已签到" in message -> "您今天已经签到过了"
      "未开始" in message -> "当前还未到签到时间"
      "不是上课时间" in message -> "当前不是上课时间，无法签到"
      "已结束" in message -> "本次签到已结束"
      "范围" in message -> "当前不在可签到范围内"
      "课程" in message && "不存在" in message -> "未找到对应课程，请刷新后重试"
      else -> "签到失败，请稍后重试"
    }
  }

  fun close() {
    client.close()
    userId = null
    sessionId = null
  }
}
