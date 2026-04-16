package cn.edu.ubaa.bykc

import io.github.cdimascio.dotenv.dotenv

/**
 * BYKC 调试日志开关。
 *
 * 默认全部关闭，避免把原始上游响应长期落盘；需要排查问题时再通过环境变量或 `.env`
 * 临时打开。
 */
object BykcDebugConfig {
  private val dotenv = dotenv { ignoreIfMissing = true }

  /** 是否记录解密后的原始 API 请求/响应。 */
  val rawApiLogEnabled: Boolean =
      env("BYKC_DEBUG_RAW_API_LOG")?.toBooleanStrictOrNull() ?: false

  /** 是否记录解析后的 [BykcRawCourse] 完整序列化结果。 */
  val parsedCourseLogEnabled: Boolean =
      env("BYKC_DEBUG_PARSED_COURSE_LOG")?.toBooleanStrictOrNull() ?: false

  private fun env(name: String): String? = dotenv[name] ?: System.getenv(name)
}
