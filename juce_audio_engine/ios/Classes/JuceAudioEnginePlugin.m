#import "JuceAudioEnginePlugin.h"
#import "JuceBridge.h"
#import "JuceLogBridge.h"  // Add this import
#import <TargetConditionals.h>

#if __has_include(<Flutter/Flutter.h>)
#import <Flutter/Flutter.h>
#elif __has_include(<FlutterMacOS/FlutterMacOS.h>)
#import <FlutterMacOS/FlutterMacOS.h>
#endif

@class JuceAudioEnginePlugin;

@interface JucePluginEventStreamHandler : NSObject <FlutterStreamHandler>
- (instancetype)initWithPlugin:(JuceAudioEnginePlugin *)plugin;
@end

@interface JuceAudioEnginePlugin ()
@property (nonatomic, copy) FlutterEventSink eventSink;
@property (nonatomic, copy) FlutterEventSink logSink;
- (void)bindEventSink:(FlutterEventSink)events;
- (void)clearEventSink;
@end

@implementation JuceAudioEnginePlugin


// for printing logs
static JuceAudioEnginePlugin* _sharedInstance = nil;

+ (instancetype)sharedInstance {
    return _sharedInstance;
}

- (BOOL)hasActiveLogListener {
    return self.logSink != nil;
}

- (void)sendFlutterLog:(NSString*)message {
    if (self.logSink) {
        self.logSink(@{ @"message": message });
    }
}

- (void)bindEventSink:(FlutterEventSink)events {
    self.eventSink = events;
}

- (void)clearEventSink {
    self.eventSink = nil;
}

- (void)handlePluginLoadedNotification:(NSNotification *)notification {
    if (!self.eventSink) {
        return;
    }
    NSDictionary *payload = notification.userInfo;
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return;
    }
    self.eventSink(payload);
}

// end for printing logs

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    NSLog(@"✅ JuceAudioEnginePlugin registered");
    [JuceBridge initializeMessageManager];
    

    FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"juce_audio_engine"
            binaryMessenger:[registrar messenger]];

    FlutterEventChannel* eventChannel = [FlutterEventChannel
      eventChannelWithName:@"juce_audio_engine/events"
           binaryMessenger:[registrar messenger]];

    FlutterEventChannel* logChannel = [FlutterEventChannel
        eventChannelWithName:@"juce_audio_engine/logs"
             binaryMessenger:[registrar messenger]];


    _sharedInstance = [JuceAudioEnginePlugin new];
    JucePluginEventStreamHandler *eventHandler =
        [[JucePluginEventStreamHandler alloc] initWithPlugin:_sharedInstance];

    [registrar addMethodCallDelegate:_sharedInstance channel:channel];
    [eventChannel setStreamHandler:eventHandler];
    [logChannel setStreamHandler:_sharedInstance];
    [[NSNotificationCenter defaultCenter] addObserver:_sharedInstance
                                             selector:@selector(handlePluginLoadedNotification:)
                                                 name:@"JUCEPluginLoaded"
                                               object:nil];

    // [JuceBridge initialiseEngineObjC];
}

- (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(FlutterEventSink)events {
    self.logSink = events;
    return nil;
}

- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    self.logSink = nil;
    return nil;
}


- (void)handleMethodCall:(FlutterMethodCall*)call
                  result:(FlutterResult)result {
    NSDictionary* args = call.arguments;

    if ([call.method isEqualToString:@"initialise"]) {
        [JuceBridge initialiseEngineObjC]; result(nil);
    } else if ([call.method isEqualToString:@"getPlatformVersion"]) {
#if TARGET_OS_OSX
        result([@"macOS " stringByAppendingString:NSProcessInfo.processInfo.operatingSystemVersionString]);
#else
        result([@"iOS " stringByAppendingString:UIDevice.currentDevice.systemVersion]);
#endif

    // ----------------------------------------
    // LEGACY / CLIP-INDEXED API (still used)
    // ----------------------------------------
    } else if ([call.method isEqualToString:@"loadTrack"]) {
        [JuceBridge loadTrackObjC:[args[@"index"] integerValue]
                             path:args[@"path"]]; result(nil);
    } else if ([call.method isEqualToString:@"removeTrack"]) {
        [JuceBridge removeTrackObjC:[args[@"track"] integerValue]];
        result(nil);
    } else if ([call.method isEqualToString:@"getTrackEffects"]) {
        result([JuceBridge getTrackEffectsObjC:[args[@"track"] integerValue]]);
    } else if ([call.method isEqualToString:@"removeEffect"]) {
        [JuceBridge removeEffectObjC:[args[@"track"] integerValue]
                         effectIndex:[args[@"effect"] integerValue]];
        result(nil);
    } else if ([call.method isEqualToString:@"reorderEffects"]) {
        [JuceBridge reorderEffectsObjC:[args[@"track"] integerValue]
                             fromIndex:[args[@"from"] integerValue]
                               toIndex:[args[@"to"]   integerValue]];
        result(nil);
    } else if ([call.method isEqualToString:@"seek"]) {
        [JuceBridge seekObjC:[args[@"track"] integerValue]
                    position:[args[@"position"] doubleValue]];
        result(nil);
    } else if ([call.method isEqualToString:@"getCurrentPosition"]) {
        double pos = [JuceBridge getCurrentPositionObjC:[args[@"track"] integerValue]];
        result(@(pos));
    } else if ([call.method isEqualToString:@"getTrackDuration"]) {
        double dur = [JuceBridge getTrackDurationObjC:[args[@"track"] integerValue]];
        result(@(dur));
    } else if ([call.method isEqualToString:@"play"]) {
        [JuceBridge playObjC]; result(nil);
    } else if ([call.method isEqualToString:@"pause"]) {
        [JuceBridge pauseObjC]; result(nil);
    } else if ([call.method isEqualToString:@"insertEffect"]) {
        [JuceBridge insertEffectObjC:[args[@"track"] integerValue]
                                 path:args[@"path"]]; result(nil);
    } else if ([call.method isEqualToString:@"setEffect"]) {
        NSInteger trackIdx = [args[@"track"] integerValue];
        NSInteger fxIdx    = [args[@"pluginIndex"] integerValue];
        NSString *paramId  = args[@"paramId"];
        id     v        = args[@"value"];

        [JuceBridge setEffectObjC:      trackIdx
                    pluginIndex:      fxIdx
                        paramId:      paramId
                           value:      v];
        result(nil);
    } else if ([call.method isEqualToString:@"setTrackVolume"]) {
        [JuceBridge setTrackVolumeObjC:[args[@"track"] integerValue]
                               volume:[args[@"volume"] floatValue]];
        result(nil);
    } else if ([call.method isEqualToString:@"getPluginParameters"]) {
        NSDictionary* args2   = call.arguments;
        NSInteger track      = [args2[@"track"] integerValue];
        NSInteger effectIdx  = [args2[@"effect"] integerValue];
        result([JuceBridge getPluginParametersObjC:track effectIndex:effectIdx]);
    } else if ([call.method isEqualToString:@"getTrackPluginParameters"]) {
        NSInteger row    = [call.arguments[@"row"] integerValue];
        NSInteger effect = [call.arguments[@"effect"] integerValue];
        NSArray* arr = [JuceBridge getTrackPluginParametersObjC:row effectIndex:effect];
        result(arr);
    } else if ([call.method isEqualToString:@"getMasterPluginParameters"]) {
        NSInteger effect = [call.arguments[@"effect"] integerValue];
        NSArray* arr = [JuceBridge getMasterPluginParametersObjC:effect];
        result(arr);
    } else if ([call.method isEqualToString:@"scanPlugins"]) {
        NSArray* plugins = [JuceBridge scanPluginsObjC];
        result(plugins);
    } else if ([call.method isEqualToString:@"getEngineCapabilities"]) {
#if TARGET_OS_OSX
        result(@{
            @"externalPluginHosting": @YES,
            @"supportedPluginFormats": @[@"AU", @"VST3"],
            @"nativePluginEditor": @NO
        });
#else
        result(@{
            @"externalPluginHosting": @NO,
            @"supportedPluginFormats": @[],
            @"nativePluginEditor": @NO
        });
#endif
    } else if ([call.method isEqualToString:@"exportMix"]) {
        NSString* out = [JuceBridge exportMixObjC:args[@"outPath"] settings:args];
        result(out);
    } else if ([call.method isEqualToString:@"exportTrack"]) {
        NSInteger track = [args[@"track"] integerValue];
        NSString* out = [JuceBridge exportTrackObjC:track outPath:args[@"outPath"] settings:args];
        result(out);
    } else if ([call.method isEqualToString:@"renderInstrumentClip"]) {
        NSString *outPath = args[@"outPath"] ?: @"";
        NSString *instrumentId = args[@"instrumentId"] ?: @"mixroom.basic_synth";
        NSString *instrumentName = args[@"instrumentName"] ?: @"Basic Synth";
        double bpm = [args[@"bpm"] doubleValue];
        NSArray *notes = args[@"notes"] ?: @[];
        NSDictionary *params = args[@"params"] ?: @{};
        NSString *out = [JuceBridge renderInstrumentClipObjC:outPath
                                                instrumentId:instrumentId
                                              instrumentName:instrumentName
                                                         bpm:bpm
                                                       notes:notes
                                                      params:params];
        result(out);
    } else if ([call.method isEqualToString:@"bypassPlugin"]) {
        NSDictionary* a = call.arguments;
        [JuceBridge bypassPluginObjC:
            [a[@"track"]  integerValue]
                        effectIndex:[a[@"effect"] integerValue]
                             bypass:[a[@"bypass"] boolValue]];
        result(nil);
    } else if ([call.method isEqualToString:@"bypassTrack"]) {
        [JuceBridge bypassTrackObjC:
            [args[@"track"] integerValue]
                        shouldBypass:[args[@"bypass"] boolValue]];
        result(nil);
    } else if ([call.method isEqualToString:@"getPluginBypassState"]) {
        BOOL bypassState = [JuceBridge getPluginBypassStateObjC:
            [args[@"track"] integerValue]
                        effectIndex:[args[@"effect"] integerValue]];
        NSNumber *out = [NSNumber numberWithBool:bypassState];
        result(out);

    // ----------------------------------------
    // ENGINE LIFECYCLE / INTERNAL
    // ----------------------------------------
    } else if ([call.method isEqualToString:@"_internalLog"]) {
        result(@"testing blabla success");
    } else if ([call.method isEqualToString:@"shutdown"]) {
        [JuceBridge shutdownEngineObjC];
        result(nil);

    // ----------------------------------------
    // VIDEO AUDIO LANE
    // ----------------------------------------
    } else if ([call.method isEqualToString:@"loadVideoAudio"]) {
        NSString* path = args[@"path"];
        [JuceBridge loadVideoAudioObjC:path];
        result(nil);
    } else if ([call.method isEqualToString:@"unloadVideoAudio"]) {
        [JuceBridge unloadVideoAudioObjC];
        result(nil);
    } else if ([call.method isEqualToString:@"setVideoAudioGain"]) {
        NSNumber* g = args[@"gain"];
        [JuceBridge setVideoAudioGainObjC:[g floatValue]];
        result(nil);
    } else if ([call.method isEqualToString:@"seekVideoAudio"]) {
        NSNumber* sec = args[@"seconds"];
        [JuceBridge seekVideoAudioObjC:[sec doubleValue]];
        result(nil);

    // ----------------------------------------
    // NEW CLIP-LEVEL API
    // ----------------------------------------
    } else if ([call.method isEqualToString:@"supportsLiveMidiClipPlayback"]) {
        result(@([JuceBridge supportsLiveMidiClipPlaybackObjC]));
    } else if ([call.method isEqualToString:@"loadMidiClip"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        NSInteger rowId = [args[@"rowId"] integerValue];
        if (args[@"row"] != nil) rowId = [args[@"row"] integerValue];
        NSString *instrumentId = args[@"instrumentId"] ?: @"mixroom.basic_synth";
        NSString *instrumentName = args[@"instrumentName"] ?: @"Basic Synth";
        NSArray *notes = args[@"notes"] ?: @[];
        NSDictionary *params = args[@"params"] ?: @{};
        double sourceTempoBpm = [args[@"sourceTempoBpm"] doubleValue];
        double startSec = [args[@"startSec"] doubleValue];
        double lengthSec = [args[@"lengthSec"] doubleValue];
        double inFileOffsetSec = [args[@"inFileOffsetSec"] doubleValue];
        BOOL ok = [JuceBridge loadMidiClipObjC:clip
                                         rowId:rowId
                                  instrumentId:instrumentId
                                instrumentName:instrumentName
                                         notes:notes
                                        params:params
                                sourceTempoBpm:sourceTempoBpm
                                      startSec:startSec
                                     lengthSec:lengthSec
                               inFileOffsetSec:inFileOffsetSec];
        result(@(ok));
    } else if ([call.method isEqualToString:@"updateMidiClipEvents"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        NSString *instrumentId = args[@"instrumentId"] ?: @"mixroom.basic_synth";
        NSString *instrumentName = args[@"instrumentName"] ?: @"Basic Synth";
        NSArray *notes = args[@"notes"] ?: @[];
        NSDictionary *params = args[@"params"] ?: @{};
        double sourceTempoBpm = [args[@"sourceTempoBpm"] doubleValue];
        BOOL ok = [JuceBridge updateMidiClipObjC:clip
                                     instrumentId:instrumentId
                                   instrumentName:instrumentName
                                            notes:notes
                                           params:params
                                   sourceTempoBpm:sourceTempoBpm];
        result(@(ok));
    } else if ([call.method isEqualToString:@"setLiveMidiInputTargetClip"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        result(@([JuceBridge setLiveMidiInputTargetClipObjC:clip]));
    } else if ([call.method isEqualToString:@"consumeLiveMidiInputEvents"]) {
        result([JuceBridge consumeLiveMidiInputEventsObjC]);
    } else if ([call.method isEqualToString:@"getConnectedMidiInputDevices"]) {
        result([JuceBridge getConnectedMidiInputDevicesObjC]);
    } else if ([call.method isEqualToString:@"loadClip"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        NSInteger rowId  = [args[@"rowId"] integerValue];
        if (args[@"row"] != nil) rowId = [args[@"row"] integerValue]; // backward compat
        NSString *path = args[@"path"];
        double startSec = [args[@"startSec"] doubleValue];
        double lengthSec = [args[@"lengthSec"] doubleValue];
        double inFileOffsetSec = [args[@"inFileOffsetSec"] doubleValue];
        [JuceBridge loadClipObjC:clip
                           rowId:rowId
                            path:path
                        startSec:startSec
                       lengthSec:lengthSec
                 inFileOffsetSec:inFileOffsetSec];
        result(nil);
    } else if ([call.method isEqualToString:@"unloadClip"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        [JuceBridge unloadClipObjC:clip];
        result(nil);
    } else if ([call.method isEqualToString:@"setClipGain"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        float gain     = [args[@"gain"] floatValue];
        [JuceBridge setClipGainObjC:clip gain:gain];
        result(nil);
    } else if ([call.method isEqualToString:@"setClipPan"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        float pan      = [args[@"pan"] floatValue];
        [JuceBridge setClipPanObjC:clip pan:pan];
        result(nil);
    } else if ([call.method isEqualToString:@"setClipPitch"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        float semitones = [args[@"semitones"] floatValue];
        [JuceBridge setClipPitchObjC:clip semitones:semitones];
        result(nil);
    } else if ([call.method isEqualToString:@"setClipReversed"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        BOOL reversed = [args[@"reversed"] boolValue];
        [JuceBridge setClipReversedObjC:clip reversed:reversed];
        result(nil);
    } else if ([call.method isEqualToString:@"setClipStretchOptions"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        double tempoRatio = [args[@"tempoRatio"] doubleValue];
        BOOL preservePitch = [args[@"preservePitch"] boolValue];
        [JuceBridge setClipStretchOptionsObjC:clip
                                   tempoRatio:tempoRatio
                                preservePitch:preservePitch];
        result(nil);
    } else if ([call.method isEqualToString:@"muteClip"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        BOOL mute      = [args[@"mute"] boolValue];
        [JuceBridge muteClipObjC:clip shouldMute:mute];
        result(nil);
    } else if ([call.method isEqualToString:@"moveClipToRow"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        NSInteger rowId  = [args[@"rowId"] integerValue];
        if (args[@"row"] != nil) rowId = [args[@"row"] integerValue]; // backward compat
        [JuceBridge moveClipToRowObjC:clip newRowId:rowId];
        result(nil);
    } else if ([call.method isEqualToString:@"setClipTime"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        double startSec = [args[@"startSec"] doubleValue];
        double lengthSec = [args[@"lengthSec"] doubleValue];
        double inFileOffsetSec = [args[@"inFileOffsetSec"] doubleValue];
        [JuceBridge setClipTimeObjC:clip
                           startSec:startSec
                          lengthSec:lengthSec
                    inFileOffsetSec:inFileOffsetSec];
        result(nil);
    } else if ([call.method isEqualToString:@"addRow"]) {
        NSString *name = args[@"name"] ?: @"Row";
        NSInteger iconId = [args[@"iconId"] integerValue];
        result([JuceBridge addRowObjC:name iconId:iconId]);
    } else if ([call.method isEqualToString:@"insertRowAbove"]) {
        NSInteger referenceRowId = [args[@"referenceRowId"] integerValue];
        NSString *name = args[@"name"] ?: @"Row";
        NSInteger iconId = [args[@"iconId"] integerValue];
        result([JuceBridge insertRowAboveObjC:referenceRowId name:name iconId:iconId]);
    } else if ([call.method isEqualToString:@"insertRowBelow"]) {
        NSInteger referenceRowId = [args[@"referenceRowId"] integerValue];
        NSString *name = args[@"name"] ?: @"Row";
        NSInteger iconId = [args[@"iconId"] integerValue];
        result([JuceBridge insertRowBelowObjC:referenceRowId name:name iconId:iconId]);
    } else if ([call.method isEqualToString:@"deleteRow"] || [call.method isEqualToString:@"removeRow"]) {
        NSInteger rowId = [args[@"rowId"] integerValue];
        if (args[@"row"] != nil) rowId = [args[@"row"] integerValue];
        result(@([JuceBridge removeRowObjC:rowId]));
    } else if ([call.method isEqualToString:@"moveRowOrder"]) {
        NSInteger from = [args[@"from"] integerValue];
        NSInteger to = [args[@"to"] integerValue];
        result(@([JuceBridge moveRowOrderObjC:from toIndex:to]));
    } else if ([call.method isEqualToString:@"renameRow"]) {
        NSInteger rowId = [args[@"rowId"] integerValue];
        if (args[@"row"] != nil) rowId = [args[@"row"] integerValue];
        NSString *name = args[@"name"] ?: @"Row";
        result(@([JuceBridge renameRowObjC:rowId name:name]));
    } else if ([call.method isEqualToString:@"setRowIcon"]) {
        NSInteger rowId = [args[@"rowId"] integerValue];
        if (args[@"row"] != nil) rowId = [args[@"row"] integerValue];
        NSInteger iconId = [args[@"iconId"] integerValue];
        result(@([JuceBridge setRowIconObjC:rowId iconId:iconId]));
    } else if ([call.method isEqualToString:@"getRowList"] || [call.method isEqualToString:@"getRows"]) {
        result([JuceBridge getRowsObjC]);
    } else if ([call.method isEqualToString:@"setTransportSeconds"]) {
        double t = [args[@"timeSeconds"] doubleValue];
        [JuceBridge setTransportSecondsObjC:t];
        result(nil);
    } else if ([call.method isEqualToString:@"getTransportSeconds"]) {
        result(@([JuceBridge getTransportSecondsObjC]));
    } else if ([call.method isEqualToString:@"seekTransport"]) {
        double t = [args[@"timeSeconds"] doubleValue];
        [JuceBridge setTransportSecondsObjC:t];
        result(nil);

    // ----------------------------------------
    // NEW ROW (TRACK BUS) API
    // ----------------------------------------
    } else if ([call.method isEqualToString:@"insertTrackEffect"]) {
        NSInteger row = [args[@"row"] integerValue];
        NSString *path = args[@"path"];
        BOOL ok = [JuceBridge insertTrackEffectObjC:row path:path];
        if (ok) {
            result(@(YES));
        } else {
            result([FlutterError errorWithCode:@"insert_track_effect_failed"
                                       message:@"Failed to insert row effect"
                                       details:@{@"row": @(row), @"path": path ?: @""}]);
        }
    } else if ([call.method isEqualToString:@"removeTrackEffect"]) {
        NSInteger row = [args[@"row"] integerValue];
        NSInteger effect = [args[@"effect"] integerValue];
        [JuceBridge removeTrackEffectObjC:row effectIndex:effect];
        result(nil);
    } else if ([call.method isEqualToString:@"reorderTrackEffects"]) {
        NSInteger row  = [args[@"row"] integerValue];
        NSInteger from = [args[@"from"] integerValue];
        NSInteger to   = [args[@"to"] integerValue];
        [JuceBridge reorderTrackEffectsObjC:row fromIndex:from toIndex:to];
        result(nil);
    } else if ([call.method isEqualToString:@"getTrackEffectsForRow"]) {
        NSInteger row = [args[@"row"] integerValue];
        result([JuceBridge getTrackEffectsForRowObjC:row]);
    } else if ([call.method isEqualToString:@"getTrackEffectIdsForRow"]) {
        NSInteger row = [args[@"row"] integerValue];
        result([JuceBridge getTrackEffectIdsForRowObjC:row]);
    } else if ([call.method isEqualToString:@"getTrackEffectInstanceIdsForRow"]) {
        NSInteger row = [args[@"row"] integerValue];
        result([JuceBridge getTrackEffectInstanceIdsForRowObjC:row]);
    } else if ([call.method isEqualToString:@"setTrackEffect"]) {
        NSInteger row    = [args[@"row"] integerValue];
        NSInteger effect = [args[@"effect"] integerValue];
        NSString *param  = args[@"paramId"];
        id value         = args[@"value"];
        [JuceBridge setTrackEffectObjC:row
                           effectIndex:effect
                               paramId:param
                                 value:value];
        result(nil);
    } else if ([call.method isEqualToString:@"bypassRowEffect"]) {
        NSInteger row = [args[@"row"] integerValue];
        NSInteger effect = [args[@"effect"] integerValue];
        BOOL bypass = [args[@"bypass"] boolValue];
        [JuceBridge bypassRowEffectObjC:row effectIndex:effect bypass:bypass];
        result(nil);
    } else if ([call.method isEqualToString:@"getRowEffectBypassState"]) {
        NSInteger row = [args[@"row"] integerValue];
        NSInteger effect = [args[@"effect"] integerValue];
        BOOL state = [JuceBridge getRowEffectBypassStateObjC:row effectIndex:effect];
        result(@(state));
    } else if ([call.method isEqualToString:@"setTrackAutomationPoints"]) {
        // points: List<Map<String, double>> from Dart
        NSArray *points = args[@"points"];
        NSInteger row   = [args[@"row"] integerValue];
        [JuceBridge setTrackAutomationPointsObjC:row points:points];
        result(nil);
    } else if ([call.method isEqualToString:@"setTrackEffectAutomationPoints"]) {
        NSArray *points = args[@"points"];
        NSInteger row = [args[@"row"] integerValue];
        NSInteger effect = [args[@"effect"] integerValue];
        NSString *param = args[@"paramId"];
        double minValue = [args[@"min"] doubleValue];
        double maxValue = [args[@"max"] doubleValue];
        [JuceBridge setTrackEffectAutomationPointsObjC:row
                                           effectIndex:effect
                                               paramId:param
                                              minValue:minValue
                                              maxValue:maxValue
                                                points:points];
        result(nil);
    } else if ([call.method isEqualToString:@"clearTrackEffectAutomationForRow"]) {
        NSInteger row = [args[@"row"] integerValue];
        [JuceBridge clearTrackEffectAutomationForRowObjC:row];
        result(nil);
    } else if ([call.method isEqualToString:@"setRowGainAutomationPoints"]) {
        NSInteger row = [args[@"row"] integerValue];
        NSArray *points = args[@"points"];
        [JuceBridge setRowGainAutomationPointsObjC:row points:points];
        result(nil);
    } else if ([call.method isEqualToString:@"setRowGain"]) {
        NSInteger row = [args[@"row"] integerValue];
        float gain    = [args[@"gain"] floatValue];
        [JuceBridge setRowGainObjC:row gain:gain];
        result(nil);
    } else if ([call.method isEqualToString:@"muteRow"]) {
        NSInteger row = [args[@"row"] integerValue];
        BOOL mute     = [args[@"mute"] boolValue];
        [JuceBridge muteRowObjC:row shouldMute:mute];
        result(nil);
    } else if ([call.method isEqualToString:@"isRowMuted"]) {
        NSInteger row = [args[@"row"] integerValue];
        BOOL muted    = [JuceBridge isRowMutedObjC:row];
        result(@(muted));
    } else if ([call.method isEqualToString:@"setRowPan"]) {
        NSInteger row = [args[@"row"] integerValue];
        float pan     = [args[@"pan"] floatValue];
        [JuceBridge setRowPanObjC:row pan:pan];
        result(nil);
    } else if ([call.method isEqualToString:@"setRowPanAutomationPoints"]) {
        NSInteger row = [args[@"row"] integerValue];
        NSArray *points = args[@"points"];
        [JuceBridge setRowPanAutomationPointsObjC:row points:points];
        result(nil);

    // ----------------------------------------
    // NEW MASTER BUS API
    // ----------------------------------------
    } else if ([call.method isEqualToString:@"insertMasterEffect"]) {
        NSString *path = args[@"path"];
        BOOL ok = [JuceBridge insertMasterEffectObjC:path];
        if (ok) {
            result(@(YES));
        } else {
            result([FlutterError errorWithCode:@"insert_master_effect_failed"
                                       message:@"Failed to insert master effect"
                                       details:@{@"path": path ?: @""}]);
        }
    } else if ([call.method isEqualToString:@"removeMasterEffect"]) {
        NSInteger effect = [args[@"effect"] integerValue];
        [JuceBridge removeMasterEffectObjC:effect];
        result(nil);
    } else if ([call.method isEqualToString:@"reorderMasterEffects"]) {
        NSInteger from = [args[@"from"] integerValue];
        NSInteger to   = [args[@"to"] integerValue];
        [JuceBridge reorderMasterEffectsObjC:from toIndex:to];
        result(nil);
    } else if ([call.method isEqualToString:@"getMasterEffects"]) {
        result([JuceBridge getMasterEffectsObjC]);
    } else if ([call.method isEqualToString:@"getMasterEffectIds"]) {
        result([JuceBridge getMasterEffectIdsObjC]);
    } else if ([call.method isEqualToString:@"setMasterEffect"]) {
        NSInteger effect = [args[@"effect"] integerValue];
        NSString *param  = args[@"paramId"];
        id value         = args[@"value"];
        [JuceBridge setMasterEffectObjC:effect paramId:param value:value];
        result(nil);
    } else if ([call.method isEqualToString:@"bypassMasterEffect"]) {
        NSInteger effect = [args[@"effect"] integerValue];
        BOOL bypass      = [args[@"bypass"] boolValue];
        [JuceBridge bypassMasterEffectObjC:effect bypass:bypass];
        result(nil);
    } else if ([call.method isEqualToString:@"getMasterEffectBypassState"]) {
        NSInteger effect = [args[@"effect"] integerValue];
        BOOL state       = [JuceBridge getMasterEffectBypassStateObjC:effect];
        result(@(state));
    } else if ([call.method isEqualToString:@"setMasterEffectAutomationPoints"]) {
        NSInteger effect = [args[@"effect"] integerValue];
        NSString *param = args[@"paramId"];
        double minValue = [args[@"min"] doubleValue];
        double maxValue = [args[@"max"] doubleValue];
        NSArray *points = args[@"points"];
        [JuceBridge setMasterEffectAutomationPointsObjC:effect
                                              paramId:param
                                             minValue:minValue
                                             maxValue:maxValue
                                               points:points];
        result(nil);
    } else if ([call.method isEqualToString:@"clearMasterEffectAutomation"]) {
        [JuceBridge clearMasterEffectAutomationObjC];
        result(nil);
    } else if ([call.method isEqualToString:@"setMasterGainAutomationPoints"]) {
        NSArray *points = args[@"points"];
        [JuceBridge setMasterGainAutomationPointsObjC:points];
        result(nil);
    } else if ([call.method isEqualToString:@"setMasterGain"]) {
        float gain = [args[@"gain"] floatValue];
        [JuceBridge setMasterGainObjC:gain];
        result(nil);
    } else if ([call.method isEqualToString:@"muteMaster"]) {
        BOOL mute = [args[@"mute"] boolValue];
        [JuceBridge muteMasterObjC:mute];
        result(nil);
    } else if ([call.method isEqualToString:@"setMasterPanAutomationPoints"]) {
        NSArray *points = args[@"points"];
        [JuceBridge setMasterPanAutomationPointsObjC:points];
        result(nil);
    } else if ([call.method isEqualToString:@"setMasterPan"]) {
        float pan = [args[@"pan"] floatValue];
        [JuceBridge setMasterPanObjC:pan];
        result(nil);

    } 
    // ===============================
    // MASTER METER
    // ===============================
    else if ([call.method isEqualToString:@"setMasterMeterEnabled"]) {
        BOOL enabled = [call.arguments[@"enabled"] boolValue];
        [JuceBridge setMasterMeterEnabledObjC:enabled];
        result(nil);
    }
    else if ([call.method isEqualToString:@"getMasterMeterValues"]) {
        NSArray* arr = [JuceBridge getMasterMeterValuesObjC];
        result(arr);
    }
    else if ([call.method isEqualToString:@"getMasterClipLatched"]) {
        BOOL latched = [JuceBridge getMasterClipLatchedObjC];
        result(@(latched));
    }
    else if ([call.method isEqualToString:@"clearMasterClipLatched"]) {
        [JuceBridge clearMasterClipLatchedObjC];
        result(nil);
    }

    // ===============================
    // ROW METERS
    // ===============================
    else if ([call.method isEqualToString:@"setRowMetersEnabled"]) {
        BOOL enabled = [call.arguments[@"enabled"] boolValue];
        [JuceBridge setRowMetersEnabledObjC:enabled];
        result(nil);
    }
    else if ([call.method isEqualToString:@"getRowMeterValues"]) {
        NSInteger row = [call.arguments[@"row"] integerValue];
        NSArray* arr = [JuceBridge getRowMeterValuesObjC:row];
        result(arr);
    }
    else if ([call.method isEqualToString:@"getAllMeterValues"]) {
        NSArray<NSNumber*>* arr = [JuceBridge getAllMeterValues];
        result(arr);
        return;
    }

    // ===============================
    // COMPRESSOR METER STRIPS
    // returns [inRmsL, inRmsR, grDb, outRmsL, outRmsR]
    // ===============================
    else if ([call.method isEqualToString:@"getClipCompressorMeter"]) {
        NSInteger clip = [call.arguments[@"clip"] integerValue];
        NSInteger effect = [call.arguments[@"effect"] integerValue];
        NSArray* arr = [JuceBridge getClipCompressorMeterObjC:clip effectIndex:effect];
        result(arr);
    }
    else if ([call.method isEqualToString:@"getRowCompressorMeter"]) {
        NSInteger row = [call.arguments[@"row"] integerValue];
        NSInteger effect = [call.arguments[@"effect"] integerValue];
        NSArray* arr = [JuceBridge getRowCompressorMeterObjC:row effectIndex:effect];
        result(arr);
    }
    else if ([call.method isEqualToString:@"getMasterCompressorMeter"]) {
        NSInteger effect = [call.arguments[@"effect"] integerValue];
        NSArray* arr = [JuceBridge getMasterCompressorMeterObjC:effect];
        result(arr);
    }
    else if ([call.method isEqualToString:@"getHostSampleRate"]) {
        double sr = [JuceBridge getHostSampleRateObjC];
        result(@(sr));
    }
    else if ([call.method isEqualToString:@"getRowEqWaveform"]) {
        NSInteger row = [call.arguments[@"row"] integerValue];
        NSInteger effect = [call.arguments[@"effect"] integerValue];
        NSInteger sampleCount = [call.arguments[@"sampleCount"] integerValue];
        NSArray* arr = [JuceBridge getRowEqWaveformObjC:row effectIndex:effect sampleCount:sampleCount];
        result(arr);
    }
    else if ([call.method isEqualToString:@"getMasterEqWaveform"]) {
        NSInteger effect = [call.arguments[@"effect"] integerValue];
        NSInteger sampleCount = [call.arguments[@"sampleCount"] integerValue];
        NSArray* arr = [JuceBridge getMasterEqWaveformObjC:effect sampleCount:sampleCount];
        result(arr);


    // ----------------------------------------
    // TRANSPORT / DEBUG
    // ----------------------------------------
    } else if ([call.method isEqualToString:@"setAutomationTransport"]) {
        double t = [args[@"timeSeconds"] doubleValue];
        [JuceBridge setAutomationTransportObjC:t];
        result(nil);
    } else if ([call.method isEqualToString:@"debugPrintGraph"]) {
        NSString *title = args[@"title"] ?: @"(no title)";
        [JuceBridge debugPrintGraphObjC:title];
        result(nil);
    } else if ([call.method isEqualToString:@"debugPrintGraphStructure"]) {
        [JuceBridge debugPrintGraphStructureObjC];
        result(nil);
    } 
    else if ([call.method isEqualToString:@"setMetronomeEnabled"]) {
        [JuceBridge setMetronomeEnabledObjC:[args[@"enabled"] boolValue]];
        result(nil);
    }
    else if ([call.method isEqualToString:@"setMetronomeVolume"]) {
        [JuceBridge setMetronomeVolumeObjC:[args[@"volume"] floatValue]];
        result(nil);
    }
    else if ([call.method isEqualToString:@"setMetronomeBpm"]) {
        [JuceBridge setMetronomeBpmObjC:[args[@"bpm"] doubleValue]];
        result(nil);
    }
    else if ([call.method isEqualToString:@"setMetronomeTransportMs"]) {
        [JuceBridge setMetronomeTransportMsObjC:[args[@"ms"] doubleValue]];
        result(nil); 
    } 
    else if ([call.method isEqualToString:@"decodeAudioMono16k"]) {
        NSString *path = args[@"path"];
        NSArray *samples = [JuceBridge decodeAudioMono16kObjC:path];
        result(samples);
    } else if ([call.method isEqualToString:@"analyzeAudioStereo16k"]) {
        NSString *path = args[@"path"];
        NSDictionary *stats = [JuceBridge analyzeAudioStereo16kObjC:path];
        result(stats);
    } else if ([call.method isEqualToString:@"getInputDevices"]) {
    result([JuceBridge getInputDevicesObjC]);
    }
    else if ([call.method isEqualToString:@"selectInputDevice"]) {
        result(@([JuceBridge selectInputDeviceObjC:args[@"name"]]));
    }
    else if ([call.method isEqualToString:@"getNumInputChannels"]) {
        result([JuceBridge getNumInputChannelsObjC]);
    }
    else if ([call.method isEqualToString:@"prepareRecordingInputs"]) {
        NSInteger desiredInputChannels = [args[@"desiredInputChannels"] integerValue];
        NSString *reason = args[@"reason"] ?: @"dart";
        result(@([JuceBridge prepareRecordingInputsObjC:desiredInputChannels reason:reason]));
    }
    else if ([call.method isEqualToString:@"refreshAudioRoute"]) {
        NSString *reason = args[@"reason"] ?: @"dart";
        [JuceBridge refreshAudioRouteObjC:reason];
        result(nil);
    }
    else if ([call.method isEqualToString:@"getRecordingPeak"]) {
        result([JuceBridge getRecordingPeakObjC]);
    }
    else if ([call.method isEqualToString:@"getCurrentDeviceName"]) {
        result([JuceBridge getCurrentDeviceNameObjC]);
    }
    else if ([call.method isEqualToString:@"startRecording"]) {
        result(@([JuceBridge startRecordingObjC:args[@"path"]
                                channelStart:[args[@"channelStart"] integerValue]
                                channelCount:[args[@"channelCount"] integerValue]]));
    }
    else if ([call.method isEqualToString:@"stopRecording"]) {
        [JuceBridge stopRecordingObjC];
        result(nil);
    }
    else if ([call.method isEqualToString:@"isRecording"]) {
        result(@([JuceBridge isRecordingObjC]));
    } else {
        result(FlutterMethodNotImplemented);
    }
}


@end

@interface JucePluginEventStreamHandler ()
@property (nonatomic, assign) JuceAudioEnginePlugin *plugin;
@end

@implementation JucePluginEventStreamHandler

- (instancetype)initWithPlugin:(JuceAudioEnginePlugin *)plugin {
    self = [super init];
    if (self) {
        _plugin = plugin;
    }
    return self;
}

- (FlutterError * _Nullable)onListenWithArguments:(id _Nullable)arguments
                                        eventSink:(FlutterEventSink)events {
    [self.plugin bindEventSink:events];
    return nil;
}

- (FlutterError * _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    [self.plugin clearEventSink];
    return nil;
}

@end
