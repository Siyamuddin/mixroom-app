# FFmpegKit (Java side APIs and class names used by JNI)
-keep class com.arthenica.** { *; }
-keep class org.ffmpeg.** { *; }
-keep class com.github.kekdvv.** { *; }   # (group used by ffmpeg_kit_flutter_new)
# ffmpeg_kit_flutter_new_full uses the repackaged com.antonkarpenko namespace.
# Keep these classes intact so JNI registration in libffmpegkit_abidetect succeeds.
-keep class com.antonkarpenko.ffmpegkit.** { *; }

# Preserve all native method signatures used by JNI
-keepclasseswithmembernames class * {
    native <methods>;
}

# Flutter release builds still need GeneratedPluginRegistrant and plugin classes
# available for reflection/automatic registration.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class io.flutter.plugins.** { *; }
-keep class ** implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }

# MediaPipe proto symbols are referenced by optional profiler/template APIs.
# These classes are not packaged in this app build and can be safely ignored.
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate
