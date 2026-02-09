#import <Foundation/Foundation.h>

@interface JuceBridge : NSObject

+ (void)initialiseEngineObjC;
+ (void)initializeMessageManager;
+ (void)shutdownEngineObjC;

// DEPRECATED: use loadClipObjC:rowIndex:path: instead
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
+ (NSString *)exportMixObjC:(NSString *)outPath;
+ (NSString *)exportTrackObjC:(NSInteger)track outPath:(NSString *)outPath;
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
+ (void)loadClipObjC:(NSInteger)clipIndex
            rowIndex:(NSInteger)rowIndex
                path:(NSString *)path;
+ (void)setClipGainObjC:(NSInteger)clipIndex gain:(float)gain;
+ (void)muteClipObjC:(NSInteger)clipIndex shouldMute:(BOOL)shouldMute;
+ (void)setClipPanObjC:(NSInteger)clipIndex pan:(float)pan;
+ (void)moveClipToRowObjC:(NSInteger)clipIndex newRow:(NSInteger)newRow;

// Row (track bus) FX and controls
+ (void)insertTrackEffectObjC:(NSInteger)trackRow path:(NSString *)pluginPath;
+ (void)removeTrackEffectObjC:(NSInteger)trackRow effectIndex:(NSInteger)effectIndex;
+ (void)reorderTrackEffectsObjC:(NSInteger)trackRow
                      fromIndex:(NSInteger)fromIdx
                        toIndex:(NSInteger)toIdx;
+ (NSArray<NSString *> *)getTrackEffectsForRowObjC:(NSInteger)trackRow;
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
+ (void)setRowGainObjC:(NSInteger)row gain:(float)gain;
+ (void)muteRowObjC:(NSInteger)row shouldMute:(BOOL)shouldMute;
+ (bool)isRowMutedObjC:(NSInteger)row;
+ (void)setRowPanObjC:(NSInteger)row pan:(float)pan;

// Master bus FX and controls
+ (void)insertMasterEffectObjC:(NSString *)pluginPath;
+ (void)removeMasterEffectObjC:(NSInteger)effectIndex;
+ (void)reorderMasterEffectsObjC:(NSInteger)fromIndex
                         toIndex:(NSInteger)toIndex;
+ (NSArray<NSString *> *)getMasterEffectsObjC;
+ (NSArray<NSDictionary *> *)getMasterPluginParametersObjC:(NSInteger)effect;
+ (void)setMasterEffectObjC:(NSInteger)effectIndex
                    paramId:(NSString *)param
                      value:(id)value;
+ (void)bypassMasterEffectObjC:(NSInteger)effectIndex
                        bypass:(BOOL)shouldBypass;
+ (bool)getMasterEffectBypassStateObjC:(NSInteger)effectIndex;
+ (void)setMasterGainObjC:(float)gain;
+ (void)muteMasterObjC:(BOOL)shouldMute;
+ (void)setMasterPanObjC:(float)pan;

// Automation (rows)
+ (void)setTrackAutomationPointsObjC:(NSInteger)trackRow
                              points:(NSArray<NSDictionary *> *)points;
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

+ (NSArray<NSString *> *)getInputDevicesObjC;
+ (BOOL)selectInputDeviceObjC:(NSString *)name;

+ (NSNumber *)getNumInputChannelsObjC;
+ (NSString *)getCurrentDeviceNameObjC;

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

@end