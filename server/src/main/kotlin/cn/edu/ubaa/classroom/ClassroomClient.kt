package cn.edu.ubaa.classroom

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.model.dto.ClassroomQueryResponse
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

class ClassroomClient(private val username: String) {
    private val log = LoggerFactory.getLogger(ClassroomClient::class.java)
    private val sessionManager: SessionManager = GlobalSessionManager.instance
    private val json = Json { ignoreUnknownKeys = true }

    private val userAgent =
            "Mozilla/5.0 (Linux; Android 16; 24031PN0DC Build/BP2A.250605.031.A3; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/138.0.7204.180 Mobile Safari/537.36 XWEB/1380275 MMWEBSDK/20230806 MMWEBID/4102 wxworklocal/3.2.200 wwlocal/3.2.200 wxwork/4.0.0 appname/wxworklocal-customized wxworklocal-device-code/195ef5586d7d3c2808fcbea32d77c0d4 MicroMessenger/7.0.1 appScheme/wxworklocalcustomized Language/zh_CN ColorScheme/Light WXWorklocalClientType/Android Brand/xiaomi"

    private suspend fun ensureSession(): SessionManager.UserSession {
        return sessionManager.getSession(username)
                ?: throw IllegalStateException("No active session for $username")
    }

    suspend fun query(xqid: Int, date: String): ClassroomQueryResponse {
        val s = ensureSession()
        val client = s.client

        // 1. 访问登录链接以建立 app.buaa.edu.cn 的会话
        val loginUrl =
                "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fapp.buaa.edu.cn%2Fa_buaa%2Fapi%2Fcas%2Findex%3Fredirect%3Dhttps%253A%252F%252Fapp.buaa.edu.cn%252Fsite%252FclassRoomQuery%252Findex%26from%3Dwap%26login_from%3D&noAutoRedirect=1"
        try {
            client.get(VpnCipher.toVpnUrl(loginUrl)) { header(HttpHeaders.UserAgent, userAgent) }
        } catch (e: Exception) {
            log.warn("Failed to visit login URL, but continuing: {}", e.message)
        }

        // 2. 访问查询链接
        val queryUrl =
                "https://app.buaa.edu.cn/buaafreeclass/wap/default/search1?xqid=$xqid&floorid=&date=$date"
        val response =
                client.get(VpnCipher.toVpnUrl(queryUrl)) {
                    header(HttpHeaders.UserAgent, userAgent)
                    // 覆盖 SessionManager 中的默认 Accept
                    headers[HttpHeaders.Accept] = "application/json, text/javascript, */*; q=0.01"
                    header(
                            HttpHeaders.Referrer,
                            VpnCipher.toVpnUrl("https://app.buaa.edu.cn/site/classRoomQuery/index")
                    )
                    header("X-Requested-With", "XMLHttpRequest")
                }

        val bodyText = response.bodyAsText()
        return try {
            json.decodeFromString<ClassroomQueryResponse>(bodyText)
        } catch (e: Exception) {
            log.error("Failed to parse classroom response: {}", bodyText)
            throw e
        }
    }
}
