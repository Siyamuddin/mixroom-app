package com.mixroom.juce_audio_engine

import android.media.AudioManager

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
