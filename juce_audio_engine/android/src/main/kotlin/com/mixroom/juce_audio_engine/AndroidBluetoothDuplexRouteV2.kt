package com.mixroom.juce_audio_engine

import android.media.AudioDeviceInfo
import android.media.AudioManager

internal data class AndroidBluetoothDuplexFactsV2(
  val apiLevel: Int,
  val sourceOutput: AndroidRouteEndpointV2?,
  val selectedCommunicationOutput: AndroidRouteEndpointV2?,
  val actualInput: AndroidRouteEndpointV2?,
  val actualOutput: AndroidRouteEndpointV2?,
  val audioMode: Int,
  val communicationDeviceId: Int?,
  val deviceOpen: Boolean,
  val callbackAttached: Boolean,
  val activeInputChannels: Int,
  val activeOutputChannels: Int,
  val sampleRateHz: Double,
  val bufferFrames: Int,
  val inputStream: AndroidOboeOutputFactsV2,
  val outputStream: AndroidOboeOutputFactsV2,
)

internal object AndroidBluetoothDuplexReadinessV2 {
  fun validate(facts: AndroidBluetoothDuplexFactsV2): String {
    if (facts.apiLevel < 31) return "recording_route_unsupported"
    val source = facts.sourceOutput ?: return "no_output"
    if (source.kind != AndroidRouteKindV2.BLUETOOTH_MEDIA) {
      return "recording_route_unsupported"
    }
    val selected = facts.selectedCommunicationOutput ?: return "no_output"
    if (
      selected.type != AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
      selected.kind != AndroidRouteKindV2.BLUETOOTH_DUPLEX
    ) {
      return "recording_route_unsupported"
    }
    val input = facts.actualInput ?: return "no_input"
    val output = facts.actualOutput ?: return "no_output"
    if (
      input.kind != AndroidRouteKindV2.BLUETOOTH_DUPLEX ||
      output.kind != AndroidRouteKindV2.BLUETOOTH_DUPLEX ||
      output.fingerprint != selected.fingerprint ||
      facts.communicationDeviceId != selected.id
    ) {
      return "route_unstable"
    }
    if (
      facts.audioMode != AudioManager.MODE_IN_COMMUNICATION ||
      !facts.deviceOpen ||
      !facts.callbackAttached ||
      facts.activeInputChannels != 1 ||
      facts.activeOutputChannels != 1 ||
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
      inputStream.performanceMode != "None" ||
      inputStream.sharingMode != "Shared" ||
      !outputStream.available ||
      !outputStream.running ||
      outputStream.routedDeviceId != output.id ||
      outputStream.channelCount != 1 ||
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

internal enum class AndroidRouteSignalKindV2 {
  DEVICE_ADDED,
  DEVICE_REMOVED,
  PLAYBACK_ACTIVITY,
  STARTUP,
}

internal enum class AndroidIntentRouteDecisionV2 {
  ORDINARY,
  INFORMATIONAL,
  TERMINAL,
}

internal object AndroidIntentRouteObserverV2 {
  fun classify(
    explicitTransactionActive: Boolean,
    operationEndpointIds: Set<Int>?,
    signal: AndroidRouteSignalKindV2,
    removedDeviceIds: Set<Int>,
  ): AndroidIntentRouteDecisionV2 {
    if (!explicitTransactionActive) return AndroidIntentRouteDecisionV2.ORDINARY

    return when (signal) {
      AndroidRouteSignalKindV2.PLAYBACK_ACTIVITY,
      AndroidRouteSignalKindV2.DEVICE_ADDED ->
        AndroidIntentRouteDecisionV2.INFORMATIONAL
      AndroidRouteSignalKindV2.DEVICE_REMOVED -> {
        if (
          operationEndpointIds == null ||
          removedDeviceIds.any(operationEndpointIds::contains)
        ) {
          AndroidIntentRouteDecisionV2.TERMINAL
        } else {
          AndroidIntentRouteDecisionV2.INFORMATIONAL
        }
      }
      AndroidRouteSignalKindV2.STARTUP -> AndroidIntentRouteDecisionV2.TERMINAL
    }
  }
}
