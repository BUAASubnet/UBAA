package cn.edu.ubaa.api.core

import io.ktor.client.engine.*
import io.ktor.client.engine.darwin.*

actual fun getDefaultEngine(): HttpClientEngine = Darwin.create()
