package com.mixroom.mixroomapp

import android.content.Context
import android.content.Intent
import android.content.ContentValues
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.Environment
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.MediaStore
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
  companion object {
    private const val MAX_INCOMING_MIXROOM_BYTES = 512L * 1024L * 1024L
  }

  private val openFileChannelName = "mixroom/open_file"
  private val hapticsChannelName = "mixroom/haptics"
  private val producerExportsChannelName = "mixroom/producer_exports"
  private var openFileChannel: MethodChannel? = null
  private var hapticsChannel: MethodChannel? = null
  private var producerExportsChannel: MethodChannel? = null
  private var initialMixroomPath: String? = null

  override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    openFileChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, openFileChannelName)
    openFileChannel?.setMethodCallHandler { call, result ->
      when (call.method) {
        "getInitialMixroomPath" -> {
          result.success(initialMixroomPath)
          initialMixroomPath = null
        }
        else -> result.notImplemented()
      }
    }

    hapticsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, hapticsChannelName)
    hapticsChannel?.setMethodCallHandler { call, result ->
      when (call.method) {
        "impact" -> {
          val args = call.arguments as? Map<*, *>
          val style = (args?.get("style") as? String) ?: "light"
          performHapticImpact(style)
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }

    producerExportsChannel = MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      producerExportsChannelName,
    )
    producerExportsChannel?.setMethodCallHandler { call, result ->
      when (call.method) {
        "saveProducerSessionToDownloads" -> {
          val args = call.arguments as? Map<*, *>
          val sourcePath = args?.get("sourcePath") as? String
          val displayName = args?.get("displayName") as? String
          val mimeType = (args?.get("mimeType") as? String) ?: "application/json"
          if (sourcePath.isNullOrBlank() || displayName.isNullOrBlank()) {
            result.error("bad_args", "Missing sourcePath or displayName", null)
          } else {
            try {
              result.success(
                saveProducerSessionToDownloads(sourcePath, displayName, mimeType)
              )
            } catch (e: Exception) {
              result.error("save_failed", e.message, null)
            }
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    handleIntent(intent, isInitial = true)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    handleIntent(intent, isInitial = false)
  }

  private fun handleIntent(intent: Intent?, isInitial: Boolean) {
    if (intent == null) return

    val action = intent.action

    val uri = when (action) {
      Intent.ACTION_VIEW -> intent.data
      Intent.ACTION_SEND -> intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
      else -> null
    } ?: return

    val path = copyUriToCacheIfMixroom(uri) ?: return

    if (isInitial && openFileChannel == null) {
      initialMixroomPath = path
    } else {
      deliverPath(path)
    }
  }

  private fun deliverPath(path: String) {
    val ch = openFileChannel
    if (ch != null) {
      ch.invokeMethod("openMixroomPath", path)
    } else {
      initialMixroomPath = path
    }
  }

  private fun performHapticImpact(style: String) {
    val rootView = window?.decorView
    val feedbackConstant = when (style.lowercase()) {
      "heavy" -> HapticFeedbackConstants.LONG_PRESS
      "medium" -> HapticFeedbackConstants.CONTEXT_CLICK
      else -> HapticFeedbackConstants.KEYBOARD_TAP
    }

    // First ask the view system for tactile feedback. This tends to map better
    // to OEM devices like Samsung than Flutter's generic haptics.
    val performedByView = rootView?.performHapticFeedback(
      feedbackConstant,
      HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING
    ) ?: false
    if (performedByView) return

    val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
      manager?.defaultVibrator
    } else {
      @Suppress("DEPRECATION")
      getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    if (vibrator == null || !vibrator.hasVibrator()) return

    val durationMs = when (style.lowercase()) {
      "heavy" -> 28L
      "medium" -> 18L
      else -> 10L
    }
    val amplitude = when (style.lowercase()) {
      "heavy" -> 255
      "medium" -> 180
      else -> 100
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      vibrator.vibrate(VibrationEffect.createOneShot(durationMs, amplitude))
    } else {
      @Suppress("DEPRECATION")
      vibrator.vibrate(durationMs)
    }
  }

  private fun copyUriToCacheIfMixroom(uri: Uri): String? {
    val rawName = guessFileName(uri) ?: return null
    if (!rawName.lowercase().endsWith(".mixroom")) return null
    val safeName = sanitizeFileName(rawName)

    return try {
      val input = contentResolver.openInputStream(uri) ?: return null
      input.use { ins ->
        val outFile = File(
          cacheDir,
          "incoming_${System.currentTimeMillis()}_$safeName",
        )
        var exceededLimit = false
        FileOutputStream(outFile).use { outs ->
          val buf = ByteArray(1024 * 64)
          var totalBytes = 0L
          while (true) {
            val r = ins.read(buf)
            if (r <= 0) break
            totalBytes += r.toLong()
            if (totalBytes > MAX_INCOMING_MIXROOM_BYTES) {
              exceededLimit = true
              break
            }
            outs.write(buf, 0, r)
          }
          outs.flush()
        }
        if (exceededLimit) {
          outFile.delete()
          return null
        }
        outFile.absolutePath
      }
    } catch (e: Exception) {
      null
    }
  }

  private fun guessFileName(uri: Uri): String? {
    // Try display name from content resolver
    try {
      val cursor = contentResolver.query(uri, null, null, null, null)
      cursor?.use {
        val nameIndex = it.getColumnIndex("_display_name")
        if (nameIndex >= 0 && it.moveToFirst()) {
          val n = it.getString(nameIndex)
          if (!n.isNullOrEmpty()) return n
        }
      }
    } catch (_: Exception) {}

    // Fallback
    val seg = uri.lastPathSegment ?: return null
    return seg.substringAfterLast('/')
  }

  private fun sanitizeFileName(rawName: String): String {
    val justName = rawName
      .substringAfterLast('/')
      .substringAfterLast('\\')
    val cleaned = justName.replace(Regex("[^A-Za-z0-9._-]"), "_")
    return cleaned.take(120).ifBlank { "import.mixroom" }
  }

  private fun saveProducerSessionToDownloads(
    sourcePath: String,
    displayName: String,
    mimeType: String,
  ): String {
    val sourceFile = File(sourcePath)
    require(sourceFile.exists()) { "Source file does not exist" }
    val safeName = sanitizeFileName(displayName)

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      val values = ContentValues().apply {
        put(MediaStore.Downloads.DISPLAY_NAME, safeName)
        put(MediaStore.Downloads.MIME_TYPE, mimeType)
        put(
          MediaStore.Downloads.RELATIVE_PATH,
          "${Environment.DIRECTORY_DOWNLOADS}/Mixroom",
        )
        put(MediaStore.Downloads.IS_PENDING, 1)
      }
      val resolver = contentResolver
      val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
      val uri = resolver.insert(collection, values)
        ?: throw IllegalStateException("Could not create Downloads entry")

      try {
        FileInputStream(sourceFile).use { input ->
          resolver.openOutputStream(uri)?.use { output ->
            input.copyTo(output)
          } ?: throw IllegalStateException("Could not open Downloads output stream")
        }
        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return "Downloads/Mixroom/$safeName"
      } catch (e: Exception) {
        resolver.delete(uri, null, null)
        throw e
      }
    }

    @Suppress("DEPRECATION")
    val downloadsDir = Environment.getExternalStoragePublicDirectory(
      Environment.DIRECTORY_DOWNLOADS,
    )
    val mixroomDir = File(downloadsDir, "Mixroom")
    if (!mixroomDir.exists()) {
      mixroomDir.mkdirs()
    }
    val targetFile = File(mixroomDir, safeName)
    FileInputStream(sourceFile).use { input ->
      FileOutputStream(targetFile).use { output ->
        input.copyTo(output)
      }
    }
    return targetFile.absolutePath
  }
}
