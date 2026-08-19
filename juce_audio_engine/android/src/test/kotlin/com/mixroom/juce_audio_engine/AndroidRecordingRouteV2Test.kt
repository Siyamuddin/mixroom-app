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
