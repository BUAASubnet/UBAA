package cn.edu.ubaa.auth

import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import org.slf4j.LoggerFactory

/** 专门负责BYXT的会话初始化和验证。 */
object ByxtService {
    private val log = LoggerFactory.getLogger(ByxtService::class.java)
    private val BYXT_INDEX_URL = VpnCipher.toVpnUrl("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do")
    private val BYXT_USER_INFO_URL =
            VpnCipher.toVpnUrl("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/getUserInfo.do")

    /** 初始化 BYXT 会话。 */
    suspend fun initializeSession(client: HttpClient) {
        log.debug("Initializing BYXT session via SSO")
        try {
            val byxtResponse = client.get(BYXT_INDEX_URL)
            if (byxtResponse.status == HttpStatusCode.OK) {
                val body = byxtResponse.bodyAsText()
                if (body.contains("homeapp") || body.contains("首页") || body.length > 1000) {
                    log.info("BYXT session initialized successfully")
                    verifyByxtApi(client)
                } else {
                    log.warn("BYXT index.do returned 200 but content looks like a login page")
                }
            } else {
                log.warn("BYXT index.do returned unexpected status: {}", byxtResponse.status)
            }
        } catch (e: Exception) {
            log.error("Failed to initialize BYXT session", e)
        }
    }

    private suspend fun verifyByxtApi(client: HttpClient) {
        try {
            val apiResponse =
                    client.get(BYXT_USER_INFO_URL) {
                        header(HttpHeaders.Accept, "application/json, text/javascript, */*; q=0.01")
                        header("X-Requested-With", "XMLHttpRequest")
                        header(HttpHeaders.Referrer, BYXT_INDEX_URL)
                    }
            val apiBody = apiResponse.bodyAsText()
            if (apiResponse.status == HttpStatusCode.OK && apiBody.contains("\"code\":\"0\"")) {
                log.info("BYXT API access verified successfully")
            } else {
                log.warn("BYXT API verification failed: {}", apiBody.take(100))
            }
        } catch (e: Exception) {
            log.warn("Error verifying BYXT API", e)
        }
    }
}
