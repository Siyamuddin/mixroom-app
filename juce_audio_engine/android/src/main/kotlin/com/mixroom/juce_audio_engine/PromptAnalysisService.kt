package com.mixroom.juce_audio_engine

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.util.Log
import java.io.Closeable
import java.io.File
import java.io.FileOutputStream
import java.nio.FloatBuffer

internal class PromptAnalysisService(
  private val context: Context,
  private val yamnetAssetLookupKey: String,
) : Closeable {
  companion object {
    private const val YAMNET_ASSET_PATH = "assets/models/yamnet.onnx"
    private const val YAMNET_SCORES_OUTPUT_NAME = "output_0"
    private const val YAMNET_WINDOW_SAMPLES = 15600
    private const val YAMNET_WINDOW_COUNT = 3
  }

  private val ortEnvironment: OrtEnvironment = OrtEnvironment.getEnvironment()
  private val sessionLock = Any()

  @Volatile
  private var yamnetSession: OrtSession? = null

  fun analyzeClip(path: String): Map<String, Any> {
    val nativeResult =
      JuceBridge.analyzeAudioForPromptJNI(
        path,
        YAMNET_WINDOW_SAMPLES,
        YAMNET_WINDOW_COUNT,
      )
    val audioStats = nativeResult.doubleMap("audioStats")
    val windows = nativeResult.floatArrayList("windows")
    val roleProbs = classifyWindows(windows)

    return mapOf(
      "audioStats" to audioStats,
      "roleProbs" to roleProbs,
    )
  }

  override fun close() {
    synchronized(sessionLock) {
      yamnetSession?.close()
      yamnetSession = null
    }
  }

  private fun classifyWindows(windows: List<FloatArray>): Map<String, Double> {
    if (windows.isEmpty()) {
      return fallbackRoleProbs()
    }

    val session = ensureYamnetSession() ?: return fallbackRoleProbs()
    var accum: DoubleArray? = null
    var used = 0

    for (window in windows) {
      val scores = runWindow(session, window) ?: continue
      if (accum == null) {
        accum = DoubleArray(scores.size)
      }
      for (i in scores.indices) {
        accum[i] += scores[i].toDouble()
      }
      used += 1
    }

    if (accum == null || used == 0) {
      return fallbackRoleProbs()
    }

    for (i in accum.indices) {
      accum[i] /= used.toDouble()
    }

    return mapYamnetToRoles(accum)
  }

  private fun runWindow(session: OrtSession, window: FloatArray): FloatArray? {
    val inputName = session.inputNames.firstOrNull() ?: return null
    val outputName =
      session.outputNames.firstOrNull { it == YAMNET_SCORES_OUTPUT_NAME }
        ?: session.outputNames.firstOrNull()
        ?: return null

    return try {
      OnnxTensor.createTensor(
        ortEnvironment,
        FloatBuffer.wrap(window),
        longArrayOf(window.size.toLong()),
      ).use { inputTensor ->
        session.run(mapOf(inputName to inputTensor)).use { outputs ->
          val outputTensor = unwrapTensor(outputs[outputName]) ?: return null
          val buffer = outputTensor.floatBuffer
          val data = FloatArray(buffer.remaining())
          buffer.get(data)
          if (data.isEmpty()) null else data
        }
      }
    } catch (error: Throwable) {
      Log.w("PromptAnalysisService", "YAMNet window inference failed", error)
      null
    }
  }

  private fun ensureYamnetSession(): OrtSession? {
    yamnetSession?.let { return it }

    synchronized(sessionLock) {
      yamnetSession?.let { return it }
      return try {
        val modelFile = materializeAsset(YAMNET_ASSET_PATH)
        val options =
          OrtSession.SessionOptions().apply {
            setIntraOpNumThreads(1)
            setInterOpNumThreads(1)
            setCPUArenaAllocator(true)
          }
        ortEnvironment.createSession(modelFile.absolutePath, options).also {
          yamnetSession = it
        }
      } catch (error: Throwable) {
        Log.e("PromptAnalysisService", "Failed to create YAMNet session", error)
        null
      }
    }
  }

  private fun materializeAsset(assetPath: String): File {
    val sourcePath = resolveAssetPath(assetPath)
    val targetDir = File(context.filesDir, "onnx_models").apply { mkdirs() }
    val target = File(targetDir, assetPath.substringAfterLast('/'))
    val temp = File(target.parentFile, "${target.name}.part")
    if (temp.exists()) {
      temp.delete()
    }
    context.assets.open(sourcePath).use { input ->
      FileOutputStream(temp).use { output ->
        input.copyTo(output)
      }
    }
    if (target.exists()) {
      target.delete()
    }
    if (!temp.renameTo(target)) {
      temp.copyTo(target, overwrite = true)
      temp.delete()
    }
    return target
  }

  private fun resolveAssetPath(assetPath: String): String {
    val candidates = linkedSetOf(yamnetAssetLookupKey, assetPath)
    for (candidate in candidates) {
      if (candidate.isBlank()) continue
      val exists = try {
        context.assets.open(candidate).use { _ -> }
        true
      } catch (_: Exception) {
        false
      }
      if (exists) {
        return candidate
      }
    }
    throw IllegalStateException(
      "Could not locate YAMNet asset. tried=${candidates.joinToString(",")}",
    )
  }

  private fun unwrapTensor(output: Any?): OnnxTensor? {
    return when {
      output is OnnxTensor -> output
      output == null -> null
      output.toString().startsWith("Optional[") -> {
        try {
          val getMethod = output.javaClass.getMethod("get")
          getMethod.invoke(output) as? OnnxTensor
        } catch (_: Exception) {
          try {
            val orElseMethod = output.javaClass.getMethod("orElse", Any::class.java)
            orElseMethod.invoke(output, null) as? OnnxTensor
          } catch (_: Exception) {
            null
          }
        }
      }
      else -> null
    }
  }

  private fun mapYamnetToRoles(scores: DoubleArray): Map<String, Double> {
    var vocals = 0.0
    var guitar = 0.0
    var bass = 0.0
    var drums = 0.0
    var synth = 0.0

    for (i in scores.indices) {
      val score = scores[i]
      if (i == 135 || i == 136 || i == 138 || i == 141) guitar += score
      if (i == 137) bass += score
      if (i in 156..168) drums += score
      if (i == 0 || i == 24 || i == 31 || i == 249) vocals += score
      if (i == 153 || i == 147 || i == 148) synth += score
    }

    return normalizeRoleProbs(
      linkedMapOf(
        "vocals" to vocals,
        "guitar" to guitar,
        "bass" to bass,
        "drums" to drums,
        "synth" to synth,
        "other" to 0.01,
      ),
    )
  }

  private fun normalizeRoleProbs(raw: Map<String, Double>): Map<String, Double> {
    val sum = raw.values.sum()
    if (sum <= 0.0) {
      return fallbackRoleProbs()
    }
    return raw.mapValues { (_, value) -> value / sum }
  }

  private fun fallbackRoleProbs(): Map<String, Double> =
    linkedMapOf(
      "vocals" to 0.17,
      "drums" to 0.17,
      "bass" to 0.17,
      "guitar" to 0.17,
      "synth" to 0.16,
      "other" to 0.16,
    )
}

private fun Map<String, Any>.doubleMap(key: String): Map<String, Double> {
  val raw = this[key] as? Map<*, *> ?: return emptyMap()
  val out = LinkedHashMap<String, Double>(raw.size)
  for ((rawKey, rawValue) in raw) {
    val keyString = rawKey?.toString() ?: continue
    val num = when (rawValue) {
      is Number -> rawValue.toDouble()
      is String -> rawValue.toDoubleOrNull()
      else -> null
    } ?: continue
    out[keyString] = num
  }
  return out
}

private fun Map<String, Any>.floatArrayList(key: String): List<FloatArray> {
  val raw = this[key] as? List<*> ?: return emptyList()
  return raw.mapNotNull { item -> item as? FloatArray }
}
