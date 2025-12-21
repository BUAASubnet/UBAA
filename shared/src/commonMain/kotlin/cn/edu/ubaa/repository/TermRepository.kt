package cn.edu.ubaa.repository

import cn.edu.ubaa.api.ScheduleApi
import cn.edu.ubaa.model.dto.Term
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class TermRepository(private val scheduleApi: ScheduleApi = ScheduleApi()) {
    
    private var cachedTerms: List<Term>? = null
    private val mutex = Mutex()

    suspend fun getTerms(forceRefresh: Boolean = false): Result<List<Term>> {
        if (!forceRefresh) {
            val currentCache = cachedTerms
            if (currentCache != null) {
                return Result.success(currentCache)
            }
        }

        return mutex.withLock {
            // 双重检查锁定，防止并发重复请求
            if (!forceRefresh && cachedTerms != null) {
                return Result.success(cachedTerms!!)
            }

            scheduleApi.getTerms().onSuccess { terms ->
                cachedTerms = terms
            }
        }
    }
}
