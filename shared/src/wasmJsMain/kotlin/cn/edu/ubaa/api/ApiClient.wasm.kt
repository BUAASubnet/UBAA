package cn.edu.ubaa.api

import io.ktor.client.engine.*
import io.ktor.client.engine.js.*

actual fun getDefaultEngine(): HttpClientEngine = Js.create()