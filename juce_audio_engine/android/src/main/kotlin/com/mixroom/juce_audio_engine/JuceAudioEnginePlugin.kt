package com.mixroom.juce_audio_engine

import android.content.Context
import android.content.res.AssetManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
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
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future

class JuceAudioEnginePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private lateinit var methodChannel: MethodChannel
  private lateinit var eventsChannel: EventChannel
  private lateinit var logsChannel: EventChannel
  private val heavyWorkExecutor: ExecutorService = Executors.newSingleThreadExecutor()
  private val mainHandler = Handler(Looper.getMainLooper())
  private var instrumentExtractionFuture: Future<*>? = null
  private lateinit var applicationContext: Context
  private lateinit var promptAnalysisService: PromptAnalysisService

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
    applicationContext = binding.applicationContext
    promptAnalysisService =
      PromptAnalysisService(
        context = binding.applicationContext,
        yamnetAssetLookupKey =
          binding.flutterAssets.getAssetFilePathBySubpath("assets/models/yamnet.onnx"),
      )

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
    instrumentExtractionFuture =
      heavyWorkExecutor.submit {
        extractInstrumentAssets(binding.applicationContext)
      }
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

  private fun packageAssetManager(context: Context): AssetManager {
    return try {
      context.createPackageContext(context.packageName, 0).assets
    } catch (_: Exception) {
      context.assets
    }
  }

  private fun currentExtractionVersion(context: Context): String {
    val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
    return packageInfo.lastUpdateTime.toString()
  }

  private fun assetExists(assetManager: AssetManager, path: String): Boolean {
    val entries = assetManager.list(path) ?: return false
    if (entries.isNotEmpty()) return true
    return try {
      assetManager.open(path).use { _ -> }
      true
    } catch (_: Exception) {
      false
    }
  }

  private fun copyAssetTree(
    assetManager: AssetManager,
    sourcePath: String,
    targetRoot: File,
    outputRelativePath: (String) -> String,
  ) {
    val entries = assetManager.list(sourcePath) ?: return
    if (entries.isEmpty()) {
      val outFile = File(targetRoot, outputRelativePath(sourcePath))
      outFile.parentFile?.mkdirs()
      assetManager.open(sourcePath).use { input ->
        FileOutputStream(outFile, false).use { output ->
          input.copyTo(output)
        }
      }
      return
    }

    for (entry in entries) {
      val child = if (sourcePath.isEmpty()) entry else "$sourcePath/$entry"
      copyAssetTree(assetManager, child, targetRoot, outputRelativePath)
    }
  }

  private fun bundledInstrumentRootDir(context: Context): File {
    return File(context.filesDir, "flutter_assets/assets/instruments")
  }

  private fun extractInstrumentAssets(context: Context): File? {
    val marker = File(context.filesDir, ".mixroom_instruments_extracted_v4")
    val extractionVersion = currentExtractionVersion(context)
    val extractedRoot = bundledInstrumentRootDir(context)
    if (
      marker.exists() &&
        marker.readText().trim() == extractionVersion &&
        extractedRoot.exists()
    ) {
      return extractedRoot
    }

    val assetManager = packageAssetManager(context)
    val targetRoot = File(context.filesDir, "flutter_assets")
    val sourceCandidates =
      listOf(
        "assets/instruments",
        "flutter_assets/assets/instruments",
      )

    val sourceRoot = sourceCandidates.firstOrNull { assetExists(assetManager, it) }
    if (sourceRoot == null) {
      Log.e("JuceAudioEngine", "Could not locate instrument asset root in packaged assets")
      return null
    }

    fun outputRelativePath(path: String): String {
      return if (path.startsWith("flutter_assets/")) {
        path.removePrefix("flutter_assets/")
      } else {
        path
      }
    }

    try {
      copyAssetTree(assetManager, sourceRoot, targetRoot, ::outputRelativePath)
      marker.writeText(extractionVersion)
      return extractedRoot
    } catch (e: IOException) {
      Log.e("JuceAudioEngine", "Failed extracting instrument assets", e)
    } catch (e: Exception) {
      Log.e("JuceAudioEngine", "Failed extracting instrument assets", e)
    }
    return null
  }

  private fun displayNameForBundledSamplePack(packSlug: String): String {
    val normalized = packSlug.trim().replace("-", "_")
    val parts =
      normalized
        .split('_')
        .map { it.trim() }
        .filter { it.isNotEmpty() }
    if (parts.isEmpty()) return "Sample Pack"
    return parts.joinToString(" ") { part ->
      val lower = part.lowercase()
      when {
        Regex("^v\\d+$").matches(lower) -> lower
        Regex("^\\d+$").matches(lower) -> lower
        lower == "cc0" -> "CC0"
        else -> lower.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
      }
    }
  }

  private fun bundledSamplePackTargetRoots(samplePacksDir: File): List<String> {
    return samplePacksDir
      .listFiles()
      ?.filter { it.isDirectory }
      ?.map { it.absolutePath }
      ?.sorted()
      ?: emptyList()
  }

  private fun extractBundledSamplePacks(context: Context): List<String> {
    val samplePacksDir = File(context.filesDir, "sample_packs")
    val marker = File(samplePacksDir, ".mixroom_sample_packs_extracted_v1")
    val extractionVersion = currentExtractionVersion(context)
    if (
      marker.exists() &&
        marker.readText().trim() == extractionVersion &&
        samplePacksDir.exists()
    ) {
      return bundledSamplePackTargetRoots(samplePacksDir)
    }

    val assetManager = packageAssetManager(context)
    val sourceCandidates =
      listOf(
        "assets/sample_packs",
        "flutter_assets/assets/sample_packs",
      )
    val sourceRoot = sourceCandidates.firstOrNull { assetExists(assetManager, it) }
    if (sourceRoot == null) {
      Log.e("JuceAudioEngine", "Could not locate sample pack asset root in packaged assets")
      return emptyList()
    }

    if (samplePacksDir.exists()) {
      samplePacksDir.deleteRecursively()
    }
    samplePacksDir.mkdirs()

    try {
      val packEntries = assetManager.list(sourceRoot)?.sorted().orEmpty()
      for (packSlug in packEntries) {
        val sourcePackRoot = "$sourceRoot/$packSlug"
        val children = assetManager.list(sourcePackRoot) ?: continue
        if (children.isEmpty()) continue
        val displayName = displayNameForBundledSamplePack(packSlug)
        val targetPackRoot = File(samplePacksDir, displayName)
        copyAssetTree(assetManager, sourcePackRoot, targetPackRoot) { path ->
          path.removePrefix("$sourcePackRoot/").removePrefix(sourcePackRoot)
        }
      }
      marker.writeText(extractionVersion)
    } catch (e: IOException) {
      Log.e("JuceAudioEngine", "Failed extracting sample packs", e)
      return emptyList()
    } catch (e: Exception) {
      Log.e("JuceAudioEngine", "Failed extracting sample packs", e)
      return emptyList()
    }

    return bundledSamplePackTargetRoots(samplePacksDir)
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

  private fun isSampledInstrumentId(instrumentId: String): Boolean {
    val normalized = instrumentId.trim().lowercase()
    return normalized.startsWith("sfz.") || normalized.startsWith("sfz_asset:")
  }

  private fun ensureInstrumentAssetsReadyIfNeeded(instrumentId: String) {
    if (!isSampledInstrumentId(instrumentId)) return
    instrumentExtractionFuture?.get()
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

  private fun normalizeRouteToken(value: String?): String {
    return value
      ?.trim()
      ?.lowercase()
      ?.replace(Regex("[^a-z0-9]+"), " ")
      ?.replace(Regex("\\s+"), " ")
      ?.trim()
      .orEmpty()
  }

  private fun namesMatch(nativeName: String?, engineName: String): Boolean {
    val left = normalizeRouteToken(nativeName)
    val right = normalizeRouteToken(engineName)
    if (left.isEmpty() || right.isEmpty()) return false
    return left == right || left.contains(right) || right.contains(left)
  }

  private fun classifyOutputRoute(device: AudioDeviceInfo?): String {
    val routeType = device?.type
    return when {
      routeType == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
          routeType == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
          routeType == AudioDeviceInfo.TYPE_LINE_ANALOG ||
          routeType == AudioDeviceInfo.TYPE_LINE_DIGITAL ||
          routeType == AudioDeviceInfo.TYPE_AUX_LINE -> "wired"
      routeType == AudioDeviceInfo.TYPE_USB_DEVICE ||
          routeType == AudioDeviceInfo.TYPE_USB_HEADSET ||
          routeType == AudioDeviceInfo.TYPE_USB_ACCESSORY ||
          routeType == AudioDeviceInfo.TYPE_DOCK -> "usb"
      routeType == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
          routeType == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
          routeType == AudioDeviceInfo.TYPE_BLE_HEADSET ||
          routeType == AudioDeviceInfo.TYPE_BLE_SPEAKER ||
          routeType == AudioDeviceInfo.TYPE_BLE_BROADCAST -> "bluetoothOutput"
      routeType == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER ||
          routeType == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE -> "speaker"
      routeType == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
      else -> "unknown"
    }
  }

  private fun isBluetoothOutputDevice(device: AudioDeviceInfo?): Boolean {
    val routeType = device?.type
    return routeType == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
      routeType == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
      routeType == AudioDeviceInfo.TYPE_BLE_HEADSET ||
      routeType == AudioDeviceInfo.TYPE_BLE_SPEAKER ||
      routeType == AudioDeviceInfo.TYPE_BLE_BROADCAST
  }

  private fun isBluetoothInput(device: AudioDeviceInfo?): Boolean {
    val routeType = device?.type
    return routeType == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
      routeType == AudioDeviceInfo.TYPE_BLE_HEADSET
  }

  @Suppress("DEPRECATION")
  private fun buildAudioRouteInfo(): Map<String, Any> {
    val juceOutputName = JuceBridge.getCurrentOutputDeviceNameJNI().trim()
    val inputName = JuceBridge.getCurrentDeviceNameJNI().trim()
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
    val inputs = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
    val matchedOutput = outputs.firstOrNull { namesMatch(it.productName?.toString(), juceOutputName) }
    val matchedInput = inputs.firstOrNull { namesMatch(it.productName?.toString(), inputName) }
    val inferredBluetoothOutput =
      outputs.firstOrNull { isBluetoothOutputDevice(it) && !it.productName.isNullOrBlank() }
    val isBluetoothA2dpActive = audioManager.isBluetoothA2dpOn
    val effectiveOutput =
      matchedOutput ?: if (isBluetoothA2dpActive) inferredBluetoothOutput else null
    val effectiveOutputName =
      effectiveOutput?.productName?.toString()?.trim()?.takeIf { it.isNotEmpty() }
        ?: juceOutputName
    return mapOf(
      "outputRouteKind" to classifyOutputRoute(effectiveOutput),
      "outputRouteName" to effectiveOutputName,
      "inputDeviceName" to inputName,
      "inputIsBluetoothHeadset" to isBluetoothInput(matchedInput),
    )
  }

  @Suppress("DEPRECATION")
  private fun normalizeAudioModeAfterRecordingStop() {
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    val previousMode = audioManager.mode
    if (previousMode != AudioManager.MODE_NORMAL) {
      audioManager.mode = AudioManager.MODE_NORMAL
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      try {
        audioManager.clearCommunicationDevice()
      } catch (_: SecurityException) {
      } catch (_: IllegalStateException) {
      }
    } else if (audioManager.isBluetoothScoOn) {
      try {
        audioManager.stopBluetoothSco()
      } catch (_: SecurityException) {
      } catch (_: IllegalStateException) {
      }
      audioManager.isBluetoothScoOn = false
    }

    Log.i(
      "JuceAudioEngine",
      "post-record normalize mode: before=$previousMode after=${audioManager.mode}",
    )
  }

  private fun hasPlaybackRoutingAnomaly(audioManager: AudioManager): Boolean {
    if (audioManager.mode != AudioManager.MODE_NORMAL) {
      return true
    }

    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S && audioManager.isBluetoothScoOn) {
      return true
    }

    return false
  }

  private fun preparePlaybackRoute(reason: String): Boolean {
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val hadRoutingAnomaly = hasPlaybackRoutingAnomaly(audioManager)
    val hasLingeringInputRoute =
      !JuceBridge.isRecordingJNI() && JuceBridge.getActiveInputChannelCountJNI() > 0
    if (hadRoutingAnomaly) {
      Log.w("JuceAudioEngine", "Recovering Android playback route: $reason")
      normalizeAudioModeAfterRecordingStop()
    }

    if (JuceBridge.isRecordingJNI()) {
      return !hadRoutingAnomaly
    }

    val outputName = JuceBridge.getCurrentOutputDeviceNameJNI().trim()
    val hasActiveOutputRoute = JuceBridge.getActiveOutputChannelCountJNI() > 0
    val shouldReopenPlaybackRoute =
      hadRoutingAnomaly || outputName.isEmpty() || !hasActiveOutputRoute || hasLingeringInputRoute
    if (!shouldReopenPlaybackRoute) {
      return true
    }

    if (hasLingeringInputRoute) {
      Log.w(
        "JuceAudioEngine",
        "Recovering playback-only route with active inputs still open: $reason",
      )
    }

    val resetOk = JuceBridge.hardResetPlaybackOnlyRouteJNI("preparePlaybackRoute:$reason")
    normalizeAudioModeAfterRecordingStop()
    return resetOk
  }

  private fun restoreBluetoothPlaybackAfterRecordingStop() {
    normalizeAudioModeAfterRecordingStop()
    JuceBridge.hardResetPlaybackOnlyRouteJNI("postRecordBluetoothReset")
    normalizeAudioModeAfterRecordingStop()
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val args = argsFrom(call)

    try {
      when (call.method) {
        "getPlatformVersion" -> {
          result.success("Android ${android.os.Build.VERSION.RELEASE}")
        }
        "initialise" -> {
          normalizeAudioModeAfterRecordingStop()
          JuceBridge.initialiseEngineJNI()
          preparePlaybackRoute("initialise")
          result.success(null)
        }
        "shutdown" -> {
          normalizeAudioModeAfterRecordingStop()
          JuceBridge.shutdownEngineJNI()
          normalizeAudioModeAfterRecordingStop()
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
          val routeReady = preparePlaybackRoute("play")
          if (routeReady) {
            JuceBridge.playJNI()
          }
          result.success(routeReady)
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
        "getEngineDiagnostics" -> {
          result.success(JuceBridge.getEngineDiagnosticsJNI())
        }
        "resetRealtimePerformanceStats" -> {
          JuceBridge.resetRealtimePerformanceStatsJNI()
          result.success(null)
        }
        "runEngineStressTest" -> {
          runHeavyTask("runEngineStressTest", result) {
            JuceBridge.runEngineStressTestJNI(
              args.intValue("clipCount", 256),
              args.intValue("blockCount", 1024),
              args.intValue("blockSize", 512),
              args.doubleValue("sampleRate", 48000.0),
            )
          }
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
              args.stringValue("clipSnapshotJson", ""),
              args.boolValue("dryClipRender", false),
            )
          }
        }
        "getExportProgress" -> {
          result.success(JuceBridge.getExportProgressJNI())
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
            val instrumentId = args.stringValue("instrumentId", "mixroom.basic_synth")
            ensureInstrumentAssetsReadyIfNeeded(instrumentId)
            JuceBridge.renderInstrumentClipJNI(
              args.stringValue("outPath"),
              instrumentId,
              args.stringValue("instrumentName", "Basic Synth"),
              args.doubleValue("bpm", 120.0),
              midiNotesFrom(args["notes"]),
              midiParamsFrom(args["params"]),
            )
          }
        }
        "renderPitchLabAudio" -> {
          runHeavyTask("renderPitchLabAudio", result) {
            @Suppress("UNCHECKED_CAST")
            val suppressed =
              args["suppressedRanges"] as? List<Map<String, Any>> ?: emptyList()
            @Suppress("UNCHECKED_CAST")
            val segments = args["segments"] as? List<Map<String, Any>> ?: emptyList()
            JuceBridge.renderPitchLabAudioJNI(
              args.stringValue("sourcePath"),
              args.stringValue("outPath"),
              args.doubleValue("trimStartMs", 0.0),
              args.doubleValue("trimEndMs", 0.0),
              args.doubleValue("sourceTimelineDurationMs", 0.0),
              args.doubleValue("outputDurationMs", 0.0),
              suppressed,
              segments,
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
          val path = args.stringValue("path")
          runHeavyTask("loadVideoAudio", result) {
            JuceBridge.loadVideoAudioJNI(path)
            null
          }
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
        "getBundledInstrumentRootPath" -> {
          instrumentExtractionFuture?.get()
          val root = bundledInstrumentRootDir(applicationContext)
          result.success(if (root.exists()) root.absolutePath else null)
        }
        "mountBundledSamplePacks" -> {
          result.success(extractBundledSamplePacks(applicationContext))
        }
        "loadMidiClip" -> {
          val clip = args.intValue("clip")
          val rowId = resolveRowId(args, 0)
          val instrumentId = args.stringValue("instrumentId", "mixroom.basic_synth")
          val instrumentName = args.stringValue("instrumentName", "Basic Synth")
          val notes = midiNotesFrom(args["notes"])
          val params = midiParamsFrom(args["params"])
          val sourceTempoBpm = args.doubleValue("sourceTempoBpm", 120.0)
          val startSec = args.doubleValue("startSec")
          val lengthSec = args.doubleValue("lengthSec")
          val inFileOffsetSec = args.doubleValue("inFileOffsetSec")
          runHeavyTask("loadMidiClip", result) {
            ensureInstrumentAssetsReadyIfNeeded(instrumentId)
            JuceBridge.loadMidiClipJNI(
              clip,
              rowId,
              instrumentId,
              instrumentName,
              notes,
              params,
              sourceTempoBpm,
              startSec,
              lengthSec,
              inFileOffsetSec,
            )
          }
        }
        "beginProjectClipLoad", "beginProjectClipLoadTransaction" -> {
          JuceBridge.beginProjectClipLoadTransactionJNI()
          result.success(null)
        }
        "endProjectClipLoad", "endProjectClipLoadTransaction" -> {
          JuceBridge.endProjectClipLoadTransactionJNI()
          result.success(null)
        }
        "beginGraphMutationBatch" -> {
          JuceBridge.beginGraphMutationBatchJNI()
          result.success(null)
        }
        "endGraphMutationBatch" -> {
          JuceBridge.endGraphMutationBatchJNI()
          result.success(null)
        }
        "updateMidiClipEvents" -> {
          val instrumentId = args.stringValue("instrumentId", "mixroom.basic_synth")
          val clip = args.intValue("clip")
          val instrumentName = args.stringValue("instrumentName", "Basic Synth")
          val notes = midiNotesFrom(args["notes"])
          val params = midiParamsFrom(args["params"])
          val sourceTempoBpm = args.doubleValue("sourceTempoBpm", 120.0)
          runHeavyTask("updateMidiClipEvents", result) {
            ensureInstrumentAssetsReadyIfNeeded(instrumentId)
            JuceBridge.updateMidiClipEventsJNI(
              clip,
              instrumentId,
              instrumentName,
              notes,
              params,
              sourceTempoBpm,
            )
          }
        }
        "setLiveMidiInputTargetClip" -> {
          result.success(JuceBridge.setLiveMidiInputTargetClipJNI(args.intValue("clip")))
        }
        "playPreviewMidiNote" -> {
          result.success(
            JuceBridge.playPreviewMidiNoteJNI(
              args.intValue("clip"),
              args.intValue("pitch", 60),
              args.floatValue("velocity", 0.9f),
              args.intValue("durationMs", 900),
            ),
          )
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
          val startSec = args.doubleValue("startSec")
          val lengthSec = args.doubleValue("lengthSec")
          val inFileOffsetSec = args.doubleValue("inFileOffsetSec")
          runHeavyTask("loadClip", result) {
            val ok = JuceBridge.loadClipJNI(
              clip,
              rowId,
              path,
              startSec,
              lengthSec,
              inFileOffsetSec,
            )
            mainHandler.post { emitPluginLoaded(clip, path, ok) }
            ok
          }
        }
        "unloadClip" -> {
          JuceBridge.unloadClipJNI(args.intValue("clip"))
          result.success(null)
        }
        "unloadClips" -> {
          val clips = (args["clips"] as? List<*>)
            ?.mapNotNull { (it as? Number)?.toInt() }
            ?.toIntArray()
            ?: IntArray(0)
          result.success(JuceBridge.unloadClipsJNI(clips))
        }
        "setClipGain" -> {
          JuceBridge.setClipGainJNI(args.intValue("clip"), args.floatValue("gain"))
          result.success(null)
        }
        "setClipExtraGainLinear" -> {
          JuceBridge.setClipExtraGainLinearJNI(args.intValue("clip"), args.floatValue("gain"))
          result.success(null)
        }
        "setClipPan" -> {
          JuceBridge.setClipPanJNI(args.intValue("clip"), args.floatValue("pan"))
          result.success(null)
        }
        "setClipFades" -> {
          JuceBridge.setClipFadesJNI(
            args.intValue("clip"),
            args.doubleValue("fadeInSec"),
            args.doubleValue("fadeOutSec"),
            args.intValue("fadeCurve"),
          )
          result.success(null)
        }
        "updateClipFadesBatch" -> {
          @Suppress("UNCHECKED_CAST")
          val updates = args["updates"] as? List<Map<String, Any>> ?: emptyList()
          result.success(JuceBridge.updateClipFadesBatchJNI(updates))
        }
        "setClipPitch" -> {
          JuceBridge.setClipPitchJNI(args.intValue("clip"), args.floatValue("semitones"))
          result.success(null)
        }
        "setClipReversed" -> {
          JuceBridge.setClipReversedJNI(
            args.intValue("clip"),
            args.boolValue("reversed"),
          )
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
        "updateClipTimelineBatch" -> {
          @Suppress("UNCHECKED_CAST")
          val updates = args["updates"] as? List<Map<String, Any>> ?: emptyList()
          result.success(JuceBridge.updateClipTimelineBatchJNI(updates))
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
        "setRowGainAutomationPoints" -> {
          JuceBridge.setRowGainAutomationPointsJNI(
            args.intValue("row"),
            (args["points"] as? List<Map<String, Any>>) ?: emptyList(),
          )
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
        "configureTrackGroups" -> {
          @Suppress("UNCHECKED_CAST")
          val groups = args["groups"] as? List<Map<String, Any>> ?: emptyList()
          JuceBridge.configureTrackGroupsJNI(groups)
          result.success(null)
        }
        "assignRowToGroup" -> {
          JuceBridge.assignRowToGroupJNI(
            args.intValue("row"),
            args.stringValue("groupId", ""),
          )
          result.success(null)
        }
        "setTrackGroupMixState" -> {
          JuceBridge.setTrackGroupMixStateJNI(
            args.stringValue("groupId"),
            args.floatValue("gain"),
            args.floatValue("pan"),
            args.boolValue("muted"),
            args.boolValue("soloed"),
          )
          result.success(null)
        }
        "setRowPanAutomationPoints" -> {
          JuceBridge.setRowPanAutomationPointsJNI(
            args.intValue("row"),
            (args["points"] as? List<Map<String, Any>>) ?: emptyList(),
          )
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
        "setMasterEffectAutomationPoints" -> {
          JuceBridge.setMasterEffectAutomationPointsJNI(
            args.intValue("effect"),
            args.stringValue("paramId"),
            args.doubleValue("min"),
            args.doubleValue("max"),
            (args["points"] as? List<Map<String, Any>>) ?: emptyList(),
          )
          result.success(null)
        }
        "clearMasterEffectAutomation" -> {
          JuceBridge.clearMasterEffectAutomationJNI()
          result.success(null)
        }
        "setMasterGainAutomationPoints" -> {
          JuceBridge.setMasterGainAutomationPointsJNI(
            (args["points"] as? List<Map<String, Any>>) ?: emptyList(),
          )
          result.success(null)
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
        "setMasterPanAutomationPoints" -> {
          JuceBridge.setMasterPanAutomationPointsJNI(
            (args["points"] as? List<Map<String, Any>>) ?: emptyList(),
          )
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
        "getRowStereoScope" -> {
          result.success(
            JuceBridge.getRowStereoScopeJNI(
              args.intValue("row"),
              args.intValue("effect"),
              args.intValue("pointCount", 256),
            ).toList(),
          )
        }
        "getMasterStereoScope" -> {
          result.success(
            JuceBridge.getMasterStereoScopeJNI(
              args.intValue("effect"),
              args.intValue("pointCount", 256),
            ).toList(),
          )
        }
        "getRowShaperPreview" -> {
          result.success(
            JuceBridge.getRowShaperPreviewJNI(
              args.intValue("row"),
              args.intValue("effect"),
              args.intValue("pointCount", 192),
            ).toList(),
          )
        }
        "getMasterShaperPreview" -> {
          result.success(
            JuceBridge.getMasterShaperPreviewJNI(
              args.intValue("effect"),
              args.intValue("pointCount", 192),
            ).toList(),
          )
        }
        "getRowDynamicSoftenerFrame" -> {
          result.success(
            JuceBridge.getRowDynamicSoftenerFrameJNI(
              args.intValue("row"),
              args.intValue("effect"),
            ).toList(),
          )
        }
        "getMasterDynamicSoftenerFrame" -> {
          result.success(
            JuceBridge.getMasterDynamicSoftenerFrameJNI(
              args.intValue("effect"),
            ).toList(),
          )
        }
        "getRowTransientShaperVisual" -> {
          result.success(
            JuceBridge.getRowTransientShaperVisualJNI(
              args.intValue("row"),
              args.intValue("effect"),
              args.intValue("pointCount", 192),
            ).toList(),
          )
        }
        "getMasterTransientShaperVisual" -> {
          result.success(
            JuceBridge.getMasterTransientShaperVisualJNI(
              args.intValue("effect"),
              args.intValue("pointCount", 192),
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
        "setMetronomeTimeSignature" -> {
          JuceBridge.setMetronomeTimeSignatureJNI(
            args.intValue("numerator"),
            args.intValue("denominator")
          )
          result.success(null)
        }
        "setMetronomeTransportMs" -> {
          JuceBridge.setMetronomeTransportMsJNI(args.doubleValue("ms"))
          result.success(null)
        }
        "decodeAudioMono16k" -> {
          try {
            result.success(JuceBridge.decodeAudioMono16kJNI(args.stringValue("path")).toList())
          } catch (t: Throwable) {
            result.error("decode_audio_mono_16k_failed", t.message, null)
          }
        }
        "decodeAudioMono16kForAnalysis" -> {
          try {
            result.success(
              JuceBridge.decodeAudioMono16kForAnalysisJNI(
                args.stringValue("path"),
                args.intValue("maxOutputSamples"),
              ).toList(),
            )
          } catch (t: Throwable) {
            result.error("decode_audio_mono_16k_analysis_failed", t.message, null)
          }
        }
        "analyzeAudioStereo16k" -> {
          result.success(JuceBridge.analyzeAudioStereo16kJNI(args.stringValue("path")))
        }
        "analyzeAudioForPrompt" -> {
          val path = args.stringValue("path")
          val trimStartMs = args.doubleValue("trimStartMs", 0.0)
          val trimEndMs = args.doubleValue("trimEndMs", -1.0)
          heavyWorkExecutor.execute {
            try {
              val analysis = promptAnalysisService.analyzeClip(
                path,
                trimStartMs,
                trimEndMs,
              )
              mainHandler.post { result.success(analysis) }
            } catch (t: Throwable) {
              mainHandler.post {
                result.error("analyze_audio_for_prompt_failed", t.message, null)
              }
            }
          }
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
        "prepareRecordingInputs" -> {
          result.success(
            JuceBridge.prepareRecordingInputsJNI(
              args.intValue("desiredInputChannels"),
              args.stringValue("reason")
            ),
          )
        }
        "refreshAudioRoute" -> {
          val reason = args.stringValue("reason")
          if (JuceBridge.isRecordingJNI()) {
            JuceBridge.refreshAudioRouteJNI(reason)
          } else {
            preparePlaybackRoute("refreshAudioRoute:$reason")
          }
          result.success(null)
        }
        "preparePlaybackRoute" -> {
          result.success(preparePlaybackRoute(args.stringValue("reason")))
        }
        "getRecordingPeak" -> {
          result.success(JuceBridge.getRecordingPeakJNI())
        }
        "getCurrentDeviceName" -> {
          result.success(JuceBridge.getCurrentDeviceNameJNI())
        }
        "getCurrentOutputDeviceName" -> {
          result.success(JuceBridge.getCurrentOutputDeviceNameJNI())
        }
        "getAudioRouteInfo" -> {
          result.success(buildAudioRouteInfo())
        }
        "setLiveInputMonitoringEnabled" -> {
          JuceBridge.setLiveInputMonitoringEnabledJNI(args.boolValue("enabled"))
          result.success(null)
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
          // Reset Android out of communication/SCO mode before JUCE tries to
          // reopen playback-only output, otherwise the reopen can latch onto
          // the degraded duplex Bluetooth route.
          normalizeAudioModeAfterRecordingStop()
          JuceBridge.stopRecordingJNI()
          normalizeAudioModeAfterRecordingStop()
          mainHandler.postDelayed({
            normalizeAudioModeAfterRecordingStop()
          }, 250L)
          result.success(null)
        }
        "stopRecordingWithoutPlaybackRestore" -> {
          JuceBridge.stopRecordingWithoutPlaybackRestoreJNI()
          normalizeAudioModeAfterRecordingStop()
          result.success(null)
        }
        "restoreBluetoothPlaybackAfterRecordingStop" -> {
          restoreBluetoothPlaybackAfterRecordingStop()
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
    promptAnalysisService.close()
    heavyWorkExecutor.shutdown()
    eventsSink = null
    logsSink = null
    sharedInstance = null
  }
}
