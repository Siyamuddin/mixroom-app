package com.mixroom.juce_audio_engine

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

import android.os.Handler
import android.os.Looper


class JuceAudioEnginePlugin: FlutterPlugin, MethodChannel.MethodCallHandler {
  private lateinit var channel: MethodChannel

  companion object {
    private var channelRef: MethodChannel? = null

    @JvmStatic
    fun sendFlutterLog(message: String) {
        channelRef?.invokeMethod("log", message)
    }

    @JvmStatic external fun setAndroidContextJNI(context: Context)


    init { 
      System.loadLibrary("juce_audio_engine") 
      Log.i("JUCE", "📍 JuceAudioEnginePlugin class loaded")
    }
  }

  override fun onAttachedToEngine(binding: FlutterPluginBinding) {
    Log.i("JUCE", "✅ setAndroidContextJNI Kotlin called")
    Log.i("JUCE", "Context class: ${binding.applicationContext::class.java.name}")
    JuceBridge.setAndroidContextJNI(binding.applicationContext)
    channel = MethodChannel(binding.binaryMessenger, "juce_audio_engine")
    channel.setMethodCallHandler(this)
    channelRef = channel

    extractPlugins(binding.applicationContext)
  }


  private fun extractPlugins(context: Context) {
    val pluginDir = File(context.filesDir, "Plugins").apply { mkdirs() }
    val assetManager = context.assets
    val pluginNames = assetManager.list("Plugins") ?: return
    for (name in pluginNames) {
      val outFile = File(pluginDir, name)
      if (!outFile.exists()) {
        assetManager.open("Plugins/$name").use { input ->
          FileOutputStream(outFile).use { output ->
            input.copyTo(output)
          }
        }
        Log.d("JuceAudioEngine", "Extracted plugin: ${outFile.absolutePath}")
      }
    }
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    // Log.i("JUCE", "✅ onmethodcall Kotlin called")
    try {
      when (call.method) {
        "getPlatformVersion" -> {
          result.success("Android ${android.os.Build.VERSION.RELEASE}")
        }
        "initialise" -> {
          // JuceBridge.initialiseEngineJNI()
          // result.success(null)
          // Handler(Looper.getMainLooper()).post {
          //     Log.i("JUCE", "🧠 initialiseEngineJNI on main thread")
            // JuceBridge.initialiseEngineJNI()
            // result.success(null)
            // Handler(Looper.getMainLooper()).post {
            //     Log.i("JUCE", "🧠 initialiseEngineJNI on main thread 2")
            JuceBridge.initialiseEngineJNI()
            result.success(null)
            // }
          // }
        }
        "shutdown" -> {
          JuceBridge.shutdownEngineJNI()
          result.success(null)
        }
        "loadTrack" -> {
          val args = call.arguments as Map<String, Any>
          JuceBridge.loadTrackJNI(args["index"] as Int, args["path"] as String)
          result.success(null)
        }
        "removeTrack" -> {
          val args = call.arguments as Map<String, Any>
          JuceBridge.removeTrackJNI(args["track"] as Int)
          result.success(null)
        }
        "getTrackEffects" -> {
          val args = call.arguments as Map<String, Any>
          result.success(JuceBridge.getTrackEffectsJNI(args["track"] as Int))
        }
        "removeEffect" -> {
          val args = call.arguments as Map<String, Any>
          JuceBridge.removeEffectJNI(args["track"] as Int, args["effect"] as Int)
          result.success(null)
        }
        "reorderEffects" -> {
          val args = call.arguments as Map<String, Any>
          JuceBridge.reorderEffectsJNI(args["track"] as Int, args["from"] as Int, args["to"] as Int)
          result.success(null)
        }
        "getCurrentPosition" -> {
          val args = call.arguments as Map<String, Any>
          result.success(JuceBridge.getCurrentPositionJNI(args["track"] as Int))
        }
        "getTrackDuration" -> {
          val args = call.arguments as Map<String, Any>
          result.success(JuceBridge.getTrackDurationJNI(args["track"] as Int))
        }
        "play" -> {
          JuceBridge.playJNI()
          result.success(null)
        }
        "pause" -> {
          JuceBridge.pauseJNI()
          result.success(null)
        }
        "seek" -> {
          val args = call.arguments as Map<String, Any>
          JuceBridge.seekJNI(args["track"] as Int, args["position"] as Double)
          result.success(null)
        }
        "insertEffect" -> {
          val args = call.arguments as Map<String, Any>
          JuceBridge.insertEffectJNI(args["track"] as Int, args["path"] as String)
          result.success(null)
        }
        "setEffect" -> {
          val args = call.arguments as Map<String, Any>
          JuceBridge.setEffectJNI(
            args["track"] as Int,
            args["pluginIndex"] as Int,
            args["paramId"] as String,
            args["value"] as Any
          )
          result.success(null)
        }
        "setTrackVolume" -> {
          val args = call.arguments as Map<String, Any>
          JuceBridge.setTrackVolumeJNI(args["track"] as Int, (args["volume"] as Double).toFloat())
          result.success(null)
        }
        "bypassPlugin" -> {
          val args = call.arguments as Map<String, Any>
          JuceBridge.bypassPluginJNI(args["track"] as Int, args["effect"] as Int, args["bypass"] as Boolean)
          result.success(null)
        }
        "bypassTrack" -> {
          val args = call.arguments as Map<String, Any>
          JuceBridge.bypassTrackJNI(args["track"] as Int, args["bypass"] as Boolean)
          result.success(null)
        }
        "getPluginParameters" -> {
          val args = call.arguments as Map<String, Any>
          val resultList = JuceBridge.getPluginParametersJNI(args["track"] as Int, args["effect"] as Int)
          result.success(resultList)
        }
        "getPluginBypassState" -> {
          val args = call.arguments as Map<String, Any>
          result.success(JuceBridge.getPluginBypassStateJNI(args["track"] as Int, args["effect"] as Int))
        }
        "scanPlugins" -> {
          result.success(JuceBridge.getAvailablePluginsJNI())
        }
        "exportMix" -> {
          val args = call.arguments as Map<String, Any>
          val output = JuceBridge.exportMixJNI(args["outPath"] as String)
          result.success(output)
        }
        "exportTrack" -> {
          val args = call.arguments as Map<String, Any>
          val output = JuceBridge.exportTrackJNI(args["track"] as Int, args["outPath"] as String)
          result.success(output)
        }
        "loadVideoAudio" -> {
          val args = call.arguments as Map<String, Any>
          JuceBridge.loadVideoAudioJNI(args["path"] as String)
          result.success(null)
        }
        "unloadVideoAudio" -> {
          JuceBridge.unloadVideoAudioJNI()
          result.success(null)
        }
        "setVideoAudioGain" -> {
          val args = call.arguments as Map<String, Any>
          // Dart sends a double; JNI wants float
          val gain = (args["gain"] as Double).toFloat()
          JuceBridge.setVideoAudioGainJNI(gain)
          result.success(null)
        }
        "seekVideoAudio" -> {
          val args = call.arguments as Map<String, Any>
          val seconds = args["seconds"] as Double
          JuceBridge.seekVideoAudioJNI(seconds)
          result.success(null)
        }
        else -> result.notImplemented()
      }
    } catch (e: Exception) {
      Log.e("JuceAudioEngine", "❌ Error in method call: ${call.method}", e)
      result.error("JUCE_ERROR", e.message, null)
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}
