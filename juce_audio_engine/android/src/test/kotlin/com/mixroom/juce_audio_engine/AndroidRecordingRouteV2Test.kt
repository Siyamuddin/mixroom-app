package com.mixroom.juce_audio_engine

import android.media.AudioDeviceInfo
import android.media.AudioManager
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class AndroidRecordingRouteV2Test {
  private val input = AndroidRouteEndpointV2(
    11,
    AudioDeviceInfo.TYPE_BUILTIN_MIC,
    "built-in-input",
    1,
  )
  private val output = AndroidRouteEndpointV2(
    12,
    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
    "built-in-output",
    2,
  )

  private fun stream(deviceId: Int, channelCount: Int = 1) = AndroidOboeOutputFactsV2(
    available = true,
    running = true,
    routedDeviceId = deviceId,
    sampleRateHz = 48000,
    bufferFrames = 256,
    bufferCapacityFrames = 512,
    framesPerBurst = 192,
    audioBackend = "AAudio",
    performanceMode = "None",
    sharingMode = "Shared",
    channelCount = channelCount,
    streamEpoch = deviceId.toLong() + 100L,
  )

  private fun validFacts() = AndroidRecordingFactsV2(
    ownedByV2 = true,
    sourceOutput = output,
    actualInput = input,
    actualOutput = output,
    audioMode = AudioManager.MODE_NORMAL,
    bluetoothCommunicationDeviceSelected = false,
    bluetoothScoActive = false,
    deviceOpen = true,
    callbackAttached = true,
    activeInputChannels = 1,
    activeOutputChannels = 2,
    sampleRateHz = 48000.0,
    bufferFrames = 256,
    inputStream = stream(input.id),
    outputStream = stream(output.id, channelCount = 2),
  )

  @Test
  fun verifiedBuiltInDuplexIsReady() {
    assertEquals("ok", AndroidRecordingReadinessV2.validate(validFacts()))
  }

  @Test
  fun systemSelectedDuplexAcceptsCallbackProvenMultichannelCapacity() {
    val fourChannelInput = input.copy(channelCount = 4)
    val facts = validFacts().copy(
      actualInput = fourChannelInput,
      requiredInputChannels = 4,
      activeInputChannels = 4,
      inputStream = stream(fourChannelInput.id, channelCount = 4),
    )

    assertEquals("ok", AndroidSystemSelectedDuplexReadinessV2.validate(facts))
    assertEquals(
      "actual_state_unavailable",
      AndroidSystemSelectedDuplexReadinessV2.validate(
        facts.copy(activeInputChannels = 2),
      ),
    )
    assertEquals(
      "actual_state_unavailable",
      AndroidSystemSelectedDuplexReadinessV2.validate(
        facts.copy(inputStream = stream(fourChannelInput.id, channelCount = 2)),
      ),
    )
  }

  @Test
  fun systemSelectedDuplexAcceptsFactuallyVerifiedRouteKindsAndPairs() {
    val pairs = listOf(
      AudioDeviceInfo.TYPE_BUILTIN_MIC to AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
      AudioDeviceInfo.TYPE_USB_DEVICE to AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
      AudioDeviceInfo.TYPE_BUILTIN_MIC to AudioDeviceInfo.TYPE_USB_DEVICE,
      AudioDeviceInfo.TYPE_USB_HEADSET to AudioDeviceInfo.TYPE_DOCK,
      123456 to 123457,
    )
    for ((index, pair) in pairs.withIndex()) {
      val selectedInput = AndroidRouteEndpointV2(
        100 + index,
        pair.first,
        "input-$index",
        1,
      )
      val selectedOutput = AndroidRouteEndpointV2(
        200 + index,
        pair.second,
        "output-$index",
        2,
      )
      val facts = validFacts().copy(
        sourceOutput = selectedOutput,
        actualInput = selectedInput,
        actualOutput = selectedOutput,
        inputStream = stream(selectedInput.id),
        outputStream = stream(selectedOutput.id, channelCount = 2).copy(
          performanceMode = "LowLatency",
          sharingMode = "Exclusive",
        ),
      )
      assertEquals("ok", AndroidSystemSelectedDuplexReadinessV2.validate(facts))
    }
  }

  @Test
  fun monitoringAcceptsOnlyVerifiedKnownNonBluetoothPairs() {
    val pairs = listOf(
      AudioDeviceInfo.TYPE_BUILTIN_MIC to AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
      AudioDeviceInfo.TYPE_BUILTIN_MIC to AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
      AudioDeviceInfo.TYPE_USB_DEVICE to AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
      AudioDeviceInfo.TYPE_BUILTIN_MIC to AudioDeviceInfo.TYPE_USB_DEVICE,
    )
    for ((index, pair) in pairs.withIndex()) {
      val selectedInput = AndroidRouteEndpointV2(300 + index, pair.first, "monitor-in", 2)
      val selectedOutput = AndroidRouteEndpointV2(400 + index, pair.second, "monitor-out", 2)
      val facts = validFacts().copy(
        sourceOutput = selectedOutput,
        actualInput = selectedInput,
        actualOutput = selectedOutput,
        requiredInputChannels = 2,
        activeInputChannels = 2,
        inputStream = stream(selectedInput.id, channelCount = 2),
        outputStream = stream(selectedOutput.id, channelCount = 2),
      )
      assertEquals("ok", AndroidMonitoringReadinessV2.validate(facts))
    }
  }

  @Test
  fun monitoringRejectsBluetoothUnknownAndUnprovenRoutes() {
    val rejectedTypes = listOf(
      AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
      AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
      AudioDeviceInfo.TYPE_BLE_HEADSET,
      123456,
    )
    for ((index, type) in rejectedTypes.withIndex()) {
      val endpoint = AndroidRouteEndpointV2(500 + index, type, "rejected", 1)
      val facts = validFacts().copy(
        sourceOutput = endpoint,
        actualOutput = endpoint,
        outputStream = stream(endpoint.id, channelCount = 2),
      )
      assertEquals("monitoring_unavailable", AndroidMonitoringReadinessV2.validate(facts))
    }
    assertEquals(
      "actual_state_unavailable",
      AndroidMonitoringReadinessV2.validate(validFacts().copy(callbackAttached = false)),
    )
    assertEquals(
      "route_unstable",
      AndroidMonitoringReadinessV2.validate(
        validFacts().copy(actualOutput = output.copy(id = 999)),
      ),
    )
  }

  @Test
  fun systemSelectedDuplexRejectsUnprovenOrChangedFacts() {
    val facts = validFacts()
    assertEquals(
      "no_output",
      AndroidSystemSelectedDuplexReadinessV2.validate(
        facts.copy(sourceOutput = null),
      ),
    )
    assertEquals(
      "no_input",
      AndroidSystemSelectedDuplexReadinessV2.validate(
        facts.copy(actualInput = null),
      ),
    )
    assertEquals(
      "no_output",
      AndroidSystemSelectedDuplexReadinessV2.validate(
        facts.copy(actualOutput = null),
      ),
    )
    assertEquals(
      "route_unstable",
      AndroidSystemSelectedDuplexReadinessV2.validate(
        facts.copy(actualOutput = output.copy(id = 99)),
      ),
    )

    val invalid = listOf(
      facts.copy(ownedByV2 = false),
      facts.copy(audioMode = AudioManager.MODE_IN_COMMUNICATION),
      facts.copy(bluetoothCommunicationDeviceSelected = true),
      facts.copy(bluetoothScoActive = true),
      facts.copy(deviceOpen = false),
      facts.copy(callbackAttached = false),
      facts.copy(activeInputChannels = 0),
      facts.copy(activeOutputChannels = 0),
      facts.copy(sampleRateHz = 0.0),
      facts.copy(bufferFrames = 0),
      facts.copy(inputStream = stream(input.id).copy(available = false)),
      facts.copy(inputStream = stream(input.id).copy(routedDeviceId = 99)),
      facts.copy(inputStream = stream(input.id).copy(running = false)),
      facts.copy(inputStream = stream(input.id).copy(channelCount = 2)),
      facts.copy(inputStream = stream(input.id).copy(bufferFrames = 0)),
      facts.copy(inputStream = stream(input.id).copy(sampleRateHz = 44100)),
      facts.copy(outputStream = stream(output.id, 2).copy(available = false)),
      facts.copy(outputStream = stream(output.id, 2).copy(running = false)),
      facts.copy(outputStream = stream(output.id, 2).copy(routedDeviceId = 99)),
      facts.copy(outputStream = stream(output.id, 1)),
      facts.copy(outputStream = stream(output.id, 2).copy(bufferFrames = 0)),
      facts.copy(outputStream = stream(output.id, 2).copy(streamEpoch = null)),
    )
    for (candidate in invalid) {
      val expected = if (!candidate.ownedByV2) {
        "implementation_conflict"
      } else {
        "actual_state_unavailable"
      }
      assertEquals(expected, AndroidSystemSelectedDuplexReadinessV2.validate(candidate))
    }
  }

  @Test
  fun nonBuiltInAndChangedRoutesAreRejected() {
    val bluetooth = AndroidRouteEndpointV2(
      13,
      AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
      "bluetooth",
      1,
    )
    assertEquals(
      "recording_route_unsupported",
      AndroidRecordingReadinessV2.validate(validFacts().copy(actualInput = bluetooth)),
    )
    assertEquals(
      "route_unstable",
      AndroidRecordingReadinessV2.validate(
        validFacts().copy(
          actualOutput = output.copy(id = 14),
          outputStream = stream(14, channelCount = 2),
        ),
      ),
    )
  }

  @Test
  fun missingEndpointsHaveStableDiagnosticCodes() {
    assertEquals(
      "no_input",
      AndroidRecordingReadinessV2.validate(validFacts().copy(actualInput = null)),
    )
    assertEquals(
      "no_output",
      AndroidRecordingReadinessV2.validate(validFacts().copy(actualOutput = null)),
    )
  }

  @Test
  fun sessionDeviceAndCallbackFactsMustRemainVerified() {
    val invalid = listOf(
      validFacts().copy(ownedByV2 = false),
      validFacts().copy(audioMode = AudioManager.MODE_IN_COMMUNICATION),
      validFacts().copy(bluetoothCommunicationDeviceSelected = true),
      validFacts().copy(bluetoothScoActive = true),
      validFacts().copy(deviceOpen = false),
      validFacts().copy(callbackAttached = false),
      validFacts().copy(activeInputChannels = 0),
      validFacts().copy(activeOutputChannels = 0),
      validFacts().copy(sampleRateHz = 0.0),
      validFacts().copy(bufferFrames = 0),
      validFacts().copy(inputStream = stream(input.id).copy(running = false)),
      validFacts().copy(
        outputStream = stream(output.id, channelCount = 2).copy(routedDeviceId = 99),
      ),
      validFacts().copy(inputStream = stream(input.id).copy(sampleRateHz = 44100)),
    )
    for (facts in invalid) {
      val result = AndroidRecordingReadinessV2.validate(facts)
      assertEquals(
        if (!facts.ownedByV2) "implementation_conflict" else "actual_state_unavailable",
        result,
      )
    }
  }

  @Test
  fun playbackTransitionOwnsOnlyItsExactAvailableTarget() {
    val expected = AndroidMediaRouteResolutionV2(output, "ok")

    assertEquals(
      true,
      AndroidPlaybackTransitionOwnershipV2.ownsNotification(
        expected = expected,
        current = AndroidMediaRouteResolutionV2(output, "ok"),
        availableOutputIds = setOf(output.id),
        removedDeviceIds = emptySet(),
      ),
    )
    assertEquals(
      false,
      AndroidPlaybackTransitionOwnershipV2.ownsNotification(
        expected = expected,
        current = AndroidMediaRouteResolutionV2(output.copy(id = 99), "ok"),
        availableOutputIds = setOf(output.id, 99),
        removedDeviceIds = emptySet(),
      ),
    )
    assertEquals(
      false,
      AndroidPlaybackTransitionOwnershipV2.ownsNotification(
        expected = expected,
        current = AndroidMediaRouteResolutionV2(output, "ok"),
        availableOutputIds = emptySet(),
        removedDeviceIds = setOf(output.id),
      ),
    )
  }

  @Test
  fun explicitBluetoothTransactionIgnoresPlaybackActivityAndOwnedDuplexAdditions() {
    assertEquals(
      AndroidIntentRouteDecisionV2.INFORMATIONAL,
      AndroidIntentRouteObserverV2.classify(
        explicitTransactionActive = true,
        operationEndpointIds = setOf(21, 22),
        signal = AndroidRouteSignalKindV2.PLAYBACK_ACTIVITY,
        removedDeviceIds = emptySet(),
      ),
    )
    assertEquals(
      AndroidIntentRouteDecisionV2.INFORMATIONAL,
      AndroidIntentRouteObserverV2.classify(
        explicitTransactionActive = true,
        operationEndpointIds = setOf(21, 22),
        signal = AndroidRouteSignalKindV2.DEVICE_ADDED,
        removedDeviceIds = emptySet(),
        expectedCommunicationDeviceType = AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        addedDevices = listOf(
          AndroidRouteDeviceChangeV2(
            22,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            isSource = false,
            isSink = true,
          ),
          AndroidRouteDeviceChangeV2(
            23,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            isSource = true,
            isSink = false,
          ),
        ),
      ),
    )
  }

  @Test
  fun unexpectedLegacyScoLossIsTerminalOnlyInsideTheExplicitTransaction() {
    assertEquals(
      AndroidIntentRouteDecisionV2.TERMINAL,
      AndroidIntentRouteObserverV2.classify(
        explicitTransactionActive = true,
        operationEndpointIds = setOf(21, 22),
        signal = AndroidRouteSignalKindV2.LEGACY_SCO_STATE_CHANGED,
        removedDeviceIds = emptySet(),
      ),
    )
    assertEquals(
      AndroidIntentRouteDecisionV2.ORDINARY,
      AndroidIntentRouteObserverV2.classify(
        explicitTransactionActive = false,
        operationEndpointIds = null,
        signal = AndroidRouteSignalKindV2.LEGACY_SCO_STATE_CHANGED,
        removedDeviceIds = emptySet(),
      ),
    )
  }

  @Test
  fun explicitBluetoothTransactionDoesNotHideUnrelatedDeviceAddition() {
    assertEquals(
      AndroidIntentRouteDecisionV2.TERMINAL,
      AndroidIntentRouteObserverV2.classify(
        explicitTransactionActive = true,
        operationEndpointIds = setOf(21, 22),
        signal = AndroidRouteSignalKindV2.DEVICE_ADDED,
        removedDeviceIds = emptySet(),
        expectedCommunicationDeviceType = AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        addedDevices = listOf(
          AndroidRouteDeviceChangeV2(
            99,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            isSource = false,
            isSink = true,
          ),
        ),
      ),
    )
  }

  @Test
  fun explicitBluetoothTransactionDoesNotHideUnknownScoSinkAddition() {
    assertEquals(
      AndroidIntentRouteDecisionV2.TERMINAL,
      AndroidIntentRouteObserverV2.classify(
        explicitTransactionActive = true,
        operationEndpointIds = setOf(21, 22),
        signal = AndroidRouteSignalKindV2.DEVICE_ADDED,
        removedDeviceIds = emptySet(),
        expectedCommunicationDeviceType = AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        addedDevices = listOf(
          AndroidRouteDeviceChangeV2(
            23,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            isSource = false,
            isSink = true,
          ),
        ),
      ),
    )
  }

  @Test
  fun processTeardownGateFailsStartupClosedUntilNativeShutdownCompletes() {
    val gate = AndroidLifecycleTeardownGateV2()

    assertEquals(true, gate.isClear())
    assertEquals(true, gate.awaitClear(1L))

    val completion = gate.publish()
    assertEquals(false, gate.isClear())
    assertEquals(false, gate.awaitClear(1L))

    gate.complete(completion)
    assertEquals(true, gate.isClear())
    assertEquals(true, gate.awaitClear(1L))
  }

  @Test
  fun onlyAnAcquiredEngineOwnerMayShutDownNativeState() {
    assertEquals(false, EngineOwnership.NONE.ownsNativeEngine)
    assertEquals(true, EngineOwnership.LEGACY.ownsNativeEngine)
    assertEquals(true, EngineOwnership.V2_SESSION.ownsNativeEngine)
  }

  @Test
  fun processTeardownGateRetainsEveryOverlappingOwner() {
    val gate = AndroidLifecycleTeardownGateV2()
    val first = gate.publish()
    val second = gate.publish()

    gate.complete(second)
    gate.complete(second)
    assertEquals(false, gate.isClear())
    assertEquals(false, gate.awaitClear(1L))

    gate.complete(first)
    assertEquals(true, gate.isClear())
    assertEquals(true, gate.awaitClear(1L))
  }

  @Test
  fun cleanupPlanStrengthensToSafeTerminalDispositionBeforeClaim() {
    val plan = AndroidRecordingCleanupPlanV2()

    assertEquals(
      AndroidRecordingCleanupDispositionV2.RESTORE_EXACT,
      plan.select(AndroidRecordingCleanupDispositionV2.RESTORE_EXACT),
    )
    assertEquals(
      AndroidRecordingCleanupDispositionV2.CLOSE_ONLY,
      plan.select(AndroidRecordingCleanupDispositionV2.CLOSE_ONLY),
    )
    assertEquals(
      AndroidRecordingCleanupDispositionV2.CLOSE_ONLY,
      plan.select(AndroidRecordingCleanupDispositionV2.RESTORE_EXACT),
    )
    assertEquals(
      AndroidRecordingCleanupDispositionV2.CLOSE_ONLY,
      plan.snapshotForCleanupWinner(),
    )
  }

  @Test
  fun cleanupWinnerDefaultsToCloseWhenNoCallerSelectedAPlan() {
    assertEquals(
      AndroidRecordingCleanupDispositionV2.CLOSE_ONLY,
      AndroidRecordingCleanupPlanV2().snapshotForCleanupWinner(),
    )
  }

  @Test
  fun explicitLifecycleMutationOwnsOnlyItsPlaybackActivityNoise() {
    assertEquals(
      true,
      AndroidIntentRouteObserverV2.isSelfGeneratedPlaybackActivity(
        lifecycleMutationActive = true,
        cleanupClaimed = false,
        signal = AndroidRouteSignalKindV2.PLAYBACK_ACTIVITY,
      ),
    )
    assertEquals(
      true,
      AndroidIntentRouteObserverV2.isSelfGeneratedPlaybackActivity(
        lifecycleMutationActive = false,
        cleanupClaimed = true,
        signal = AndroidRouteSignalKindV2.PLAYBACK_ACTIVITY,
      ),
    )
    assertEquals(
      false,
      AndroidIntentRouteObserverV2.isSelfGeneratedPlaybackActivity(
        lifecycleMutationActive = true,
        cleanupClaimed = true,
        signal = AndroidRouteSignalKindV2.DEVICE_ADDED,
      ),
    )
    assertEquals(
      false,
      AndroidIntentRouteObserverV2.isSelfGeneratedPlaybackActivity(
        lifecycleMutationActive = true,
        cleanupClaimed = true,
        signal = AndroidRouteSignalKindV2.DEVICE_REMOVED,
      ),
    )
  }

  @Test
  fun explicitBluetoothTransactionOnlyTerminatesForOwnedEndpointRemoval() {
    assertEquals(
      AndroidIntentRouteDecisionV2.TERMINAL,
      AndroidIntentRouteObserverV2.classify(
        explicitTransactionActive = true,
        operationEndpointIds = setOf(21, 22),
        signal = AndroidRouteSignalKindV2.DEVICE_REMOVED,
        removedDeviceIds = setOf(21),
      ),
    )
    assertEquals(
      AndroidIntentRouteDecisionV2.TERMINAL,
      AndroidIntentRouteObserverV2.classify(
        explicitTransactionActive = true,
        operationEndpointIds = setOf(21, 22),
        signal = AndroidRouteSignalKindV2.DEVICE_REMOVED,
        removedDeviceIds = setOf(22),
      ),
    )
    assertEquals(
      AndroidIntentRouteDecisionV2.INFORMATIONAL,
      AndroidIntentRouteObserverV2.classify(
        explicitTransactionActive = true,
        operationEndpointIds = setOf(21, 22),
        signal = AndroidRouteSignalKindV2.DEVICE_REMOVED,
        removedDeviceIds = setOf(99),
      ),
    )
  }

  @Test
  fun verifiedCommunicationDeviceChangeIsTerminalForBluetoothTransaction() {
    assertEquals(
      AndroidIntentRouteDecisionV2.TERMINAL,
      AndroidIntentRouteObserverV2.classify(
        explicitTransactionActive = true,
        operationEndpointIds = setOf(17, 19, 20),
        signal = AndroidRouteSignalKindV2.COMMUNICATION_DEVICE_CHANGED,
        removedDeviceIds = emptySet(),
      ),
    )
    assertEquals(
      AndroidIntentRouteDecisionV2.ORDINARY,
      AndroidIntentRouteObserverV2.classify(
        explicitTransactionActive = false,
        operationEndpointIds = null,
        signal = AndroidRouteSignalKindV2.COMMUNICATION_DEVICE_CHANGED,
        removedDeviceIds = emptySet(),
      ),
    )
  }

  @Test
  fun nativeDuplexStreamLossIsTerminalOnlyInsideTheExplicitTransaction() {
    assertEquals(
      AndroidIntentRouteDecisionV2.TERMINAL,
      AndroidIntentRouteObserverV2.classify(
        explicitTransactionActive = true,
        operationEndpointIds = setOf(17, 19, 20),
        signal = AndroidRouteSignalKindV2.NATIVE_STREAM_DISCONNECTED,
        removedDeviceIds = emptySet(),
      ),
    )
    assertEquals(
      AndroidIntentRouteDecisionV2.ORDINARY,
      AndroidIntentRouteObserverV2.classify(
        explicitTransactionActive = false,
        operationEndpointIds = null,
        signal = AndroidRouteSignalKindV2.NATIVE_STREAM_DISCONNECTED,
        removedDeviceIds = emptySet(),
      ),
    )
  }

  @Test
  fun routeSignalsRemainOrdinaryOutsideTheExplicitTransaction() {
    assertEquals(
      AndroidIntentRouteDecisionV2.ORDINARY,
      AndroidIntentRouteObserverV2.classify(
        explicitTransactionActive = false,
        operationEndpointIds = null,
        signal = AndroidRouteSignalKindV2.PLAYBACK_ACTIVITY,
        removedDeviceIds = emptySet(),
      ),
    )
    assertEquals(
      AndroidIntentRouteDecisionV2.TERMINAL,
      AndroidIntentRouteObserverV2.classify(
        explicitTransactionActive = true,
        operationEndpointIds = null,
        signal = AndroidRouteSignalKindV2.DEVICE_REMOVED,
        removedDeviceIds = setOf(21),
      ),
    )
  }

  @Test
  fun completedRecoveryOwnsOnlyLateSignalsFromItsOldEndpoints() {
    assertTrue(
      AndroidCommittedRecoveryOwnershipV2.ownsLateSignal(
        signal = AndroidRouteSignalKindV2.DEVICE_REMOVED,
        removedDeviceIds = setOf(21, 22),
        completedOperationEndpointIds = setOf(21, 22, 23),
      ),
    )
    assertTrue(
      AndroidCommittedRecoveryOwnershipV2.ownsLateSignal(
        signal = AndroidRouteSignalKindV2.COMMUNICATION_DEVICE_CHANGED,
        removedDeviceIds = emptySet(),
        completedOperationEndpointIds = setOf(21, 22, 23),
      ),
    )
    assertFalse(
      AndroidCommittedRecoveryOwnershipV2.ownsLateSignal(
        signal = AndroidRouteSignalKindV2.DEVICE_REMOVED,
        removedDeviceIds = setOf(99),
        completedOperationEndpointIds = setOf(21, 22, 23),
      ),
    )
    assertFalse(
      AndroidCommittedRecoveryOwnershipV2.ownsLateSignal(
        signal = AndroidRouteSignalKindV2.NATIVE_STREAM_DISCONNECTED,
        removedDeviceIds = emptySet(),
        completedOperationEndpointIds = setOf(21, 22, 23),
      ),
    )
  }
}
