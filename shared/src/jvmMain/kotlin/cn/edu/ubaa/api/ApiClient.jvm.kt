package cn.edu.ubaa.api

import io.ktor.client.engine.*
import io.ktor.client.engine.cio.*

actual fun getDefaultEngine(): HttpClientEngine = CIO.create()