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
        fun open(legacy: Boolean = false): Exception? {
            var failure: Exception? = null
            var completed = false
            initialize(FlutterSecureStorageConfig(mapOf(
                "resetOnError" to "true", "migrateOnAlgorithmChange" to "true",
                "keyCipherAlgorithm" to if (legacy) "RSA_ECB_PKCS1Padding" else "RSA_ECB_OAEPwithSHA_256andMGF1Padding",
                "storageCipherAlgorithm" to if (legacy) "AES_CBC_PKCS7Padding" else "AES_GCM_NoPadding",
            )), object : SecurePreferencesCallback<Void> {
                override fun onSuccess(result: Void?) { completed = true }
                override fun onError(error: Exception) { failure = error; completed = true }
            })
            check(completed)
            return failure
        }
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
    fun 已有旧算法材料迁移后可以重开读取() {
        val context = isolated()
        val old = Storage(context)
        assertNull(old.open(legacy = true))
        val key = old.addPrefixToKey("synthetic-legacy")
        old.write(key, "synthetic-preserved")
        val migrated = Storage(context)
        assertNull(migrated.open())
        assertEquals("synthetic-preserved", migrated.read(key))
        val reopened = Storage(context)
        assertNull(reopened.open())
        assertEquals("synthetic-preserved", reopened.read(key))
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

    @Test
    fun 旧算法迁移失败可以清空并重新初始化() {
        val context = isolated()
        val old = Storage(context)
        assertNull(old.open(legacy = true))
        val key = old.addPrefixToKey("synthetic-unreadable")
        old.write(key, "synthetic-value")
        context.getSharedPreferences(names[0], 0).edit().putString(key, "invalid-ciphertext").commit()
        val recovered = Storage(context)
        assertNull(recovered.open())
        assertNull(recovered.read(key))
        recovered.write(key, "recovered")
        assertEquals("recovered", recovered.read(key))
        val reopened = Storage(context)
        assertNull(reopened.open())
        assertEquals("recovered", reopened.read(key))
    }
}
