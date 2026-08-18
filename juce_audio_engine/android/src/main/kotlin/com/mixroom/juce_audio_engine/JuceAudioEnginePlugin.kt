package com.mixroom.juce_audio_engine

import android.content.Context
import android.content.res.AssetManager
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.AudioPlaybackConfiguration
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.time.Instant
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class JuceAudioEnginePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private enum class EngineOwnership { NONE, LEGACY, V2_SESSION }
  private enum class AudioRouteIntentV2 { PLAYBACK_ONLY, PREPARING_RECORDING, RECORDING }
  private enum class IntentOperationModeV2 { STANDARD, SYSTEM_SELECTED_PROBE }

  private enum class AndroidStreamPolicyV2(val nativeValue: Int) {
    NORMAL(0),
    BLUETOOTH_MEDIA(1),
    BLUETOOTH_COMMUNICATION_DUPLEX(2),
  }

  private data class RecordingOperationV2(
    val id: Long,
    val generation: Long,
    val sourceOutput: AndroidRouteEndpointV2,
    val mode: IntentOperationModeV2 = IntentOperationModeV2.STANDARD,
    val startedNanos: Long = SystemClock.elapsedRealtimeNanos(),
    val cancelled: AtomicBoolean = AtomicBoolean(false),
    val routeInvalidated: AtomicBoolean = AtomicBoolean(false),
    val cleanupClaimed: AtomicBoolean = AtomicBoolean(false),
    @Volatile var verifiedInput: AndroidRouteEndpointV2? = null,
    @Volatile var verifiedOutput: AndroidRouteEndpointV2? = null,
    @Volatile var expectedCommunicationOutput: AndroidRouteEndpointV2? = null,
    @Volatile var phase: String = "preparing",
    @Volatile var callbackCount: Int = 0,
    @Volatile var terminalCause: String? = null,
    @Volatile var cleanupOutcome: String = "pending",
    @Volatile var lifecycleSignal: CountDownLatch? = null,
  )

  private lateinit var methodChannel: MethodChannel
  private lateinit var eventsChannel: EventChannel
  private lateinit var logsChannel: EventChannel
  private val heavyWorkExecutor: ExecutorService = Executors.newSingleThreadExecutor()
  private val audioLifecycleExecutorV2: ExecutorService = Executors.newSingleThreadExecutor()
  private val mainHandler = Handler(Looper.getMainLooper())
  private var instrumentExtractionFuture: Future<*>? = null
  private lateinit var applicationContext: Context
  private lateinit var promptAnalysisService: PromptAnalysisService
  @Volatile private var engineOwnership = EngineOwnership.NONE
  @Volatile private var verifiedPlaybackRouteV2: AndroidRouteEndpointV2? = null
  @Volatile private var bluetoothMediaPolicyActiveV2 = false
  @Volatile private var v2SessionRequested = false
  @Volatile private var audioRouteMonitoringV2 = false
  @Volatile private var audioRouteGenerationV2 = 0L
  @Volatile private var audioRouteTransitionIdV2 = 0L
  @Volatile private var audioRouteFingerprintV2 = ""
  @Volatile private var verifiedPlaybackFingerprintV2 = ""
  @Volatile private var routeTransitionWasPlayingV2 = false
  private val recordingOperationIdV2 = AtomicLong(0L)
  private val recordingCancellationRequestedV2 = AtomicBoolean(false)
  @Volatile private var recordingOperationV2: RecordingOperationV2? = null
  @Volatile private var expectedPlaybackTransitionV2: AndroidMediaRouteResolutionV2? = null
  @Volatile private var audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY
  @Volatile private var lifecycleTransitionInProgressV2 = false
  @Volatile private var lifecycleDisposedV2 = false
  @Volatile private var duplexProbeFactsV2: Map<String, Any?>? = null

  private val audioDeviceCallbackV2 =
    object : AudioDeviceCallback() {
      override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
        handleAudioRouteSignalV2(
          AndroidRouteSignalKindV2.DEVICE_ADDED,
          emptySet(),
        )
      }

      override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
        val removedDeviceIds = removedDevices.mapTo(mutableSetOf()) { it.id }
        recordingOperationV2
          ?.takeIf { it.mode == IntentOperationModeV2.SYSTEM_SELECTED_PROBE }
          ?.takeIf { operation ->
            removedDeviceIds.any { removedId ->
              removedId == operation.sourceOutput.id ||
                removedId == operation.expectedCommunicationOutput?.id ||
                removedId == operation.verifiedInput?.id ||
                removedId == operation.verifiedOutput?.id
            }
          }
          ?.let { operation ->
            operation.routeInvalidated.set(true)
            operation.cancelled.set(true)
            operation.terminalCause = "deviceRemoved"
            operation.phase = "physicalRouteInvalidation"
            operation.lifecycleSignal?.countDown()
          }
        handleAudioRouteSignalV2(
          AndroidRouteSignalKindV2.DEVICE_REMOVED,
          removedDeviceIds,
        )
      }
    }

  private val audioPlaybackCallbackV2 =
    object : AudioManager.AudioPlaybackCallback() {
      override fun onPlaybackConfigChanged(
        configs: MutableList<AudioPlaybackConfiguration>,
      ) {
        handleAudioRouteSignalV2(
          AndroidRouteSignalKindV2.PLAYBACK_ACTIVITY,
          emptySet(),
        )
      }
    }

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

  private fun Map<String, Any?>.longValue(key: String, default: Long = 0L): Long {
    val raw = this[key]
    return when (raw) {
      is Number -> raw.toLong()
      is String -> raw.toLongOrNull() ?: default
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

  @Suppress("DEPRECATION")
  private fun preparePlaybackOnlyModeV2() {
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    audioManager.mode = AudioManager.MODE_NORMAL
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      try {
        audioManager.clearCommunicationDevice()
      } catch (_: SecurityException) {
      } catch (_: IllegalStateException) {
      }
    } else {
      try {
        if (audioManager.isBluetoothScoOn) audioManager.stopBluetoothSco()
        audioManager.isBluetoothScoOn = false
      } catch (_: SecurityException) {
      } catch (_: IllegalStateException) {
      }
    }
  }

  private fun setAndroidStreamPolicyV2(policy: AndroidStreamPolicyV2) {
    bluetoothMediaPolicyActiveV2 = policy == AndroidStreamPolicyV2.BLUETOOTH_MEDIA
    JuceBridge.setAndroidStreamPolicyV2JNI(policy.nativeValue)
  }

  private fun routeEndpointMapV2(
    endpoint: AndroidRouteEndpointV2?,
    direction: String,
  ): Map<String, Any?>? = endpoint?.let {
    mapOf(
      "direction" to direction,
      "uid" to it.id.toString(),
      "name" to it.name,
      "nativePortType" to it.type.toString(),
      "normalizedKind" to it.kind.wireValue,
      "channelCount" to it.channelCount,
    )
  }

  private fun updateDuplexProbeFactsV2(
    operation: RecordingOperationV2,
    status: String,
    diagnosticCode: String,
    restoredOutput: AndroidRouteEndpointV2? = null,
  ) {
    if (operation.mode != IntentOperationModeV2.SYSTEM_SELECTED_PROBE) return
    duplexProbeFactsV2 = mapOf(
      "status" to status,
      "diagnosticCode" to diagnosticCode,
      "validationStage" to operation.phase,
      "phase" to operation.phase,
      "terminalCause" to operation.terminalCause,
      "actualCallbackCount" to operation.callbackCount,
      "cleanupOutcome" to operation.cleanupOutcome,
      "selectionMode" to "androidCommunicationDevice",
      "operationId" to operation.id,
      "elapsedMs" to
        ((SystemClock.elapsedRealtimeNanos() - operation.startedNanos) / 1_000_000L).toInt(),
      "sourceOutput" to routeEndpointMapV2(operation.sourceOutput, "output"),
      "duplexInput" to routeEndpointMapV2(operation.verifiedInput, "input"),
      "duplexOutput" to routeEndpointMapV2(operation.verifiedOutput, "output"),
      "restoredOutput" to routeEndpointMapV2(restoredOutput, "output"),
    )
  }

  private fun AudioDeviceInfo.toRouteEndpointV2(): AndroidRouteEndpointV2 {
    val channels = channelCounts.maxOrNull()?.takeIf { it > 0 }
    return AndroidRouteEndpointV2(
      id = id,
      type = type,
      name = productName?.toString().orEmpty(),
      channelCount = channels,
    )
  }

  private data class AndroidEffectiveRouteStateV2(
    val resolution: AndroidMediaRouteResolutionV2,
    val actualEndpoint: AndroidRouteEndpointV2?,
    val routedDeviceId: Int?,
    val bluetoothCommunicationActive: Boolean,
    val fingerprint: String,
  )

  @Suppress("DEPRECATION")
  private fun resolveMediaRouteV2(): AndroidMediaRouteResolutionV2 {
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    return try {
      val outputs = audioManager
        .getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        .filter { it.isSink }
        .map { it.toRouteEndpointV2() }
      val mediaDevices = if (Build.VERSION.SDK_INT >= 33) {
          val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
          audioManager.getAudioDevicesForAttributes(attributes)
            .filter { it.isSink }
            .map { it.toRouteEndpointV2() }
        } else {
          emptyList()
        }
      AndroidMediaRouteResolverV2.resolve(
        apiLevel = Build.VERSION.SDK_INT,
        bluetoothA2dpActive = audioManager.isBluetoothA2dpOn,
        bluetoothScoActive =
          Build.VERSION.SDK_INT < Build.VERSION_CODES.S && audioManager.isBluetoothScoOn,
        mediaDevices = mediaDevices,
        outputDevices = outputs,
      )
    } catch (_: SecurityException) {
      AndroidMediaRouteResolutionV2(null, "bluetooth_route_unverified")
    } catch (_: IllegalStateException) {
      AndroidMediaRouteResolutionV2(null, "bluetooth_route_unverified")
    }
  }

  private fun outputEndpointsV2(): List<AndroidRouteEndpointV2> {
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    return try {
      audioManager
        .getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        .filter { it.isSink }
        .map { it.toRouteEndpointV2() }
    } catch (_: SecurityException) {
      emptyList()
    } catch (_: IllegalStateException) {
      emptyList()
    }
  }

  private fun inputEndpointsV2(): List<AndroidRouteEndpointV2> {
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    return try {
      audioManager
        .getDevices(AudioManager.GET_DEVICES_INPUTS)
        .filter { it.isSource }
        .map { it.toRouteEndpointV2() }
    } catch (_: SecurityException) {
      emptyList()
    } catch (_: IllegalStateException) {
      emptyList()
    }
  }

  @Suppress("DEPRECATION")
  private fun bluetoothCommunicationDeviceSelectedV2(
    audioManager: AudioManager,
  ): Boolean =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      when (audioManager.communicationDevice?.type) {
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_BLE_HEADSET -> true
        else -> false
      }
    } else {
      audioManager.isBluetoothScoOn
    }

  @Suppress("DEPRECATION")
  private fun currentEffectiveRouteStateV2(): AndroidEffectiveRouteStateV2 {
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val resolution = resolveMediaRouteV2()
    val oboe = currentOboeFactsV2()
    val routedDeviceId = (oboe["routedDeviceId"] as? Number)?.toInt()?.takeIf { it > 0 }
    val actualEndpoint = routedDeviceId?.let { id ->
      outputEndpointsV2().singleOrNull { it.id == id }
    }
    val bluetoothCommunicationActive =
      bluetoothCommunicationDeviceSelectedV2(audioManager)
    val intended = resolution.endpoint?.fingerprint
      ?: if (resolution.diagnosticCode == "ok") "system-default" else resolution.diagnosticCode
    val actual = actualEndpoint?.fingerprint ?: routedDeviceId?.toString() ?: "unavailable"
    return AndroidEffectiveRouteStateV2(
      resolution = resolution,
      actualEndpoint = actualEndpoint,
      routedDeviceId = routedDeviceId,
      bluetoothCommunicationActive = bluetoothCommunicationActive,
      fingerprint = "intended=$intended|actual=$actual|communication=$bluetoothCommunicationActive",
    )
  }

  private fun startAudioRouteMonitoringV2(): Map<String, Any?> {
    if (engineOwnership != EngineOwnership.V2_SESSION) {
      return capturePlaybackSnapshotV2(
        extraUnavailable = mapOf("coordinator" to "implementation_conflict"),
      )
    }
    if (eventsSink == null) {
      return capturePlaybackSnapshotV2(
        extraUnavailable = mapOf("coordinator" to "eventListenerUnavailable"),
      )
    }
    if (audioRouteMonitoringV2) return capturePlaybackSnapshotV2()

    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    audioRouteGenerationV2 = 0L
    audioRouteTransitionIdV2 = 0L
    routeTransitionWasPlayingV2 = false
    audioRouteFingerprintV2 = verifiedPlaybackFingerprintV2.ifEmpty {
      currentEffectiveRouteStateV2().fingerprint
    }
    return try {
      // Mark monitoring active before registration so a partial registration
      // can always be unwound by the shared cleanup path.
      audioRouteMonitoringV2 = true
      audioManager.registerAudioDeviceCallback(audioDeviceCallbackV2, mainHandler)
      audioManager.registerAudioPlaybackCallback(audioPlaybackCallbackV2, mainHandler)
      if (currentEffectiveRouteStateV2().fingerprint != audioRouteFingerprintV2) {
        handleAudioRouteSignalV2(AndroidRouteSignalKindV2.STARTUP, emptySet())
      }
      capturePlaybackSnapshotV2()
    } catch (_: SecurityException) {
      stopAudioRouteMonitoringV2()
      capturePlaybackSnapshotV2(
        extraUnavailable = mapOf("coordinator" to "nativeMonitoringUnavailable"),
      )
    } catch (_: IllegalStateException) {
      stopAudioRouteMonitoringV2()
      capturePlaybackSnapshotV2(
        extraUnavailable = mapOf("coordinator" to "nativeMonitoringUnavailable"),
      )
    }
  }

  private fun stopAudioRouteMonitoringV2() {
    if (!audioRouteMonitoringV2) return
    audioRouteMonitoringV2 = false
    audioRouteGenerationV2 += 1L
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    try {
      audioManager.unregisterAudioDeviceCallback(audioDeviceCallbackV2)
    } catch (_: IllegalArgumentException) {
    }
    try {
      audioManager.unregisterAudioPlaybackCallback(audioPlaybackCallbackV2)
    } catch (_: IllegalArgumentException) {
    }
    audioRouteFingerprintV2 = ""
    routeTransitionWasPlayingV2 = false
  }

  private fun handleAudioRouteSignalV2(
    signal: AndroidRouteSignalKindV2,
    removedDeviceIds: Set<Int>,
  ) {
    if (Looper.myLooper() != Looper.getMainLooper()) {
      mainHandler.post { handleAudioRouteSignalV2(signal, removedDeviceIds) }
      return
    }
    if (!audioRouteMonitoringV2 || engineOwnership != EngineOwnership.V2_SESSION) return
    val operation = recordingOperationV2
    val operationEndpointIds = operation?.let { activeOperation ->
      setOfNotNull(
        activeOperation.sourceOutput.id,
        activeOperation.expectedCommunicationOutput?.id,
        activeOperation.verifiedInput?.id,
        activeOperation.verifiedOutput?.id,
      )
    }
    val decision = AndroidIntentRouteObserverV2.classify(
      explicitTransactionActive =
        operation?.mode == IntentOperationModeV2.SYSTEM_SELECTED_PROBE,
      operationEndpointIds = operationEndpointIds,
      signal = signal,
      removedDeviceIds = removedDeviceIds,
    )
    if (decision == AndroidIntentRouteDecisionV2.INFORMATIONAL) return

    val cause = when (signal) {
      AndroidRouteSignalKindV2.DEVICE_ADDED -> "deviceInventoryChanged"
      AndroidRouteSignalKindV2.DEVICE_REMOVED -> "deviceRemoved"
      AndroidRouteSignalKindV2.PLAYBACK_ACTIVITY -> "mediaRouteChanged"
      AndroidRouteSignalKindV2.STARTUP -> "startupOutputChanged"
    }

    if (
      lifecycleTransitionInProgressV2 ||
      audioRouteIntentV2 != AudioRouteIntentV2.PLAYBACK_ONLY
    ) {
      recordingCancellationRequestedV2.set(true)
      operation?.routeInvalidated?.set(true)
      operation?.cancelled?.set(true)
      operation?.lifecycleSignal?.countDown()
      operation?.terminalCause = cause
      operation?.phase = "physicalRouteInvalidation"
      audioRouteGenerationV2 += 1L
      eventsSink?.success(
        mapOf(
          "event" to "audioRouteChangedV2",
          "generation" to audioRouteGenerationV2,
          "cause" to cause,
          "fingerprint" to audioRouteFingerprintV2,
          "transportWasPlaying" to false,
          "snapshot" to lifecycleUnavailableSnapshotV2(),
        ),
      )
      return
    }

    val effective = currentEffectiveRouteStateV2()
    if (effective.fingerprint == audioRouteFingerprintV2) return

    val removedActive =
      verifiedPlaybackRouteV2?.id?.let(removedDeviceIds::contains) == true ||
        effective.routedDeviceId?.let(removedDeviceIds::contains) == true
    val wasPlaying = JuceBridge.quiescePlaybackV2JNI(removedActive)
    routeTransitionWasPlayingV2 = routeTransitionWasPlayingV2 || wasPlaying
    audioRouteGenerationV2 += 1L
    audioRouteFingerprintV2 = effective.fingerprint
    eventsSink?.success(
      mapOf(
        "event" to "audioRouteChangedV2",
        "generation" to audioRouteGenerationV2,
        "cause" to cause,
        "fingerprint" to effective.fingerprint,
        "transportWasPlaying" to routeTransitionWasPlayingV2,
        "snapshot" to capturePlaybackSnapshotV2(),
      ),
    )
  }

  private fun routeTransitionResultV2(
    status: String,
    generation: Long,
    transitionId: Long,
    diagnosticCode: String,
    startedNanos: Long,
    transportWasPlaying: Boolean,
    snapshot: Map<String, Any?> = capturePlaybackSnapshotV2(),
  ): Map<String, Any?> = mapOf(
    "status" to status,
    "generation" to generation,
    "transitionId" to transitionId,
    "diagnosticCode" to diagnosticCode,
    "elapsedMs" to
      ((SystemClock.elapsedRealtimeNanos() - startedNanos) / 1_000_000L).toInt(),
    "transportWasPlaying" to transportWasPlaying,
    "snapshot" to snapshot,
  )

  private data class IntentOutcomeV2(
    val status: String,
    val diagnosticCode: String,
    val transportWasPlaying: Boolean = false,
  )

  private fun deliverLifecycleResultV2(
    result: MethodChannel.Result,
    generation: Long,
    transitionId: Long,
    startedNanos: Long,
    outcome: IntentOutcomeV2,
  ) {
    mainHandler.post {
      // Commit the verified playback fingerprint and release transition
      // ownership together on the observer's main-thread serialization path.
      // Notifications queued by the completed reopen therefore remain owned
      // by this transaction instead of becoming a new physical route change.
      var deliveredOutcome = outcome
      if (
        outcome.status == "success" &&
        audioRouteIntentV2 == AudioRouteIntentV2.PLAYBACK_ONLY
      ) {
        val committed = currentEffectiveRouteStateV2()
        val expected = expectedPlaybackTransitionV2?.endpoint
        val actual = committed.actualEndpoint ?: committed.resolution.endpoint
        if (expected != null && actual?.fingerprint != expected.fingerprint) {
          deliveredOutcome = IntentOutcomeV2("failure", "route_unstable")
        } else {
          verifiedPlaybackRouteV2 = actual
          audioRouteFingerprintV2 = committed.fingerprint
          verifiedPlaybackFingerprintV2 = committed.fingerprint
        }
      }
      lifecycleTransitionInProgressV2 = false
      expectedPlaybackTransitionV2 = null
      recordingOperationV2
        ?.takeIf { it.cleanupClaimed.get() }
        ?.let { completed ->
          if (recordingOperationV2 === completed) recordingOperationV2 = null
        }
      result.success(
        routeTransitionResultV2(
          status = deliveredOutcome.status,
          generation = generation,
          transitionId = transitionId,
          diagnosticCode = deliveredOutcome.diagnosticCode,
          startedNanos = startedNanos,
          transportWasPlaying = deliveredOutcome.transportWasPlaying,
        ),
      )
    }
  }

  private fun resolveActualOutputV2(): AndroidRouteEndpointV2? {
    val state = currentEffectiveRouteStateV2()
    return state.actualEndpoint ?: state.resolution.endpoint
  }

  private fun restorePlaybackOnlyV2(
    expectedOutput: AndroidRouteEndpointV2?,
    operation: RecordingOperationV2? = null,
  ): String {
    val probeOperation = operation?.takeIf {
      it.mode == IntentOperationModeV2.SYSTEM_SELECTED_PROBE
    }
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val releaseSignal = probeOperation?.let { activeProbe ->
      activeProbe.expectedCommunicationOutput?.let { target ->
        val released = CountDownLatch(1)
        released to AudioManager.OnCommunicationDeviceChangedListener { device ->
          if (device?.id != target.id) released.countDown()
        }
      }
    }
    if (releaseSignal != null) {
      probeOperation.phase = "releasingCommunicationDevice"
      probeOperation.lifecycleSignal = releaseSignal.first
      try {
        audioManager.addOnCommunicationDeviceChangedListener(
          applicationContext.mainExecutor,
          releaseSignal.second,
        )
      } catch (_: SecurityException) {
        probeOperation.lifecycleSignal = null
        return "actual_state_unavailable"
      } catch (_: IllegalStateException) {
        probeOperation.lifecycleSignal = null
        return "actual_state_unavailable"
      }
    }
    return try {
      if (probeOperation != null) JuceBridge.quiescePlaybackV2JNI(true)
      preparePlaybackOnlyModeV2()

      // Communication-device release, not playback activity, is the settling
      // boundary for this explicit transaction. Oboe route readback below
      // remains authoritative for the final media endpoint.
      if (releaseSignal != null) {
        val activeProbe = requireNotNull(probeOperation)
        val remainingNanos = activeProbe.startedNanos + TimeUnit.SECONDS.toNanos(5) -
          SystemClock.elapsedRealtimeNanos()
        if (
          remainingNanos <= 0L ||
          !releaseSignal.first.await(remainingNanos, TimeUnit.NANOSECONDS)
        ) {
          Log.w("JuceAudioEngine", "Android V2 playback restore failed: communication_release")
          return "actual_state_unavailable"
        }
        if (
          activeProbe.cancelled.get() ||
          activeProbe.routeInvalidated.get() ||
          activeProbe.generation != audioRouteGenerationV2
        ) {
          return "route_unstable"
        }
      }

      val expectedRoute = expectedOutput?.let {
        AndroidMediaRouteResolutionV2(it, "ok")
      } ?: resolveMediaRouteV2()
      if (expectedRoute.diagnosticCode != "ok") return expectedRoute.diagnosticCode
      expectedPlaybackTransitionV2 = expectedRoute
      setAndroidStreamPolicyV2(
        if (expectedRoute.isBluetooth) AndroidStreamPolicyV2.BLUETOOTH_MEDIA
        else AndroidStreamPolicyV2.NORMAL,
      )
      if (!JuceBridge.reconfigurePlaybackV2JNI()) {
        Log.w("JuceAudioEngine", "Android V2 playback restore failed: juce_reopen_failed")
        return "juce_reopen_failed"
      }
      val callbackRemainingNanos = probeOperation?.let { activeProbe ->
        activeProbe.startedNanos + TimeUnit.SECONDS.toNanos(5) -
          SystemClock.elapsedRealtimeNanos()
      }
      if (callbackRemainingNanos != null && callbackRemainingNanos <= 0L) {
        Log.w("JuceAudioEngine", "Android V2 playback restore failed: callback_deadline")
        return "actual_state_unavailable"
      }
      val callbackTimeoutMillis = callbackRemainingNanos?.let { remaining ->
        TimeUnit.NANOSECONDS.toMillis(remaining).coerceIn(1L, 5000L).toInt()
      } ?: 1000
      if (!JuceBridge.waitForV2CallbackReadyJNI(callbackTimeoutMillis)) {
        Log.w("JuceAudioEngine", "Android V2 playback restore failed: callback_unavailable")
        return "actual_state_unavailable"
      }

      var code = AndroidPlaybackReadinessV2.validate(currentPlaybackFactsV2())
      val actual = currentEffectiveRouteStateV2()
      if (code == "ok") {
        code = AndroidLiveRouteValidatorV2.validate(
          expectedRoute,
          actual.resolution,
          actual.actualEndpoint,
          AndroidOboeOutputFactsV2.fromMap(currentOboeFactsV2()),
        )
      }
      val actualOutput = actual.actualEndpoint ?: actual.resolution.endpoint
      if (
        code == "ok" &&
        expectedOutput != null &&
        actualOutput?.fingerprint != expectedOutput.fingerprint
      ) {
        code = "route_unstable"
      }
      if (code != "ok") {
        Log.w("JuceAudioEngine", "Android V2 playback restore failed: $code")
        return code
      }

      verifiedPlaybackRouteV2 = actualOutput
      audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY
      routeTransitionWasPlayingV2 = false
      "ok"
    } finally {
      if (releaseSignal != null) {
        try {
          audioManager.removeOnCommunicationDeviceChangedListener(releaseSignal.second)
        } catch (_: IllegalArgumentException) {
        }
        if (probeOperation?.lifecycleSignal === releaseSignal.first) {
          probeOperation.lifecycleSignal = null
        }
      }
    }
  }

  private fun cleanupRecordingOperationV2(
    operation: RecordingOperationV2,
    restorePlayback: Boolean,
  ): String {
    if (!operation.cleanupClaimed.compareAndSet(false, true)) {
      return if (audioRouteIntentV2 == AudioRouteIntentV2.PLAYBACK_ONLY) "ok"
      else "actual_state_unavailable"
    }
    if (JuceBridge.isRecordingJNI()) {
      JuceBridge.discardRecordingCaptureV2JNI()
    }
    val code = if (restorePlayback) {
      restorePlaybackOnlyV2(operation.sourceOutput, operation)
    } else {
      JuceBridge.quiescePlaybackV2JNI(true)
      preparePlaybackOnlyModeV2()
      setAndroidStreamPolicyV2(AndroidStreamPolicyV2.NORMAL)
      JuceBridge.resetPlaybackPolicyV2JNI()
      audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY
      "ok"
    }
    if (code != "ok") {
      JuceBridge.quiescePlaybackV2JNI(true)
      setAndroidStreamPolicyV2(AndroidStreamPolicyV2.NORMAL)
      JuceBridge.resetPlaybackPolicyV2JNI()
      verifiedPlaybackRouteV2 = null
      verifiedPlaybackFingerprintV2 = ""
      audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY
    }
    operation.cleanupOutcome = when {
      restorePlayback && code == "ok" -> "restored"
      restorePlayback -> "restoreFailed"
      operation.routeInvalidated.get() -> "closedForCurrentRouteRecovery"
      else -> "closed"
    }
    operation.phase = if (code == "ok") "complete" else "cleanup"
    updateDuplexProbeFactsV2(
      operation,
      status = when {
        operation.routeInvalidated.get() -> "failed"
        code == "ok" -> "restored"
        else -> "failedRestored"
      },
      diagnosticCode = if (operation.routeInvalidated.get()) "route_unstable" else code,
      restoredOutput = if (restorePlayback && code == "ok") verifiedPlaybackRouteV2 else null,
    )
    return code
  }

  private fun prepareBuiltInRecordingV2(
    generation: Long,
  ): IntentOutcomeV2 {
    if (
      lifecycleDisposedV2 ||
      recordingCancellationRequestedV2.get() ||
      !audioRouteMonitoringV2 ||
      engineOwnership != EngineOwnership.V2_SESSION
    ) {
      return IntentOutcomeV2("failure", "coordinator_disposed")
    }
    if (generation != audioRouteGenerationV2) {
      return IntentOutcomeV2("failure", "stale_generation")
    }
    if (AndroidPlaybackReadinessV2.validate(currentPlaybackFactsV2()) != "ok") {
      return IntentOutcomeV2("failure", "actual_state_unavailable")
    }
    val sourceOutput = resolveActualOutputV2()
      ?: return IntentOutcomeV2("failure", "no_output")
    if (sourceOutput.kind != AndroidRouteKindV2.BUILT_IN) {
      return IntentOutcomeV2("failure", "recording_route_unsupported")
    }

    val operation = RecordingOperationV2(
      id = recordingOperationIdV2.incrementAndGet(),
      generation = generation,
      sourceOutput = sourceOutput,
    )
    recordingOperationV2 = operation
    audioRouteIntentV2 = AudioRouteIntentV2.PREPARING_RECORDING
    preparePlaybackOnlyModeV2()
    setAndroidStreamPolicyV2(AndroidStreamPolicyV2.NORMAL)

    if (operation.cancelled.get() || generation != audioRouteGenerationV2) {
      val code = cleanupRecordingOperationV2(
        operation,
        restorePlayback = !operation.routeInvalidated.get(),
      )
      return IntentOutcomeV2("failure", if (code == "ok") "recording_interrupted" else code)
    }
    if (!JuceBridge.prepareRecordingV2JNI()) {
      val code = cleanupRecordingOperationV2(
        operation,
        restorePlayback = !operation.routeInvalidated.get(),
      )
      return IntentOutcomeV2("failure", if (code == "ok") "juce_reopen_failed" else code)
    }
    if (!JuceBridge.waitForV2CallbackReadyJNI(1000)) {
      val code = cleanupRecordingOperationV2(
        operation,
        restorePlayback = !operation.routeInvalidated.get(),
      )
      return IntentOutcomeV2("failure", if (code == "ok") "actual_state_unavailable" else code)
    }
    if (operation.cancelled.get() || generation != audioRouteGenerationV2) {
      val code = cleanupRecordingOperationV2(
        operation,
        restorePlayback = !operation.routeInvalidated.get(),
      )
      return IntentOutcomeV2("failure", if (code == "ok") "stale_generation" else code)
    }

    val facts = currentRecordingFactsV2(sourceOutput)
    val readiness = AndroidRecordingReadinessV2.validate(facts)
    if (readiness != "ok") {
      val code = cleanupRecordingOperationV2(
        operation,
        restorePlayback = !operation.routeInvalidated.get(),
      )
      return IntentOutcomeV2("failure", if (code == "ok") readiness else code)
    }
    operation.verifiedInput = facts.actualInput
    operation.verifiedOutput = facts.actualOutput
    return IntentOutcomeV2("success", "ok")
  }

  private fun failBluetoothDuplexProbeV2(
    operation: RecordingOperationV2,
    diagnosticCode: String,
  ): IntentOutcomeV2 {
    val validationStage = operation.phase
    val restoreCode = cleanupRecordingOperationV2(
      operation,
      restorePlayback = !operation.routeInvalidated.get(),
    )
    val finalCode = when {
      operation.routeInvalidated.get() -> "route_unstable"
      restoreCode != "ok" -> restoreCode
      else -> diagnosticCode
    }
    operation.phase = validationStage
    updateDuplexProbeFactsV2(
      operation,
      status = if (operation.cleanupOutcome == "restored") {
        "failedRestored"
      } else {
        "failed"
      },
      diagnosticCode = finalCode,
      restoredOutput = if (operation.cleanupOutcome == "restored") {
        verifiedPlaybackRouteV2
      } else {
        null
      },
    )
    return IntentOutcomeV2("failure", finalCode)
  }

  private fun currentBluetoothDuplexFactsV2(
    operation: RecordingOperationV2,
  ): AndroidBluetoothDuplexFactsV2 {
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val diagnostics = JuceBridge.getEngineDiagnosticsJNI()
    val inputStream = AndroidOboeOutputFactsV2.fromMap(currentOboeInputFactsV2())
    val outputStream = AndroidOboeOutputFactsV2.fromMap(currentOboeFactsV2())
    val input = inputStream.routedDeviceId?.let { id ->
      inputEndpointsV2().singleOrNull { it.id == id }
    }
    val output = outputStream.routedDeviceId?.let { id ->
      outputEndpointsV2().singleOrNull { it.id == id }
    }
    val communicationDeviceId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      audioManager.communicationDevice?.id
    } else {
      null
    }
    return AndroidBluetoothDuplexFactsV2(
      apiLevel = Build.VERSION.SDK_INT,
      sourceOutput = operation.sourceOutput,
      selectedCommunicationOutput = operation.expectedCommunicationOutput,
      actualInput = input,
      actualOutput = output,
      audioMode = audioManager.mode,
      communicationDeviceId = communicationDeviceId,
      deviceOpen = diagnostics["deviceOpen"] == true,
      callbackAttached = diagnostics["audioCallbackAttached"] == true,
      activeInputChannels =
        (diagnostics["inputChannelCount"] as? Number)?.toInt() ?: 0,
      activeOutputChannels =
        (diagnostics["outputChannelCount"] as? Number)?.toInt() ?: 0,
      sampleRateHz = (diagnostics["sampleRate"] as? Number)?.toDouble() ?: 0.0,
      bufferFrames = (diagnostics["bufferSize"] as? Number)?.toInt() ?: 0,
      inputStream = inputStream,
      outputStream = outputStream,
    )
  }

  private fun prepareBluetoothDuplexProbeV2(
    generation: Long,
  ): IntentOutcomeV2 {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
      return IntentOutcomeV2("failure", "recording_route_unsupported")
    }
    if (
      lifecycleDisposedV2 ||
      recordingCancellationRequestedV2.get() ||
      !audioRouteMonitoringV2 ||
      engineOwnership != EngineOwnership.V2_SESSION
    ) {
      return IntentOutcomeV2("failure", "coordinator_disposed")
    }
    if (generation != audioRouteGenerationV2) {
      return IntentOutcomeV2("failure", "stale_generation")
    }
    if (AndroidPlaybackReadinessV2.validate(currentPlaybackFactsV2()) != "ok") {
      return IntentOutcomeV2("failure", "actual_state_unavailable")
    }
    val sourceOutput = resolveActualOutputV2()
      ?: return IntentOutcomeV2("failure", "no_output")
    if (sourceOutput.kind != AndroidRouteKindV2.BLUETOOTH_MEDIA) {
      return IntentOutcomeV2("failure", "recording_route_unsupported")
    }

    val operation = RecordingOperationV2(
      id = recordingOperationIdV2.incrementAndGet(),
      generation = generation,
      sourceOutput = sourceOutput,
      mode = IntentOperationModeV2.SYSTEM_SELECTED_PROBE,
    )
    recordingOperationV2 = operation
    duplexProbeFactsV2 = null
    audioRouteIntentV2 = AudioRouteIntentV2.PREPARING_RECORDING
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val candidates = try {
      audioManager.availableCommunicationDevices
        .filter { it.isSink && it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
        .distinctBy { it.id }
    } catch (_: SecurityException) {
      emptyList()
    } catch (_: IllegalStateException) {
      emptyList()
    }
    if (candidates.size != 1) {
      operation.phase = "communicationDeviceUnavailable"
      return failBluetoothDuplexProbeV2(operation, "recording_route_unsupported")
    }
    val candidate = candidates.single()
    operation.expectedCommunicationOutput = candidate.toRouteEndpointV2()
    operation.phase = "selectingCommunicationDevice"

    val selected = CountDownLatch(1)
    operation.lifecycleSignal = selected
    val listener = AudioManager.OnCommunicationDeviceChangedListener { device ->
      if (device?.id == candidate.id) selected.countDown()
    }
    try {
      audioManager.addOnCommunicationDeviceChangedListener(
        applicationContext.mainExecutor,
        listener,
      )
      audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
      if (!audioManager.setCommunicationDevice(candidate)) {
        operation.phase = "communicationDeviceSelection"
        return failBluetoothDuplexProbeV2(operation, "recording_route_unsupported")
      }
      val deadlineNanos = operation.startedNanos + TimeUnit.SECONDS.toNanos(5)
      val remainingNanos = deadlineNanos - SystemClock.elapsedRealtimeNanos()
      if (remainingNanos <= 0L || !selected.await(remainingNanos, TimeUnit.NANOSECONDS)) {
        operation.phase = "communicationDeviceTimeout"
        return failBluetoothDuplexProbeV2(operation, "actual_state_unavailable")
      }
    } catch (_: SecurityException) {
      operation.phase = "communicationDeviceSelection"
      return failBluetoothDuplexProbeV2(operation, "recording_route_unsupported")
    } catch (_: IllegalStateException) {
      operation.phase = "communicationDeviceSelection"
      return failBluetoothDuplexProbeV2(operation, "actual_state_unavailable")
    } finally {
      operation.lifecycleSignal = null
      try {
        audioManager.removeOnCommunicationDeviceChangedListener(listener)
      } catch (_: IllegalArgumentException) {
      }
    }

    if (
      operation.cancelled.get() ||
      operation.routeInvalidated.get() ||
      generation != audioRouteGenerationV2
    ) {
      operation.phase = if (operation.routeInvalidated.get()) {
        "physicalRouteInvalidation"
      } else {
        "cancelled"
      }
      return failBluetoothDuplexProbeV2(operation, "route_unstable")
    }

    operation.phase = "openingDuplex"
    setAndroidStreamPolicyV2(AndroidStreamPolicyV2.BLUETOOTH_COMMUNICATION_DUPLEX)
    if (!JuceBridge.prepareBluetoothDuplexProbeV2JNI()) {
      operation.phase = "juceOpen"
      return failBluetoothDuplexProbeV2(operation, "juce_reopen_failed")
    }
    val remainingAfterOpenNanos =
      operation.startedNanos + TimeUnit.SECONDS.toNanos(5) -
        SystemClock.elapsedRealtimeNanos()
    if (remainingAfterOpenNanos <= 0L) {
      operation.phase = "callbackTimeout"
      return failBluetoothDuplexProbeV2(operation, "actual_state_unavailable")
    }
    val remainingMillis = TimeUnit.NANOSECONDS.toMillis(remainingAfterOpenNanos)
      .coerceIn(1L, 5000L)
      .toInt()
    if (!JuceBridge.waitForV2CallbackReadyJNI(remainingMillis)) {
      operation.phase = "callback"
      return failBluetoothDuplexProbeV2(operation, "actual_state_unavailable")
    }
    operation.callbackCount = 1
    if (
      operation.cancelled.get() ||
      operation.routeInvalidated.get() ||
      generation != audioRouteGenerationV2
    ) {
      operation.phase = if (operation.routeInvalidated.get()) {
        "physicalRouteInvalidation"
      } else {
        "cancelled"
      }
      return failBluetoothDuplexProbeV2(operation, "route_unstable")
    }

    val facts = currentBluetoothDuplexFactsV2(operation)
    val readiness = AndroidBluetoothDuplexReadinessV2.validate(facts)
    if (readiness != "ok") {
      operation.phase = "duplexValidation"
      return failBluetoothDuplexProbeV2(operation, readiness)
    }
    operation.verifiedInput = facts.actualInput
    operation.verifiedOutput = facts.actualOutput
    operation.phase = "duplexVerified"
    updateDuplexProbeFactsV2(operation, "duplexVerified", "ok")
    return IntentOutcomeV2("success", "ok")
  }

  private fun verifyRecordingIntentV2(generation: Long): IntentOutcomeV2 {
    val operation = recordingOperationV2
      ?: return IntentOutcomeV2("failure", "actual_state_unavailable")
    if (
      operation.cancelled.get() ||
      recordingCancellationRequestedV2.get() ||
      generation != operation.generation ||
      generation != audioRouteGenerationV2
    ) {
      return IntentOutcomeV2("failure", "stale_generation")
    }
    if (!JuceBridge.isRecordingJNI()) {
      return IntentOutcomeV2("failure", "actual_state_unavailable")
    }
    val readiness = validatePreparedRecordingV2(operation)
    if (readiness != "ok") return IntentOutcomeV2("failure", readiness)
    audioRouteIntentV2 = AudioRouteIntentV2.RECORDING
    return IntentOutcomeV2("success", "ok")
  }

  private fun restoreRecordingPlaybackV2(generation: Long): IntentOutcomeV2 {
    if (generation != audioRouteGenerationV2) {
      recordingOperationV2?.let { operation ->
        operation.routeInvalidated.set(true)
        operation.cancelled.set(true)
        cleanupRecordingOperationV2(operation, restorePlayback = false)
      }
      return IntentOutcomeV2("failure", "stale_generation")
    }
    val operation = recordingOperationV2
    val code = if (operation != null) {
      cleanupRecordingOperationV2(operation, restorePlayback = true)
    } else {
      restorePlaybackOnlyV2(expectedOutput = null)
    }
    return IntentOutcomeV2(if (code == "ok") "success" else "failure", code)
  }

  private fun setAudioRouteIntentV2(
    args: Map<String, Any?>,
    result: MethodChannel.Result,
  ) {
    val started = SystemClock.elapsedRealtimeNanos()
    val generation = args.longValue("generation")
    audioRouteTransitionIdV2 += 1L
    val transitionId = audioRouteTransitionIdV2
    if (
      lifecycleTransitionInProgressV2 ||
      lifecycleDisposedV2 ||
      !audioRouteMonitoringV2 ||
      engineOwnership != EngineOwnership.V2_SESSION
    ) {
      result.success(
        routeTransitionResultV2(
          "failure",
          generation,
          transitionId,
          if (lifecycleTransitionInProgressV2) "route_unstable" else "coordinator_disposed",
          started,
          false,
        ),
      )
      return
    }
    val requestedIntent = when (args.stringValue("intent")) {
      "playbackOnly" -> AudioRouteIntentV2.PLAYBACK_ONLY
      "preparingRecording" -> AudioRouteIntentV2.PREPARING_RECORDING
      "recording" -> AudioRouteIntentV2.RECORDING
      else -> null
    }
    val operationMode = when (args.stringValue("intentOperation")) {
      "systemSelectedProbe" -> IntentOperationModeV2.SYSTEM_SELECTED_PROBE
      else -> IntentOperationModeV2.STANDARD
    }
    if (requestedIntent == null) {
      result.success(
        routeTransitionResultV2(
          "failure", generation, transitionId, "recording_route_unsupported",
          started, false,
        ),
      )
      return
    }
    if (requestedIntent == AudioRouteIntentV2.PREPARING_RECORDING) {
      recordingCancellationRequestedV2.set(false)
    }

    lifecycleTransitionInProgressV2 = true
    audioLifecycleExecutorV2.execute {
      val outcome = try {
        when (requestedIntent) {
          AudioRouteIntentV2.PREPARING_RECORDING ->
            if (operationMode == IntentOperationModeV2.SYSTEM_SELECTED_PROBE) {
              prepareBluetoothDuplexProbeV2(generation)
            } else {
              prepareBuiltInRecordingV2(generation)
            }
          AudioRouteIntentV2.RECORDING -> verifyRecordingIntentV2(generation)
          AudioRouteIntentV2.PLAYBACK_ONLY -> restoreRecordingPlaybackV2(generation)
        }
      } catch (error: Exception) {
        Log.e("JuceAudioEngine", "Android V2 intent transition failed", error)
        val operation = recordingOperationV2
        if (operation != null) {
          cleanupRecordingOperationV2(
            operation,
            restorePlayback = !operation.routeInvalidated.get(),
          )
        }
        IntentOutcomeV2("failure", "actual_state_unavailable")
      }
      deliverLifecycleResultV2(result, generation, transitionId, started, outcome)
    }
  }

  private fun abortRecordingV2(
    args: Map<String, Any?>,
    result: MethodChannel.Result,
  ) {
    val operation = recordingOperationV2
    recordingCancellationRequestedV2.set(true)
    operation?.cancelled?.set(true)
    operation?.lifecycleSignal?.countDown()
    val restorePlayback = args.boolValue("restorePlayback", true)
    audioLifecycleExecutorV2.execute {
      if (operation != null) {
        cleanupRecordingOperationV2(
          operation,
          restorePlayback && !operation.routeInvalidated.get(),
        )
      } else if (JuceBridge.isRecordingJNI()) {
        JuceBridge.discardRecordingCaptureV2JNI()
      }
      mainHandler.post {
        if (
          operation != null &&
          operation.cleanupClaimed.get() &&
          recordingOperationV2 === operation
        ) {
          recordingOperationV2 = null
        }
        result.success(null)
      }
    }
  }

  private fun startPreparedCaptureV2(
    args: Map<String, Any?>,
    result: MethodChannel.Result,
  ) {
    val operation = recordingOperationV2
    if (
      operation == null ||
      operation.cancelled.get() ||
      recordingCancellationRequestedV2.get() ||
      audioRouteIntentV2 != AudioRouteIntentV2.PREPARING_RECORDING ||
      lifecycleTransitionInProgressV2
    ) {
      result.success(false)
      return
    }
    lifecycleTransitionInProgressV2 = true
    audioLifecycleExecutorV2.execute {
      var started = false
      try {
        val readiness = validatePreparedRecordingV2(operation)
        if (
          readiness == "ok" &&
          !operation.cancelled.get() &&
          !recordingCancellationRequestedV2.get() &&
          operation.generation == audioRouteGenerationV2
        ) {
          started = JuceBridge.startRecordingJNI(
            args.stringValue("path"),
            0,
            1,
          )
        }
        if (
          started &&
          (operation.cancelled.get() ||
            recordingCancellationRequestedV2.get() ||
            operation.generation != audioRouteGenerationV2)
        ) {
          JuceBridge.discardRecordingCaptureV2JNI()
          started = false
        }
      } catch (error: Exception) {
        Log.e("JuceAudioEngine", "Android V2 capture start failed", error)
      } finally {
        lifecycleTransitionInProgressV2 = false
      }
      mainHandler.post { result.success(started) }
    }
  }

  private fun stopPreparedCaptureV2(result: MethodChannel.Result) {
    lifecycleTransitionInProgressV2 = true
    audioLifecycleExecutorV2.execute {
      val captureResult = try {
        JuceBridge.stopRecordingWithoutPlaybackRestoreJNI()
      } catch (error: Exception) {
        Log.e("JuceAudioEngine", "Android V2 capture stop failed", error)
        hashMapOf<String, Any>(
          "success" to false,
          "diagnosticCode" to "writer_finalize_failed",
        )
      } finally {
        lifecycleTransitionInProgressV2 = false
      }
      mainHandler.post { result.success(captureResult) }
    }
  }

  private fun closeFailedPlaybackRouteV2() {
    JuceBridge.quiescePlaybackV2JNI(true)
    JuceBridge.resetPlaybackPolicyV2JNI()
    bluetoothMediaPolicyActiveV2 = false
    verifiedPlaybackRouteV2 = null
    verifiedPlaybackFingerprintV2 = ""
  }

  private fun applyAudioRouteConfigurationV2(args: Map<String, Any?>): Map<String, Any?> {
    val started = SystemClock.elapsedRealtimeNanos()
    val generation = args.longValue("generation")
    audioRouteTransitionIdV2 += 1L
    val transitionId = audioRouteTransitionIdV2
    val transportWasPlaying = routeTransitionWasPlayingV2
    if (
      lifecycleTransitionInProgressV2 ||
      !audioRouteMonitoringV2 ||
      engineOwnership != EngineOwnership.V2_SESSION
    ) {
      return routeTransitionResultV2(
        "failure",
        generation,
        transitionId,
        if (lifecycleTransitionInProgressV2) "route_unstable" else "coordinator_disposed",
        started,
        transportWasPlaying,
      )
    }
    if (generation != audioRouteGenerationV2) {
      return routeTransitionResultV2(
        "failure",
        generation,
        transitionId,
        "stale_generation",
        started,
        transportWasPlaying,
      )
    }

    val previousWasBluetooth =
      bluetoothMediaPolicyActiveV2 ||
        verifiedPlaybackRouteV2?.kind == AndroidRouteKindV2.BLUETOOTH_MEDIA ||
        verifiedPlaybackRouteV2?.kind == AndroidRouteKindV2.BLUETOOTH_LE
    val expected = resolveMediaRouteV2()
    if (expected.diagnosticCode != "ok") {
      closeFailedPlaybackRouteV2()
      return routeTransitionResultV2(
        "failure",
        generation,
        transitionId,
        expected.diagnosticCode,
        started,
        transportWasPlaying,
      )
    }

    preparePlaybackOnlyModeV2()
    setAndroidStreamPolicyV2(
      if (expected.isBluetooth) AndroidStreamPolicyV2.BLUETOOTH_MEDIA
      else AndroidStreamPolicyV2.NORMAL,
    )
    if (!JuceBridge.reconfigurePlaybackV2JNI()) {
      closeFailedPlaybackRouteV2()
      return routeTransitionResultV2(
        "failure",
        generation,
        transitionId,
        "juce_reopen_failed",
        started,
        transportWasPlaying,
      )
    }
    if (!JuceBridge.waitForV2CallbackReadyJNI(1000)) {
      closeFailedPlaybackRouteV2()
      return routeTransitionResultV2(
        "failure",
        generation,
        transitionId,
        "actual_state_unavailable",
        started,
        transportWasPlaying,
      )
    }

    if (generation != audioRouteGenerationV2) {
      Log.w(
        "JuceAudioEngine",
        "Android V2 playback apply failed: stale_generation after callback",
      )
      JuceBridge.quiescePlaybackV2JNI(false)
      return routeTransitionResultV2(
        "failure",
        generation,
        transitionId,
        "stale_generation",
        started,
        transportWasPlaying,
      )
    }

    val snapshot = capturePlaybackSnapshotV2()
    var diagnosticCode = AndroidPlaybackReadinessV2.validate(currentPlaybackFactsV2())
    val actual = currentEffectiveRouteStateV2()
    if (diagnosticCode == "ok" && actual.bluetoothCommunicationActive) {
      diagnosticCode = "bluetooth_duplex_forbidden"
    }
    if (diagnosticCode == "ok") {
      diagnosticCode = AndroidLiveRouteValidatorV2.validate(
        expected,
        actual.resolution,
        actual.actualEndpoint,
        AndroidOboeOutputFactsV2.fromMap(currentOboeFactsV2()),
        acceptSystemSelectedReplacement = previousWasBluetooth && !expected.isBluetooth,
      )
    }
    if (
      diagnosticCode == "ok" &&
      snapshot["captureConsistency"] != "stable"
    ) {
      diagnosticCode = "route_unstable"
    }
    if (generation != audioRouteGenerationV2) diagnosticCode = "stale_generation"

    if (diagnosticCode != "ok") {
      Log.w("JuceAudioEngine", "Android V2 playback apply failed: $diagnosticCode")
      if (diagnosticCode == "stale_generation") {
        JuceBridge.quiescePlaybackV2JNI(false)
      } else {
        closeFailedPlaybackRouteV2()
      }
      return routeTransitionResultV2(
        "failure",
        generation,
        transitionId,
        diagnosticCode,
        started,
        transportWasPlaying,
        if (diagnosticCode == "stale_generation") snapshot else capturePlaybackSnapshotV2(),
      )
    }

    verifiedPlaybackRouteV2 = actual.actualEndpoint ?: actual.resolution.endpoint
    verifiedPlaybackFingerprintV2 = actual.fingerprint
    audioRouteFingerprintV2 = actual.fingerprint
    routeTransitionWasPlayingV2 = false
    val usedSpeakerFallback =
      previousWasBluetooth &&
        !expected.isBluetooth &&
        actual.actualEndpoint?.kind == AndroidRouteKindV2.BUILT_IN
    return routeTransitionResultV2(
      if (usedSpeakerFallback) "fallback" else "success",
      generation,
      transitionId,
      if (usedSpeakerFallback) "fallback_succeeded" else "ok",
      started,
      transportWasPlaying,
      capturePlaybackSnapshotV2(),
    )
  }

  private fun cleanupFailedPlaybackV2() {
    stopAudioRouteMonitoringV2()
    JuceBridge.shutdownEngineSynchronouslyJNI()
    JuceBridge.resetPlaybackPolicyV2JNI()
    verifiedPlaybackRouteV2 = null
    bluetoothMediaPolicyActiveV2 = false
    verifiedPlaybackFingerprintV2 = ""
    audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY
    recordingOperationV2 = null
    duplexProbeFactsV2 = null
    expectedPlaybackTransitionV2 = null
    engineOwnership = EngineOwnership.NONE
  }

  private fun currentOboeFactsV2(): Map<String, Any> =
    JuceBridge.getOboeOutputStreamFactsV2JNI()

  private fun currentOboeInputFactsV2(): Map<String, Any> =
    JuceBridge.getOboeInputStreamFactsV2JNI()

  private fun validateVerifiedBluetoothRouteV2(
    expected: AndroidRouteEndpointV2,
    actual: AndroidMediaRouteResolutionV2,
    oboe: Map<String, Any>,
  ): String {
    return AndroidBluetoothStartupValidatorV2.validate(
      expected,
      actual,
      AndroidOboeOutputFactsV2.fromMap(oboe),
    )
  }

  private fun validatePlaybackV2Now(): String {
    if (audioRouteIntentV2 != AudioRouteIntentV2.PLAYBACK_ONLY) {
      val operation = recordingOperationV2 ?: return "actual_state_unavailable"
      if (audioRouteIntentV2 != AudioRouteIntentV2.RECORDING) {
        return "route_unstable"
      }
      if (!JuceBridge.isRecordingJNI()) return "actual_state_unavailable"
      return validatePreparedRecordingV2(operation)
    }
    val readiness = AndroidPlaybackReadinessV2.validate(currentPlaybackFactsV2())
    if (readiness != "ok") return readiness
    val expected = verifiedPlaybackRouteV2 ?: return "ok"
    if (!bluetoothMediaPolicyActiveV2) return "ok"
    return validateVerifiedBluetoothRouteV2(
      expected,
      resolveMediaRouteV2(),
      currentOboeFactsV2(),
    )
  }

  @Suppress("DEPRECATION")
  private fun currentPlaybackFactsV2(): AndroidPlaybackFactsV2 {
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val diagnostics = JuceBridge.getEngineDiagnosticsJNI()
    val bluetoothCommunicationDeviceSelected =
      bluetoothCommunicationDeviceSelectedV2(audioManager)
    val scoActive =
      Build.VERSION.SDK_INT < Build.VERSION_CODES.S && audioManager.isBluetoothScoOn
    return AndroidPlaybackFactsV2(
      ownedByV2 = engineOwnership == EngineOwnership.V2_SESSION,
      audioMode = audioManager.mode,
      bluetoothCommunicationDeviceSelected = bluetoothCommunicationDeviceSelected,
      bluetoothScoActive = scoActive,
      deviceOpen = diagnostics["deviceOpen"] == true,
      callbackAttached = diagnostics["audioCallbackAttached"] == true,
      activeInputChannels = (diagnostics["inputChannelCount"] as? Number)?.toInt() ?: 0,
      activeOutputChannels = (diagnostics["outputChannelCount"] as? Number)?.toInt() ?: 0,
      sampleRateHz = (diagnostics["sampleRate"] as? Number)?.toDouble() ?: 0.0,
      bufferFrames = (diagnostics["bufferSize"] as? Number)?.toInt() ?: 0,
    )
  }

  @Suppress("DEPRECATION")
  private fun currentRecordingFactsV2(
    sourceOutput: AndroidRouteEndpointV2,
  ): AndroidRecordingFactsV2 {
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val diagnostics = JuceBridge.getEngineDiagnosticsJNI()
    val inputStream = AndroidOboeOutputFactsV2.fromMap(currentOboeInputFactsV2())
    val outputStream = AndroidOboeOutputFactsV2.fromMap(currentOboeFactsV2())
    val input = inputStream.routedDeviceId?.let { id ->
      inputEndpointsV2().singleOrNull { it.id == id }
    }
    val output = outputStream.routedDeviceId?.let { id ->
      outputEndpointsV2().singleOrNull { it.id == id }
    }
    return AndroidRecordingFactsV2(
      ownedByV2 = engineOwnership == EngineOwnership.V2_SESSION,
      sourceOutput = sourceOutput,
      actualInput = input,
      actualOutput = output,
      audioMode = audioManager.mode,
      bluetoothCommunicationDeviceSelected =
        bluetoothCommunicationDeviceSelectedV2(audioManager),
      bluetoothScoActive =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S && audioManager.isBluetoothScoOn,
      deviceOpen = diagnostics["deviceOpen"] == true,
      callbackAttached = diagnostics["audioCallbackAttached"] == true,
      activeInputChannels =
        (diagnostics["inputChannelCount"] as? Number)?.toInt() ?: 0,
      activeOutputChannels =
        (diagnostics["outputChannelCount"] as? Number)?.toInt() ?: 0,
      sampleRateHz = (diagnostics["sampleRate"] as? Number)?.toDouble() ?: 0.0,
      bufferFrames = (diagnostics["bufferSize"] as? Number)?.toInt() ?: 0,
      inputStream = inputStream,
      outputStream = outputStream,
    )
  }

  private fun validatePreparedRecordingV2(operation: RecordingOperationV2): String {
    if (
      operation.cancelled.get() ||
      recordingCancellationRequestedV2.get() ||
      operation.generation != audioRouteGenerationV2
    ) {
      return "stale_generation"
    }
    val facts = currentRecordingFactsV2(operation.sourceOutput)
    val readiness = AndroidRecordingReadinessV2.validate(facts)
    if (readiness != "ok") return readiness
    val verifiedInput = operation.verifiedInput ?: return "actual_state_unavailable"
    val verifiedOutput = operation.verifiedOutput ?: return "actual_state_unavailable"
    if (
      facts.actualInput?.fingerprint != verifiedInput.fingerprint ||
      facts.actualOutput?.fingerprint != verifiedOutput.fingerprint
    ) {
      return "route_unstable"
    }
    return "ok"
  }

  private fun audioModeName(mode: Int): String =
    when (mode) {
      AudioManager.MODE_NORMAL -> "MODE_NORMAL"
      AudioManager.MODE_RINGTONE -> "MODE_RINGTONE"
      AudioManager.MODE_IN_CALL -> "MODE_IN_CALL"
      AudioManager.MODE_IN_COMMUNICATION -> "MODE_IN_COMMUNICATION"
      else -> "MODE_UNKNOWN($mode)"
    }

  private fun intentWireValueV2(): String = when (audioRouteIntentV2) {
    AudioRouteIntentV2.PLAYBACK_ONLY -> "playbackOnly"
    AudioRouteIntentV2.PREPARING_RECORDING -> "preparingRecording"
    AudioRouteIntentV2.RECORDING -> "recording"
  }

  private fun lifecycleUnavailableSnapshotV2(): Map<String, Any?> = mapOf(
    "schemaVersion" to 1,
    "capturedAtUtc" to Instant.now().toString(),
    "implementation" to "v2",
    "generation" to audioRouteGenerationV2.takeIf { audioRouteMonitoringV2 },
    "transitionId" to audioRouteTransitionIdV2.takeIf { audioRouteMonitoringV2 },
    "coordinatorManaged" to audioRouteMonitoringV2,
    "captureConsistency" to "unavailable",
    "intent" to intentWireValueV2(),
    "inputs" to emptyList<Map<String, Any?>>(),
    "outputs" to emptyList<Map<String, Any?>>(),
    "session" to emptyMap<String, Any?>(),
    "juce" to emptyMap<String, Any?>(),
    "unavailableReasons" to mapOf(
      "snapshot" to "lifecycleTransitionInProgress",
    ),
    "duplexProbe" to duplexProbeFactsV2,
  )

  @Suppress("DEPRECATION")
  private fun capturePlaybackSnapshotV2(
    implementationOverride: String? = null,
    extraUnavailable: Map<String, String> = emptyMap(),
  ): Map<String, Any?> {
    if (lifecycleTransitionInProgressV2) return lifecycleUnavailableSnapshotV2()
    val started = SystemClock.elapsedRealtimeNanos()
    val firstRoute = resolveMediaRouteV2()
    val diagnostics = JuceBridge.getEngineDiagnosticsJNI()
    val facts = currentPlaybackFactsV2()
    val oboe = currentOboeFactsV2()
    val oboeInput = currentOboeInputFactsV2()
    val secondRoute = resolveMediaRouteV2()
    val routedDeviceId = (oboe["routedDeviceId"] as? Number)
      ?.toInt()
      ?.takeIf { it > 0 }
    val routedEndpoint = routedDeviceId?.let { id ->
      outputEndpointsV2().singleOrNull { it.id == id }
    }
    val routedInputDeviceId = (oboeInput["routedDeviceId"] as? Number)
      ?.toInt()
      ?.takeIf { it > 0 }
    val routedInputEndpoint = routedInputDeviceId?.let { id ->
      inputEndpointsV2().singleOrNull { it.id == id }
    }
    val firstFingerprint = firstRoute.endpoint?.fingerprint
    val secondFingerprint = secondRoute.endpoint?.fingerprint
    val probeOperation = recordingOperationV2?.takeIf {
      it.mode == IntentOperationModeV2.SYSTEM_SELECTED_PROBE
    }
    val verifiedProbeRoute =
      probeOperation?.verifiedInput?.id == routedInputEndpoint?.id &&
        probeOperation?.verifiedOutput?.id == routedEndpoint?.id
    val consistency = when {
      extraUnavailable.containsKey("coordinator") -> "unavailable"
      verifiedProbeRoute -> "stable"
      firstRoute.diagnosticCode != "ok" || secondRoute.diagnosticCode != "ok" -> "unavailable"
      firstFingerprint == secondFingerprint -> "stable"
      else -> "routeChangedDuringCapture"
    }
    val output = (secondRoute.endpoint ?: routedEndpoint)?.let { endpoint ->
      mapOf(
        "direction" to "output",
        "nativePortType" to endpoint.type.toString(),
        "normalizedKind" to endpoint.kind.wireValue,
        "uid" to endpoint.id.toString(),
        "name" to endpoint.name,
        "channelCount" to endpoint.channelCount,
      )
    }
    val input = routedInputEndpoint?.takeIf {
      audioRouteIntentV2 != AudioRouteIntentV2.PLAYBACK_ONLY
    }?.let { endpoint ->
      mapOf(
        "direction" to "input",
        "nativePortType" to endpoint.type.toString(),
        "normalizedKind" to endpoint.kind.wireValue,
        "uid" to endpoint.id.toString(),
        "name" to endpoint.name,
        "channelCount" to endpoint.channelCount,
      )
    }
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val communicationDevice = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      audioManager.communicationDevice
    } else {
      null
    }
    val unavailable = mutableMapOf<String, String>()
    if (output == null) {
      unavailable["route.outputEndpoint"] =
        if (secondRoute.diagnosticCode == "ok") "notObservableOnThisAndroidVersion"
        else secondRoute.diagnosticCode
    }
    if (oboe["available"] != true) {
      unavailable["juce.oboe"] = "bluetoothMediaPolicyStreamUnavailable"
    }
    if (oboe["xRunCount"] == null) {
      unavailable["juce.xRunCount"] = "notReportedByActiveOboeStream"
    }
    unavailable.putAll(extraUnavailable)
    return mapOf(
      "schemaVersion" to 1,
      "capturedAtUtc" to Instant.now().toString(),
      "captureDurationMs" to
        ((SystemClock.elapsedRealtimeNanos() - started) / 1_000_000L).toInt(),
      "implementation" to
        (implementationOverride ?:
          if (v2SessionRequested) "v2" else "legacy"),
      "generation" to audioRouteGenerationV2.takeIf { audioRouteMonitoringV2 },
      "transitionId" to audioRouteTransitionIdV2.takeIf { audioRouteMonitoringV2 },
      "coordinatorManaged" to audioRouteMonitoringV2,
      "captureConsistency" to consistency,
      "intent" to intentWireValueV2(),
      "inputs" to listOfNotNull(input),
      "outputs" to listOfNotNull(output),
      "session" to mapOf(
        "category" to if (probeOperation != null) {
          "USAGE_VOICE_COMMUNICATION/CONTENT_TYPE_SPEECH"
        } else {
          "USAGE_MEDIA/CONTENT_TYPE_MUSIC"
        },
        "mode" to audioModeName(facts.audioMode),
        "sampleRateHz" to facts.sampleRateHz,
        "ioBufferDurationSeconds" to
          if (facts.sampleRateHz > 0.0 && facts.bufferFrames > 0) {
            facts.bufferFrames / facts.sampleRateHz
          } else {
            null
          },
        "inputChannelCount" to facts.activeInputChannels,
        "outputChannelCount" to facts.activeOutputChannels,
        "active" to null,
        "streamRunning" to (oboe["running"] as? Boolean),
        "communicationDeviceSelected" to (communicationDevice != null),
        "communicationDeviceType" to communicationDevice?.type?.toString(),
        "bluetoothScoActive" to
          (Build.VERSION.SDK_INT < Build.VERSION_CODES.S && audioManager.isBluetoothScoOn),
      ),
      "juce" to mapOf(
        "deviceOpen" to facts.deviceOpen,
        "audioCallbackAttached" to facts.callbackAttached,
        "sampleRateHz" to facts.sampleRateHz,
        "bufferFrames" to facts.bufferFrames,
        "activeInputChannels" to facts.activeInputChannels,
        "activeOutputChannels" to facts.activeOutputChannels,
        "inputDeviceName" to null,
        "inputOpen" to (facts.activeInputChannels > 0),
        "outputDeviceName" to diagnostics["outputDeviceName"],
        "realtimeCallbackCount" to diagnostics["realtimeCallbackCount"],
        "realtimeCallbackLastMs" to diagnostics["realtimeCallbackLastMs"],
        "realtimeCallbackMaxMs" to diagnostics["realtimeCallbackMaxMs"],
        "realtimeCallbackAverageMs" to diagnostics["realtimeCallbackAvgMs"],
        "realtimeCallbackBudgetMs" to diagnostics["realtimeCallbackBudgetMs"],
        "realtimeCallbackOverBudgetCount" to
          diagnostics["realtimeCallbackOverBudgetCount"],
        "xRunCount" to oboe["xRunCount"],
        "requestedSampleRateHz" to
          (oboe["requestedSampleRateHz"] as? Number)?.takeIf { it.toInt() > 0 },
        "requestedBufferFrames" to
          (oboe["requestedBufferFrames"] as? Number)?.takeIf { it.toInt() > 0 },
        "oboeSampleRateHz" to oboe["sampleRateHz"],
        "oboeBufferFrames" to oboe["bufferFrames"],
        "audioBackend" to oboe["audioBackend"],
        "performanceMode" to oboe["performanceMode"],
        "sharingMode" to oboe["sharingMode"],
        "bufferCapacityFrames" to oboe["bufferCapacityFrames"],
        "framesPerBurst" to oboe["framesPerBurst"],
        "framesPerCallback" to
          (oboe["framesPerCallback"] as? Number)?.takeIf { it.toInt() > 0 },
        "streamState" to oboe["streamState"],
        "routedDeviceId" to oboe["routedDeviceId"]?.toString(),
        "inputStreamState" to oboeInput["streamState"],
        "inputRoutedDeviceId" to oboeInput["routedDeviceId"]?.toString(),
      ),
      "unavailableReasons" to unavailable,
      "duplexProbe" to duplexProbeFactsV2,
    )
  }

  private fun playbackStartupResult(
    success: Boolean,
    diagnosticCode: String,
    snapshot: Map<String, Any?>? = null,
  ): Map<String, Any?> = mapOf(
    "success" to success,
    "diagnosticCode" to diagnosticCode,
    "snapshot" to (snapshot ?: mapOf(
      "schemaVersion" to 1,
      "capturedAtUtc" to Instant.now().toString(),
      "implementation" to "v2",
      "coordinatorManaged" to false,
      "captureConsistency" to "unavailable",
      "inputs" to emptyList<Map<String, Any?>>(),
      "outputs" to emptyList<Map<String, Any?>>(),
      "session" to emptyMap<String, Any?>(),
      "juce" to emptyMap<String, Any?>(),
      "unavailableReasons" to mapOf("startup" to diagnosticCode),
    )),
  )

  private fun initialisePlaybackV2(): Map<String, Any?> {
    if (engineOwnership != EngineOwnership.NONE) {
      return playbackStartupResult(false, "implementation_conflict")
    }
    v2SessionRequested = true
    lifecycleDisposedV2 = false
    lifecycleTransitionInProgressV2 = false
    audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY
    recordingOperationV2 = null
    recordingCancellationRequestedV2.set(false)
    duplexProbeFactsV2 = null

    return try {
      initialisePlaybackV2Unchecked()
    } catch (error: Exception) {
      Log.e("JuceAudioEngine", "Android V2 startup failed", error)
      if (engineOwnership == EngineOwnership.V2_SESSION) {
        cleanupFailedPlaybackV2()
      } else {
        JuceBridge.resetPlaybackPolicyV2JNI()
      }
      playbackStartupResult(false, "actual_state_unavailable")
    }
  }

  private fun initialisePlaybackV2Unchecked(): Map<String, Any?> {
    JuceBridge.resetPlaybackPolicyV2JNI()
    val expectedRoute = resolveMediaRouteV2()
    if (expectedRoute.diagnosticCode != "ok") {
      return playbackStartupResult(
        false,
        expectedRoute.diagnosticCode,
        capturePlaybackSnapshotV2(implementationOverride = "v2"),
      )
    }

    engineOwnership = EngineOwnership.V2_SESSION
    verifiedPlaybackRouteV2 = expectedRoute.endpoint
    setAndroidStreamPolicyV2(
      if (expectedRoute.isBluetooth) AndroidStreamPolicyV2.BLUETOOTH_MEDIA
      else AndroidStreamPolicyV2.NORMAL,
    )
    preparePlaybackOnlyModeV2()
    if (!JuceBridge.initialisePlaybackV2JNI()) {
      cleanupFailedPlaybackV2()
      return playbackStartupResult(false, "juce_open_failed")
    }

    val snapshot = capturePlaybackSnapshotV2()
    if (
      bluetoothMediaPolicyActiveV2 &&
      snapshot["captureConsistency"] != "stable"
    ) {
      val consistency = snapshot["captureConsistency"]?.toString()
      cleanupFailedPlaybackV2()
      return playbackStartupResult(
        false,
        if (consistency == "routeChangedDuringCapture") "route_unstable"
        else "bluetooth_route_unverified",
        snapshot,
      )
    }
    val code = AndroidPlaybackReadinessV2.validate(currentPlaybackFactsV2())
    if (code != "ok") {
      cleanupFailedPlaybackV2()
      return playbackStartupResult(false, code, snapshot)
    }
    if (bluetoothMediaPolicyActiveV2) {
      val bluetoothCode = validateVerifiedBluetoothRouteV2(
        expectedRoute.endpoint!!,
        resolveMediaRouteV2(),
        currentOboeFactsV2(),
      )
      if (bluetoothCode != "ok") {
        cleanupFailedPlaybackV2()
        return playbackStartupResult(false, bluetoothCode, snapshot)
      }
    }
    verifiedPlaybackFingerprintV2 = currentEffectiveRouteStateV2().fingerprint
    return playbackStartupResult(true, "ok", snapshot)
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
      return !hadRoutingAnomaly && JuceBridge.preparePlaybackGraphJNI(reason)
    }

    val outputName = JuceBridge.getCurrentOutputDeviceNameJNI().trim()
    val hasActiveOutputRoute = JuceBridge.getActiveOutputChannelCountJNI() > 0
    val shouldReopenPlaybackRoute =
      hadRoutingAnomaly || outputName.isEmpty() || !hasActiveOutputRoute || hasLingeringInputRoute
    if (!shouldReopenPlaybackRoute) {
      return JuceBridge.preparePlaybackGraphJNI(reason)
    }

    if (hasLingeringInputRoute) {
      Log.w(
        "JuceAudioEngine",
        "Recovering playback-only route with active inputs still open: $reason",
      )
    }

    val resetOk = JuceBridge.hardResetPlaybackOnlyRouteJNI("preparePlaybackRoute:$reason")
    normalizeAudioModeAfterRecordingStop()
    return resetOk && JuceBridge.preparePlaybackGraphJNI(reason)
  }

  private fun restoreBluetoothPlaybackAfterRecordingStop() {
    normalizeAudioModeAfterRecordingStop()
    JuceBridge.hardResetPlaybackOnlyRouteJNI("postRecordBluetoothReset")
    normalizeAudioModeAfterRecordingStop()
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val args = argsFrom(call)

    if (
      engineOwnership == EngineOwnership.V2_SESSION &&
      call.method in setOf(
        "initialise",
        "selectInputDevice",
        "prepareRecordingInputs",
        "refreshAudioRoute",
        "preparePlaybackRoute",
        "setLiveInputMonitoringEnabled",
        "stopRecordingWithoutPlaybackRestore",
        "restoreBluetoothPlaybackAfterRecordingStop",
      )
    ) {
      result.error(
        "implementation_conflict",
        "Legacy audio operation is unavailable in a Bluetooth 2.0 session",
        null,
      )
      return
    }

    try {
      when (call.method) {
        "getPlatformVersion" -> {
          result.success("Android ${android.os.Build.VERSION.RELEASE}")
        }
        "initialise" -> {
          if (engineOwnership == EngineOwnership.V2_SESSION) {
            result.error("implementation_conflict", "Bluetooth 2.0 owns the engine", null)
            return
          }
          normalizeAudioModeAfterRecordingStop()
          v2SessionRequested = false
          JuceBridge.initialiseEngineJNI()
          preparePlaybackRoute("initialise")
          engineOwnership = EngineOwnership.LEGACY
          result.success(null)
        }
        "initialisePlaybackV2" -> {
          result.success(initialisePlaybackV2())
        }
        "getAudioRouteSnapshotV2" -> {
          result.success(capturePlaybackSnapshotV2())
        }
        "validatePlaybackV2" -> {
          result.success(validatePlaybackV2Now())
        }
        "startAudioRouteMonitoringV2" -> {
          result.success(startAudioRouteMonitoringV2())
        }
        "applyAudioRouteConfigurationV2" -> {
          result.success(applyAudioRouteConfigurationV2(args))
        }
        "setAudioRouteIntentV2" -> {
          setAudioRouteIntentV2(args, result)
        }
        "abortRecordingV2" -> {
          abortRecordingV2(args, result)
        }
        "stopAudioRouteMonitoringV2" -> {
          stopAudioRouteMonitoringV2()
          result.success(null)
        }
        "shutdown" -> {
          stopAudioRouteMonitoringV2()
          if (engineOwnership == EngineOwnership.V2_SESSION) {
            lifecycleDisposedV2 = true
            recordingOperationV2?.cancelled?.set(true)
            recordingOperationV2?.lifecycleSignal?.countDown()
            audioLifecycleExecutorV2.execute {
              recordingOperationV2?.let {
                cleanupRecordingOperationV2(it, restorePlayback = false)
              }
              JuceBridge.shutdownEngineSynchronouslyJNI()
              JuceBridge.resetPlaybackPolicyV2JNI()
              verifiedPlaybackRouteV2 = null
              verifiedPlaybackFingerprintV2 = ""
              bluetoothMediaPolicyActiveV2 = false
              v2SessionRequested = false
              audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY
              recordingOperationV2 = null
              engineOwnership = EngineOwnership.NONE
              mainHandler.post { result.success(null) }
            }
          } else {
            normalizeAudioModeAfterRecordingStop()
            // Ownership cannot be released until the shared native engine is
            // fully closed; otherwise a quickly reopened editor can overlap
            // Legacy teardown with V2 startup.
            JuceBridge.shutdownEngineSynchronouslyJNI()
            normalizeAudioModeAfterRecordingStop()
            JuceBridge.resetPlaybackPolicyV2JNI()
            verifiedPlaybackRouteV2 = null
            verifiedPlaybackFingerprintV2 = ""
            bluetoothMediaPolicyActiveV2 = false
            v2SessionRequested = false
            engineOwnership = EngineOwnership.NONE
            result.success(null)
          }
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
          val routeReady = if (engineOwnership == EngineOwnership.V2_SESSION) {
            validatePlaybackV2Now() == "ok" &&
              JuceBridge.playPlaybackV2JNI()
          } else {
            preparePlaybackRoute("play").also { if (it) JuceBridge.playJNI() }
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
              args.boolValue("forceIndividualRow"),
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
        "sendLiveMidiInputEvent" -> {
          result.success(
            JuceBridge.sendLiveMidiInputEventJNI(
              args.boolValue("noteOn"),
              args.intValue("channel", 1),
              args.intValue("pitch", 60),
              args.floatValue("velocity"),
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
              args.intValue("preferredRowId", -1),
            ),
          )
        }
        "insertRowAbove" -> {
          result.success(
            JuceBridge.insertRowAboveJNI(
              args.intValue("referenceRowId"),
              args.stringValue("name", "Row"),
              args.intValue("iconId"),
              args.intValue("preferredRowId", -1),
            ),
          )
        }
        "insertRowBelow" -> {
          result.success(
            JuceBridge.insertRowBelowJNI(
              args.intValue("referenceRowId"),
              args.stringValue("name", "Row"),
              args.intValue("iconId"),
              args.intValue("preferredRowId", -1),
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
            args.boolValue("forceIndividualRow"),
          )
          result.success(ok)
        }
        "removeTrackEffect" -> {
          JuceBridge.removeTrackEffectJNI(
            args.intValue("row"),
            args.intValue("effect"),
            args.boolValue("forceIndividualRow"),
          )
          result.success(null)
        }
        "reorderTrackEffects" -> {
          JuceBridge.reorderTrackEffectsJNI(
            args.intValue("row"),
            args.intValue("from"),
            args.intValue("to"),
            args.boolValue("forceIndividualRow"),
          )
          result.success(null)
        }
        "getTrackEffectsForRow" -> {
          result.success(JuceBridge.getTrackEffectsForRowJNI(args.intValue("row"), args.boolValue("forceIndividualRow")))
        }
        "getTrackEffectIdsForRow" -> {
          result.success(JuceBridge.getTrackEffectIdsForRowJNI(args.intValue("row"), args.boolValue("forceIndividualRow")))
        }
        "getTrackEffectInstanceIdsForRow" -> {
          result.success(JuceBridge.getTrackEffectInstanceIdsForRowJNI(args.intValue("row"), args.boolValue("forceIndividualRow")))
        }
        "setTrackEffect" -> {
          val value = args["value"]
          if (value != null) {
            JuceBridge.setTrackEffectJNI(
              args.intValue("row"),
              args.intValue("effect"),
              args.stringValue("paramId"),
              value,
              args.boolValue("forceIndividualRow"),
            )
          }
          result.success(null)
        }
        "bypassRowEffect" -> {
          JuceBridge.bypassRowEffectJNI(
            args.intValue("row"),
            args.intValue("effect"),
            args.boolValue("bypass"),
            args.boolValue("forceIndividualRow"),
          )
          result.success(null)
        }
        "getRowEffectBypassState" -> {
          result.success(
            JuceBridge.getRowEffectBypassStateJNI(
              args.intValue("row"),
              args.intValue("effect"),
              args.boolValue("forceIndividualRow"),
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
        "setMidiClipPluginParameter",
        "setMidiClipPluginAutomationPoints",
        "clearMidiClipPluginAutomation" -> {
          // Android's native instruments are not hosted MIDI plugins. The
          // shared editor still synchronizes this Apple/desktop-only contract
          // while loading a project, so acknowledge it without aborting load.
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
          val path = args.stringValue("path")
          runHeavyTask("decodeAudioMono16k", result) {
            JuceBridge.decodeAudioMono16kJNI(path).toList()
          }
        }
        "decodeAudioMono16kForAnalysis" -> {
          val path = args.stringValue("path")
          val maxOutputSamples = args.intValue("maxOutputSamples")
          runHeavyTask("decodeAudioMono16kForAnalysis", result) {
            JuceBridge.decodeAudioMono16kForAnalysisJNI(path, maxOutputSamples).toList()
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
        "preparePlaybackGraph" -> {
          result.success(JuceBridge.preparePlaybackGraphJNI(args.stringValue("reason")))
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
          if (engineOwnership == EngineOwnership.V2_SESSION) {
            startPreparedCaptureV2(args, result)
          } else {
            result.success(
              JuceBridge.startRecordingJNI(
                args.stringValue("path"),
                args.intValue("channelStart"),
                args.intValue("channelCount"),
              ),
            )
          }
        }
        "stopRecording" -> {
          if (engineOwnership == EngineOwnership.V2_SESSION) {
            stopPreparedCaptureV2(result)
          } else {
            runHeavyTask("stopRecording", result) {
              // Preserve Android's established route restoration order while
              // keeping WAV flushing and device restoration off Flutter's UI.
              normalizeAudioModeAfterRecordingStop()
              val captureResult = JuceBridge.stopRecordingJNI()
              normalizeAudioModeAfterRecordingStop()
              mainHandler.postDelayed({
                normalizeAudioModeAfterRecordingStop()
              }, 250L)
              captureResult
            }
          }
        }
        "stopRecordingWithoutPlaybackRestore" -> {
          runHeavyTask("stopRecordingWithoutPlaybackRestore", result) {
            val captureResult = JuceBridge.stopRecordingWithoutPlaybackRestoreJNI()
            normalizeAudioModeAfterRecordingStop()
            captureResult
          }
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
    stopAudioRouteMonitoringV2()
    if (engineOwnership == EngineOwnership.V2_SESSION) {
      lifecycleDisposedV2 = true
      recordingOperationV2?.cancelled?.set(true)
      audioLifecycleExecutorV2.execute {
        recordingOperationV2?.let {
          cleanupRecordingOperationV2(it, restorePlayback = false)
        }
        JuceBridge.shutdownEngineSynchronouslyJNI()
        JuceBridge.resetPlaybackPolicyV2JNI()
        verifiedPlaybackRouteV2 = null
        verifiedPlaybackFingerprintV2 = ""
        bluetoothMediaPolicyActiveV2 = false
        v2SessionRequested = false
        audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY
        recordingOperationV2 = null
        engineOwnership = EngineOwnership.NONE
      }
    }
    methodChannel.setMethodCallHandler(null)
    eventsChannel.setStreamHandler(null)
    logsChannel.setStreamHandler(null)
    promptAnalysisService.close()
    heavyWorkExecutor.shutdown()
    audioLifecycleExecutorV2.shutdown()
    eventsSink = null
    logsSink = null
    sharedInstance = null
  }
}
