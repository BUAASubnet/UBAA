package cn.edu.ubaa.ubaa_flutter.platform

import android.content.Context
import android.content.ContextWrapper
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.AndroidJUnit4
import com.it_nomads.fluttersecurestorage.FlutterSecureStorage
import com.it_nomads.fluttersecurestorage.FlutterSecureStorageConfig
import com.it_nomads.fluttersecurestorage.SecurePreferencesCallback
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class SecureStorageTest {
    private val base = InstrumentationRegistry.getInstrumentation().targetContext
    private val names = listOf("FlutterSecureStorage", "FlutterSecureStorageConfiguration", "FlutterSecureKeyStorage")

    // 每项用独立的合成 SharedPreferences；原生 Keystore 也在专用应用沙箱内。
    private fun isolated(): Context {
        check(base.packageName == "cn.edu.ubaa.synthetic.materials")
        val id = java.util.UUID.randomUUID().toString()
        return object : ContextWrapper(base) {
            override fun getApplicationContext() = this
            override fun getPackageName() = "${base.packageName}.$id"
            override fun getSharedPreferences(name: String, mode: Int) =
                base.getSharedPreferences("synthetic-$id-$name", mode)
        }
    }

    private class Storage(context: Context) : FlutterSecureStorage(context) {
        private fun <T> call(action: (SecurePreferencesCallback<T>) -> Unit): T? {
            val completion = CountDownLatch(1)
            var value: T? = null
            var failure: Exception? = null
            action(object : SecurePreferencesCallback<T> {
                override fun onSuccess(result: T?) { value = result; completion.countDown() }
                override fun onError(error: Exception) { failure = error; completion.countDown() }
            })
            check(completion.await(10, TimeUnit.SECONDS)) { "安全存储原生调用超时" }
            failure?.let { throw it }
            return value
        }

        fun open(recover: Boolean = true): Exception? = try {
            call<Void> { callback ->
                initialize(FlutterSecureStorageConfig(mapOf(
                    "resetOnError" to recover.toString(), "migrateOnAlgorithmChange" to recover.toString(),
                    "keyCipherAlgorithm" to "RSA_ECB_OAEPwithSHA_256andMGF1Padding",
                    "storageCipherAlgorithm" to "AES_GCM_NoPadding",
                )), callback)
            }
            null
        } catch (error: Exception) { error }

        fun read(key: String): String? = call<String> { callback -> super.read(key, callback) }
        fun write(key: String, value: String) { call<Void> { callback -> super.write(key, value, callback) } }
    }

    @Test
    fun 全新安装无需旧算法迁移或错误重置() {
        val storage = Storage(isolated())
        assertNull(storage.open(recover = false))
        val key = storage.addPrefixToKey("synthetic-fresh")
        storage.write(key, "synthetic-value")
        assertEquals("synthetic-value", storage.read(key))
        storage.delete(key)
        assertNull(storage.read(key))
    }

    @Test
    fun 跨版本升级保留当前算法材料() {
        check(base.packageName == "cn.edu.ubaa.synthetic.materials")
        val arguments = InstrumentationRegistry.getArguments()
        val stage = arguments.getString("storageUpgradeStage")
        org.junit.Assume.assumeNotNull(stage)
        check(stage == "seed" || stage == "verify")
        val storage = Storage(base)
        assertNull(storage.open())
        val key = storage.addPrefixToKey("ubaa.synthetic.upgrade")
        if (stage == "seed") storage.write(key, "synthetic-v10-preserved")
        assertEquals("synthetic-v10-preserved", storage.read(key))
        if (stage == "verify") storage.delete(key)
    }

    @Test
    fun 全新安装首次读写成功且重开保留密文() {
        val context = isolated()
        val first = Storage(context)
        assertNull(first.open())
        val key = first.addPrefixToKey("synthetic-key")
        assertNull(first.read(key))
        first.write(key, "synthetic-value")
        val reopened = Storage(context)
        assertNull(reopened.open())
        assertEquals("synthetic-value", reopened.read(key))
        assertFalse(context.getSharedPreferences(names[0], 0).all.values.contains("synthetic-value"))
        reopened.delete(key)
        assertNull(reopened.read(key))
    }

    @Test
    fun 损坏密文清除后可以重新写入且其他材料保留() {
        val context = isolated()
        val first = Storage(context)
        assertNull(first.open())
        val key = first.addPrefixToKey("synthetic-corrupt")
        first.write(key, "synthetic-value")
        val healthy = first.addPrefixToKey("synthetic-healthy")
        first.write(healthy, "preserved")
        context.getSharedPreferences(names[0], 0).edit().putString(key, "invalid-ciphertext").commit()
        val reopened = Storage(context)
        assertNull(reopened.open())
        assertNull(reopened.read(key))
        assertFalse(context.getSharedPreferences(names[0], 0).contains(key))
        assertEquals("preserved", reopened.read(healthy))
        reopened.write(key, "recovered")
        assertEquals("recovered", reopened.read(key))
    }
}
