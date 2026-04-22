#import <Foundation/Foundation.h>

@interface JuceBridge : NSObject

+ (void)initialiseEngineObjC;
+ (void)initializeMessageManager;
+ (void)shutdownEngineObjC;
+ (void)setFlutterAssetRootObjC:(NSString *)rootPath;

// DEPRECATED: use loadClipObjC:rowId:path:startSec:lengthSec:inFileOffsetSec: instead
+ (void)loadTrackObjC:(NSInteger)idx path:(NSString *)path;

+ (void)playObjC;
+ (void)pauseObjC;
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
+ (NSArray<NSDictionary *> *)scanPluginsObjC;
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
+ (BOOL)supportsLiveMidiClipPlaybackObjC;
+ (BOOL)loadMidiClipObjC:(NSInteger)clipIndex
                   rowId:(NSInteger)rowId
            instrumentId:(NSString *)instrumentId
          instrumentName:(NSString *)instrumentName
                   notes:(NSArray<NSDictionary *> *)notes
                  params:(NSDictionary<NSString *, NSNumber *> *)params
           sourceTempoBpm:(double)sourceTempoBpm
                startSec:(double)startSec
               lengthSec:(double)lengthSec
         inFileOffsetSec:(double)inFileOffsetSec;
+ (BOOL)updateMidiClipObjC:(NSInteger)clipIndex
              instrumentId:(NSString *)instrumentId
            instrumentName:(NSString *)instrumentName
                     notes:(NSArray<NSDictionary *> *)notes
                    params:(NSDictionary<NSString *, NSNumber *> *)params
             sourceTempoBpm:(double)sourceTempoBpm;
+ (BOOL)setLiveMidiInputTargetClipObjC:(NSInteger)clipIndex;
+ (BOOL)playPreviewMidiNoteObjC:(NSInteger)clipIndex
                          pitch:(NSInteger)pitch
                       velocity:(float)velocity
                     durationMs:(NSInteger)durationMs;
+ (NSArray<NSDictionary *> *)consumeLiveMidiInputEventsObjC;
+ (NSArray<NSDictionary *> *)getConnectedMidiInputDevicesObjC;
+ (void)unloadClipObjC:(NSInteger)clipIndex;
+ (void)setClipGainObjC:(NSInteger)clipIndex gain:(float)gain;
+ (void)muteClipObjC:(NSInteger)clipIndex shouldMute:(BOOL)shouldMute;
+ (void)setClipPanObjC:(NSInteger)clipIndex pan:(float)pan;
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

// Row management
+ (NSNumber *)addRowObjC:(NSString *)name iconId:(NSInteger)iconId;
+ (NSNumber *)insertRowAboveObjC:(NSInteger)referenceRowId name:(NSString *)name iconId:(NSInteger)iconId;
+ (NSNumber *)insertRowBelowObjC:(NSInteger)referenceRowId name:(NSString *)name iconId:(NSInteger)iconId;
+ (BOOL)removeRowObjC:(NSInteger)rowId;
+ (BOOL)moveRowOrderObjC:(NSInteger)fromIndex toIndex:(NSInteger)toIndex;
+ (BOOL)renameRowObjC:(NSInteger)rowId name:(NSString *)name;
+ (BOOL)setRowIconObjC:(NSInteger)rowId iconId:(NSInteger)iconId;
+ (NSArray<NSDictionary *> *)getRowsObjC;

// Transport source of truth
+ (void)setTransportSecondsObjC:(double)seconds;
+ (double)getTransportSecondsObjC;

// Row (track bus) FX and controls
+ (BOOL)insertTrackEffectObjC:(NSInteger)trackRow path:(NSString *)pluginPath;
+ (void)removeTrackEffectObjC:(NSInteger)trackRow effectIndex:(NSInteger)effectIndex;
+ (void)reorderTrackEffectsObjC:(NSInteger)trackRow
                      fromIndex:(NSInteger)fromIdx
                        toIndex:(NSInteger)toIdx;
+ (NSArray<NSString *> *)getTrackEffectsForRowObjC:(NSInteger)trackRow;
+ (NSArray<NSString *> *)getTrackEffectIdsForRowObjC:(NSInteger)trackRow;
+ (NSArray<NSString *> *)getTrackEffectInstanceIdsForRowObjC:(NSInteger)trackRow;
+ (NSArray<NSDictionary *> *)getTrackPluginParametersObjC:(NSInteger)row
                                              effectIndex:(NSInteger)effect;
+ (void)setTrackEffectObjC:(NSInteger)trackRow
               effectIndex:(NSInteger)effectIndex
                   paramId:(NSString *)param
                     value:(id)value;
+ (void)bypassRowEffectObjC:(NSInteger)rowIndex
                effectIndex:(NSInteger)effectIndex
                     bypass:(BOOL)shouldBypass;
+ (bool)getRowEffectBypassStateObjC:(NSInteger)rowIndex
                        effectIndex:(NSInteger)effectIndex;
+ (void)setRowGainAutomationPointsObjC:(NSInteger)row
                               points:(NSArray<NSDictionary *> *)points;
+ (void)setRowGainObjC:(NSInteger)row gain:(float)gain;
+ (void)muteRowObjC:(NSInteger)row shouldMute:(BOOL)shouldMute;
+ (bool)isRowMutedObjC:(NSInteger)row;
+ (void)setRowPanAutomationPointsObjC:(NSInteger)row
                              points:(NSArray<NSDictionary *> *)points;
+ (void)setRowPanObjC:(NSInteger)row pan:(float)pan;

// Master bus FX and controls
+ (BOOL)insertMasterEffectObjC:(NSString *)pluginPath;
+ (void)removeMasterEffectObjC:(NSInteger)effectIndex;
+ (void)reorderMasterEffectsObjC:(NSInteger)fromIndex
                         toIndex:(NSInteger)toIndex;
+ (NSArray<NSString *> *)getMasterEffectsObjC;
+ (NSArray<NSString *> *)getMasterEffectIdsObjC;
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

// Sync transport (in milliseconds)
+ (void)setMetronomeTransportMsObjC:(double)ms;

+ (NSArray<NSNumber *> *)decodeAudioMono16kObjC:(NSString *)path;
+ (NSDictionary<NSString *, NSNumber *> *)analyzeAudioStereo16kObjC:(NSString *)path;
+ (NSDictionary<NSString *, id> *)analyzeAudioForPromptObjC:(NSString *)path
                                                trimStartMs:(double)trimStartMs
                                                  trimEndMs:(double)trimEndMs;

+ (NSArray<NSString *> *)getInputDevicesObjC;
+ (BOOL)selectInputDeviceObjC:(NSString *)name;

+ (NSNumber *)getNumInputChannelsObjC;
+ (NSString *)getCurrentDeviceNameObjC;
+ (NSString *)getCurrentOutputDeviceNameObjC;
+ (BOOL)prepareRecordingInputsObjC:(NSInteger)desiredInputChannels
                            reason:(NSString *)reason;
+ (BOOL)preparePlaybackRouteObjC:(NSString *)reason;
+ (void)refreshAudioRouteObjC:(NSString *)reason;
+ (void)setLiveInputMonitoringEnabledObjC:(BOOL)enabled;

+ (BOOL)startRecordingObjC:(NSString *)path
              channelStart:(NSInteger)start
              channelCount:(NSInteger)count;

+ (NSNumber *)getRecordingPeakObjC;

+ (void)stopRecordingObjC;
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
+ (NSArray<NSNumber *> *)getRowEqWaveformObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex sampleCount:(NSInteger)sampleCount;
+ (NSArray<NSNumber *> *)getMasterEqWaveformObjC:(NSInteger)effectIndex sampleCount:(NSInteger)sampleCount;
+ (NSArray<NSNumber *> *)getRowStereoScopeObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex pointCount:(NSInteger)pointCount;
+ (NSArray<NSNumber *> *)getMasterStereoScopeObjC:(NSInteger)effectIndex pointCount:(NSInteger)pointCount;
+ (NSArray<NSNumber *> *)getRowShaperPreviewObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex pointCount:(NSInteger)pointCount;
+ (NSArray<NSNumber *> *)getMasterShaperPreviewObjC:(NSInteger)effectIndex pointCount:(NSInteger)pointCount;

@end
