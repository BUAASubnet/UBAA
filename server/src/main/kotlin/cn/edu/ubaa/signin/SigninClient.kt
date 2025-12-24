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

class SigninClient(private val studentId: String) {
    private val log = LoggerFactory.getLogger(SigninClient::class.java)
    private val json = Json { ignoreUnknownKeys = true }

    private val client =
            HttpClient(CIO) {
                install(ContentNegotiation) { json(json) }
                install(HttpTimeout) {
                    requestTimeoutMillis = 30000
                    connectTimeoutMillis = 10000
                }
                engine {
                    https {
                        trustManager =
                                object : X509TrustManager {
                                    override fun checkClientTrusted(
                                            chain: Array<out X509Certificate>?,
                                            authType: String?
                                    ) {}
                                    override fun checkServerTrusted(
                                            chain: Array<out X509Certificate>?,
                                            authType: String?
                                    ) {}
                                    override fun getAcceptedIssuers(): Array<X509Certificate> =
                                            arrayOf()
                                }
                    }
                }
            }

    private var userId: String? = null
    private var sessionId: String? = null

    private suspend fun login(): Boolean {
        try {
            val response: HttpResponse =
                    client.get(VpnCipher.toVpnUrl("https://iclass.buaa.edu.cn:8346/app/user/login.action")) {
                        parameter("password", "")
                        parameter("phone", studentId)
                        parameter("userLevel", "1")
                        parameter("verificationType", "2")
                        parameter("verificationUrl", "")
                    }

            if (!response.status.isSuccess()) return false

            val body = response.bodyAsText()
            val jsonResponse = json.parseToJsonElement(body).jsonObject

            if (jsonResponse["STATUS"]?.jsonPrimitive?.intOrNull != 0) {
                log.error("Signin login failed: {}", body)
                return false
            }

            val result = jsonResponse["result"]?.jsonObject
            userId = result?.get("id")?.jsonPrimitive?.content
            sessionId = result?.get("sessionId")?.jsonPrimitive?.content

            return userId != null && sessionId != null
        } catch (e: Exception) {
            log.error("Signin login exception", e)
            return false
        }
    }

    suspend fun getClasses(dateStr: String): List<SigninClassDto> {
        if (userId == null || sessionId == null) {
            if (!login()) return emptyList()
        }

        return try {
            val response: HttpResponse =
                    client.get(
                            VpnCipher.toVpnUrl("https://iclass.buaa.edu.cn:8346/app/course/get_stu_course_sched.action")
                    ) {
                        header("sessionId", sessionId)
                        parameter("id", userId)
                        parameter("dateStr", dateStr)
                    }

            if (!response.status.isSuccess()) return emptyList()

            val body = response.bodyAsText()
            val jsonResponse = json.parseToJsonElement(body).jsonObject
            val classes = jsonResponse["result"]?.jsonArray ?: return emptyList()

            classes.map {
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
            log.error("Signin getClasses exception", e)
            emptyList()
        }
    }

    suspend fun signIn(courseId: String): Pair<Boolean, String> {
        if (userId == null || sessionId == null) {
            if (!login()) return false to "登录失败"
        }

        return try {
            val timestamp = System.currentTimeMillis()
            // 注意：签到接口使用的是 http 8081 端口
            val response: HttpResponse =
                    client.post(VpnCipher.toVpnUrl("http://iclass.buaa.edu.cn:8081/app/course/stu_scan_sign.action")) {
                        parameter("courseSchedId", courseId)
                        parameter("timestamp", timestamp.toString())
                        setBody(FormDataContent(Parameters.build { append("id", userId!!) }))
                    }

            val body = response.bodyAsText()
            val jsonResponse = json.parseToJsonElement(body).jsonObject

            val status = jsonResponse["STATUS"]?.jsonPrimitive?.intOrNull
            val result = jsonResponse["result"]?.jsonObject
            val signStatus = result?.get("stuSignStatus")?.jsonPrimitive?.intOrNull

            val success = status == 0 && signStatus == 1
            val message = jsonResponse["ERRMSG"]?.jsonPrimitive?.content ?: "未知错误"

            success to message
        } catch (e: Exception) {
            log.error("Signin signIn exception", e)
            false to (e.message ?: "网络异常")
        }
    }
}
