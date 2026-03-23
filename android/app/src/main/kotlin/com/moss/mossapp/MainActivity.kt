package com.mixroom.mixroomapp

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
  companion object {
    private const val MAX_INCOMING_MIXROOM_BYTES = 512L * 1024L * 1024L
  }

  private val openFileChannelName = "mixroom/open_file"
  private val hapticsChannelName = "mixroom/haptics"
  private var openFileChannel: MethodChannel? = null
  private var hapticsChannel: MethodChannel? = null
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
}
