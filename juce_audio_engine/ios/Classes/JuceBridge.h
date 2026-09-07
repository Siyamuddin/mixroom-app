#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

@interface JuceBridge : NSObject

+ (void)initialiseEngineObjC;
// "V2" denotes Mixroom's coordinator-owned, verified route lifecycle, not a
// JUCE API version. These calls serialize route mutation and prove the native
// device/callback state before playback or recording is admitted.
+ (BOOL)initialisePlaybackV2ObjC:(NSString * _Nonnull)outputDeviceName;
+ (BOOL)pausePlaybackForRouteChangeV2ObjC;
+ (BOOL)quiescePlaybackRouteV2ObjC:(BOOL)closeRemovedDevice;
+ (BOOL)reconfigurePlaybackRouteV2ObjC:(NSString * _Nonnull)outputDeviceName;
+ (BOOL)reconfigurePlaybackRouteV2ObjC:(NSString * _Nonnull)outputDeviceName
                            sampleRate:(double)sampleRate
                          bufferFrames:(NSInteger)bufferFrames;
#if TARGET_OS_OSX
+ (BOOL)initialiseMacPlaybackV2ObjC:(NSString * _Nonnull)outputDeviceName
                         sampleRate:(double)sampleRate
                       bufferFrames:(NSInteger)bufferFrames;
+ (BOOL)reconfigureMacPlaybackRouteV2ObjC:(NSString * _Nonnull)outputDeviceName
                              sampleRate:(double)sampleRate
                            bufferFrames:(NSInteger)bufferFrames;
+ (void)beginMacOutputCallbackProofV2ObjC;
+ (BOOL)waitForMacOutputCallbackProofV2ObjC:(NSInteger)timeoutMilliseconds;
+ (void)cancelMacOutputCallbackProofV2ObjC;
+ (NSNumber * _Nonnull)getMacOutputCallbackProofCountV2ObjC;
+ (NSNumber * _Nonnull)getMacOutputCallbackProofFramesV2ObjC;
+ (NSNumber * _Nonnull)getMacOutputCallbackProofSampleRateV2ObjC;
+ (BOOL)startMacInputProbeV2ObjC:(uint32_t)deviceID
                    channelStart:(NSInteger)channelStart
                    channelCount:(NSInteger)channelCount;
+ (BOOL)waitForMacInputProbeCallbackV2ObjC:(NSInteger)timeoutMilliseconds;
+ (void)cancelMacInputProbeWaitV2ObjC;
+ (NSDictionary<NSString *, id> * _Nonnull)getMacInputProbeFactsV2ObjC;
+ (void)stopMacInputProbeV2ObjC;
+ (BOOL)startMacInputRecordingV2ObjC:(NSString * _Nonnull)path
                         channelStart:(NSInteger)channelStart
                         channelCount:(NSInteger)channelCount;
+ (NSDictionary<NSString *, id> * _Nonnull)stopMacInputRecordingV2ObjC;
+ (void)discardMacInputRecordingV2ObjC;
+ (BOOL)isMacInputRecordingV2ObjC;
+ (NSDictionary<NSString *, id> * _Nonnull)getMacInputCaptureFactsV2ObjC;
+ (BOOL)prepareMacIndependentInputMonitoringV2ObjC:(NSInteger)row
                                      channelCount:(NSInteger)channelCount
                                   inputSampleRate:(double)inputSampleRate
                                  outputSampleRate:(double)outputSampleRate
                                  inputBlockFrames:(NSInteger)inputBlockFrames
                                 outputBlockFrames:(NSInteger)outputBlockFrames;
+ (void)disableMacIndependentInputMonitoringV2ObjC;
+ (NSDictionary<NSString *, NSNumber *> * _Nonnull)getMacIndependentInputMonitoringFactsV2ObjC;
#endif
+ (void)beginOutputCallbackProofV2ObjC;
+ (BOOL)waitForOutputCallbackProofV2ObjC:(NSInteger)timeoutMilliseconds;
+ (NSNumber * _Nonnull)getOutputCallbackProofCountV2ObjC;
+ (NSNumber * _Nonnull)getOutputCallbackProofFramesV2ObjC;
+ (NSNumber * _Nonnull)getOutputCallbackProofSampleRateV2ObjC;
+ (BOOL)reconfigureRecordingRouteV2ObjC:(NSString * _Nonnull)outputDeviceName
                              inputName:(NSString * _Nonnull)inputDeviceName;
+ (BOOL)prepareBluetoothDuplexSessionV2ObjC;
+ (BOOL)openPreparedBluetoothDuplexRouteV2ObjC:(NSInteger)timeoutMilliseconds;
+ (BOOL)prepareSystemSelectedDuplexSessionV2ObjC;
+ (BOOL)openPreparedSystemSelectedDuplexRouteV2ObjC:(NSInteger)timeoutMilliseconds
                                      outputChannels:(NSInteger)outputChannels
                                       inputChannels:(NSInteger)inputChannels;
+ (BOOL)reconfigureBluetoothDuplexRouteV2ObjC;
+ (NSDictionary<NSString *, NSNumber *> * _Nonnull)getLiveInputMonitoringFactsV2ObjC;
+ (void)discardRecordingForMonitoringV2ObjC;
+ (BOOL)validateRecordingRouteV2ObjC;
+ (BOOL)setLiveInputMonitorTargetV2ObjC:(NSInteger)row
                           channelStart:(NSInteger)channelStart
                           channelCount:(NSInteger)channelCount;
+ (void)disableLiveInputMonitoringV2ObjC;
+ (BOOL)isBluetoothDuplexProjectCallbackReadyV2ObjC;
+ (void)beginIOSIntentOperationV2ObjC;
+ (void)endIOSIntentOperationV2ObjC;
+ (void)markIOSIntentRouteInvalidatedV2ObjC;
+ (BOOL)isIOSIntentRouteInvalidatedV2ObjC;
+ (NSDictionary<NSString *, id> * _Nonnull)getIOSAudioSessionPolicyFactsObjC;
+ (NSString * _Nonnull)getAudioRouteImplementationObjC;
+ (void)initializeMessageManager;
+ (void)shutdownEngineObjC;
+ (void)shutdownForApplicationTerminationObjC;
+ (void)panicLiveMidiNotesForApplicationDeactivationObjC;
+ (void)setFlutterAssetRootObjC:(NSString *)rootPath;

// DEPRECATED: use loadClipObjC:rowId:path:startSec:lengthSec:inFileOffsetSec: instead
+ (void)loadTrackObjC:(NSInteger)idx path:(NSString *)path;

+ (BOOL)playObjC;
+ (void)pauseObjC;
+ (BOOL)isTransportPlayingObjC;
+ (void)removeTrackObjC:(NSInteger)trackIndex;
+ (NSArray<NSString *> *)getTrackEffectsObjC:(NSInteger)trackIndex;
+ (void)removeEffectObjC:(NSInteger)trackIndex effectIndex:(NSInteger)effectIndex;
+ (void)reorderEffectsObjC:(NSInteger)trackIndex
                 fromIndex:(NSInteger)fromIdx
                   toIndex:(NSInteger)toIdx;
+ (void)seekObjC:(NSInteger)trackIndex position:(double)seconds;
+ (double)getCurrentPositionObjC:(NSInteger)trackIndex;
+ (double)getTrackDurationObjC:(NSInteger)trackIndex;
+ (void)insertEffectObjC:(NSInteger)track path:(NSString *)pluginPath;

// DEPRECATED: use setEffectParameter-style APIs for clips/rows/master
+ (void)setEffectObjC:(NSInteger)track
          pluginIndex:(NSInteger)pindex
              paramId:(NSString *)param
                value:(id)value;

+ (void)setTrackVolumeObjC:(NSInteger)track volume:(float)v;
+ (NSArray<NSDictionary *> *)getPluginParametersObjC:(NSInteger)track
                                         effectIndex:(NSInteger)effect;
+ (NSString *)exportMixObjC:(NSString *)outPath settings:(NSDictionary *)settings;
+ (double)getExportProgressObjC;
+ (NSString *)exportTrackObjC:(NSInteger)track outPath:(NSString *)outPath settings:(NSDictionary *)settings;
+ (NSString *)renderInstrumentClipObjC:(NSString *)outPath
                          instrumentId:(NSString *)instrumentId
                        instrumentName:(NSString *)instrumentName
                                   bpm:(double)bpm
                                 notes:(NSArray<NSDictionary *> *)notes
                                params:(NSDictionary<NSString *, NSNumber *> *)params;
+ (NSString *)renderPitchLabAudioObjC:(NSString *)sourcePath
                              outPath:(NSString *)outPath
                          trimStartMs:(double)trimStartMs
                            trimEndMs:(double)trimEndMs
             sourceTimelineDurationMs:(double)sourceTimelineDurationMs
                     outputDurationMs:(double)outputDurationMs
                     suppressedRanges:(NSArray<NSDictionary *> *)suppressedRanges
                             segments:(NSArray<NSDictionary *> *)segments;
+ (NSArray<NSDictionary *> *)scanPluginsObjC:(NSArray<NSString *> * _Nullable)searchPaths;
+ (NSArray<NSDictionary *> *)rescanPluginsObjC:(NSArray<NSString *> * _Nullable)searchPaths;
+ (void)cancelPluginScanObjC;
+ (NSArray<NSDictionary *> *)getQuarantinedPluginsObjC;
+ (BOOL)isPluginQuarantinedObjC:(NSString *)pluginId;
+ (void)clearPluginQuarantineObjC:(NSString *)pluginId;
+ (void)clearAllPluginQuarantinesObjC;
+ (NSDictionary<NSString *, id> *)getEngineDiagnosticsObjC;
+ (NSDictionary<NSString *, id> *)runEngineStressTestObjC:(NSInteger)clipCount
                                               blockCount:(NSInteger)blockCount
                                                blockSize:(NSInteger)blockSize
                                               sampleRate:(double)sampleRate;
+ (void)resetRealtimePerformanceStatsObjC;
+ (void)bypassPluginObjC:(NSInteger)trackIndex
             effectIndex:(NSInteger)effectIndex
                  bypass:(BOOL)shouldBypass;
+ (bool)getPluginBypassStateObjC:(NSInteger)trackIndex
                     effectIndex:(NSInteger)effectIndex;
+ (void)bypassTrackObjC:(NSInteger)trackIndex
           shouldBypass:(BOOL)shouldBypass;
+ (void)loadVideoAudioObjC:(NSString *)path;
+ (void)unloadVideoAudioObjC;
+ (void)setVideoAudioGainObjC:(float)gain;
+ (void)seekVideoAudioObjC:(double)seconds;

// ===============================================================
// NEW DAW-STYLE API (clip / row / master / automation)
// ===============================================================

// Debug graph inspection
+ (void)debugPrintGraphObjC:(NSString *)title;
+ (void)debugPrintGraphStructureObjC;

// Clip-level control (per-clip)
+ (BOOL)loadClipObjC:(NSInteger)clipIndex
               rowId:(NSInteger)rowId
                path:(NSString *)path
            startSec:(double)startSec
           lengthSec:(double)lengthSec
     inFileOffsetSec:(double)inFileOffsetSec;
+ (void)beginProjectClipLoadObjC;
+ (void)endProjectClipLoadObjC;
+ (void)beginGraphMutationBatchObjC;
+ (void)endGraphMutationBatchObjC;
+ (BOOL)supportsLiveMidiClipPlaybackObjC;
+ (BOOL)isBuiltInMidiInstrumentObjC:(NSString *)instrumentId;
+ (BOOL)loadMidiClipObjC:(NSInteger)clipIndex
                   rowId:(NSInteger)rowId
            instrumentId:(NSString *)instrumentId
          instrumentName:(NSString *)instrumentName
                   notes:(NSArray<NSDictionary *> *)notes
                  params:(NSDictionary<NSString *, NSNumber *> *)params
           sourceTempoBpm:(double)sourceTempoBpm
                startSec:(double)startSec
               lengthSec:(double)lengthSec
         inFileOffsetSec:(double)inFileOffsetSec
           loadRequestId:(int64_t)loadRequestId;
+ (BOOL)cancelMidiClipLoadObjC:(NSInteger)clipIndex
                 requestId:(int64_t)loadRequestId;
+ (BOOL)updateMidiClipObjC:(NSInteger)clipIndex
              instrumentId:(NSString *)instrumentId
            instrumentName:(NSString *)instrumentName
                     notes:(NSArray<NSDictionary *> *)notes
                    params:(NSDictionary<NSString *, NSNumber *> *)params
             sourceTempoBpm:(double)sourceTempoBpm;
+ (BOOL)setLiveMidiInputTargetClipObjC:(NSInteger)clipIndex;
+ (BOOL)sendLiveMidiInputEventObjC:(BOOL)noteOn
                           channel:(NSInteger)channel
                             pitch:(NSInteger)pitch
                          velocity:(float)velocity;
+ (BOOL)playPreviewMidiNoteObjC:(NSInteger)clipIndex
                          pitch:(NSInteger)pitch
                       velocity:(float)velocity
                     durationMs:(NSInteger)durationMs;
+ (BOOL)openMidiClipPluginEditorObjC:(NSInteger)clipIndex;
+ (void)setMidiClipPluginParameterObjC:(NSInteger)clipIndex
                               paramId:(NSString * _Nonnull)paramId
                      normalizedValue:(float)normalizedValue;
+ (void)setMidiClipPluginAutomationPointsObjC:(NSInteger)clipIndex
                                       paramId:(NSString * _Nonnull)paramId
                                        points:(NSArray<NSDictionary *> * _Nonnull)points;
+ (void)clearMidiClipPluginAutomationObjC:(NSInteger)clipIndex;
+ (NSString *)getMidiClipPluginStateObjC:(NSInteger)clipIndex;
+ (BOOL)setMidiClipPluginStateObjC:(NSInteger)clipIndex
                        stateBase64:(NSString *)stateBase64;
+ (void)setHostedPluginWindowsDetachedObjC:(BOOL)detached;
+ (void)setDesktopKeyboardMidiForwardingEnabledObjC:(BOOL)enabled;
+ (NSArray<NSDictionary *> *)consumeLiveMidiInputEventsObjC;
+ (NSArray<NSDictionary *> *)getConnectedMidiInputDevicesObjC;
+ (void)unloadClipObjC:(NSInteger)clipIndex;
+ (NSInteger)unloadClipsObjC:(NSArray<NSNumber *> *)clipIndices;
+ (void)setClipGainObjC:(NSInteger)clipIndex gain:(float)gain;
+ (void)setClipExtraGainLinearObjC:(NSInteger)clipIndex gain:(float)gain;
+ (void)muteClipObjC:(NSInteger)clipIndex shouldMute:(BOOL)shouldMute;
+ (void)setClipPanObjC:(NSInteger)clipIndex pan:(float)pan;
+ (void)setClipFadesObjC:(NSInteger)clipIndex
               fadeInSec:(double)fadeInSec
              fadeOutSec:(double)fadeOutSec
               fadeCurve:(NSInteger)fadeCurve;
+ (NSInteger)updateClipFadesBatchObjC:(NSArray<NSDictionary *> *)updates;
+ (void)setClipPitchObjC:(NSInteger)clipIndex semitones:(float)semitones;
+ (void)setClipReversedObjC:(NSInteger)clipIndex reversed:(BOOL)reversed;
+ (void)setClipStretchOptionsObjC:(NSInteger)clipIndex
                       tempoRatio:(double)tempoRatio
                    preservePitch:(BOOL)preservePitch;
+ (void)moveClipToRowObjC:(NSInteger)clipIndex newRowId:(NSInteger)newRowId;
+ (void)setClipTimeObjC:(NSInteger)clipIndex
               startSec:(double)startSec
              lengthSec:(double)lengthSec
        inFileOffsetSec:(double)inFileOffsetSec;
+ (NSInteger)updateClipTimelineBatchObjC:(NSArray<NSDictionary *> *)updates;

// Row management
+ (NSNumber *)addRowObjC:(NSString *)name iconId:(NSInteger)iconId preferredRowId:(NSInteger)preferredRowId;
+ (NSNumber *)insertRowAboveObjC:(NSInteger)referenceRowId name:(NSString *)name iconId:(NSInteger)iconId preferredRowId:(NSInteger)preferredRowId;
+ (NSNumber *)insertRowBelowObjC:(NSInteger)referenceRowId name:(NSString *)name iconId:(NSInteger)iconId preferredRowId:(NSInteger)preferredRowId;
+ (BOOL)removeRowObjC:(NSInteger)rowId;
+ (BOOL)moveRowOrderObjC:(NSInteger)fromIndex toIndex:(NSInteger)toIndex;
+ (BOOL)renameRowObjC:(NSInteger)rowId name:(NSString *)name;
+ (BOOL)setRowIconObjC:(NSInteger)rowId iconId:(NSInteger)iconId;
+ (NSArray<NSDictionary *> *)getRowsObjC;

// Transport source of truth
+ (void)setTransportSecondsObjC:(double)seconds;
+ (double)getTransportSecondsObjC;
+ (void)setLoopRegionObjC:(BOOL)enabled startSeconds:(double)startSeconds endSeconds:(double)endSeconds;

// Row (track bus) FX and controls
+ (BOOL)insertTrackEffectObjC:(NSInteger)trackRow path:(NSString *)pluginPath forceIndividualRow:(BOOL)forceIndividualRow;
+ (void)removeTrackEffectObjC:(NSInteger)trackRow effectIndex:(NSInteger)effectIndex forceIndividualRow:(BOOL)forceIndividualRow;
+ (void)reorderTrackEffectsObjC:(NSInteger)trackRow
                      fromIndex:(NSInteger)fromIdx
                        toIndex:(NSInteger)toIdx
             forceIndividualRow:(BOOL)forceIndividualRow;
+ (NSArray<NSString *> *)getTrackEffectsForRowObjC:(NSInteger)trackRow forceIndividualRow:(BOOL)forceIndividualRow;
+ (NSArray<NSString *> *)getTrackEffectIdsForRowObjC:(NSInteger)trackRow forceIndividualRow:(BOOL)forceIndividualRow;
+ (NSArray<NSString *> *)getTrackEffectInstanceIdsForRowObjC:(NSInteger)trackRow forceIndividualRow:(BOOL)forceIndividualRow;
+ (NSString *)getTrackEffectStateObjC:(NSInteger)trackRow
                          effectIndex:(NSInteger)effectIndex
                   forceIndividualRow:(BOOL)forceIndividualRow;
+ (BOOL)setTrackEffectStateObjC:(NSInteger)trackRow
                    effectIndex:(NSInteger)effectIndex
                    stateBase64:(NSString *)stateBase64
             forceIndividualRow:(BOOL)forceIndividualRow;
+ (BOOL)openTrackPluginEditorObjC:(NSInteger)trackRow
                     effectIndex:(NSInteger)effectIndex;
+ (NSArray<NSDictionary *> *)getTrackPluginParametersObjC:(NSInteger)row
                                              effectIndex:(NSInteger)effect
                                       forceIndividualRow:(BOOL)forceIndividualRow;
+ (void)setTrackEffectObjC:(NSInteger)trackRow
               effectIndex:(NSInteger)effectIndex
                   paramId:(NSString *)param
                     value:(id)value
        forceIndividualRow:(BOOL)forceIndividualRow;
+ (void)bypassRowEffectObjC:(NSInteger)rowIndex
                effectIndex:(NSInteger)effectIndex
                     bypass:(BOOL)shouldBypass
         forceIndividualRow:(BOOL)forceIndividualRow;
+ (bool)getRowEffectBypassStateObjC:(NSInteger)rowIndex
                        effectIndex:(NSInteger)effectIndex
                 forceIndividualRow:(BOOL)forceIndividualRow;
+ (void)setRowGainAutomationPointsObjC:(NSInteger)row
                               points:(NSArray<NSDictionary *> *)points;
+ (void)setRowGainObjC:(NSInteger)row gain:(float)gain;
+ (void)muteRowObjC:(NSInteger)row shouldMute:(BOOL)shouldMute;
+ (bool)isRowMutedObjC:(NSInteger)row;
+ (void)setRowPanAutomationPointsObjC:(NSInteger)row
                              points:(NSArray<NSDictionary *> *)points;
+ (void)setRowPanObjC:(NSInteger)row pan:(float)pan;
+ (void)configureTrackGroupsObjC:(NSArray<NSDictionary *> *)groups;
+ (void)assignRowToGroupObjC:(NSInteger)row groupId:(NSString *)groupId;
+ (void)setTrackGroupMixStateObjC:(NSString *)groupId
                             gain:(float)gain
                              pan:(float)pan
                            muted:(BOOL)muted
                           soloed:(BOOL)soloed;

// Master bus FX and controls
+ (BOOL)insertMasterEffectObjC:(NSString *)pluginPath;
+ (void)removeMasterEffectObjC:(NSInteger)effectIndex;
+ (void)reorderMasterEffectsObjC:(NSInteger)fromIndex
                         toIndex:(NSInteger)toIndex;
+ (NSArray<NSString *> *)getMasterEffectsObjC;
+ (NSArray<NSString *> *)getMasterEffectIdsObjC;
+ (NSString *)getMasterEffectStateObjC:(NSInteger)effectIndex;
+ (BOOL)setMasterEffectStateObjC:(NSInteger)effectIndex
                     stateBase64:(NSString *)stateBase64;
+ (BOOL)openMasterPluginEditorObjC:(NSInteger)effectIndex;
+ (NSArray<NSDictionary *> *)getMasterPluginParametersObjC:(NSInteger)effect;
+ (void)setMasterEffectObjC:(NSInteger)effectIndex
                    paramId:(NSString *)param
                      value:(id)value;
+ (void)bypassMasterEffectObjC:(NSInteger)effectIndex
                        bypass:(BOOL)shouldBypass;
+ (bool)getMasterEffectBypassStateObjC:(NSInteger)effectIndex;
+ (void)setMasterEffectAutomationPointsObjC:(NSInteger)effectIndex
                                  paramId:(NSString *)paramId
                                 minValue:(double)minValue
                                 maxValue:(double)maxValue
                                   points:(NSArray<NSDictionary *> *)points;
+ (void)clearMasterEffectAutomationObjC;
+ (void)setMasterGainAutomationPointsObjC:(NSArray<NSDictionary *> *)points;
+ (void)setMasterGainObjC:(float)gain;
+ (void)muteMasterObjC:(BOOL)shouldMute;
+ (void)setMasterPanAutomationPointsObjC:(NSArray<NSDictionary *> *)points;
+ (void)setMasterPanObjC:(float)pan;

// Automation (rows)
+ (void)setTrackAutomationPointsObjC:(NSInteger)trackRow
                              points:(NSArray<NSDictionary *> *)points;
+ (void)setTrackEffectAutomationPointsObjC:(NSInteger)trackRow
                                effectIndex:(NSInteger)effectIndex
                                    paramId:(NSString *)paramId
                                   minValue:(double)minValue
                                   maxValue:(double)maxValue
                                     points:(NSArray<NSDictionary *> *)points;
+ (void)clearTrackEffectAutomationForRowObjC:(NSInteger)trackRow;
+ (void)setAutomationTransportObjC:(double)timeSeconds;

// =======================
// METRONOME API
// =======================

// Turn metronome on/off
+ (void)setMetronomeEnabledObjC:(BOOL)enabled;

// Set metronome volume (0.0–1.0)
+ (void)setMetronomeVolumeObjC:(float)vol;

// Change BPM
+ (void)setMetronomeBpmObjC:(double)bpm;

// Change time signature
+ (void)setMetronomeTimeSignatureObjC:(NSInteger)numerator
                          denominator:(NSInteger)denominator;

// Sync transport (in milliseconds)
+ (void)setMetronomeTransportMsObjC:(double)ms;

+ (NSArray<NSNumber *> *)decodeAudioMono16kObjC:(NSString *)path;
+ (NSDictionary<NSString *, NSNumber *> *)analyzeAudioStereo16kObjC:(NSString *)path;
+ (NSDictionary<NSString *, id> *)analyzeAudioForPromptObjC:(NSString *)path
                                                trimStartMs:(double)trimStartMs
                                                  trimEndMs:(double)trimEndMs;

+ (NSArray<NSString *> *)getInputDevicesObjC;
+ (NSArray<NSString *> *)getOutputDevicesObjC;
+ (BOOL)selectInputDeviceObjC:(NSString *)name;
+ (BOOL)selectOutputDeviceObjC:(NSString *)name;

+ (NSNumber *)getNumInputChannelsObjC;
+ (NSString *)getCurrentDeviceNameObjC;
+ (NSString *)getCurrentOutputDeviceNameObjC;
+ (BOOL)prepareRecordingInputsObjC:(NSInteger)desiredInputChannels
                            reason:(NSString *)reason;
+ (BOOL)configureAudioDeviceObjC:(double)sampleRate
                       bufferSize:(NSInteger)bufferSize
              desiredInputChannels:(NSInteger)desiredInputChannels
                            reason:(NSString *)reason;
+ (BOOL)preparePlaybackRouteObjC:(NSString *)reason;
+ (BOOL)preparePlaybackGraphObjC:(NSString *)reason;
+ (void)refreshAudioRouteObjC:(NSString *)reason;
+ (void)setLiveInputMonitoringEnabledObjC:(BOOL)enabled;
+ (void)setMidiInputChannelFilterObjC:(NSInteger)channel;
+ (NSNumber *)getMidiInputChannelFilterObjC;

+ (BOOL)startRecordingObjC:(NSString *)path
              channelStart:(NSInteger)start
              channelCount:(NSInteger)count;

+ (NSNumber *)getRecordingPeakObjC;

+ (NSDictionary<NSString *, id> *)stopRecordingObjC;
+ (NSDictionary<NSString *, id> *)finalizeRecordingForMonitoringV2ObjC;
+ (void)discardRecordingCaptureObjC;
+ (BOOL)isRecordingObjC;

// ===============================
// MASTER METER
// ===============================
+ (void)setMasterMeterEnabledObjC:(BOOL)enabled;
+ (NSArray<NSNumber *> *)getMasterMeterValuesObjC; // [peakL, peakR, rmsL, rmsR]
+ (BOOL)getMasterClipLatchedObjC;
+ (void)clearMasterClipLatchedObjC;

// ===============================
// ROW METERS
// ===============================
+ (void)setRowMetersEnabledObjC:(BOOL)enabled;
+ (NSArray<NSNumber *> *)getRowMeterValuesObjC:(NSInteger)row; // [peakL, peakR, rmsL, rmsR]

+ (NSArray<NSNumber *> *)getAllMeterValues;

// ===============================
// COMPRESSOR METER STRIPS
// [inRmsL, inRmsR, grDb, outRmsL, outRmsR]
// ===============================
+ (NSArray<NSNumber *> *)getClipCompressorMeterObjC:(NSInteger)clipIndex effectIndex:(NSInteger)effectIndex;
+ (NSArray<NSNumber *> *)getRowCompressorMeterObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex;
+ (NSArray<NSNumber *> *)getMasterCompressorMeterObjC:(NSInteger)effectIndex;
+ (double)getHostSampleRateObjC;
+ (NSArray<NSNumber *> *)getRecentMasterWaveformObjC:(NSInteger)sampleCount;
+ (NSArray<NSNumber *> *)getRecentMasterStereoWaveformObjC:(NSInteger)sampleCount;
+ (NSArray<NSNumber *> *)getRowEqWaveformObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex sampleCount:(NSInteger)sampleCount;
+ (NSArray<NSNumber *> *)getMasterEqWaveformObjC:(NSInteger)effectIndex sampleCount:(NSInteger)sampleCount;
+ (NSArray<NSNumber *> *)getRowStereoScopeObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex pointCount:(NSInteger)pointCount;
+ (NSArray<NSNumber *> *)getMasterStereoScopeObjC:(NSInteger)effectIndex pointCount:(NSInteger)pointCount;
+ (NSArray<NSNumber *> *)getRowShaperPreviewObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex pointCount:(NSInteger)pointCount;
+ (NSArray<NSNumber *> *)getMasterShaperPreviewObjC:(NSInteger)effectIndex pointCount:(NSInteger)pointCount;
+ (NSArray<NSNumber *> *)getRowDynamicSoftenerFrameObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex;
+ (NSArray<NSNumber *> *)getMasterDynamicSoftenerFrameObjC:(NSInteger)effectIndex;
+ (NSArray<NSNumber *> *)getRowTransientShaperVisualObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex pointCount:(NSInteger)pointCount;
+ (NSArray<NSNumber *> *)getMasterTransientShaperVisualObjC:(NSInteger)effectIndex pointCount:(NSInteger)pointCount;

@end
