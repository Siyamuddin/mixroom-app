package com.mixroom.juce_audio_engine

import android.media.AudioDeviceInfo
import android.media.AudioManager
import kotlin.test.Test
import kotlin.test.assertEquals

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
}
