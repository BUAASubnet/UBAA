# Rust通过JNI调用证书验证组件，压缩器无法自动发现调用关系。
-keep,includedescriptorclasses class org.rustls.platformverifier.** { *; }
-keepclasseswithmembernames,includedescriptorclasses class * { native <methods>; }
