package cn.edu.ubaa.auth

import kotlin.test.Test
import kotlin.test.assertFailsWith

class AuthConfigTest {

  @Test
  fun distributedLockTtlMustCoverProtectedTimeoutsWithSafetyMargin() {
    assertFailsWith<IllegalArgumentException> {
      AuthConfig.validateDistributedLockBudgets(
          distributedLockTtlMillis = 18_000L,
          loginTimeoutMillis = 18_000L,
          preloadTimeoutMillis = 3_000L,
      )
    }
  }
}
