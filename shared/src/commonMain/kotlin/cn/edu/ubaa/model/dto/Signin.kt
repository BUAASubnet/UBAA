package cn.edu.ubaa.model.dto

import kotlinx.serialization.Serializable

/**
 * 课堂签到信息 DTO。
 *
 * @property courseId 课程 ID。
 * @property courseName 课程名称。
 * @property classBeginTime 课堂开始时间。
 * @property classEndTime 课堂结束时间。
 * @property signStatus 签到状态：0 代表未签到，1 代表已签到。
 */
@Serializable
data class SigninClassDto(
  val courseId: String,
  val courseName: String,
  val classBeginTime: String,
  val classEndTime: String,
  val signStatus: Int, // 0: 未签到, 1: 已签到
)

/**
 * 签到状态查询 API 响应。
 *
 * @property code 业务状态码。
 * @property message 提示消息。
 * @property data 签到课程列表。
 */
@Serializable
data class SigninStatusResponse(
  val code: Int,
  val message: String,
  val data: List<SigninClassDto> = emptyList(),
)

/**
 * 签到动作执行结果响应。
 *
 * @property code 状态码。
 * @property success 是否成功。
 * @property message 响应描述。
 */
@Serializable
data class SigninActionResponse(val code: Int, val success: Boolean, val message: String)
