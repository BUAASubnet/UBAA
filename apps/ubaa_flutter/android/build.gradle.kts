import com.android.build.gradle.BaseExtension
import java.util.Properties

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
val toolVersions = Properties().apply {
    rootProject.file("../../../scripts/tools/versions.env").inputStream().use { load(it) }
}

subprojects {
    afterEvaluate {
        // 所有 Android 插件共用已安装的 SDK，避免分别下载旧版平台和 NDK。
        extensions.findByType(BaseExtension::class.java)?.apply {
            compileSdkVersion("android-${toolVersions.getProperty("ANDROID_API")}")
            buildToolsVersion = toolVersions.getProperty("ANDROID_BUILD_TOOLS")
            ndkVersion = toolVersions.getProperty("ANDROID_NDK")
            externalNativeBuild.cmake.version = toolVersions.getProperty("ANDROID_CMAKE")
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
