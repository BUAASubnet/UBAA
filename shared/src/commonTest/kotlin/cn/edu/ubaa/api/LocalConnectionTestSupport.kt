package cn.edu.ubaa.api

import kotlinx.coroutines.sync.Mutex

internal val localConnectionTestMutex = Mutex()
