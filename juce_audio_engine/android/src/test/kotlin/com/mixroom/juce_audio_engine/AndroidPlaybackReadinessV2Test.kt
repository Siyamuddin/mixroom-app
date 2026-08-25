package com.mixroom.juce_audio_engine

import android.media.AudioManager
import kotlin.test.Test
import kotlin.test.assertEquals

internal class AndroidPlaybackReadinessV2Test {
  private fun validFacts() =
    AndroidPlaybackFactsV2(
      ownedByV2 = true,
      audioMode = AudioManager.MODE_NORMAL,
      bluetoothCommunicationDeviceSelected = false,
      bluetoothScoActive = false,
      deviceOpen = true,
      callbackAttached = true,
      activeInputChannels = 0,
      activeOutputChannels = 2,
      sampleRateHz = 48000.0,
      bufferFrames = 512,
    )

  @Test
  fun validOutputOnlyFactsAreReady() {
    assertEquals("ok", AndroidPlaybackReadinessV2.validate(validFacts()))
  }

  @Test
  fun ownershipConflictIsRejected() {
    assertEquals(
      "implementation_conflict",
      AndroidPlaybackReadinessV2.validate(validFacts().copy(ownedByV2 = false)),
    )
  }

  @Test
  fun missingOutputIsRejected() {
    assertEquals(
      "no_output",
      AndroidPlaybackReadinessV2.validate(validFacts().copy(activeOutputChannels = 0)),
    )
  }

  @Test
  fun activeInputIsRejected() {
    assertEquals(
      "input_open",
      AndroidPlaybackReadinessV2.validate(validFacts().copy(activeInputChannels = 1)),
    )
  }

  @Test
  fun invalidSessionOrAcceptedDeviceFactsAreUnavailable() {
    val invalidFacts = listOf(
      validFacts().copy(audioMode = AudioManager.MODE_IN_COMMUNICATION),
      validFacts().copy(bluetoothCommunicationDeviceSelected = true),
      validFacts().copy(bluetoothScoActive = true),
      validFacts().copy(callbackAttached = false),
      validFacts().copy(sampleRateHz = 0.0),
      validFacts().copy(bufferFrames = 0),
    )
    for (facts in invalidFacts) {
      assertEquals(
        "actual_state_unavailable",
        AndroidPlaybackReadinessV2.validate(facts),
      )
    }
  }
}
