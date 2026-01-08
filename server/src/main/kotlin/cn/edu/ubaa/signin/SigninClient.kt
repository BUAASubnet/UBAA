package cn.edu.ubaa.signin

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
import kotlinx.serialization.json.*
import org.slf4j.LoggerFactory

/**
 * 课堂签到系统 (iclass) 原始 API 客户端。 负责 iclass 系统的独立登录、课堂列表获取及签到指令提交。
 *
 * @param studentId 学号。
 */
class SigninClient(private val studentId: String) {
    private val log = LoggerFactory.getLogger(SigninClient::class.java)
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
                                    override fun getAcceptedIssuers(): Array<X509Certificate> =
                                            arrayOf()
                                }
                    }
                }
            }

    private var userId: String? = null
    private var sessionId: String? = null

    /** 执行 iclass 登录。目前 iclass 支持学号直接登录（无密码模式或特定逻辑）。 */
    private suspend fun login(): Boolean {
        try {
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
            if (!response.status.isSuccess()) return false
            val body = response.bodyAsText()
            val jsonResponse = json.parseToJsonElement(body).jsonObject
            if (jsonResponse["STATUS"]?.jsonPrimitive?.intOrNull != 0) return false

            val result = jsonResponse["result"]?.jsonObject
            userId = result?.get("id")?.jsonPrimitive?.content
            sessionId = result?.get("sessionId")?.jsonPrimitive?.content
            return userId != null && sessionId != null
        } catch (e: Exception) {
            return false
        }
    }

    /** 获取指定日期的课程排课及签到状态。 */
    suspend fun getClasses(dateStr: String): List<SigninClassDto> {
        if (userId == null || sessionId == null) if (!login()) return emptyList()
        return try {
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
                            ?: return emptyList()
            result.map {
                val obj = it.jsonObject
                SigninClassDto(
                        courseId = obj["id"]?.jsonPrimitive?.content ?: "",
                        courseName = obj["courseName"]?.jsonPrimitive?.content ?: "",
                        classBeginTime = obj["classBeginTime"]?.jsonPrimitive?.content ?: "",
                        classEndTime = obj["classEndTime"]?.jsonPrimitive?.content ?: "",
                        signStatus = obj["signStatus"]?.jsonPrimitive?.intOrNull ?: 0
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** 提交签到请求。 */
    suspend fun signIn(courseId: String): Pair<Boolean, String> {
        if (userId == null || sessionId == null) if (!login()) return false to "登录失败"
        return try {
            // iclass 签到接口采用 HTTP 8081 端口
            val response =
                    client.post(
                            VpnCipher.toVpnUrl(
                                    "http://iclass.buaa.edu.cn:8081/app/course/stu_scan_sign.action"
                            )
                    ) {
                        parameter("courseSchedId", courseId)
                        parameter("timestamp", System.currentTimeMillis().toString())
                        setBody(FormDataContent(Parameters.build { append("id", userId!!) }))
                    }
            val jsonResponse = json.parseToJsonElement(response.bodyAsText()).jsonObject
            val success =
                    jsonResponse["STATUS"]?.jsonPrimitive?.intOrNull == 0 &&
                            jsonResponse["result"]?.jsonObject?.get("stuSignStatus")
                                    ?.jsonPrimitive
                                    ?.intOrNull == 1
            success to (jsonResponse["ERRMSG"]?.jsonPrimitive?.content ?: "未知状态")
        } catch (e: Exception) {
            false to (e.message ?: "网络异常")
        }
    }
}
