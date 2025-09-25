package cn.edu.ubaa.model.dto

import kotlinx.serialization.Serializable

@Serializable
data class LoginRequest(
    val username: String,
    val password: String
)

@Serializable
data class UserData(
    val name: String,
    val schoolid: String
)
