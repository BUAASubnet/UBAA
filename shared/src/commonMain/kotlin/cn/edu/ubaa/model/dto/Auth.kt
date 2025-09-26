package cn.edu.ubaa.model.dto

import kotlinx.serialization.Serializable

@Serializable
data class LoginRequest(
    val username: String,
    val password: String,
    val captcha: String? = null
)

@Serializable
data class UserData(
    val name: String,
    val schoolid: String
)

@Serializable
data class LoginResponse(
    val user: UserData,
    val token: String
)

@Serializable
data class CaptchaInfo(
    val id: String,
    val type: String = "image",
    val imageUrl: String
)

@Serializable
data class CaptchaRequiredResponse(
    val captcha: CaptchaInfo,
    val message: String = "CAPTCHA verification required"
)
