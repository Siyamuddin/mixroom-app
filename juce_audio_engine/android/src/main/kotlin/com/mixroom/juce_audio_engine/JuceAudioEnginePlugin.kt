package com.mixroom.juce_audio_engine

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class JuceAudioEnginePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private lateinit var methodChannel: MethodChannel
  private lateinit var eventsChannel: EventChannel
  private lateinit var logsChannel: EventChannel
  private val heavyWorkExecutor: ExecutorService = Executors.newSingleThreadExecutor()
  private val mainHandler = Handler(Looper.getMainLooper())

  private var eventsSink: EventChannel.EventSink? = null
  private var logsSink: EventChannel.EventSink? = null

  companion object {
    private var sharedInstance: JuceAudioEnginePlugin? = null

    @JvmStatic
    fun sendFlutterLog(message: String) {
      sharedInstance?.emitLog(message)
    }

    @JvmStatic
    external fun setAndroidContextJNI(context: Context)

    init {
      System.loadLibrary("juce_audio_engine")
      Log.i("JUCE", "JuceAudioEnginePlugin class loaded")
    }
  }

  override fun onAttachedToEngine(binding: FlutterPluginBinding) {
    sharedInstance = this

    JuceBridge.setAndroidContextJNI(binding.applicationContext)

    methodChannel = MethodChannel(binding.binaryMessenger, "juce_audio_engine")
    methodChannel.setMethodCallHandler(this)

    eventsChannel = EventChannel(binding.binaryMessenger, "juce_audio_engine/events")
    eventsChannel.setStreamHandler(
      object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
          eventsSink = events
        }

        override fun onCancel(arguments: Any?) {
          eventsSink = null
        }
      },
    )

    logsChannel = EventChannel(binding.binaryMessenger, "juce_audio_engine/logs")
    logsChannel.setStreamHandler(
      object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
          logsSink = events
        }

        override fun onCancel(arguments: Any?) {
          logsSink = null
        }
      },
    )

    extractPlugins(binding.applicationContext)
    extractInstrumentAssets(binding.applicationContext)
    JuceBridge.setFlutterAssetRootJNI(binding.applicationContext.filesDir.absolutePath)
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

  private fun extractInstrumentAssets(context: Context) {
    val marker = File(context.filesDir, ".mixroom_instruments_extracted_v1")
    if (marker.exists()) return

    val root = "assets/instruments"
    val targetRoot = File(context.filesDir, "flutter_assets")

    fun copyAssetTree(path: String) {
      val entries = context.assets.list(path) ?: return
      if (entries.isEmpty()) {
        val outFile = File(targetRoot, path)
        outFile.parentFile?.mkdirs()
        if (!outFile.exists() || outFile.length() == 0L) {
          context.assets.open(path).use { input ->
            FileOutputStream(outFile).use { output ->
              input.copyTo(output)
            }
          }
        }
        return
      }

      for (entry in entries) {
        val child = if (path.isEmpty()) entry else "$path/$entry"
        copyAssetTree(child)
      }
    }

    try {
      copyAssetTree(root)
      marker.writeText("ok")
    } catch (e: Exception) {
      Log.e("JuceAudioEngine", "Failed extracting instrument assets", e)
    }
  }

  private fun emitLog(message: String) {
    logsSink?.success(mapOf("message" to message))
  }

  private fun emitPluginLoaded(track: Int, path: String, success: Boolean) {
    eventsSink?.success(
      mapOf(
        "event" to "pluginLoaded",
        "track" to track,
        "path" to path,
        "success" to success,
      ),
    )
  }

  private fun Map<String, Any?>.intValue(key: String, default: Int = 0): Int {
    val raw = this[key]
    return when (raw) {
      is Int -> raw
      is Long -> raw.toInt()
      is Double -> raw.toInt()
      is Float -> raw.toInt()
      is Short -> raw.toInt()
      is Byte -> raw.toInt()
      is String -> raw.toIntOrNull() ?: default
      else -> default
    }
  }

  private fun Map<String, Any?>.doubleValue(key: String, default: Double = 0.0): Double {
    val raw = this[key]
    return when (raw) {
      is Double -> raw
      is Float -> raw.toDouble()
      is Int -> raw.toDouble()
      is Long -> raw.toDouble()
      is Short -> raw.toDouble()
      is Byte -> raw.toDouble()
      is String -> raw.toDoubleOrNull() ?: default
      else -> default
    }
  }

  private fun Map<String, Any?>.floatValue(key: String, default: Float = 0.0f): Float {
    return doubleValue(key, default.toDouble()).toFloat()
  }

  private fun Map<String, Any?>.boolValue(key: String, default: Boolean = false): Boolean {
    val raw = this[key]
    return when (raw) {
      is Boolean -> raw
      is Number -> raw.toInt() != 0
      is String -> raw.equals("true", ignoreCase = true) || raw == "1"
      else -> default
    }
  }

  private fun Map<String, Any?>.stringValue(key: String, default: String = ""): String {
    val raw = this[key]
    return if (raw is String) raw else default
  }

  private fun argsFrom(call: MethodCall): Map<String, Any?> {
    val args = call.arguments as? Map<*, *> ?: return emptyMap()
    return args.entries.associate { (k, v) -> k.toString() to v }
  }

  private fun midiNotesFrom(raw: Any?): List<Map<String, Any>> {
    val list = raw as? List<*> ?: return emptyList()
    return list.mapNotNull { entry ->
      val map = entry as? Map<*, *> ?: return@mapNotNull null
      val out = mutableMapOf<String, Any>()
      map.forEach { (k, v) ->
        if (k != null && v != null) out[k.toString()] = v
      }
      out
    }
  }

  private fun mapListFrom(raw: Any?): List<Map<String, Any>> {
    val list = raw as? List<*> ?: return emptyList()
    return list.mapNotNull { entry ->
      val map = entry as? Map<*, *> ?: return@mapNotNull null
      val out = mutableMapOf<String, Any>()
      map.forEach { (k, v) ->
        if (k != null && v != null) out[k.toString()] = v
      }
      out
    }
  }

  private fun midiParamsFrom(raw: Any?): Map<String, Double> {
    val map = raw as? Map<*, *> ?: return emptyMap()
    val out = mutableMapOf<String, Double>()
    map.forEach { (k, v) ->
      val key = k?.toString() ?: return@forEach
      val num = when (v) {
        is Number -> v.toDouble()
        is String -> v.toDoubleOrNull()
        else -> null
      } ?: return@forEach
      out[key] = num
    }
    return out
  }

  private fun resolveRowId(args: Map<String, Any?>, default: Int = 0): Int {
    var rowId = args.intValue("rowId", default)
    if (args.containsKey("row")) {
      rowId = args.intValue("row", rowId)
    }
    return rowId
  }

  private fun <T> runHeavyTask(
    taskName: String,
    result: MethodChannel.Result,
    task: () -> T,
  ) {
    heavyWorkExecutor.execute {
      try {
        val output = task()
        mainHandler.post { result.success(output) }
      } catch (e: Exception) {
        Log.e("JuceAudioEngine", "Error during $taskName", e)
        mainHandler.post { result.error("JUCE_ERROR", e.message, null) }
      }
    }
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val args = argsFrom(call)

    try {
      when (call.method) {
        "getPlatformVersion" -> {
          result.success("Android ${android.os.Build.VERSION.RELEASE}")
        }
        "initialise" -> {
          JuceBridge.initialiseEngineJNI()
          result.success(null)
        }
        "shutdown" -> {
          JuceBridge.shutdownEngineJNI()
          result.success(null)
        }
        "loadTrack" -> {
          val index = args.intValue("index")
          val path = args.stringValue("path")
          JuceBridge.loadTrackJNI(index, path)
          emitPluginLoaded(index, path, true)
          result.success(null)
        }
        "removeTrack" -> {
          JuceBridge.removeTrackJNI(args.intValue("track"))
          result.success(null)
        }
        "getTrackEffects" -> {
          result.success(JuceBridge.getTrackEffectsJNI(args.intValue("track")))
        }
        "removeEffect" -> {
          JuceBridge.removeEffectJNI(args.intValue("track"), args.intValue("effect"))
          result.success(null)
        }
        "reorderEffects" -> {
          JuceBridge.reorderEffectsJNI(
            args.intValue("track"),
            args.intValue("from"),
            args.intValue("to"),
          )
          result.success(null)
        }
        "seek" -> {
          JuceBridge.seekJNI(args.intValue("track"), args.doubleValue("position"))
          result.success(null)
        }
        "getCurrentPosition" -> {
          result.success(JuceBridge.getCurrentPositionJNI(args.intValue("track")))
        }
        "getTrackDuration" -> {
          result.success(JuceBridge.getTrackDurationJNI(args.intValue("track")))
        }
        "play" -> {
          JuceBridge.playJNI()
          result.success(null)
        }
        "pause" -> {
          JuceBridge.pauseJNI()
          result.success(null)
        }
        "insertEffect" -> {
          val track = args.intValue("track")
          val path = args.stringValue("path")
          JuceBridge.insertEffectJNI(track, path)
          emitPluginLoaded(track, path, true)
          result.success(null)
        }
        "setEffect" -> {
          val value = args["value"]
          if (value != null) {
            JuceBridge.setEffectJNI(
              args.intValue("track"),
              args.intValue("pluginIndex"),
              args.stringValue("paramId"),
              value,
            )
          }
          result.success(null)
        }
        "setTrackVolume" -> {
          JuceBridge.setTrackVolumeJNI(
            args.intValue("track"),
            args.floatValue("volume"),
          )
          result.success(null)
        }
        "getPluginParameters" -> {
          result.success(
            JuceBridge.getPluginParametersJNI(
              args.intValue("track"),
              args.intValue("effect"),
            ),
          )
        }
        "getTrackPluginParameters" -> {
          result.success(
            JuceBridge.getTrackPluginParametersJNI(
              args.intValue("row"),
              args.intValue("effect"),
            ),
          )
        }
        "getMasterPluginParameters" -> {
          result.success(
            JuceBridge.getMasterPluginParametersJNI(
              args.intValue("effect"),
            ),
          )
        }
        "scanPlugins" -> {
          result.success(JuceBridge.getAvailablePluginsJNI())
        }
        "getEngineCapabilities" -> {
          result.success(
            mapOf(
              "externalPluginHosting" to false,
              "supportedPluginFormats" to emptyList<String>(),
              "nativePluginEditor" to false,
            ),
          )
        }
        "exportMix" -> {
          runHeavyTask("exportMix", result) {
            JuceBridge.exportMixJNI(
              args.stringValue("outPath"),
              args.stringValue("format", "wav"),
              (args["sampleRate"] as? Number)?.toInt() ?: 44100,
              (args["wavBitDepth"] as? Number)?.toInt() ?: 16,
              args.boolValue("wavDithering", true),
              (args["mp3BitrateKbps"] as? Number)?.toInt() ?: 192,
            )
          }
        }
        "exportTrack" -> {
          runHeavyTask("exportTrack", result) {
            JuceBridge.exportTrackJNI(
              args.intValue("track"),
              args.stringValue("outPath"),
              args.stringValue("format", "wav"),
              (args["sampleRate"] as? Number)?.toInt() ?: 44100,
              (args["wavBitDepth"] as? Number)?.toInt() ?: 16,
              args.boolValue("wavDithering", true),
              (args["mp3BitrateKbps"] as? Number)?.toInt() ?: 192,
            )
          }
        }
        "renderInstrumentClip" -> {
          runHeavyTask("renderInstrumentClip", result) {
            JuceBridge.renderInstrumentClipJNI(
              args.stringValue("outPath"),
              args.stringValue("instrumentId", "mixroom.basic_synth"),
              args.stringValue("instrumentName", "Basic Synth"),
              args.doubleValue("bpm", 120.0),
              midiNotesFrom(args["notes"]),
              midiParamsFrom(args["params"]),
            )
          }
        }
        "bypassPlugin" -> {
          JuceBridge.bypassPluginJNI(
            args.intValue("track"),
            args.intValue("effect"),
            args.boolValue("bypass"),
          )
          result.success(null)
        }
        "bypassTrack" -> {
          JuceBridge.bypassTrackJNI(
            args.intValue("track"),
            args.boolValue("bypass"),
          )
          result.success(null)
        }
        "getPluginBypassState" -> {
          result.success(
            JuceBridge.getPluginBypassStateJNI(
              args.intValue("track"),
              args.intValue("effect"),
            ),
          )
        }
        "_internalLog" -> {
          result.success("testing blabla success")
        }
        "loadVideoAudio" -> {
          JuceBridge.loadVideoAudioJNI(args.stringValue("path"))
          result.success(null)
        }
        "unloadVideoAudio" -> {
          JuceBridge.unloadVideoAudioJNI()
          result.success(null)
        }
        "setVideoAudioGain" -> {
          JuceBridge.setVideoAudioGainJNI(args.floatValue("gain"))
          result.success(null)
        }
        "seekVideoAudio" -> {
          JuceBridge.seekVideoAudioJNI(args.doubleValue("seconds"))
          result.success(null)
        }
        "supportsLiveMidiClipPlayback" -> {
          result.success(JuceBridge.supportsLiveMidiClipPlaybackJNI())
        }
        "loadMidiClip" -> {
          val clip = args.intValue("clip")
          val rowId = resolveRowId(args, 0)
          val ok = JuceBridge.loadMidiClipJNI(
            clip,
            rowId,
            args.stringValue("instrumentId", "mixroom.basic_synth"),
            args.stringValue("instrumentName", "Basic Synth"),
            midiNotesFrom(args["notes"]),
            midiParamsFrom(args["params"]),
            args.doubleValue("sourceTempoBpm", 120.0),
            args.doubleValue("startSec"),
            args.doubleValue("lengthSec"),
            args.doubleValue("inFileOffsetSec"),
          )
          result.success(ok)
        }
        "updateMidiClipEvents" -> {
          val ok = JuceBridge.updateMidiClipEventsJNI(
            args.intValue("clip"),
            args.stringValue("instrumentId", "mixroom.basic_synth"),
            args.stringValue("instrumentName", "Basic Synth"),
            midiNotesFrom(args["notes"]),
            midiParamsFrom(args["params"]),
            args.doubleValue("sourceTempoBpm", 120.0),
          )
          result.success(ok)
        }
        "setLiveMidiInputTargetClip" -> {
          result.success(JuceBridge.setLiveMidiInputTargetClipJNI(args.intValue("clip")))
        }
        "consumeLiveMidiInputEvents" -> {
          result.success(JuceBridge.consumeLiveMidiInputEventsJNI())
        }
        "getConnectedMidiInputDevices" -> {
          result.success(JuceBridge.getConnectedMidiInputDevicesJNI())
        }
        "loadClip" -> {
          val clip = args.intValue("clip")
          val rowId = resolveRowId(args, 0)
          val path = args.stringValue("path")
          JuceBridge.loadClipJNI(
            clip,
            rowId,
            path,
            args.doubleValue("startSec"),
            args.doubleValue("lengthSec"),
            args.doubleValue("inFileOffsetSec"),
          )
          emitPluginLoaded(clip, path, true)
          result.success(null)
        }
        "unloadClip" -> {
          JuceBridge.unloadClipJNI(args.intValue("clip"))
          result.success(null)
        }
        "setClipGain" -> {
          JuceBridge.setClipGainJNI(args.intValue("clip"), args.floatValue("gain"))
          result.success(null)
        }
        "setClipPan" -> {
          JuceBridge.setClipPanJNI(args.intValue("clip"), args.floatValue("pan"))
          result.success(null)
        }
        "setClipPitch" -> {
          JuceBridge.setClipPitchJNI(args.intValue("clip"), args.floatValue("semitones"))
          result.success(null)
        }
        "setClipStretchOptions" -> {
          JuceBridge.setClipStretchOptionsJNI(
            args.intValue("clip"),
            args.doubleValue("tempoRatio", 1.0),
            args.boolValue("preservePitch", true),
          )
          result.success(null)
        }
        "muteClip" -> {
          JuceBridge.muteClipJNI(args.intValue("clip"), args.boolValue("mute"))
          result.success(null)
        }
        "moveClipToRow" -> {
          JuceBridge.moveClipToRowJNI(args.intValue("clip"), resolveRowId(args, 0))
          result.success(null)
        }
        "setClipTime" -> {
          JuceBridge.setClipTimeJNI(
            args.intValue("clip"),
            args.doubleValue("startSec"),
            args.doubleValue("lengthSec"),
            args.doubleValue("inFileOffsetSec"),
          )
          result.success(null)
        }
        "addRow" -> {
          result.success(
            JuceBridge.addRowJNI(
              args.stringValue("name", "Row"),
              args.intValue("iconId"),
            ),
          )
        }
        "insertRowAbove" -> {
          result.success(
            JuceBridge.insertRowAboveJNI(
              args.intValue("referenceRowId"),
              args.stringValue("name", "Row"),
              args.intValue("iconId"),
            ),
          )
        }
        "insertRowBelow" -> {
          result.success(
            JuceBridge.insertRowBelowJNI(
              args.intValue("referenceRowId"),
              args.stringValue("name", "Row"),
              args.intValue("iconId"),
            ),
          )
        }
        "deleteRow", "removeRow" -> {
          result.success(JuceBridge.removeRowJNI(resolveRowId(args, -1)))
        }
        "moveRowOrder" -> {
          result.success(JuceBridge.moveRowOrderJNI(args.intValue("from"), args.intValue("to")))
        }
        "renameRow" -> {
          result.success(
            JuceBridge.renameRowJNI(
              resolveRowId(args, -1),
              args.stringValue("name", "Row"),
            ),
          )
        }
        "setRowIcon" -> {
          result.success(
            JuceBridge.setRowIconJNI(
              resolveRowId(args, -1),
              args.intValue("iconId"),
            ),
          )
        }
        "getRowList", "getRows" -> {
          result.success(JuceBridge.getRowsJNI())
        }
        "setTransportSeconds" -> {
          JuceBridge.setTransportSecondsJNI(args.doubleValue("timeSeconds"))
          result.success(null)
        }
        "getTransportSeconds" -> {
          result.success(JuceBridge.getTransportSecondsJNI())
        }
        "seekTransport" -> {
          JuceBridge.setTransportSecondsJNI(args.doubleValue("timeSeconds"))
          result.success(null)
        }
        "insertTrackEffect" -> {
          val ok = JuceBridge.insertTrackEffectJNI(
            args.intValue("row"),
            args.stringValue("path"),
          )
          result.success(ok)
        }
        "removeTrackEffect" -> {
          JuceBridge.removeTrackEffectJNI(
            args.intValue("row"),
            args.intValue("effect"),
          )
          result.success(null)
        }
        "reorderTrackEffects" -> {
          JuceBridge.reorderTrackEffectsJNI(
            args.intValue("row"),
            args.intValue("from"),
            args.intValue("to"),
          )
          result.success(null)
        }
        "getTrackEffectsForRow" -> {
          result.success(JuceBridge.getTrackEffectsForRowJNI(args.intValue("row")))
        }
        "getTrackEffectIdsForRow" -> {
          result.success(JuceBridge.getTrackEffectIdsForRowJNI(args.intValue("row")))
        }
        "getTrackEffectInstanceIdsForRow" -> {
          result.success(JuceBridge.getTrackEffectInstanceIdsForRowJNI(args.intValue("row")))
        }
        "setTrackEffect" -> {
          val value = args["value"]
          if (value != null) {
            JuceBridge.setTrackEffectJNI(
              args.intValue("row"),
              args.intValue("effect"),
              args.stringValue("paramId"),
              value,
            )
          }
          result.success(null)
        }
        "bypassRowEffect" -> {
          JuceBridge.bypassRowEffectJNI(
            args.intValue("row"),
            args.intValue("effect"),
            args.boolValue("bypass"),
          )
          result.success(null)
        }
        "getRowEffectBypassState" -> {
          result.success(
            JuceBridge.getRowEffectBypassStateJNI(
              args.intValue("row"),
              args.intValue("effect"),
            ),
          )
        }
        "setTrackAutomationPoints" -> {
          JuceBridge.setTrackAutomationPointsJNI(
            args.intValue("row"),
            mapListFrom(args["points"]),
          )
          result.success(null)
        }
        "setTrackEffectAutomationPoints" -> {
          JuceBridge.setTrackEffectAutomationPointsJNI(
            args.intValue("row"),
            args.intValue("effect"),
            args.stringValue("paramId"),
            args.doubleValue("min", 0.0),
            args.doubleValue("max", 1.0),
            mapListFrom(args["points"]),
          )
          result.success(null)
        }
        "clearTrackEffectAutomationForRow" -> {
          JuceBridge.clearTrackEffectAutomationForRowJNI(args.intValue("row"))
          result.success(null)
        }
        "setRowGain" -> {
          JuceBridge.setRowGainJNI(args.intValue("row"), args.floatValue("gain"))
          result.success(null)
        }
        "muteRow" -> {
          JuceBridge.muteRowJNI(args.intValue("row"), args.boolValue("mute"))
          result.success(null)
        }
        "isRowMuted" -> {
          result.success(JuceBridge.isRowMutedJNI(args.intValue("row")))
        }
        "setRowPan" -> {
          JuceBridge.setRowPanJNI(args.intValue("row"), args.floatValue("pan"))
          result.success(null)
        }
        "insertMasterEffect" -> {
          result.success(JuceBridge.insertMasterEffectJNI(args.stringValue("path")))
        }
        "removeMasterEffect" -> {
          JuceBridge.removeMasterEffectJNI(args.intValue("effect"))
          result.success(null)
        }
        "reorderMasterEffects" -> {
          JuceBridge.reorderMasterEffectsJNI(args.intValue("from"), args.intValue("to"))
          result.success(null)
        }
        "getMasterEffects" -> {
          result.success(JuceBridge.getMasterEffectsJNI())
        }
        "getMasterEffectIds" -> {
          result.success(JuceBridge.getMasterEffectIdsJNI())
        }
        "setMasterEffect" -> {
          val value = args["value"]
          if (value != null) {
            JuceBridge.setMasterEffectJNI(
              args.intValue("effect"),
              args.stringValue("paramId"),
              value,
            )
          }
          result.success(null)
        }
        "bypassMasterEffect" -> {
          JuceBridge.bypassMasterEffectJNI(
            args.intValue("effect"),
            args.boolValue("bypass"),
          )
          result.success(null)
        }
        "getMasterEffectBypassState" -> {
          result.success(JuceBridge.getMasterEffectBypassStateJNI(args.intValue("effect")))
        }
        "setMasterGain" -> {
          JuceBridge.setMasterGainJNI(args.floatValue("gain"))
          result.success(null)
        }
        "muteMaster" -> {
          JuceBridge.muteMasterJNI(args.boolValue("mute"))
          result.success(null)
        }
        "setMasterPan" -> {
          JuceBridge.setMasterPanJNI(args.floatValue("pan"))
          result.success(null)
        }
        "setMasterMeterEnabled" -> {
          JuceBridge.setMasterMeterEnabledJNI(args.boolValue("enabled"))
          result.success(null)
        }
        "getMasterMeterValues" -> {
          result.success(JuceBridge.getMasterMeterValuesJNI().toList())
        }
        "getMasterClipLatched" -> {
          result.success(JuceBridge.getMasterClipLatchedJNI())
        }
        "clearMasterClipLatched" -> {
          JuceBridge.clearMasterClipLatchedJNI()
          result.success(null)
        }
        "setRowMetersEnabled" -> {
          JuceBridge.setRowMetersEnabledJNI(args.boolValue("enabled"))
          result.success(null)
        }
        "getRowMeterValues" -> {
          result.success(JuceBridge.getRowMeterValuesJNI(args.intValue("row")).toList())
        }
        "getAllMeterValues" -> {
          result.success(JuceBridge.getAllMeterValuesJNI().toList())
        }
        "getClipCompressorMeter" -> {
          result.success(
            JuceBridge.getTrackCompressorMeterJNI(
              args.intValue("clip"),
              args.intValue("effect"),
            ).toList(),
          )
        }
        "getRowCompressorMeter" -> {
          result.success(
            JuceBridge.getRowCompressorMeterJNI(
              args.intValue("row"),
              args.intValue("effect"),
            ).toList(),
          )
        }
        "getMasterCompressorMeter" -> {
          result.success(
            JuceBridge.getMasterCompressorMeterJNI(
              args.intValue("effect"),
            ).toList(),
          )
        }
        "getHostSampleRate" -> {
          result.success(JuceBridge.getHostSampleRateJNI())
        }
        "getRowEqWaveform" -> {
          result.success(
            JuceBridge.getRowEqWaveformJNI(
              args.intValue("row"),
              args.intValue("effect"),
              args.intValue("sampleCount", 1024),
            ).toList(),
          )
        }
        "getMasterEqWaveform" -> {
          result.success(
            JuceBridge.getMasterEqWaveformJNI(
              args.intValue("effect"),
              args.intValue("sampleCount", 1024),
            ).toList(),
          )
        }
        "setAutomationTransport" -> {
          JuceBridge.setAutomationTransportJNI(args.doubleValue("timeSeconds"))
          result.success(null)
        }
        "debugPrintGraph" -> {
          JuceBridge.debugPrintGraphJNI(args.stringValue("title", "(no title)"))
          result.success(null)
        }
        "debugPrintGraphStructure" -> {
          JuceBridge.debugPrintGraphStructureJNI()
          result.success(null)
        }
        "setMetronomeEnabled" -> {
          JuceBridge.setMetronomeEnabledJNI(args.boolValue("enabled"))
          result.success(null)
        }
        "setMetronomeVolume" -> {
          JuceBridge.setMetronomeVolumeJNI(args.floatValue("volume"))
          result.success(null)
        }
        "setMetronomeBpm" -> {
          JuceBridge.setMetronomeBpmJNI(args.doubleValue("bpm"))
          result.success(null)
        }
        "setMetronomeTransportMs" -> {
          JuceBridge.setMetronomeTransportMsJNI(args.doubleValue("ms"))
          result.success(null)
        }
        "decodeAudioMono16k" -> {
          result.success(JuceBridge.decodeAudioMono16kJNI(args.stringValue("path")).toList())
        }
        "analyzeAudioStereo16k" -> {
          result.success(JuceBridge.analyzeAudioStereo16kJNI(args.stringValue("path")))
        }
        "getInputDevices" -> {
          result.success(JuceBridge.getInputDevicesJNI())
        }
        "selectInputDevice" -> {
          result.success(JuceBridge.selectInputDeviceJNI(args.stringValue("name")))
        }
        "getNumInputChannels" -> {
          result.success(JuceBridge.getNumInputChannelsJNI())
        }
        "getRecordingPeak" -> {
          result.success(JuceBridge.getRecordingPeakJNI())
        }
        "getCurrentDeviceName" -> {
          result.success(JuceBridge.getCurrentDeviceNameJNI())
        }
        "startRecording" -> {
          result.success(
            JuceBridge.startRecordingJNI(
              args.stringValue("path"),
              args.intValue("channelStart"),
              args.intValue("channelCount"),
            ),
          )
        }
        "stopRecording" -> {
          JuceBridge.stopRecordingJNI()
          result.success(null)
        }
        "isRecording" -> {
          result.success(JuceBridge.isRecordingJNI())
        }
        else -> result.notImplemented()
      }
    } catch (e: Exception) {
      Log.e("JuceAudioEngine", "Error in method call: ${call.method}", e)
      result.error("JUCE_ERROR", e.message, null)
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)
    eventsChannel.setStreamHandler(null)
    logsChannel.setStreamHandler(null)
    heavyWorkExecutor.shutdown()
    eventsSink = null
    logsSink = null
    sharedInstance = null
  }
}
