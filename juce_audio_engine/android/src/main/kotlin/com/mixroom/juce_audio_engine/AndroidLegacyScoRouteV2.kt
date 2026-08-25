package com.mixroom.juce_audio_engine

import android.media.AudioManager

internal enum class AndroidBluetoothRouteSelectionModeV2(
  val diagnosticName: String,
) {
  COMMUNICATION_DEVICE("androidCommunicationDevice"),
  LEGACY_SCO("androidLegacySco");

  companion object {
    fun forApiLevel(apiLevel: Int): AndroidBluetoothRouteSelectionModeV2 =
      if (apiLevel >= 31) COMMUNICATION_DEVICE else LEGACY_SCO
  }
}

internal enum class AndroidLegacyScoEventV2 {
  NONE,
  ACQUIRED,
  ACQUISITION_FAILED,
  RELEASED,
  TERMINAL_LOSS,
}

/**
 * Operation-owned state for Android 10-11's sticky SCO broadcast contract.
 *
 * The Android callback is evidence that SCO was acquired or released. Actual
 * input/output ownership is still proven later through JUCE/Oboe readback.
 */
internal class AndroidLegacyScoStateV2 {
  private enum class Phase {
    IDLE,
    ACQUIRING,
    CONNECTED,
    RELEASING,
    RELEASED,
    FAILED,
  }

  private val lock = Any()
  private var phase = Phase.IDLE
  private var connectingObserved = false
  private var requestStarted = false
  private var stopClaimed = false

  fun beginAcquisition(stickyState: Int): AndroidLegacyScoEventV2 =
    synchronized(lock) {
      phase = Phase.ACQUIRING
      connectingObserved = stickyState == AudioManager.SCO_AUDIO_STATE_CONNECTING
      if (stickyState == AudioManager.SCO_AUDIO_STATE_CONNECTED) {
        phase = Phase.CONNECTED
        AndroidLegacyScoEventV2.ACQUIRED
      } else {
        AndroidLegacyScoEventV2.NONE
      }
    }

  fun markRequestStarted() {
    synchronized(lock) { requestStarted = true }
  }

  fun observe(state: Int): AndroidLegacyScoEventV2 = synchronized(lock) {
    when (state) {
      AudioManager.SCO_AUDIO_STATE_CONNECTING -> {
        if (phase == Phase.ACQUIRING) connectingObserved = true
        AndroidLegacyScoEventV2.NONE
      }
      AudioManager.SCO_AUDIO_STATE_CONNECTED -> when (phase) {
        Phase.ACQUIRING -> {
          phase = Phase.CONNECTED
          AndroidLegacyScoEventV2.ACQUIRED
        }
        else -> AndroidLegacyScoEventV2.NONE
      }
      AudioManager.SCO_AUDIO_STATE_DISCONNECTED -> when (phase) {
        Phase.ACQUIRING -> {
          if (!connectingObserved) {
            AndroidLegacyScoEventV2.NONE
          } else {
            phase = Phase.FAILED
            AndroidLegacyScoEventV2.ACQUISITION_FAILED
          }
        }
        Phase.CONNECTED -> {
          phase = Phase.FAILED
          AndroidLegacyScoEventV2.TERMINAL_LOSS
        }
        Phase.RELEASING -> {
          phase = Phase.RELEASED
          AndroidLegacyScoEventV2.RELEASED
        }
        else -> AndroidLegacyScoEventV2.NONE
      }
      else -> AndroidLegacyScoEventV2.NONE
    }
  }

  /** Returns true only when a disconnect event is still expected. */
  fun beginRelease(): Boolean = synchronized(lock) {
    val waitForDisconnect = phase == Phase.CONNECTED ||
      (phase == Phase.ACQUIRING && connectingObserved)
    if (phase != Phase.RELEASED) phase = Phase.RELEASING
    waitForDisconnect
  }

  fun claimStopRequest(): Boolean = synchronized(lock) {
    if (!requestStarted || stopClaimed) return@synchronized false
    stopClaimed = true
    true
  }

  fun isConnected(): Boolean = synchronized(lock) { phase == Phase.CONNECTED }
}
