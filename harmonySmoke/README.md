# UBAA HarmonyOS Smoke

This isolated project validates the ovCompose HarmonyOS toolchain without downgrading the main UBAA Gradle build.

It follows `Tencent-TDS/ovCompose-sample` with:

- Kotlin `2.0.21-KBA-005`
- Compose Multiplatform `1.6.1-KBA-007`
- `ohosArm64` shared library output named `libkn.so`
- a minimal ArkUI host under `harmonyApp/`

On Windows, verify Gradle wiring with JDK 17:

```powershell
$env:JAVA_HOME='F:\dragonwell-17'
$env:Path="$env:JAVA_HOME\bin;$env:Path"
.\gradlew.bat tasks --group harmony
```

On a macOS host with DevEco Studio installed, build and copy the native payload:

```shell
./gradlew :composeApp:publishDebugBinariesToHarmonyApp
```

Current verification note: the KBA Kotlin/Native package used by ovCompose sample resolves on macOS hosts, but the Tencent Maven repository currently returns `404` for `kotlin-native-prebuilt-2.0.21-KBA-005-windows-x86_64.zip` and `kotlin-native-prebuilt-2.0.21-KBA-005-linux-x86_64.tar.gz`. On Windows/Linux, `tasks --all` can verify Gradle wiring, but `publishDebugBinariesToHarmonyApp` cannot link `libkn.so` until a supported host distribution is available.

The task should copy these generated files into `harmonyApp/`:

- `entry/src/main/cpp/include/libkn_api.h`
- `entry/libs/arm64-v8a/libkn.so`

Opening `harmonyApp/` in DevEco Studio is still required for device packaging and install.
