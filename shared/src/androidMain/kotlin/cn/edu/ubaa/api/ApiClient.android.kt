package cn.edu.ubaa.api

import io.ktor.client.engine.*
import io.ktor.client.engine.okhttp.*

actual fun getDefaultEngine(): HttpClientEngine = OkHttp.create()