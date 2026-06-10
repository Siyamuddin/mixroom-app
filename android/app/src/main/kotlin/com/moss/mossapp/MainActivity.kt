package com.mixroom.mixroomapp

import android.content.Context
import android.content.Intent
import android.content.ContentValues
import android.content.ClipData
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.MediaStore
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.activity.enableEdgeToEdge
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterFragmentActivity() {
  companion object {
    private const val MAX_INCOMING_MIXROOM_BYTES = 512L * 1024L * 1024L
    private const val MAX_INCOMING_AUDIO_BYTES = 512L * 1024L * 1024L
    private const val REQUEST_CODE_SAVE_EXPORTED_FILE = 40171
  }

  private val openFileChannelName = "mixroom/open_file"
  private val hapticsChannelName = "mixroom/haptics"
  private val producerExportsChannelName = "mixroom/producer_exports"
  private val savedExportsChannelName = "mixroom/saved_exports"
  private var openFileChannel: MethodChannel? = null
  private var hapticsChannel: MethodChannel? = null
  private var producerExportsChannel: MethodChannel? = null
  private var savedExportsChannel: MethodChannel? = null
  private var initialMixroomPath: String? = null
  private var initialMixroomUrl: String? = null
  private var pendingSavedExportResult: MethodChannel.Result? = null
  private var pendingSavedExportSourcePath: String? = null
  private var pendingSavedExportSuggestedFileName: String? = null

  override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    openFileChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, openFileChannelName)
    openFileChannel?.setMethodCallHandler { call, result ->
      when (call.method) {
        "getInitialMixroomPath" -> {
          result.success(initialMixroomPath)
          initialMixroomPath = null
        }
        "getInitialMixroomUrl" -> {
          result.success(initialMixroomUrl)
          initialMixroomUrl = null
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

    savedExportsChannel = MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      savedExportsChannelName,
    )
    savedExportsChannel?.setMethodCallHandler { call, result ->
      when (call.method) {
        "openSavedExport" -> {
          val args = call.arguments as? Map<*, *>
          val path = args?.get("path") as? String
          if (path.isNullOrBlank()) {
            result.success(false)
          } else {
            result.success(openSavedExport(path))
          }
        }
        "saveExportedFile" -> {
          val args = call.arguments as? Map<*, *>
          val sourceFilePath = args?.get("sourceFilePath") as? String
          val suggestedFileName = args?.get("suggestedFileName") as? String
          val mimeType = (args?.get("mimeType") as? String)?.trim().orEmpty()
          if (sourceFilePath.isNullOrBlank() || suggestedFileName.isNullOrBlank()) {
            result.error("bad_args", "Missing sourceFilePath or suggestedFileName", null)
          } else {
            launchSavedExportDocument(
              sourceFilePath = sourceFilePath,
              suggestedFileName = suggestedFileName,
              mimeType = if (mimeType.isNotEmpty()) mimeType else "*/*",
              result = result,
            )
          }
        }
        "normalizeSavedExportName" -> {
          val args = call.arguments as? Map<*, *>
          val path = args?.get("path") as? String
          val expectedExtension = args?.get("expectedExtension") as? String
          if (path.isNullOrBlank() || expectedExtension.isNullOrBlank()) {
            result.success(path)
          } else {
            result.success(normalizeSavedExportName(path, expectedExtension))
          }
        }
        "resolveSavedExportDisplayName" -> {
          val args = call.arguments as? Map<*, *>
          val path = args?.get("path") as? String
          if (path.isNullOrBlank()) {
            result.success(null)
          } else {
            result.success(resolveSavedExportDisplayName(path))
          }
        }
        "materializeSavedExportForPreview" -> {
          val args = call.arguments as? Map<*, *>
          val path = args?.get("path") as? String
          if (path.isNullOrBlank()) {
            result.success(null)
          } else {
            result.success(materializeSavedExportForPreview(path))
          }
        }
        "shareSavedExport" -> {
          val args = call.arguments as? Map<*, *>
          val path = args?.get("path") as? String
          if (path.isNullOrBlank()) {
            result.success(false)
          } else {
            result.success(shareSavedExport(path))
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
    handleIntent(intent, isInitial = true)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    handleIntent(intent, isInitial = false)
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    if (requestCode == REQUEST_CODE_SAVE_EXPORTED_FILE) {
      handleSavedExportDocumentResult(resultCode, data)
      return
    }
    super.onActivityResult(requestCode, resultCode, data)
  }

  private fun handleIntent(intent: Intent?, isInitial: Boolean) {
    if (intent == null) return

    val action = intent.action

    val uri = when (action) {
      Intent.ACTION_VIEW -> intent.data
      Intent.ACTION_SEND -> intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
      else -> null
    } ?: return

    if (isMixroomEducationInviteUri(uri)) {
      deliverUrl(uri.toString(), isInitial)
      return
    }

    val path = copyUriToCacheIfSupportedImport(uri) ?: return

    if (isInitial && openFileChannel == null) {
      initialMixroomPath = path
    } else {
      deliverPath(path)
    }
  }

  private fun launchSavedExportDocument(
    sourceFilePath: String,
    suggestedFileName: String,
    mimeType: String,
    result: MethodChannel.Result,
  ) {
    if (pendingSavedExportResult != null) {
      result.error("save_in_progress", "Another export save is already in progress", null)
      return
    }

    val sourceFile = File(sourceFilePath)
    if (!sourceFile.exists() || !sourceFile.isFile) {
      result.error("source_missing", "Export source file is missing", null)
      return
    }

    pendingSavedExportResult = result
    pendingSavedExportSourcePath = sourceFile.absolutePath
    pendingSavedExportSuggestedFileName = suggestedFileName

    try {
      val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        type = mimeType.ifBlank { "*/*" }
        putExtra(Intent.EXTRA_TITLE, suggestedFileName)
      }
      startActivityForResult(intent, REQUEST_CODE_SAVE_EXPORTED_FILE)
    } catch (e: Exception) {
      clearPendingSavedExport()
      result.error("save_launch_failed", e.message, null)
    }
  }

  private fun handleSavedExportDocumentResult(resultCode: Int, data: Intent?) {
    val result = pendingSavedExportResult
    val sourceFilePath = pendingSavedExportSourcePath
    val suggestedFileName = pendingSavedExportSuggestedFileName

    if (result == null) {
      clearPendingSavedExport()
      return
    }

    if (resultCode != RESULT_OK || data?.data == null) {
      clearPendingSavedExport()
      result.success(null)
      return
    }

    if (sourceFilePath.isNullOrBlank() || suggestedFileName.isNullOrBlank()) {
      clearPendingSavedExport()
      result.error("save_state_missing", "Missing pending export save state", null)
      return
    }

    val destinationUri = data.data!!
    try {
      val persistFlags =
        data.flags and
          (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
      if (persistFlags != 0) {
        contentResolver.takePersistableUriPermission(destinationUri, persistFlags)
      }
    } catch (_: Exception) {
      // Persisting the URI permission is best-effort only.
    }

    Thread {
      try {
        val finalUri = saveExportedFileToDocument(
          sourceFile = File(sourceFilePath),
          destinationUri = destinationUri,
          suggestedFileName = suggestedFileName,
        )
        runOnUiThread {
          clearPendingSavedExport()
          result.success(finalUri.toString())
        }
      } catch (e: Exception) {
        runOnUiThread {
          clearPendingSavedExport()
          result.error("save_failed", e.message, null)
        }
      }
    }.start()
  }

  private fun clearPendingSavedExport() {
    pendingSavedExportResult = null
    pendingSavedExportSourcePath = null
    pendingSavedExportSuggestedFileName = null
  }

  private fun deliverPath(path: String) {
    val ch = openFileChannel
    if (ch != null) {
      ch.invokeMethod("openMixroomPath", path)
    } else {
      initialMixroomPath = path
    }
  }

  private fun deliverUrl(url: String, isInitial: Boolean) {
    val ch = openFileChannel
    initialMixroomUrl = url
    if (isInitial && ch == null) {
      initialMixroomUrl = url
    } else if (ch != null) {
      ch.invokeMethod("openMixroomUrl", url)
    } else {
      initialMixroomUrl = url
    }
  }

  private fun isMixroomEducationInviteUri(uri: Uri): Boolean {
    if (uri.scheme != "mixroom") return false
    val host = uri.host ?: return false
    return host == "education" && uri.pathSegments.firstOrNull() == "invites"
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

  private fun copyUriToCacheIfSupportedImport(uri: Uri): String? {
    val rawName = guessFileName(uri) ?: return null
    val lowerName = rawName.lowercase()
    val isProject = lowerName.endsWith(".mixroom")
    val isAudio = isSupportedIncomingAudioName(lowerName)
    if (!isProject && !isAudio) return null
    val safeName = sanitizeFileName(rawName)
    val maxBytes = if (isProject) MAX_INCOMING_MIXROOM_BYTES else MAX_INCOMING_AUDIO_BYTES

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
            if (totalBytes > maxBytes) {
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

  private fun isSupportedIncomingAudioName(lowerName: String): Boolean {
    return lowerName.endsWith(".wav") ||
      lowerName.endsWith(".wave") ||
      lowerName.endsWith(".mp3") ||
      lowerName.endsWith(".m4a") ||
      lowerName.endsWith(".aac") ||
      lowerName.endsWith(".caf") ||
      lowerName.endsWith(".aiff") ||
      lowerName.endsWith(".aif") ||
      lowerName.endsWith(".flac") ||
      lowerName.endsWith(".ogg")
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

  private fun normalizeSavedExportName(path: String, expectedExtension: String): String {
    val normalizedPath = path.trim()
    if (normalizedPath.isEmpty()) return path

    val expectedExt = expectedExtension.trim().removePrefix(".").lowercase()
    if (expectedExt.isEmpty()) return path

    for (uri in buildSavedExportUriCandidates(normalizedPath)) {
      return normalizeSavedExportUri(uri, expectedExt).toString()
    }

    return path
  }

  private fun saveExportedFileToDocument(
    sourceFile: File,
    destinationUri: Uri,
    suggestedFileName: String,
  ): Uri {
    sourceFile.inputStream().use { input ->
      contentResolver.openOutputStream(destinationUri, "rwt")?.use { output ->
        input.copyTo(output)
        output.flush()
      } ?: throw IllegalStateException("Unable to open destination output stream")
    }

    val expectedExtension =
      suggestedFileName.substringAfterLast('.', "").trim().removePrefix(".").lowercase()
    if (expectedExtension.isEmpty()) {
      return destinationUri
    }
    return normalizeSavedExportUri(destinationUri, expectedExtension)
  }

  private fun normalizeSavedExportUri(uri: Uri, expectedExtension: String): Uri {
    val currentDisplayName = queryDisplayName(uri) ?: displayNameFromDocumentUri(uri) ?: return uri
    val correctedDisplayName =
      correctedDisplayNameForExtension(currentDisplayName, expectedExtension) ?: return uri

    if (currentDisplayName.equals(correctedDisplayName, ignoreCase = true)) {
      return uri
    }

    return try {
      DocumentsContract.renameDocument(contentResolver, uri, correctedDisplayName) ?: uri
    } catch (_: Exception) {
      uri
    }
  }

  private fun resolveSavedExportDisplayName(path: String): String? {
    val normalizedPath = path.trim()
    if (normalizedPath.isEmpty()) return null

    val uriCandidates = buildSavedExportUriCandidates(normalizedPath)
    for (uri in uriCandidates) {
      val displayName = queryDisplayName(uri) ?: displayNameFromDocumentUri(uri)
      if (!displayName.isNullOrBlank()) {
        return displayName
      }
    }

    val localFile = File(normalizedPath)
    if (localFile.exists()) {
      return localFile.name
    }

    for (documentId in extractDocumentIdsFromPath(normalizedPath)) {
      val fallbackName = documentId
        .substringAfterLast('/')
        .substringAfterLast(':')
        .trim()
      if (fallbackName.isNotEmpty()) {
        return fallbackName
      }
      val documentLocalFile = localFileFromDocumentId(documentId)
      if (documentLocalFile != null && documentLocalFile.exists()) {
        return documentLocalFile.name
      }
    }

    return null
  }

  private fun materializeSavedExportForPreview(path: String): String? {
    val normalizedPath = path.trim()
    if (normalizedPath.isEmpty()) return null

    val directFile = File(normalizedPath)
    if (directFile.exists() && directFile.isFile) {
      return directFile.absolutePath
    }

    for (documentId in extractDocumentIdsFromPath(normalizedPath)) {
      val localFile = localFileFromDocumentId(documentId)
      if (localFile != null && localFile.exists() && localFile.isFile) {
        return localFile.absolutePath
      }
    }

    for (uri in buildSavedExportUriCandidates(normalizedPath)) {
      try {
        val displayName =
          queryDisplayName(uri)
            ?: displayNameFromDocumentUri(uri)
            ?: "mixroom_export_preview"
        val safeName = sanitizeFileName(displayName)
        val cacheFile = File(
          cacheDir,
          "saved_export_preview_${System.currentTimeMillis()}_$safeName",
        )

        contentResolver.openInputStream(uri)?.use { input ->
          FileOutputStream(cacheFile).use { output ->
            input.copyTo(output)
            output.flush()
          }
        } ?: continue

        if (cacheFile.exists() && cacheFile.length() > 0L) {
          return cacheFile.absolutePath
        }

        cacheFile.delete()
      } catch (_: Exception) {}
    }

    return null
  }

  private fun buildSavedExportUriCandidates(path: String): List<Uri> {
    val candidates = mutableListOf<Uri>()

    fun addCandidate(uri: Uri?) {
      if (uri == null) return
      if (candidates.any { it.toString() == uri.toString() }) return
      candidates.add(uri)
    }

    val raw = path.trim()
    if (raw.isEmpty()) return candidates

    val variants = linkedSetOf(raw)
    try {
      variants.add(Uri.decode(raw))
    } catch (_: Exception) {}

    for (variant in variants) {
      if (variant.contains("://")) {
        try {
          addCandidate(Uri.parse(variant))
        } catch (_: Exception) {}
      }
    }

    val authorities = buildDocumentProviderAuthorities()

    for (documentId in extractDocumentIdsFromPath(path)) {
      for (authority in authorities) {
        try {
          addCandidate(DocumentsContract.buildDocumentUri(authority, documentId))
        } catch (_: Exception) {}
      }
    }

    val localDocumentId = localPathToDocumentId(path)
    if (!localDocumentId.isNullOrBlank()) {
      for (authority in authorities) {
        try {
          addCandidate(DocumentsContract.buildDocumentUri(authority, localDocumentId))
        } catch (_: Exception) {}
      }
    }

    for ((treeId, documentId) in extractTreeAndDocumentIdsFromPath(path)) {
      for (authority in authorities) {
        try {
          val treeUri = DocumentsContract.buildTreeDocumentUri(authority, treeId)
          addCandidate(treeUri)
          val docId = documentId ?: treeId
          addCandidate(DocumentsContract.buildDocumentUriUsingTree(treeUri, docId))
        } catch (_: Exception) {}
      }
    }

    return candidates
  }

  private fun shareSavedExport(path: String): Boolean {
    val normalized = path.trim()
    if (normalized.isEmpty()) return false

    val uriCandidates = buildSavedExportUriCandidates(normalized)
    for (uri in uriCandidates) {
      try {
        val mimeType = contentResolver.getType(uri) ?: "*/*"
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
          type = mimeType
          putExtra(Intent.EXTRA_STREAM, uri)
          clipData = ClipData.newUri(contentResolver, "Mixroom export", uri)
          addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
              Intent.FLAG_GRANT_READ_URI_PERMISSION or
              Intent.FLAG_GRANT_WRITE_URI_PERMISSION
          )
        }

        val resolveInfoList =
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
              shareIntent,
              PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong()),
            )
          } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(shareIntent, PackageManager.MATCH_DEFAULT_ONLY)
          }

        if (resolveInfoList.isEmpty()) {
          continue
        }

        for (resolveInfo in resolveInfoList) {
          val packageName = resolveInfo.activityInfo.packageName
          grantUriPermission(
            packageName,
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
          )
        }

        val chooser = Intent.createChooser(shareIntent, null).apply {
          addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(chooser)
        return true
      } catch (_: Exception) {}
    }

    return false
  }

  private fun localPathToDocumentId(path: String): String? {
    val raw = path.trim()
    if (raw.isEmpty()) return null
    val absolutePath = try {
      File(raw).absolutePath
    } catch (_: Exception) {
      raw
    }

    @Suppress("DEPRECATION")
    val primaryRoot = Environment.getExternalStorageDirectory()?.absolutePath?.trimEnd('/')
    if (!primaryRoot.isNullOrEmpty() &&
      absolutePath.startsWith("$primaryRoot/", ignoreCase = true)
    ) {
      val relative = absolutePath.removePrefix("$primaryRoot/").trimStart('/')
      if (relative.isNotEmpty()) {
        return "primary:$relative"
      }
    }

    return null
  }

  private fun extractDocumentIdsFromPath(path: String): Set<String> {
    val ids = linkedSetOf<String>()
    val raw = path.trim()
    if (raw.isEmpty()) return ids

    val variants = linkedSetOf(raw)
    try {
      variants.add(Uri.decode(raw))
    } catch (_: Exception) {}

    for (variant in variants) {
      val normalized = if (variant.startsWith("/")) variant else "/$variant"
      if (normalized.startsWith("/document/")) {
        val docId = normalized.substringAfter("/document/").trim('/').trim()
        if (docId.isNotEmpty()) ids.add(docId)
      }
      val marker = "/document/"
      if (normalized.startsWith("/tree/") && normalized.contains(marker)) {
        val docId = normalized.substringAfter(marker).trim('/').trim()
        if (docId.isNotEmpty()) ids.add(docId)
      }
    }

    return ids
  }

  private fun extractTreeAndDocumentIdsFromPath(path: String): List<Pair<String, String?>> {
    val pairs = mutableListOf<Pair<String, String?>>()
    val raw = path.trim()
    if (raw.isEmpty()) return pairs

    val variants = linkedSetOf(raw)
    try {
      variants.add(Uri.decode(raw))
    } catch (_: Exception) {}

    for (variant in variants) {
      val normalized = if (variant.startsWith("/")) variant else "/$variant"
      if (!normalized.startsWith("/tree/")) continue
      val afterTree = normalized.substringAfter("/tree/")
      val marker = "/document/"
      if (afterTree.contains(marker)) {
        val treeId = afterTree.substringBefore(marker).trim('/').trim()
        val docId = afterTree.substringAfter(marker).trim('/').trim()
        if (treeId.isNotEmpty()) {
          pairs.add(treeId to docId.ifBlank { null })
        }
      } else {
        val treeId = afterTree.trim('/').trim()
        if (treeId.isNotEmpty()) {
          pairs.add(treeId to null)
        }
      }
    }
    return pairs
  }

  private fun displayNameFromDocumentUri(uri: Uri): String? {
    return try {
      val documentId = DocumentsContract.getDocumentId(uri).trim()
      if (documentId.isEmpty()) {
        null
      } else {
        documentId
          .substringAfterLast('/')
          .substringAfterLast(':')
          .trim()
          .ifBlank { null }
      }
    } catch (_: Exception) {
      null
    }
  }

  private fun parentDocumentId(documentId: String): String? {
    val cleaned = documentId.trim().trim('/')
    if (cleaned.isEmpty() || !cleaned.contains(":")) return null

    val volume = cleaned.substringBefore(':').trim()
    val relativePath = cleaned.substringAfter(':').trim().trim('/')
    if (volume.isEmpty()) return null
    if (relativePath.isEmpty() || !relativePath.contains('/')) return "$volume:"

    val parentRelativePath = relativePath.substringBeforeLast('/').trim('/')
    return if (parentRelativePath.isEmpty()) "$volume:" else "$volume:$parentRelativePath"
  }

  private fun queryDefaultIntentActivities(intent: Intent): List<android.content.pm.ResolveInfo> {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      packageManager.queryIntentActivities(
        intent,
        PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong())
      )
    } else {
      @Suppress("DEPRECATION")
      packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
    }
  }

  private fun grantUriToIntentHandlers(uri: Uri, flags: Int, handlers: List<android.content.pm.ResolveInfo>) {
    for (resolveInfo in handlers) {
      grantUriPermission(resolveInfo.activityInfo.packageName, uri, flags)
    }
  }

  private fun startUriIntentIfResolvable(intent: Intent, uri: Uri, flags: Int): Boolean {
    val handlers = queryDefaultIntentActivities(intent)
    if (handlers.isEmpty()) return false
    grantUriToIntentHandlers(uri, flags, handlers)
    startActivity(intent)
    return true
  }

  private fun isFolderLikeDocumentUri(uri: Uri): Boolean {
    val path = uri.path ?: return false
    if (path.contains("/tree/") && !path.contains("/document/")) return true
    return try {
      contentResolver.getType(uri) == DocumentsContract.Document.MIME_TYPE_DIR
    } catch (_: Exception) {
      false
    }
  }

  private fun isDocumentsUiHandler(resolveInfo: android.content.pm.ResolveInfo): Boolean {
    val packageName = resolveInfo.activityInfo.packageName.lowercase()
    val activityName = resolveInfo.activityInfo.name.lowercase()
    return packageName.contains("documentsui") || activityName.contains("documentsui")
  }

  private fun isFileManagerHandler(resolveInfo: android.content.pm.ResolveInfo): Boolean {
    val packageName = resolveInfo.activityInfo.packageName.lowercase()
    val activityName = resolveInfo.activityInfo.name.lowercase()
    return isDocumentsUiHandler(resolveInfo) ||
      packageName == "com.sec.android.app.myfiles" ||
      activityName.contains("myfiles") ||
      packageName == "com.android.providers.downloads.ui"
  }

  private fun startWithExactHandler(
    baseIntent: Intent,
    uri: Uri,
    flags: Int,
    handler: android.content.pm.ResolveInfo,
  ): Boolean {
    val exactIntent = Intent(baseIntent).apply {
      setClassName(handler.activityInfo.packageName, handler.activityInfo.name)
    }
    return startUriIntentIfResolvable(exactIntent, uri, flags)
  }

  private fun launchDocumentPickerAtSavedExportFile(path: String): Boolean {
    val permissionFlags =
      Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION

    for (uri in buildSavedExportUriCandidates(path)) {
      if (isFolderLikeDocumentUri(uri)) continue

      val mimeType = try {
        contentResolver.getType(uri) ?: "*/*"
      } catch (_: Exception) {
        "*/*"
      }

      val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        addCategory(Intent.CATEGORY_DEFAULT)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or permissionFlags)
        type = mimeType
        putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri)
      }

      val documentsUiHandlers = queryDefaultIntentActivities(intent).filter(::isDocumentsUiHandler)
      for (handler in documentsUiHandlers) {
        try {
          if (startWithExactHandler(intent, uri, permissionFlags, handler)) {
            return true
          }
        } catch (_: Exception) {}
      }

      val fileViewerHandlers = queryDefaultIntentActivities(intent)
        .filterNot(::isFileManagerHandler)

      for (handler in fileViewerHandlers) {
        try {
          if (startWithExactHandler(intent, uri, permissionFlags, handler)) {
            return true
          }
        } catch (_: Exception) {}
      }
    }

    return false
  }

  private fun launchSavedExportFile(path: String): Boolean {
    val permissionFlags =
      Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION

    for (uri in buildSavedExportUriCandidates(path)) {
      if (isFolderLikeDocumentUri(uri)) continue

      val mimeType = try {
        contentResolver.getType(uri) ?: "*/*"
      } catch (_: Exception) {
        "*/*"
      }

      val intent = Intent(Intent.ACTION_VIEW).apply {
        addCategory(Intent.CATEGORY_DEFAULT)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or permissionFlags)
        setDataAndType(uri, mimeType)
        clipData = ClipData.newUri(contentResolver, "Mixroom export", uri)
      }

      try {
        if (startUriIntentIfResolvable(intent, uri, permissionFlags)) {
          return true
        }
      } catch (_: Exception) {}
    }

    return false
  }

  private fun launchFilesAppForSavedExportFile(path: String): Boolean {
    val permissionFlags =
      Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION

    for (uri in buildSavedExportUriCandidates(path)) {
      if (isFolderLikeDocumentUri(uri)) continue

      val mimeType = try {
        contentResolver.getType(uri) ?: "*/*"
      } catch (_: Exception) {
        "*/*"
      }

      val baseIntent = Intent(Intent.ACTION_VIEW).apply {
        addCategory(Intent.CATEGORY_DEFAULT)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or permissionFlags)
        setDataAndType(uri, mimeType)
        clipData = ClipData.newUri(contentResolver, "Mixroom export", uri)
        putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri)
      }

      val documentsUiHandlers = queryDefaultIntentActivities(baseIntent).filter(::isDocumentsUiHandler)
      for (resolveInfo in documentsUiHandlers) {
        try {
          if (startWithExactHandler(baseIntent, uri, permissionFlags, resolveInfo)) {
            return true
          }
        } catch (_: Exception) {}
      }
    }

    return false
  }

  private fun launchFilesAppForDocument(path: String): Boolean {
    val authorities = buildDocumentProviderAuthorities()
    val parentUris = mutableListOf<Uri>()

    fun addParentUri(authority: String, documentId: String) {
      val parentId = parentDocumentId(documentId) ?: return
      try {
        val uri = DocumentsContract.buildDocumentUri(authority, parentId)
        if (parentUris.none { it.toString() == uri.toString() }) {
          parentUris.add(uri)
        }
      } catch (_: Exception) {}
    }

    for (uri in buildSavedExportUriCandidates(path)) {
      try {
        val authority = uri.authority?.trim()
        val documentId = DocumentsContract.getDocumentId(uri)
        if (!authority.isNullOrEmpty()) {
          addParentUri(authority, documentId)
        }
      } catch (_: Exception) {}
    }

    val localDocumentId = localPathToDocumentId(path)
    if (!localDocumentId.isNullOrBlank()) {
      for (authority in authorities) {
        addParentUri(authority, localDocumentId)
      }
    }

    for (documentId in extractDocumentIdsFromPath(path)) {
      for (authority in authorities) {
        addParentUri(authority, documentId)
      }
    }

    for (folderUri in parentUris) {
      try {
        val intent = Intent(Intent.ACTION_VIEW).apply {
          addCategory(Intent.CATEGORY_DEFAULT)
          addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
          setDataAndType(folderUri, DocumentsContract.Document.MIME_TYPE_DIR)
        }

        val resolveInfoList = queryDefaultIntentActivities(intent)
        if (resolveInfoList.isEmpty()) continue

        val documentsUiHandlers = resolveInfoList.filter(::isDocumentsUiHandler)
        for (resolveInfo in documentsUiHandlers) {
          try {
            if (startWithExactHandler(
                intent,
                folderUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
                resolveInfo
              )
            ) {
              return true
            }
          } catch (_: Exception) {}
        }

        grantUriToIntentHandlers(
          folderUri,
          Intent.FLAG_GRANT_READ_URI_PERMISSION,
          resolveInfoList
        )

        startActivity(intent)
        return true
      } catch (_: Exception) {}
    }

    return false
  }

  private fun localFileFromDocumentId(documentId: String): File? {
    val cleaned = documentId.trim().trim('/')
    if (cleaned.isEmpty() || !cleaned.contains(":")) return null
    val volume = cleaned.substringBefore(':').trim()
    val relativePath = cleaned.substringAfter(':').trim().trimStart('/')
    if (volume.isEmpty() || relativePath.isEmpty()) return null

    val root = if (volume.equals("primary", ignoreCase = true)) {
      @Suppress("DEPRECATION")
      Environment.getExternalStorageDirectory()
    } else {
      File("/storage/$volume")
    }

    return File(root, relativePath)
  }

  private fun localFileFromDocumentUri(uri: Uri): File? {
    return try {
      val documentId = DocumentsContract.getDocumentId(uri)
      localFileFromDocumentId(documentId)
    } catch (_: Exception) {
      null
    }
  }

  private fun buildDocumentProviderAuthorities(): List<String> {
    val authorities = linkedSetOf(
      "com.android.externalstorage.documents",
      "com.android.providers.downloads.documents",
      "com.android.providers.media.documents",
    )

    try {
      for (permission in contentResolver.persistedUriPermissions) {
        val authority = permission.uri?.authority?.trim()
        if (!authority.isNullOrEmpty()) {
          authorities.add(authority)
        }
      }
    } catch (_: Exception) {}

    try {
      val intent = Intent(DocumentsContract.PROVIDER_INTERFACE)
      val providers = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        packageManager.queryIntentContentProviders(
          intent,
          PackageManager.ResolveInfoFlags.of(0),
        )
      } else {
        @Suppress("DEPRECATION")
        packageManager.queryIntentContentProviders(intent, 0)
      }
      for (provider in providers) {
        val authority = provider.providerInfo?.authority?.trim()
        if (!authority.isNullOrEmpty()) {
          authorities.add(authority)
        }
      }
    } catch (_: Exception) {}

    return authorities.toList()
  }

  private fun queryDisplayName(uri: Uri): String? {
    return try {
      contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
        if (!it.moveToFirst()) return null
        val idx = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
        if (idx < 0) return null
        it.getString(idx)
      }
    } catch (_: Exception) {
      null
    }
  }

  private fun correctedDisplayNameForExtension(
    displayName: String,
    expectedExtension: String,
  ): String? {
    val trimmedName = displayName.trim()
    if (trimmedName.isEmpty()) return null

    val expectedExtWithDot = ".$expectedExtension"
    val collisionSuffixPattern = Regex("\\s*\\((\\d+)\\)$")
    val collisionSuffixMatch = collisionSuffixPattern.find(trimmedName)
    val suffix =
      collisionSuffixMatch?.groupValues?.getOrNull(1)?.trim()?.takeIf { it.isNotEmpty() }?.let {
        " ($it)"
      } ?: ""

    var stem = if (collisionSuffixMatch != null) {
      trimmedName.substring(0, collisionSuffixMatch.range.first).trimEnd()
    } else {
      trimmedName
    }

    var removedExpectedExtension = false
    while (stem.lowercase().endsWith(expectedExtWithDot)) {
      stem = stem.dropLast(expectedExtWithDot.length).trimEnd()
      removedExpectedExtension = true
    }

    val canonicalStem = stem.ifBlank { "Mixroom Export" }
    val canonicalName = "$canonicalStem$suffix.$expectedExtension"
    if (trimmedName.equals(canonicalName, ignoreCase = true)) {
      return null
    }

    if (!removedExpectedExtension && suffix.isEmpty() && trimmedName.contains('.')) {
      val lastDot = trimmedName.lastIndexOf('.')
      if (lastDot > 0) {
        val trailingExt = trimmedName.substring(lastDot + 1).trim().lowercase()
        if (trailingExt == expectedExtension.lowercase()) {
          return null
        }
      }
    }

    return canonicalName
  }

  private fun openSavedExport(path: String): Boolean {
    val normalized = path.trim()
    if (normalized.isEmpty()) return false

    return launchSavedExportFile(normalized)
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
