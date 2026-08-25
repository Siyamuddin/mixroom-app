package com.mixroom.juce_audio_engine

import android.media.AudioDeviceInfo
import android.media.AudioManager

internal data class AndroidBluetoothDuplexFactsV2(
  val apiLevel: Int,
  val selectionMode: AndroidBluetoothRouteSelectionModeV2,
  val sourceOutput: AndroidRouteEndpointV2?,
  val selectedCommunicationOutput: AndroidRouteEndpointV2?,
  val actualInput: AndroidRouteEndpointV2?,
  val actualOutput: AndroidRouteEndpointV2?,
  val audioMode: Int,
  val communicationDeviceId: Int?,
  val legacyScoConnected: Boolean,
  val legacyScoRoutingEnabled: Boolean,
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
    if (facts.apiLevel < 29) return "recording_route_unsupported"
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
      output.fingerprint != selected.fingerprint
    ) {
      return "route_unstable"
    }
    when (facts.selectionMode) {
      AndroidBluetoothRouteSelectionModeV2.COMMUNICATION_DEVICE -> {
        if (facts.apiLevel < 31) return "recording_route_unsupported"
        if (facts.communicationDeviceId != selected.id) return "route_unstable"
      }
      AndroidBluetoothRouteSelectionModeV2.LEGACY_SCO -> {
        if (facts.apiLevel !in 29..30) return "recording_route_unsupported"
        if (!facts.legacyScoConnected || !facts.legacyScoRoutingEnabled) {
          return "actual_state_unavailable"
        }
      }
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
      (outputStream.streamEpoch ?: 0L) <= 0L ||
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
  COMMUNICATION_DEVICE_CHANGED,
  LEGACY_SCO_STATE_CHANGED,
  NATIVE_STREAM_DISCONNECTED,
  PLAYBACK_ACTIVITY,
  STARTUP,
}

internal data class AndroidRouteDeviceChangeV2(
  val id: Int,
  val type: Int,
  val isSource: Boolean,
  val isSink: Boolean,
)

internal enum class AndroidIntentRouteDecisionV2 {
  ORDINARY,
  INFORMATIONAL,
  TERMINAL,
}

internal object AndroidIntentRouteObserverV2 {
  fun isSelfGeneratedPlaybackActivity(
    lifecycleMutationActive: Boolean,
    cleanupClaimed: Boolean,
    signal: AndroidRouteSignalKindV2,
  ): Boolean =
    signal == AndroidRouteSignalKindV2.PLAYBACK_ACTIVITY &&
      (lifecycleMutationActive || cleanupClaimed)

  fun classify(
    explicitTransactionActive: Boolean,
    operationEndpointIds: Set<Int>?,
    signal: AndroidRouteSignalKindV2,
    removedDeviceIds: Set<Int>,
    expectedCommunicationDeviceType: Int? = null,
    addedDevices: List<AndroidRouteDeviceChangeV2> = emptyList(),
  ): AndroidIntentRouteDecisionV2 {
    if (!explicitTransactionActive) return AndroidIntentRouteDecisionV2.ORDINARY

    return when (signal) {
      AndroidRouteSignalKindV2.PLAYBACK_ACTIVITY ->
        AndroidIntentRouteDecisionV2.INFORMATIONAL
      AndroidRouteSignalKindV2.DEVICE_ADDED -> {
        val ownedAddition =
          addedDevices.isNotEmpty() &&
            addedDevices.all { device ->
              device.id in operationEndpointIds.orEmpty() ||
                (expectedCommunicationDeviceType != null &&
                  device.type == expectedCommunicationDeviceType &&
                  device.isSource &&
                  !device.isSink)
            }
        if (ownedAddition) AndroidIntentRouteDecisionV2.INFORMATIONAL
        else AndroidIntentRouteDecisionV2.TERMINAL
      }
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
      AndroidRouteSignalKindV2.COMMUNICATION_DEVICE_CHANGED ->
        AndroidIntentRouteDecisionV2.TERMINAL
      AndroidRouteSignalKindV2.LEGACY_SCO_STATE_CHANGED ->
        AndroidIntentRouteDecisionV2.TERMINAL
      AndroidRouteSignalKindV2.NATIVE_STREAM_DISCONNECTED ->
        AndroidIntentRouteDecisionV2.TERMINAL
      AndroidRouteSignalKindV2.STARTUP -> AndroidIntentRouteDecisionV2.TERMINAL
    }
  }
}

/**
 * Owns only notifications that can be delivered late for an already completed
 * recording-disconnect recovery. A new loss of the committed playback output
 * is deliberately excluded so it can start an ordinary route episode.
 */
internal object AndroidCommittedRecoveryOwnershipV2 {
  fun ownsLateSignal(
    signal: AndroidRouteSignalKindV2,
    removedDeviceIds: Set<Int>,
    completedOperationEndpointIds: Set<Int>,
  ): Boolean = when (signal) {
    AndroidRouteSignalKindV2.DEVICE_REMOVED ->
      removedDeviceIds.isNotEmpty() &&
        removedDeviceIds.all(completedOperationEndpointIds::contains)
    AndroidRouteSignalKindV2.COMMUNICATION_DEVICE_CHANGED -> true
    AndroidRouteSignalKindV2.LEGACY_SCO_STATE_CHANGED -> true
    AndroidRouteSignalKindV2.PLAYBACK_ACTIVITY -> true
    AndroidRouteSignalKindV2.DEVICE_ADDED,
    AndroidRouteSignalKindV2.NATIVE_STREAM_DISCONNECTED,
    AndroidRouteSignalKindV2.STARTUP -> false
  }
}
