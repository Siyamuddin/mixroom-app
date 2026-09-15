package com.mixroom.juce_audio_engine

import android.media.AudioManager
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

// The System Default Oboe input and Bluetooth communication capture are mono.
// This is an app capture capability, not the advertised device channel count.
internal object AndroidRecordingChannelPolicyV2 {
  const val channelStart = 0
  const val channelCount = 1
  fun accepts(start: Int, count: Int): Boolean = start == channelStart && count == channelCount
  fun toMap(): Map<String, Int> = mapOf("channelStart" to channelStart, "channelCount" to channelCount)
}

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

internal enum class AndroidRecordingRouteAdapterV2 {
  BUILT_IN,
  BLUETOOTH_COMMUNICATION,
  SYSTEM_SELECTED,
}

internal object AndroidMonitoringReadinessV2 {
  fun validate(facts: AndroidRecordingFactsV2): String {
    val genericReadiness = AndroidSystemSelectedDuplexReadinessV2.validate(facts)
    if (genericReadiness != "ok") return genericReadiness
    val allowedKinds = setOf(
      AndroidRouteKindV2.BUILT_IN,
      AndroidRouteKindV2.WIRED,
      AndroidRouteKindV2.EXTERNAL,
    )
    if (
      facts.sourceOutput?.kind !in allowedKinds ||
      facts.actualInput?.kind !in allowedKinds ||
      facts.actualOutput?.kind !in allowedKinds
    ) {
      return "monitoring_unavailable"
    }
    return "ok"
  }
}

/** Selects one system-owned recording adapter before any route mutation occurs. */
internal object AndroidSystemRecordingRouteResolverV2 {
  fun resolve(
    sourceKind: AndroidRouteKindV2,
    apiLevel: Int,
    communicationCandidateCount: Int,
  ): AndroidRecordingRouteAdapterV2? {
    if (
      sourceKind != AndroidRouteKindV2.BLUETOOTH_MEDIA &&
      sourceKind != AndroidRouteKindV2.BLUETOOTH_LE
    ) {
      return AndroidRecordingRouteAdapterV2.SYSTEM_SELECTED
    }
    return when {
      communicationCandidateCount == 0 ->
        AndroidRecordingRouteAdapterV2.SYSTEM_SELECTED
      apiLevel >= 29 && communicationCandidateCount == 1 ->
        AndroidRecordingRouteAdapterV2.BLUETOOTH_COMMUNICATION
      else -> null
    }
  }
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
  val requiredInputChannels: Int = 1,
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
      facts.requiredInputChannels !in 1..32 ||
      facts.activeInputChannels != facts.requiredInputChannels ||
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
      inputStream.channelCount != facts.requiredInputChannels ||
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

/** Verifies an OS-selected non-communication duplex route from native facts. */
internal object AndroidSystemSelectedDuplexReadinessV2 {
  fun validate(facts: AndroidRecordingFactsV2): String {
    if (!facts.ownedByV2) return "implementation_conflict"
    val source = facts.sourceOutput ?: return "no_output"

    val input = facts.actualInput ?: return "no_input"
    val output = facts.actualOutput ?: return "no_output"
    if (output.fingerprint != source.fingerprint) {
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
      facts.requiredInputChannels !in 1..32 ||
      facts.activeInputChannels != facts.requiredInputChannels ||
      facts.activeOutputChannels <= 0 ||
      facts.sampleRateHz <= 0.0 ||
      facts.bufferFrames <= 0
    ) {
      return "actual_state_unavailable"
    }

    val inputStream = facts.inputStream
    val outputStream = facts.outputStream
    val retainsBluetoothMedia =
      source.kind == AndroidRouteKindV2.BLUETOOTH_MEDIA ||
        source.kind == AndroidRouteKindV2.BLUETOOTH_LE
    if (
      !inputStream.available ||
      !inputStream.running ||
      inputStream.routedDeviceId != input.id ||
      inputStream.channelCount != facts.requiredInputChannels ||
      (inputStream.sampleRateHz ?: 0) <= 0 ||
      (inputStream.bufferFrames ?: 0) <= 0 ||
      !outputStream.available ||
      !outputStream.running ||
      (outputStream.streamEpoch ?: 0L) <= 0L ||
      outputStream.routedDeviceId != output.id ||
      outputStream.channelCount != facts.activeOutputChannels ||
      (outputStream.sampleRateHz ?: 0) <= 0 ||
      (outputStream.bufferFrames ?: 0) <= 0 ||
      (retainsBluetoothMedia && outputStream.performanceMode != "None") ||
      (retainsBluetoothMedia && outputStream.sharingMode != "Shared")
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
