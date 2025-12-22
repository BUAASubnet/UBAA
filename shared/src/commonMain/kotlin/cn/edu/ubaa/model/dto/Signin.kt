package cn.edu.ubaa.model.dto

import kotlinx.serialization.Serializable

/** 课程签到信息 DTO */
@Serializable
data class SigninClassDto(
        val courseId: String,
        val courseName: String,
        val classBeginTime: String,
        val classEndTime: String,
        val signStatus: Int // 0: 未签到, 1: 已签到
)

/** 签到状态响应 */
@Serializable
data class SigninStatusResponse(
        val code: Int,
        val message: String,
        val data: List<SigninClassDto> = emptyList()
)

/** 签到操作响应 */
@Serializable
data class SigninActionResponse(val code: Int, val success: Boolean, val message: String)
