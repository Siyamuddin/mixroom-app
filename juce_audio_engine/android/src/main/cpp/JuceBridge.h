#pragma once

#include <jni.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // Context/bootstrap
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setAndroidContextJNI(JNIEnv *env, jclass, jobject context);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setFlutterAssetRootJNI(JNIEnv *env, jclass, jstring rootPath);

    // Engine lifecycle
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_initialiseEngineJNI(JNIEnv *env, jclass);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_shutdownEngineJNI(JNIEnv *, jclass);

    // Legacy track API
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_loadTrackJNI(JNIEnv *, jclass, jint, jstring);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_playJNI(JNIEnv *, jclass);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_pauseJNI(JNIEnv *, jclass);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_removeTrackJNI(JNIEnv *, jclass, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_seekJNI(JNIEnv *, jclass, jint, jdouble);
    JNIEXPORT jdouble JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getCurrentPositionJNI(JNIEnv *, jclass, jint);
    JNIEXPORT jdouble JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackDurationJNI(JNIEnv *, jclass, jint);

    // New clip API
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_beginProjectClipLoadTransactionJNI(JNIEnv *, jclass);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_endProjectClipLoadTransactionJNI(JNIEnv *, jclass);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_loadClipJNI(JNIEnv *, jclass, jint, jint, jstring, jdouble, jdouble, jdouble);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_unloadClipJNI(JNIEnv *, jclass, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipGainJNI(JNIEnv *, jclass, jint, jfloat);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipExtraGainLinearJNI(JNIEnv *, jclass, jint, jfloat);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_muteClipJNI(JNIEnv *, jclass, jint, jboolean);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipPanJNI(JNIEnv *, jclass, jint, jfloat);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipFadesJNI(JNIEnv *, jclass, jint, jdouble, jdouble, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipPitchJNI(JNIEnv *, jclass, jint, jfloat);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipReversedJNI(JNIEnv *, jclass, jint, jboolean);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipStretchOptionsJNI(JNIEnv *, jclass, jint, jdouble, jboolean);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_moveClipToRowJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipTimeJNI(JNIEnv *, jclass, jint, jdouble, jdouble, jdouble);

    // Live MIDI clip playback
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_supportsLiveMidiClipPlaybackJNI(JNIEnv *, jclass);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_loadMidiClipJNI(JNIEnv *, jclass, jint, jint, jstring, jstring, jobject, jobject, jdouble, jdouble, jdouble, jdouble);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_updateMidiClipEventsJNI(JNIEnv *, jclass, jint, jstring, jstring, jobject, jobject, jdouble);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setLiveMidiInputTargetClipJNI(JNIEnv *, jclass, jint);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_consumeLiveMidiInputEventsJNI(JNIEnv *, jclass);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getConnectedMidiInputDevicesJNI(JNIEnv *, jclass);

    // Transport
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setTransportSecondsJNI(JNIEnv *, jclass, jdouble);
    JNIEXPORT jdouble JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTransportSecondsJNI(JNIEnv *, jclass);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setAutomationTransportJNI(JNIEnv *, jclass, jdouble);

    // Legacy FX API (clip/track-indexed)
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackEffectsJNI(JNIEnv *, jclass, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_insertEffectJNI(JNIEnv *, jclass, jint, jstring);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_removeEffectJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_reorderEffectsJNI(JNIEnv *, jclass, jint, jint, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setEffectJNI(JNIEnv *, jclass, jint, jint, jstring, jobject);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getPluginParametersJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_bypassPluginJNI(JNIEnv *, jclass, jint, jint, jboolean);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getPluginBypassStateJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setTrackVolumeJNI(JNIEnv *, jclass, jint, jfloat);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_bypassTrackJNI(JNIEnv *, jclass, jint, jboolean);

    // Row management
    JNIEXPORT jint JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_addRowJNI(JNIEnv *, jclass, jstring, jint);
    JNIEXPORT jint JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_insertRowAboveJNI(JNIEnv *, jclass, jint, jstring, jint);
    JNIEXPORT jint JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_insertRowBelowJNI(JNIEnv *, jclass, jint, jstring, jint);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_removeRowJNI(JNIEnv *, jclass, jint);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_moveRowOrderJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_renameRowJNI(JNIEnv *, jclass, jint, jstring);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setRowIconJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowsJNI(JNIEnv *, jclass);

    // Row FX and controls
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_insertTrackEffectJNI(JNIEnv *, jclass, jint, jstring);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_removeTrackEffectJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_reorderTrackEffectsJNI(JNIEnv *, jclass, jint, jint, jint);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackEffectsForRowJNI(JNIEnv *, jclass, jint);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackEffectIdsForRowJNI(JNIEnv *, jclass, jint);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackEffectInstanceIdsForRowJNI(JNIEnv *, jclass, jint);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackPluginParametersJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setTrackEffectJNI(JNIEnv *, jclass, jint, jint, jstring, jobject);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_bypassRowEffectJNI(JNIEnv *, jclass, jint, jint, jboolean);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowEffectBypassStateJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setTrackAutomationPointsJNI(JNIEnv *, jclass, jint, jobject);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setTrackEffectAutomationPointsJNI(JNIEnv *, jclass, jint, jint, jstring, jdouble, jdouble, jobject);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_clearTrackEffectAutomationForRowJNI(JNIEnv *, jclass, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setRowGainAutomationPointsJNI(JNIEnv *, jclass, jint, jobject);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setRowGainJNI(JNIEnv *, jclass, jint, jfloat);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_muteRowJNI(JNIEnv *, jclass, jint, jboolean);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_isRowMutedJNI(JNIEnv *, jclass, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setRowPanAutomationPointsJNI(JNIEnv *, jclass, jint, jobject);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setRowPanJNI(JNIEnv *, jclass, jint, jfloat);

    // Master FX and controls
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_insertMasterEffectJNI(JNIEnv *, jclass, jstring);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_removeMasterEffectJNI(JNIEnv *, jclass, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_reorderMasterEffectsJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterEffectsJNI(JNIEnv *, jclass);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterEffectIdsJNI(JNIEnv *, jclass);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterPluginParametersJNI(JNIEnv *, jclass, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterEffectJNI(JNIEnv *, jclass, jint, jstring, jobject);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_bypassMasterEffectJNI(JNIEnv *, jclass, jint, jboolean);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterEffectBypassStateJNI(JNIEnv *, jclass, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterEffectAutomationPointsJNI(JNIEnv *, jclass, jint, jstring, jdouble, jdouble, jobject);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_clearMasterEffectAutomationJNI(JNIEnv *, jclass);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterGainAutomationPointsJNI(JNIEnv *, jclass, jobject);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterGainJNI(JNIEnv *, jclass, jfloat);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_muteMasterJNI(JNIEnv *, jclass, jboolean);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterPanAutomationPointsJNI(JNIEnv *, jclass, jobject);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterPanJNI(JNIEnv *, jclass, jfloat);

    // Debug graph
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_debugPrintGraphJNI(JNIEnv *, jclass, jstring);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_debugPrintGraphStructureJNI(JNIEnv *, jclass);

    // Metronome
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMetronomeEnabledJNI(JNIEnv *, jclass, jboolean);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMetronomeVolumeJNI(JNIEnv *, jclass, jfloat);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMetronomeBpmJNI(JNIEnv *, jclass, jdouble);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMetronomeTransportMsJNI(JNIEnv *, jclass, jdouble);

    // Offline analysis
    JNIEXPORT jdoubleArray JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_decodeAudioMono16kJNI(JNIEnv *, jclass, jstring);
    JNIEXPORT jdoubleArray JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_decodeAudioMono16kForAnalysisJNI(JNIEnv *, jclass, jstring, jint);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_analyzeAudioStereo16kJNI(JNIEnv *, jclass, jstring);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_analyzeAudioForPromptJNI(JNIEnv *, jclass, jstring, jint, jint, jdouble, jdouble);

    // Input devices and recording
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getInputDevicesJNI(JNIEnv *, jclass);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_selectInputDeviceJNI(JNIEnv *, jclass, jstring);
    JNIEXPORT jint JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getNumInputChannelsJNI(JNIEnv *, jclass);
    JNIEXPORT jint JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getActiveInputChannelCountJNI(JNIEnv *, jclass);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_prepareRecordingInputsJNI(JNIEnv *, jclass, jint, jstring);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_refreshAudioRouteJNI(JNIEnv *, jclass, jstring);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_hardResetPlaybackOnlyRouteJNI(JNIEnv *, jclass, jstring);
    JNIEXPORT jdouble JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRecordingPeakJNI(JNIEnv *, jclass);
    JNIEXPORT jstring JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getCurrentDeviceNameJNI(JNIEnv *, jclass);
    JNIEXPORT jstring JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getCurrentOutputDeviceNameJNI(JNIEnv *, jclass);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setLiveInputMonitoringEnabledJNI(JNIEnv *, jclass, jboolean);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_startRecordingJNI(JNIEnv *, jclass, jstring, jint, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_stopRecordingJNI(JNIEnv *, jclass);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_stopRecordingWithoutPlaybackRestoreJNI(JNIEnv *, jclass);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_isRecordingJNI(JNIEnv *, jclass);

    // Meters and waveforms
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterMeterEnabledJNI(JNIEnv *, jclass, jboolean);
    JNIEXPORT jdoubleArray JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterMeterValuesJNI(JNIEnv *, jclass);
    JNIEXPORT jboolean JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterClipLatchedJNI(JNIEnv *, jclass);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_clearMasterClipLatchedJNI(JNIEnv *, jclass);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setRowMetersEnabledJNI(JNIEnv *, jclass, jboolean);
    JNIEXPORT jdoubleArray JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowMeterValuesJNI(JNIEnv *, jclass, jint);
    JNIEXPORT jdoubleArray JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getAllMeterValuesJNI(JNIEnv *, jclass);
    JNIEXPORT jdoubleArray JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackCompressorMeterJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT jdoubleArray JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowCompressorMeterJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT jdoubleArray JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterCompressorMeterJNI(JNIEnv *, jclass, jint);
    JNIEXPORT jdouble JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getHostSampleRateJNI(JNIEnv *, jclass);
    JNIEXPORT jdoubleArray JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowEqWaveformJNI(JNIEnv *, jclass, jint, jint, jint);
    JNIEXPORT jdoubleArray JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterEqWaveformJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT jdoubleArray JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowStereoScopeJNI(JNIEnv *, jclass, jint, jint, jint);
    JNIEXPORT jdoubleArray JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterStereoScopeJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT jdoubleArray JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowShaperPreviewJNI(JNIEnv *, jclass, jint, jint, jint);
    JNIEXPORT jdoubleArray JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterShaperPreviewJNI(JNIEnv *, jclass, jint, jint);

    // Export and plugin discovery
    JNIEXPORT jstring JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_exportMixJNI(JNIEnv *, jclass, jstring, jstring, jint, jint, jboolean, jint, jstring);
    JNIEXPORT jdouble JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getExportProgressJNI(JNIEnv *, jclass);
    JNIEXPORT jstring JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_exportTrackJNI(JNIEnv *, jclass, jint, jstring, jstring, jint, jint, jboolean, jint);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getAvailablePluginsJNI(JNIEnv *, jclass);
    JNIEXPORT jstring JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_renderInstrumentClipJNI(JNIEnv *, jclass, jstring, jstring, jstring, jdouble, jobject, jobject);

    // Video lane
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_loadVideoAudioJNI(JNIEnv *, jclass, jstring);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_unloadVideoAudioJNI(JNIEnv *, jclass);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setVideoAudioGainJNI(JNIEnv *, jclass, jfloat);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_seekVideoAudioJNI(JNIEnv *, jclass, jdouble);

#ifdef __cplusplus
}
#endif
