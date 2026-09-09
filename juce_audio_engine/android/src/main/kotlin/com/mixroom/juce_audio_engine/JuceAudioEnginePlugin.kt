package com.mixroom.juce_audio_engine

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
  private enum class AudioRouteIntentV2 {
    PLAYBACK_ONLY,
    MONITORING,
    PREPARING_RECORDING,
    RECORDING,
  }
  private enum class IntentOperationModeV2 {
    STANDARD,
    SYSTEM_SELECTED_RECORDING,
    SYSTEM_SELECTED_MONITORING,
  }

  private enum class InputLifecyclePurposeV2 { RECORDING, MONITORING }

  private fun IntentOperationModeV2.ownsExplicitRouteTransaction(): Boolean =
    this != IntentOperationModeV2.STANDARD

  private fun IntentOperationModeV2.reportsDuplexFacts(): Boolean =
    this != IntentOperationModeV2.STANDARD

  private fun RecordingOperationV2.usesBluetoothDuplexRoute(): Boolean =
    routeAdapter == AndroidRecordingRouteAdapterV2.BLUETOOTH_COMMUNICATION

  private fun RecordingOperationV2.usesSystemSelectedRoute(): Boolean =
    routeAdapter == AndroidRecordingRouteAdapterV2.SYSTEM_SELECTED

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
    val routeAdapter: AndroidRecordingRouteAdapterV2 =
      AndroidRecordingRouteAdapterV2.BUILT_IN,
    val recordingChannelStart: Int = 0,
    val recordingChannelCount: Int = 1,
    val purpose: InputLifecyclePurposeV2 = InputLifecyclePurposeV2.RECORDING,
    val monitoringTargetRow: Int = 0,
    val bluetoothSelectionMode: AndroidBluetoothRouteSelectionModeV2? = null,
    val startedNanos: Long = SystemClock.elapsedRealtimeNanos(),
    val cancelled: AtomicBoolean = AtomicBoolean(false),
    val routeInvalidated: AtomicBoolean = AtomicBoolean(false),
    val cleanupClaimed: AtomicBoolean = AtomicBoolean(false),
    val cleanupPlan: AndroidRecordingCleanupPlanV2 = AndroidRecordingCleanupPlanV2(),
    val communicationRouteSelected: AtomicBoolean = AtomicBoolean(false),
    val legacyScoState: AndroidLegacyScoStateV2 = AndroidLegacyScoStateV2(),
    val nativeOutputEpochGate: AndroidNativeStreamEpochGateV2 =
      AndroidNativeStreamEpochGateV2(),
    @Volatile var verifiedInput: AndroidRouteEndpointV2? = null,
    @Volatile var verifiedOutput: AndroidRouteEndpointV2? = null,
    @Volatile var expectedCommunicationOutput: AndroidRouteEndpointV2? = null,
    @Volatile var phase: String = "preparing",
    @Volatile var callbackCount: Int = 0,
    @Volatile var terminalCause: String? = null,
    @Volatile var cleanupOutcome: String = "pending",
    @Volatile var lifecycleSignal: CountDownLatch? = null,
    @Volatile var legacyScoReceiver: BroadcastReceiver? = null,
  )

  private lateinit var methodChannel: MethodChannel
  private lateinit var eventsChannel: EventChannel
  private lateinit var logsChannel: EventChannel
  private val heavyWorkExecutor: ExecutorService = Executors.newSingleThreadExecutor()
  private val midiPreparationExecutor: ExecutorService = Executors.newFixedThreadPool(2)
  private val audioLifecycleExecutorV2: ExecutorService = Executors.newSingleThreadExecutor()
  private val mainHandler = Handler(Looper.getMainLooper())
  private var instrumentExtractionFuture: Future<*>? = null
  private lateinit var applicationContext: Context
  private lateinit var promptAnalysisService: PromptAnalysisService
  @Volatile private var engineOwnership = EngineOwnership.NONE
  @Volatile private var verifiedPlaybackRouteV2: AndroidRouteEndpointV2? = null
  @Volatile private var verifiedPlaybackOutputEpochV2: Long? = null
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
          addedDevices = addedDevices.map {
            AndroidRouteDeviceChangeV2(
              id = it.id,
              type = it.type,
              isSource = it.isSource,
              isSink = it.isSink,
            )
          },
        )
      }

      override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
        val removedDeviceIds = removedDevices.mapTo(mutableSetOf()) { it.id }
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

  // Keep the stored type API-neutral so loading the plugin remains safe on
  // Android 10-11, where OnCommunicationDeviceChangedListener does not exist.
  @Volatile private var communicationDeviceCallbackV2: Any? = null

  private fun handleCommunicationDeviceChangedV2(device: AudioDeviceInfo?) {
    val operation = recordingOperationV2 ?: return
    val expected = operation.expectedCommunicationOutput ?: return
    if (
      !audioRouteMonitoringV2 ||
      !operation.usesBluetoothDuplexRoute() ||
      !operation.communicationRouteSelected.get() ||
      operation.cleanupClaimed.get() ||
      device?.id == expected.id
    ) {
      return
    }

    handleAudioRouteSignalV2(
      AndroidRouteSignalKindV2.COMMUNICATION_DEVICE_CHANGED,
      emptySet(),
    )
  }

  private var eventsSink: EventChannel.EventSink? = null
  private var logsSink: EventChannel.EventSink? = null

  companion object {
    private var sharedInstance: JuceAudioEnginePlugin? = null
    private val processV2TeardownGate = AndroidLifecycleTeardownGateV2()

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
    nativeSetRouteEventTargetV2(true)
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

  private fun <T> runMidiPreparationTask(
    taskName: String,
    result: MethodChannel.Result,
    task: () -> T,
  ) {
    midiPreparationExecutor.execute {
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

  private fun selectCleanupDispositionV2(
    operation: RecordingOperationV2,
    disposition: AndroidRecordingCleanupDispositionV2,
  ): AndroidRecordingCleanupDispositionV2 = operation.cleanupPlan.select(disposition)

  private fun verifiedOutputEpochV2(
    facts: Map<String, Any> = currentOboeFactsV2(),
  ): Long? = (facts["streamEpoch"] as? Number)?.toLong()?.takeIf { it > 0L }

  private fun commitVerifiedPlaybackOutputEpochV2(
    facts: Map<String, Any> = currentOboeFactsV2(),
  ) {
    verifiedPlaybackOutputEpochV2 = verifiedOutputEpochV2(facts)
  }

  private fun adoptCurrentPlaybackAfterCommittedRecoveryV2(): Boolean {
    if (AndroidPlaybackReadinessV2.validate(currentPlaybackFactsV2()) != "ok") {
      return false
    }
    val actual = currentEffectiveRouteStateV2()
    if (actual.bluetoothCommunicationActive) return false
    val actualOutput = actual.actualEndpoint ?: actual.resolution.endpoint
      ?: return false
    val outputFacts = currentOboeFactsV2()
    val code = AndroidLiveRouteValidatorV2.validate(
      actual.resolution,
      actual.resolution,
      actual.actualEndpoint,
      AndroidOboeOutputFactsV2.fromMap(outputFacts),
      acceptSystemSelectedReplacement = true,
    )
    if (code != "ok") return false

    verifiedPlaybackRouteV2 = actualOutput
    audioRouteFingerprintV2 = actual.fingerprint
    verifiedPlaybackFingerprintV2 = actual.fingerprint
    commitVerifiedPlaybackOutputEpochV2(outputFacts)
    return true
  }

  private fun postDeferredNativeDisconnectV2(
    operation: RecordingOperationV2,
    streamEpoch: Long,
  ) {
    mainHandler.post {
      if (recordingOperationV2 !== operation || streamEpoch <= 0L) return@post
      handleAudioRouteSignalV2(
        AndroidRouteSignalKindV2.NATIVE_STREAM_DISCONNECTED,
        emptySet(),
        requiresReconfiguration = true,
      )
    }
  }

  private fun commitRecordingOutputEpochV2(
    operation: RecordingOperationV2,
    streamEpoch: Long?,
  ): Boolean {
    val acceptedEpoch = streamEpoch?.takeIf { it > 0L }
    return operation.nativeOutputEpochGate.commit(acceptedEpoch)
  }

  private fun reconcileRecordingOutputEpochV2(
    operation: RecordingOperationV2?,
    facts: Map<String, Any>,
  ): Boolean {
    if (operation == null) return false
    val outputEpoch = verifiedOutputEpochV2(facts)
    val deferredDisconnect = commitRecordingOutputEpochV2(operation, outputEpoch)
    if (deferredDisconnect && outputEpoch != null) {
      selectCleanupDispositionV2(
        operation,
        AndroidRecordingCleanupDispositionV2.CLOSE_ONLY,
      )
      postDeferredNativeDisconnectV2(operation, outputEpoch)
    }
    return deferredDisconnect
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
    if (!operation.mode.reportsDuplexFacts()) return
    duplexProbeFactsV2 = mapOf(
      "status" to status,
      "diagnosticCode" to diagnosticCode,
      "validationStage" to operation.phase,
      "phase" to operation.phase,
      "terminalCause" to operation.terminalCause,
      "actualCallbackCount" to operation.callbackCount,
      "cleanupOutcome" to operation.cleanupOutcome,
      "selectionMode" to
        when {
          operation.usesSystemSelectedRoute() ->
            "androidSystemSelectedMedia"
          operation.usesBluetoothDuplexRoute() ->
            operation.bluetoothSelectionMode?.diagnosticName
          else -> null
        },
      "physicalValidationPending" to
        (operation.bluetoothSelectionMode ==
          AndroidBluetoothRouteSelectionModeV2.LEGACY_SCO),
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

  private fun inputDeviceInfosV2(): List<Map<String, Any>> {
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    return try {
      val devices = audioManager
        .getDevices(AudioManager.GET_DEVICES_INPUTS)
        .filter { it.isSource }
      val outputKind = resolveMediaRouteV2().endpoint?.kind
      val matching = devices.filter { device ->
        val kind = classifyAndroidRouteKindV2(device.type)
        when (outputKind) {
          AndroidRouteKindV2.BLUETOOTH_MEDIA,
          AndroidRouteKindV2.BLUETOOTH_DUPLEX ->
            kind == AndroidRouteKindV2.BLUETOOTH_DUPLEX
          AndroidRouteKindV2.BLUETOOTH_LE ->
            kind == AndroidRouteKindV2.BLUETOOTH_LE ||
              kind == AndroidRouteKindV2.BLUETOOTH_DUPLEX
          AndroidRouteKindV2.WIRED -> kind == AndroidRouteKindV2.WIRED
          AndroidRouteKindV2.EXTERNAL -> kind == AndroidRouteKindV2.EXTERNAL
          AndroidRouteKindV2.BUILT_IN -> kind == AndroidRouteKindV2.BUILT_IN
          else -> false
        }
      }
      val defaultId = matching.singleOrNull()?.id
      devices.map { device ->
        val endpoint = device.toRouteEndpointV2()
        mapOf(
          "uid" to device.id.toString(),
          "name" to device.productName?.toString().orEmpty(),
          "channelCount" to (endpoint.channelCount ?: 0),
          "isBluetoothInput" to
            (endpoint.kind == AndroidRouteKindV2.BLUETOOTH_DUPLEX ||
              endpoint.kind == AndroidRouteKindV2.BLUETOOTH_LE),
          "isBuiltIn" to (endpoint.kind == AndroidRouteKindV2.BUILT_IN),
          "isDefault" to (device.id == defaultId),
          "transport" to endpoint.kind.wireValue,
        )
      }
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
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val communicationListener =
          AudioManager.OnCommunicationDeviceChangedListener(
            ::handleCommunicationDeviceChangedV2,
          )
        communicationDeviceCallbackV2 = communicationListener
        audioManager.addOnCommunicationDeviceChangedListener(
          applicationContext.mainExecutor,
          communicationListener,
        )
      }
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
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val communicationListener = communicationDeviceCallbackV2
      try {
        if (communicationListener is AudioManager.OnCommunicationDeviceChangedListener) {
          audioManager.removeOnCommunicationDeviceChangedListener(
            communicationListener,
          )
        }
      } catch (_: IllegalArgumentException) {
      }
      communicationDeviceCallbackV2 = null
    }
    audioRouteFingerprintV2 = ""
    routeTransitionWasPlayingV2 = false
  }

  private fun handleAudioRouteSignalV2(
    signal: AndroidRouteSignalKindV2,
    removedDeviceIds: Set<Int>,
    addedDevices: List<AndroidRouteDeviceChangeV2> = emptyList(),
    requiresReconfiguration: Boolean = false,
  ) {
    if (Looper.myLooper() != Looper.getMainLooper()) {
      mainHandler.post {
        handleAudioRouteSignalV2(
          signal,
          removedDeviceIds,
          addedDevices,
          requiresReconfiguration,
        )
      }
      return
    }
    if (!audioRouteMonitoringV2 || engineOwnership != EngineOwnership.V2_SESSION) return
    var operation = recordingOperationV2
    if (
      AndroidIntentRouteObserverV2.isSelfGeneratedPlaybackActivity(
        lifecycleMutationActive = lifecycleTransitionInProgressV2,
        cleanupClaimed = operation?.cleanupClaimed?.get() == true,
        signal = signal,
      )
    ) {
      return
    }
    if (
      signal == AndroidRouteSignalKindV2.DEVICE_ADDED &&
      lifecycleTransitionInProgressV2 &&
      operation == null &&
      AndroidPlaybackTransitionOwnershipV2.ownsNotification(
        expected = expectedPlaybackTransitionV2,
        current = resolveMediaRouteV2(),
        availableOutputIds = outputEndpointsV2().mapTo(mutableSetOf()) { it.id },
        removedDeviceIds = emptySet(),
      )
    ) {
      return
    }
    val operationEndpointIds = operation?.let { activeOperation ->
      setOfNotNull(
        activeOperation.sourceOutput.id,
        activeOperation.expectedCommunicationOutput?.id,
        activeOperation.verifiedInput?.id,
        activeOperation.verifiedOutput?.id,
      )
    }
    val completedRecoveryOwnsSignal = operation?.let { completed ->
      completed.phase == "playbackCommitted" &&
        completed.routeInvalidated.get() &&
        completed.cleanupClaimed.get() &&
        AndroidCommittedRecoveryOwnershipV2.ownsLateSignal(
          signal = signal,
          removedDeviceIds = removedDeviceIds,
          completedOperationEndpointIds = operationEndpointIds.orEmpty(),
        )
    } == true
    if (completedRecoveryOwnsSignal) {
      // Android can publish source/SCO removal after its replacement media
      // stream has already auto-restarted. Adopt that verified running stream
      // inside the completed episode instead of reopening it a second time.
      if (adoptCurrentPlaybackAfterCommittedRecoveryV2()) return
    }
    if (operation?.phase == "playbackCommitted") {
      // A signal unrelated to the completed source/duplex endpoints belongs
      // to a genuinely new route episode.
      if (recordingOperationV2 === operation) recordingOperationV2 = null
      operation = null
    }
    val decision = AndroidIntentRouteObserverV2.classify(
      explicitTransactionActive =
        operation?.mode?.ownsExplicitRouteTransaction() == true,
      operationEndpointIds = operationEndpointIds,
      signal = signal,
      removedDeviceIds = removedDeviceIds,
      expectedCommunicationDeviceType = operation?.expectedCommunicationOutput?.type,
      addedDevices = addedDevices,
    )
    if (decision == AndroidIntentRouteDecisionV2.INFORMATIONAL) return
    if (
      operation?.routeInvalidated?.get() == true &&
      operation.cleanupClaimed.get() &&
      !lifecycleTransitionInProgressV2
    ) {
      // The first terminal signal owns the disconnect episode. Retain the
      // operation through current-output recovery so delayed native, device,
      // and communication callbacks cannot create a second generation.
      return
    }

    val cause = when (signal) {
      AndroidRouteSignalKindV2.DEVICE_ADDED -> "deviceInventoryChanged"
      AndroidRouteSignalKindV2.DEVICE_REMOVED -> "deviceRemoved"
      AndroidRouteSignalKindV2.COMMUNICATION_DEVICE_CHANGED ->
        "communicationDeviceChanged"
      AndroidRouteSignalKindV2.LEGACY_SCO_STATE_CHANGED ->
        "legacyScoDisconnected"
      AndroidRouteSignalKindV2.NATIVE_STREAM_DISCONNECTED ->
        "nativeStreamDisconnected"
      AndroidRouteSignalKindV2.PLAYBACK_ACTIVITY -> "mediaRouteChanged"
      AndroidRouteSignalKindV2.STARTUP -> "startupOutputChanged"
    }

    if (
      lifecycleTransitionInProgressV2 ||
      audioRouteIntentV2 != AudioRouteIntentV2.PLAYBACK_ONLY
    ) {
      val currentRecoveryLostAgain =
        requiresReconfiguration &&
          lifecycleTransitionInProgressV2 &&
          operation?.cleanupClaimed?.get() == true &&
          operation.routeInvalidated.get()
      if (
        operation != null &&
        !currentRecoveryLostAgain &&
        !operation.routeInvalidated.compareAndSet(false, true)
      ) {
        return
      }
      operation?.let {
        selectCleanupDispositionV2(
          it,
          AndroidRecordingCleanupDispositionV2.CLOSE_ONLY,
        )
      }
      recordingCancellationRequestedV2.set(true)
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
          "requiresReconfiguration" to requiresReconfiguration,
          "snapshot" to lifecycleUnavailableSnapshotV2(),
        ),
      )
      return
    }

    val effective = currentEffectiveRouteStateV2()
    if (!requiresReconfiguration && effective.fingerprint == audioRouteFingerprintV2) return

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
        "requiresReconfiguration" to requiresReconfiguration,
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
          verifiedPlaybackOutputEpochV2 = null
          deliveredOutcome = IntentOutcomeV2("failure", "route_unstable")
        } else {
          verifiedPlaybackRouteV2 = actual
          audioRouteFingerprintV2 = committed.fingerprint
          verifiedPlaybackFingerprintV2 = committed.fingerprint
        }
      }
      val completedPlaybackRecovery =
        deliveredOutcome.status == "success" &&
          audioRouteIntentV2 == AudioRouteIntentV2.PLAYBACK_ONLY &&
          expectedPlaybackTransitionV2 != null
      lifecycleTransitionInProgressV2 = false
      expectedPlaybackTransitionV2 = null
      recordingOperationV2
        ?.takeIf { it.cleanupClaimed.get() }
        ?.let { completed ->
          if (completed.routeInvalidated.get() && completedPlaybackRecovery) {
            // Retain the completed operation as a bounded ownership tombstone.
            // Android may deliver removal/release callbacks after the verified
            // replacement output has committed. The next explicit operation
            // replaces it, while a genuinely new route signal clears it.
            completed.phase = "playbackCommitted"
          } else if (!completed.routeInvalidated.get() &&
            recordingOperationV2 === completed
          ) {
            recordingOperationV2 = null
          }
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
    deadlineNanos: Long? = null,
  ): String {
    val restorationGeneration = audioRouteGenerationV2
    val recoveringCurrentOutput =
      expectedOutput == null &&
        operation?.routeInvalidated?.get() == true &&
        operation.cleanupClaimed.get()
    val bluetoothOperation = operation?.takeIf {
      it.usesBluetoothDuplexRoute()
    }
    var restorationDeadlineNanos = deadlineNanos ?: bluetoothOperation?.let {
      SystemClock.elapsedRealtimeNanos() + TimeUnit.SECONDS.toNanos(5)
    }
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val releaseSignal = bluetoothOperation
      ?.takeIf {
        it.bluetoothSelectionMode ==
          AndroidBluetoothRouteSelectionModeV2.COMMUNICATION_DEVICE
      }
      ?.let { activeOperation ->
        activeOperation.expectedCommunicationOutput?.let { target ->
          val released = CountDownLatch(1)
          released to AudioManager.OnCommunicationDeviceChangedListener { device ->
            if (device?.id != target.id) released.countDown()
          }
        }
      }
    var mediaRouteMigrationToken = 0L
    var reopenedOperationEpoch: Long? = null
    fun finishMediaRouteMigrationV2() {
      if (mediaRouteMigrationToken == 0L) return
      JuceBridge.finishBluetoothMediaRouteMigrationV2JNI(
        mediaRouteMigrationToken,
      )
      mediaRouteMigrationToken = 0L
    }
    if (releaseSignal != null) {
      bluetoothOperation.phase = "releasingCommunicationDevice"
      bluetoothOperation.lifecycleSignal = releaseSignal.first
      try {
        audioManager.addOnCommunicationDeviceChangedListener(
          applicationContext.mainExecutor,
          releaseSignal.second,
        )
      } catch (_: SecurityException) {
        bluetoothOperation.lifecycleSignal = null
        return "actual_state_unavailable"
      } catch (_: IllegalStateException) {
        bluetoothOperation.lifecycleSignal = null
        return "actual_state_unavailable"
      }
    }
    return try {
      if (lifecycleDisposedV2) return "coordinator_disposed"
      if (bluetoothOperation != null) JuceBridge.quiescePlaybackV2JNI(true)
      var legacyReleaseCode = "ok"
      if (
        bluetoothOperation?.bluetoothSelectionMode ==
        AndroidBluetoothRouteSelectionModeV2.LEGACY_SCO
      ) {
        legacyReleaseCode = releaseLegacyScoRouteV2(
          bluetoothOperation,
          audioManager,
          requireNotNull(restorationDeadlineNanos),
          waitForRelease = true,
        )
      }
      preparePlaybackOnlyModeV2()
      if (legacyReleaseCode != "ok") return legacyReleaseCode

      // Communication-device release, not playback activity, is the settling
      // boundary for this explicit transaction. Oboe route readback below
      // remains authoritative for the final media endpoint.
      if (releaseSignal != null) {
        val activeOperation = requireNotNull(bluetoothOperation)
        val target = requireNotNull(activeOperation.expectedCommunicationOutput)
        // Cancellation can win before Android publishes the selected SCO
        // device. In that case clearCommunicationDevice() has no transition to
        // report, so pair the listener with an immediate state readback to
        // avoid waiting for an event that cannot occur.
        if (
          Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
          audioManager.communicationDevice?.id != target.id
        ) {
          releaseSignal.first.countDown()
        }
        val remainingNanos = requireNotNull(restorationDeadlineNanos) -
          SystemClock.elapsedRealtimeNanos()
        if (
          remainingNanos <= 0L ||
          !releaseSignal.first.await(remainingNanos, TimeUnit.NANOSECONDS)
        ) {
          Log.w("JuceAudioEngine", "Android V2 playback restore failed: communication_release")
          return "actual_state_unavailable"
        }
        if (
          !recoveringCurrentOutput &&
          (activeOperation.routeInvalidated.get() ||
            activeOperation.generation != audioRouteGenerationV2)
        ) {
          return "route_unstable"
        }
        if (lifecycleDisposedV2) return "coordinator_disposed"
      }

      val expectedRoute = expectedOutput?.let {
        AndroidMediaRouteResolutionV2(it, "ok")
      } ?: resolveMediaRouteV2()
      if (expectedRoute.diagnosticCode != "ok") return expectedRoute.diagnosticCode
      if (lifecycleDisposedV2) return "coordinator_disposed"
      if (expectedRoute.isBluetooth && restorationDeadlineNanos == null) {
        restorationDeadlineNanos =
          SystemClock.elapsedRealtimeNanos() + TimeUnit.SECONDS.toNanos(5)
      }
      expectedPlaybackTransitionV2 = expectedRoute
      setAndroidStreamPolicyV2(
        if (expectedRoute.isBluetooth) AndroidStreamPolicyV2.BLUETOOTH_MEDIA
        else AndroidStreamPolicyV2.NORMAL,
      )
      if (expectedRoute.isBluetooth) {
        operation?.phase = "awaitingNativeMediaRouteMigration"
        mediaRouteMigrationToken =
          JuceBridge.beginBluetoothMediaRouteMigrationV2JNI()
      }
      if (!JuceBridge.reconfigurePlaybackV2JNI()) {
        Log.w("JuceAudioEngine", "Android V2 playback restore failed: juce_reopen_failed")
        return "juce_reopen_failed"
      }
      var reopenedOutputFacts = currentOboeFactsV2()
      if (mediaRouteMigrationToken != 0L) {
        if (
          AndroidOboeOutputFactsV2.fromMap(reopenedOutputFacts).routedDeviceId !=
          expectedRoute.endpoint?.id
        ) {
          val mediaRemainingNanos = requireNotNull(restorationDeadlineNanos) -
            SystemClock.elapsedRealtimeNanos()
          val migrationObserved = mediaRemainingNanos > 0L &&
            JuceBridge.waitForBluetoothMediaRouteMigrationV2JNI(
              mediaRouteMigrationToken,
              TimeUnit.NANOSECONDS.toMillis(mediaRemainingNanos)
                .coerceIn(1L, 5000L)
                .toInt(),
            )
          if (!migrationObserved) {
            Log.w("JuceAudioEngine", "Android V2 playback restore failed: media_route")
            return "actual_state_unavailable"
          }
          // Once the expected migration was observed, later loss belongs to
          // the newly opened media stream and must reach the epoch owner.
          finishMediaRouteMigrationV2()
          val activeOperation = operation
          if (
            !recoveringCurrentOutput &&
            activeOperation != null &&
            (activeOperation.routeInvalidated.get() ||
              activeOperation.generation != audioRouteGenerationV2)
          ) {
            return "route_unstable"
          }
          activeOperation?.phase = "reopeningSettledMediaRoute"
          if (!JuceBridge.reconfigurePlaybackV2JNI()) {
            Log.w("JuceAudioEngine", "Android V2 settled media reopen failed")
            return "juce_reopen_failed"
          }
          reopenedOutputFacts = currentOboeFactsV2()
        } else {
          // The first reopen already owns exact A2DP. Do not let its real
          // disconnect be consumed as a migration signal during validation.
          finishMediaRouteMigrationV2()
        }
      }
      operation?.let { activeOperation ->
        val openedEpoch = verifiedOutputEpochV2(reopenedOutputFacts)
          ?: return "actual_state_unavailable"
        reopenedOperationEpoch = openedEpoch
        if (reconcileRecordingOutputEpochV2(activeOperation, reopenedOutputFacts)) {
          return "route_unstable"
        }
      }
      val callbackRemainingNanos = restorationDeadlineNanos?.minus(
        SystemClock.elapsedRealtimeNanos(),
      )
      if (callbackRemainingNanos != null && callbackRemainingNanos <= 0L) {
        Log.w("JuceAudioEngine", "Android V2 playback restore failed: callback_deadline")
        return if (
          operation?.routeInvalidated?.get() == true ||
          audioRouteGenerationV2 != restorationGeneration
        ) {
          "route_unstable"
        } else {
          "actual_state_unavailable"
        }
      }
      val callbackTimeoutMillis = callbackRemainingNanos?.let { remaining ->
        TimeUnit.NANOSECONDS.toMillis(remaining).coerceIn(1L, 5000L).toInt()
      } ?: 1000
      if (!JuceBridge.waitForV2CallbackReadyJNI(callbackTimeoutMillis)) {
        Log.w("JuceAudioEngine", "Android V2 playback restore failed: callback_unavailable")
        return if (
          operation?.routeInvalidated?.get() == true ||
          audioRouteGenerationV2 != restorationGeneration
        ) {
          "route_unstable"
        } else {
          "actual_state_unavailable"
        }
      }
      if (lifecycleDisposedV2) return "coordinator_disposed"

      var code = AndroidPlaybackReadinessV2.validate(currentPlaybackFactsV2())
      val actual = currentEffectiveRouteStateV2()
      val outputFacts = currentOboeFactsV2()
      if (code == "ok") {
        code = AndroidLiveRouteValidatorV2.validate(
          expectedRoute,
          actual.resolution,
          actual.actualEndpoint,
          AndroidOboeOutputFactsV2.fromMap(outputFacts),
          acceptSystemSelectedReplacement = expectedOutput == null,
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
      if (
        code == "ok" &&
        reopenedOperationEpoch != null &&
        verifiedOutputEpochV2(outputFacts) != reopenedOperationEpoch
      ) {
        code = "route_unstable"
      }
      if (lifecycleDisposedV2) {
        code = "coordinator_disposed"
      } else if (
        audioRouteGenerationV2 != restorationGeneration
      ) {
        code = "route_unstable"
      }
      if (code != "ok") {
        Log.w("JuceAudioEngine", "Android V2 playback restore failed: $code")
        return code
      }

      // A current-output recovery starts without an exact endpoint because
      // Android may expose one built-in endpoint before opening the stream and
      // route the stream to another equivalent built-in endpoint. Commit the
      // endpoint proven by Oboe so final delivery still rejects any later
      expectedPlaybackTransitionV2 = AndroidMediaRouteResolutionV2(actualOutput, "ok")
      verifiedPlaybackRouteV2 = actualOutput
      commitVerifiedPlaybackOutputEpochV2(outputFacts)
      audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY
      routeTransitionWasPlayingV2 = false
      "ok"
    } finally {
      if (releaseSignal != null) {
        try {
          audioManager.removeOnCommunicationDeviceChangedListener(releaseSignal.second)
        } catch (_: IllegalArgumentException) {
        }
      }
      finishMediaRouteMigrationV2()
      bluetoothOperation?.let { operation ->
        if (operation.lifecycleSignal === releaseSignal?.first) {
          operation.lifecycleSignal = null
        }
        if (
          operation.bluetoothSelectionMode ==
          AndroidBluetoothRouteSelectionModeV2.LEGACY_SCO
        ) {
          unregisterLegacyScoReceiverV2(operation)
        }
      }
    }
  }

  private fun cleanupRecordingOperationV2(
    operation: RecordingOperationV2,
    requestedDisposition: AndroidRecordingCleanupDispositionV2,
  ): String {
    selectCleanupDispositionV2(operation, requestedDisposition)
    if (!operation.cleanupClaimed.compareAndSet(false, true)) {
      return if (audioRouteIntentV2 == AudioRouteIntentV2.PLAYBACK_ONLY) "ok"
      else "actual_state_unavailable"
    }
    val disposition = operation.cleanupPlan.snapshotForCleanupWinner()
    val cleanupDeadlineNanos =
      SystemClock.elapsedRealtimeNanos() + TimeUnit.SECONDS.toNanos(5)
    // Deliberately closing the recording stream must not look like physical
    // loss. Exact restore commits the replacement output epoch below.
    operation.nativeOutputEpochGate.clear()
    JuceBridge.setLiveInputMonitoringEnabledJNI(false)
    if (JuceBridge.isRecordingJNI()) {
      JuceBridge.discardRecordingCaptureV2JNI()
    }
    val code = when (disposition) {
      AndroidRecordingCleanupDispositionV2.RESTORE_EXACT ->
        restorePlaybackOnlyV2(
          operation.sourceOutput,
          operation,
          cleanupDeadlineNanos,
        )
      AndroidRecordingCleanupDispositionV2.CLOSE_ONLY -> {
        JuceBridge.quiescePlaybackV2JNI(true)
        val audioManager =
          applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        releaseLegacyScoRouteV2(
          operation,
          audioManager,
          cleanupDeadlineNanos,
          waitForRelease = false,
        )
        preparePlaybackOnlyModeV2()
        setAndroidStreamPolicyV2(AndroidStreamPolicyV2.NORMAL)
        JuceBridge.resetPlaybackPolicyV2JNI()
        verifiedPlaybackOutputEpochV2 = null
        audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY
        "ok"
      }
    }
    if (code != "ok") {
      JuceBridge.quiescePlaybackV2JNI(true)
      setAndroidStreamPolicyV2(AndroidStreamPolicyV2.NORMAL)
      JuceBridge.resetPlaybackPolicyV2JNI()
      verifiedPlaybackRouteV2 = null
      verifiedPlaybackFingerprintV2 = ""
      verifiedPlaybackOutputEpochV2 = null
      audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY
    }
    operation.cleanupOutcome = when {
      disposition == AndroidRecordingCleanupDispositionV2.RESTORE_EXACT && code == "ok" ->
        "restored"
      disposition != AndroidRecordingCleanupDispositionV2.CLOSE_ONLY -> "restoreFailed"
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
      restoredOutput = if (
        disposition != AndroidRecordingCleanupDispositionV2.CLOSE_ONLY && code == "ok"
      ) {
        verifiedPlaybackRouteV2
      } else {
        null
      },
    )
    return code
  }

  private fun prepareBuiltInRecordingV2(
    generation: Long,
    channelStart: Int,
    channelCount: Int,
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
      recordingChannelStart = channelStart,
      recordingChannelCount = channelCount,
    )
    recordingOperationV2 = operation
    audioRouteIntentV2 = AudioRouteIntentV2.PREPARING_RECORDING
    preparePlaybackOnlyModeV2()
    setAndroidStreamPolicyV2(AndroidStreamPolicyV2.NORMAL)

    if (operation.cancelled.get() || generation != audioRouteGenerationV2) {
      val code = cleanupRecordingOperationV2(
        operation,
        requestedDisposition = if (operation.routeInvalidated.get()) {
          AndroidRecordingCleanupDispositionV2.CLOSE_ONLY
        } else {
          AndroidRecordingCleanupDispositionV2.RESTORE_EXACT
        },
      )
      return IntentOutcomeV2("failure", if (code == "ok") "recording_interrupted" else code)
    }
    if (!JuceBridge.prepareRecordingV2JNI(channelStart + channelCount)) {
      val code = cleanupRecordingOperationV2(
        operation,
        requestedDisposition = AndroidRecordingCleanupDispositionV2.RESTORE_EXACT,
      )
      return IntentOutcomeV2("failure", if (code == "ok") "juce_reopen_failed" else code)
    }
    if (!JuceBridge.waitForV2CallbackReadyJNI(1000)) {
      val code = cleanupRecordingOperationV2(
        operation,
        requestedDisposition = AndroidRecordingCleanupDispositionV2.RESTORE_EXACT,
      )
      return IntentOutcomeV2("failure", if (code == "ok") "actual_state_unavailable" else code)
    }
    if (operation.cancelled.get() || generation != audioRouteGenerationV2) {
      val code = cleanupRecordingOperationV2(
        operation,
        requestedDisposition = if (operation.routeInvalidated.get()) {
          AndroidRecordingCleanupDispositionV2.CLOSE_ONLY
        } else {
          AndroidRecordingCleanupDispositionV2.RESTORE_EXACT
        },
      )
      return IntentOutcomeV2("failure", if (code == "ok") "stale_generation" else code)
    }

    val facts = currentRecordingFactsV2(
      sourceOutput,
      channelStart + channelCount,
    )
    val readiness = AndroidRecordingReadinessV2.validate(facts)
    if (readiness != "ok") {
      val code = cleanupRecordingOperationV2(
        operation,
        requestedDisposition = AndroidRecordingCleanupDispositionV2.RESTORE_EXACT,
      )
      return IntentOutcomeV2("failure", if (code == "ok") readiness else code)
    }
    operation.verifiedInput = facts.actualInput
    operation.verifiedOutput = facts.actualOutput
    val outputEpoch = facts.outputStream.streamEpoch?.takeIf { it > 0L }
    if (commitRecordingOutputEpochV2(operation, outputEpoch)) {
      selectCleanupDispositionV2(
        operation,
        AndroidRecordingCleanupDispositionV2.CLOSE_ONLY,
      )
      operation.cancelled.set(true)
      if (outputEpoch != null) postDeferredNativeDisconnectV2(operation, outputEpoch)
      cleanupRecordingOperationV2(
        operation,
        AndroidRecordingCleanupDispositionV2.CLOSE_ONLY,
      )
      return IntentOutcomeV2("failure", "route_unstable")
    }
    return IntentOutcomeV2("success", "ok")
  }

  private fun failBluetoothDuplexV2(
    operation: RecordingOperationV2,
    diagnosticCode: String,
  ): IntentOutcomeV2 {
    val validationStage = operation.phase
    val restoreCode = cleanupRecordingOperationV2(
      operation,
      requestedDisposition = if (operation.routeInvalidated.get()) {
        AndroidRecordingCleanupDispositionV2.CLOSE_ONLY
      } else {
        AndroidRecordingCleanupDispositionV2.RESTORE_EXACT
      },
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

  private fun activateVerifiedMonitorGraphV2(
    targetRow: Int,
    channelStart: Int,
    channelCount: Int,
  ): Boolean {
    val facts = JuceBridge.activateLiveInputMonitoringV2JNI(
      targetRow,
      channelStart,
      channelCount,
    )
    return facts.boolValue("active") &&
      facts.intValue("targetRow", -1) == targetRow &&
      facts.intValue("channelStart", -1) == channelStart &&
      facts.intValue("channelCount") == channelCount &&
      facts.intValue("connectionCount") == channelCount
  }

  private fun prepareSystemSelectedDuplexV2(
    generation: Long,
    mode: IntentOperationModeV2,
    sourceOutput: AndroidRouteEndpointV2,
    channelStart: Int,
    channelCount: Int,
    purpose: InputLifecyclePurposeV2 = InputLifecyclePurposeV2.RECORDING,
    monitoringTargetRow: Int = 0,
  ): IntentOutcomeV2 {
    if (mode != IntentOperationModeV2.SYSTEM_SELECTED_RECORDING &&
      mode != IntentOperationModeV2.SYSTEM_SELECTED_MONITORING
    ) {
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
    val currentOutput = resolveActualOutputV2()
      ?: return IntentOutcomeV2("failure", "no_output")
    if (currentOutput.fingerprint != sourceOutput.fingerprint) {
      return IntentOutcomeV2("failure", "route_unstable")
    }
    val operation = RecordingOperationV2(
      id = recordingOperationIdV2.incrementAndGet(),
      generation = generation,
      sourceOutput = sourceOutput,
      mode = mode,
      routeAdapter = AndroidRecordingRouteAdapterV2.SYSTEM_SELECTED,
      recordingChannelStart = channelStart,
      recordingChannelCount = channelCount,
      purpose = purpose,
      monitoringTargetRow = monitoringTargetRow,
    )
    recordingOperationV2 = operation
    duplexProbeFactsV2 = null
    audioRouteIntentV2 = if (purpose == InputLifecyclePurposeV2.MONITORING) {
      AudioRouteIntentV2.MONITORING
    } else {
      AudioRouteIntentV2.PREPARING_RECORDING
    }
    val deadlineNanos = operation.startedNanos + TimeUnit.SECONDS.toNanos(5)

    preparePlaybackOnlyModeV2()
    val retainsBluetoothMedia =
      sourceOutput.kind == AndroidRouteKindV2.BLUETOOTH_MEDIA ||
        sourceOutput.kind == AndroidRouteKindV2.BLUETOOTH_LE
    setAndroidStreamPolicyV2(
      if (retainsBluetoothMedia) AndroidStreamPolicyV2.BLUETOOTH_MEDIA
      else AndroidStreamPolicyV2.NORMAL,
    )
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
      return failBluetoothDuplexV2(operation, "route_unstable")
    }

    operation.phase = "openingSystemSelectedDuplex"
    if (!JuceBridge.prepareSystemSelectedMediaDuplexV2JNI(channelStart + channelCount)) {
      operation.phase = "juceOpen"
      return failBluetoothDuplexV2(operation, "juce_reopen_failed")
    }
    val openedOutputEpoch = verifiedOutputEpochV2(currentOboeFactsV2())
    if (openedOutputEpoch == null) {
      operation.phase = "juceOpenFacts"
      return failBluetoothDuplexV2(operation, "actual_state_unavailable")
    }
    if (commitRecordingOutputEpochV2(operation, openedOutputEpoch)) {
      selectCleanupDispositionV2(
        operation,
        AndroidRecordingCleanupDispositionV2.CLOSE_ONLY,
      )
      operation.cancelled.set(true)
      postDeferredNativeDisconnectV2(operation, openedOutputEpoch)
      operation.phase = "physicalRouteInvalidation"
      return failBluetoothDuplexV2(operation, "route_unstable")
    }
    val openedFacts = currentRecordingFactsV2(
      sourceOutput,
      channelStart + channelCount,
    )
    operation.verifiedInput = openedFacts.actualInput
    operation.verifiedOutput = openedFacts.actualOutput

    val remainingNanos = deadlineNanos - SystemClock.elapsedRealtimeNanos()
    if (remainingNanos <= 0L) {
      operation.phase = "callbackTimeout"
      return failBluetoothDuplexV2(operation, "actual_state_unavailable")
    }
    val callbackTimeoutMillis = TimeUnit.NANOSECONDS.toMillis(remainingNanos)
      .coerceIn(1L, 5000L)
      .toInt()
    if (!JuceBridge.waitForV2CallbackReadyJNI(callbackTimeoutMillis)) {
      operation.phase = "callback"
      return failBluetoothDuplexV2(operation, "actual_state_unavailable")
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
      return failBluetoothDuplexV2(operation, "route_unstable")
    }

    val facts = currentRecordingFactsV2(
      sourceOutput,
      channelStart + channelCount,
    )
    val readiness = if (purpose == InputLifecyclePurposeV2.MONITORING) {
      AndroidMonitoringReadinessV2.validate(facts)
    } else {
      AndroidSystemSelectedDuplexReadinessV2.validate(facts)
    }
    if (readiness != "ok") {
      operation.phase = "duplexValidation"
      return failBluetoothDuplexV2(operation, readiness)
    }
    operation.verifiedInput = facts.actualInput
    operation.verifiedOutput = facts.actualOutput
    if (facts.outputStream.streamEpoch != openedOutputEpoch) {
      operation.phase = "duplexEpochChanged"
      return failBluetoothDuplexV2(operation, "route_unstable")
    }
    operation.phase = "duplexVerified"
    if (purpose == InputLifecyclePurposeV2.MONITORING) {
      if (!activateVerifiedMonitorGraphV2(
          monitoringTargetRow,
          channelStart,
          channelCount,
        )) {
        operation.phase = "monitorGraph"
        return failBluetoothDuplexV2(operation, "monitoring_unavailable")
      }
      audioRouteIntentV2 = AudioRouteIntentV2.MONITORING
    }
    updateDuplexProbeFactsV2(operation, "duplexVerified", "ok")
    return IntentOutcomeV2("success", "ok")
  }

  private fun bluetoothCommunicationCandidatesV2(
    audioManager: AudioManager,
    selectionMode: AndroidBluetoothRouteSelectionModeV2,
  ): List<AudioDeviceInfo> = try {
    val devices = when (selectionMode) {
      AndroidBluetoothRouteSelectionModeV2.COMMUNICATION_DEVICE ->
        audioManager.availableCommunicationDevices
      AndroidBluetoothRouteSelectionModeV2.LEGACY_SCO ->
        audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList()
    }
    devices
      .filter { it.isSink && it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
      .distinctBy { it.id }
  } catch (_: SecurityException) {
    emptyList()
  } catch (_: IllegalStateException) {
    emptyList()
  }

  private fun acquireCommunicationDeviceRouteV2(
    operation: RecordingOperationV2,
    audioManager: AudioManager,
    candidate: AudioDeviceInfo,
    deadlineNanos: Long,
  ): String {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
      return "recording_route_unsupported"
    }
    val selected = CountDownLatch(1)
    operation.lifecycleSignal = selected
    val listener = AudioManager.OnCommunicationDeviceChangedListener { device ->
      if (device?.id == candidate.id) selected.countDown()
    }
    return try {
      audioManager.addOnCommunicationDeviceChangedListener(
        applicationContext.mainExecutor,
        listener,
      )
      audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
      if (!audioManager.setCommunicationDevice(candidate)) {
        return "recording_route_unsupported"
      }
      val remainingNanos = deadlineNanos - SystemClock.elapsedRealtimeNanos()
      if (
        remainingNanos <= 0L ||
        !selected.await(remainingNanos, TimeUnit.NANOSECONDS)
      ) {
        return "actual_state_unavailable"
      }
      operation.communicationRouteSelected.set(true)
      if (audioManager.communicationDevice?.id != candidate.id) {
        return "route_unstable"
      }
      "ok"
    } catch (_: SecurityException) {
      "recording_route_unsupported"
    } catch (_: IllegalStateException) {
      "actual_state_unavailable"
    } finally {
      operation.lifecycleSignal = null
      try {
        audioManager.removeOnCommunicationDeviceChangedListener(listener)
      } catch (_: IllegalArgumentException) {
      }
    }
  }

  private fun handleLegacyScoEventV2(
    operation: RecordingOperationV2,
    event: AndroidLegacyScoEventV2,
  ) {
    when (event) {
      AndroidLegacyScoEventV2.ACQUIRED,
      AndroidLegacyScoEventV2.ACQUISITION_FAILED,
      AndroidLegacyScoEventV2.RELEASED -> operation.lifecycleSignal?.countDown()
      AndroidLegacyScoEventV2.TERMINAL_LOSS -> {
        if (
          recordingOperationV2 === operation &&
          !operation.cleanupClaimed.get()
        ) {
          handleAudioRouteSignalV2(
            AndroidRouteSignalKindV2.LEGACY_SCO_STATE_CHANGED,
            emptySet(),
            requiresReconfiguration = true,
          )
        }
      }
      AndroidLegacyScoEventV2.NONE -> Unit
    }
  }

  @Suppress("DEPRECATION")
  private fun acquireLegacyScoRouteV2(
    operation: RecordingOperationV2,
    audioManager: AudioManager,
    deadlineNanos: Long,
  ): String {
    if (Build.VERSION.SDK_INT !in 29..30) return "recording_route_unsupported"
    val acquired = CountDownLatch(1)
    operation.lifecycleSignal = acquired
    val receiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action != AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED) return
        val state = intent.getIntExtra(
          AudioManager.EXTRA_SCO_AUDIO_STATE,
          AudioManager.SCO_AUDIO_STATE_ERROR,
        )
        handleLegacyScoEventV2(operation, operation.legacyScoState.observe(state))
      }
    }
    operation.legacyScoReceiver = receiver
    return try {
      val sticky = applicationContext.registerReceiver(
        receiver,
        IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED),
      )
      val stickyState = sticky?.getIntExtra(
        AudioManager.EXTRA_SCO_AUDIO_STATE,
        AudioManager.SCO_AUDIO_STATE_ERROR,
      ) ?: AudioManager.SCO_AUDIO_STATE_ERROR
      val initialEvent = operation.legacyScoState.beginAcquisition(stickyState)
      audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
      operation.legacyScoState.markRequestStarted()
      audioManager.startBluetoothSco()
      audioManager.isBluetoothScoOn = true
      handleLegacyScoEventV2(operation, initialEvent)

      val remainingNanos = deadlineNanos - SystemClock.elapsedRealtimeNanos()
      if (
        remainingNanos <= 0L ||
        !acquired.await(remainingNanos, TimeUnit.NANOSECONDS)
      ) {
        return "actual_state_unavailable"
      }
      if (!operation.legacyScoState.isConnected() || !audioManager.isBluetoothScoOn) {
        return "actual_state_unavailable"
      }
      operation.communicationRouteSelected.set(true)
      "ok"
    } catch (_: SecurityException) {
      "recording_route_unsupported"
    } catch (_: IllegalStateException) {
      "actual_state_unavailable"
    } finally {
      operation.lifecycleSignal = null
    }
  }

  private fun acquireBluetoothRouteV2(
    operation: RecordingOperationV2,
    audioManager: AudioManager,
    candidate: AudioDeviceInfo,
    deadlineNanos: Long,
  ): String = when (operation.bluetoothSelectionMode) {
    AndroidBluetoothRouteSelectionModeV2.COMMUNICATION_DEVICE ->
      acquireCommunicationDeviceRouteV2(
        operation,
        audioManager,
        candidate,
        deadlineNanos,
      )
    AndroidBluetoothRouteSelectionModeV2.LEGACY_SCO ->
      acquireLegacyScoRouteV2(operation, audioManager, deadlineNanos)
    null -> "recording_route_unsupported"
  }

  private fun unregisterLegacyScoReceiverV2(operation: RecordingOperationV2) {
    val receiver = operation.legacyScoReceiver ?: return
    operation.legacyScoReceiver = null
    try {
      applicationContext.unregisterReceiver(receiver)
    } catch (_: IllegalArgumentException) {
    }
  }

  @Suppress("DEPRECATION")
  private fun releaseLegacyScoRouteV2(
    operation: RecordingOperationV2,
    audioManager: AudioManager,
    deadlineNanos: Long,
    waitForRelease: Boolean,
  ): String {
    if (
      operation.bluetoothSelectionMode !=
      AndroidBluetoothRouteSelectionModeV2.LEGACY_SCO
    ) {
      return "ok"
    }
    operation.phase = "releasingLegacySco"
    val released = CountDownLatch(1)
    operation.lifecycleSignal = released
    val shouldWait = operation.legacyScoState.beginRelease()
    return try {
      audioManager.isBluetoothScoOn = false
      if (operation.legacyScoState.claimStopRequest()) {
        audioManager.stopBluetoothSco()
      }
      if (!shouldWait || !waitForRelease) released.countDown()
      val remainingNanos = deadlineNanos - SystemClock.elapsedRealtimeNanos()
      if (
        remainingNanos <= 0L ||
        !released.await(remainingNanos, TimeUnit.NANOSECONDS)
      ) {
        "actual_state_unavailable"
      } else {
        "ok"
      }
    } catch (_: SecurityException) {
      "actual_state_unavailable"
    } catch (_: IllegalStateException) {
      "actual_state_unavailable"
    } finally {
      operation.lifecycleSignal = null
      unregisterLegacyScoReceiverV2(operation)
    }
  }

  @Suppress("DEPRECATION")
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
      selectionMode = operation.bluetoothSelectionMode
        ?: AndroidBluetoothRouteSelectionModeV2.forApiLevel(Build.VERSION.SDK_INT),
      sourceOutput = operation.sourceOutput,
      selectedCommunicationOutput = operation.expectedCommunicationOutput,
      actualInput = input,
      actualOutput = output,
      audioMode = audioManager.mode,
      communicationDeviceId = communicationDeviceId,
      legacyScoConnected = operation.legacyScoState.isConnected(),
      legacyScoRoutingEnabled =
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

  /**
   * Resolve the recording adapter once before any adapter mutates Android
   * audio state. Non-Bluetooth routes stay system-selected. Bluetooth media
   * routes retain the existing communication-device capability decision.
   */
  private fun prepareSystemSelectedRecordingV2(
    generation: Long,
    mode: IntentOperationModeV2,
    channelStart: Int,
    channelCount: Int,
  ): IntentOutcomeV2 {
    if (mode != IntentOperationModeV2.SYSTEM_SELECTED_RECORDING) {
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
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val selectionMode =
      AndroidBluetoothRouteSelectionModeV2.forApiLevel(Build.VERSION.SDK_INT)
    val communicationCandidates =
      bluetoothCommunicationCandidatesV2(audioManager, selectionMode)
    return when (
      AndroidSystemRecordingRouteResolverV2.resolve(
        sourceKind = sourceOutput.kind,
        apiLevel = Build.VERSION.SDK_INT,
        communicationCandidateCount = communicationCandidates.size,
      )
    ) {
      AndroidRecordingRouteAdapterV2.SYSTEM_SELECTED ->
        prepareSystemSelectedDuplexV2(
          generation,
          mode,
          sourceOutput,
          channelStart,
          channelCount,
        )
      AndroidRecordingRouteAdapterV2.BLUETOOTH_COMMUNICATION ->
        prepareBluetoothDuplexV2(
          generation,
          mode,
          communicationCandidates.single(),
        )
      else -> IntentOutcomeV2("failure", "recording_route_unsupported")
    }
  }

  private fun prepareSystemSelectedMonitoringV2(
    generation: Long,
    mode: IntentOperationModeV2,
    channelStart: Int,
    channelCount: Int,
    targetRow: Int,
  ): IntentOutcomeV2 {
    if (mode != IntentOperationModeV2.SYSTEM_SELECTED_MONITORING || targetRow < 0) {
      return IntentOutcomeV2("failure", "monitoring_unavailable")
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
    if (sourceOutput.kind !in setOf(
        AndroidRouteKindV2.BUILT_IN,
        AndroidRouteKindV2.WIRED,
        AndroidRouteKindV2.EXTERNAL,
      )) {
      return IntentOutcomeV2("failure", "monitoring_unavailable")
    }
    return prepareSystemSelectedDuplexV2(
      generation,
      mode,
      sourceOutput,
      channelStart,
      channelCount,
      purpose = InputLifecyclePurposeV2.MONITORING,
      monitoringTargetRow = targetRow,
    )
  }

  private fun prepareBluetoothDuplexV2(
    generation: Long,
    mode: IntentOperationModeV2,
    resolvedCandidate: AudioDeviceInfo? = null,
  ): IntentOutcomeV2 {
    if (mode != IntentOperationModeV2.SYSTEM_SELECTED_RECORDING) {
      return IntentOutcomeV2("failure", "recording_route_unsupported")
    }
    if (Build.VERSION.SDK_INT < 29) {
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

    val selectionMode =
      AndroidBluetoothRouteSelectionModeV2.forApiLevel(Build.VERSION.SDK_INT)
    val operation = RecordingOperationV2(
      id = recordingOperationIdV2.incrementAndGet(),
      generation = generation,
      sourceOutput = sourceOutput,
      mode = mode,
      routeAdapter = AndroidRecordingRouteAdapterV2.BLUETOOTH_COMMUNICATION,
      bluetoothSelectionMode = selectionMode,
    )
    recordingOperationV2 = operation
    duplexProbeFactsV2 = null
    audioRouteIntentV2 = AudioRouteIntentV2.PREPARING_RECORDING
    val audioManager =
      applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val candidates = if (resolvedCandidate == null) {
      bluetoothCommunicationCandidatesV2(audioManager, selectionMode)
    } else if (
      resolvedCandidate.isSink &&
      resolvedCandidate.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
    ) {
      listOf(resolvedCandidate)
    } else {
      emptyList()
    }
    if (candidates.size != 1) {
      operation.phase = "communicationDeviceUnavailable"
      return failBluetoothDuplexV2(operation, "recording_route_unsupported")
    }
    val candidate = candidates.single()
    operation.expectedCommunicationOutput = candidate.toRouteEndpointV2()
    operation.phase = "selectingCommunicationDevice"

    val deadlineNanos = operation.startedNanos + TimeUnit.SECONDS.toNanos(5)
    val selectionCode = acquireBluetoothRouteV2(
      operation,
      audioManager,
      candidate,
      deadlineNanos,
    )
    if (selectionCode != "ok") {
      operation.phase = when (selectionCode) {
        "recording_route_unsupported" -> "communicationDeviceSelection"
        "route_unstable" -> "communicationRouteChanged"
        else -> "communicationDeviceTimeout"
      }
      return failBluetoothDuplexV2(operation, selectionCode)
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
      return failBluetoothDuplexV2(operation, "route_unstable")
    }

    operation.phase = "openingDuplex"
    setAndroidStreamPolicyV2(AndroidStreamPolicyV2.BLUETOOTH_COMMUNICATION_DUPLEX)
    if (!JuceBridge.prepareBluetoothDuplexV2JNI()) {
      operation.phase = "juceOpen"
      return failBluetoothDuplexV2(operation, "juce_reopen_failed")
    }
    val openedOutputEpoch = verifiedOutputEpochV2(currentOboeFactsV2())
    if (openedOutputEpoch == null) {
      operation.phase = "juceOpenFacts"
      return failBluetoothDuplexV2(operation, "actual_state_unavailable")
    }
    if (commitRecordingOutputEpochV2(operation, openedOutputEpoch)) {
      selectCleanupDispositionV2(
        operation,
        AndroidRecordingCleanupDispositionV2.CLOSE_ONLY,
      )
      operation.cancelled.set(true)
      postDeferredNativeDisconnectV2(operation, openedOutputEpoch)
      operation.phase = "physicalRouteInvalidation"
      return failBluetoothDuplexV2(operation, "route_unstable")
    }
    val remainingAfterOpenNanos =
      operation.startedNanos + TimeUnit.SECONDS.toNanos(5) -
        SystemClock.elapsedRealtimeNanos()
    if (remainingAfterOpenNanos <= 0L) {
      operation.phase = "callbackTimeout"
      return failBluetoothDuplexV2(operation, "actual_state_unavailable")
    }
    val remainingMillis = TimeUnit.NANOSECONDS.toMillis(remainingAfterOpenNanos)
      .coerceIn(1L, 5000L)
      .toInt()
    if (!JuceBridge.waitForV2CallbackReadyJNI(remainingMillis)) {
      operation.phase = "callback"
      return failBluetoothDuplexV2(operation, "actual_state_unavailable")
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
      return failBluetoothDuplexV2(operation, "route_unstable")
    }

    val facts = currentBluetoothDuplexFactsV2(operation)
    val readiness = AndroidBluetoothDuplexReadinessV2.validate(facts)
    if (readiness != "ok") {
      operation.phase = "duplexValidation"
      return failBluetoothDuplexV2(operation, readiness)
    }
    operation.verifiedInput = facts.actualInput
    operation.verifiedOutput = facts.actualOutput
    if (facts.outputStream.streamEpoch != openedOutputEpoch) {
      operation.phase = "duplexEpochChanged"
      return failBluetoothDuplexV2(operation, "route_unstable")
    }
    operation.phase = "duplexVerified"
    updateDuplexProbeFactsV2(operation, "duplexVerified", "ok")
    return IntentOutcomeV2("success", "ok")
  }

  private fun verifyRecordingIntentV2(generation: Long): IntentOutcomeV2 {
    val operation = recordingOperationV2
      ?: return IntentOutcomeV2("failure", "actual_state_unavailable")
    if (
      operation.purpose != InputLifecyclePurposeV2.RECORDING ||
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

  private fun verifyMonitoringIntentV2(generation: Long): IntentOutcomeV2 {
    val operation = recordingOperationV2
      ?: return IntentOutcomeV2("failure", "actual_state_unavailable")
    if (
      operation.purpose != InputLifecyclePurposeV2.MONITORING ||
      operation.cancelled.get() ||
      generation != operation.generation ||
      generation != audioRouteGenerationV2 ||
      JuceBridge.isRecordingJNI()
    ) {
      return IntentOutcomeV2("failure", "stale_generation")
    }
    val readiness = validatePreparedRecordingV2(operation)
    if (readiness != "ok") return IntentOutcomeV2("failure", readiness)
    if (!activateVerifiedMonitorGraphV2(
        operation.monitoringTargetRow,
        operation.recordingChannelStart,
        operation.recordingChannelCount,
      )) {
      return IntentOutcomeV2("failure", "monitoring_unavailable")
    }
    audioRouteIntentV2 = AudioRouteIntentV2.MONITORING
    return IntentOutcomeV2("success", "ok")
  }

  private fun restoreRecordingPlaybackV2(generation: Long): IntentOutcomeV2 {
    if (generation != audioRouteGenerationV2) {
      recordingOperationV2?.let { operation ->
        selectCleanupDispositionV2(
          operation,
          AndroidRecordingCleanupDispositionV2.CLOSE_ONLY,
        )
        operation.routeInvalidated.set(true)
        operation.cancelled.set(true)
        operation.lifecycleSignal?.countDown()
        cleanupRecordingOperationV2(
          operation,
          AndroidRecordingCleanupDispositionV2.CLOSE_ONLY,
        )
      }
      return IntentOutcomeV2("failure", "stale_generation")
    }
    val operation = recordingOperationV2
    val code = when {
      operation == null -> restorePlaybackOnlyV2(expectedOutput = null)
      operation.routeInvalidated.get() && operation.cleanupClaimed.get() -> {
        // Terminal cleanup already closed capture, input and communication
        // routing. Recover the output Android currently selected; the retained
        // operation exists only to own delayed notifications until commit.
        restorePlaybackOnlyV2(expectedOutput = null, operation = operation)
      }
      operation.routeInvalidated.get() -> {
        val cleanupCode = cleanupRecordingOperationV2(
          operation,
          AndroidRecordingCleanupDispositionV2.CLOSE_ONLY,
        )
        if (cleanupCode == "ok") {
          restorePlaybackOnlyV2(expectedOutput = null, operation = operation)
        } else {
          cleanupCode
        }
      }
      else -> cleanupRecordingOperationV2(
        operation,
        AndroidRecordingCleanupDispositionV2.RESTORE_EXACT,
      )
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
      "monitoring" -> AudioRouteIntentV2.MONITORING
      "preparingRecording" -> AudioRouteIntentV2.PREPARING_RECORDING
      "recording" -> AudioRouteIntentV2.RECORDING
      else -> null
    }
    val requestedOperation = args.stringValue("intentOperation")
    val requestedChannelStart = args.intValue("recordingChannelStart")
    val requestedChannelCount = args.intValue("recordingChannelCount", 1)
    val requestedMonitoringTargetRow = args.intValue("monitoringTargetRow", -1)
    val validRecordingSelection = requestedChannelStart >= 0 &&
      requestedChannelCount in 1..2 &&
      requestedChannelStart + requestedChannelCount in 1..32
    val operationMode = when (requestedOperation) {
      "systemSelectedRecording" -> IntentOperationModeV2.SYSTEM_SELECTED_RECORDING
      "systemSelectedMonitoring" -> IntentOperationModeV2.SYSTEM_SELECTED_MONITORING
      else -> IntentOperationModeV2.STANDARD
    }
    if (operationMode.reportsDuplexFacts()) {
      // A report captured during this request must never retain evidence from
      // an earlier probe that happened to use a different route adapter.
      duplexProbeFactsV2 = null
    }
    Log.i(
      "JuceAudioEngine",
      "Android V2 intent=$requestedIntent operation=${requestedOperation ?: "standard"}",
    )
    if (requestedIntent == null ||
      ((requestedIntent == AudioRouteIntentV2.PREPARING_RECORDING ||
          requestedIntent == AudioRouteIntentV2.MONITORING) &&
        !validRecordingSelection)
    ) {
      result.success(
        routeTransitionResultV2(
          "failure", generation, transitionId, "recording_route_unsupported",
          started, false,
        ),
      )
      return
    }
    if (requestedIntent == AudioRouteIntentV2.PREPARING_RECORDING ||
      requestedIntent == AudioRouteIntentV2.MONITORING
    ) {
      recordingCancellationRequestedV2.set(false)
    }

    lifecycleTransitionInProgressV2 = true
    audioLifecycleExecutorV2.execute {
      val outcome = try {
        when (requestedIntent) {
          AudioRouteIntentV2.MONITORING -> if (
            audioRouteIntentV2 == AudioRouteIntentV2.RECORDING ||
            audioRouteIntentV2 == AudioRouteIntentV2.MONITORING
          ) {
            verifyMonitoringIntentV2(generation)
          } else {
            prepareSystemSelectedMonitoringV2(
              generation,
              operationMode,
              requestedChannelStart,
              requestedChannelCount,
              requestedMonitoringTargetRow,
            )
          }
          AudioRouteIntentV2.PREPARING_RECORDING -> when (operationMode) {
            IntentOperationModeV2.SYSTEM_SELECTED_RECORDING ->
              prepareSystemSelectedRecordingV2(
                generation,
                operationMode,
                requestedChannelStart,
                requestedChannelCount,
              )
            IntentOperationModeV2.STANDARD -> prepareBuiltInRecordingV2(
              generation,
              requestedChannelStart,
              requestedChannelCount,
            )
            IntentOperationModeV2.SYSTEM_SELECTED_MONITORING ->
              IntentOutcomeV2("failure", "recording_route_unsupported")
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
            requestedDisposition = if (operation.routeInvalidated.get()) {
              AndroidRecordingCleanupDispositionV2.CLOSE_ONLY
            } else {
              AndroidRecordingCleanupDispositionV2.RESTORE_EXACT
            },
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
    val restorePlayback = args.boolValue("restorePlayback", true)
    operation?.let {
      selectCleanupDispositionV2(
        it,
        if (restorePlayback && !it.routeInvalidated.get()) {
          AndroidRecordingCleanupDispositionV2.RESTORE_EXACT
        } else {
          AndroidRecordingCleanupDispositionV2.CLOSE_ONLY
        },
      )
    }
    recordingCancellationRequestedV2.set(true)
    operation?.cancelled?.set(true)
    operation?.lifecycleSignal?.countDown()
    audioLifecycleExecutorV2.execute {
      if (operation != null) {
        cleanupRecordingOperationV2(
          operation,
          if (restorePlayback && !operation.routeInvalidated.get()) {
            AndroidRecordingCleanupDispositionV2.RESTORE_EXACT
          } else {
            AndroidRecordingCleanupDispositionV2.CLOSE_ONLY
          },
        )
      } else if (JuceBridge.isRecordingJNI()) {
        JuceBridge.discardRecordingCaptureV2JNI()
      }
      mainHandler.post {
        if (
          operation != null &&
          operation.cleanupClaimed.get() &&
          !operation.routeInvalidated.get() &&
          recordingOperationV2 === operation
        ) {
          recordingOperationV2 = null
        }
        result.success(null)
      }
    }
  }

  private fun prepareV2TeardownV2(): RecordingOperationV2? {
    val operation = recordingOperationV2
    operation?.let {
      // Match iOS: decide terminal teardown before cancellation releases a
      // lifecycle waiter, so whichever executor task wins cleanup cannot reopen.
      selectCleanupDispositionV2(
        it,
        AndroidRecordingCleanupDispositionV2.CLOSE_ONLY,
      )
    }
    lifecycleDisposedV2 = true
    recordingCancellationRequestedV2.set(true)
    operation?.cancelled?.set(true)
    operation?.lifecycleSignal?.countDown()
    return operation
  }

  private fun startPreparedCaptureV2(
    args: Map<String, Any?>,
    result: MethodChannel.Result,
  ) {
    val operation = recordingOperationV2
    if (
      operation == null ||
      operation.purpose != InputLifecyclePurposeV2.RECORDING ||
      operation.cancelled.get() ||
      recordingCancellationRequestedV2.get() ||
      audioRouteIntentV2 != AudioRouteIntentV2.PREPARING_RECORDING ||
      lifecycleTransitionInProgressV2
    ) {
      result.success(false)
      return
    }
    val requestedChannelStart = args.intValue("channelStart")
    val requestedChannelCount = args.intValue("channelCount")
    if (
      requestedChannelStart != operation.recordingChannelStart ||
      requestedChannelCount != operation.recordingChannelCount
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
            operation.recordingChannelStart,
            operation.recordingChannelCount,
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
    verifiedPlaybackOutputEpochV2 = null
  }

  private fun applyAudioRouteConfigurationV2(
    args: Map<String, Any?>,
    result: MethodChannel.Result,
  ) {
    val started = SystemClock.elapsedRealtimeNanos()
    val generation = args.longValue("generation")
    audioRouteTransitionIdV2 += 1L
    val transitionId = audioRouteTransitionIdV2
    val transportWasPlaying = routeTransitionWasPlayingV2
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
          transportWasPlaying,
        ),
      )
      return
    }
    lifecycleTransitionInProgressV2 = true
    audioLifecycleExecutorV2.execute {
      val transition = try {
        applyAudioRouteConfigurationOnLifecycleV2(
          generation = generation,
          transitionId = transitionId,
          startedNanos = started,
          transportWasPlaying = transportWasPlaying,
        )
      } catch (error: Exception) {
        Log.e("JuceAudioEngine", "Android V2 playback apply failed", error)
        closeFailedPlaybackRouteV2()
        routeTransitionResultV2(
          "failure",
          generation,
          transitionId,
          "actual_state_unavailable",
          started,
          transportWasPlaying,
          capturePlaybackSnapshotV2(allowLifecycleTransition = true),
        )
      }
      mainHandler.post {
        expectedPlaybackTransitionV2 = null
        lifecycleTransitionInProgressV2 = false
        result.success(transition)
      }
    }
  }

  private fun applyAudioRouteConfigurationOnLifecycleV2(
    generation: Long,
    transitionId: Long,
    startedNanos: Long,
    transportWasPlaying: Boolean,
  ): Map<String, Any?> {
    if (
      lifecycleDisposedV2 ||
      !audioRouteMonitoringV2 ||
      engineOwnership != EngineOwnership.V2_SESSION
    ) {
      return routeTransitionResultV2(
        "failure",
        generation,
        transitionId,
        "coordinator_disposed",
        startedNanos,
        transportWasPlaying,
        capturePlaybackSnapshotV2(allowLifecycleTransition = true),
      )
    }
    if (generation != audioRouteGenerationV2) {
      return routeTransitionResultV2(
        "failure",
        generation,
        transitionId,
        "stale_generation",
        startedNanos,
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
        startedNanos,
        transportWasPlaying,
      )
    }
    expectedPlaybackTransitionV2 = expected

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
        startedNanos,
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
        startedNanos,
        transportWasPlaying,
      )
    }

    if (lifecycleDisposedV2 || generation != audioRouteGenerationV2) {
      Log.w(
        "JuceAudioEngine",
        "Android V2 playback apply failed: stale_generation after callback",
      )
      JuceBridge.quiescePlaybackV2JNI(false)
      return routeTransitionResultV2(
        "failure",
        generation,
        transitionId,
        if (lifecycleDisposedV2) "coordinator_disposed" else "stale_generation",
        startedNanos,
        transportWasPlaying,
      )
    }

    val snapshot = capturePlaybackSnapshotV2(allowLifecycleTransition = true)
    var diagnosticCode = AndroidPlaybackReadinessV2.validate(currentPlaybackFactsV2())
    val actual = currentEffectiveRouteStateV2()
    val outputFactsMap = currentOboeFactsV2()
    val outputFacts = AndroidOboeOutputFactsV2.fromMap(outputFactsMap)
    if (diagnosticCode == "ok" && actual.bluetoothCommunicationActive) {
      diagnosticCode = "bluetooth_duplex_forbidden"
    }
    if (diagnosticCode == "ok") {
      diagnosticCode = AndroidLiveRouteValidatorV2.validate(
        expected,
        actual.resolution,
        actual.actualEndpoint,
        outputFacts,
        acceptSystemSelectedReplacement = previousWasBluetooth && !expected.isBluetooth,
      )
    }
    if (
      diagnosticCode == "ok" &&
      snapshot["captureConsistency"] != "stable"
    ) {
      diagnosticCode = "route_unstable"
    }
    if (lifecycleDisposedV2) {
      diagnosticCode = "coordinator_disposed"
    } else if (generation != audioRouteGenerationV2) {
      diagnosticCode = "stale_generation"
    }

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
        startedNanos,
        transportWasPlaying,
        if (diagnosticCode == "stale_generation") {
          snapshot
        } else {
          capturePlaybackSnapshotV2(allowLifecycleTransition = true)
        },
      )
    }

    verifiedPlaybackRouteV2 = actual.actualEndpoint ?: actual.resolution.endpoint
    verifiedPlaybackFingerprintV2 = actual.fingerprint
    commitVerifiedPlaybackOutputEpochV2(outputFactsMap)
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
      startedNanos,
      transportWasPlaying,
      capturePlaybackSnapshotV2(allowLifecycleTransition = true),
    )
  }

  private fun cleanupFailedPlaybackV2() {
    stopAudioRouteMonitoringV2()
    JuceBridge.shutdownEngineSynchronouslyJNI()
    JuceBridge.resetPlaybackPolicyV2JNI()
    verifiedPlaybackRouteV2 = null
    bluetoothMediaPolicyActiveV2 = false
    verifiedPlaybackFingerprintV2 = ""
    verifiedPlaybackOutputEpochV2 = null
    audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY
    recordingOperationV2 = null
    duplexProbeFactsV2 = null
    expectedPlaybackTransitionV2 = null
    engineOwnership = EngineOwnership.NONE
    v2SessionRequested = false
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
      if (audioRouteIntentV2 == AudioRouteIntentV2.MONITORING) {
        if (JuceBridge.isRecordingJNI()) return "actual_state_unavailable"
        return validatePreparedRecordingV2(operation)
      }
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
    requiredInputChannels: Int = 1,
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
      requiredInputChannels = requiredInputChannels,
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
    val verifiedInput = operation.verifiedInput ?: return "actual_state_unavailable"
    val verifiedOutput = operation.verifiedOutput ?: return "actual_state_unavailable"
    val actualInput: AndroidRouteEndpointV2?
    val actualOutput: AndroidRouteEndpointV2?
    val readiness = when (operation.routeAdapter) {
      AndroidRecordingRouteAdapterV2.BLUETOOTH_COMMUNICATION -> {
        val facts = currentBluetoothDuplexFactsV2(operation)
        actualInput = facts.actualInput
        actualOutput = facts.actualOutput
        AndroidBluetoothDuplexReadinessV2.validate(facts)
      }
      AndroidRecordingRouteAdapterV2.SYSTEM_SELECTED -> {
        val facts = currentRecordingFactsV2(
          operation.sourceOutput,
          operation.recordingChannelStart + operation.recordingChannelCount,
        )
        actualInput = facts.actualInput
        actualOutput = facts.actualOutput
        if (operation.purpose == InputLifecyclePurposeV2.MONITORING) {
          AndroidMonitoringReadinessV2.validate(facts)
        } else {
          AndroidSystemSelectedDuplexReadinessV2.validate(facts)
        }
      }
      AndroidRecordingRouteAdapterV2.BUILT_IN -> {
        val facts = currentRecordingFactsV2(
          operation.sourceOutput,
          operation.recordingChannelStart + operation.recordingChannelCount,
        )
        actualInput = facts.actualInput
        actualOutput = facts.actualOutput
        AndroidRecordingReadinessV2.validate(facts)
      }
    }
    if (readiness != "ok") return readiness
    if (
      actualInput?.fingerprint != verifiedInput.fingerprint ||
      actualOutput?.fingerprint != verifiedOutput.fingerprint
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
    AudioRouteIntentV2.MONITORING -> "monitoring"
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
    allowLifecycleTransition: Boolean = false,
  ): Map<String, Any?> {
    if (lifecycleTransitionInProgressV2 && !allowLifecycleTransition) {
      return lifecycleUnavailableSnapshotV2()
    }
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
    val bluetoothOperation = recordingOperationV2?.takeIf {
      it.usesBluetoothDuplexRoute()
    }
    val verifiedBluetoothRoute =
      bluetoothOperation?.verifiedInput?.id == routedInputEndpoint?.id &&
        bluetoothOperation?.verifiedOutput?.id == routedEndpoint?.id
    val consistency = when {
      extraUnavailable.containsKey("coordinator") -> "unavailable"
      verifiedBluetoothRoute -> "stable"
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
        "category" to if (bluetoothOperation != null) {
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
        "streamEpoch" to oboe["streamEpoch"],
        "routedDeviceId" to oboe["routedDeviceId"]?.toString(),
        "inputStreamState" to oboeInput["streamState"],
        "inputStreamEpoch" to oboeInput["streamEpoch"],
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

  private fun initialisePlaybackV2(result: MethodChannel.Result) {
    if (
      engineOwnership != EngineOwnership.NONE ||
      v2SessionRequested ||
      lifecycleTransitionInProgressV2
    ) {
      result.success(playbackStartupResult(false, "implementation_conflict"))
      return
    }
    v2SessionRequested = true
    lifecycleDisposedV2 = false
    lifecycleTransitionInProgressV2 = true
    audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY
    recordingOperationV2 = null
    recordingCancellationRequestedV2.set(false)
    duplexProbeFactsV2 = null

    audioLifecycleExecutorV2.execute {
      val startup = try {
        initialisePlaybackV2Unchecked()
      } catch (error: Exception) {
        Log.e("JuceAudioEngine", "Android V2 startup failed", error)
        if (engineOwnership == EngineOwnership.V2_SESSION) {
          cleanupFailedPlaybackV2()
        } else {
          JuceBridge.resetPlaybackPolicyV2JNI()
          v2SessionRequested = false
        }
        playbackStartupResult(false, "actual_state_unavailable")
      }
      if (startup["success"] != true && engineOwnership == EngineOwnership.NONE) {
        v2SessionRequested = false
      }
      mainHandler.post {
        lifecycleTransitionInProgressV2 = false
        result.success(startup)
      }
    }
  }

  private fun initialisePlaybackV2Unchecked(): Map<String, Any?> {
    // A previous plugin instance may still own the process-global JUCE engine.
    // Wait only on this lifecycle worker; timeout fails closed without opening.
    if (!processV2TeardownGate.awaitClear()) {
      return playbackStartupResult(false, "coordinator_disposed")
    }
    if (lifecycleDisposedV2) {
      return playbackStartupResult(false, "coordinator_disposed")
    }
    JuceBridge.resetPlaybackPolicyV2JNI()
    val expectedRoute = resolveMediaRouteV2()
    if (expectedRoute.diagnosticCode != "ok") {
      return playbackStartupResult(
        false,
        expectedRoute.diagnosticCode,
        capturePlaybackSnapshotV2(
          implementationOverride = "v2",
          allowLifecycleTransition = true,
        ),
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
    if (!JuceBridge.waitForV2CallbackReadyJNI(1000)) {
      val snapshot = capturePlaybackSnapshotV2(allowLifecycleTransition = true)
      cleanupFailedPlaybackV2()
      return playbackStartupResult(false, "actual_state_unavailable", snapshot)
    }
    if (lifecycleDisposedV2) {
      cleanupFailedPlaybackV2()
      return playbackStartupResult(false, "coordinator_disposed")
    }

    val snapshot = capturePlaybackSnapshotV2(allowLifecycleTransition = true)
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
    val outputFacts = currentOboeFactsV2()
    if (bluetoothMediaPolicyActiveV2) {
      val bluetoothCode = validateVerifiedBluetoothRouteV2(
        expectedRoute.endpoint!!,
        resolveMediaRouteV2(),
        outputFacts,
      )
      if (bluetoothCode != "ok") {
        cleanupFailedPlaybackV2()
        return playbackStartupResult(false, bluetoothCode, snapshot)
      }
    }
    verifiedPlaybackFingerprintV2 = currentEffectiveRouteStateV2().fingerprint
    commitVerifiedPlaybackOutputEpochV2(outputFacts)
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
      (engineOwnership == EngineOwnership.V2_SESSION || v2SessionRequested) &&
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
        "Legacy audio operation is unavailable in a V2 audio session",
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
          if (!processV2TeardownGate.isClear()) {
            result.error(
              "coordinator_disposed",
              "Previous Android audio teardown is still in progress",
              null,
            )
            return
          }
          if (engineOwnership == EngineOwnership.V2_SESSION) {
            result.error("implementation_conflict", "V2 audio owns the engine", null)
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
          initialisePlaybackV2(result)
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
          applyAudioRouteConfigurationV2(args, result)
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
          if (engineOwnership == EngineOwnership.V2_SESSION || v2SessionRequested) {
            val operation = prepareV2TeardownV2()
            stopAudioRouteMonitoringV2()
            audioLifecycleExecutorV2.execute {
              // The queued startup task decides ownership before this task
              // runs. A failed-start instance must never close another plugin
              // instance's process-global native engine.
              val ownsNativeEngineAtExecution = engineOwnership.ownsNativeEngine
              if (ownsNativeEngineAtExecution) {
                operation?.let {
                  cleanupRecordingOperationV2(
                    it,
                    AndroidRecordingCleanupDispositionV2.CLOSE_ONLY,
                  )
                }
                JuceBridge.shutdownEngineSynchronouslyJNI()
                JuceBridge.resetPlaybackPolicyV2JNI()
              }
              verifiedPlaybackRouteV2 = null
              verifiedPlaybackFingerprintV2 = ""
              verifiedPlaybackOutputEpochV2 = null
              bluetoothMediaPolicyActiveV2 = false
              v2SessionRequested = false
              audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY
              recordingOperationV2 = null
              engineOwnership = EngineOwnership.NONE
              mainHandler.post {
                lifecycleTransitionInProgressV2 = false
                result.success(null)
              }
            }
          } else {
            stopAudioRouteMonitoringV2()
            val ownsNativeEngineAtCall = engineOwnership.ownsNativeEngine
            if (ownsNativeEngineAtCall) {
              normalizeAudioModeAfterRecordingStop()
              // Ownership cannot be released until the shared native engine is
              // fully closed; otherwise a quickly reopened editor can overlap
              // Legacy teardown with V2 startup.
              JuceBridge.shutdownEngineSynchronouslyJNI()
              normalizeAudioModeAfterRecordingStop()
              JuceBridge.resetPlaybackPolicyV2JNI()
            }
            verifiedPlaybackRouteV2 = null
            verifiedPlaybackFingerprintV2 = ""
            verifiedPlaybackOutputEpochV2 = null
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
          val loadRequestId = args.longValue("loadRequestId")
          runMidiPreparationTask("loadMidiClip", result) {
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
              loadRequestId,
            )
          }
        }
        "cancelMidiClipLoad" -> {
          result.success(
            JuceBridge.cancelMidiClipLoadJNI(
              args.intValue("clip"),
              args.longValue("loadRequestId"),
            ),
          )
        }
        "beginProjectClipLoad", "beginProjectClipLoadTransaction" -> {
          JuceBridge.beginProjectClipLoadTransactionJNI()
          result.success(null)
        }
        "endProjectClipLoad", "endProjectClipLoadTransaction" -> {
          JuceBridge.endProjectClipLoadTransactionJNI()
          result.success(null)
        }
        "endProjectClipLoadDetailed" -> {
          result.success(JuceBridge.endProjectClipLoadTransactionDetailedJNI())
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
        "loadClipDetailed" -> {
          val clip = args.intValue("clip")
          val rowId = resolveRowId(args, 0)
          val path = args.stringValue("path")
          val startSec = args.doubleValue("startSec")
          val lengthSec = args.doubleValue("lengthSec")
          val inFileOffsetSec = args.doubleValue("inFileOffsetSec")
          runHeavyTask("loadClipDetailed", result) {
            JuceBridge.loadClipDetailedJNI(
              clip,
              rowId,
              path,
              startSec,
              lengthSec,
              inFileOffsetSec,
            )
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
        "setLoopRegion" -> {
          JuceBridge.setLoopRegionJNI(
            args.boolValue("enabled"),
            args.doubleValue("startSeconds"),
            args.doubleValue("endSeconds"),
          )
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
        "getRecentMasterStereoWaveform" -> {
          result.success(
            JuceBridge.getRecentMasterStereoWaveformJNI(
              args.intValue("sampleCount", 2048),
            ).toList(),
          )
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
        "getInputDeviceInfos" -> {
          result.success(inputDeviceInfosV2())
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
    nativeSetRouteEventTargetV2(false)
    val requiresV2Teardown =
      engineOwnership == EngineOwnership.V2_SESSION || v2SessionRequested
    val requiresEngineTeardown =
      engineOwnership.ownsNativeEngine || v2SessionRequested
    val operation = if (requiresV2Teardown) prepareV2TeardownV2() else null
    stopAudioRouteMonitoringV2()
    if (requiresEngineTeardown) {
      val completion = processV2TeardownGate.publish()
      audioLifecycleExecutorV2.execute {
        // This executes after any queued startup, so ownership here is the
        // authoritative answer. A request that failed before acquisition owns
        // only its gate token and local plugin state.
        val ownsNativeEngineAtExecution = engineOwnership.ownsNativeEngine
        var nativeShutdownCompleted = !ownsNativeEngineAtExecution
        try {
          if (ownsNativeEngineAtExecution) {
            try {
              operation?.let {
                cleanupRecordingOperationV2(
                  it,
                  AndroidRecordingCleanupDispositionV2.CLOSE_ONLY,
                )
              }
            } catch (error: Exception) {
              Log.e("JuceAudioEngine", "Android V2 detach cleanup failed", error)
            }
            try {
              JuceBridge.shutdownEngineSynchronouslyJNI()
              nativeShutdownCompleted = true
            } finally {
              JuceBridge.resetPlaybackPolicyV2JNI()
            }
          }
        } finally {
          verifiedPlaybackRouteV2 = null
          verifiedPlaybackFingerprintV2 = ""
          verifiedPlaybackOutputEpochV2 = null
          bluetoothMediaPolicyActiveV2 = false
          v2SessionRequested = false
          audioRouteIntentV2 = AudioRouteIntentV2.PLAYBACK_ONLY
          recordingOperationV2 = null
          engineOwnership = EngineOwnership.NONE
          if (nativeShutdownCompleted) {
            processV2TeardownGate.complete(completion)
          }
        }
      }
    }
    methodChannel.setMethodCallHandler(null)
    eventsChannel.setStreamHandler(null)
    logsChannel.setStreamHandler(null)
    promptAnalysisService.close()
    heavyWorkExecutor.shutdown()
    midiPreparationExecutor.shutdown()
    audioLifecycleExecutorV2.shutdown()
    eventsSink = null
    logsSink = null
    sharedInstance = null
  }

  @Suppress("unused")
  private fun onNativeBluetoothDuplexDisconnectedV2(streamEpoch: Long) {
    mainHandler.post {
      val operation = recordingOperationV2
      val accepted = if (operation != null) {
        operation.nativeOutputEpochGate.observe(streamEpoch)
      } else {
        AndroidNativeStreamEpochV2.matches(
          verifiedPlaybackOutputEpochV2,
          streamEpoch,
        )
      }
      if (!accepted) {
        return@post
      }
      handleAudioRouteSignalV2(
        AndroidRouteSignalKindV2.NATIVE_STREAM_DISCONNECTED,
        emptySet(),
        requiresReconfiguration = true,
      )
    }
  }

  private external fun nativeSetRouteEventTargetV2(enabled: Boolean)
}
