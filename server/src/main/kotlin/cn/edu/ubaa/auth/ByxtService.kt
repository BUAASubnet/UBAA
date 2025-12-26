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
    private val BYXT_INDEX_URL =
            VpnCipher.toVpnUrl("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/currentUser.do")

    /** 初始化 BYXT 会话。 */
    suspend fun initializeSession(client: HttpClient) {
        log.debug("Initializing BYXT session...")
        try {
            val indexResponse = client.get(BYXT_INDEX_URL)
            log.debug(
                    "BYXT index page accessed. Status: {}, Final URL: {}",
                    indexResponse.status,
                    indexResponse.request.url
            )
        } catch (e: Exception) {
            log.error("Failed to initialize BYXT session", e)
        }
    }
}
