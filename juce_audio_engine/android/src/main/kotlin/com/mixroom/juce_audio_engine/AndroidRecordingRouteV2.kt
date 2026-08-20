package com.mixroom.juce_audio_engine

import android.media.AudioManager
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

internal enum class EngineOwnership {
  NONE,
  LEGACY,
  V2_SESSION;

  val ownsNativeEngine: Boolean
    get() = this != NONE
}

internal enum class AndroidRecordingCleanupDispositionV2 {
  RESTORE_EXACT,
  CLOSE_ONLY,
}

/**
 * Records teardown intent before a waiter is cancelled or released.
 *
 * Safety-oriented requests may strengthen an unclaimed plan. Closing always
 * wins over restoring an endpoint that may already have disappeared. Current-
 * output recovery is a later coordinator-owned playback transition, not a
 * second recording-cleanup mode. The cleanup CAS winner snapshots this plan.
 */
internal class AndroidRecordingCleanupPlanV2 {
  private val selected =
    AtomicReference<AndroidRecordingCleanupDispositionV2?>(null)

  fun select(
    requested: AndroidRecordingCleanupDispositionV2,
  ): AndroidRecordingCleanupDispositionV2 {
    while (true) {
      val current = selected.get()
      val resolved = AndroidRecordingCleanupPolicyV2.resolve(current, requested)
      if (current == resolved || selected.compareAndSet(current, resolved)) {
        return resolved
      }
    }
  }

  fun snapshotForCleanupWinner(): AndroidRecordingCleanupDispositionV2 =
    selected.get() ?: AndroidRecordingCleanupDispositionV2.CLOSE_ONLY
}

internal object AndroidRecordingCleanupPolicyV2 {
  fun resolve(
    current: AndroidRecordingCleanupDispositionV2?,
    requested: AndroidRecordingCleanupDispositionV2,
  ): AndroidRecordingCleanupDispositionV2 = when {
    current == AndroidRecordingCleanupDispositionV2.CLOSE_ONLY ||
      requested == AndroidRecordingCleanupDispositionV2.CLOSE_ONLY ->
      AndroidRecordingCleanupDispositionV2.CLOSE_ONLY
    else -> AndroidRecordingCleanupDispositionV2.RESTORE_EXACT
  }
}

internal class AndroidLifecycleTeardownGateV2 {
  companion object {
    const val STARTUP_TIMEOUT_MILLIS = 6000L
  }

  internal class Completion internal constructor() {
    internal val completed = AtomicBoolean(false)
  }

  private val lock = Any()
  private var pendingCount = 0
  private var clearSignal = CountDownLatch(0)

  fun publish(): Completion {
    val completion = Completion()
    synchronized(lock) {
      if (pendingCount == 0) clearSignal = CountDownLatch(1)
      pendingCount += 1
    }
    return completion
  }

  fun complete(completion: Completion) {
    if (!completion.completed.compareAndSet(false, true)) return
    val signal = synchronized(lock) {
      check(pendingCount > 0)
      pendingCount -= 1
      if (pendingCount == 0) clearSignal else null
    }
    signal?.countDown()
  }

  fun isClear(): Boolean = synchronized(lock) { pendingCount == 0 }

  fun awaitClear(
    timeoutMillis: Long = STARTUP_TIMEOUT_MILLIS,
  ): Boolean {
    val deadlineNanos = System.nanoTime() +
      TimeUnit.MILLISECONDS.toNanos(timeoutMillis.coerceAtLeast(0L))
    while (true) {
      val signal = synchronized(lock) {
        if (pendingCount == 0) return true
        clearSignal
      }
      val remainingNanos = deadlineNanos - System.nanoTime()
      if (remainingNanos <= 0L) return false
      try {
        if (!signal.await(remainingNanos, TimeUnit.NANOSECONDS)) return false
      } catch (_: InterruptedException) {
        Thread.currentThread().interrupt()
        return false
      }
    }
  }
}

internal data class AndroidRecordingFactsV2(
  val ownedByV2: Boolean,
  val sourceOutput: AndroidRouteEndpointV2?,
  val actualInput: AndroidRouteEndpointV2?,
  val actualOutput: AndroidRouteEndpointV2?,
  val audioMode: Int,
  val bluetoothCommunicationDeviceSelected: Boolean,
  val bluetoothScoActive: Boolean,
  val deviceOpen: Boolean,
  val callbackAttached: Boolean,
  val activeInputChannels: Int,
  val activeOutputChannels: Int,
  val sampleRateHz: Double,
  val bufferFrames: Int,
  val inputStream: AndroidOboeOutputFactsV2,
  val outputStream: AndroidOboeOutputFactsV2,
)

internal object AndroidRecordingReadinessV2 {
  fun validate(facts: AndroidRecordingFactsV2): String {
    if (!facts.ownedByV2) return "implementation_conflict"
    val source = facts.sourceOutput ?: return "no_output"
    if (source.kind != AndroidRouteKindV2.BUILT_IN) {
      return "recording_route_unsupported"
    }

    val input = facts.actualInput ?: return "no_input"
    val output = facts.actualOutput ?: return "no_output"
    if (
      input.kind != AndroidRouteKindV2.BUILT_IN ||
      output.kind != AndroidRouteKindV2.BUILT_IN
    ) {
      return "recording_route_unsupported"
    }
    if (output.fingerprint != source.fingerprint) return "route_unstable"

    if (
      facts.audioMode != AudioManager.MODE_NORMAL ||
      facts.bluetoothCommunicationDeviceSelected ||
      facts.bluetoothScoActive
    ) {
      return "actual_state_unavailable"
    }
    if (
      !facts.deviceOpen ||
      !facts.callbackAttached ||
      facts.activeInputChannels != 1 ||
      facts.activeOutputChannels <= 0 ||
      facts.sampleRateHz <= 0.0 ||
      facts.bufferFrames <= 0
    ) {
      return "actual_state_unavailable"
    }

    val inputStream = facts.inputStream
    val outputStream = facts.outputStream
    if (
      !inputStream.available ||
      !inputStream.running ||
      inputStream.routedDeviceId != input.id ||
      inputStream.channelCount != 1 ||
      (inputStream.sampleRateHz ?: 0) <= 0 ||
      (inputStream.bufferFrames ?: 0) <= 0 ||
      !outputStream.available ||
      !outputStream.running ||
      outputStream.routedDeviceId != output.id ||
      outputStream.channelCount != facts.activeOutputChannels ||
      (outputStream.sampleRateHz ?: 0) <= 0 ||
      (outputStream.bufferFrames ?: 0) <= 0
    ) {
      return "actual_state_unavailable"
    }
    if (
      inputStream.sampleRateHz != outputStream.sampleRateHz ||
      inputStream.sampleRateHz?.toDouble() != facts.sampleRateHz
    ) {
      return "actual_state_unavailable"
    }
    return "ok"
  }
}

/**
 * Verifies Android's default non-communication input while preserving an
 * already-selected Bluetooth media output. This deliberately accepts only
 * observable microphone-capable route classes and never infers identity from
 * a product name or Bluetooth address.
 */
internal object AndroidSystemSelectedMediaDuplexReadinessV2 {
  fun validate(facts: AndroidRecordingFactsV2): String {
    if (!facts.ownedByV2) return "implementation_conflict"
    val source = facts.sourceOutput ?: return "no_output"
    if (source.kind != AndroidRouteKindV2.BLUETOOTH_MEDIA) {
      return "recording_route_unsupported"
    }

    val input = facts.actualInput ?: return "no_input"
    val output = facts.actualOutput ?: return "no_output"
    if (
      input.kind !in setOf(
        AndroidRouteKindV2.BUILT_IN,
        AndroidRouteKindV2.WIRED,
        AndroidRouteKindV2.EXTERNAL,
      ) ||
      output.fingerprint != source.fingerprint
    ) {
      return "route_unstable"
    }
    if (
      facts.audioMode != AudioManager.MODE_NORMAL ||
      facts.bluetoothCommunicationDeviceSelected ||
      facts.bluetoothScoActive
    ) {
      return "actual_state_unavailable"
    }
    if (
      !facts.deviceOpen ||
      !facts.callbackAttached ||
      facts.activeInputChannels != 1 ||
      facts.activeOutputChannels <= 0 ||
      facts.sampleRateHz <= 0.0 ||
      facts.bufferFrames <= 0
    ) {
      return "actual_state_unavailable"
    }

    val inputStream = facts.inputStream
    val outputStream = facts.outputStream
    if (
      !inputStream.available ||
      !inputStream.running ||
      inputStream.routedDeviceId != input.id ||
      inputStream.channelCount != 1 ||
      (inputStream.sampleRateHz ?: 0) <= 0 ||
      (inputStream.bufferFrames ?: 0) <= 0 ||
      !outputStream.available ||
      !outputStream.running ||
      (outputStream.streamEpoch ?: 0L) <= 0L ||
      outputStream.routedDeviceId != output.id ||
      outputStream.channelCount != facts.activeOutputChannels ||
      (outputStream.sampleRateHz ?: 0) <= 0 ||
      (outputStream.bufferFrames ?: 0) <= 0 ||
      outputStream.performanceMode != "None" ||
      outputStream.sharingMode != "Shared"
    ) {
      return "actual_state_unavailable"
    }
    if (
      inputStream.sampleRateHz != outputStream.sampleRateHz ||
      inputStream.sampleRateHz?.toDouble() != facts.sampleRateHz
    ) {
      return "actual_state_unavailable"
    }
    return "ok"
  }
}

internal object AndroidPlaybackTransitionOwnershipV2 {
  fun ownsNotification(
    expected: AndroidMediaRouteResolutionV2?,
    current: AndroidMediaRouteResolutionV2,
    availableOutputIds: Set<Int>,
    removedDeviceIds: Set<Int>,
  ): Boolean {
    if (expected == null || expected.diagnosticCode != "ok") return false
    val expectedOutput = expected.endpoint ?: return false
    if (
      expectedOutput.id in removedDeviceIds ||
      expectedOutput.id !in availableOutputIds
    ) {
      return false
    }
    return current.diagnosticCode == "ok" &&
      current.endpoint?.fingerprint == expectedOutput.fingerprint
  }
}
