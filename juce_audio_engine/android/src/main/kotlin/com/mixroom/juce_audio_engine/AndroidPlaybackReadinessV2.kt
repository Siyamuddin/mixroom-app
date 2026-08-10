package com.mixroom.juce_audio_engine

import android.media.AudioManager

internal data class AndroidPlaybackFactsV2(
  val ownedByV2: Boolean,
  val audioMode: Int,
  val bluetoothCommunicationDeviceSelected: Boolean,
  val bluetoothScoActive: Boolean,
  val deviceOpen: Boolean,
  val callbackAttached: Boolean,
  val activeInputChannels: Int,
  val activeOutputChannels: Int,
  val sampleRateHz: Double,
  val bufferFrames: Int,
)

internal object AndroidPlaybackReadinessV2 {
  fun validate(facts: AndroidPlaybackFactsV2): String {
    if (!facts.ownedByV2) return "implementation_conflict"
    if (
      facts.audioMode != AudioManager.MODE_NORMAL ||
      facts.bluetoothCommunicationDeviceSelected ||
      facts.bluetoothScoActive
    ) {
      return "actual_state_unavailable"
    }
    if (!facts.deviceOpen || facts.activeOutputChannels <= 0) return "no_output"
    if (facts.activeInputChannels > 0) return "input_open"
    if (
      !facts.callbackAttached ||
      facts.sampleRateHz <= 0.0 ||
      facts.bufferFrames <= 0
    ) {
      return "actual_state_unavailable"
    }
    return "ok"
  }
}
