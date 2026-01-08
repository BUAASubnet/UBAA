package cn.edu.ubaa.signin

import cn.edu.ubaa.model.dto.SigninActionResponse
import cn.edu.ubaa.model.dto.SigninStatusResponse
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.concurrent.ConcurrentHashMap

/** 课堂签到业务服务。 管理签到系统的独立客户端会话缓存。 */
object SigninService {
  private val clientCache = ConcurrentHashMap<String, SigninClient>()

  /** 获取或创建指定学生的签到客户端。 */
  private fun getClient(studentId: String): SigninClient =
    clientCache.getOrPut(studentId) { SigninClient(studentId) }

  /** 获取今日的签到状态列表。 */
  suspend fun getTodayClasses(studentId: String): SigninStatusResponse {
    val today = LocalDate.now().format(DateTimeFormatter.ofPattern("yyyyMMdd"))
    val classes = getClient(studentId).getClasses(today)
    return SigninStatusResponse(code = 200, message = "Success", data = classes)
  }

  /** 执行签到动作。 */
  suspend fun performSignin(studentId: String, courseId: String): SigninActionResponse {
    val (success, message) = getClient(studentId).signIn(courseId)
    return SigninActionResponse(
      code = if (success) 200 else 400,
      success = success,
      message = message,
    )
  }
}
