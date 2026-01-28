# FFmpegKit (Java side APIs and class names used by JNI)
-keep class com.arthenica.** { *; }
-keep class org.ffmpeg.** { *; }
-keep class com.github.kekdvv.** { *; }   # (group used by ffmpeg_kit_flutter_new)

# Preserve all native method signatures used by JNI
-keepclasseswithmembernames class * {
    native <methods>;
}
