package com.mixroom.mixroomapp

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

  private val CHANNEL = "mixroom/open_file"
  private var methodChannel: MethodChannel? = null
  private var initialMixroomPath: String? = null

  override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    methodChannel?.setMethodCallHandler { call, result ->
      when (call.method) {
        "getInitialMixroomPath" -> {
          result.success(initialMixroomPath)
          initialMixroomPath = null
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

    if (isInitial && methodChannel == null) {
      initialMixroomPath = path
    } else {
      deliverPath(path)
    }
  }

  private fun deliverPath(path: String) {
    val ch = methodChannel
    if (ch != null) {
      ch.invokeMethod("openMixroomPath", path)
    } else {
      initialMixroomPath = path
    }
  }

  private fun copyUriToCacheIfMixroom(uri: Uri): String? {
    val name = guessFileName(uri) ?: return null
    if (!name.lowercase().endsWith(".mixroom")) return null

    return try {
      val input = contentResolver.openInputStream(uri) ?: return null
      input.use { ins ->
        val outFile = File(cacheDir, "incoming_${System.currentTimeMillis()}_$name")
        FileOutputStream(outFile).use { outs ->
          val buf = ByteArray(1024 * 64)
          while (true) {
            val r = ins.read(buf)
            if (r <= 0) break
            outs.write(buf, 0, r)
          }
          outs.flush()
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
}
