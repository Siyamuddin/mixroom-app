package com.mixroom.juce_audio_engine

import android.content.Context

object JuceBridge {
    init {
        System.loadLibrary("juce_audio_engine")
    }

    @JvmStatic external fun setAndroidContextJNI(context: Context)
    @JvmStatic external fun setFlutterAssetRootJNI(rootPath: String)

    // Engine lifecycle
    @JvmStatic external fun initialiseEngineJNI()
    @JvmStatic external fun shutdownEngineJNI()

    // Playback control
    @JvmStatic external fun playJNI()
    @JvmStatic external fun pauseJNI()

    // Legacy track/clip API
    @JvmStatic external fun loadTrackJNI(trackIndex: Int, filePath: String)
    @JvmStatic external fun removeTrackJNI(trackIndex: Int)
    @JvmStatic external fun seekJNI(trackIndex: Int, positionSeconds: Double)
    @JvmStatic external fun getCurrentPositionJNI(trackIndex: Int): Double
    @JvmStatic external fun getTrackDurationJNI(trackIndex: Int): Double

    // New clip API
    @JvmStatic external fun beginProjectClipLoadTransactionJNI()
    @JvmStatic external fun loadClipJNI(
        clipIndex: Int,
        rowId: Int,
        filePath: String,
        startSec: Double,
        lengthSec: Double,
        inFileOffsetSec: Double,
    ): Boolean

    @JvmStatic external fun unloadClipJNI(clipIndex: Int)
    @JvmStatic external fun endProjectClipLoadTransactionJNI()
    @JvmStatic external fun setClipGainJNI(clipIndex: Int, gain: Float)
    @JvmStatic external fun muteClipJNI(clipIndex: Int, mute: Boolean)
    @JvmStatic external fun setClipPanJNI(clipIndex: Int, pan: Float)
    @JvmStatic external fun setClipPitchJNI(clipIndex: Int, semitones: Float)
    @JvmStatic external fun setClipReversedJNI(clipIndex: Int, reversed: Boolean)
    @JvmStatic external fun setClipStretchOptionsJNI(
        clipIndex: Int,
        tempoRatio: Double,
        preservePitch: Boolean,
    )

    @JvmStatic external fun moveClipToRowJNI(clipIndex: Int, newRowId: Int)
    @JvmStatic external fun setClipTimeJNI(
        clipIndex: Int,
        startSec: Double,
        lengthSec: Double,
        inFileOffsetSec: Double,
    )

    // Live MIDI clip playback
    @JvmStatic external fun supportsLiveMidiClipPlaybackJNI(): Boolean
    @JvmStatic external fun loadMidiClipJNI(
        clipIndex: Int,
        rowId: Int,
        instrumentId: String,
        instrumentName: String,
        notes: List<Map<String, Any>>,
        params: Map<String, Double>,
        sourceTempoBpm: Double,
        startSec: Double,
        lengthSec: Double,
        inFileOffsetSec: Double,
    ): Boolean

    @JvmStatic external fun updateMidiClipEventsJNI(
        clipIndex: Int,
        instrumentId: String,
        instrumentName: String,
        notes: List<Map<String, Any>>,
        params: Map<String, Double>,
        sourceTempoBpm: Double,
    ): Boolean

    @JvmStatic external fun setLiveMidiInputTargetClipJNI(clipIndex: Int): Boolean
    @JvmStatic external fun playPreviewMidiNoteJNI(
        clipIndex: Int,
        pitch: Int,
        velocity: Float,
        durationMs: Int,
    ): Boolean
    @JvmStatic external fun consumeLiveMidiInputEventsJNI(): ArrayList<HashMap<String, Any>>
    @JvmStatic external fun getConnectedMidiInputDevicesJNI(): ArrayList<HashMap<String, String>>

    // Transport
    @JvmStatic external fun setTransportSecondsJNI(timeSeconds: Double)
    @JvmStatic external fun getTransportSecondsJNI(): Double
    @JvmStatic external fun setAutomationTransportJNI(timeSeconds: Double)

    // Volume & bypass (legacy)
    @JvmStatic external fun setTrackVolumeJNI(trackIndex: Int, volume: Float)
    @JvmStatic external fun bypassTrackJNI(trackIndex: Int, shouldBypass: Boolean)
    @JvmStatic external fun bypassPluginJNI(trackIndex: Int, effectIndex: Int, shouldBypass: Boolean)

    // Plugin / FX chain (legacy clip/track-indexed)
    @JvmStatic external fun getTrackEffectsJNI(trackIndex: Int): List<String>
    @JvmStatic external fun insertEffectJNI(trackIndex: Int, pluginId: String)
    @JvmStatic external fun removeEffectJNI(trackIndex: Int, effectIndex: Int)
    @JvmStatic external fun reorderEffectsJNI(trackIndex: Int, fromIndex: Int, toIndex: Int)

    // Plugin parameters (legacy)
    @JvmStatic external fun setEffectJNI(trackIndex: Int, pluginId: Int, paramId: String, value: Any)
    @JvmStatic external fun getPluginParametersJNI(trackIndex: Int, effectIndex: Int): ArrayList<HashMap<String, Any>>
    @JvmStatic external fun getPluginBypassStateJNI(trackIndex: Int, effectIndex: Int): Boolean

    // Row management
    @JvmStatic external fun addRowJNI(name: String, iconId: Int): Int
    @JvmStatic external fun insertRowAboveJNI(referenceRowId: Int, name: String, iconId: Int): Int
    @JvmStatic external fun insertRowBelowJNI(referenceRowId: Int, name: String, iconId: Int): Int
    @JvmStatic external fun removeRowJNI(rowId: Int): Boolean
    @JvmStatic external fun moveRowOrderJNI(fromIndex: Int, toIndex: Int): Boolean
    @JvmStatic external fun renameRowJNI(rowId: Int, name: String): Boolean
    @JvmStatic external fun setRowIconJNI(rowId: Int, iconId: Int): Boolean
    @JvmStatic external fun getRowsJNI(): ArrayList<HashMap<String, Any>>

    // Row FX and controls
    @JvmStatic external fun insertTrackEffectJNI(row: Int, pluginPath: String): Boolean
    @JvmStatic external fun removeTrackEffectJNI(row: Int, effectIndex: Int)
    @JvmStatic external fun reorderTrackEffectsJNI(row: Int, fromIndex: Int, toIndex: Int)
    @JvmStatic external fun getTrackEffectsForRowJNI(row: Int): ArrayList<String>
    @JvmStatic external fun getTrackEffectIdsForRowJNI(row: Int): ArrayList<String>
    @JvmStatic external fun getTrackEffectInstanceIdsForRowJNI(row: Int): ArrayList<String>
    @JvmStatic external fun getTrackPluginParametersJNI(row: Int, effectIndex: Int): ArrayList<HashMap<String, Any>>
    @JvmStatic external fun setTrackEffectJNI(row: Int, effectIndex: Int, paramId: String, value: Any)
    @JvmStatic external fun bypassRowEffectJNI(row: Int, effectIndex: Int, bypass: Boolean)
    @JvmStatic external fun getRowEffectBypassStateJNI(row: Int, effectIndex: Int): Boolean
    @JvmStatic external fun setTrackAutomationPointsJNI(row: Int, points: List<Map<String, Any>>)
    @JvmStatic external fun setTrackEffectAutomationPointsJNI(
        row: Int,
        effectIndex: Int,
        paramId: String,
        minValue: Double,
        maxValue: Double,
        points: List<Map<String, Any>>,
    )

    @JvmStatic external fun clearTrackEffectAutomationForRowJNI(row: Int)
    @JvmStatic external fun setRowGainAutomationPointsJNI(row: Int, points: List<Map<String, Any>>)
    @JvmStatic external fun setRowGainJNI(row: Int, gain: Float)
    @JvmStatic external fun muteRowJNI(row: Int, mute: Boolean)
    @JvmStatic external fun isRowMutedJNI(row: Int): Boolean
    @JvmStatic external fun setRowPanAutomationPointsJNI(row: Int, points: List<Map<String, Any>>)
    @JvmStatic external fun setRowPanJNI(row: Int, pan: Float)

    // Master FX and controls
    @JvmStatic external fun insertMasterEffectJNI(pluginPath: String): Boolean
    @JvmStatic external fun removeMasterEffectJNI(effectIndex: Int)
    @JvmStatic external fun reorderMasterEffectsJNI(fromIndex: Int, toIndex: Int)
    @JvmStatic external fun getMasterEffectsJNI(): ArrayList<String>
    @JvmStatic external fun getMasterEffectIdsJNI(): ArrayList<String>
    @JvmStatic external fun getMasterPluginParametersJNI(effectIndex: Int): ArrayList<HashMap<String, Any>>
    @JvmStatic external fun setMasterEffectJNI(effectIndex: Int, paramId: String, value: Any)
    @JvmStatic external fun bypassMasterEffectJNI(effectIndex: Int, bypass: Boolean)
    @JvmStatic external fun getMasterEffectBypassStateJNI(effectIndex: Int): Boolean
    @JvmStatic external fun setMasterEffectAutomationPointsJNI(
        effectIndex: Int,
        paramId: String,
        minValue: Double,
        maxValue: Double,
        points: List<Map<String, Any>>,
    )

    @JvmStatic external fun clearMasterEffectAutomationJNI()
    @JvmStatic external fun setMasterGainAutomationPointsJNI(points: List<Map<String, Any>>)
    @JvmStatic external fun setMasterGainJNI(gain: Float)
    @JvmStatic external fun muteMasterJNI(mute: Boolean)
    @JvmStatic external fun setMasterPanAutomationPointsJNI(points: List<Map<String, Any>>)
    @JvmStatic external fun setMasterPanJNI(pan: Float)

    // Debug
    @JvmStatic external fun debugPrintGraphJNI(title: String)
    @JvmStatic external fun debugPrintGraphStructureJNI()

    // Metronome
    @JvmStatic external fun setMetronomeEnabledJNI(enabled: Boolean)
    @JvmStatic external fun setMetronomeVolumeJNI(volume: Float)
    @JvmStatic external fun setMetronomeBpmJNI(bpm: Double)
    @JvmStatic external fun setMetronomeTransportMsJNI(ms: Double)

    // Offline analysis
    @JvmStatic external fun decodeAudioMono16kJNI(path: String): DoubleArray
    @JvmStatic external fun decodeAudioMono16kForAnalysisJNI(path: String, maxOutputSamples: Int): DoubleArray
    @JvmStatic external fun analyzeAudioStereo16kJNI(path: String): HashMap<String, Double>
    @JvmStatic external fun analyzeAudioForPromptJNI(
        path: String,
        windowSamples: Int,
        windowCount: Int,
        trimStartMs: Double,
        trimEndMs: Double,
    ): HashMap<String, Any>

    // Input device / recording
    @JvmStatic external fun getInputDevicesJNI(): ArrayList<String>
    @JvmStatic external fun selectInputDeviceJNI(name: String): Boolean
    @JvmStatic external fun getNumInputChannelsJNI(): Int
    @JvmStatic external fun getActiveInputChannelCountJNI(): Int
    @JvmStatic external fun prepareRecordingInputsJNI(desiredInputChannels: Int, reason: String): Boolean
    @JvmStatic external fun refreshAudioRouteJNI(reason: String)
    @JvmStatic external fun hardResetPlaybackOnlyRouteJNI(reason: String): Boolean
    @JvmStatic external fun getRecordingPeakJNI(): Double
    @JvmStatic external fun getCurrentDeviceNameJNI(): String
    @JvmStatic external fun getCurrentOutputDeviceNameJNI(): String
    @JvmStatic external fun setLiveInputMonitoringEnabledJNI(enabled: Boolean)
    @JvmStatic external fun startRecordingJNI(path: String, channelStart: Int, channelCount: Int): Boolean
    @JvmStatic external fun stopRecordingJNI()
    @JvmStatic external fun stopRecordingWithoutPlaybackRestoreJNI()
    @JvmStatic external fun isRecordingJNI(): Boolean

    // Meters and analysis
    @JvmStatic external fun setMasterMeterEnabledJNI(enabled: Boolean)
    @JvmStatic external fun getMasterMeterValuesJNI(): DoubleArray
    @JvmStatic external fun getMasterClipLatchedJNI(): Boolean
    @JvmStatic external fun clearMasterClipLatchedJNI()
    @JvmStatic external fun setRowMetersEnabledJNI(enabled: Boolean)
    @JvmStatic external fun getRowMeterValuesJNI(row: Int): DoubleArray
    @JvmStatic external fun getAllMeterValuesJNI(): DoubleArray
    @JvmStatic external fun getTrackCompressorMeterJNI(trackIndex: Int, effectIndex: Int): DoubleArray
    @JvmStatic external fun getRowCompressorMeterJNI(row: Int, effectIndex: Int): DoubleArray
    @JvmStatic external fun getMasterCompressorMeterJNI(effectIndex: Int): DoubleArray
    @JvmStatic external fun getHostSampleRateJNI(): Double
    @JvmStatic external fun getRowEqWaveformJNI(row: Int, effectIndex: Int, sampleCount: Int): DoubleArray
    @JvmStatic external fun getMasterEqWaveformJNI(effectIndex: Int, sampleCount: Int): DoubleArray
    @JvmStatic external fun getRowStereoScopeJNI(row: Int, effectIndex: Int, pointCount: Int): DoubleArray
    @JvmStatic external fun getMasterStereoScopeJNI(effectIndex: Int, pointCount: Int): DoubleArray
    @JvmStatic external fun getRowShaperPreviewJNI(row: Int, effectIndex: Int, pointCount: Int): DoubleArray
    @JvmStatic external fun getMasterShaperPreviewJNI(effectIndex: Int, pointCount: Int): DoubleArray

    // Export
    @JvmStatic external fun exportMixJNI(
        outputPath: String,
        format: String,
        sampleRate: Int,
        wavBitDepth: Int,
        wavDithering: Boolean,
        mp3BitrateKbps: Int,
    ): String
    @JvmStatic external fun getExportProgressJNI(): Double

    @JvmStatic external fun exportTrackJNI(
        trackIndex: Int,
        outputPath: String,
        format: String,
        sampleRate: Int,
        wavBitDepth: Int,
        wavDithering: Boolean,
        mp3BitrateKbps: Int,
    ): String

    @JvmStatic external fun getAvailablePluginsJNI(): ArrayList<HashMap<String, String>>
    @JvmStatic external fun renderInstrumentClipJNI(
        outPath: String,
        instrumentId: String,
        instrumentName: String,
        bpm: Double,
        notes: List<Map<String, Any>>,
        params: Map<String, Double>,
    ): String

    // Video lane
    @JvmStatic external fun loadVideoAudioJNI(path: String)
    @JvmStatic external fun unloadVideoAudioJNI()
    @JvmStatic external fun setVideoAudioGainJNI(gain: Float)
    @JvmStatic external fun seekVideoAudioJNI(seconds: Double)
}
