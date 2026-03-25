package cn.edu.ubaa.auth

import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

enum class AcademicPortalType {
  UNKNOWN,
  UNDERGRAD,
  GRADUATE,
}

enum class AcademicPortalProbeResult(val portalType: AcademicPortalType, val isReady: Boolean) {
  UNDERGRAD_READY(AcademicPortalType.UNDERGRAD, true),
  GRADUATE_READY(AcademicPortalType.GRADUATE, true),
  SSO_REQUIRED(AcademicPortalType.UNKNOWN, false),
  UNAVAILABLE(AcademicPortalType.UNKNOWN, false),
}

/** 负责探测本科 BYXT 与研究生 GSMIS 的学籍门户会话。 */
object ByxtService {
  private val log = LoggerFactory.getLogger(ByxtService::class.java)
  private val json = Json { ignoreUnknownKeys = true }
  private val UNDERGRAD_CURRENT_USER_URL =
      VpnCipher.toVpnUrl("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/currentUser.do")
  private val GRADUATE_USER_INFO_URL =
      VpnCipher.toVpnUrl(
          "https://gsmis.buaa.edu.cn/gsapp/sys/yjsemaphome/modules/pubWork/getUserInfo.do"
      )

  /** 探测当前学籍门户会话状态。本科或研究生任一门户可用即视为会话已就绪。 */
  suspend fun initializeSession(client: HttpClient): AcademicPortalProbeResult {
    log.debug("Initializing academic portal session...")
    val undergradResult = probeUndergradPortal(client)
    if (undergradResult == AcademicPortalProbeResult.UNDERGRAD_READY) {
      return undergradResult
    }
    if (undergradResult == AcademicPortalProbeResult.SSO_REQUIRED) {
      return undergradResult
    }

    val graduateResult = probeGraduatePortal(client)
    if (graduateResult.isReady) {
      return graduateResult
    }

    return if (graduateResult == AcademicPortalProbeResult.SSO_REQUIRED) {
      graduateResult
    } else {
      undergradResult
    }
  }

  fun isSessionReady(status: HttpStatusCode, finalUrl: String, body: String): Boolean {
    return classifyUndergradResponse(status, finalUrl, body) == AcademicPortalProbeResult.UNDERGRAD_READY
  }

  internal fun classifyUndergradResponse(
      status: HttpStatusCode,
      finalUrl: String,
      body: String,
  ): AcademicPortalProbeResult {
    if (isSsoRedirect(status, finalUrl, body)) return AcademicPortalProbeResult.SSO_REQUIRED
    if (status != HttpStatusCode.OK) return AcademicPortalProbeResult.UNAVAILABLE

    val trimmed = body.trimStart()
    if (finalUrl.contains("/jwapp/sys/byrhmhsy/", ignoreCase = true)) {
      return if (trimmed.startsWith("{") || trimmed.startsWith("[") || body.isBlank()) {
        AcademicPortalProbeResult.GRADUATE_READY
      } else {
        AcademicPortalProbeResult.UNAVAILABLE
      }
    }

    if (
        trimmed.startsWith("<!DOCTYPE html", ignoreCase = true) ||
            trimmed.startsWith("<html", ignoreCase = true)
    ) {
      return AcademicPortalProbeResult.UNAVAILABLE
    }

    return if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
      AcademicPortalProbeResult.UNDERGRAD_READY
    } else {
      AcademicPortalProbeResult.UNAVAILABLE
    }
  }

  internal fun classifyGraduateResponse(
      status: HttpStatusCode,
      finalUrl: String,
      body: String,
  ): AcademicPortalProbeResult {
    if (isSsoRedirect(status, finalUrl, body)) return AcademicPortalProbeResult.SSO_REQUIRED
    if (status != HttpStatusCode.OK) return AcademicPortalProbeResult.UNAVAILABLE
    if (!finalUrl.contains("gsmis.buaa.edu.cn", ignoreCase = true)) {
      return AcademicPortalProbeResult.UNAVAILABLE
    }

    return try {
      val parsed = json.decodeFromString(GraduateUserInfoResponse.serializer(), body)
      if (parsed.code == "0" && !parsed.data?.userId.isNullOrBlank()) {
        AcademicPortalProbeResult.GRADUATE_READY
      } else {
        AcademicPortalProbeResult.UNAVAILABLE
      }
    } catch (_: Exception) {
      AcademicPortalProbeResult.UNAVAILABLE
    }
  }

  private suspend fun probeUndergradPortal(client: HttpClient): AcademicPortalProbeResult {
    return try {
      val response = client.get(UNDERGRAD_CURRENT_USER_URL)
      val body = response.bodyAsText()
      val result = classifyUndergradResponse(response.status, response.request.url.toString(), body)
      log.debug(
          "Undergrad BYXT probe finished. Status: {}, Final URL: {}, Result: {}",
          response.status,
          response.request.url,
          result,
      )
      result
    } catch (e: Exception) {
      log.error("Failed to initialize undergrad BYXT session", e)
      AcademicPortalProbeResult.UNAVAILABLE
    }
  }

  private suspend fun probeGraduatePortal(client: HttpClient): AcademicPortalProbeResult {
    return try {
      val response = client.get(GRADUATE_USER_INFO_URL)
      val body = response.bodyAsText()
      val result = classifyGraduateResponse(response.status, response.request.url.toString(), body)
      log.debug(
          "Graduate GSMIS probe finished. Status: {}, Final URL: {}, Result: {}",
          response.status,
          response.request.url,
          result,
      )
      result
    } catch (e: Exception) {
      log.error("Failed to initialize graduate GSMIS session", e)
      AcademicPortalProbeResult.UNAVAILABLE
    }
  }

  private fun isSsoRedirect(status: HttpStatusCode, finalUrl: String, body: String): Boolean {
    if (status == HttpStatusCode.Unauthorized) return true
    if (finalUrl.contains("sso.buaa.edu.cn", ignoreCase = true)) return true
    val trimmed = body.trimStart()
    if (trimmed.startsWith("<!DOCTYPE html", ignoreCase = true)) {
      return body.contains("input name=\"execution\"") || body.contains("统一身份认证", ignoreCase = true)
    }
    if (trimmed.startsWith("<html", ignoreCase = true)) {
      return body.contains("input name=\"execution\"") || body.contains("统一身份认证", ignoreCase = true)
    }
    return false
  }
}

@Serializable
private data class GraduateUserInfoResponse(
    val code: String? = null,
    val data: GraduateUserInfoData? = null,
)

@Serializable private data class GraduateUserInfoData(val userId: String? = null)
