# Kotlinx Datetime
-keep class kotlinx.datetime.** { *; }
-keepnames class kotlinx.datetime.** { *; }
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-dontwarn kotlinx.datetime.**

# General Kotlin
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# Ktor
-dontwarn io.ktor.**
-keep class io.ktor.** { *; }
-keepnames class io.ktor.** { *; }
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Coroutines
-keep class kotlinx.coroutines.** { *; }
-keepnames class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# Android classes referenced in common code but not present in Desktop JVM
-dontwarn android.util.**
-dontwarn android.os.**

# Logging
-dontwarn org.slf4j.**
-dontwarn ch.qos.logback.**

# Compose
-keep class androidx.compose.** { *; }
-dontwarn androidx.compose.**
