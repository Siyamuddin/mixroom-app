package com.mixroom.juce_audio_engine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class AndroidRecordingChannelPolicyV2Test {
  @Test fun onlySupportedMonoSelectionIsAccepted() {
    assertTrue(AndroidRecordingChannelPolicyV2.accepts(0, 1))
    listOf(0 to 2, 1 to 1, -1 to 1, 0 to 0, 255 to 1, Int.MAX_VALUE to 1).forEach {
      assertFalse(AndroidRecordingChannelPolicyV2.accepts(it.first, it.second))
    }
  }
  @Test fun exposedConfigurationMatchesEnforcedRange() {
    val config = AndroidRecordingChannelPolicyV2.toMap()
    assertEquals(0, config["channelStart"])
    assertEquals(1, config["channelCount"])
    assertTrue(AndroidRecordingChannelPolicyV2.accepts(config.getValue("channelStart"), config.getValue("channelCount")))
  }
}
