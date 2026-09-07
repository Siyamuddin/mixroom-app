package com.mixroom.juce_audio_engine

/** Narrow native seam: capture finalization and route teardown are distinct. */
internal interface AndroidCaptureNativeV2 {
  fun isRecording(): Boolean
  fun start(path: String, channelStart: Int, channelCount: Int): Boolean
  fun stop(preserveMonitoring: Boolean): Map<String, Any>
  fun discard(preserveMonitoring: Boolean)
}

/** Invoked on the serialized audio lifecycle executor; never owns a device route. */
internal class AndroidCaptureLifecycleV2(private val native: AndroidCaptureNativeV2) {
  fun start(
    path: String,
    ownedChannelStart: Int,
    ownedChannelCount: Int,
    requestedChannelStart: Int,
    requestedChannelCount: Int,
    preserveMonitoring: Boolean,
    isCurrentAndReady: () -> Boolean,
    isCancelled: () -> Boolean,
  ): Boolean {
    if (path.isBlank() || requestedChannelStart != ownedChannelStart ||
      requestedChannelCount != ownedChannelCount || ownedChannelStart < 0 ||
      ownedChannelCount !in 1..2 || isCancelled() || !isCurrentAndReady() || native.isRecording()
    ) return false
    try {
      val started = native.start(path, ownedChannelStart, ownedChannelCount)
      if (!started || isCancelled() || !isCurrentAndReady()) {
        if (native.isRecording()) native.discard(preserveMonitoring)
        return false
      }
      return true
    } catch (_: Exception) {
      // A native failure may occur after arming the writer. Close it before
      // reporting failure so Dart may safely dispose of the unpublished file.
      native.discard(preserveMonitoring)
      return false
    }
  }

  fun stop(preserveMonitoring: Boolean, isCurrent: () -> Boolean): Map<String, Any> {
    if (!isCurrent()) return failure("route_unstable")
    val result = try {
      native.stop(preserveMonitoring)
    } catch (_: Exception) {
      native.discard(preserveMonitoring)
      failure("writer_finalize_failed")
    }
    return if (isCurrent()) result else result + failure("route_unstable")
  }

  private fun failure(code: String): Map<String, Any> =
    mapOf("success" to false, "diagnosticCode" to code)
}
