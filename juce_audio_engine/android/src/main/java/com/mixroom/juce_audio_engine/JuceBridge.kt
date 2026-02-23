package com.mixroom.juce_audio_engine

import android.content.Context

object JuceBridge {
    init {
        System.loadLibrary("juce_audio_engine")
    }

    @JvmStatic external fun setAndroidContextJNI(context: Context)

    // Engine lifecycle
    @JvmStatic external fun initialiseEngineJNI()
    @JvmStatic external fun shutdownEngineJNI()

    // Playback control
    @JvmStatic external fun playJNI()
    @JvmStatic external fun pauseJNI()

    // Track control
    @JvmStatic external fun loadTrackJNI(trackIndex: Int, filePath: String)
    @JvmStatic external fun removeTrackJNI(trackIndex: Int)
    @JvmStatic external fun seekJNI(trackIndex: Int, positionSeconds: Double)
    @JvmStatic external fun getCurrentPositionJNI(trackIndex: Int): Double
    @JvmStatic external fun getTrackDurationJNI(trackIndex: Int): Double
    @JvmStatic external fun getHostSampleRateJNI(): Double

    // Volume & bypass
    @JvmStatic external fun setTrackVolumeJNI(trackIndex: Int, volume: Float)
    @JvmStatic external fun bypassTrackJNI(trackIndex: Int, shouldBypass: Boolean)
    @JvmStatic external fun bypassPluginJNI(trackIndex: Int, effectIndex: Int, shouldBypass: Boolean)

    // Plugin / FX chain
    @JvmStatic external fun getTrackEffectsJNI(trackIndex: Int): List<String>
    @JvmStatic external fun insertEffectJNI(trackIndex: Int, pluginId: String)
    @JvmStatic external fun removeEffectJNI(trackIndex: Int, effectIndex: Int)
    @JvmStatic external fun reorderEffectsJNI(trackIndex: Int, fromIndex: Int, toIndex: Int)

    // Plugin parameters
    @JvmStatic external fun setEffectJNI(trackIndex: Int, pluginId: Int, paramId: String, value: Any)
    @JvmStatic external fun getPluginParametersJNI(trackIndex: Int, effectIndex: Int): ArrayList<HashMap<String, Any>>
    @JvmStatic external fun getPluginBypassStateJNI(trackIndex: Int, effectIndex: Int): Boolean

    // Export
    @JvmStatic external fun exportMixJNI(
        outputPath: String,
        format: String,
        sampleRate: Int,
        wavBitDepth: Int,
        wavDithering: Boolean,
        mp3BitrateKbps: Int
    ): String

    @JvmStatic external fun exportTrackJNI(
        trackIndex: Int,
        outputPath: String,
        format: String,
        sampleRate: Int,
        wavBitDepth: Int,
        wavDithering: Boolean,
        mp3BitrateKbps: Int
    ): String

    // Plugin discovery
    @JvmStatic external fun getAvailablePluginsJNI(): ArrayList<HashMap<String, String>>

    @JvmStatic external fun loadVideoAudioJNI(path: String)
    @JvmStatic external fun unloadVideoAudioJNI()
    @JvmStatic external fun setVideoAudioGainJNI(gain: Float)
    @JvmStatic external fun seekVideoAudioJNI(seconds: Double)
}
