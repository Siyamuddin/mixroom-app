#import "JuceAudioEnginePlugin.h"
#import "JuceBridge.h"
#import "JuceLogBridge.h"  // Add this import
#import <Flutter/Flutter.h>

@interface JuceAudioEnginePlugin ()
@property (nonatomic, copy) FlutterEventSink eventSink;
@end

@implementation JuceAudioEnginePlugin


// for printing logs
static JuceAudioEnginePlugin* _sharedInstance = nil;

+ (instancetype)sharedInstance {
    return _sharedInstance;
}

- (void)sendFlutterLog:(NSString*)message {
    if (self.eventSink) {
        self.eventSink(@{ @"message": message });
    }
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

    [registrar addMethodCallDelegate:_sharedInstance channel:channel];
    [logChannel setStreamHandler:_sharedInstance];

    // [JuceBridge initialiseEngineObjC];
}

- (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(FlutterEventSink)events {
    self.eventSink = events;
    return nil;
}

- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    self.eventSink = nil;
    return nil;
}


- (void)handleMethodCall:(FlutterMethodCall*)call
                  result:(FlutterResult)result {
    NSDictionary* args = call.arguments;

    if ([call.method isEqualToString:@"initialise"]) {
        [JuceBridge initialiseEngineObjC]; result(nil);
    } else if ([call.method isEqualToString:@"getPlatformVersion"]) {
        result([@"iOS " stringByAppendingString:UIDevice.currentDevice.systemVersion]);

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
    } else if ([call.method isEqualToString:@"exportMix"]) {
        NSString* out = [JuceBridge exportMixObjC:args[@"outPath"]];
        result(out);
    } else if ([call.method isEqualToString:@"exportTrack"]) {
        NSInteger track = [args[@"track"] integerValue];
        NSString* out = [JuceBridge exportTrackObjC:track outPath:args[@"outPath"]];
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
    } else if ([call.method isEqualToString:@"loadClip"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        NSInteger row  = [args[@"row"] integerValue];
        NSString *path = args[@"path"];
        [JuceBridge loadClipObjC:clip rowIndex:row path:path];
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
    } else if ([call.method isEqualToString:@"muteClip"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        BOOL mute      = [args[@"mute"] boolValue];
        [JuceBridge muteClipObjC:clip shouldMute:mute];
        result(nil);
    } else if ([call.method isEqualToString:@"moveClipToRow"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        NSInteger row  = [args[@"row"] integerValue];
        [JuceBridge moveClipToRowObjC:clip newRow:row];
        result(nil);

    // ----------------------------------------
    // NEW ROW (TRACK BUS) API
    // ----------------------------------------
    } else if ([call.method isEqualToString:@"insertTrackEffect"]) {
        NSInteger row = [args[@"row"] integerValue];
        NSString *path = args[@"path"];
        [JuceBridge insertTrackEffectObjC:row path:path];
        result(nil);
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

    // ----------------------------------------
    // NEW MASTER BUS API
    // ----------------------------------------
    } else if ([call.method isEqualToString:@"insertMasterEffect"]) {
        NSString *path = args[@"path"];
        [JuceBridge insertMasterEffectObjC:path];
        result(nil);
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
    } else if ([call.method isEqualToString:@"setMasterGain"]) {
        float gain = [args[@"gain"] floatValue];
        [JuceBridge setMasterGainObjC:gain];
        result(nil);
    } else if ([call.method isEqualToString:@"muteMaster"]) {
        BOOL mute = [args[@"mute"] boolValue];
        [JuceBridge muteMasterObjC:mute];
        result(nil);
    } else if ([call.method isEqualToString:@"setMasterPan"]) {
        float pan = [args[@"pan"] floatValue];
        [JuceBridge setMasterPanObjC:pan];
        result(nil);

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
    } else if ([call.method isEqualToString:@"getInputDevices"]) {
    result([JuceBridge getInputDevicesObjC]);
    }
    else if ([call.method isEqualToString:@"selectInputDevice"]) {
        result(@([JuceBridge selectInputDeviceObjC:args[@"name"]]));
    }
    else if ([call.method isEqualToString:@"getNumInputChannels"]) {
        result([JuceBridge getNumInputChannelsObjC]);
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
