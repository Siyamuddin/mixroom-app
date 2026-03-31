package com.mixroom.mixroomapp

import android.content.Context
import android.content.Intent
import android.content.ContentValues
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
        "normalizeSavedExportName" -> {
          val args = call.arguments as? Map<*, *>
          val path = args?.get("path") as? String
          val expectedExtension = args?.get("expectedExtension") as? String
          if (path.isNullOrBlank() || expectedExtension.isNullOrBlank()) {
            result.success(path)
          } else {
            result.success(
              normalizeSavedExportName(path = path, expectedExtension = expectedExtension)
            )
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

  private fun normalizeSavedExportName(path: String, expectedExtension: String): String {
    val normalizedPath = path.trim()
    if (normalizedPath.isEmpty()) return path

    val expectedExt = expectedExtension.trim().removePrefix(".").lowercase()
    if (expectedExt.isEmpty()) return path

    val uriCandidates = buildSavedExportUriCandidates(normalizedPath)

    for (uri in uriCandidates) {
      val currentDisplayName = queryDisplayName(uri) ?: displayNameFromDocumentUri(uri) ?: continue
      val correctedDisplayName = correctedDisplayNameForExtension(
        currentDisplayName,
        expectedExt,
      ) ?: continue

      if (currentDisplayName.equals(correctedDisplayName, ignoreCase = true)) {
        return uri.toString()
      }

      try {
        val renamedUri = DocumentsContract.renameDocument(
          contentResolver,
          uri,
          correctedDisplayName,
        )
        if (renamedUri != null) {
          return renamedUri.toString()
        }
      } catch (_: Exception) {
        // Try URI-derived local fallback below.
      }

      val localFromUri = localFileFromDocumentUri(uri)
      if (localFromUri != null && localFromUri.exists()) {
        val normalizedLocalPath = normalizeLocalSavedExportFile(
          localFile = localFromUri,
          expectedExtension = expectedExt,
          fallbackPath = path,
          preferredReturnedPath = path,
        )
        if (normalizedLocalPath != path) {
          return normalizedLocalPath
        }
      }
    }

    val localFile = File(normalizedPath)
    if (localFile.exists()) {
      return normalizeLocalSavedExportFile(
        localFile = localFile,
        expectedExtension = expectedExt,
        fallbackPath = path,
        preferredReturnedPath = normalizedPath,
      )
    }

    for (documentId in extractDocumentIdsFromPath(normalizedPath)) {
      val documentLocalFile = localFileFromDocumentId(documentId) ?: continue
      if (!documentLocalFile.exists()) continue
      return normalizeLocalSavedExportFile(
        localFile = documentLocalFile,
        expectedExtension = expectedExt,
        fallbackPath = path,
        preferredReturnedPath = path,
      )
    }

    return path
  }

  private fun normalizeLocalSavedExportFile(
    localFile: File,
    expectedExtension: String,
    fallbackPath: String,
    preferredReturnedPath: String? = null,
  ): String {
    fun preferredPathForName(fileName: String): String? {
      val preferred = preferredReturnedPath?.trim()
      if (preferred.isNullOrEmpty()) return null
      return replaceFileNameInSavedPath(preferred, fileName)
    }

    val correctedLocalName = correctedDisplayNameForExtension(
      localFile.name,
      expectedExtension,
    ) ?: return preferredPathForName(localFile.name) ?: localFile.absolutePath

    if (localFile.name.equals(correctedLocalName, ignoreCase = true)) {
      return preferredPathForName(localFile.name) ?: localFile.absolutePath
    }
    val parent = localFile.parentFile ?: return fallbackPath
    var target = File(parent, correctedLocalName)
    if (target.exists()) {
      target = uniqueCollisionSafeSibling(
        parent = parent,
        candidateName = correctedLocalName,
        expectedExtension = expectedExtension,
      )
    }
    return try {
      if (localFile.renameTo(target)) {
        preferredPathForName(target.name) ?: target.absolutePath
      } else {
        fallbackPath
      }
    } catch (_: Exception) {
      fallbackPath
    }
  }

  private fun replaceFileNameInSavedPath(path: String, fileName: String): String {
    val trimmedPath = path.trim()
    if (trimmedPath.isEmpty()) return path

    val normalized = if (trimmedPath.startsWith("/")) trimmedPath else "/$trimmedPath"
    val documentMarker = "/document/"
    val treeMarker = "/tree/"

    fun updatedDocumentId(documentId: String): String {
      val cleanId = documentId.trim().trim('/')
      if (cleanId.contains('/')) {
        val prefix = cleanId.substringBeforeLast('/')
        return "$prefix/$fileName"
      }
      if (cleanId.contains(':')) {
        val volumePrefix = cleanId.substringBeforeLast(':')
        return "$volumePrefix:$fileName"
      }
      return fileName
    }

    if (normalized.startsWith(documentMarker)) {
      val existingDocumentId = normalized.substringAfter(documentMarker).trim('/').trim()
      if (existingDocumentId.isNotEmpty()) {
        return "$documentMarker${updatedDocumentId(existingDocumentId)}"
      }
    }

    if (normalized.startsWith(treeMarker) && normalized.contains(documentMarker)) {
      val treeId = normalized.substringAfter(treeMarker).substringBefore(documentMarker).trim('/').trim()
      val existingDocumentId = normalized.substringAfter(documentMarker).trim('/').trim()
      if (treeId.isNotEmpty() && existingDocumentId.isNotEmpty()) {
        return "$treeMarker$treeId$documentMarker${updatedDocumentId(existingDocumentId)}"
      }
    }

    val file = File(trimmedPath)
    val parent = file.parentFile
    return if (parent != null) File(parent, fileName).absolutePath else fileName
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
    if (trimmedName.lowercase().endsWith(expectedExtWithDot)) {
      return null
    }

    val escapedExt = Regex.escape(expectedExtension)
    val extThenCollisionPattern = Regex(
      pattern = "^(.*)\\.${escapedExt}(\\s*\\(\\d+\\))$",
      option = RegexOption.IGNORE_CASE,
    )
    val extThenCollisionMatch = extThenCollisionPattern.matchEntire(trimmedName)
    if (extThenCollisionMatch != null) {
      val stem = extThenCollisionMatch.groupValues[1].trim().ifBlank { "Mixroom Export" }
      val suffix = extThenCollisionMatch.groupValues[2].replace(Regex("\\s+"), " ")
      return "$stem$suffix.$expectedExtension"
    }

    val collisionSuffixPattern = Regex("^(.*?)(\\s*\\(\\d+\\))$")
    val collisionSuffixMatch = collisionSuffixPattern.matchEntire(trimmedName)
    if (collisionSuffixMatch != null) {
      val stemRaw = collisionSuffixMatch.groupValues[1].trim()
      val suffix = collisionSuffixMatch.groupValues[2].replace(Regex("\\s+"), " ")
      val stemLower = stemRaw.lowercase()
      if (stemLower.endsWith(expectedExtWithDot)) {
        return stemRaw
      }
      return "${stemRaw.ifBlank { "Mixroom Export" }}$suffix.$expectedExtension"
    }

    return "$trimmedName.$expectedExtension"
  }

  private fun uniqueCollisionSafeSibling(
    parent: File,
    candidateName: String,
    expectedExtension: String,
  ): File {
    val extSuffix = ".$expectedExtension"
    val stem = if (candidateName.lowercase().endsWith(extSuffix)) {
      candidateName.dropLast(extSuffix.length)
    } else {
      candidateName
    }
    var index = 1
    while (index < 1000) {
      val next = File(parent, "$stem ($index)$extSuffix")
      if (!next.exists()) return next
      index++
    }
    return File(parent, candidateName)
  }

  private fun openSavedExport(path: String): Boolean {
    val normalized = path.trim()
    if (normalized.isEmpty()) return false

    val uriCandidates = mutableListOf<Uri>()

    fun addCandidate(uri: Uri?) {
      if (uri == null) return
      if (uriCandidates.any { it.toString() == uri.toString() }) return
      uriCandidates.add(uri)
    }

    if (normalized.contains("://")) {
      try {
        addCandidate(Uri.parse(normalized))
      } catch (_: Exception) {}
    }

    if (normalized.startsWith("/document/") || normalized.startsWith("/tree/")) {
      val pathValue = if (normalized.startsWith("/")) normalized else "/$normalized"
      val authorities = listOf(
        "com.android.externalstorage.documents",
        "com.android.providers.downloads.documents",
        "com.android.providers.media.documents",
      )
      for (authority in authorities) {
        try {
          addCandidate(Uri.parse("content://$authority$pathValue"))
        } catch (_: Exception) {}
      }
    }

    for (uri in uriCandidates) {
      try {
        val mimeType = contentResolver.getType(uri) ?: "*/*"
        val intent = Intent(Intent.ACTION_VIEW).apply {
          addCategory(Intent.CATEGORY_DEFAULT)
          addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
              Intent.FLAG_GRANT_READ_URI_PERMISSION or
              Intent.FLAG_GRANT_WRITE_URI_PERMISSION
          )
          setDataAndType(uri, mimeType)
        }

        val resolveInfoList = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
          packageManager.queryIntentActivities(
            intent,
            PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong())
          )
        } else {
          @Suppress("DEPRECATION")
          packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
        }

        if (resolveInfoList.isEmpty()) {
          continue
        }

        for (resolveInfo in resolveInfoList) {
          val packageName = resolveInfo.activityInfo.packageName
          grantUriPermission(
            packageName,
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
          )
        }

        startActivity(intent)
        return true
      } catch (_: Exception) {}
    }

    return false
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
