#import "JuceAudioEnginePlugin.h"
#import "JuceBridge.h"
#import "JuceLogBridge.h"  // Add this import
#import <AVFoundation/AVFoundation.h>
#import <TargetConditionals.h>
#if !TARGET_OS_OSX
#import "MixroomIOSCaptureLifecycleV2.h"
#endif

#if TARGET_OS_OSX
#import <CoreAudio/CoreAudio.h>
#import <mach/mach_time.h>
#else
#import <UIKit/UIKit.h>
#endif

#if __has_include(<Flutter/Flutter.h>)
#import <Flutter/Flutter.h>
#elif __has_include(<FlutterMacOS/FlutterMacOS.h>)
#import <FlutterMacOS/FlutterMacOS.h>
#endif

#if TARGET_OS_OSX
extern void mixroomScheduleOttPluginEditorAutotest(void);
#endif

#if !TARGET_OS_OSX
@interface MixroomIOSCaptureBridgeV2 : NSObject <MixroomIOSCaptureNativeV2>
@end
@implementation MixroomIOSCaptureBridgeV2
- (BOOL)isRecording { return [JuceBridge isRecordingObjC]; }
- (NSDictionary *)monitorFacts { return [JuceBridge getLiveInputMonitoringFactsV2ObjC]; }
- (BOOL)start:(NSString *)path channelStart:(NSInteger)start channelCount:(NSInteger)count {
    return [JuceBridge startRecordingObjC:path channelStart:start channelCount:count];
}
- (NSDictionary *)finalizePreservingMonitor:(BOOL)preserve {
    return preserve ? [JuceBridge finalizeRecordingForMonitoringV2ObjC] : [JuceBridge stopRecordingObjC];
}
- (void)discardPreservingMonitor:(BOOL)preserve {
    if (preserve) [JuceBridge discardRecordingForMonitoringV2ObjC];
    else [JuceBridge discardRecordingCaptureObjC];
}
@end
#endif

@class JuceAudioEnginePlugin;

@interface JucePluginEventStreamHandler : NSObject <FlutterStreamHandler>
- (instancetype)initWithPlugin:(JuceAudioEnginePlugin *)plugin;
@end

@interface JuceAudioEnginePlugin ()
@property (nonatomic, copy) FlutterEventSink eventSink;
@property (nonatomic, copy) FlutterEventSink logSink;
@property (atomic, assign) BOOL applicationTerminationStarted;
@property (nonatomic, assign) BOOL audioRouteMonitoringV2;
@property (atomic, assign) uint64_t audioRouteGenerationV2;
@property (atomic, assign) uint64_t audioRouteTransitionIdV2;
@property (atomic, assign) uint32_t observedOutputDeviceV2;
@property (atomic, copy) NSString *audioRouteFingerprintV2;
@property (nonatomic, assign) BOOL routeTransitionWasPlayingV2;
@property (nonatomic, assign) BOOL routeTransitionFromBluetoothV2;
@property (nonatomic, assign) BOOL iosObservedOutputWasBluetoothV2;
@property (nonatomic, copy) NSString *iosVerifiedPlaybackOutputFingerprintV2;
@property (nonatomic, assign) BOOL iosVerifiedPlaybackOutputWasBluetoothV2;
@property (nonatomic, copy) NSString *iosLastObservedRouteCauseV2;
@property (atomic, copy) NSString *currentAudioRouteIntentV2;
@property (atomic, copy) NSDictionary<NSString *, id> *iosRecordingOutputV2;
@property (atomic, copy) NSDictionary<NSString *, id> *iosRecordingInputV2;
@property (atomic, assign) double preferredPlaybackSampleRateV2;
@property (atomic, assign) NSInteger preferredPlaybackBufferFramesV2;
#if TARGET_OS_OSX
@property (atomic, assign) BOOL macIntentOperationActiveV2;
@property (atomic, assign) BOOL macIntentOperationCancelledV2;
@property (atomic, assign) BOOL macIntentCleanupClaimedV2;
@property (atomic, assign) BOOL macLifecycleTransitionActiveV2;
@property (atomic, assign) BOOL macLifecycleReconcilePendingV2;
@property (atomic, assign) BOOL macIntentRecoveryPendingV2;
@property (atomic, assign) BOOL macIntentListenersInstalledV2;
@property (atomic, assign) uint64_t macIntentOperationIdV2;
@property (atomic, assign) uint64_t macIntentOperationGenerationV2;
@property (atomic, assign) uint32_t macIntentObservedInputDeviceV2;
@property (atomic, assign) uint32_t macIntentObservedOutputDeviceV2;
@property (atomic, assign) double macIntentOperationStartedAtMsV2;
@property (atomic, copy) NSString *macIntentOperationModeV2;
@property (atomic, copy) NSString *macIntentLifecyclePhaseV2;
@property (atomic, copy) NSString *macIntentTerminalCauseV2;
@property (atomic, copy) NSString *macIntentSourceFingerprintV2;
@property (atomic, copy) NSDictionary<NSString *, id> *macIntentSourceOutputV2;
@property (atomic, copy) NSDictionary<NSString *, id> *macIntentTargetInputV2;
@property (atomic, copy) NSDictionary<NSString *, id> *macIntentTargetOutputV2;
@property (atomic, copy) NSDictionary<NSString *, id> *macIntentVerifiedOutputV2;
@property (atomic, copy) NSDictionary<NSString *, id> *macIntentInputFactsV2;
@property (atomic, assign) NSInteger macIntentRecordingChannelStartV2;
@property (atomic, assign) NSInteger macIntentRecordingChannelCountV2;
@property (atomic, assign) NSInteger macIntentMonitoringTargetRowV2;
@property (atomic, retain) NSCondition *macIntentRouteConditionV2;
@property (atomic, assign) BOOL macIntentRouteConditionSignalledV2;
@property (atomic, retain) NSCondition *macHardwareSettingsConditionV2;
@property (atomic, copy) NSString *macSelectedOutputUIDV2;
@property (atomic, copy) NSString *macSelectedInputUIDV2;
@property (atomic, assign) BOOL macIntentFollowsSystemInputV2;
#endif
#if !TARGET_OS_OSX
@property (atomic, retain) MixroomIOSCaptureLifecycleV2 *iosCaptureV2;
- (BOOL)isIOSCaptureCurrentV2:(uint64_t)operationID generation:(uint64_t)generation;
- (BOOL)isIOSMonitorOwnedV2;
- (MixroomIOSCaptureLifecycleV2 *)newIOSCaptureV2;
#endif
@property (atomic, assign) uint64_t iosMonitorStreamGenerationV2;
@property (atomic, assign) uint64_t iosLifecycleCompletionTokenV2;
@property (atomic, assign) uint64_t iosIntentOperationIdV2;
@property (atomic, assign) uint64_t iosIntentOperationGenerationV2;
@property (atomic, assign) NSInteger iosIntentRecordingChannelStartV2;
@property (atomic, assign) NSInteger iosIntentRecordingChannelCountV2;
@property (atomic, assign) NSInteger iosIntentMonitoringTargetRowV2;
@property (atomic, assign) BOOL iosIntentOperationActiveV2;
@property (atomic, assign) BOOL iosIntentOperationCancelledV2;
@property (atomic, assign) double iosIntentOperationStartedAtMsV2;
@property (atomic, copy) NSString *iosIntentOperationSourceFingerprintV2;
@property (atomic, copy) NSString *iosIntentOperationPendingFingerprintV2;
@property (atomic, copy) NSString *iosIntentOperationTargetFingerprintV2;
@property (atomic, copy) NSDictionary<NSString *, id> *iosIntentOperationTargetOutputV2;
@property (atomic, copy) NSDictionary<NSString *, id> *iosLastDuplexProbeV2;
@property (atomic, assign) BOOL iosLifecycleTransitionActiveV2;
@property (atomic, assign) BOOL iosIntentCleanupClaimedV2;
@property (atomic, assign) BOOL iosIntentCompletionDeliveredV2;
@property (atomic, retain) NSCondition *iosIntentRouteConditionV2;
@property (atomic, assign) BOOL iosIntentRouteConditionSignalledV2;
@property (atomic, copy) NSString *iosIntentLifecyclePhaseV2;
@property (atomic, copy) NSString *iosIntentTerminalCauseV2;
@property (atomic, copy) NSString *iosIntentOperationModeV2;
@property (atomic, assign) BOOL iosInterruptionActiveV2;
@property (atomic, assign) BOOL iosInterruptionRecoveryPendingV2;
@property (atomic, assign) BOOL iosInterruptionWasSuspendedV2;
@property (atomic, assign) BOOL iosInterruptionShouldResumeV2;
@property (atomic, copy) NSString *iosInterruptionPhaseV2;
@property (atomic, retain) NSNumber *iosInterruptionReasonV2;
@property (atomic, copy) NSString *iosInterruptionRecoveryOutcomeV2;
@property (atomic, assign) BOOL iosForegroundRecoveryPendingV2;
- (void)bindEventSink:(FlutterEventSink)events;
- (void)clearEventSink;
- (NSDictionary<NSString *, id> *)buildAudioRouteSnapshotV2;
- (NSDictionary<NSString *, id> *)initialisePlaybackV2;
- (NSDictionary<NSString *, id> *)startAudioRouteMonitoringV2;
- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:(NSDictionary *)args;
- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args;
- (void)setAudioRouteIntentV2:(NSDictionary *)args
                   completion:(void (^)(NSDictionary<NSString *, id> *))completion;
#if TARGET_OS_OSX
- (void)signalMacIntentRouteConditionV2;
- (void)signalMacHardwareSettingsConditionV2;
- (BOOL)settleMacOutputHardwareSettingsV2:
    (NSDictionary<NSString *, id> *)output
    sampleRate:(double)sampleRate
    bufferFrames:(NSInteger)bufferFrames
    generation:(uint64_t)generation
    deadlineMs:(double)deadlineMs
    diagnosticCode:(NSString **)diagnosticCode;
- (BOOL)installMacIntentDeviceListenersV2;
- (void)removeMacIntentDeviceListenersV2;
- (BOOL)claimMacIntentCleanupV2;
- (void)finishMacIntentOperationV2;
- (void)emitMacIntentRouteInvalidationEventV2:(BOOL)recordingWasActive
                           monitoringWasActive:(BOOL)monitoringWasActive;
- (BOOL)isMacMonitoringSessionReusableV2;
- (BOOL)startMacIndependentInputRecordingV2:(NSString *)path
                                channelStart:(NSInteger)channelStart
                                channelCount:(NSInteger)channelCount;
- (NSDictionary<NSString *, id> *)currentMacPlaybackOutputV2:
    (NSArray<NSDictionary<NSString *, id> *> *)inventory;
- (NSDictionary<NSString *, id> *)currentMacRecordingInputV2:
    (NSArray<NSDictionary<NSString *, id> *> *)inventory;
- (NSString *)currentMacPlaybackOutputFingerprintV2;
#else
- (void)signalIOSIntentRouteConditionV2;
- (BOOL)claimIOSIntentCleanupV2;
#endif
- (void)stopAudioRouteMonitoringV2;
- (void)handleAudioRoutePropertyChangeV2:(NSString *)cause;
- (void)updateObservedOutputDeviceV2:(uint32_t)deviceID;
#if !TARGET_OS_OSX
- (BOOL)startIOSAudioRouteMonitoringV2;
- (void)stopIOSAudioRouteMonitoringV2;
- (void)handleIOSAudioRouteChangeV2:(NSNotification *)notification;
#endif
@end

#if TARGET_OS_OSX
static OSStatus MixroomAudioRoutePropertyListenerV2(
    AudioObjectID objectID,
    UInt32 numberAddresses,
    const AudioObjectPropertyAddress addresses[],
    void *clientData
) {
    #pragma unused(objectID, numberAddresses)
    JuceAudioEnginePlugin *plugin = (JuceAudioEnginePlugin *)clientData;
    NSString *cause = @"deviceInventoryChanged";
    if (addresses != NULL &&
        addresses[0].mSelector == kAudioHardwarePropertyDefaultOutputDevice) {
        cause = @"defaultOutputChanged";
    } else if (addresses != NULL &&
               addresses[0].mSelector == kAudioHardwarePropertyDefaultInputDevice) {
        cause = @"defaultInputChanged";
    } else if (addresses != NULL &&
               addresses[0].mSelector == kAudioDevicePropertyDeviceIsAlive) {
        cause = @"activeDeviceRemoved";
    } else if (addresses != NULL &&
               addresses[0].mSelector == kAudioDevicePropertyNominalSampleRate) {
        cause = @"nominalSampleRateChanged";
    } else if (addresses != NULL &&
               addresses[0].mSelector == kAudioDevicePropertyBufferFrameSize) {
        cause = @"bufferFrameSizeChanged";
    } else if (addresses != NULL &&
               addresses[0].mSelector == kAudioDevicePropertyStreamConfiguration) {
        cause = @"streamConfigurationChanged";
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [plugin handleAudioRoutePropertyChangeV2:cause];
    });
    return noErr;
}
#endif

@implementation JuceAudioEnginePlugin

static dispatch_queue_t MixroomPromptAnalysisQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_queue_attr_t attr =
            dispatch_queue_attr_make_with_qos_class(
                DISPATCH_QUEUE_SERIAL,
                QOS_CLASS_USER_INITIATED,
                0
            );
        queue = dispatch_queue_create(
            "com.mixroom.juce_audio_engine.prompt_analysis",
            attr
        );
    });
    return queue;
}

static dispatch_queue_t MixroomMidiClipLoadQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_queue_attr_t attr =
            dispatch_queue_attr_make_with_qos_class(
                DISPATCH_QUEUE_SERIAL,
                QOS_CLASS_USER_INITIATED,
                0
            );
        queue = dispatch_queue_create(
            "com.mixroom.juce_audio_engine.midi_clip_load",
            attr
        );
    });
    return queue;
}

static dispatch_queue_t MixroomBuiltInMidiClipPreparationQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_queue_attr_t attr =
            dispatch_queue_attr_make_with_qos_class(
                DISPATCH_QUEUE_CONCURRENT,
                QOS_CLASS_USER_INITIATED,
                0
            );
        queue = dispatch_queue_create(
            "com.mixroom.juce_audio_engine.builtin_midi_prepare",
            attr
        );
    });
    return queue;
}

#if MIXROOM_ENABLE_TEST_HOOKS
static NSCondition *MixroomMidiClipLoadTestCondition(void) {
    static NSCondition *condition;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        condition = [NSCondition new];
    });
    return condition;
}

static int64_t mixroomMidiClipLoadTestRequestId = 0;
static BOOL mixroomMidiClipLoadTestWaiting = NO;
static BOOL mixroomMidiClipLoadTestReleased = YES;
static BOOL mixroomMidiClipLoadTestPreparationOnMainThread = NO;

static BOOL MixroomConfigureMidiClipLoadTestStall(int64_t requestId) {
    if (requestId <= 0) {
        return NO;
    }
    NSCondition *condition = MixroomMidiClipLoadTestCondition();
    [condition lock];
    if (mixroomMidiClipLoadTestWaiting && !mixroomMidiClipLoadTestReleased) {
        [condition unlock];
        return NO;
    }
    mixroomMidiClipLoadTestRequestId = requestId;
    mixroomMidiClipLoadTestWaiting = NO;
    mixroomMidiClipLoadTestReleased = NO;
    mixroomMidiClipLoadTestPreparationOnMainThread = NO;
    [condition unlock];
    return YES;
}

static void MixroomWaitForMidiClipLoadTestStall(int64_t requestId) {
    NSCondition *condition = MixroomMidiClipLoadTestCondition();
    [condition lock];
    if (requestId != mixroomMidiClipLoadTestRequestId ||
        mixroomMidiClipLoadTestReleased) {
        [condition unlock];
        return;
    }
    mixroomMidiClipLoadTestWaiting = YES;
    mixroomMidiClipLoadTestPreparationOnMainThread = [NSThread isMainThread];
    [condition broadcast];
    while (requestId == mixroomMidiClipLoadTestRequestId &&
           !mixroomMidiClipLoadTestReleased) {
        [condition wait];
    }
    mixroomMidiClipLoadTestWaiting = NO;
    if (requestId == mixroomMidiClipLoadTestRequestId) {
        mixroomMidiClipLoadTestRequestId = 0;
    }
    [condition broadcast];
    [condition unlock];
}

static BOOL MixroomReleaseMidiClipLoadTestStall(int64_t requestId) {
    NSCondition *condition = MixroomMidiClipLoadTestCondition();
    [condition lock];
    const BOOL matches = requestId == mixroomMidiClipLoadTestRequestId;
    if (matches) {
        mixroomMidiClipLoadTestReleased = YES;
        [condition broadcast];
    }
    [condition unlock];
    return matches;
}

static NSDictionary *MixroomMidiClipLoadTestState(void) {
    NSCondition *condition = MixroomMidiClipLoadTestCondition();
    [condition lock];
    NSDictionary *state = @{
        @"requestId": @(mixroomMidiClipLoadTestRequestId),
        @"waiting": @(mixroomMidiClipLoadTestWaiting),
        @"released": @(mixroomMidiClipLoadTestReleased),
        @"preparationOnMainThread":
            @(mixroomMidiClipLoadTestPreparationOnMainThread),
    };
    [condition unlock];
    return state;
}
#endif

static dispatch_queue_t MixroomPluginScanQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_queue_attr_t attr =
            dispatch_queue_attr_make_with_qos_class(
                DISPATCH_QUEUE_SERIAL,
                QOS_CLASS_UTILITY,
                0
            );
        queue = dispatch_queue_create(
            "com.mixroom.juce_audio_engine.plugin_scan",
            attr
        );
    });
    return queue;
}

#if TARGET_OS_OSX
static const void *MixroomMacLifecycleQueueKey = &MixroomMacLifecycleQueueKey;

static dispatch_queue_t MixroomMacPlaybackStartupQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_queue_attr_t attr =
            dispatch_queue_attr_make_with_qos_class(
                DISPATCH_QUEUE_SERIAL,
                QOS_CLASS_USER_INITIATED,
                0
            );
        queue = dispatch_queue_create(
            "com.mixroom.juce_audio_engine.macos_v2_startup",
            attr
        );
        dispatch_queue_set_specific(
            queue,
            MixroomMacLifecycleQueueKey,
            (void *)MixroomMacLifecycleQueueKey,
            NULL
        );
    });
    return queue;
}

static BOOL MixroomIsOnMacLifecycleQueue(void) {
    return dispatch_get_specific(MixroomMacLifecycleQueueKey) != NULL;
}
#endif

#if !TARGET_OS_OSX
static const void *MixroomIOSLifecycleQueueKey = &MixroomIOSLifecycleQueueKey;

static dispatch_queue_t MixroomIOSLifecycleQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_queue_attr_t attr =
            dispatch_queue_attr_make_with_qos_class(
                DISPATCH_QUEUE_SERIAL,
                QOS_CLASS_USER_INITIATED,
                0
            );
        queue = dispatch_queue_create(
            "com.mixroom.juce_audio_engine.ios_v2_lifecycle",
            attr
        );
        dispatch_queue_set_specific(
            queue,
            MixroomIOSLifecycleQueueKey,
            (void *)MixroomIOSLifecycleQueueKey,
            NULL
        );
    });
    return queue;
}

static BOOL MixroomIsOnIOSLifecycleQueue(void) {
    return dispatch_get_specific(MixroomIOSLifecycleQueueKey) != NULL;
}
#endif

static NSString *MixroomRouteKindForPortType(NSString *portType) {
#if TARGET_OS_OSX
    #pragma unused(portType)
    return @"unknown";
#else
    if (portType == nil) {
        return @"unknown";
    }
    if ([portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
        [portType isEqualToString:AVAudioSessionPortBluetoothHFP] ||
        [portType isEqualToString:AVAudioSessionPortBluetoothLE]) {
        return @"bluetoothOutput";
    }
    if ([portType isEqualToString:AVAudioSessionPortHeadphones] ||
        [portType isEqualToString:AVAudioSessionPortHeadsetMic] ||
        [portType isEqualToString:AVAudioSessionPortLineOut]) {
        return @"wired";
    }
    if ([portType isEqualToString:AVAudioSessionPortUSBAudio]) {
        return @"usb";
    }
    if ([portType isEqualToString:AVAudioSessionPortBuiltInSpeaker] ||
        [portType isEqualToString:AVAudioSessionPortBuiltInReceiver]) {
        return @"speaker";
    }
    return @"unknown";
#endif
}

#if !TARGET_OS_OSX
static double MixroomIOSMonotonicMilliseconds(void) {
    return [NSProcessInfo processInfo].systemUptime * 1000.0;
}

static NSString *MixroomIOSRouteKind(NSString *portType) {
    if ([portType isEqualToString:AVAudioSessionPortBluetoothA2DP]) {
        return @"bluetoothMedia";
    }
    if ([portType isEqualToString:AVAudioSessionPortBluetoothHFP]) {
        return @"bluetoothDuplex";
    }
    if ([portType isEqualToString:AVAudioSessionPortBluetoothLE]) {
        return @"bluetoothLe";
    }
    if ([portType isEqualToString:AVAudioSessionPortBuiltInSpeaker] ||
        [portType isEqualToString:AVAudioSessionPortBuiltInReceiver] ||
        [portType isEqualToString:AVAudioSessionPortBuiltInMic]) {
        return @"builtIn";
    }
    if ([portType isEqualToString:AVAudioSessionPortHeadphones] ||
        [portType isEqualToString:AVAudioSessionPortHeadsetMic] ||
        [portType isEqualToString:AVAudioSessionPortLineIn] ||
        [portType isEqualToString:AVAudioSessionPortLineOut]) {
        return @"wired";
    }
    if ([portType isEqualToString:AVAudioSessionPortUSBAudio] ||
        [portType isEqualToString:AVAudioSessionPortAirPlay] ||
        [portType isEqualToString:AVAudioSessionPortHDMI] ||
        [portType isEqualToString:AVAudioSessionPortCarAudio]) {
        return @"external";
    }
    return @"unknown";
}

static NSDictionary<NSString *, id> *MixroomIOSRouteEndpoint(
    AVAudioSessionPortDescription *port,
    NSString *direction
) {
    NSArray<AVAudioSessionChannelDescription *> *channels = port.channels;
    return @{
        @"direction": direction,
        @"nativePortType": port.portType ?: @"",
        @"normalizedKind": MixroomIOSRouteKind(port.portType),
        @"uid": port.UID ?: @"",
        @"name": port.portName ?: @"",
        @"channelCount": channels == nil ? [NSNull null] : @(channels.count),
    };
}

static NSArray<NSDictionary<NSString *, id> *> *MixroomIOSRouteEndpoints(
    AVAudioSessionRouteDescription *route,
    BOOL inputs
) {
    NSArray<AVAudioSessionPortDescription *> *ports = inputs
        ? route.inputs
        : route.outputs;
    NSMutableArray<NSDictionary<NSString *, id> *> *endpoints =
        [NSMutableArray arrayWithCapacity:ports.count];
    NSString *direction = inputs ? @"input" : @"output";
    for (AVAudioSessionPortDescription *port in ports) {
        [endpoints addObject:MixroomIOSRouteEndpoint(port, direction)];
    }
    return endpoints;
}

static NSString *MixroomIOSRouteFingerprint(
    AVAudioSessionRouteDescription *route
) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    void (^appendPorts)(NSArray<AVAudioSessionPortDescription *> *, NSString *) =
        ^(NSArray<AVAudioSessionPortDescription *> *ports, NSString *direction) {
            for (AVAudioSessionPortDescription *port in ports) {
                NSNumber *channels = port.channels == nil
                    ? nil
                    : @(port.channels.count);
                [parts addObject:[NSString stringWithFormat:@"%@|%@|%@|%@",
                    direction,
                    port.UID ?: @"",
                    port.portType ?: @"",
                    channels ?: @"unknown"]];
            }
        };
    appendPorts(route.inputs, @"input");
    appendPorts(route.outputs, @"output");
    [parts sortUsingSelector:@selector(compare:)];
    return [parts componentsJoinedByString:@";"];
}

static NSString *MixroomIOSOutputFingerprint(
    AVAudioSessionRouteDescription *route
) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (AVAudioSessionPortDescription *port in route.outputs) {
        NSNumber *channels = port.channels == nil
            ? nil
            : @(port.channels.count);
        [parts addObject:[NSString stringWithFormat:@"%@|%@|%@|%@",
            port.UID ?: @"",
            port.portType ?: @"",
            MixroomIOSRouteKind(port.portType),
            channels ?: @"unknown"]];
    }
    [parts sortUsingSelector:@selector(compare:)];
    return [parts componentsJoinedByString:@";"];
}

static NSString *MixroomIOSObservedRouteCause(
    AVAudioSessionRouteChangeReason reason
) {
    switch (reason) {
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            return @"newDeviceAvailable";
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            return @"oldDeviceUnavailable";
        case AVAudioSessionRouteChangeReasonCategoryChange:
            return @"categoryChanged";
        case AVAudioSessionRouteChangeReasonOverride:
            return @"routeOverride";
        case AVAudioSessionRouteChangeReasonWakeFromSleep:
            return @"wakeFromSleep";
        case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
            return @"noSuitableRoute";
        case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
            return @"routeConfigurationChanged";
        case AVAudioSessionRouteChangeReasonUnknown:
        default:
            return @"unknown";
    }
}

static NSDictionary<NSString *, id> *MixroomIOSSingleOutputEndpoint(
    AVAudioSessionRouteDescription *route
) {
    if (route.outputs.count != 1) {
        return nil;
    }
    return MixroomIOSRouteEndpoint(route.outputs.firstObject, @"output");
}

static NSDictionary<NSString *, id> *MixroomIOSSingleInputEndpoint(
    AVAudioSessionRouteDescription *route
) {
    if (route.inputs.count != 1) {
        return nil;
    }
    return MixroomIOSRouteEndpoint(route.inputs.firstObject, @"input");
}

static BOOL MixroomIOSOutputIsBuiltInSpeaker(
    NSDictionary<NSString *, id> *endpoint
) {
    return [endpoint[@"nativePortType"] isEqual:AVAudioSessionPortBuiltInSpeaker] &&
        [endpoint[@"normalizedKind"] isEqual:@"builtIn"];
}

static BOOL MixroomIOSInputIsBuiltInMicrophone(
    NSDictionary<NSString *, id> *endpoint
) {
    return [endpoint[@"nativePortType"] isEqual:AVAudioSessionPortBuiltInMic] &&
        [endpoint[@"normalizedKind"] isEqual:@"builtIn"];
}

static NSArray<AVAudioSessionPortDescription *> *MixroomIOSBuiltInInputs(
    AVAudioSession *session
) {
    NSMutableArray<AVAudioSessionPortDescription *> *matches =
        [NSMutableArray array];
    for (AVAudioSessionPortDescription *input in session.availableInputs ?: @[]) {
        if ([input.portType isEqual:AVAudioSessionPortBuiltInMic]) {
            [matches addObject:input];
        }
    }
    return matches;
}

static BOOL MixroomIOSOutputIdentityIsObservable(
    NSDictionary<NSString *, id> *endpoint
) {
    NSString *uid = [endpoint[@"uid"] isKindOfClass:[NSString class]]
        ? endpoint[@"uid"]
        : @"";
    NSString *portType =
        [endpoint[@"nativePortType"] isKindOfClass:[NSString class]]
            ? endpoint[@"nativePortType"]
            : @"";
    return uid.length > 0 && portType.length > 0;
}

static BOOL MixroomIOSOutputIdentitiesMatch(
    NSDictionary<NSString *, id> *expected,
    NSDictionary<NSString *, id> *actual
) {
    if (!MixroomIOSOutputIdentityIsObservable(expected) ||
        !MixroomIOSOutputIdentityIsObservable(actual)) {
        return NO;
    }
    return [expected[@"uid"] isEqual:actual[@"uid"]] &&
        [expected[@"nativePortType"] isEqual:actual[@"nativePortType"]] &&
        [expected[@"normalizedKind"] isEqual:actual[@"normalizedKind"]];
}

static BOOL MixroomIOSEndpointIdentitiesMatchStrict(
    NSDictionary<NSString *, id> *expected,
    NSDictionary<NSString *, id> *actual
) {
    if (!MixroomIOSOutputIdentitiesMatch(expected, actual)) {
        return NO;
    }
    id expectedDirection = expected[@"direction"];
    id actualDirection = actual[@"direction"];
    id expectedChannels = expected[@"channelCount"];
    id actualChannels = actual[@"channelCount"];
    return [expectedDirection isEqual:actualDirection] &&
        [expectedChannels isEqual:actualChannels];
}

static BOOL MixroomIOSOutputIsBluetoothMedia(
    NSDictionary<NSString *, id> *endpoint
) {
    return [endpoint[@"nativePortType"]
               isEqual:AVAudioSessionPortBluetoothA2DP] &&
        [endpoint[@"normalizedKind"] isEqual:@"bluetoothMedia"];
}

static BOOL MixroomIOSInputIsBluetoothHFP(
    NSDictionary<NSString *, id> *endpoint
) {
    return [endpoint[@"direction"] isEqual:@"input"] &&
        [endpoint[@"nativePortType"]
            isEqual:AVAudioSessionPortBluetoothHFP] &&
        [endpoint[@"normalizedKind"] isEqual:@"bluetoothDuplex"] &&
        MixroomIOSOutputIdentityIsObservable(endpoint);
}

static BOOL MixroomIOSOutputIsBluetoothHFP(
    NSDictionary<NSString *, id> *endpoint
) {
    return [endpoint[@"direction"] isEqual:@"output"] &&
        [endpoint[@"nativePortType"]
            isEqual:AVAudioSessionPortBluetoothHFP] &&
        [endpoint[@"normalizedKind"] isEqual:@"bluetoothDuplex"] &&
        MixroomIOSOutputIdentityIsObservable(endpoint);
}

static BOOL MixroomIOSRouteIsBluetoothHFPDuplex(
    AVAudioSessionRouteDescription *route
) {
    if (route == nil) {
        return NO;
    }
    return MixroomIOSInputIsBluetoothHFP(
               MixroomIOSSingleInputEndpoint(route)) &&
        MixroomIOSOutputIsBluetoothHFP(
               MixroomIOSSingleOutputEndpoint(route));
}

static BOOL MixroomIOSRouteHasSingleObservableDuplex(
    AVAudioSessionRouteDescription *route
) {
    NSDictionary<NSString *, id> *input =
        MixroomIOSSingleInputEndpoint(route);
    NSDictionary<NSString *, id> *output =
        MixroomIOSSingleOutputEndpoint(route);
    return input != nil && output != nil &&
        MixroomIOSOutputIdentityIsObservable(input) &&
        MixroomIOSOutputIdentityIsObservable(output) &&
        [input[@"channelCount"] integerValue] > 0 &&
        [output[@"channelCount"] integerValue] > 0;
}

static BOOL MixroomIOSSystemSelectedTargetMatchesSource(
    NSDictionary<NSString *, id> *sourceOutput,
    AVAudioSessionRouteDescription *targetRoute
) {
    if (!MixroomIOSRouteHasSingleObservableDuplex(targetRoute)) {
        return NO;
    }
    NSDictionary<NSString *, id> *targetInput =
        MixroomIOSSingleInputEndpoint(targetRoute);
    NSDictionary<NSString *, id> *targetOutput =
        MixroomIOSSingleOutputEndpoint(targetRoute);
    if (MixroomIOSEndpointIdentitiesMatchStrict(sourceOutput, targetOutput)) {
        return YES;
    }
    return MixroomIOSOutputIsBluetoothMedia(sourceOutput) &&
        MixroomIOSInputIsBluetoothHFP(targetInput) &&
        MixroomIOSOutputIsBluetoothHFP(targetOutput);
}

static NSArray<NSString *> *MixroomIOSCategoryOptionNames(
    AVAudioSessionCategoryOptions options
) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    if ((options & AVAudioSessionCategoryOptionMixWithOthers) != 0) {
        [names addObject:@"mixWithOthers"];
    }
    if ((options & AVAudioSessionCategoryOptionDefaultToSpeaker) != 0) {
        [names addObject:@"defaultToSpeaker"];
    }
    if ((options & AVAudioSessionCategoryOptionAllowBluetoothHFP) != 0) {
        [names addObject:@"allowBluetoothHFP"];
    }
    if ((options & AVAudioSessionCategoryOptionAllowBluetoothA2DP) != 0) {
        [names addObject:@"allowBluetoothA2DP"];
    }
    if ((options & AVAudioSessionCategoryOptionAllowAirPlay) != 0) {
        [names addObject:@"allowAirPlay"];
    }
    return names;
}

static BOOL MixroomIOSOutputIsBluetoothDuplex(
    NSDictionary<NSString *, id> *endpoint
) {
    return [endpoint[@"normalizedKind"] isEqual:@"bluetoothDuplex"];
}

static BOOL MixroomIOSOutputIsBluetooth(
    NSDictionary<NSString *, id> *endpoint
) {
    NSString *kind = [endpoint[@"normalizedKind"] isKindOfClass:[NSString class]]
        ? endpoint[@"normalizedKind"]
        : @"unknown";
    return [kind isEqualToString:@"bluetoothMedia"] ||
        [kind isEqualToString:@"bluetoothLe"] ||
        [kind isEqualToString:@"bluetoothDuplex"];
}

static BOOL MixroomIOSMonitoringEndpointIsAllowed(
    NSDictionary<NSString *, id> *endpoint
) {
    if (!MixroomIOSOutputIdentityIsObservable(endpoint)) {
        return NO;
    }
    NSString *kind = [endpoint[@"normalizedKind"] isKindOfClass:[NSString class]]
        ? endpoint[@"normalizedKind"] : @"unknown";
    return [kind isEqualToString:@"builtIn"] ||
        [kind isEqualToString:@"wired"] ||
        [kind isEqualToString:@"external"];
}

static BOOL MixroomHardwareSampleRatePreferenceIsSupported(double value) {
    const NSInteger rounded = (NSInteger)llround(value);
    return rounded == 44100 || rounded == 48000 ||
        rounded == 88200 || rounded == 96000;
}

static BOOL MixroomHardwareBufferPreferenceIsSupported(NSInteger value) {
    return value == 64 || value == 128 || value == 256 ||
        value == 512 || value == 1024;
}

static double MixroomIOSPlaybackOpenRate(
    NSDictionary<NSString *, id> *output,
    AVAudioSession *session,
    double preferredRate
) {
    return MixroomIOSOutputIsBluetooth(output) ||
        !MixroomHardwareSampleRatePreferenceIsSupported(preferredRate)
        ? session.sampleRate : preferredRate;
}

static NSInteger MixroomIOSPlaybackOpenBuffer(
    NSDictionary<NSString *, id> *output,
    AVAudioSession *session,
    NSInteger preferredBuffer
) {
    const NSInteger nativeBuffer = session.sampleRate > 1000.0 &&
        session.IOBufferDuration > 0.0
        ? (NSInteger)llround(session.sampleRate * session.IOBufferDuration)
        : 0;
    return MixroomIOSOutputIsBluetooth(output) ||
        !MixroomHardwareBufferPreferenceIsSupported(preferredBuffer)
        ? nativeBuffer : preferredBuffer;
}

#endif

#if TARGET_OS_OSX
static const AudioObjectPropertyElement kMixroomCoreAudioElement =
    kAudioObjectPropertyElementMain;

static NSString *MixroomStringFromCoreAudioObject(AudioObjectID objectID,
                                                  AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = {
        selector,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    if (!AudioObjectHasProperty(objectID, &address)) {
        return @"";
    }

    CFStringRef value = NULL;
    UInt32 size = sizeof(value);
    if (AudioObjectGetPropertyData(objectID, &address, 0, NULL, &size, &value) != noErr ||
        value == NULL) {
        return @"";
    }

    NSString *result = [(__bridge NSString *)value copy];
    CFRelease(value);
    return [result autorelease];
}

static BOOL MixroomCoreAudioDeviceHasInput(AudioDeviceID deviceID) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyStreams,
        kAudioDevicePropertyScopeInput,
        kMixroomCoreAudioElement,
    };
    UInt32 size = 0;
    return AudioObjectHasProperty(deviceID, &address) &&
        AudioObjectGetPropertyDataSize(deviceID, &address, 0, NULL, &size) == noErr &&
        size > 0;
}

static UInt32 MixroomCoreAudioDeviceTransport(AudioDeviceID deviceID) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyTransportType,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    UInt32 transport = kAudioDeviceTransportTypeUnknown;
    UInt32 size = sizeof(transport);
    if (AudioObjectHasProperty(deviceID, &address)) {
        AudioObjectGetPropertyData(deviceID, &address, 0, NULL, &size, &transport);
    }
    return transport;
}

static AudioDeviceID MixroomDefaultCoreAudioInputDevice(void) {
    AudioDeviceID deviceID = kAudioObjectUnknown;
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    UInt32 size = sizeof(deviceID);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                   &address,
                                   0,
                                   NULL,
                                   &size,
                                   &deviceID) != noErr) {
        return kAudioObjectUnknown;
    }
    return deviceID;
}

static AudioDeviceID MixroomDefaultCoreAudioOutputDevice(void) {
    AudioDeviceID deviceID = kAudioObjectUnknown;
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    UInt32 size = sizeof(deviceID);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                   &address,
                                   0,
                                   NULL,
                                   &size,
                                   &deviceID) != noErr) {
        return kAudioObjectUnknown;
    }
    return deviceID;
}

static BOOL MixroomCoreAudioDeviceIsAlive(AudioDeviceID deviceID) {
    if (deviceID == kAudioObjectUnknown) {
        return NO;
    }
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyDeviceIsAlive,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    UInt32 value = 0;
    UInt32 size = sizeof(value);
    return AudioObjectHasProperty(deviceID, &address) &&
        AudioObjectGetPropertyData(deviceID, &address, 0, NULL, &size, &value) == noErr &&
        value != 0;
}

static BOOL MixroomTransportIsBluetooth(UInt32 transport) {
    return transport == kAudioDeviceTransportTypeBluetooth ||
        transport == kAudioDeviceTransportTypeBluetoothLE;
}

static BOOL MixroomMacMonitoringTransportIsAllowed(UInt32 transport) {
    return transport != kAudioDeviceTransportTypeUnknown &&
        !MixroomTransportIsBluetooth(transport);
}

static BOOL MixroomHardwareSampleRatePreferenceIsSupported(double value) {
    const NSInteger rounded = (NSInteger)llround(value);
    return rounded == 44100 || rounded == 48000 ||
        rounded == 88200 || rounded == 96000;
}

static BOOL MixroomHardwareBufferPreferenceIsSupported(NSInteger value) {
    return value == 64 || value == 128 || value == 256 ||
        value == 512 || value == 1024;
}

static BOOL MixroomTransportIsBuiltIn(UInt32 transport) {
    return transport == kAudioDeviceTransportTypeBuiltIn;
}

static NSString *MixroomTransportLabel(UInt32 transport) {
    switch (transport) {
        case kAudioDeviceTransportTypeBuiltIn:
            return @"builtIn";
        case kAudioDeviceTransportTypeUSB:
            return @"usb";
        case kAudioDeviceTransportTypeFireWire:
            return @"firewire";
        case kAudioDeviceTransportTypePCI:
            return @"pci";
        case kAudioDeviceTransportTypeAggregate:
            return @"aggregate";
        case kAudioDeviceTransportTypeVirtual:
            return @"virtual";
        case kAudioDeviceTransportTypeBluetooth:
        case kAudioDeviceTransportTypeBluetoothLE:
            return @"bluetooth";
        default:
            return @"unknown";
    }
}

static NSString *MixroomNormalizeAudioDeviceName(NSString *name) {
    NSString *lower = [[name ?: @"" lowercaseString]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (lower.length == 0) {
        return @"";
    }
    NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
    NSMutableString *out = [NSMutableString stringWithCapacity:lower.length];
    BOOL lastWasSpace = NO;
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar ch = [lower characterAtIndex:i];
        if ([allowed characterIsMember:ch]) {
            [out appendFormat:@"%C", ch];
            lastWasSpace = NO;
        } else if (!lastWasSpace) {
            [out appendString:@" "];
            lastWasSpace = YES;
        }
    }
    return [out stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL MixroomAudioDeviceNameLooksBluetooth(NSString *name) {
    NSString *normalized = MixroomNormalizeAudioDeviceName(name);
    return [normalized containsString:@"airpods"] ||
        [normalized containsString:@"bluetooth"] ||
        [normalized containsString:@"beats"] ||
        [normalized containsString:@"buds"] ||
        [normalized containsString:@"headset"];
}

static NSNumber *MixroomCoreAudioChannelCount(AudioDeviceID deviceID,
                                              AudioObjectPropertyScope scope);

static NSArray<NSDictionary<NSString *, id> *> *MixroomMacInputDeviceInfos(void) {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,
                                       &address,
                                       0,
                                       NULL,
                                       &size) != noErr ||
        size == 0) {
        return @[];
    }

    UInt32 count = size / sizeof(AudioDeviceID);
    AudioDeviceID *devices = calloc(count, sizeof(AudioDeviceID));
    if (devices == NULL) {
        return @[];
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *infos =
        [NSMutableArray arrayWithCapacity:count];
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                   &address,
                                   0,
                                   NULL,
                                   &size,
                                   devices) == noErr) {
        AudioDeviceID defaultInput = MixroomDefaultCoreAudioInputDevice();
        for (UInt32 i = 0; i < count; i++) {
            AudioDeviceID deviceID = devices[i];
            if (!MixroomCoreAudioDeviceHasInput(deviceID)) {
                continue;
            }
            NSString *name = MixroomStringFromCoreAudioObject(deviceID, kAudioObjectPropertyName);
            if (name.length == 0) {
                continue;
            }
            UInt32 transport = MixroomCoreAudioDeviceTransport(deviceID);
            BOOL isBluetooth = MixroomTransportIsBluetooth(transport) ||
                MixroomAudioDeviceNameLooksBluetooth(name);
            [infos addObject:@{
                @"name": name,
                @"channelCount": MixroomCoreAudioChannelCount(
                    deviceID,
                    kAudioDevicePropertyScopeInput
                ) ?: @0,
                @"isBluetoothInput": @(isBluetooth),
                @"isBuiltIn": @(MixroomTransportIsBuiltIn(transport)),
                @"isDefault": @(deviceID == defaultInput),
                @"transport": MixroomTransportLabel(transport),
            }];
        }
    }
    free(devices);
    return infos;
}

static BOOL MixroomMacInputDeviceNameIsBluetooth(NSString *name) {
    NSString *target = MixroomNormalizeAudioDeviceName(name);
    if (target.length == 0) {
        return NO;
    }
    for (NSDictionary<NSString *, id> *info in MixroomMacInputDeviceInfos()) {
        NSString *candidate = MixroomNormalizeAudioDeviceName(info[@"name"]);
        if ([candidate isEqualToString:target] ||
            [candidate containsString:target] ||
            [target containsString:candidate]) {
            return [info[@"isBluetoothInput"] boolValue];
        }
    }
    return MixroomAudioDeviceNameLooksBluetooth(name);
}

static double MixroomMonotonicMilliseconds(void) {
    static mach_timebase_info_data_t timebase;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mach_timebase_info(&timebase);
    });
    const double nanoseconds = (double)mach_absolute_time() *
        (double)timebase.numer / (double)timebase.denom;
    return nanoseconds / 1000000.0;
}

static NSNumber *MixroomCoreAudioChannelCount(AudioDeviceID deviceID,
                                              AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyStreamConfiguration,
        scope,
        kMixroomCoreAudioElement,
    };
    UInt32 size = 0;
    if (!AudioObjectHasProperty(deviceID, &address) ||
        AudioObjectGetPropertyDataSize(deviceID, &address, 0, NULL, &size) != noErr ||
        size < sizeof(AudioBufferList)) {
        return nil;
    }

    AudioBufferList *buffers = malloc(size);
    if (buffers == NULL) {
        return nil;
    }

    NSNumber *result = nil;
    if (AudioObjectGetPropertyData(deviceID,
                                   &address,
                                   0,
                                   NULL,
                                   &size,
                                   buffers) == noErr) {
        UInt32 channels = 0;
        for (UInt32 index = 0; index < buffers->mNumberBuffers; index++) {
            channels += buffers->mBuffers[index].mNumberChannels;
        }
        result = @(channels);
    }
    free(buffers);
    return result;
}

static NSNumber *MixroomCoreAudioSampleRate(AudioDeviceID deviceID) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    Float64 value = 0.0;
    UInt32 size = sizeof(value);
    if (!AudioObjectHasProperty(deviceID, &address) ||
        AudioObjectGetPropertyData(deviceID, &address, 0, NULL, &size, &value) != noErr ||
        value <= 0.0) {
        return nil;
    }
    return @(value);
}

static NSNumber *MixroomCoreAudioBufferFrames(AudioDeviceID deviceID) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyBufferFrameSize,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    UInt32 value = 0;
    UInt32 size = sizeof(value);
    if (!AudioObjectHasProperty(deviceID, &address) ||
        AudioObjectGetPropertyData(deviceID, &address, 0, NULL, &size, &value) != noErr ||
        value == 0) {
        return nil;
    }
    return @(value);
}

static BOOL MixroomCoreAudioPropertyIsSettable(
    AudioDeviceID deviceID,
    AudioObjectPropertyAddress address
) {
    Boolean settable = false;
    return AudioObjectHasProperty(deviceID, &address) &&
        AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr &&
        settable;
}

static BOOL MixroomCoreAudioSampleRateIsAvailable(
    AudioDeviceID deviceID,
    double requestedRate
) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyAvailableNominalSampleRates,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    UInt32 size = 0;
    if (!AudioObjectHasProperty(deviceID, &address) ||
        AudioObjectGetPropertyDataSize(
            deviceID, &address, 0, NULL, &size) != noErr ||
        size == 0 || size % sizeof(AudioValueRange) != 0) {
        return NO;
    }
    AudioValueRange *ranges = malloc(size);
    if (ranges == NULL) {
        return NO;
    }
    const OSStatus status = AudioObjectGetPropertyData(
        deviceID, &address, 0, NULL, &size, ranges);
    BOOL available = NO;
    if (status == noErr) {
        const UInt32 count = size / sizeof(AudioValueRange);
        for (UInt32 index = 0; index < count; index++) {
            if (requestedRate >= ranges[index].mMinimum - 0.5 &&
                requestedRate <= ranges[index].mMaximum + 0.5) {
                available = YES;
                break;
            }
        }
    }
    free(ranges);
    return available;
}

static BOOL MixroomCoreAudioBufferSizeIsAvailable(
    AudioDeviceID deviceID,
    NSInteger requestedBuffer
) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyBufferFrameSizeRange,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    AudioValueRange range = {0.0, 0.0};
    UInt32 size = sizeof(range);
    return AudioObjectHasProperty(deviceID, &address) &&
        AudioObjectGetPropertyData(
            deviceID, &address, 0, NULL, &size, &range) == noErr &&
        requestedBuffer >= (NSInteger)ceil(range.mMinimum) &&
        requestedBuffer <= (NSInteger)floor(range.mMaximum);
}

static BOOL MixroomCoreAudioOutputSupportsHardwareSettings(
    NSDictionary<NSString *, id> *output,
    double requestedRate,
    NSInteger requestedBuffer
) {
    const AudioDeviceID deviceID =
        [output[@"deviceID"] unsignedIntValue];
    const double currentRate =
        MixroomCoreAudioSampleRate(deviceID).doubleValue;
    const NSInteger currentBuffer =
        MixroomCoreAudioBufferFrames(deviceID).integerValue;
    AudioObjectPropertyAddress rateAddress = {
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    AudioObjectPropertyAddress bufferAddress = {
        kAudioDevicePropertyBufferFrameSize,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    const BOOL rateSupported = fabs(currentRate - requestedRate) < 1.0 ||
        (MixroomCoreAudioPropertyIsSettable(deviceID, rateAddress) &&
         MixroomCoreAudioSampleRateIsAvailable(deviceID, requestedRate));
    const BOOL bufferSupported = currentBuffer == requestedBuffer ||
        (MixroomCoreAudioPropertyIsSettable(deviceID, bufferAddress) &&
         MixroomCoreAudioBufferSizeIsAvailable(deviceID, requestedBuffer));
    return MixroomCoreAudioDeviceIsAlive(deviceID) &&
        requestedRate > 1000.0 && requestedBuffer > 0 &&
        rateSupported && bufferSupported;
}

static BOOL MixroomSetCoreAudioOutputSampleRate(
    AudioDeviceID deviceID,
    double requestedRate
) {
    AudioObjectPropertyAddress rateAddress = {
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    Float64 rate = requestedRate;
    NSNumber *currentRate = MixroomCoreAudioSampleRate(deviceID);
    if ((currentRate == nil ||
         fabs(currentRate.doubleValue - requestedRate) >= 1.0) &&
        AudioObjectSetPropertyData(
            deviceID, &rateAddress, 0, NULL, sizeof(rate), &rate) != noErr) {
        return NO;
    }
    return YES;
}

static BOOL MixroomSetCoreAudioOutputBufferFrames(
    AudioDeviceID deviceID,
    NSInteger requestedBuffer
) {
    AudioObjectPropertyAddress bufferAddress = {
        kAudioDevicePropertyBufferFrameSize,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    UInt32 buffer = (UInt32)requestedBuffer;
    NSNumber *currentBuffer = MixroomCoreAudioBufferFrames(deviceID);
    if ((currentBuffer == nil ||
         currentBuffer.integerValue != requestedBuffer) &&
        AudioObjectSetPropertyData(
            deviceID, &bufferAddress, 0, NULL,
            sizeof(buffer), &buffer) != noErr) {
        return NO;
    }
    return YES;
}

static NSString *MixroomRawTransportValue(UInt32 transport) {
    return [NSString stringWithFormat:@"0x%08x", (unsigned int)transport];
}

static NSNumber *MixroomCoreAudioClockDomain(AudioDeviceID deviceID) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyClockDomain,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    UInt32 clockDomain = 0;
    UInt32 size = sizeof(clockDomain);
    if (!AudioObjectHasProperty(deviceID, &address) ||
        AudioObjectGetPropertyData(
            deviceID, &address, 0, NULL, &size, &clockDomain) != noErr ||
        clockDomain == 0) {
        return nil;
    }
    return @(clockDomain);
}

static NSArray<NSDictionary<NSString *, id> *> *MixroomCoreAudioDeviceInventory(void) {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,
                                       &address,
                                       0,
                                       NULL,
                                       &size) != noErr) {
        return nil;
    }
    if (size == 0) {
        return @[];
    }

    const UInt32 capacity = size / sizeof(AudioDeviceID);
    AudioDeviceID *devices = calloc(capacity, sizeof(AudioDeviceID));
    if (devices == NULL) {
        return nil;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *inventory =
        [NSMutableArray arrayWithCapacity:capacity];
    const OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                                       &address,
                                                       0,
                                                       NULL,
                                                       &size,
                                                       devices);
    if (status == noErr) {
        const UInt32 returnedCount = MIN(
            capacity,
            size / (UInt32)sizeof(AudioDeviceID)
        );
        for (UInt32 index = 0; index < returnedCount; index++) {
            const AudioDeviceID deviceID = devices[index];
            NSString *name = MixroomStringFromCoreAudioObject(
                deviceID,
                kAudioObjectPropertyName
            );
            NSString *uid = MixroomStringFromCoreAudioObject(
                deviceID,
                kAudioDevicePropertyDeviceUID
            );
            const UInt32 transport = MixroomCoreAudioDeviceTransport(deviceID);
            [inventory addObject:@{
                @"deviceID": @(deviceID),
                @"name": name ?: @"",
                @"uid": uid ?: @"",
                @"transport": @(transport),
                @"rawTransport": MixroomRawTransportValue(transport),
                @"clockDomain": MixroomCoreAudioClockDomain(deviceID)
                    ?: [NSNull null],
                @"inputChannels": MixroomCoreAudioChannelCount(
                    deviceID,
                    kAudioDevicePropertyScopeInput
                ) ?: [NSNull null],
                @"outputChannels": MixroomCoreAudioChannelCount(
                    deviceID,
                    kAudioDevicePropertyScopeOutput
                ) ?: [NSNull null],
                @"sampleRateHz": MixroomCoreAudioSampleRate(deviceID) ?: [NSNull null],
                @"bufferFrames": MixroomCoreAudioBufferFrames(deviceID) ?: [NSNull null],
            }];
        }
    }
    free(devices);
    return status == noErr ? inventory : nil;
}

static BOOL MixroomMacMonitoringSharesClockDomain(
    NSDictionary<NSString *, id> *input,
    NSDictionary<NSString *, id> *output
) {
    if (input == nil || output == nil) {
        return NO;
    }
    NSNumber *inputDeviceID = input[@"deviceID"];
    NSNumber *outputDeviceID = output[@"deviceID"];
    if ([inputDeviceID isKindOfClass:[NSNumber class]] &&
        [outputDeviceID isKindOfClass:[NSNumber class]] &&
        inputDeviceID.unsignedIntValue != kAudioObjectUnknown &&
        inputDeviceID.unsignedIntValue == outputDeviceID.unsignedIntValue) {
        return YES;
    }
    NSNumber *inputClock = input[@"clockDomain"];
    NSNumber *outputClock = output[@"clockDomain"];
    return [inputClock isKindOfClass:[NSNumber class]] &&
        [outputClock isKindOfClass:[NSNumber class]] &&
        inputClock.unsignedIntValue > 0 &&
        inputClock.unsignedIntValue == outputClock.unsignedIntValue;
}

static NSArray<NSDictionary<NSString *, id> *> *MixroomExactDeviceMatches(
    NSArray<NSDictionary<NSString *, id> *> *inventory,
    NSString *name,
    BOOL input
);

static NSDictionary<NSString *, id> *MixroomOutputForDeviceID(
    NSArray<NSDictionary<NSString *, id> *> *inventory,
    AudioDeviceID deviceID
) {
    for (NSDictionary<NSString *, id> *device in inventory) {
        NSNumber *channels = device[@"outputChannels"];
        if ([device[@"deviceID"] unsignedIntValue] == deviceID &&
            (id)channels != [NSNull null] &&
            channels.integerValue > 0) {
            return device;
        }
    }
    return nil;
}

static NSDictionary<NSString *, id> *MixroomInputForDeviceID(
    NSArray<NSDictionary<NSString *, id> *> *inventory,
    AudioDeviceID deviceID
) {
    for (NSDictionary<NSString *, id> *device in inventory) {
        NSNumber *channels = device[@"inputChannels"];
        if ([device[@"deviceID"] unsignedIntValue] == deviceID &&
            (id)channels != [NSNull null] &&
            channels.integerValue > 0) {
            return device;
        }
    }
    return nil;
}

static NSDictionary<NSString *, id> *MixroomInputForUID(
    NSArray<NSDictionary<NSString *, id> *> *inventory,
    NSString *uid
) {
    if (uid.length == 0) {
        return nil;
    }
    for (NSDictionary<NSString *, id> *device in inventory) {
        NSNumber *channels = device[@"inputChannels"];
        if ([device[@"uid"] isEqualToString:uid] &&
            (id)channels != [NSNull null] &&
            channels.integerValue > 0) {
            return device;
        }
    }
    return nil;
}

static NSDictionary<NSString *, id> *MixroomOutputForUID(
    NSArray<NSDictionary<NSString *, id> *> *inventory,
    NSString *uid
) {
    if (uid.length == 0) {
        return nil;
    }
    for (NSDictionary<NSString *, id> *device in inventory) {
        NSNumber *channels = device[@"outputChannels"];
        if ([device[@"uid"] isEqualToString:uid] &&
            (id)channels != [NSNull null] &&
            channels.integerValue > 0) {
            return device;
        }
    }
    return nil;
}

static NSDictionary<NSString *, id> *MixroomUniqueBuiltInOutput(
    NSArray<NSDictionary<NSString *, id> *> *inventory
) {
    NSMutableArray<NSDictionary<NSString *, id> *> *candidates =
        [NSMutableArray array];
    for (NSDictionary<NSString *, id> *device in inventory) {
        NSNumber *channels = device[@"outputChannels"];
        if ([device[@"transport"] unsignedIntValue] ==
                kAudioDeviceTransportTypeBuiltIn &&
            (id)channels != [NSNull null] &&
            channels.integerValue > 0) {
            [candidates addObject:device];
        }
    }
    return candidates.count == 1 ? candidates.firstObject : nil;
}

static NSDictionary<NSString *, id> *MixroomUniqueBuiltInInput(
    NSArray<NSDictionary<NSString *, id> *> *inventory
) {
    NSMutableArray<NSDictionary<NSString *, id> *> *candidates =
        [NSMutableArray array];
    for (NSDictionary<NSString *, id> *device in inventory) {
        NSNumber *channels = device[@"inputChannels"];
        if ([device[@"transport"] unsignedIntValue] ==
                kAudioDeviceTransportTypeBuiltIn &&
            [device[@"uid"] length] > 0 &&
            (id)channels != [NSNull null] &&
            channels.integerValue > 0 &&
            MixroomCoreAudioDeviceIsAlive([device[@"deviceID"] unsignedIntValue])) {
            [candidates addObject:device];
        }
    }
    return candidates.count == 1 ? candidates.firstObject : nil;
}

static BOOL MixroomOutputNameIsUnique(
    NSArray<NSDictionary<NSString *, id> *> *inventory,
    NSDictionary<NSString *, id> *target
) {
    if (target == nil || [target[@"name"] length] == 0) {
        return NO;
    }
    return MixroomExactDeviceMatches(inventory, target[@"name"], NO).count == 1;
}

static BOOL MixroomOutputSupportsV2Recording(
    NSArray<NSDictionary<NSString *, id> *> *inventory,
    NSDictionary<NSString *, id> *output
) {
    if (output == nil || [output[@"uid"] length] == 0 ||
        !MixroomCoreAudioDeviceIsAlive([output[@"deviceID"] unsignedIntValue]) ||
        !MixroomOutputNameIsUnique(inventory, output)) {
        return NO;
    }
    NSNumber *channels = output[@"outputChannels"];
    if ((id)channels == [NSNull null] || channels.integerValue <= 0) {
        return NO;
    }
    const UInt32 transport = [output[@"transport"] unsignedIntValue];
    if (transport == kAudioDeviceTransportTypeBuiltIn) {
        return YES;
    }
    // Classic Bluetooth is the only Bluetooth recording-output combination
    // supported here. Requiring stereo output also rejects the
    // observable call-quality shape without guessing a profile from its name.
    return transport == kAudioDeviceTransportTypeBluetooth &&
        channels.integerValue >= 2;
}

static NSString *MixroomOutputFingerprint(
    NSDictionary<NSString *, id> *device
) {
    if (device == nil) {
        return @"missing";
    }
    const AudioDeviceID deviceID = [device[@"deviceID"] unsignedIntValue];
    NSString *identity = [device[@"uid"] length] > 0
        ? device[@"uid"]
        : [device[@"deviceID"] stringValue];
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@",
            identity,
            device[@"rawTransport"],
            device[@"outputChannels"],
            device[@"sampleRateHz"],
            device[@"bufferFrames"],
            MixroomCoreAudioDeviceIsAlive(deviceID) ? @"alive" : @"dead"];
}

static NSString *MixroomEffectiveOutputFingerprint(void) {
    AudioDeviceID deviceID = MixroomDefaultCoreAudioOutputDevice();
    NSArray<NSDictionary<NSString *, id> *> *inventory =
        MixroomCoreAudioDeviceInventory();
    NSDictionary<NSString *, id> *device =
        MixroomOutputForDeviceID(inventory ?: @[], deviceID);
    return device == nil
        ? [NSString stringWithFormat:@"%u|missing", (unsigned int)deviceID]
        : MixroomOutputFingerprint(device);
}

static NSString *MixroomCoreAudioInventoryFingerprint(
    NSArray<NSDictionary<NSString *, id> *> *inventory
) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *device in inventory) {
        NSString *identity = [device[@"uid"] length] > 0
            ? device[@"uid"]
            : [device[@"deviceID"] stringValue];
        NSNumber *inputChannels = device[@"inputChannels"];
        NSNumber *outputChannels = device[@"outputChannels"];
        if ((id)inputChannels != [NSNull null] && inputChannels.integerValue > 0) {
            [parts addObject:[NSString stringWithFormat:@"input|%@|%@|%@",
                              identity,
                              device[@"rawTransport"],
                              inputChannels]];
        }
        if ((id)outputChannels != [NSNull null] && outputChannels.integerValue > 0) {
            [parts addObject:[NSString stringWithFormat:@"output|%@|%@|%@",
                              identity,
                              device[@"rawTransport"],
                              outputChannels]];
        }
    }
    [parts sortUsingSelector:@selector(compare:)];
    return [parts componentsJoinedByString:@";"];
}

static NSString *MixroomJuceRouteFingerprint(
    NSDictionary<NSString *, id> *diagnostics
) {
    if (diagnostics == nil) {
        return nil;
    }
    NSArray<NSString *> *keys = @[
        @"deviceOpen",
        @"inputDeviceName",
        @"outputDeviceName",
        @"inputChannelCount",
        @"outputChannelCount",
        @"sampleRate",
        @"bufferSize",
    ];
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:keys.count];
    for (NSString *key in keys) {
        id value = diagnostics[key];
        [parts addObject:[NSString stringWithFormat:@"%@=%@",
                          key,
                          value == nil || value == [NSNull null] ? @"<unavailable>" : value]];
    }
    return [parts componentsJoinedByString:@";"];
}

static NSArray<NSDictionary<NSString *, id> *> *MixroomExactDeviceMatches(
    NSArray<NSDictionary<NSString *, id> *> *inventory,
    NSString *name,
    BOOL input
) {
    NSString *normalizedName = [name stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (normalizedName.length == 0) {
        return @[];
    }
    NSMutableArray<NSDictionary<NSString *, id> *> *matches = [NSMutableArray array];
    NSString *channelKey = input ? @"inputChannels" : @"outputChannels";
    for (NSDictionary<NSString *, id> *device in inventory) {
        NSNumber *channels = device[channelKey];
        NSString *candidateName = [device[@"name"]
            stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([candidateName isEqualToString:normalizedName] &&
            (id)channels != [NSNull null] &&
            channels.integerValue > 0) {
            [matches addObject:device];
        }
    }
    return matches;
}

static NSString *MixroomNormalizedMacRouteKind(UInt32 transport,
                                                BOOL input,
                                                BOOL bluetoothInputActive) {
    if (transport == kAudioDeviceTransportTypeBluetoothLE) {
        return @"bluetoothLe";
    }
    if (transport == kAudioDeviceTransportTypeBluetooth) {
        return input || bluetoothInputActive ? @"bluetoothDuplex" : @"bluetooth";
    }
    if (transport == kAudioDeviceTransportTypeBuiltIn) {
        return @"builtIn";
    }
    if (transport == kAudioDeviceTransportTypeUnknown) {
        return @"unknown";
    }
    return @"external";
}

static NSDictionary<NSString *, id> *MixroomRouteEndpoint(
    NSDictionary<NSString *, id> *device,
    BOOL input,
    BOOL bluetoothInputActive
) {
    const UInt32 transport = [device[@"transport"] unsignedIntValue];
    return @{
        @"direction": input ? @"input" : @"output",
        @"nativePortType": device[@"rawTransport"] ?: @"",
        @"normalizedKind": MixroomNormalizedMacRouteKind(
            transport,
            input,
            bluetoothInputActive
        ),
        @"uid": device[@"uid"] ?: @"",
        @"name": device[@"name"] ?: @"",
        @"clockDomain": device[@"clockDomain"] ?: [NSNull null],
        @"channelCount": device[input ? @"inputChannels" : @"outputChannels"]
            ?: [NSNull null],
    };
}

static BOOL MixroomEndpointMatchesCoreAudioDevice(
    NSDictionary<NSString *, id> *endpoint,
    NSDictionary<NSString *, id> *device,
    BOOL input
) {
    if (endpoint == nil || device == nil || [device[@"uid"] length] == 0) {
        return NO;
    }
    NSString *expectedKind = MixroomNormalizedMacRouteKind(
        [device[@"transport"] unsignedIntValue], input, NO);
    return [endpoint[@"uid"] isEqualToString:device[@"uid"]] &&
        [endpoint[@"nativePortType"] isEqualToString:device[@"rawTransport"]] &&
        [endpoint[@"normalizedKind"] isEqualToString:expectedKind];
}

static BOOL MixroomCoreAudioOutputHasNativeClock(
    NSDictionary<NSString *, id> *output
) {
    return output != nil && [output[@"uid"] length] > 0 &&
        [output[@"outputChannels"] integerValue] > 0 &&
        [output[@"sampleRateHz"] doubleValue] > 1000.0 &&
        [output[@"bufferFrames"] integerValue] > 0;
}

static BOOL MixroomMacOutputIdentityIsUsable(
    NSArray<NSDictionary<NSString *, id> *> *inventory,
    NSDictionary<NSString *, id> *output
) {
    return output != nil &&
        [output[@"uid"] length] > 0 &&
        MixroomCoreAudioDeviceIsAlive([output[@"deviceID"] unsignedIntValue]) &&
        MixroomOutputNameIsUnique(inventory, output);
}

static BOOL MixroomMacOutputIsUsable(
    NSArray<NSDictionary<NSString *, id> *> *inventory,
    NSDictionary<NSString *, id> *output
) {
    return MixroomMacOutputIdentityIsUsable(inventory, output) &&
        MixroomCoreAudioOutputHasNativeClock(output);
}

static NSDictionary<NSString *, id> *MixroomMacPlaybackOpenPlan(
    NSDictionary<NSString *, id> *output,
    double preferredRate,
    NSInteger preferredBuffer
) {
    if (output == nil ||
        MixroomTransportIsBluetooth([output[@"transport"] unsignedIntValue]) ||
        !MixroomHardwareSampleRatePreferenceIsSupported(preferredRate) ||
        !MixroomHardwareBufferPreferenceIsSupported(preferredBuffer)) {
        return output;
    }
    NSMutableDictionary<NSString *, id> *plan =
        [NSMutableDictionary dictionaryWithDictionary:output];
    plan[@"sampleRateHz"] = @(preferredRate);
    plan[@"bufferFrames"] = @(preferredBuffer);
    return plan;
}

static BOOL MixroomMacInputIsUsable(
    NSArray<NSDictionary<NSString *, id> *> *inventory,
    NSDictionary<NSString *, id> *input
) {
    (void)inventory;
    NSString *uid = [input[@"uid"] isKindOfClass:[NSString class]]
        ? input[@"uid"] : nil;
    NSNumber *deviceID = [input[@"deviceID"] isKindOfClass:[NSNumber class]]
        ? input[@"deviceID"] : nil;
    NSNumber *inputChannels =
        [input[@"inputChannels"] isKindOfClass:[NSNumber class]]
            ? input[@"inputChannels"] : nil;
    NSNumber *sampleRate =
        [input[@"sampleRateHz"] isKindOfClass:[NSNumber class]]
            ? input[@"sampleRateHz"] : nil;
    NSNumber *bufferFrames =
        [input[@"bufferFrames"] isKindOfClass:[NSNumber class]]
            ? input[@"bufferFrames"] : nil;
    return uid.length > 0 && deviceID != nil && inputChannels.integerValue > 0 &&
        sampleRate.doubleValue > 1000.0 && bufferFrames.integerValue > 0 &&
        MixroomCoreAudioDeviceIsAlive(deviceID.unsignedIntValue);
}

static NSArray<NSDictionary<NSString *, id> *> *
MixroomMacV2InputDeviceInfos(void) {
    NSArray<NSDictionary<NSString *, id> *> *inventory =
        MixroomCoreAudioDeviceInventory() ?: @[];
    AudioDeviceID defaultInput = MixroomDefaultCoreAudioInputDevice();
    NSMutableArray<NSDictionary<NSString *, id> *> *infos =
        [NSMutableArray array];
    for (NSDictionary<NSString *, id> *device in inventory) {
        if (!MixroomMacInputIsUsable(inventory, device)) {
            continue;
        }
        NSString *name = [device[@"name"]
            stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length == 0) {
            continue;
        }
        const UInt32 transport = [device[@"transport"] unsignedIntValue];
        [infos addObject:@{
            @"uid": device[@"uid"] ?: @"",
            @"name": name,
            @"channelCount": device[@"inputChannels"] ?: @0,
            @"clockDomain": device[@"clockDomain"] ?: [NSNull null],
            @"isBluetoothInput": @(MixroomTransportIsBluetooth(transport)),
            @"isBuiltIn": @(MixroomTransportIsBuiltIn(transport)),
            @"isDefault": @([device[@"deviceID"] unsignedIntValue] ==
                defaultInput),
            @"transport": MixroomTransportLabel(transport),
        }];
    }
    return infos;
}

- (NSDictionary<NSString *, id> *)currentMacPlaybackOutputV2:
    (NSArray<NSDictionary<NSString *, id> *> *)inventory {
    NSArray<NSDictionary<NSString *, id> *> *devices = inventory ?: @[];
    NSString *selectedUID = self.macSelectedOutputUIDV2;
    if (selectedUID.length > 0) {
        NSDictionary *selected = MixroomOutputForUID(devices, selectedUID);
        return MixroomMacOutputIsUsable(devices, selected) ? selected : nil;
    }
    NSDictionary *systemOutput = MixroomOutputForDeviceID(
        devices, MixroomDefaultCoreAudioOutputDevice());
    return MixroomMacOutputIsUsable(devices, systemOutput)
        ? systemOutput : nil;
}

- (NSDictionary<NSString *, id> *)currentMacRecordingInputV2:
    (NSArray<NSDictionary<NSString *, id> *> *)inventory {
    NSArray<NSDictionary<NSString *, id> *> *devices = inventory ?: @[];
    NSString *selectedUID = self.macSelectedInputUIDV2;
    if (selectedUID.length > 0) {
        NSDictionary *selected = MixroomInputForUID(devices, selectedUID);
        if (MixroomMacInputIsUsable(devices, selected)) {
            return selected;
        }
        self.macSelectedInputUIDV2 = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.eventSink != nil) {
                self.eventSink(@{
                    @"event": @"macV2InputPreferenceChanged",
                    @"followsSystemInput": @YES,
                });
            }
        });
    }
    NSDictionary *systemInput = MixroomInputForDeviceID(
        devices, MixroomDefaultCoreAudioInputDevice());
    return MixroomMacInputIsUsable(devices, systemInput) ? systemInput : nil;
}

- (NSString *)currentMacPlaybackOutputFingerprintV2 {
    NSArray<NSDictionary<NSString *, id> *> *inventory =
        MixroomCoreAudioDeviceInventory() ?: @[];
    NSDictionary *output = [self currentMacPlaybackOutputV2:inventory];
    return output == nil ? @"missing" : MixroomOutputFingerprint(output);
}

static BOOL MixroomMacPlaybackSnapshotMatchesPlan(
    NSDictionary<NSString *, id> *snapshot,
    NSDictionary<NSString *, id> *output,
    double callbackRate,
    NSInteger callbackFrames,
    unsigned long long callbackCount
) {
    NSDictionary *juce = [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
        ? snapshot[@"juce"] : @{};
    NSArray *outputs = [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
        ? snapshot[@"outputs"] : @[];
    NSDictionary *actualOutput = outputs.count == 1 ? outputs.firstObject : nil;
    const double nativeRate = [output[@"sampleRateHz"] doubleValue];
    const NSInteger nativeBuffer = [output[@"bufferFrames"] integerValue];
    return MixroomCoreAudioOutputHasNativeClock(output) &&
        [snapshot[@"captureConsistency"] isEqualToString:@"stable"] &&
        [juce[@"deviceOpen"] boolValue] &&
        [juce[@"audioCallbackAttached"] boolValue] &&
        [juce[@"activeInputChannels"] integerValue] == 0 &&
        [juce[@"activeOutputChannels"] integerValue] > 0 &&
        [juce[@"activeOutputChannels"] integerValue] <=
            [output[@"outputChannels"] integerValue] &&
        fabs([juce[@"sampleRateHz"] doubleValue] - nativeRate) < 1.0 &&
        [juce[@"bufferFrames"] integerValue] == nativeBuffer &&
        fabs([juce[@"projectGraphSampleRateHz"] doubleValue] - nativeRate) < 1.0 &&
        [juce[@"projectGraphBufferFrames"] integerValue] == nativeBuffer &&
        callbackCount > 0 && fabs(callbackRate - nativeRate) < 1.0 &&
        callbackFrames == nativeBuffer &&
        MixroomEndpointMatchesCoreAudioDevice(actualOutput, output, NO);
}

static BOOL MixroomSnapshotMatchesRecordingRoute(
    NSDictionary<NSString *, id> *snapshot,
    NSDictionary<NSString *, id> *input,
    NSDictionary<NSString *, id> *output
) {
    NSArray *inputs = [snapshot[@"inputs"] isKindOfClass:[NSArray class]]
        ? snapshot[@"inputs"] : @[];
    NSArray *outputs = [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
        ? snapshot[@"outputs"] : @[];
    NSDictionary *juce = [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
        ? snapshot[@"juce"] : @{};
    NSDictionary *actualInput = inputs.count == 1 ? inputs.firstObject : nil;
    NSDictionary *actualOutput = outputs.count == 1 ? outputs.firstObject : nil;
    return [snapshot[@"captureConsistency"] isEqualToString:@"stable"] &&
        MixroomEndpointMatchesCoreAudioDevice(actualInput, input, YES) &&
        MixroomEndpointMatchesCoreAudioDevice(actualOutput, output, NO) &&
        [actualInput[@"normalizedKind"] isEqualToString:@"builtIn"] &&
        ![actualOutput[@"normalizedKind"] isEqualToString:@"bluetoothDuplex"] &&
        [juce[@"deviceOpen"] boolValue] &&
        [juce[@"audioCallbackAttached"] boolValue] &&
        [juce[@"activeInputChannels"] integerValue] == 1 &&
        [juce[@"activeOutputChannels"] integerValue] > 0 &&
        [juce[@"sampleRateHz"] doubleValue] > 1000.0 &&
        [juce[@"bufferFrames"] integerValue] > 0;
}

static BOOL MixroomMacPlaybackSnapshotHasVerifiedClock(
    NSDictionary<NSString *, id> *snapshot,
    NSDictionary<NSString *, id> *output
) {
    NSDictionary *juce = [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
        ? snapshot[@"juce"] : @{};
    return MixroomMacPlaybackSnapshotMatchesPlan(
        snapshot,
        output,
        [juce[@"sampleRateHz"] doubleValue],
        [juce[@"bufferFrames"] integerValue],
        [juce[@"realtimeCallbackCount"] unsignedLongLongValue]);
}
#endif

#if !TARGET_OS_OSX
static NSInteger MixroomIOSSessionBufferFrames(AVAudioSession *session) {
    if (session.sampleRate <= 1000.0 || session.IOBufferDuration <= 0.0) {
        return 0;
    }
    return (NSInteger)llround(session.sampleRate * session.IOBufferDuration);
}

static BOOL MixroomIOSPlaybackSnapshotMatchesClock(
    NSDictionary<NSString *, id> *snapshot,
    NSDictionary<NSString *, id> *expectedOutput,
    double callbackRate,
    NSInteger callbackFrames,
    unsigned long long callbackCount
) {
    NSDictionary *session = [snapshot[@"session"] isKindOfClass:[NSDictionary class]]
        ? snapshot[@"session"] : @{};
    NSDictionary *juce = [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
        ? snapshot[@"juce"] : @{};
    NSArray *outputs = [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
        ? snapshot[@"outputs"] : @[];
    NSDictionary *actualOutput = outputs.count == 1 ? outputs.firstObject : nil;
    const double actualRate = [session[@"sampleRateHz"] doubleValue];
    const NSInteger actualBuffer = actualRate > 1000.0
        ? (NSInteger)llround(
            actualRate * [session[@"ioBufferDurationSeconds"] doubleValue])
        : 0;
    return [snapshot[@"captureConsistency"] isEqualToString:@"stable"] &&
        MixroomIOSOutputIdentitiesMatch(expectedOutput, actualOutput) &&
        [session[@"category"] isEqual:AVAudioSessionCategoryPlayback] &&
        [session[@"mode"] isEqual:AVAudioSessionModeDefault] &&
        [session[@"inputChannelCount"] integerValue] == 0 &&
        [juce[@"deviceOpen"] boolValue] &&
        [juce[@"audioCallbackAttached"] boolValue] &&
        [juce[@"activeInputChannels"] integerValue] == 0 &&
        [juce[@"activeOutputChannels"] integerValue] > 0 &&
        actualRate > 1000.0 && actualBuffer > 0 &&
        fabs([juce[@"sampleRateHz"] doubleValue] - actualRate) < 1.0 &&
        [juce[@"bufferFrames"] integerValue] == actualBuffer &&
        fabs([juce[@"projectGraphSampleRateHz"] doubleValue] - actualRate) < 1.0 &&
        [juce[@"projectGraphBufferFrames"] integerValue] == actualBuffer &&
        callbackCount > 0 && fabs(callbackRate - actualRate) < 1.0 &&
        callbackFrames == actualBuffer;
}
#endif

static NSString *MixroomFlutterAssetRootPath(void) {
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];

    NSString *privateFrameworksPath = mainBundle.privateFrameworksPath ?: @"";
    if (privateFrameworksPath.length > 0) {
        NSString *frameworkFlutterAssets =
            [[privateFrameworksPath stringByAppendingPathComponent:@"App.framework"]
                stringByAppendingPathComponent:@"flutter_assets"];
        if ([fileManager fileExistsAtPath:frameworkFlutterAssets]) {
            [candidates addObject:frameworkFlutterAssets];
        }
    }

    NSString *assetManifestKey = [FlutterDartProject lookupKeyForAsset:@"AssetManifest.bin"];
    if (assetManifestKey.length == 0) {
        assetManifestKey = [FlutterDartProject lookupKeyForAsset:@"AssetManifest.json"];
    }
    if (assetManifestKey.length > 0) {
        NSString *manifestPath =
            [[mainBundle bundlePath] stringByAppendingPathComponent:assetManifestKey];
        if (manifestPath.length > 0) {
            if ([fileManager fileExistsAtPath:manifestPath]) {
                [candidates addObject:[manifestPath stringByDeletingLastPathComponent]];
            }
        }
    }

    NSString *resourcePath = mainBundle.resourcePath ?: @"";
    if (resourcePath.length > 0) {
        NSString *resourceFlutterAssets =
            [resourcePath stringByAppendingPathComponent:@"flutter_assets"];
        if ([fileManager fileExistsAtPath:resourceFlutterAssets]) {
            [candidates addObject:resourceFlutterAssets];
        } else {
            [candidates addObject:resourcePath];
        }
    }

    NSString *instrumentProbeRelativePath =
        @"assets/instruments/VSCO-2-CE-1.1.0/UprightPiano.sfz";
    for (NSString *candidate in candidates) {
        if (candidate.length == 0) {
            continue;
        }
        NSString *instrumentProbe =
            [candidate stringByAppendingPathComponent:instrumentProbeRelativePath];
        if ([fileManager fileExistsAtPath:instrumentProbe]) {
            return candidate;
        }
    }

    for (NSString *candidate in candidates) {
        if (candidate.length == 0) {
            continue;
        }
        NSString *manifestBin =
            [candidate stringByAppendingPathComponent:@"AssetManifest.bin"];
        NSString *manifestJson =
            [candidate stringByAppendingPathComponent:@"AssetManifest.json"];
        if ([fileManager fileExistsAtPath:manifestBin] ||
            [fileManager fileExistsAtPath:manifestJson]) {
            return candidate;
        }
    }

    if (candidates.count > 0) {
        return candidates.firstObject;
    }

    return @"";
}

- (NSDictionary<NSString *, id> *)buildAudioRouteInfo {
#if TARGET_OS_OSX
    NSString *inputDeviceName = [JuceBridge getCurrentDeviceNameObjC] ?: @"";
    NSString *outputDeviceName = [JuceBridge getCurrentOutputDeviceNameObjC] ?: @"";
    return @{
        @"outputRouteKind": @"unknown",
        @"outputRouteName": outputDeviceName,
        @"inputDeviceName": inputDeviceName,
        @"inputIsBluetoothHeadset": @(MixroomMacInputDeviceNameIsBluetooth(inputDeviceName)),
    };
#else
    AVAudioSession *session = [AVAudioSession sharedInstance];
    AVAudioSessionRouteDescription *route = session.currentRoute;
    AVAudioSessionPortDescription *output = route.outputs.firstObject;
    AVAudioSessionPortDescription *input = route.inputs.firstObject ?: session.preferredInput;
    NSString *inputPortType = input.portType ?: @"";
    BOOL inputIsBluetoothHeadset =
        [inputPortType isEqualToString:AVAudioSessionPortBluetoothHFP] ||
        [inputPortType isEqualToString:AVAudioSessionPortBluetoothLE];

    return @{
        @"outputRouteKind": MixroomRouteKindForPortType(output.portType),
        @"outputRouteName": output.portName ?: @"",
        @"inputDeviceName": input.portName ?: ([JuceBridge getCurrentDeviceNameObjC] ?: @""),
        @"inputIsBluetoothHeadset": @(inputIsBluetoothHeadset),
    };
#endif
}

- (NSDictionary<NSString *, id> *)buildAudioRouteSnapshotV2 {
#if TARGET_OS_OSX
    const double startedAtMs = MixroomMonotonicMilliseconds();
    NSArray<NSDictionary<NSString *, id> *> *firstInventory =
        MixroomCoreAudioDeviceInventory();
    const BOOL lifecycleTransitionInProgress =
        self.macLifecycleTransitionActiveV2 &&
        !MixroomIsOnMacLifecycleQueue();
    NSDictionary<NSString *, id> *firstDiagnostics =
        lifecycleTransitionInProgress
            ? nil : [JuceBridge getEngineDiagnosticsObjC];
    NSArray<NSDictionary<NSString *, id> *> *secondInventory =
        MixroomCoreAudioDeviceInventory();
    NSDictionary<NSString *, id> *secondDiagnostics =
        lifecycleTransitionInProgress
            ? nil : [JuceBridge getEngineDiagnosticsObjC];

    NSMutableDictionary<NSString *, NSString *> *unavailable =
        [NSMutableDictionary dictionary];
    NSString *captureConsistency = @"unavailable";
    if (firstInventory == nil || secondInventory == nil) {
        unavailable[@"coreAudio.inventory"] = @"coreAudioReadFailed";
    } else if (lifecycleTransitionInProgress) {
        unavailable[@"snapshot"] = @"lifecycleTransitionInProgress";
    } else if (firstDiagnostics == nil || secondDiagnostics == nil) {
        unavailable[@"juce.route"] = @"juceDiagnosticsReadFailed";
    } else {
        NSString *firstFingerprint =
            MixroomCoreAudioInventoryFingerprint(firstInventory);
        NSString *secondFingerprint =
            MixroomCoreAudioInventoryFingerprint(secondInventory);
        NSString *firstJuceFingerprint =
            MixroomJuceRouteFingerprint(firstDiagnostics);
        NSString *secondJuceFingerprint =
            MixroomJuceRouteFingerprint(secondDiagnostics);
        const BOOL coreAudioStable =
            [firstFingerprint isEqualToString:secondFingerprint];
        const BOOL juceStable =
            [firstJuceFingerprint isEqualToString:secondJuceFingerprint];
        captureConsistency = coreAudioStable && juceStable
            ? @"stable"
            : @"routeChangedDuringCapture";
    }

    NSArray<NSDictionary<NSString *, id> *> *inventory = secondInventory ?: @[];
    NSDictionary<NSString *, id> *diagnostics = secondDiagnostics ?: @{};
    NSString *inputDeviceName = [diagnostics[@"inputDeviceName"] isKindOfClass:[NSString class]]
        ? diagnostics[@"inputDeviceName"]
        : @"";
    NSString *outputDeviceName = [diagnostics[@"outputDeviceName"] isKindOfClass:[NSString class]]
        ? diagnostics[@"outputDeviceName"]
        : @"";
    NSArray<NSDictionary<NSString *, id> *> *inputMatches =
        MixroomExactDeviceMatches(inventory, inputDeviceName, YES);
    NSArray<NSDictionary<NSString *, id> *> *outputMatches =
        MixroomExactDeviceMatches(inventory, outputDeviceName, NO);

    if (inputDeviceName.length > 0 && inputMatches.count != 1) {
        unavailable[@"route.inputEndpoint"] = inputMatches.count == 0
            ? @"selectedJuceDeviceNotFoundInCoreAudio"
            : @"selectedJuceDeviceNameIsAmbiguous";
    }
    if (outputDeviceName.length > 0 && outputMatches.count != 1) {
        unavailable[@"route.outputEndpoint"] = outputMatches.count == 0
            ? @"selectedJuceDeviceNotFoundInCoreAudio"
            : @"selectedJuceDeviceNameIsAmbiguous";
    }

    const BOOL independentInputActive =
        self.macIntentOperationActiveV2 &&
        [self.macIntentInputFactsV2[@"running"] boolValue];
    NSDictionary<NSString *, id> *selectedInput = independentInputActive
        ? self.macIntentTargetInputV2
        : (inputMatches.count == 1 ? inputMatches.firstObject : nil);
    NSDictionary<NSString *, id> *selectedOutput =
        outputMatches.count == 1 ? outputMatches.firstObject : nil;
    NSNumber *activeInputChannels =
        [diagnostics[@"inputChannelCount"] isKindOfClass:[NSNumber class]]
            ? diagnostics[@"inputChannelCount"]
            : nil;
    const BOOL selectedInputIsBluetooth = selectedInput != nil &&
        MixroomTransportIsBluetooth([selectedInput[@"transport"] unsignedIntValue]);
    const BOOL bluetoothInputActive = selectedInputIsBluetooth &&
        (independentInputActive ||
         (activeInputChannels != nil && activeInputChannels.integerValue > 0));
    const BOOL selectedOutputIsUnspecifiedBluetooth = selectedOutput != nil &&
        [selectedOutput[@"transport"] unsignedIntValue] ==
            kAudioDeviceTransportTypeBluetooth &&
        !bluetoothInputActive;
    if (selectedOutputIsUnspecifiedBluetooth) {
        unavailable[@"route.outputBluetoothProfile"] =
            @"notObservableFromCoreAudioTransport";
    }

    NSArray<NSDictionary<NSString *, id> *> *inputs = selectedInput == nil
        ? @[]
        : @[MixroomRouteEndpoint(selectedInput, YES, bluetoothInputActive)];
    NSArray<NSDictionary<NSString *, id> *> *outputs = selectedOutput == nil
        ? @[]
        : @[MixroomRouteEndpoint(selectedOutput, NO, bluetoothInputActive)];

    NSNumber *nativeSampleRate = selectedOutput[@"sampleRateHz"];
    NSNumber *nativeBufferFrames = selectedOutput[@"bufferFrames"];
    if ((id)nativeSampleRate == [NSNull null]) {
        nativeSampleRate = nil;
    }
    if ((id)nativeBufferFrames == [NSNull null]) {
        nativeBufferFrames = nil;
    }
    NSNumber *nativeBufferDuration = nil;
    if (nativeSampleRate.doubleValue > 0.0 && nativeBufferFrames.integerValue > 0) {
        nativeBufferDuration = @(
            nativeBufferFrames.doubleValue / nativeSampleRate.doubleValue
        );
    }
    if (nativeSampleRate == nil) {
        unavailable[@"session.sampleRateHz"] = @"selectedOutputUnavailable";
    }
    if (nativeBufferDuration == nil) {
        unavailable[@"session.ioBufferDurationSeconds"] = @"selectedOutputUnavailable";
    }

    unavailable[@"session.category"] = @"notApplicableOnMacOS";
    unavailable[@"session.mode"] = @"notApplicableOnMacOS";
    unavailable[@"session.active"] = @"notObservableFromCoreAudio";
    unavailable[@"session.streamRunning"] = @"notObservableFromCurrentJuceDiagnostics";
    unavailable[@"juce.xRunCount"] = @"unsupportedByCurrentCoreAudioBackend";

    NSNumber *deviceOpenValue = [diagnostics[@"deviceOpen"] isKindOfClass:[NSNumber class]]
        ? diagnostics[@"deviceOpen"]
        : nil;
    const BOOL deviceOpen = deviceOpenValue != nil && deviceOpenValue.boolValue;
    if (deviceOpenValue == nil) {
        unavailable[@"juce.deviceOpen"] = @"missingFromJuceDiagnostics";
    }
    if (![diagnostics[@"audioCallbackAttached"] isKindOfClass:[NSNumber class]]) {
        unavailable[@"juce.audioCallbackAttached"] = @"missingFromJuceDiagnostics";
    }
    if (![diagnostics[@"sampleRate"] isKindOfClass:[NSNumber class]]) {
        unavailable[@"juce.sampleRateHz"] = @"missingFromJuceDiagnostics";
    }
    if (![diagnostics[@"bufferSize"] isKindOfClass:[NSNumber class]]) {
        unavailable[@"juce.bufferFrames"] = @"missingFromJuceDiagnostics";
    }
    id (^diagnosticNumber)(NSString *) = ^id(NSString *key) {
        id value = diagnostics[key];
        return [value isKindOfClass:[NSNumber class]] ? value : [NSNull null];
    };
    id (^openDeviceNumber)(NSString *) = ^id(NSString *key) {
        return deviceOpen ? diagnosticNumber(key) : [NSNull null];
    };

    NSDictionary<NSString *, id> *sessionFacts = @{
        @"category": [NSNull null],
        @"mode": [NSNull null],
        @"sampleRateHz": nativeSampleRate ?: [NSNull null],
        @"ioBufferDurationSeconds": nativeBufferDuration ?: [NSNull null],
        @"inputChannelCount": selectedInput == nil
            ? [NSNull null]
            : (independentInputActive
                ? @1 : selectedInput[@"inputChannels"]),
        @"outputChannelCount": selectedOutput == nil
            ? [NSNull null]
            : selectedOutput[@"outputChannels"],
        @"active": [NSNull null],
        @"streamRunning": [NSNull null],
    };
    NSDictionary<NSString *, id> *juceFacts = @{
        @"deviceOpen": deviceOpenValue ?: [NSNull null],
        @"audioCallbackAttached": diagnosticNumber(@"audioCallbackAttached"),
        @"sampleRateHz": openDeviceNumber(@"sampleRate"),
        @"bufferFrames": openDeviceNumber(@"bufferSize"),
        @"projectGraphSampleRateHz": openDeviceNumber(@"projectGraphSampleRate"),
        @"projectGraphBufferFrames": openDeviceNumber(@"projectGraphBufferFrames"),
        @"outputCallbackProofSampleRateHz": diagnosticNumber(
            @"outputCallbackProofSampleRate"),
        @"outputCallbackProofFrames": diagnosticNumber(
            @"outputCallbackProofFrames"),
        @"activeInputChannels": diagnosticNumber(@"inputChannelCount"),
        @"activeOutputChannels": diagnosticNumber(@"outputChannelCount"),
        @"inputDeviceName": inputDeviceName,
        @"outputDeviceName": outputDeviceName,
        @"realtimeCallbackCount": diagnosticNumber(@"realtimeCallbackCount"),
        @"realtimeCallbackLastMs": diagnosticNumber(@"realtimeCallbackLastMs"),
        @"realtimeCallbackMaxMs": diagnosticNumber(@"realtimeCallbackMaxMs"),
        @"realtimeCallbackAverageMs": diagnosticNumber(@"realtimeCallbackAvgMs"),
        @"realtimeCallbackBudgetMs": openDeviceNumber(@"realtimeCallbackBudgetMs"),
        @"realtimeCallbackOverBudgetCount": diagnosticNumber(
            @"realtimeCallbackOverBudgetCount"
        ),
        @"xRunCount": [NSNull null],
    };

    NSISO8601DateFormatter *dateFormatter =
        [[[NSISO8601DateFormatter alloc] init] autorelease];
    dateFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
        NSISO8601DateFormatWithFractionalSeconds;
    NSString *capturedAtUtc = [dateFormatter stringFromDate:[NSDate date]] ?: @"";
    const double captureDurationMs =
        MixroomMonotonicMilliseconds() - startedAtMs;
    NSString *implementation = [JuceBridge getAudioRouteImplementationObjC];
    if (![implementation isEqualToString:@"v2"]) {
        implementation = @"legacy";
    }
    const BOOL coordinatorManaged =
        [implementation isEqualToString:@"v2"] && self.audioRouteMonitoringV2;

    id duplexProbeFacts = self.iosLastDuplexProbeV2 ?: [NSNull null];
    if (!lifecycleTransitionInProgress && self.macIntentOperationActiveV2 &&
        [self.iosLastDuplexProbeV2 isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary<NSString *, id> *liveProbe =
            [NSMutableDictionary dictionaryWithDictionary:self.iosLastDuplexProbeV2];
        NSDictionary<NSString *, id> *captureFacts =
            [JuceBridge getMacInputCaptureFactsV2ObjC] ?: @{};
        liveProbe[@"captureActive"] =
            @([JuceBridge isMacInputRecordingV2ObjC]);
        liveProbe[@"captureAttemptedSamples"] =
            captureFacts[@"attemptedSamples"] ?: @0;
        liveProbe[@"captureAcceptedSamples"] =
            captureFacts[@"acceptedSamples"] ?: @0;
        liveProbe[@"captureDroppedSamples"] =
            captureFacts[@"droppedSamples"] ?: @0;
        liveProbe[@"captureInvalidBlockCount"] =
            captureFacts[@"invalidBlockCount"] ?: @0;
        liveProbe[@"captureSampleRateHz"] =
            captureFacts[@"actualSampleRate"] ?: @0;
        duplexProbeFacts = liveProbe;
    }

    return @{
        @"schemaVersion": @1,
        @"capturedAtUtc": capturedAtUtc,
        @"captureDurationMs": @((NSInteger)(captureDurationMs + 0.5)),
        @"implementation": implementation,
        @"generation": coordinatorManaged
            ? @(self.audioRouteGenerationV2)
            : [NSNull null],
        @"transitionId": coordinatorManaged
            ? @(self.audioRouteTransitionIdV2)
            : [NSNull null],
        @"coordinatorManaged": @(coordinatorManaged),
        @"intent": [implementation isEqualToString:@"v2"]
            ? (self.currentAudioRouteIntentV2 ?: @"playbackOnly")
            : @"playbackOnly",
        @"duplexProbe": duplexProbeFacts,
        @"interruption": [NSNull null],
        @"captureConsistency": captureConsistency,
        @"inputs": inputs,
        @"outputs": outputs,
        @"session": sessionFacts,
        @"juce": juceFacts,
        @"unavailableReasons": unavailable,
    };
#else
    const double startedAtMs = MixroomIOSMonotonicMilliseconds();
    AVAudioSession *session = [AVAudioSession sharedInstance];
    AVAudioSessionRouteDescription *firstRoute = session.currentRoute;
    const BOOL lifecycleTransitionInProgress =
        self.iosLifecycleTransitionActiveV2 &&
        !MixroomIsOnIOSLifecycleQueue();
    NSDictionary<NSString *, id> *diagnostics =
        lifecycleTransitionInProgress
            ? @{}
            : ([JuceBridge getEngineDiagnosticsObjC] ?: @{});
    AVAudioSessionRouteDescription *secondRoute = session.currentRoute;

    NSMutableDictionary<NSString *, NSString *> *unavailable =
        [NSMutableDictionary dictionary];
    NSString *captureConsistency = @"unavailable";
    if (lifecycleTransitionInProgress) {
        unavailable[@"snapshot"] = @"lifecycleTransitionInProgress";
    } else if (firstRoute == nil || secondRoute == nil) {
        unavailable[@"avAudioSession.route"] = @"routeReadFailed";
    } else if (![MixroomIOSRouteFingerprint(firstRoute)
                    isEqualToString:MixroomIOSRouteFingerprint(secondRoute)]) {
        captureConsistency = @"routeChangedDuringCapture";
    } else {
        captureConsistency = @"stable";
    }

    NSArray<NSDictionary<NSString *, id> *> *inputs = secondRoute == nil
        ? @[]
        : MixroomIOSRouteEndpoints(secondRoute, YES);
    NSArray<NSDictionary<NSString *, id> *> *outputs = secondRoute == nil
        ? @[]
        : MixroomIOSRouteEndpoints(secondRoute, NO);
    if (outputs.count == 0) {
        unavailable[@"route.outputEndpoint"] = @"noActiveOutput";
    }

    id (^diagnosticValue)(NSString *) = ^id(NSString *key) {
        id value = diagnostics[key];
        return value ?: [NSNull null];
    };
    NSNumber *deviceOpenValue =
        [diagnostics[@"deviceOpen"] isKindOfClass:[NSNumber class]]
            ? diagnostics[@"deviceOpen"]
            : nil;
    if (deviceOpenValue == nil) {
        unavailable[@"juce.deviceOpen"] = @"missingFromJuceDiagnostics";
    }
    if (![diagnostics[@"audioCallbackAttached"] isKindOfClass:[NSNumber class]]) {
        unavailable[@"juce.audioCallbackAttached"] = @"missingFromJuceDiagnostics";
    }
    if (![diagnostics[@"sampleRate"] isKindOfClass:[NSNumber class]]) {
        unavailable[@"juce.sampleRateHz"] = @"missingFromJuceDiagnostics";
    }
    if (![diagnostics[@"bufferSize"] isKindOfClass:[NSNumber class]]) {
        unavailable[@"juce.bufferFrames"] = @"missingFromJuceDiagnostics";
    }
    if (session.sampleRate <= 0.0) {
        unavailable[@"session.sampleRateHz"] = @"notAvailableFromAVAudioSession";
    }
    if (session.IOBufferDuration <= 0.0) {
        unavailable[@"session.ioBufferDurationSeconds"] =
            @"notAvailableFromAVAudioSession";
    }
    unavailable[@"session.active"] = @"notDirectlyObservableFromAVAudioSession";
    unavailable[@"session.streamRunning"] = @"reportedThroughJuceCallbackState";
    unavailable[@"juce.xRunCount"] = @"unsupportedByCurrentIOSBackend";

    NSISO8601DateFormatter *dateFormatter =
        [[[NSISO8601DateFormatter alloc] init] autorelease];
    dateFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
        NSISO8601DateFormatWithFractionalSeconds;
    NSString *implementation = [JuceBridge getAudioRouteImplementationObjC];
    if (![implementation isEqualToString:@"v2"]) {
        implementation = @"legacy";
    }

    return @{
        @"schemaVersion": @1,
        @"capturedAtUtc": [dateFormatter stringFromDate:[NSDate date]] ?: @"",
        @"captureDurationMs": @((NSInteger)(
            MixroomIOSMonotonicMilliseconds() - startedAtMs + 0.5)),
        @"implementation": implementation,
        @"generation": self.audioRouteMonitoringV2
            ? @(self.audioRouteGenerationV2)
            : [NSNull null],
        @"transitionId": self.audioRouteMonitoringV2
            ? @(self.audioRouteTransitionIdV2)
            : [NSNull null],
        @"coordinatorManaged": @(self.audioRouteMonitoringV2),
        @"intent": [implementation isEqualToString:@"v2"]
            ? (self.currentAudioRouteIntentV2 ?: @"playbackOnly")
            : @"playbackOnly",
        @"duplexProbe": self.iosLastDuplexProbeV2 ?: [NSNull null],
        @"interruption": @{
            @"phase": self.iosInterruptionPhaseV2 ?: @"idle",
            @"wasSuspended": @(self.iosInterruptionWasSuspendedV2),
            @"shouldResumeHint": @(self.iosInterruptionShouldResumeV2),
            @"reason": self.iosInterruptionReasonV2 ?: [NSNull null],
            @"recoveryOutcome":
                self.iosInterruptionRecoveryOutcomeV2 ?: [NSNull null],
        },
        @"captureConsistency": captureConsistency,
        @"inputs": inputs,
        @"outputs": outputs,
        @"session": @{
            @"category": session.category ?: [NSNull null],
            @"mode": session.mode ?: [NSNull null],
            @"categoryOptions": MixroomIOSCategoryOptionNames(
                session.categoryOptions),
            @"sampleRateHz": session.sampleRate > 0.0
                ? @(session.sampleRate)
                : [NSNull null],
            @"ioBufferDurationSeconds": session.IOBufferDuration > 0.0
                ? @(session.IOBufferDuration)
                : [NSNull null],
            @"inputChannelCount": @(session.inputNumberOfChannels),
            @"outputChannelCount": @(session.outputNumberOfChannels),
            @"active": [NSNull null],
            @"streamRunning": [NSNull null],
        },
        @"juce": @{
            @"deviceOpen": deviceOpenValue ?: [NSNull null],
            @"audioCallbackAttached": diagnosticValue(@"audioCallbackAttached"),
            @"duplexProbeCallbackCount": diagnosticValue(
                @"duplexProbeCallbackCount"),
            @"bluetoothDuplexProjectCallbackReady": diagnosticValue(
                @"bluetoothDuplexProjectCallbackReady"),
            @"bluetoothDuplexProjectCallbackCount": diagnosticValue(
                @"bluetoothDuplexProjectCallbackCount"),
            @"sampleRateHz": diagnosticValue(@"sampleRate"),
            @"bufferFrames": diagnosticValue(@"bufferSize"),
            @"projectGraphSampleRateHz": diagnosticValue(
                @"projectGraphSampleRate"),
            @"projectGraphBufferFrames": diagnosticValue(
                @"projectGraphBufferFrames"),
            @"outputCallbackProofSampleRateHz": diagnosticValue(
                @"outputCallbackProofSampleRate"),
            @"outputCallbackProofFrames": diagnosticValue(
                @"outputCallbackProofFrames"),
            @"activeInputChannels": diagnosticValue(@"inputChannelCount"),
            @"activeOutputChannels": diagnosticValue(@"outputChannelCount"),
            @"inputDeviceName": diagnosticValue(@"inputDeviceName"),
            @"outputDeviceName": diagnosticValue(@"outputDeviceName"),
            @"realtimeCallbackCount": diagnosticValue(@"realtimeCallbackCount"),
            @"realtimeCallbackLastMs": diagnosticValue(@"realtimeCallbackLastMs"),
            @"realtimeCallbackMaxMs": diagnosticValue(@"realtimeCallbackMaxMs"),
            @"realtimeCallbackAverageMs": diagnosticValue(@"realtimeCallbackAvgMs"),
            @"realtimeCallbackBudgetMs": diagnosticValue(@"realtimeCallbackBudgetMs"),
            @"realtimeCallbackOverBudgetCount": diagnosticValue(
                @"realtimeCallbackOverBudgetCount"),
            @"xRunCount": [NSNull null],
        },
        @"unavailableReasons": unavailable,
        @"observation": @{
            @"active": @(self.audioRouteMonitoringV2),
            @"meaningfulChangeCount": @(self.audioRouteGenerationV2),
            @"lastCause": self.iosLastObservedRouteCauseV2 ?: [NSNull null],
        },
    };
#endif
}

- (NSDictionary<NSString *, id> *)initialisePlaybackV2 {
    self.preferredPlaybackSampleRateV2 = 0.0;
    self.preferredPlaybackBufferFramesV2 = 0;
#if TARGET_OS_OSX
    self.macSelectedOutputUIDV2 = nil;
    self.macSelectedInputUIDV2 = nil;
    self.currentAudioRouteIntentV2 = @"playbackOnly";
    NSString *before = [JuceBridge getAudioRouteImplementationObjC] ?: @"none";
    if (![before isEqualToString:@"none"] && ![before isEqualToString:@"v2"]) {
        return @{
            @"success": @NO,
            @"diagnosticCode": @"implementation_conflict",
            @"snapshot": [self buildAudioRouteSnapshotV2],
        };
    }

    NSArray<NSDictionary<NSString *, id> *> *inventory =
        MixroomCoreAudioDeviceInventory() ?: @[];
    const AudioDeviceID expectedDefault = MixroomDefaultCoreAudioOutputDevice();
    NSDictionary<NSString *, id> *target =
        MixroomOutputForDeviceID(inventory, expectedDefault);
    const BOOL targetUsable = target != nil &&
        MixroomCoreAudioDeviceIsAlive(expectedDefault) &&
        MixroomOutputNameIsUnique(inventory, target) &&
        MixroomCoreAudioOutputHasNativeClock(target);
    if (!targetUsable) {
        return @{
            @"success": @NO,
            @"diagnosticCode": target == nil ? @"no_output" : @"actual_state_unavailable",
            @"snapshot": [self buildAudioRouteSnapshotV2],
        };
    }
    NSString *expectedFingerprint = MixroomEffectiveOutputFingerprint();
    if (![JuceBridge
            initialiseMacPlaybackV2ObjC:target[@"name"]
            sampleRate:[target[@"sampleRateHz"] doubleValue]
            bufferFrames:[target[@"bufferFrames"] integerValue]]) {
        return @{
            @"success": @NO,
            @"diagnosticCode": @"juce_open_failed",
            @"snapshot": [self buildAudioRouteSnapshotV2],
        };
    }
    [JuceBridge beginMacOutputCallbackProofV2ObjC];
    const BOOL callbackReady =
        [JuceBridge waitForMacOutputCallbackProofV2ObjC:2000];

    NSDictionary<NSString *, id> *snapshot = [self buildAudioRouteSnapshotV2];
    NSDictionary<NSString *, id> *juce =
        [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
            ? snapshot[@"juce"]
            : @{};
    NSArray *outputs = [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
        ? snapshot[@"outputs"]
        : @[];
    NSDictionary *actualOutput = outputs.count == 1 ? outputs.firstObject : nil;
    NSString *consistency =
        [snapshot[@"captureConsistency"] isKindOfClass:[NSString class]]
            ? snapshot[@"captureConsistency"]
            : @"unavailable";
    NSNumber *deviceOpen = [juce[@"deviceOpen"] isKindOfClass:[NSNumber class]]
        ? juce[@"deviceOpen"]
        : nil;
    NSNumber *activeInputs =
        [juce[@"activeInputChannels"] isKindOfClass:[NSNumber class]]
            ? juce[@"activeInputChannels"]
            : nil;
    NSNumber *activeOutputs =
        [juce[@"activeOutputChannels"] isKindOfClass:[NSNumber class]]
            ? juce[@"activeOutputChannels"]
            : nil;
    NSNumber *sampleRate = [juce[@"sampleRateHz"] isKindOfClass:[NSNumber class]]
        ? juce[@"sampleRateHz"]
        : nil;
    NSNumber *bufferFrames = [juce[@"bufferFrames"] isKindOfClass:[NSNumber class]]
        ? juce[@"bufferFrames"]
        : nil;
    const unsigned long long callbackCount =
        [JuceBridge getMacOutputCallbackProofCountV2ObjC]
            .unsignedLongLongValue;
    const NSInteger callbackFrames =
        [JuceBridge getMacOutputCallbackProofFramesV2ObjC].integerValue;
    const double callbackRate =
        [JuceBridge getMacOutputCallbackProofSampleRateV2ObjC].doubleValue;

    NSString *diagnosticCode = @"ok";
    if (MixroomDefaultCoreAudioOutputDevice() != expectedDefault ||
        ![MixroomEffectiveOutputFingerprint() isEqualToString:expectedFingerprint]) {
        diagnosticCode = @"route_unstable";
    } else if (![consistency isEqualToString:@"stable"]) {
        diagnosticCode = @"route_unstable";
    } else if (deviceOpen == nil || !deviceOpen.boolValue) {
        diagnosticCode = @"juce_open_failed";
    } else if (activeInputs == nil || activeOutputs == nil ||
               sampleRate == nil || bufferFrames == nil) {
        diagnosticCode = @"actual_state_unavailable";
    } else if (activeInputs.integerValue != 0) {
        diagnosticCode = @"input_open";
    } else if (activeOutputs.integerValue <= 0 || outputs.count != 1) {
        diagnosticCode = @"no_output";
    } else if (sampleRate.doubleValue <= 0.0 || bufferFrames.integerValue <= 0) {
        diagnosticCode = @"actual_state_unavailable";
    } else if (![actualOutput[@"uid"] isEqualToString:target[@"uid"]]) {
        diagnosticCode = @"actual_state_unavailable";
    } else if (!callbackReady ||
               !MixroomMacPlaybackSnapshotMatchesPlan(
                   snapshot, target, callbackRate, callbackFrames, callbackCount)) {
        diagnosticCode = @"actual_state_unavailable";
    }

    const BOOL success = [diagnosticCode isEqualToString:@"ok"];
    if (!success) {
        [JuceBridge shutdownEngineObjC];
    }
    NSDictionary *defaultInput = MixroomInputForDeviceID(
        MixroomCoreAudioDeviceInventory() ?: @[],
        MixroomDefaultCoreAudioInputDevice());
    const BOOL reducedBluetoothQuality = success &&
        [target[@"transport"] unsignedIntValue] ==
            kAudioDeviceTransportTypeBluetooth &&
        [target[@"outputChannels"] integerValue] == 1 &&
        [defaultInput[@"transport"] unsignedIntValue] ==
            kAudioDeviceTransportTypeBluetooth;
    return @{
        @"success": @(success),
        @"diagnosticCode": diagnosticCode,
        @"bluetoothCommunicationQualityReduced": @(reducedBluetoothQuality),
        @"snapshot": snapshot,
    };
#else
    self.currentAudioRouteIntentV2 = @"playbackOnly";
    self.iosRecordingOutputV2 = nil;
    self.iosRecordingInputV2 = nil;
    [JuceBridge endIOSIntentOperationV2ObjC];
    self.iosIntentOperationActiveV2 = NO;
    self.iosIntentOperationModeV2 = @"standard";
    self.iosIntentMonitoringTargetRowV2 = -1;
    self.iosIntentOperationCancelledV2 = NO;
    self.iosIntentCleanupClaimedV2 = NO;
    self.iosIntentLifecyclePhaseV2 = @"idle";
    self.iosIntentTerminalCauseV2 = nil;
    self.iosIntentRouteConditionV2 = nil;
    self.iosIntentOperationSourceFingerprintV2 = nil;
    self.iosIntentOperationPendingFingerprintV2 = nil;
    self.iosIntentOperationTargetFingerprintV2 = nil;
    self.iosIntentOperationTargetOutputV2 = nil;
    self.iosInterruptionActiveV2 = NO;
    self.iosInterruptionRecoveryPendingV2 = NO;
    self.iosInterruptionWasSuspendedV2 = NO;
    self.iosInterruptionShouldResumeV2 = NO;
    self.iosInterruptionPhaseV2 = @"idle";
    self.iosInterruptionReasonV2 = nil;
    self.iosInterruptionRecoveryOutcomeV2 = nil;
    self.iosForegroundRecoveryPendingV2 = NO;
    self.iosLastDuplexProbeV2 = nil;
    NSString *before = [JuceBridge getAudioRouteImplementationObjC] ?: @"none";
    if (![before isEqualToString:@"none"] && ![before isEqualToString:@"v2"]) {
        return @{
            @"success": @NO,
            @"diagnosticCode": @"implementation_conflict",
            @"snapshot": [self buildAudioRouteSnapshotV2],
        };
    }

    AVAudioSession *session = [AVAudioSession sharedInstance];
    self.iosVerifiedPlaybackOutputFingerprintV2 = nil;
    self.iosVerifiedPlaybackOutputWasBluetoothV2 = NO;
    NSDictionary<NSString *, id> *expectedOutput =
        MixroomIOSSingleOutputEndpoint(session.currentRoute);
    NSString *preflightCode = @"ok";
    if (expectedOutput == nil) {
        preflightCode = @"no_output";
    } else if (!MixroomIOSOutputIdentityIsObservable(expectedOutput)) {
        preflightCode = @"actual_state_unavailable";
    } else if (MixroomIOSOutputIsBluetoothDuplex(expectedOutput)) {
        preflightCode = @"bluetooth_duplex_forbidden";
    }
    if (![preflightCode isEqualToString:@"ok"]) {
        return @{
            @"success": @NO,
            @"diagnosticCode": preflightCode,
            @"snapshot": [self buildAudioRouteSnapshotV2],
        };
    }

    if (![JuceBridge initialisePlaybackV2ObjC:@""]) {
        NSDictionary *policyFacts =
            [JuceBridge getIOSAudioSessionPolicyFactsObjC];
        NSString *policyCode =
            [policyFacts[@"diagnosticCode"] isKindOfClass:[NSString class]]
                ? policyFacts[@"diagnosticCode"] : @"juce_open_failed";
        return @{
            @"success": @NO,
            @"diagnosticCode": policyCode,
            @"snapshot": [self buildAudioRouteSnapshotV2],
        };
    }

    NSDictionary *policyFacts = [JuceBridge getIOSAudioSessionPolicyFactsObjC];
    const BOOL sessionConfigured =
        [policyFacts[@"policy"] isEqualToString:@"v2PlaybackOnly"] &&
        [policyFacts[@"diagnosticCode"] isEqualToString:@"ok"] &&
        [policyFacts[@"activationCount"] integerValue] == 1;
    NSDictionary<NSString *, id> *snapshot = [self buildAudioRouteSnapshotV2];
    NSDictionary<NSString *, id> *sessionFacts =
        [snapshot[@"session"] isKindOfClass:[NSDictionary class]]
            ? snapshot[@"session"]
            : @{};
    NSDictionary<NSString *, id> *juce =
        [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
            ? snapshot[@"juce"]
            : @{};
    NSArray *outputs = [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
        ? snapshot[@"outputs"]
        : @[];
    NSString *consistency =
        [snapshot[@"captureConsistency"] isKindOfClass:[NSString class]]
            ? snapshot[@"captureConsistency"]
            : @"unavailable";
    NSNumber *deviceOpen = [juce[@"deviceOpen"] isKindOfClass:[NSNumber class]]
        ? juce[@"deviceOpen"]
        : nil;
    NSNumber *callbackAttached =
        [juce[@"audioCallbackAttached"] isKindOfClass:[NSNumber class]]
            ? juce[@"audioCallbackAttached"]
            : nil;
    NSNumber *activeInputs =
        [juce[@"activeInputChannels"] isKindOfClass:[NSNumber class]]
            ? juce[@"activeInputChannels"]
            : nil;
    NSNumber *activeOutputs =
        [juce[@"activeOutputChannels"] isKindOfClass:[NSNumber class]]
            ? juce[@"activeOutputChannels"]
            : nil;
    NSNumber *sampleRate = [juce[@"sampleRateHz"] isKindOfClass:[NSNumber class]]
        ? juce[@"sampleRateHz"]
        : nil;
    NSNumber *bufferFrames = [juce[@"bufferFrames"] isKindOfClass:[NSNumber class]]
        ? juce[@"bufferFrames"]
        : nil;
    NSDictionary *output = outputs.count == 1 ? outputs.firstObject : nil;
    NSNumber *sessionInputChannels =
        [sessionFacts[@"inputChannelCount"] isKindOfClass:[NSNumber class]]
            ? sessionFacts[@"inputChannelCount"]
            : nil;

    NSString *diagnosticCode = @"ok";
    if (!sessionConfigured) {
        diagnosticCode = @"actual_state_unavailable";
    } else if (![consistency isEqualToString:@"stable"]) {
        diagnosticCode = @"route_unstable";
    } else if (![sessionFacts[@"category"] isEqual:AVAudioSessionCategoryPlayback] ||
               ![sessionFacts[@"mode"] isEqual:AVAudioSessionModeDefault]) {
        diagnosticCode = @"actual_state_unavailable";
    } else if (deviceOpen == nil || !deviceOpen.boolValue ||
               callbackAttached == nil || !callbackAttached.boolValue) {
        diagnosticCode = @"juce_open_failed";
    } else if (activeInputs == nil || activeOutputs == nil ||
               sampleRate == nil || bufferFrames == nil) {
        diagnosticCode = @"actual_state_unavailable";
    } else if (activeInputs.integerValue != 0) {
        diagnosticCode = @"input_open";
    } else if (sessionInputChannels == nil) {
        diagnosticCode = @"actual_state_unavailable";
    } else if (sessionInputChannels.integerValue != 0) {
        diagnosticCode = @"input_open";
    } else if (activeOutputs.integerValue <= 0 || outputs.count != 1 ||
               ![output[@"uid"] isKindOfClass:[NSString class]] ||
               [output[@"uid"] length] == 0) {
        diagnosticCode = @"no_output";
    } else if (sampleRate.doubleValue <= 0.0 || bufferFrames.integerValue <= 0) {
        diagnosticCode = @"actual_state_unavailable";
    } else if (MixroomIOSOutputIsBluetoothDuplex(output)) {
        diagnosticCode = @"bluetooth_duplex_forbidden";
    } else if (!MixroomIOSOutputIdentitiesMatch(expectedOutput, output)) {
        diagnosticCode = @"route_unstable";
    }

    const BOOL success = [diagnosticCode isEqualToString:@"ok"];
    if (!success) {
        [JuceBridge shutdownEngineObjC];
    } else {
        self.iosVerifiedPlaybackOutputFingerprintV2 =
            MixroomIOSOutputFingerprint(session.currentRoute);
        self.iosVerifiedPlaybackOutputWasBluetoothV2 =
            MixroomIOSOutputIsBluetooth(output);
    }
    return @{
        @"success": @(success),
        @"diagnosticCode": diagnosticCode,
        @"snapshot": snapshot,
    };
#endif
}

#if TARGET_OS_OSX
- (void)signalMacIntentRouteConditionV2 {
    NSCondition *condition = self.macIntentRouteConditionV2;
    if (condition == nil) {
        return;
    }
    [condition lock];
    self.macIntentRouteConditionSignalledV2 = YES;
    [condition broadcast];
    [condition unlock];
}

- (void)signalMacHardwareSettingsConditionV2 {
    NSCondition *condition = self.macHardwareSettingsConditionV2;
    if (condition == nil) {
        return;
    }
    [condition lock];
    [condition broadcast];
    [condition unlock];
}

- (BOOL)settleMacOutputHardwareSettingsV2:
    (NSDictionary<NSString *, id> *)output
    sampleRate:(double)sampleRate
    bufferFrames:(NSInteger)bufferFrames
    generation:(uint64_t)generation
    deadlineMs:(double)deadlineMs
    diagnosticCode:(NSString **)diagnosticCode {
    if (!MixroomCoreAudioOutputSupportsHardwareSettings(
            output, sampleRate, bufferFrames)) {
        if (diagnosticCode != NULL) {
            *diagnosticCode = @"unsupported_hardware_settings";
        }
        return NO;
    }

    const AudioDeviceID deviceID =
        [output[@"deviceID"] unsignedIntValue];
    NSString *expectedUID = output[@"uid"];
    NSCondition *condition = [[NSCondition alloc] init];
    self.macHardwareSettingsConditionV2 = condition;
    [condition release];

    [condition lock];
    const BOOL rateRequested = MixroomSetCoreAudioOutputSampleRate(
        deviceID, sampleRate);
    BOOL rateSettled = NO;
    while (rateRequested && self.audioRouteMonitoringV2 &&
           self.macLifecycleTransitionActiveV2 &&
           generation == self.audioRouteGenerationV2 &&
           MixroomCoreAudioDeviceIsAlive(deviceID)) {
        NSString *actualUID = MixroomStringFromCoreAudioObject(
            deviceID, kAudioDevicePropertyDeviceUID);
        const double actualRate =
            MixroomCoreAudioSampleRate(deviceID).doubleValue;
        if ([actualUID isEqualToString:expectedUID] &&
            fabs(actualRate - sampleRate) < 1.0) {
            rateSettled = YES;
            break;
        }
        const double remainingMs =
            deadlineMs - MixroomMonotonicMilliseconds();
        if (remainingMs <= 0.0) {
            break;
        }
        [condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:
            remainingMs / 1000.0]];
    }

    const BOOL bufferAvailable = rateSettled &&
        MixroomCoreAudioBufferSizeIsAvailable(deviceID, bufferFrames);
    BOOL bufferRequested = NO;
    BOOL settled = NO;
    if (bufferAvailable) {
        bufferRequested = MixroomSetCoreAudioOutputBufferFrames(
            deviceID, bufferFrames);
    }
    while (rateSettled && bufferRequested && self.audioRouteMonitoringV2 &&
           self.macLifecycleTransitionActiveV2 &&
           generation == self.audioRouteGenerationV2 &&
           MixroomCoreAudioDeviceIsAlive(deviceID)) {
        NSString *actualUID = MixroomStringFromCoreAudioObject(
            deviceID, kAudioDevicePropertyDeviceUID);
        const double actualRate =
            MixroomCoreAudioSampleRate(deviceID).doubleValue;
        const NSInteger actualBuffer =
            MixroomCoreAudioBufferFrames(deviceID).integerValue;
        if ([actualUID isEqualToString:expectedUID] &&
            fabs(actualRate - sampleRate) < 1.0 &&
            actualBuffer == bufferFrames) {
            settled = YES;
            break;
        }
        const double remainingMs =
            deadlineMs - MixroomMonotonicMilliseconds();
        if (remainingMs <= 0.0) {
            break;
        }
        [condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:
            remainingMs / 1000.0]];
    }
    [condition unlock];
    if (self.macHardwareSettingsConditionV2 == condition) {
        self.macHardwareSettingsConditionV2 = nil;
    }

    if (!settled && diagnosticCode != NULL) {
        if (!rateRequested) {
            *diagnosticCode = @"hardware_settings_apply_failed";
        } else if (!rateSettled) {
            *diagnosticCode = @"hardware_settings_settle_timeout";
        } else if (!bufferAvailable) {
            *diagnosticCode = @"unsupported_hardware_settings";
        } else if (!bufferRequested) {
            *diagnosticCode = @"hardware_settings_apply_failed";
        } else {
            *diagnosticCode = @"hardware_settings_settle_timeout";
        }
        NSLog(@"[MacV2Hardware] settle failed code=%@ requestedRate=%.0f "
              "requestedBuffer=%ld actualRate=%.0f actualBuffer=%ld",
              *diagnosticCode,
              sampleRate,
              (long)bufferFrames,
              MixroomCoreAudioSampleRate(deviceID).doubleValue,
              (long)MixroomCoreAudioBufferFrames(deviceID).integerValue);
    }
    return settled;
}

- (BOOL)claimMacIntentCleanupV2 {
    @synchronized (self) {
        if (self.macIntentCleanupClaimedV2) {
            return NO;
        }
        self.macIntentCleanupClaimedV2 = YES;
        return YES;
    }
}

- (BOOL)installMacIntentDeviceListenersV2 {
    if (self.macIntentListenersInstalledV2) {
        return YES;
    }
    AudioObjectPropertyAddress defaultInputAddress = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    BOOL installed = YES;
    if (self.macIntentFollowsSystemInputV2) {
        installed = AudioObjectAddPropertyListener(
            kAudioObjectSystemObject,
            &defaultInputAddress,
            MixroomAudioRoutePropertyListenerV2,
            self) == noErr;
    }

    const AudioDeviceID input = self.macIntentObservedInputDeviceV2;
    const AudioDeviceID output = self.macIntentObservedOutputDeviceV2;
    AudioObjectPropertyAddress aliveAddress = {
        kAudioDevicePropertyDeviceIsAlive,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    AudioObjectPropertyAddress rateAddress = {
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    AudioObjectPropertyAddress inputStreamsAddress = {
        kAudioDevicePropertyStreamConfiguration,
        kAudioDevicePropertyScopeInput,
        kMixroomCoreAudioElement,
    };
    if (input != kAudioObjectUnknown) {
        // The permanent route observer already owns output alive/rate/stream
        // evidence. When a Bluetooth headset is both input and output,
        // registering those same listener tuples again makes ownership and
        // removal ambiguous. The operation owns only facts not covered by the
        // output observer.
        if (input != output) {
            installed = AudioObjectAddPropertyListener(input, &aliveAddress,
                MixroomAudioRoutePropertyListenerV2, self) == noErr && installed;
            installed = AudioObjectAddPropertyListener(input, &rateAddress,
                MixroomAudioRoutePropertyListenerV2, self) == noErr && installed;
        }
        installed = AudioObjectAddPropertyListener(input, &inputStreamsAddress,
            MixroomAudioRoutePropertyListenerV2, self) == noErr && installed;
    }
    self.macIntentListenersInstalledV2 = YES;
    if (!installed) {
        [self removeMacIntentDeviceListenersV2];
    }
    return installed;
}

- (void)removeMacIntentDeviceListenersV2 {
    if (!self.macIntentListenersInstalledV2) {
        return;
    }
    AudioObjectPropertyAddress defaultInputAddress = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    if (self.macIntentFollowsSystemInputV2) {
        AudioObjectRemovePropertyListener(
            kAudioObjectSystemObject,
            &defaultInputAddress,
            MixroomAudioRoutePropertyListenerV2,
            self);
    }

    const AudioDeviceID input = self.macIntentObservedInputDeviceV2;
    const AudioDeviceID output = self.macIntentObservedOutputDeviceV2;
    AudioObjectPropertyAddress aliveAddress = {
        kAudioDevicePropertyDeviceIsAlive,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    AudioObjectPropertyAddress rateAddress = {
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    AudioObjectPropertyAddress inputStreamsAddress = {
        kAudioDevicePropertyStreamConfiguration,
        kAudioDevicePropertyScopeInput,
        kMixroomCoreAudioElement,
    };
    if (input != kAudioObjectUnknown) {
        if (input != output) {
            AudioObjectRemovePropertyListener(input, &aliveAddress,
                MixroomAudioRoutePropertyListenerV2, self);
            AudioObjectRemovePropertyListener(input, &rateAddress,
                MixroomAudioRoutePropertyListenerV2, self);
        }
        AudioObjectRemovePropertyListener(input, &inputStreamsAddress,
            MixroomAudioRoutePropertyListenerV2, self);
    }
    self.macIntentListenersInstalledV2 = NO;
    self.macIntentObservedInputDeviceV2 = kAudioObjectUnknown;
    self.macIntentObservedOutputDeviceV2 = kAudioObjectUnknown;
}

- (void)finishMacIntentOperationV2 {
    [self removeMacIntentDeviceListenersV2];
    self.macIntentOperationActiveV2 = NO;
    self.macIntentOperationCancelledV2 = NO;
    self.macIntentCleanupClaimedV2 = NO;
    self.macLifecycleTransitionActiveV2 = NO;
    self.macIntentOperationModeV2 = @"standard";
    self.macIntentLifecyclePhaseV2 = @"complete";
    self.macIntentRouteConditionV2 = nil;
    self.macIntentRouteConditionSignalledV2 = NO;
    self.macIntentFollowsSystemInputV2 = YES;
    self.macIntentOperationGenerationV2 = 0;
    self.macIntentOperationStartedAtMsV2 = 0.0;
    self.macIntentSourceOutputV2 = nil;
    self.macIntentSourceFingerprintV2 = nil;
    self.macIntentTargetInputV2 = nil;
    self.macIntentTargetOutputV2 = nil;
    self.macIntentVerifiedOutputV2 = nil;
    self.macIntentInputFactsV2 = nil;
    self.macIntentMonitoringTargetRowV2 = -1;
}

- (void)emitMacIntentRouteInvalidationEventV2:(BOOL)recordingWasActive
                           monitoringWasActive:(BOOL)monitoringWasActive {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.audioRouteMonitoringV2 || self.eventSink == nil) {
            self.macIntentRecoveryPendingV2 = NO;
            return;
        }
        self.audioRouteGenerationV2 += 1;
        NSArray *inventory = MixroomCoreAudioDeviceInventory() ?: @[];
        NSDictionary *output = [self currentMacPlaybackOutputV2:inventory];
        NSString *fingerprint = output == nil
            ? @"missing" : MixroomOutputFingerprint(output);
        self.audioRouteFingerprintV2 = fingerprint;
        [self updateObservedOutputDeviceV2:output == nil
            ? kAudioObjectUnknown
            : [output[@"deviceID"] unsignedIntValue]];
        self.eventSink(@{
            @"event": @"audioRouteChangedV2",
            @"generation": @(self.audioRouteGenerationV2),
            @"cause": recordingWasActive
                ? @"recordingRouteInvalidated"
                : (monitoringWasActive
                    ? @"monitoringRouteInvalidated"
                    : @"recordingPreparationInvalidated"),
            @"fingerprint": fingerprint ?: @"",
            @"transportWasPlaying": @NO,
            @"snapshot": [self buildAudioRouteSnapshotV2],
        });
    });
}

// Validate the existing monitor session without opening, closing, or retargeting it.
// Recording is a second consumer of this session, not a new input lifecycle.
- (BOOL)isMacMonitoringSessionReusableV2 {
    if (!self.macIntentOperationActiveV2 || self.macIntentOperationCancelledV2 ||
        ![self.macIntentOperationModeV2 isEqualToString:@"systemSelectedMonitoring"] ||
        self.macIntentOperationGenerationV2 != self.audioRouteGenerationV2 ||
        (![self.currentAudioRouteIntentV2 isEqualToString:@"monitoring"] &&
         ![self.currentAudioRouteIntentV2 isEqualToString:@"recording"])) {
        return NO;
    }
    NSArray *inventory = MixroomCoreAudioDeviceInventory() ?: @[];
    NSDictionary *input = [self currentMacRecordingInputV2:inventory];
    NSDictionary *output = [self currentMacPlaybackOutputV2:inventory];
    NSDictionary *inputFacts = [JuceBridge getMacInputProbeFactsV2ObjC] ?: @{};
    NSDictionary *monitor = [JuceBridge getMacIndependentInputMonitoringFactsV2ObjC] ?: @{};
    NSDictionary *snapshot = [self buildAudioRouteSnapshotV2];
    NSDictionary *juce = snapshot[@"juce"] ?: @{};
    return input != nil && output != nil &&
        [input[@"uid"] isEqualToString:self.macIntentTargetInputV2[@"uid"]] &&
        [output[@"uid"] isEqualToString:self.macIntentVerifiedOutputV2[@"uid"]] &&
        MixroomCoreAudioDeviceIsAlive([input[@"deviceID"] unsignedIntValue]) &&
        MixroomCoreAudioDeviceIsAlive([output[@"deviceID"] unsignedIntValue]) &&
        [MixroomOutputFingerprint(output) isEqualToString:self.macIntentSourceFingerprintV2] &&
        MixroomMacMonitoringSharesClockDomain(input, output) &&
        [inputFacts[@"running"] boolValue] &&
        [inputFacts[@"callbackCount"] unsignedLongLongValue] > 0 &&
        [inputFacts[@"invalidCallbackCount"] unsignedLongLongValue] == 0 &&
        [inputFacts[@"channelStart"] integerValue] == self.macIntentRecordingChannelStartV2 &&
        [inputFacts[@"channelCount"] integerValue] == self.macIntentRecordingChannelCountV2 &&
        fabs([input[@"sampleRateHz"] doubleValue] - [inputFacts[@"sampleRateHz"] doubleValue]) < 1.0 &&
        [input[@"bufferFrames"] integerValue] == [inputFacts[@"bufferFrames"] integerValue] &&
        [monitor[@"active"] boolValue] &&
        [monitor[@"targetRow"] integerValue] == self.macIntentMonitoringTargetRowV2 &&
        [monitor[@"channelCount"] integerValue] == self.macIntentRecordingChannelCountV2 &&
        [snapshot[@"captureConsistency"] isEqualToString:@"stable"] &&
        [juce[@"deviceOpen"] boolValue] && [juce[@"audioCallbackAttached"] boolValue] &&
        [juce[@"activeInputChannels"] integerValue] == 0 &&
        [juce[@"activeOutputChannels"] integerValue] > 0 &&
        fabs([juce[@"sampleRateHz"] doubleValue] - [inputFacts[@"sampleRateHz"] doubleValue]) < 1.0;
}

- (BOOL)startMacIndependentInputRecordingV2:(NSString *)path
                                channelStart:(NSInteger)channelStart
                                channelCount:(NSInteger)channelCount {
    const BOOL monitoringCapture =
        [self.currentAudioRouteIntentV2 isEqualToString:@"monitoring"] &&
        [self isMacMonitoringSessionReusableV2];
    const BOOL preparedCapture =
        [self.macIntentOperationModeV2 isEqualToString:@"systemSelectedRecording"] &&
        [self.currentAudioRouteIntentV2 isEqualToString:@"preparingRecording"];
    if ((!monitoringCapture && !preparedCapture) ||
        [JuceBridge isMacInputRecordingV2ObjC] ||
        !self.macIntentOperationActiveV2 ||
        self.macIntentOperationCancelledV2 ||
        self.macIntentOperationGenerationV2 != self.audioRouteGenerationV2 ||
        path.length == 0 ||
        channelStart != self.macIntentRecordingChannelStartV2 ||
        channelCount != self.macIntentRecordingChannelCountV2) {
        return NO;
    }

    NSArray<NSDictionary<NSString *, id> *> *inventory =
        MixroomCoreAudioDeviceInventory() ?: @[];
    NSDictionary *input = [self currentMacRecordingInputV2:inventory];
    NSDictionary *output = [self currentMacPlaybackOutputV2:inventory];
    NSDictionary *expectedInput = self.macIntentTargetInputV2;
    NSDictionary *expectedOutput = self.macIntentVerifiedOutputV2;
    NSDictionary *inputFacts =
        [JuceBridge getMacInputProbeFactsV2ObjC] ?: @{};
    NSDictionary *diagnostics = [JuceBridge getEngineDiagnosticsObjC] ?: @{};
    const BOOL routeStable = input != nil && output != nil &&
        expectedInput != nil && expectedOutput != nil &&
        [input[@"uid"] isEqualToString:expectedInput[@"uid"]] &&
        [output[@"uid"] isEqualToString:expectedOutput[@"uid"]];
    const BOOL inputReady = [inputFacts[@"running"] boolValue] &&
        [inputFacts[@"callbackCount"] unsignedLongLongValue] > 0 &&
        [inputFacts[@"invalidCallbackCount"] unsignedLongLongValue] == 0 &&
        [inputFacts[@"sampleRateHz"] doubleValue] > 1000.0 &&
        fabs([inputFacts[@"sampleRateHz"] doubleValue] -
             [expectedInput[@"sampleRateHz"] doubleValue]) < 1.0 &&
        [inputFacts[@"bufferFrames"] integerValue] > 0 &&
        [inputFacts[@"channelStart"] integerValue] == channelStart &&
        [inputFacts[@"channelCount"] integerValue] == channelCount;
    const BOOL outputReady = [diagnostics[@"deviceOpen"] boolValue] &&
        [diagnostics[@"audioCallbackAttached"] boolValue] &&
        [diagnostics[@"inputChannelCount"] integerValue] == 0 &&
        [diagnostics[@"outputChannelCount"] integerValue] > 0 &&
        fabs([diagnostics[@"sampleRate"] doubleValue] -
             [expectedOutput[@"sampleRateHz"] doubleValue]) < 1.0 &&
        [diagnostics[@"bufferSize"] integerValue] ==
            [expectedOutput[@"bufferFrames"] integerValue] &&
        fabs([diagnostics[@"projectGraphSampleRate"] doubleValue] -
             [expectedOutput[@"sampleRateHz"] doubleValue]) < 1.0 &&
        [diagnostics[@"projectGraphBufferFrames"] integerValue] ==
            [expectedOutput[@"bufferFrames"] integerValue] &&
        fabs([diagnostics[@"outputCallbackProofSampleRate"] doubleValue] -
             [expectedOutput[@"sampleRateHz"] doubleValue]) < 1.0 &&
        [diagnostics[@"outputCallbackProofFrames"] integerValue] ==
            [expectedOutput[@"bufferFrames"] integerValue];
    if (!routeStable || !inputReady || !outputReady)
        return NO;

    if (![JuceBridge startMacInputRecordingV2ObjC:path
                                      channelStart:channelStart
                                      channelCount:channelCount])
        return NO;

    NSDictionary *captureFacts =
        [JuceBridge getMacInputCaptureFactsV2ObjC] ?: @{};
    const BOOL captureReady = [JuceBridge isMacInputRecordingV2ObjC] &&
        [captureFacts[@"active"] boolValue] &&
        [captureFacts[@"channelCount"] integerValue] == channelCount &&
        fabs([captureFacts[@"actualSampleRate"] doubleValue] -
             [inputFacts[@"sampleRateHz"] doubleValue]) < 1.0;
    if (!captureReady) {
        [JuceBridge discardMacInputRecordingV2ObjC];
        return NO;
    }
    return YES;
}
#else
- (void)signalIOSIntentRouteConditionV2 {
    NSCondition *condition = self.iosIntentRouteConditionV2;
    if (condition == nil) {
        return;
    }
    [condition lock];
    self.iosIntentRouteConditionSignalledV2 = YES;
    [condition broadcast];
    [condition unlock];
}

- (BOOL)claimIOSIntentCleanupV2 {
    @synchronized (self) {
        if (self.iosIntentCleanupClaimedV2) {
            return NO;
        }
        self.iosIntentCleanupClaimedV2 = YES;
        return YES;
    }
}
#endif

- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {
#if TARGET_OS_OSX
    const double startedAtMs = MixroomMonotonicMilliseconds();
    const uint64_t generation = [args[@"generation"] unsignedLongLongValue];
    NSString *intent = [args[@"intent"] isKindOfClass:[NSString class]]
        ? args[@"intent"]
        : @"";
    NSString *intentOperation =
        [args[@"intentOperation"] isKindOfClass:[NSString class]]
            ? args[@"intentOperation"] : @"standard";
    const NSInteger recordingChannelStart =
        [args[@"recordingChannelStart"] isKindOfClass:[NSNumber class]]
            ? [args[@"recordingChannelStart"] integerValue] : 0;
    const NSInteger recordingChannelCount =
        [args[@"recordingChannelCount"] isKindOfClass:[NSNumber class]]
            ? [args[@"recordingChannelCount"] integerValue] : 1;
    const NSInteger monitoringTargetRow =
        [args[@"monitoringTargetRow"] isKindOfClass:[NSNumber class]]
            ? [args[@"monitoringTargetRow"] integerValue] : -1;
    const NSInteger requiredInputChannels =
        recordingChannelStart + recordingChannelCount;
    const BOOL validRecordingSelection = recordingChannelStart >= 0 &&
        (recordingChannelCount == 1 || recordingChannelCount == 2) &&
        requiredInputChannels >= 1 && requiredInputChannels <= 32;
    const BOOL monitoringIntent = [intent isEqualToString:@"monitoring"];
    const BOOL systemSelectedMonitoring =
        [intentOperation isEqualToString:@"systemSelectedMonitoring"];
    const BOOL inputLifecycleIntent =
        [intent isEqualToString:@"preparingRecording"] || monitoringIntent;
    self.audioRouteTransitionIdV2 += 1;
    const uint64_t transitionID = self.audioRouteTransitionIdV2;
    NSString *diagnosticCode = @"ok";
    BOOL success = NO;
    BOOL restoredAfterFailure = NO;

    NSInteger (^remainingMilliseconds)(double) = ^NSInteger(double deadlineMs) {
        return MAX(0, (NSInteger)(deadlineMs -
            MixroomMonotonicMilliseconds()));
    };
    BOOL (^restorationAllowed)(void) = ^BOOL {
        return !self.macIntentOperationCancelledV2 ||
            [self.macIntentTerminalCauseV2 isEqualToString:@"cancelled"];
    };
    BOOL (^outputSnapshotIsValid)(NSDictionary *, NSDictionary *) =
        ^BOOL(NSDictionary *snapshot, NSDictionary *expectedOutput) {
            NSDictionary *juce =
                [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
                    ? snapshot[@"juce"] : @{};
            NSArray *outputs =
                [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
                    ? snapshot[@"outputs"] : @[];
            NSDictionary *actualOutput =
                outputs.count == 1 ? outputs.firstObject : nil;
            return [snapshot[@"captureConsistency"] isEqualToString:@"stable"] &&
                [juce[@"deviceOpen"] boolValue] &&
                [juce[@"audioCallbackAttached"] boolValue] &&
                [juce[@"activeInputChannels"] integerValue] == 0 &&
                [juce[@"activeOutputChannels"] integerValue] > 0 &&
                [juce[@"activeOutputChannels"] integerValue] <=
                    [expectedOutput[@"outputChannels"] integerValue] &&
                [juce[@"sampleRateHz"] doubleValue] > 1000.0 &&
                fabs([juce[@"sampleRateHz"] doubleValue] -
                     [expectedOutput[@"sampleRateHz"] doubleValue]) < 1.0 &&
                [expectedOutput[@"bufferFrames"] integerValue] > 0 &&
                [juce[@"bufferFrames"] integerValue] ==
                    [expectedOutput[@"bufferFrames"] integerValue] &&
                fabs([juce[@"projectGraphSampleRateHz"] doubleValue] -
                     [expectedOutput[@"sampleRateHz"] doubleValue]) < 1.0 &&
                [juce[@"projectGraphBufferFrames"] integerValue] ==
                    [expectedOutput[@"bufferFrames"] integerValue] &&
                actualOutput != nil && expectedOutput != nil &&
                [actualOutput[@"uid"] isEqualToString:expectedOutput[@"uid"]] &&
                [actualOutput[@"channelCount"] integerValue] ==
                    [expectedOutput[@"outputChannels"] integerValue];
        };

    void (^releaseOperation)(void) = ^{
        [self finishMacIntentOperationV2];
    };

    BOOL (^restoreSourceOutput)(void) = ^BOOL {
        NSDictionary *source = self.macIntentSourceOutputV2;
        if (source == nil || !restorationAllowed()) {
            NSLog(@"[MacV2Route] op=%llu phase=restore preflight=failed source=%@ cancelled=%d",
                  (unsigned long long)self.macIntentOperationIdV2,
                  source == nil ? @"missing" : @"present",
                  self.macIntentOperationCancelledV2);
            return NO;
        }
        const double restoreDeadline =
            MixroomMonotonicMilliseconds() + 2000.0;
        NSArray *inventory = MixroomCoreAudioDeviceInventory() ?: @[];
        NSDictionary *candidate =
            MixroomOutputForUID(inventory, source[@"uid"]);
        NSDictionary *policyOutput =
            [self currentMacPlaybackOutputV2:inventory];
        const BOOL samePolicyOutput = candidate != nil && policyOutput != nil &&
            [candidate[@"uid"] isEqualToString:policyOutput[@"uid"]];
        if (candidate == nil || !restorationAllowed()) {
            NSLog(@"[MacV2Route] op=%llu phase=restore candidate=%@ cancelled=%d",
                  (unsigned long long)self.macIntentOperationIdV2,
                  candidate == nil ? @"missing" : @"present",
                  self.macIntentOperationCancelledV2);
            return NO;
        }
        const BOOL candidateAlive = MixroomCoreAudioDeviceIsAlive(
            [candidate[@"deviceID"] unsignedIntValue]);
        const BOOL candidateNameUnique =
            MixroomOutputNameIsUnique(inventory, candidate);
        if (!samePolicyOutput || !candidateAlive ||
            !candidateNameUnique) {
            NSLog(@"[MacV2Route] op=%llu phase=restore samePolicy=%d alive=%d unique=%d",
                  (unsigned long long)self.macIntentOperationIdV2,
                  samePolicyOutput,
                  candidateAlive,
                  candidateNameUnique);
            return NO;
        }
        NSMutableSet<NSString *> *attemptedFingerprints =
            [NSMutableSet set];
        BOOL opened = NO;
        NSInteger openAttempts = 0;
        while (!opened && restorationAllowed() &&
               self.macIntentOperationGenerationV2 ==
                   self.audioRouteGenerationV2 &&
               remainingMilliseconds(restoreDeadline) > 0) {
            inventory = MixroomCoreAudioDeviceInventory() ?: @[];
            candidate = MixroomOutputForUID(inventory, source[@"uid"]);
            policyOutput = [self currentMacPlaybackOutputV2:inventory];
            const BOOL candidateStillUsable = candidate != nil &&
                policyOutput != nil &&
                [candidate[@"uid"] isEqualToString:policyOutput[@"uid"]] &&
                MixroomCoreAudioDeviceIsAlive(
                    [candidate[@"deviceID"] unsignedIntValue]) &&
                MixroomOutputNameIsUnique(inventory, candidate);
            if (!candidateStillUsable) {
                break;
            }

            NSString *observedFingerprint =
                MixroomOutputFingerprint(candidate);
            if (![attemptedFingerprints containsObject:observedFingerprint]) {
                [attemptedFingerprints addObject:observedFingerprint];
                openAttempts += 1;
                [JuceBridge beginMacOutputCallbackProofV2ObjC];
                opened = [JuceBridge
                    reconfigureMacPlaybackRouteV2ObjC:candidate[@"name"]
                    sampleRate:[source[@"sampleRateHz"] doubleValue]
                    bufferFrames:[source[@"bufferFrames"] integerValue]];
                if (opened) {
                    break;
                }
                [JuceBridge cancelMacOutputCallbackProofV2ObjC];
            }

            const double remainingSeconds =
                (restoreDeadline - MixroomMonotonicMilliseconds()) / 1000.0;
            NSCondition *condition = self.macIntentRouteConditionV2;
            if (remainingSeconds <= 0.0 || condition == nil) {
                break;
            }
            [condition lock];
            if (!self.macIntentRouteConditionSignalledV2) {
                [condition waitUntilDate:
                    [NSDate dateWithTimeIntervalSinceNow:remainingSeconds]];
            }
            self.macIntentRouteConditionSignalledV2 = NO;
            [condition unlock];
        }
        const NSInteger remaining = remainingMilliseconds(restoreDeadline);
        const BOOL callbackReady = opened && remaining > 0 &&
            [JuceBridge waitForMacOutputCallbackProofV2ObjC:remaining];
        NSArray *restoredInventory =
            MixroomCoreAudioDeviceInventory() ?: @[];
        NSDictionary *restoredOutput =
            MixroomOutputForUID(restoredInventory, source[@"uid"]);
        self.macIntentTargetOutputV2 = restoredOutput ?: candidate;
        NSDictionary *snapshot = [self buildAudioRouteSnapshotV2];
        NSDictionary *juce =
            [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
                ? snapshot[@"juce"] : @{};
        const BOOL restoredPresent = restoredOutput != nil;
        const BOOL snapshotValid =
            outputSnapshotIsValid(snapshot, restoredOutput ?: candidate);
        const BOOL sourceProfileRestored = restoredOutput != nil &&
            [MixroomOutputFingerprint(restoredOutput)
                isEqualToString:self.macIntentSourceFingerprintV2];
        const BOOL generationValid = self.macIntentOperationGenerationV2 ==
            self.audioRouteGenerationV2;
        const unsigned long long callbackCount =
            [JuceBridge getMacOutputCallbackProofCountV2ObjC]
                .unsignedLongLongValue;
        const NSInteger callbackFrames =
            [JuceBridge getMacOutputCallbackProofFramesV2ObjC]
                .integerValue;
        const double callbackRate =
            [JuceBridge getMacOutputCallbackProofSampleRateV2ObjC]
                .doubleValue;
        const BOOL callbackShapeValid = callbackFrames > 0 &&
            callbackFrames == [juce[@"bufferFrames"] integerValue] &&
            fabs(callbackRate - [juce[@"sampleRateHz"] doubleValue]) < 1.0;
        NSLog(@"[MacV2Route] op=%llu phase=restore attempts=%ld opened=%d callbackReady=%d "
              "restored=%d snapshot=%d sourceProfile=%d generation=%d callbacks=%llu "
              "callbackFrames=%ld callbackShape=%d "
              "sourceRate=%@ sourceBuffer=%@ restoredRate=%@ restoredBuffer=%@ "
              "juceRate=%@ juceBuffer=%@",
              (unsigned long long)self.macIntentOperationIdV2,
              (long)openAttempts,
              opened,
              callbackReady,
              restoredPresent,
              snapshotValid,
              sourceProfileRestored,
              generationValid,
              callbackCount,
              (long)callbackFrames,
              callbackShapeValid,
              source[@"sampleRateHz"] ?: @"missing",
              source[@"bufferFrames"] ?: @"missing",
              restoredOutput[@"sampleRateHz"] ?: @"missing",
              restoredOutput[@"bufferFrames"] ?: @"missing",
              juce[@"sampleRateHz"] ?: @"missing",
              juce[@"bufferFrames"] ?: @"missing");
        const BOOL restorationVerified = callbackReady && restoredPresent &&
            snapshotValid && sourceProfileRestored && generationValid &&
            callbackCount > 0 && callbackShapeValid;
        if (!restorationVerified) {
            [JuceBridge cancelMacOutputCallbackProofV2ObjC];
            [JuceBridge quiescePlaybackRouteV2ObjC:YES];
        }
        return restorationVerified;
    };

    if (!self.audioRouteMonitoringV2 ||
        ![[JuceBridge getAudioRouteImplementationObjC] isEqualToString:@"v2"]) {
        diagnosticCode = @"coordinator_disposed";
    } else if (generation != self.audioRouteGenerationV2) {
        diagnosticCode = @"stale_generation";
    } else if ([intent isEqualToString:@"recording"]) {
        NSArray<NSDictionary<NSString *, id> *> *inventory =
            MixroomCoreAudioDeviceInventory() ?: @[];
        NSDictionary *currentInput =
            [self currentMacRecordingInputV2:inventory];
        NSDictionary *currentOutput =
            [self currentMacPlaybackOutputV2:inventory];
        NSDictionary *expectedInput = self.macIntentTargetInputV2;
        NSDictionary *expectedOutput = self.macIntentVerifiedOutputV2;
        NSDictionary *snapshot = [self buildAudioRouteSnapshotV2];
        NSDictionary *captureFacts =
            [JuceBridge getMacInputCaptureFactsV2ObjC] ?: @{};
        const BOOL routeStable = currentInput != nil && currentOutput != nil &&
            expectedInput != nil && expectedOutput != nil &&
            [currentInput[@"uid"] isEqualToString:expectedInput[@"uid"]] &&
            [currentOutput[@"uid"] isEqualToString:expectedOutput[@"uid"]] &&
            self.macIntentOperationGenerationV2 == self.audioRouteGenerationV2;
        const BOOL captureReady =
            [JuceBridge isMacInputRecordingV2ObjC] &&
            [captureFacts[@"active"] boolValue] &&
            [captureFacts[@"actualSampleRate"] doubleValue] > 1000.0 &&
            fabs([captureFacts[@"actualSampleRate"] doubleValue] -
                 [self.macIntentInputFactsV2[@"sampleRateHz"] doubleValue]) < 1.0 &&
            [captureFacts[@"channelCount"] integerValue] ==
                self.macIntentRecordingChannelCountV2 &&
            [captureFacts[@"droppedSamples"] longLongValue] == 0 &&
            [captureFacts[@"invalidBlockCount"] longLongValue] == 0;
        const BOOL monitoringCapture = [self isMacMonitoringSessionReusableV2];
        const BOOL preparedCapture =
            [self.macIntentOperationModeV2 isEqualToString:@"systemSelectedRecording"] &&
            [self.currentAudioRouteIntentV2 isEqualToString:@"preparingRecording"];
        success = self.macIntentOperationActiveV2 &&
            (monitoringCapture || preparedCapture) &&
            !self.macIntentOperationCancelledV2 && routeStable &&
            captureReady && outputSnapshotIsValid(snapshot, expectedOutput);
        if (success) {
            self.currentAudioRouteIntentV2 = @"recording";
            self.macIntentLifecyclePhaseV2 = @"recording";
            NSMutableDictionary<NSString *, id> *recordingFacts =
                [NSMutableDictionary dictionaryWithDictionary:
                    self.iosLastDuplexProbeV2 ?: @{}];
            recordingFacts[@"status"] = @"recording";
            recordingFacts[@"phase"] = @"recording";
            recordingFacts[@"validationStage"] = @"recording";
            recordingFacts[@"captureActive"] = @YES;
            recordingFacts[@"captureSampleRateHz"] =
                captureFacts[@"actualSampleRate"] ?: @0;
            recordingFacts[@"captureAttemptedSamples"] =
                captureFacts[@"attemptedSamples"] ?: @0;
            recordingFacts[@"captureAcceptedSamples"] =
                captureFacts[@"acceptedSamples"] ?: @0;
            recordingFacts[@"captureDroppedSamples"] =
                captureFacts[@"droppedSamples"] ?: @0;
            recordingFacts[@"captureInvalidBlockCount"] =
                captureFacts[@"invalidBlockCount"] ?: @0;
            self.iosLastDuplexProbeV2 = recordingFacts;
        } else {
            diagnosticCode = self.macIntentOperationCancelledV2 || !routeStable
                ? @"route_unstable" : @"actual_state_unavailable";
        }
    } else if (monitoringIntent && systemSelectedMonitoring &&
               self.macIntentOperationActiveV2 &&
               [self.macIntentOperationModeV2 isEqualToString:@"systemSelectedMonitoring"]) {
        const BOOL reusesMacMonitoringRoute =
            [self isMacMonitoringSessionReusableV2] &&
            ![JuceBridge isMacInputRecordingV2ObjC] &&
            monitoringTargetRow == self.macIntentMonitoringTargetRowV2 &&
            recordingChannelStart == self.macIntentRecordingChannelStartV2 &&
            recordingChannelCount == self.macIntentRecordingChannelCountV2;
        success = reusesMacMonitoringRoute;
        diagnosticCode = success ? @"ok" : @"route_unstable";
        if (success) {
            self.currentAudioRouteIntentV2 = @"monitoring";
            self.macIntentLifecyclePhaseV2 = @"monitoring";
            NSMutableDictionary *facts = [NSMutableDictionary dictionaryWithDictionary:
                self.iosLastDuplexProbeV2 ?: @{}];
            facts[@"status"] = @"monitoring";
            facts[@"phase"] = @"monitoring";
            facts[@"captureActive"] = @NO;
            self.iosLastDuplexProbeV2 = facts;
        }
    } else if (inputLifecycleIntent &&
               ((!monitoringIntent &&
                 ![intentOperation isEqualToString:@"systemSelectedRecording"]) ||
                (monitoringIntent &&
                 (!systemSelectedMonitoring || monitoringTargetRow < 0)))) {
        diagnosticCode = @"recording_route_unsupported";
    } else if (inputLifecycleIntent) {
        NSArray<NSDictionary<NSString *, id> *> *inventory =
            MixroomCoreAudioDeviceInventory() ?: @[];
        NSDictionary *input = [self currentMacRecordingInputV2:inventory];
        const BOOL followsSystemInput = self.macSelectedInputUIDV2.length == 0;
        const AudioDeviceID inputDeviceID = input == nil
            ? kAudioObjectUnknown
            : [input[@"deviceID"] unsignedIntValue];
        NSDictionary *policyOutput =
            [self currentMacPlaybackOutputV2:inventory];
        const AudioDeviceID defaultOutputID = policyOutput == nil
            ? kAudioObjectUnknown
            : [policyOutput[@"deviceID"] unsignedIntValue];
        NSDictionary *output = policyOutput;
        NSDictionary *sourceSnapshot = [self buildAudioRouteSnapshotV2];
        NSArray *sourceInputs =
            [sourceSnapshot[@"inputs"] isKindOfClass:[NSArray class]]
                ? sourceSnapshot[@"inputs"] : @[];

        if (self.macIntentOperationActiveV2) {
            diagnosticCode = @"route_unstable";
        } else if (!validRecordingSelection) {
            diagnosticCode = @"recording_route_unsupported";
        } else if (input == nil || output == nil) {
            diagnosticCode = input == nil
                ? @"recording_route_unsupported" : @"no_output";
        } else if ([input[@"uid"] length] == 0 ||
                   [output[@"uid"] length] == 0 ||
                   [input[@"inputChannels"] integerValue] < requiredInputChannels ||
                   [input[@"sampleRateHz"] doubleValue] <= 1000.0 ||
                   [input[@"bufferFrames"] integerValue] <= 0 ||
                   [output[@"outputChannels"] integerValue] <= 0 ||
                   [output[@"sampleRateHz"] doubleValue] <= 1000.0 ||
                   [output[@"bufferFrames"] integerValue] <= 0 ||
                   inputDeviceID == kAudioObjectUnknown ||
                   !MixroomCoreAudioDeviceIsAlive(inputDeviceID) ||
                   defaultOutputID == kAudioObjectUnknown ||
                   !MixroomCoreAudioDeviceIsAlive(defaultOutputID) ||
                   !MixroomOutputNameIsUnique(inventory, output)) {
            diagnosticCode = @"actual_state_unavailable";
        } else if (monitoringIntent &&
                   (!MixroomMacMonitoringTransportIsAllowed(
                        [input[@"transport"] unsignedIntValue]) ||
                    !MixroomMacMonitoringTransportIsAllowed(
                        [output[@"transport"] unsignedIntValue]))) {
            diagnosticCode = @"monitoring_unavailable";
        } else if (monitoringIntent &&
                   !MixroomMacMonitoringSharesClockDomain(input, output)) {
            diagnosticCode = @"monitoring_unavailable";
        } else if (monitoringIntent &&
                   fabs([input[@"sampleRateHz"] doubleValue] -
                        [output[@"sampleRateHz"] doubleValue]) >= 1.0) {
            diagnosticCode = @"monitoring_unavailable";
        } else if (sourceInputs.count != 0 ||
                   !outputSnapshotIsValid(sourceSnapshot, output)) {
            diagnosticCode = @"actual_state_unavailable";
        } else {
            self.macIntentOperationIdV2 += 1;
            self.macIntentOperationGenerationV2 = generation;
            self.macIntentOperationModeV2 = intentOperation;
            self.macIntentOperationActiveV2 = YES;
            self.macIntentOperationCancelledV2 = NO;
            self.macIntentCleanupClaimedV2 = NO;
            self.macLifecycleTransitionActiveV2 = YES;
            self.macIntentLifecyclePhaseV2 = @"openingInput";
            self.macIntentTerminalCauseV2 = nil;
            self.macIntentOperationStartedAtMsV2 = startedAtMs;
            self.macIntentSourceOutputV2 = output;
            self.macIntentSourceFingerprintV2 =
                MixroomOutputFingerprint(output);
            self.macIntentTargetInputV2 = input;
            self.macIntentTargetOutputV2 = output;
            self.macIntentVerifiedOutputV2 = nil;
            self.macIntentInputFactsV2 = nil;
            self.macIntentRecordingChannelStartV2 = recordingChannelStart;
            self.macIntentRecordingChannelCountV2 = recordingChannelCount;
            self.macIntentMonitoringTargetRowV2 = monitoringIntent
                ? monitoringTargetRow : -1;
            self.macIntentFollowsSystemInputV2 = followsSystemInput;
            self.macIntentRouteConditionV2 =
                [[[NSCondition alloc] init] autorelease];
            self.macIntentRouteConditionSignalledV2 = NO;
            self.macIntentObservedInputDeviceV2 = inputDeviceID;
            self.macIntentObservedOutputDeviceV2 = defaultOutputID;
            const BOOL listenersInstalled =
                [self installMacIntentDeviceListenersV2];

            const double prepareDeadline = startedAtMs + 2000.0;
            [JuceBridge quiescePlaybackRouteV2ObjC:YES];
            const BOOL inputStarted = listenersInstalled &&
                !self.macIntentOperationCancelledV2 &&
                [JuceBridge startMacInputProbeV2ObjC:inputDeviceID
                                         channelStart:recordingChannelStart
                                         channelCount:recordingChannelCount];
            const NSInteger inputRemaining =
                remainingMilliseconds(prepareDeadline);
            const BOOL inputCallbackReady = inputStarted &&
                inputRemaining > 0 &&
                [JuceBridge waitForMacInputProbeCallbackV2ObjC:inputRemaining];
            NSDictionary *inputFacts =
                [JuceBridge getMacInputProbeFactsV2ObjC] ?: @{};
            self.macIntentInputFactsV2 = inputFacts;

            NSArray *settledInventory =
                MixroomCoreAudioDeviceInventory() ?: @[];
            NSDictionary *settledInput =
                [self currentMacRecordingInputV2:settledInventory];
            NSDictionary *settledOutput = MixroomOutputForUID(
                settledInventory, output[@"uid"]);
            NSDictionary *settledDefaultOutput =
                [self currentMacPlaybackOutputV2:settledInventory];
            const BOOL routeStable = settledInput != nil &&
                settledOutput != nil && settledDefaultOutput != nil &&
                [settledInput[@"uid"] isEqualToString:input[@"uid"]] &&
                [settledDefaultOutput[@"uid"]
                    isEqualToString:output[@"uid"]] &&
                MixroomCoreAudioDeviceIsAlive(
                    [settledInput[@"deviceID"] unsignedIntValue]) &&
                MixroomCoreAudioDeviceIsAlive(
                    [settledOutput[@"deviceID"] unsignedIntValue]) &&
                MixroomOutputNameIsUnique(settledInventory, settledOutput) &&
                (!monitoringIntent ||
                 [MixroomOutputFingerprint(settledOutput)
                    isEqualToString:self.macIntentSourceFingerprintV2]);

            self.macIntentLifecyclePhaseV2 = @"openingOutput";
            NSDictionary *settledOutputPlan = monitoringIntent
                ? settledOutput
                : MixroomMacPlaybackOpenPlan(
                    settledOutput,
                    self.preferredPlaybackSampleRateV2,
                    self.preferredPlaybackBufferFramesV2);
            [JuceBridge beginMacOutputCallbackProofV2ObjC];
            const BOOL outputOpened = inputCallbackReady && routeStable &&
                !self.macIntentOperationCancelledV2 &&
                [JuceBridge
                    reconfigureMacPlaybackRouteV2ObjC:settledOutput[@"name"]
                    sampleRate:[settledOutputPlan[@"sampleRateHz"] doubleValue]
                    bufferFrames:[settledOutputPlan[@"bufferFrames"] integerValue]];
            const NSInteger outputRemaining =
                remainingMilliseconds(prepareDeadline);
            const BOOL outputCallbackReady = outputOpened &&
                outputRemaining > 0 &&
                [JuceBridge
                    waitForMacOutputCallbackProofV2ObjC:outputRemaining];
            settledOutput = MixroomOutputForUID(
                MixroomCoreAudioDeviceInventory() ?: @[], output[@"uid"]);
            self.macIntentTargetInputV2 = settledInput ?: input;
            self.macIntentTargetOutputV2 = settledOutput ?: output;
            self.macLifecycleTransitionActiveV2 = NO;
            NSDictionary *duplexSnapshot = [self buildAudioRouteSnapshotV2];
            const BOOL inputFactsValid =
                [inputFacts[@"running"] boolValue] &&
                [inputFacts[@"deviceID"] unsignedIntValue] == inputDeviceID &&
                [inputFacts[@"sampleRateHz"] doubleValue] > 1000.0 &&
                fabs([inputFacts[@"sampleRateHz"] doubleValue] -
                     [settledInput[@"sampleRateHz"] doubleValue]) < 1.0 &&
                [inputFacts[@"bufferFrames"] integerValue] > 0 &&
                [inputFacts[@"bufferFrames"] integerValue] ==
                    [settledInput[@"bufferFrames"] integerValue] &&
                [inputFacts[@"channelStart"] integerValue] ==
                    recordingChannelStart &&
                [inputFacts[@"channelCount"] integerValue] ==
                    recordingChannelCount &&
                [inputFacts[@"callbackCount"] unsignedLongLongValue] > 0 &&
                [inputFacts[@"invalidCallbackCount"] unsignedLongLongValue] == 0;
            NSDictionary *duplexJuce =
                [duplexSnapshot[@"juce"] isKindOfClass:[NSDictionary class]]
                    ? duplexSnapshot[@"juce"] : @{};
            const NSInteger outputCallbackFrames =
                [JuceBridge getMacOutputCallbackProofFramesV2ObjC]
                    .integerValue;
            const double outputCallbackRate =
                [JuceBridge getMacOutputCallbackProofSampleRateV2ObjC]
                    .doubleValue;
            const BOOL outputCallbackShapeValid =
                outputCallbackFrames > 0 &&
                outputCallbackFrames ==
                    [duplexJuce[@"bufferFrames"] integerValue] &&
                fabs(outputCallbackRate -
                     [duplexJuce[@"sampleRateHz"] doubleValue]) < 1.0;
            const BOOL outputFactsValid = outputCallbackReady &&
                outputSnapshotIsValid(duplexSnapshot, settledOutput) &&
                [JuceBridge getMacOutputCallbackProofCountV2ObjC]
                    .unsignedLongLongValue > 0 &&
                outputCallbackShapeValid;
            NSLog(@"[MacV2Route] op=%llu phase=duplexValidation "
                  "listeners=%d inputStarted=%d inputCallback=%d routeStable=%d "
                  "outputOpened=%d outputCallback=%d inputFacts=%d outputFacts=%d "
                  "cancelled=%d generation=%llu/%llu inputRate=%@/%@ "
                  "inputBuffer=%@/%@ inputFrames=%@ outputRate=%@/%@ "
                  "outputBuffer=%@/%@ outputFrames=%ld outputShape=%d",
                  (unsigned long long)self.macIntentOperationIdV2,
                  listenersInstalled,
                  inputStarted,
                  inputCallbackReady,
                  routeStable,
                  outputOpened,
                  outputCallbackReady,
                  inputFactsValid,
                  outputFactsValid,
                  self.macIntentOperationCancelledV2,
                  (unsigned long long)self.macIntentOperationGenerationV2,
                  (unsigned long long)self.audioRouteGenerationV2,
                  inputFacts[@"sampleRateHz"] ?: @"missing",
                  settledInput[@"sampleRateHz"] ?: @"missing",
                  inputFacts[@"bufferFrames"] ?: @"missing",
                  settledInput[@"bufferFrames"] ?: @"missing",
                  inputFacts[@"lastFrames"] ?: @"missing",
                  duplexJuce[@"sampleRateHz"] ?: @"missing",
                  settledOutput[@"sampleRateHz"] ?: @"missing",
                  duplexJuce[@"bufferFrames"] ?: @"missing",
                  settledOutput[@"bufferFrames"] ?: @"missing",
                  (long)outputCallbackFrames,
                  outputCallbackShapeValid);
            const BOOL monitoringClockValid = !monitoringIntent ||
                (MixroomMacMonitoringSharesClockDomain(
                     settledInput, settledOutput) &&
                 fabs([inputFacts[@"sampleRateHz"] doubleValue] -
                      [duplexJuce[@"sampleRateHz"] doubleValue]) < 1.0 &&
                 [inputFacts[@"bufferFrames"] integerValue] > 0 &&
                 [duplexJuce[@"bufferFrames"] integerValue] > 0);
            BOOL monitoringBridgeReady = !monitoringIntent;
            NSDictionary *monitoringFacts = @{};
            if (inputFactsValid && outputFactsValid && routeStable &&
                monitoringClockValid && !self.macIntentOperationCancelledV2 &&
                self.macIntentOperationGenerationV2 ==
                    self.audioRouteGenerationV2 && monitoringIntent) {
                monitoringBridgeReady = [JuceBridge
                    prepareMacIndependentInputMonitoringV2ObjC:monitoringTargetRow
                    channelCount:recordingChannelCount
                    inputSampleRate:[inputFacts[@"sampleRateHz"] doubleValue]
                    outputSampleRate:[duplexJuce[@"sampleRateHz"] doubleValue]
                    inputBlockFrames:[inputFacts[@"bufferFrames"] integerValue]
                    outputBlockFrames:[duplexJuce[@"bufferFrames"] integerValue]];
                monitoringFacts =
                    [JuceBridge getMacIndependentInputMonitoringFactsV2ObjC]
                        ?: @{};
                monitoringBridgeReady = monitoringBridgeReady &&
                    [monitoringFacts[@"active"] boolValue] &&
                    [monitoringFacts[@"targetRow"] integerValue] ==
                        monitoringTargetRow &&
                    [monitoringFacts[@"channelCount"] integerValue] ==
                        recordingChannelCount &&
                    [monitoringFacts[@"capacityFrames"] integerValue] >=
                        8 * MAX([inputFacts[@"bufferFrames"] integerValue],
                                [duplexJuce[@"bufferFrames"] integerValue]);
            }
            success = inputFactsValid && outputFactsValid && routeStable &&
                monitoringClockValid && monitoringBridgeReady &&
                !self.macIntentOperationCancelledV2 &&
                self.macIntentOperationGenerationV2 ==
                    self.audioRouteGenerationV2;

            if (success) {
                self.macIntentVerifiedOutputV2 = settledOutput;
                self.currentAudioRouteIntentV2 = monitoringIntent
                    ? @"monitoring" : @"preparingRecording";
                self.macIntentLifecyclePhaseV2 = monitoringIntent
                    ? @"monitoring" : @"duplexVerified";
                self.iosLastDuplexProbeV2 = @{
                    @"status": monitoringIntent
                        ? @"monitoring" : @"duplexVerified",
                    @"diagnosticCode": @"ok",
                    @"validationStage": @"duplexVerified",
                    @"categoryOptions": @[],
                    @"phase": @"duplexVerified",
                    @"terminalCause": [NSNull null],
                    @"actualCallbackCount": inputFacts[@"callbackCount"] ?: @0,
                    @"inputCallbackCount": inputFacts[@"callbackCount"] ?: @0,
                    @"outputCallbackCount":
                        [JuceBridge getMacOutputCallbackProofCountV2ObjC],
                    @"outputCallbackFrames": @(outputCallbackFrames),
                    @"inputSampleRateHz": inputFacts[@"sampleRateHz"] ?: @0,
                    @"inputBufferFrames": inputFacts[@"bufferFrames"] ?: @0,
                    @"monitoringActive": monitoringFacts[@"active"] ?: @NO,
                    @"monitoringBufferedFrames":
                        monitoringFacts[@"bufferedFrames"] ?: @0,
                    @"monitoringCallbackCount":
                        monitoringFacts[@"callbackCount"] ?: @0,
                    @"monitoringUnderflowCount":
                        monitoringFacts[@"underflowCount"] ?: @0,
                    @"monitoringOverflowCount":
                        monitoringFacts[@"overflowCount"] ?: @0,
                    @"monitoringInvalidBlockCount":
                        monitoringFacts[@"invalidBlockCount"] ?: @0,
                    @"cleanupOutcome": @"pending",
                    @"selectionMode": @"macOSIndependentInput",
                    @"operationId": @(self.macIntentOperationIdV2),
                    @"elapsedMs": @((NSInteger)(
                        MixroomMonotonicMilliseconds() -
                        self.macIntentOperationStartedAtMsV2 + 0.5)),
                    @"sourceOutput": MixroomRouteEndpoint(output, NO, NO),
                    @"duplexInput": MixroomRouteEndpoint(
                        self.macIntentTargetInputV2, YES,
                        MixroomTransportIsBluetooth(
                            [self.macIntentTargetInputV2[@"transport"]
                                unsignedIntValue])),
                    @"duplexOutput": MixroomRouteEndpoint(
                        self.macIntentTargetOutputV2, NO,
                        MixroomTransportIsBluetooth(
                            [self.macIntentTargetInputV2[@"transport"]
                                unsignedIntValue])),
                    @"restoredOutput": [NSNull null],
                };
            } else {
                NSString *terminalCause = self.macIntentTerminalCauseV2;
                const BOOL physicalRouteInvalidation =
                    self.macIntentOperationCancelledV2 &&
                    ![terminalCause isEqualToString:@"cancelled"] &&
                    ![terminalCause isEqualToString:@"shutdown"];
                diagnosticCode = self.macIntentOperationCancelledV2
                    ? @"route_unstable"
                    : (monitoringIntent
                        ? @"monitoring_unavailable"
                        : @"actual_state_unavailable");
                [JuceBridge cancelMacOutputCallbackProofV2ObjC];
                [JuceBridge disableMacIndependentInputMonitoringV2ObjC];
                [JuceBridge quiescePlaybackRouteV2ObjC:YES];
                [JuceBridge discardMacInputRecordingV2ObjC];
                [JuceBridge stopMacInputProbeV2ObjC];
                if ([self claimMacIntentCleanupV2]) {
                    if (restorationAllowed()) {
                        self.macLifecycleTransitionActiveV2 = YES;
                        restoredAfterFailure = restoreSourceOutput();
                        self.macLifecycleTransitionActiveV2 = NO;
                    }
                }
                self.currentAudioRouteIntentV2 = @"playbackOnly";
                self.iosLastDuplexProbeV2 = @{
                    @"status": restoredAfterFailure
                        ? @"failedRestored" : @"failed",
                    @"diagnosticCode": diagnosticCode,
                    @"validationStage": self.macIntentOperationCancelledV2
                        ? @"physicalRouteInvalidation" : @"duplexValidation",
                    @"categoryOptions": @[],
                    @"phase": @"cleanup",
                    @"terminalCause": self.macIntentTerminalCauseV2
                        ?: [NSNull null],
                    @"actualCallbackCount": inputFacts[@"callbackCount"] ?: @0,
                    @"inputCallbackCount": inputFacts[@"callbackCount"] ?: @0,
                    @"outputCallbackCount":
                        [JuceBridge getMacOutputCallbackProofCountV2ObjC],
                    @"outputCallbackFrames": @(outputCallbackFrames),
                    @"inputSampleRateHz": inputFacts[@"sampleRateHz"] ?: @0,
                    @"inputBufferFrames": inputFacts[@"bufferFrames"] ?: @0,
                    @"inputCallbackFrames": inputFacts[@"lastFrames"] ?: @0,
                    @"outputSampleRateHz": duplexJuce[@"sampleRateHz"] ?: @0,
                    @"outputBufferFrames": duplexJuce[@"bufferFrames"] ?: @0,
                    @"cleanupOutcome": restoredAfterFailure
                        ? @"restored" : @"closed",
                    @"selectionMode": @"macOSIndependentInput",
                    @"operationId": @(self.macIntentOperationIdV2),
                    @"elapsedMs": @((NSInteger)(
                        MixroomMonotonicMilliseconds() -
                        self.macIntentOperationStartedAtMsV2 + 0.5)),
                    @"sourceOutput": MixroomRouteEndpoint(output, NO, NO),
                    @"duplexInput": MixroomRouteEndpoint(input, YES, NO),
                    @"duplexOutput": settledOutput == nil
                        ? [NSNull null]
                        : MixroomRouteEndpoint(settledOutput, NO, NO),
                    @"restoredOutput": restoredAfterFailure
                        ? MixroomRouteEndpoint(
                            self.macIntentTargetOutputV2, NO, NO)
                        : [NSNull null],
                };
                releaseOperation();
                if (physicalRouteInvalidation) {
                    [self emitMacIntentRouteInvalidationEventV2:NO
                                           monitoringWasActive:monitoringIntent];
                }
            }
        }
    } else if ([intent isEqualToString:@"playbackOnly"] &&
               self.macIntentOperationActiveV2) {
        self.macLifecycleTransitionActiveV2 = YES;
        self.macIntentLifecyclePhaseV2 = @"restoringPlayback";
        if ([self claimMacIntentCleanupV2]) {
            [JuceBridge cancelMacOutputCallbackProofV2ObjC];
            [JuceBridge disableMacIndependentInputMonitoringV2ObjC];
            [JuceBridge quiescePlaybackRouteV2ObjC:YES];
            [JuceBridge discardMacInputRecordingV2ObjC];
            [JuceBridge stopMacInputProbeV2ObjC];
            success = restorationAllowed() && restoreSourceOutput();
        }
        diagnosticCode = success ? @"ok" :
            (self.macIntentOperationCancelledV2
                ? @"route_unstable" : @"actual_state_unavailable");
        NSDictionary *source = self.macIntentSourceOutputV2;
        NSDictionary *restored = self.macIntentTargetOutputV2;
        NSDictionary *inputFacts = self.macIntentInputFactsV2 ?: @{};
        NSDictionary *priorProbe =
            [self.iosLastDuplexProbeV2 isKindOfClass:[NSDictionary class]]
                ? self.iosLastDuplexProbeV2 : @{};
        self.currentAudioRouteIntentV2 = @"playbackOnly";
        self.iosLastDuplexProbeV2 = @{
            @"status": success ? @"restored" : @"failed",
            @"diagnosticCode": diagnosticCode,
            @"validationStage": success
                ? @"duplexVerified"
                : (self.macIntentOperationCancelledV2
                    ? @"physicalRouteInvalidation" : @"cleanup"),
            @"categoryOptions": @[],
            @"phase": @"complete",
            @"terminalCause": self.macIntentTerminalCauseV2 ?: [NSNull null],
            @"actualCallbackCount": inputFacts[@"callbackCount"] ?: @0,
            @"inputCallbackCount": inputFacts[@"callbackCount"] ?: @0,
            @"outputCallbackCount":
                [JuceBridge getMacOutputCallbackProofCountV2ObjC],
            @"inputSampleRateHz": inputFacts[@"sampleRateHz"] ?: @0,
            @"inputBufferFrames": inputFacts[@"bufferFrames"] ?: @0,
            @"captureActive": @NO,
            @"captureAttemptedSamples":
                priorProbe[@"captureAttemptedSamples"] ?: @0,
            @"captureAcceptedSamples":
                priorProbe[@"captureAcceptedSamples"] ?: @0,
            @"captureDroppedSamples":
                priorProbe[@"captureDroppedSamples"] ?: @0,
            @"captureInvalidBlockCount":
                priorProbe[@"captureInvalidBlockCount"] ?: @0,
            @"captureSampleRateHz":
                priorProbe[@"captureSampleRateHz"] ?: @0,
            @"cleanupOutcome": success ? @"restored" : @"closed",
            @"selectionMode": @"macOSIndependentInput",
            @"operationId": @(self.macIntentOperationIdV2),
            @"elapsedMs": @((NSInteger)(
                MixroomMonotonicMilliseconds() -
                self.macIntentOperationStartedAtMsV2 + 0.5)),
            @"sourceOutput": source == nil
                ? [NSNull null] : MixroomRouteEndpoint(source, NO, NO),
            @"duplexInput": self.macIntentTargetInputV2 == nil
                ? [NSNull null] : MixroomRouteEndpoint(
                    self.macIntentTargetInputV2, YES,
                    MixroomTransportIsBluetooth(
                        [self.macIntentTargetInputV2[@"transport"]
                            unsignedIntValue])),
            @"duplexOutput": self.macIntentVerifiedOutputV2 == nil
                ? [NSNull null] : MixroomRouteEndpoint(
                    self.macIntentVerifiedOutputV2, NO,
                    MixroomTransportIsBluetooth(
                        [self.macIntentVerifiedOutputV2[@"transport"]
                            unsignedIntValue])),
            @"restoredOutput": success && restored != nil
                ? MixroomRouteEndpoint(restored, NO, NO)
                : [NSNull null],
        };
        releaseOperation();
        if (success) {
            self.audioRouteFingerprintV2 =
                MixroomOutputFingerprint(restored);
            [self updateObservedOutputDeviceV2:restored == nil
                ? kAudioObjectUnknown
                : [restored[@"deviceID"] unsignedIntValue]];
        }
    } else if (![intent isEqualToString:@"playbackOnly"]) {
        diagnosticCode = @"recording_route_unsupported";
    } else {
        const double recoveryDeadlineMs = startedAtMs + 2000.0;
        self.macIntentRouteConditionV2 =
            [[[NSCondition alloc] init] autorelease];
        self.macIntentRouteConditionSignalledV2 = NO;
        NSDictionary<NSString *, id> *output =
            [self currentMacPlaybackOutputV2:
                MixroomCoreAudioDeviceInventory() ?: @[]];
        const BOOL waitedForRouteEvidence = output == nil;
        if (waitedForRouteEvidence && self.audioRouteMonitoringV2) {
            const double remainingSeconds =
                (recoveryDeadlineMs - MixroomMonotonicMilliseconds()) / 1000.0;
            if (remainingSeconds > 0.0) {
                NSCondition *condition = self.macIntentRouteConditionV2;
                [condition lock];
                if (!self.macIntentRouteConditionSignalledV2) {
                    [condition waitUntilDate:
                        [NSDate dateWithTimeIntervalSinceNow:remainingSeconds]];
                }
                self.macIntentRouteConditionSignalledV2 = NO;
                [condition unlock];
            }
            output = self.audioRouteMonitoringV2
                ? [self currentMacPlaybackOutputV2:
                    MixroomCoreAudioDeviceInventory() ?: @[]]
                : nil;
        }
        const AudioDeviceID defaultOutputID = output == nil
            ? kAudioObjectUnknown
            : [output[@"deviceID"] unsignedIntValue];

        if (output == nil) {
            diagnosticCode = @"no_output";
        } else {
            NSDictionary *outputPlan = MixroomMacPlaybackOpenPlan(
                output,
                self.preferredPlaybackSampleRateV2,
                self.preferredPlaybackBufferFramesV2);
            [JuceBridge beginMacOutputCallbackProofV2ObjC];
            success = [JuceBridge
                reconfigureMacPlaybackRouteV2ObjC:output[@"name"]
                sampleRate:[outputPlan[@"sampleRateHz"] doubleValue]
                bufferFrames:[outputPlan[@"bufferFrames"] integerValue]];
            const NSInteger remainingMs = MAX(0, (NSInteger)(
                recoveryDeadlineMs - MixroomMonotonicMilliseconds()));
            const BOOL callbackReady = success && remainingMs > 0 &&
                [JuceBridge waitForMacOutputCallbackProofV2ObjC:remainingMs];
            if (!success) {
                diagnosticCode = @"juce_reopen_failed";
            } else {
                NSDictionary *snapshot = [self buildAudioRouteSnapshotV2];
                NSDictionary *settledOutput =
                    [self currentMacPlaybackOutputV2:
                        MixroomCoreAudioDeviceInventory() ?: @[]];
                success = callbackReady &&
                    generation == self.audioRouteGenerationV2 &&
                    [settledOutput[@"uid"] isEqualToString:output[@"uid"]] &&
                    MixroomMacPlaybackSnapshotMatchesPlan(
                        snapshot,
                        settledOutput,
                        [JuceBridge getMacOutputCallbackProofSampleRateV2ObjC]
                            .doubleValue,
                        [JuceBridge getMacOutputCallbackProofFramesV2ObjC]
                            .integerValue,
                        [JuceBridge getMacOutputCallbackProofCountV2ObjC]
                            .unsignedLongLongValue);
                if (!success) {
                    diagnosticCode = @"actual_state_unavailable";
                } else {
                    output = settledOutput;
                    self.audioRouteFingerprintV2 =
                        MixroomOutputFingerprint(settledOutput);
                    [self updateObservedOutputDeviceV2:
                        [settledOutput[@"deviceID"] unsignedIntValue]];
                    NSDictionary *priorProbe =
                        [self.iosLastDuplexProbeV2
                            isKindOfClass:[NSDictionary class]]
                            ? self.iosLastDuplexProbeV2 : nil;
                    const BOOL recoveredInvalidation =
                        [priorProbe[@"validationStage"]
                            isEqualToString:@"physicalRouteInvalidation"] &&
                        [priorProbe[@"cleanupOutcome"]
                            isEqualToString:@"closed"];
                    if (recoveredInvalidation) {
                        NSMutableDictionary *recoveredProbe =
                            [NSMutableDictionary
                                dictionaryWithDictionary:priorProbe];
                        recoveredProbe[@"status"] = @"failedRestored";
                        recoveredProbe[@"phase"] = @"complete";
                        recoveredProbe[@"cleanupOutcome"] = @"restored";
                        recoveredProbe[@"restoredOutput"] =
                            MixroomRouteEndpoint(output, NO, NO);
                        self.iosLastDuplexProbeV2 = recoveredProbe;
                    }
                }
            }
        }
        NSLog(@"[MacV2Recovery] transition=%llu routeReady=%d waited=%d "
              "device=%u opened=%d code=%@ elapsedMs=%ld",
              (unsigned long long)transitionID,
              output != nil,
              waitedForRouteEvidence,
              (unsigned int)defaultOutputID,
              success,
              diagnosticCode,
              (long)(MixroomMonotonicMilliseconds() - startedAtMs + 0.5));
        self.macIntentRouteConditionV2 = nil;
        self.macIntentRouteConditionSignalledV2 = NO;
    }

    if (success && [intent isEqualToString:@"playbackOnly"]) {
        self.currentAudioRouteIntentV2 = @"playbackOnly";
    }

    NSDictionary *snapshot = [self buildAudioRouteSnapshotV2];
    const NSInteger elapsedMs = (NSInteger)(
        MixroomMonotonicMilliseconds() - startedAtMs + 0.5);
    return @{
        @"status": success ? @"success" : @"failure",
        @"generation": @(generation),
        @"transitionId": @(transitionID),
        @"diagnosticCode": diagnosticCode,
        @"elapsedMs": @(elapsedMs),
        @"transportWasPlaying": @NO,
        @"snapshot": snapshot,
    };
#else
    const double startedAtMs = MixroomIOSMonotonicMilliseconds();
    const uint64_t generation = [args[@"generation"] unsignedLongLongValue];
    NSString *intent = [args[@"intent"] isKindOfClass:[NSString class]]
        ? args[@"intent"]
        : @"";
    self.audioRouteTransitionIdV2 += 1;
    const uint64_t transitionID = self.audioRouteTransitionIdV2;
    NSString *diagnosticCode = @"ok";
    NSString *probeValidationStage = @"notStarted";
    NSDictionary<NSString *, id> *probeCandidateInput = nil;
    NSDictionary<NSString *, id> *probeCandidateOutput = nil;
    NSArray<NSString *> *probeCandidateCategoryOptions = @[];
    NSNumber *probeActualCallbackCount = @0;
    BOOL success = NO;
    BOOL playbackRecoveryUsedFallback = NO;
    BOOL recordingRouteMutationStarted = NO;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSString *intentOperation =
        [args[@"intentOperation"] isKindOfClass:[NSString class]]
            ? args[@"intentOperation"] : @"standard";
    const NSInteger recordingChannelStart =
        [args[@"recordingChannelStart"] isKindOfClass:[NSNumber class]]
            ? [args[@"recordingChannelStart"] integerValue] : 0;
    const NSInteger recordingChannelCount =
        [args[@"recordingChannelCount"] isKindOfClass:[NSNumber class]]
            ? [args[@"recordingChannelCount"] integerValue] : 1;
    const NSInteger monitoringTargetRow =
        [args[@"monitoringTargetRow"] isKindOfClass:[NSNumber class]]
            ? [args[@"monitoringTargetRow"] integerValue] : -1;
    const NSInteger requiredInputChannels =
        recordingChannelStart + recordingChannelCount;
    const BOOL validRecordingSelection = recordingChannelStart >= 0 &&
        (recordingChannelCount == 1 || recordingChannelCount == 2) &&
        requiredInputChannels >= 1 && requiredInputChannels <= 32;
    const BOOL monitoringIntent = [intent isEqualToString:@"monitoring"];
    const BOOL systemSelectedMonitoring =
        [intentOperation isEqualToString:@"systemSelectedMonitoring"];
    const BOOL systemSelectedRoute =
        [intentOperation isEqualToString:@"systemSelectedRecording"] ||
        systemSelectedMonitoring;
    const BOOL reusesMonitoringRoute = monitoringIntent &&
        self.iosIntentOperationActiveV2 &&
        [self.iosIntentOperationModeV2
            isEqualToString:@"systemSelectedMonitoring"];

    if (!self.audioRouteMonitoringV2 ||
        ![[JuceBridge getAudioRouteImplementationObjC] isEqualToString:@"v2"]) {
        diagnosticCode = @"coordinator_disposed";
    } else if (generation != self.audioRouteGenerationV2) {
        diagnosticCode = @"stale_generation";
    } else if (![intent isEqualToString:@"playbackOnly"] &&
               !monitoringIntent &&
               ![intent isEqualToString:@"preparingRecording"] &&
               ![intent isEqualToString:@"recording"]) {
        diagnosticCode = @"recording_route_unsupported";
    } else if (([intent isEqualToString:@"preparingRecording"] ||
                monitoringIntent) &&
               !validRecordingSelection) {
        diagnosticCode = @"recording_route_unsupported";
    } else if (monitoringIntent &&
               (!systemSelectedMonitoring || monitoringTargetRow < 0)) {
        diagnosticCode = @"monitoring_unavailable";
    } else if (reusesMonitoringRoute) {
        NSDictionary *snapshot = [self buildAudioRouteSnapshotV2];
        NSDictionary *juce = [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
            ? snapshot[@"juce"] : @{};
        NSDictionary *sessionFacts =
            [snapshot[@"session"] isKindOfClass:[NSDictionary class]]
                ? snapshot[@"session"] : @{};
        NSArray *inputs = [snapshot[@"inputs"] isKindOfClass:[NSArray class]]
            ? snapshot[@"inputs"] : @[];
        NSArray *outputs = [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
            ? snapshot[@"outputs"] : @[];
        NSDictionary *actualInput = inputs.count == 1 ? inputs.firstObject : nil;
        NSDictionary *actualOutput = outputs.count == 1 ? outputs.firstObject : nil;
        const BOOL routeVerified = generation == self.audioRouteGenerationV2 &&
            generation == self.iosIntentOperationGenerationV2 &&
            !self.iosIntentOperationCancelledV2 &&
            ![JuceBridge isRecordingObjC] &&
            [snapshot[@"captureConsistency"] isEqualToString:@"stable"] &&
            MixroomIOSMonitoringEndpointIsAllowed(actualInput) &&
            MixroomIOSMonitoringEndpointIsAllowed(actualOutput) &&
            MixroomIOSEndpointIdentitiesMatchStrict(
                self.iosRecordingInputV2, actualInput) &&
            MixroomIOSEndpointIdentitiesMatchStrict(
                self.iosIntentOperationTargetOutputV2, actualOutput) &&
            [self.iosIntentOperationTargetFingerprintV2
                isEqualToString:MixroomIOSRouteFingerprint(session.currentRoute)] &&
            [juce[@"deviceOpen"] boolValue] &&
            [juce[@"audioCallbackAttached"] boolValue] &&
            [juce[@"activeInputChannels"] integerValue] == requiredInputChannels &&
            [juce[@"activeOutputChannels"] integerValue] > 0 &&
            [juce[@"sampleRateHz"] doubleValue] > 1000.0 &&
            [juce[@"bufferFrames"] integerValue] > 0 &&
            [sessionFacts[@"category"] isEqual:AVAudioSessionCategoryPlayAndRecord] &&
            [sessionFacts[@"mode"] isEqual:AVAudioSessionModeDefault] &&
            [sessionFacts[@"inputChannelCount"] integerValue] >=
                requiredInputChannels &&
            fabs([juce[@"sampleRateHz"] doubleValue] -
                 [sessionFacts[@"sampleRateHz"] doubleValue]) < 1.0 &&
            [juce[@"bufferFrames"] integerValue] == (NSInteger)llround(
                [sessionFacts[@"sampleRateHz"] doubleValue] *
                [sessionFacts[@"ioBufferDurationSeconds"] doubleValue]) &&
            [JuceBridge validateRecordingRouteV2ObjC];
        success = routeVerified &&
            monitoringTargetRow == self.iosIntentMonitoringTargetRowV2 &&
            recordingChannelStart == self.iosIntentRecordingChannelStartV2 &&
            recordingChannelCount == self.iosIntentRecordingChannelCountV2 &&
            [[[self newIOSCaptureV2] autorelease] monitorMatches];
        diagnosticCode = success ? @"ok" : @"actual_state_unavailable";
        if (success) {
            self.iosIntentLifecyclePhaseV2 = @"monitoring";
        }
    } else if ([intent isEqualToString:@"preparingRecording"] ||
               monitoringIntent) {
        AVAudioSessionRouteDescription *sourceRoute = session.currentRoute;
        NSDictionary<NSString *, id> *expectedOutput =
            MixroomIOSSingleOutputEndpoint(sourceRoute);
        NSString *expectedFingerprint =
            MixroomIOSOutputFingerprint(sourceRoute);
        NSString *completeSourceFingerprint =
            MixroomIOSRouteFingerprint(sourceRoute);
        const BOOL builtInDuplex =
            MixroomIOSOutputIsBuiltInSpeaker(expectedOutput);
        const BOOL bluetoothProbe =
            !systemSelectedRoute &&
            MixroomIOSOutputIsBluetoothMedia(expectedOutput);
        const BOOL lifecycleOperation = bluetoothProbe || systemSelectedRoute;
        if (expectedOutput == nil) {
            diagnosticCode = @"no_output";
        } else if (!MixroomIOSOutputIdentityIsObservable(expectedOutput)) {
            diagnosticCode = @"actual_state_unavailable";
        } else if (monitoringIntent &&
                   !MixroomIOSMonitoringEndpointIsAllowed(expectedOutput)) {
            diagnosticCode = @"monitoring_unavailable";
        } else if (!systemSelectedRoute && !builtInDuplex && !bluetoothProbe) {
            diagnosticCode = @"recording_route_unsupported";
        } else {
            self.iosIntentOperationCancelledV2 = NO;
            self.iosIntentTerminalCauseV2 = nil;
            if (lifecycleOperation) {
                [JuceBridge beginIOSIntentOperationV2ObjC];
                self.iosIntentOperationIdV2 += 1;
                const uint64_t operationID = self.iosIntentOperationIdV2;
                self.iosIntentOperationGenerationV2 = generation;
                self.iosIntentOperationActiveV2 = YES;
                self.iosIntentCleanupClaimedV2 = NO;
                self.iosIntentCompletionDeliveredV2 = NO;
                self.iosIntentLifecyclePhaseV2 = @"configuringSession";
                self.iosIntentRouteConditionV2 =
                    [[[NSCondition alloc] init] autorelease];
                self.iosIntentRouteConditionSignalledV2 = NO;
                self.iosIntentOperationStartedAtMsV2 =
                    MixroomIOSMonotonicMilliseconds();
                self.iosIntentOperationSourceFingerprintV2 =
                    completeSourceFingerprint;
                self.iosIntentOperationPendingFingerprintV2 = nil;
                self.iosIntentOperationTargetFingerprintV2 = nil;
                self.iosIntentOperationTargetOutputV2 = nil;
                self.iosIntentOperationModeV2 = intentOperation;
                self.iosIntentMonitoringTargetRowV2 = monitoringIntent
                    ? monitoringTargetRow : -1;
                self.iosRecordingOutputV2 = expectedOutput;
                self.iosRecordingInputV2 = nil;
                dispatch_after(
                    dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                    dispatch_get_main_queue(),
                    ^{
                        NSString *phase = self.iosIntentLifecyclePhaseV2 ?: @"";
                        const BOOL preparationStillPending =
                            [phase isEqualToString:@"configuringSession"] ||
                            [phase isEqualToString:@"awaitingHfpRoute"] ||
                            [phase isEqualToString:@"awaitingSystemRoute"] ||
                            [phase isEqualToString:@"openingDevice"] ||
                            [phase isEqualToString:@"validating"];
                        if (self.iosIntentOperationActiveV2 &&
                            self.iosIntentOperationIdV2 == operationID &&
                            preparationStillPending) {
                            self.iosIntentOperationCancelledV2 = YES;
                            self.iosIntentTerminalCauseV2 = @"operationDeadline";
                            [self signalIOSIntentRouteConditionV2];
                        }
                    });
            }
            recordingRouteMutationStarted = YES;
            const BOOL sessionPrepared = !lifecycleOperation ||
                (systemSelectedRoute
                    ? [JuceBridge prepareSystemSelectedDuplexSessionV2ObjC]
                    : [JuceBridge prepareBluetoothDuplexSessionV2ObjC]);
            const BOOL initialRouteReady = systemSelectedRoute
                ? MixroomIOSSystemSelectedTargetMatchesSource(
                    expectedOutput, session.currentRoute)
                : MixroomIOSRouteIsBluetoothHFPDuplex(session.currentRoute);
            if (lifecycleOperation && sessionPrepared && !initialRouteReady &&
                !self.iosIntentOperationCancelledV2 &&
                ![JuceBridge isIOSIntentRouteInvalidatedV2ObjC]) {
                self.iosIntentLifecyclePhaseV2 = systemSelectedRoute
                    ? @"awaitingSystemRoute" : @"awaitingHfpRoute";
                const double remainingMilliseconds =
                    2000.0 - (MixroomIOSMonotonicMilliseconds() -
                        self.iosIntentOperationStartedAtMsV2);
                if (remainingMilliseconds > 0.0) {
                    NSCondition *condition = self.iosIntentRouteConditionV2;
                    [condition lock];
                    if (!self.iosIntentRouteConditionSignalledV2) {
                        [condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:
                            remainingMilliseconds / 1000.0]];
                    }
                    [condition unlock];
                }
            }
            self.iosIntentLifecyclePhaseV2 = @"openingDevice";
            const BOOL routeReady = !lifecycleOperation ||
                (systemSelectedRoute
                    ? MixroomIOSSystemSelectedTargetMatchesSource(
                        expectedOutput, session.currentRoute)
                    : MixroomIOSRouteIsBluetoothHFPDuplex(
                        session.currentRoute));
            const NSInteger deviceOpenTimeoutMs = lifecycleOperation
                ? MAX(0, (NSInteger)(2000.0 -
                    (MixroomIOSMonotonicMilliseconds() -
                     self.iosIntentOperationStartedAtMsV2)))
                : 0;
            const BOOL routeForcesMono =
                MixroomIOSRouteIsBluetoothHFPDuplex(session.currentRoute);
            const NSInteger routeInputChannels = routeForcesMono
                ? 1
                : MAX(
                    (NSInteger)session.inputNumberOfChannels,
                    (NSInteger)session.maximumInputNumberOfChannels);
            const NSInteger effectiveChannelStart = routeForcesMono
                ? 0 : recordingChannelStart;
            const NSInteger effectiveChannelCount = routeForcesMono
                ? 1 : recordingChannelCount;
            const NSInteger effectiveRequiredInputChannels =
                effectiveChannelStart + effectiveChannelCount;
            self.iosIntentRecordingChannelStartV2 = effectiveChannelStart;
            self.iosIntentRecordingChannelCountV2 = effectiveChannelCount;
            const BOOL opened = sessionPrepared && routeReady &&
                effectiveRequiredInputChannels <= routeInputChannels &&
                (lifecycleOperation
                    ? (systemSelectedRoute
                        ? [JuceBridge
                            openPreparedSystemSelectedDuplexRouteV2ObjC:
                                deviceOpenTimeoutMs
                            outputChannels:MAX(
                                1, MIN(2, session.outputNumberOfChannels))
                            inputChannels:effectiveRequiredInputChannels]
                        : [JuceBridge
                            openPreparedBluetoothDuplexRouteV2ObjC:
                                deviceOpenTimeoutMs])
                    : [JuceBridge reconfigureRecordingRouteV2ObjC:@""
                                                           inputName:@""]);
            self.iosIntentLifecyclePhaseV2 = @"validating";
            if (self.iosIntentOperationCancelledV2) {
                diagnosticCode = @"stale_generation";
                probeValidationStage = self.iosIntentTerminalCauseV2.length > 0
                    ? self.iosIntentTerminalCauseV2 : @"cancelled";
            } else if (lifecycleOperation &&
                [JuceBridge isIOSIntentRouteInvalidatedV2ObjC]) {
                diagnosticCode = @"route_unstable";
                probeValidationStage = @"physicalRouteInvalidation";
            } else if (lifecycleOperation && sessionPrepared && !routeReady) {
                diagnosticCode = @"route_unstable";
                probeValidationStage = @"systemRouteAcquisition";
            } else if (!opened) {
                NSDictionary *policyFacts =
                    [JuceBridge getIOSAudioSessionPolicyFactsObjC];
                NSString *policyCode =
                    [policyFacts[@"diagnosticCode"] isKindOfClass:[NSString class]]
                        ? policyFacts[@"diagnosticCode"] : @"juce_reopen_failed";
                diagnosticCode = [policyCode isEqualToString:@"ok"]
                    ? @"juce_reopen_failed" : policyCode;
            } else {
                NSDictionary *policyFacts =
                    [JuceBridge getIOSAudioSessionPolicyFactsObjC];
                NSDictionary *snapshot = [self buildAudioRouteSnapshotV2];
                NSDictionary *sessionFacts =
                    [snapshot[@"session"] isKindOfClass:[NSDictionary class]]
                        ? snapshot[@"session"] : @{};
                NSDictionary *juce =
                    [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
                        ? snapshot[@"juce"] : @{};
                NSArray *inputs =
                    [snapshot[@"inputs"] isKindOfClass:[NSArray class]]
                        ? snapshot[@"inputs"] : @[];
                NSArray *outputs =
                    [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
                        ? snapshot[@"outputs"] : @[];
                NSDictionary *actualInput =
                    inputs.count == 1 ? inputs.firstObject : nil;
                NSDictionary *actualOutput =
                    outputs.count == 1 ? outputs.firstObject : nil;
                NSArray *categoryOptions =
                    [sessionFacts[@"categoryOptions"] isKindOfClass:[NSArray class]]
                        ? sessionFacts[@"categoryOptions"] : @[];
                if (lifecycleOperation) {
                    probeCandidateInput = actualInput;
                    probeCandidateOutput = actualOutput;
                    probeCandidateCategoryOptions = categoryOptions;
                    probeActualCallbackCount =
                        [juce[@"bluetoothDuplexProjectCallbackCount"]
                            isKindOfClass:[NSNumber class]]
                            ? juce[@"bluetoothDuplexProjectCallbackCount"] : @0;
                }
                if (lifecycleOperation &&
                    [JuceBridge isIOSIntentRouteInvalidatedV2ObjC]) {
                    diagnosticCode = @"route_unstable";
                    probeValidationStage = @"physicalRouteInvalidation";
                } else if (generation != self.audioRouteGenerationV2 ||
                    (lifecycleOperation &&
                     (self.iosIntentOperationCancelledV2 ||
                      self.iosIntentOperationGenerationV2 != generation))) {
                    diagnosticCode = @"stale_generation";
                    probeValidationStage = @"epoch";
                } else if (lifecycleOperation &&
                           self.iosIntentOperationPendingFingerprintV2.length > 0 &&
                           ![self.iosIntentOperationPendingFingerprintV2
                               isEqualToString:
                                   MixroomIOSRouteFingerprint(session.currentRoute)]) {
                    diagnosticCode = @"route_unstable";
                    probeValidationStage = @"pendingNotification";
                } else if (![snapshot[@"captureConsistency"]
                               isEqualToString:@"stable"]) {
                    diagnosticCode = @"route_unstable";
                    probeValidationStage = @"snapshotStability";
                } else if ((builtInDuplex &&
                            (![MixroomIOSOutputFingerprint(session.currentRoute)
                                isEqualToString:expectedFingerprint] ||
                             !MixroomIOSEndpointIdentitiesMatchStrict(
                                 expectedOutput, actualOutput))) ||
                           (systemSelectedRoute &&
                            !MixroomIOSSystemSelectedTargetMatchesSource(
                                expectedOutput, session.currentRoute)) ||
                           (bluetoothProbe &&
                            (!MixroomIOSInputIsBluetoothHFP(actualInput) ||
                             !MixroomIOSOutputIsBluetoothHFP(actualOutput)))) {
                    diagnosticCode = @"route_unstable";
                    probeValidationStage = @"routeProfile";
                } else if (monitoringIntent &&
                           (!MixroomIOSMonitoringEndpointIsAllowed(actualInput) ||
                            !MixroomIOSMonitoringEndpointIsAllowed(actualOutput) ||
                            !MixroomIOSEndpointIdentitiesMatchStrict(
                                expectedOutput, actualOutput))) {
                    diagnosticCode = @"monitoring_unavailable";
                    probeValidationStage = @"monitoringRoute";
                } else if (![policyFacts[@"policy"] isEqualToString:
                               systemSelectedRoute
                                   ? @"v2SystemSelectedDuplex"
                                   : (bluetoothProbe
                                       ? @"v2BluetoothHfpDuplex"
                                       : @"v2BuiltInDuplex")]) {
                    diagnosticCode = @"actual_state_unavailable";
                    probeValidationStage = @"policy";
                } else if (![policyFacts[@"diagnosticCode"]
                               isEqualToString:@"ok"]) {
                    diagnosticCode = @"actual_state_unavailable";
                    probeValidationStage = @"policyResult";
                } else if ([policyFacts[@"activationCount"] integerValue] != 1) {
                    diagnosticCode = @"actual_state_unavailable";
                    probeValidationStage = @"activationCount";
                } else if (![sessionFacts[@"category"]
                               isEqual:AVAudioSessionCategoryPlayAndRecord]) {
                    diagnosticCode = @"actual_state_unavailable";
                    probeValidationStage = @"category";
                } else if (![sessionFacts[@"mode"]
                               isEqual:AVAudioSessionModeDefault]) {
                    diagnosticCode = @"actual_state_unavailable";
                    probeValidationStage = @"mode";
                } else if (bluetoothProbe &&
                           ([categoryOptions containsObject:@"allowBluetoothA2DP"] ||
                            [categoryOptions containsObject:@"defaultToSpeaker"])) {
                    diagnosticCode = @"actual_state_unavailable";
                    probeValidationStage = @"categoryOptions";
                } else if ((builtInDuplex &&
                            (!MixroomIOSInputIsBuiltInMicrophone(actualInput) ||
                             !MixroomIOSOutputIsBuiltInSpeaker(actualOutput))) ||
                           ![juce[@"deviceOpen"] boolValue]) {
                    diagnosticCode = @"actual_state_unavailable";
                    probeValidationStage = @"deviceOpen";
                } else if (![juce[@"audioCallbackAttached"] boolValue]) {
                    diagnosticCode = @"actual_state_unavailable";
                    probeValidationStage = @"callback";
                } else if (lifecycleOperation &&
                           (![juce[@"bluetoothDuplexProjectCallbackReady"]
                               boolValue] ||
                            ![JuceBridge
                                isBluetoothDuplexProjectCallbackReadyV2ObjC] ||
                            [juce[@"bluetoothDuplexProjectCallbackCount"]
                                unsignedLongLongValue] == 0)) {
                    diagnosticCode = @"actual_state_unavailable";
                    probeValidationStage = @"projectCallback";
                } else if ([juce[@"activeInputChannels"] integerValue] !=
                           effectiveRequiredInputChannels) {
                    diagnosticCode = @"actual_state_unavailable";
                    probeValidationStage = @"juceInputChannels";
                } else if ([juce[@"activeOutputChannels"] integerValue] <= 0) {
                    diagnosticCode = @"actual_state_unavailable";
                    probeValidationStage = @"juceOutputChannels";
                } else if ([sessionFacts[@"inputChannelCount"] integerValue] <
                           effectiveRequiredInputChannels) {
                    diagnosticCode = @"actual_state_unavailable";
                    probeValidationStage = @"sessionInputChannels";
                } else if ([juce[@"sampleRateHz"] doubleValue] <= 1000.0) {
                    diagnosticCode = @"actual_state_unavailable";
                    probeValidationStage = @"sampleRate";
                } else if ([juce[@"bufferFrames"] integerValue] <= 0) {
                    diagnosticCode = @"actual_state_unavailable";
                    probeValidationStage = @"buffer";
                } else if (monitoringIntent &&
                           (fabs([juce[@"sampleRateHz"] doubleValue] -
                                 [sessionFacts[@"sampleRateHz"] doubleValue]) >= 1.0 ||
                            [juce[@"bufferFrames"] integerValue] !=
                                (NSInteger)llround(
                                    [sessionFacts[@"sampleRateHz"] doubleValue] *
                                    [sessionFacts[@"ioBufferDurationSeconds"] doubleValue]))) {
                    diagnosticCode = @"actual_state_unavailable";
                    probeValidationStage = @"clockAgreement";
                } else if (![JuceBridge validateRecordingRouteV2ObjC]) {
                    diagnosticCode = @"actual_state_unavailable";
                    probeValidationStage = @"nativeReadiness";
                } else if (monitoringIntent &&
                           ![JuceBridge
                               setLiveInputMonitorTargetV2ObjC:monitoringTargetRow
                               channelStart:effectiveChannelStart
                               channelCount:effectiveChannelCount]) {
                    diagnosticCode = @"monitoring_unavailable";
                    probeValidationStage = @"monitorGraph";
                } else {
                    if (monitoringIntent) {
                        self.iosMonitorStreamGenerationV2 =
                            [[JuceBridge getLiveInputMonitoringFactsV2ObjC][@"streamGeneration"] unsignedLongLongValue];
                        self.iosCaptureV2 = nil;
                    }
                    probeValidationStage = @"duplexVerified";
                    if (lifecycleOperation) {
                        self.iosIntentOperationTargetFingerprintV2 =
                            MixroomIOSRouteFingerprint(session.currentRoute);
                        self.iosIntentOperationPendingFingerprintV2 = nil;
                        self.iosIntentOperationTargetOutputV2 = actualOutput;
                        self.audioRouteFingerprintV2 =
                            MixroomIOSOutputFingerprint(session.currentRoute);
                        self.iosObservedOutputWasBluetoothV2 =
                            MixroomIOSOutputIsBluetooth(actualOutput);
                        self.iosLastDuplexProbeV2 = @{
                            @"status": monitoringIntent
                                ? @"monitoring" : @"duplexVerified",
                            @"diagnosticCode": @"ok",
                            @"validationStage": probeValidationStage,
                            @"phase": monitoringIntent
                                ? @"monitoring" : @"duplexVerified",
                            @"terminalCause": [NSNull null],
                            @"cleanupOutcome": @"pending",
                            @"selectionMode": systemSelectedRoute
                                ? @"systemSelected" : @"explicitHfp",
                            @"categoryOptions": categoryOptions,
                            @"operationId": @(self.iosIntentOperationIdV2),
                            @"actualCallbackCount": probeActualCallbackCount,
                            @"elapsedMs": @((NSInteger)(
                                MixroomIOSMonotonicMilliseconds() -
                                self.iosIntentOperationStartedAtMsV2 + 0.5)),
                            @"sourceOutput": expectedOutput,
                            @"duplexInput": actualInput,
                            @"duplexOutput": actualOutput,
                        };
                    } else {
                        self.iosRecordingOutputV2 = actualOutput;
                    }
                    self.iosRecordingInputV2 = actualInput;
                    if (monitoringIntent) {
                        self.iosIntentLifecyclePhaseV2 = @"monitoring";
                    }
                    success = YES;
                }
            }
        }
    } else if ([intent isEqualToString:@"recording"]) {
        NSDictionary *snapshot = [self buildAudioRouteSnapshotV2];
        NSDictionary *sessionFacts =
            [snapshot[@"session"] isKindOfClass:[NSDictionary class]]
                ? snapshot[@"session"] : @{};
        NSDictionary *juce = [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
            ? snapshot[@"juce"] : @{};
        NSArray *inputs = [snapshot[@"inputs"] isKindOfClass:[NSArray class]]
            ? snapshot[@"inputs"] : @[];
        NSArray *outputs = [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
            ? snapshot[@"outputs"] : @[];
        NSDictionary *actualInput = inputs.count == 1 ? inputs.firstObject : nil;
        NSDictionary *actualOutput = outputs.count == 1 ? outputs.firstObject : nil;
        const BOOL lifecycleRecording =
            self.iosIntentOperationActiveV2 &&
            self.iosIntentOperationTargetFingerprintV2.length > 0;
        const BOOL systemSelectedRecording =
            lifecycleRecording &&
            [self.iosIntentOperationModeV2
                isEqualToString:@"systemSelectedRecording"];
        const BOOL monitoringOwnedRecording =
            lifecycleRecording &&
            [self.iosIntentOperationModeV2
                isEqualToString:@"systemSelectedMonitoring"];
        NSDictionary *expectedActiveOutput = lifecycleRecording
            ? self.iosIntentOperationTargetOutputV2
            : self.iosRecordingOutputV2;
        if (self.iosRecordingOutputV2 == nil || self.iosRecordingInputV2 == nil) {
            diagnosticCode = @"recording_route_unsupported";
        } else if (generation != self.audioRouteGenerationV2 ||
                   (lifecycleRecording &&
                    (self.iosIntentOperationCancelledV2 ||
                     self.iosIntentOperationGenerationV2 != generation))) {
            diagnosticCode = @"stale_generation";
        } else if (![snapshot[@"captureConsistency"] isEqualToString:@"stable"] ||
                   expectedActiveOutput == nil ||
                   !MixroomIOSEndpointIdentitiesMatchStrict(
                       expectedActiveOutput, actualOutput) ||
                   !MixroomIOSEndpointIdentitiesMatchStrict(
                       self.iosRecordingInputV2, actualInput) ||
                   (lifecycleRecording &&
                    ![self.iosIntentOperationTargetFingerprintV2
                        isEqualToString:
                            MixroomIOSRouteFingerprint(session.currentRoute)])) {
            diagnosticCode = @"route_unstable";
        } else {
            const BOOL expectedProfile = lifecycleRecording
                ? (((!systemSelectedRecording && !monitoringOwnedRecording) ||
                    MixroomIOSSystemSelectedTargetMatchesSource(
                        self.iosRecordingOutputV2, session.currentRoute)) &&
                   (!monitoringOwnedRecording ||
                    (MixroomIOSMonitoringEndpointIsAllowed(actualInput) &&
                     MixroomIOSMonitoringEndpointIsAllowed(actualOutput))) &&
                   [JuceBridge isBluetoothDuplexProjectCallbackReadyV2ObjC])
                : (MixroomIOSInputIsBuiltInMicrophone(actualInput) &&
                   MixroomIOSOutputIsBuiltInSpeaker(actualOutput));
            success = expectedProfile &&
                [sessionFacts[@"category"]
                    isEqual:AVAudioSessionCategoryPlayAndRecord] &&
                [sessionFacts[@"mode"] isEqual:AVAudioSessionModeDefault] &&
                [juce[@"deviceOpen"] boolValue] &&
                [juce[@"audioCallbackAttached"] boolValue] &&
                [juce[@"activeInputChannels"] integerValue] ==
                    self.iosIntentRecordingChannelStartV2 +
                        self.iosIntentRecordingChannelCountV2 &&
                [juce[@"activeOutputChannels"] integerValue] > 0 &&
                [juce[@"sampleRateHz"] doubleValue] > 1000.0 &&
                [juce[@"bufferFrames"] integerValue] > 0 &&
                [JuceBridge validateRecordingRouteV2ObjC] &&
                [JuceBridge isRecordingObjC] &&
                (!monitoringOwnedRecording ||
                 (!self.iosCaptureV2.cancelled &&
                  [[[self newIOSCaptureV2] autorelease] monitorMatches]));
            if (!success) {
                diagnosticCode = @"actual_state_unavailable";
            } else if (lifecycleRecording) {
                self.iosIntentLifecyclePhaseV2 = @"recording";
            }
        }
    } else {
        const BOOL restoringMonitoringRoute =
            self.iosIntentOperationActiveV2 &&
            [self.iosIntentOperationModeV2
                isEqualToString:@"systemSelectedMonitoring"];
        if (restoringMonitoringRoute) {
            [JuceBridge disableLiveInputMonitoringV2ObjC];
        }
        NSDictionary<NSString *, id> *recordingSourceOutput =
            self.iosRecordingOutputV2;
        NSDictionary<NSString *, id> *currentSystemOutput =
            MixroomIOSSingleOutputEndpoint(session.currentRoute);
        const BOOL activeBluetoothOperation =
            self.iosIntentOperationActiveV2;
        const BOOL recoveringAfterPhysicalInvalidation =
            activeBluetoothOperation &&
            [JuceBridge isIOSIntentRouteInvalidatedV2ObjC];
        NSDictionary<NSString *, id> *expectedOutput =
            recordingSourceOutput ?: currentSystemOutput;
        NSDictionary<NSString *, id> *playbackOpenProfileOutput =
            expectedOutput;
        const BOOL restoringBluetoothProbe =
            activeBluetoothOperation;
        NSDictionary<NSString *, id> *restoredOutputForFacts = nil;
        if (restoringBluetoothProbe) {
            [self claimIOSIntentCleanupV2];
            self.iosIntentLifecyclePhaseV2 = recoveringAfterPhysicalInvalidation
                ? @"recoveringSystemOutput" : @"restoringPlayback";
        }
        if (recoveringAfterPhysicalInvalidation) {
            [JuceBridge discardRecordingCaptureObjC];
            // The terminal route event already selected the replacement output.
            // End HFP transaction ownership before installing playback policy so
            // its configuration notifications follow ordinary duplicate rules.
            [JuceBridge endIOSIntentOperationV2ObjC];
            self.iosIntentOperationActiveV2 = NO;
            self.iosIntentRouteConditionV2 = nil;
            // The notification cause is diagnostic only. Once recording
            // cleanup has released transaction ownership, follow the output
            // that iOS currently exposes instead of the removed source route.
            expectedOutput =
                MixroomIOSSingleOutputEndpoint(session.currentRoute);
            // A route change can expose HFP temporarily while the monitoring
            // PlayAndRecord policy is still installed. Use the verified source
            // playback profile to reopen output-only; validate the OS-selected
            // endpoint only after playback policy has been restored.
            playbackOpenProfileOutput = recordingSourceOutput;
        } else if ([JuceBridge isRecordingObjC]) {
            [JuceBridge stopRecordingObjC];
        }
        const BOOL recoveryPlaybackPreferencesValid =
            !recoveringAfterPhysicalInvalidation ||
            (MixroomHardwareSampleRatePreferenceIsSupported(
                 self.preferredPlaybackSampleRateV2) &&
             MixroomHardwareBufferPreferenceIsSupported(
                 self.preferredPlaybackBufferFramesV2));
        BOOL playbackReopened = NO;
        BOOL playbackCallbackReady = NO;
        if (expectedOutput == nil) {
            diagnosticCode = @"no_output";
        } else if (!MixroomIOSOutputIdentityIsObservable(expectedOutput)) {
            diagnosticCode = @"actual_state_unavailable";
        } else if (!recoveryPlaybackPreferencesValid) {
            diagnosticCode = @"actual_state_unavailable";
        } else if (!recoveringAfterPhysicalInvalidation &&
                   MixroomIOSOutputIsBluetoothDuplex(expectedOutput)) {
            diagnosticCode = @"bluetooth_duplex_forbidden";
        } else {
            [JuceBridge beginOutputCallbackProofV2ObjC];
            playbackReopened = [JuceBridge
                reconfigurePlaybackRouteV2ObjC:@""
                sampleRate:MixroomIOSPlaybackOpenRate(
                    playbackOpenProfileOutput,
                    session,
                    self.preferredPlaybackSampleRateV2)
                bufferFrames:MixroomIOSPlaybackOpenBuffer(
                    playbackOpenProfileOutput,
                    session,
                    self.preferredPlaybackBufferFramesV2)];
            playbackCallbackReady = playbackReopened &&
                [JuceBridge waitForOutputCallbackProofV2ObjC:2000];
            if (!playbackReopened) {
                diagnosticCode = @"juce_reopen_failed";
            }
        }
        if (playbackReopened && playbackCallbackReady) {
            NSDictionary *snapshot = [self buildAudioRouteSnapshotV2];
            NSDictionary *sessionFacts =
                [snapshot[@"session"] isKindOfClass:[NSDictionary class]]
                    ? snapshot[@"session"] : @{};
            NSDictionary *juce = [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
                ? snapshot[@"juce"] : @{};
            NSArray *inputs = [snapshot[@"inputs"] isKindOfClass:[NSArray class]]
                ? snapshot[@"inputs"] : @[];
            NSArray *outputs = [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
                ? snapshot[@"outputs"] : @[];
            NSDictionary *actualOutput = outputs.count == 1 ? outputs.firstObject : nil;
            restoredOutputForFacts = actualOutput;
            const BOOL outputIdentityVerified =
                recoveringAfterPhysicalInvalidation
                    ? MixroomIOSOutputIdentityIsObservable(actualOutput)
                    : MixroomIOSEndpointIdentitiesMatchStrict(
                          expectedOutput, actualOutput);
            success = (!restoringBluetoothProbe ||
                       recoveringAfterPhysicalInvalidation ||
                       ![JuceBridge isIOSIntentRouteInvalidatedV2ObjC]) &&
                generation == self.audioRouteGenerationV2 &&
                [snapshot[@"captureConsistency"] isEqualToString:@"stable"] &&
                outputIdentityVerified &&
                !MixroomIOSOutputIsBluetoothDuplex(actualOutput) &&
                [sessionFacts[@"category"] isEqual:AVAudioSessionCategoryPlayback] &&
                [sessionFacts[@"mode"] isEqual:AVAudioSessionModeDefault] &&
                inputs.count == 0 &&
                [sessionFacts[@"inputChannelCount"] integerValue] == 0 &&
                [juce[@"deviceOpen"] boolValue] &&
                [juce[@"audioCallbackAttached"] boolValue] &&
                [juce[@"activeInputChannels"] integerValue] == 0 &&
                [juce[@"activeOutputChannels"] integerValue] > 0 &&
                [juce[@"sampleRateHz"] doubleValue] > 1000.0 &&
                [juce[@"bufferFrames"] integerValue] > 0 &&
                MixroomIOSPlaybackSnapshotMatchesClock(
                    snapshot,
                    actualOutput,
                    [JuceBridge getOutputCallbackProofSampleRateV2ObjC]
                        .doubleValue,
                    [JuceBridge getOutputCallbackProofFramesV2ObjC]
                        .integerValue,
                    [JuceBridge getOutputCallbackProofCountV2ObjC]
                        .unsignedLongLongValue);
            if (!success) {
                if (restoringBluetoothProbe &&
                    !recoveringAfterPhysicalInvalidation &&
                    [JuceBridge isIOSIntentRouteInvalidatedV2ObjC]) {
                    diagnosticCode = @"route_unstable";
                } else {
                    diagnosticCode = generation == self.audioRouteGenerationV2
                        ? @"actual_state_unavailable"
                        : @"stale_generation";
                }
            }
        } else if (playbackReopened && !playbackCallbackReady) {
            diagnosticCode = @"actual_state_unavailable";
        }
        if (success) {
            if (restoringBluetoothProbe) {
                self.audioRouteFingerprintV2 =
                    MixroomIOSOutputFingerprint(session.currentRoute);
                self.iosObservedOutputWasBluetoothV2 =
                    MixroomIOSOutputIsBluetooth(restoredOutputForFacts);
                self.iosVerifiedPlaybackOutputFingerprintV2 =
                    self.audioRouteFingerprintV2;
                self.iosVerifiedPlaybackOutputWasBluetoothV2 =
                    self.iosObservedOutputWasBluetoothV2;
                self.routeTransitionFromBluetoothV2 = NO;
                self.routeTransitionWasPlayingV2 = NO;
                NSDictionary *verifiedDuplexFacts =
                    [self.iosLastDuplexProbeV2 isKindOfClass:[NSDictionary class]]
                        ? self.iosLastDuplexProbeV2 : @{};
                self.iosLastDuplexProbeV2 = @{
                    @"status": recoveringAfterPhysicalInvalidation
                        ? @"recoveredAfterDisconnect" : @"restored",
                    @"diagnosticCode": recoveringAfterPhysicalInvalidation
                        ? @"fallback_succeeded" : @"ok",
                    @"validationStage": @"duplexVerified",
                    @"phase": @"complete",
                    @"terminalCause": recoveringAfterPhysicalInvalidation
                        ? (self.iosIntentTerminalCauseV2 ?:
                           @"physicalRouteInvalidation")
                        : [NSNull null],
                    @"cleanupOutcome": recoveringAfterPhysicalInvalidation
                        ? @"recovered" : @"restored",
                    @"selectionMode":
                        verifiedDuplexFacts[@"selectionMode"] ?:
                            @"explicitHfp",
                    @"categoryOptions":
                        verifiedDuplexFacts[@"categoryOptions"] ?: @[],
                    @"operationId": @(self.iosIntentOperationIdV2),
                    @"actualCallbackCount":
                        verifiedDuplexFacts[@"actualCallbackCount"] ?: @0,
                    @"elapsedMs": @((NSInteger)(
                        MixroomIOSMonotonicMilliseconds() -
                        self.iosIntentOperationStartedAtMsV2 + 0.5)),
                    @"sourceOutput": recordingSourceOutput ?: expectedOutput,
                    @"duplexInput": self.iosRecordingInputV2 ?: [NSNull null],
                    @"duplexOutput":
                        self.iosIntentOperationTargetOutputV2 ?: [NSNull null],
                    @"restoredOutput":
                        restoredOutputForFacts ?: [NSNull null],
                };
                [JuceBridge endIOSIntentOperationV2ObjC];
                self.iosIntentOperationActiveV2 = NO;
                self.iosIntentOperationModeV2 = @"standard";
                self.iosIntentMonitoringTargetRowV2 = -1;
                self.iosIntentLifecyclePhaseV2 = @"idle";
                self.iosIntentRouteConditionV2 = nil;
                self.iosIntentOperationCancelledV2 = NO;
                self.iosIntentOperationSourceFingerprintV2 = nil;
                self.iosIntentOperationPendingFingerprintV2 = nil;
                self.iosIntentOperationTargetFingerprintV2 = nil;
                self.iosIntentOperationTargetOutputV2 = nil;
            }
            if (recoveringAfterPhysicalInvalidation) {
                playbackRecoveryUsedFallback = YES;
                diagnosticCode = @"fallback_succeeded";
            }
            self.iosRecordingOutputV2 = nil;
            self.iosRecordingInputV2 = nil;
        } else if (restoringBluetoothProbe) {
            [JuceBridge quiescePlaybackRouteV2ObjC:YES];
            NSDictionary<NSString *, id> *currentOutput =
                MixroomIOSSingleOutputEndpoint(session.currentRoute);
            const BOOL physicalRouteInvalidation =
                recoveringAfterPhysicalInvalidation ||
                [JuceBridge isIOSIntentRouteInvalidatedV2ObjC] ||
                (!MixroomIOSEndpointIdentitiesMatchStrict(
                     expectedOutput, currentOutput) &&
                 !MixroomIOSOutputIsBluetoothHFP(currentOutput));
            NSDictionary *verifiedDuplexFacts =
                [self.iosLastDuplexProbeV2 isKindOfClass:[NSDictionary class]]
                    ? self.iosLastDuplexProbeV2 : @{};
            self.iosLastDuplexProbeV2 = @{
                @"status": @"failed",
                @"diagnosticCode": diagnosticCode,
                @"validationStage": physicalRouteInvalidation
                    ? @"physicalRouteInvalidation" : @"restoration",
                @"phase": @"cleanup",
                @"terminalCause": physicalRouteInvalidation
                    ? (self.iosIntentTerminalCauseV2 ?: @"physicalRouteInvalidation")
                    : [NSNull null],
                @"cleanupOutcome": @"closed",
                @"selectionMode":
                    verifiedDuplexFacts[@"selectionMode"] ?: @"explicitHfp",
                @"categoryOptions":
                    verifiedDuplexFacts[@"categoryOptions"] ?: @[],
                @"operationId": @(self.iosIntentOperationIdV2),
                @"actualCallbackCount":
                    verifiedDuplexFacts[@"actualCallbackCount"] ?: @0,
                @"elapsedMs": @((NSInteger)(
                    MixroomIOSMonotonicMilliseconds() -
                    self.iosIntentOperationStartedAtMsV2 + 0.5)),
                @"sourceOutput": recordingSourceOutput ?: expectedOutput ?:
                    [NSNull null],
                @"duplexInput": self.iosRecordingInputV2 ?: [NSNull null],
                @"duplexOutput":
                    self.iosIntentOperationTargetOutputV2 ?: [NSNull null],
                @"restoredOutput": [NSNull null],
            };
            [JuceBridge endIOSIntentOperationV2ObjC];
            self.iosIntentOperationActiveV2 = NO;
            self.iosIntentOperationModeV2 = @"standard";
            self.iosIntentMonitoringTargetRowV2 = -1;
            self.iosIntentLifecyclePhaseV2 = @"idle";
            self.iosIntentRouteConditionV2 = nil;
            self.iosIntentOperationCancelledV2 = YES;
            self.iosIntentOperationSourceFingerprintV2 = nil;
            self.iosIntentOperationPendingFingerprintV2 = nil;
            self.iosIntentOperationTargetFingerprintV2 = nil;
            self.iosIntentOperationTargetOutputV2 = nil;
            self.iosRecordingOutputV2 = nil;
            self.iosRecordingInputV2 = nil;
        }
    }

    if (success && [self isIOSMonitorOwnedV2] &&
        (![self isIOSCaptureCurrentV2:self.iosIntentOperationIdV2 generation:generation] ||
         ([intent isEqualToString:@"recording"] && self.iosCaptureV2.cancelled))) {
        success = NO;
        diagnosticCode = @"stale_generation";
    }
    if (success) {
        self.currentAudioRouteIntentV2 = intent;
        if ([intent isEqualToString:@"playbackOnly"] &&
            self.iosInterruptionRecoveryPendingV2) {
            self.iosInterruptionRecoveryPendingV2 = NO;
            self.iosInterruptionPhaseV2 = @"complete";
            self.iosInterruptionRecoveryOutcomeV2 = @"recovered";
            self.iosForegroundRecoveryPendingV2 = NO;
            self.audioRouteFingerprintV2 =
                MixroomIOSOutputFingerprint(session.currentRoute);
            NSDictionary<NSString *, id> *recoveredOutput =
                MixroomIOSSingleOutputEndpoint(session.currentRoute);
            self.iosObservedOutputWasBluetoothV2 =
                recoveredOutput != nil &&
                MixroomIOSOutputIsBluetooth(recoveredOutput);
            self.iosVerifiedPlaybackOutputFingerprintV2 =
                self.audioRouteFingerprintV2;
            self.iosVerifiedPlaybackOutputWasBluetoothV2 =
                self.iosObservedOutputWasBluetoothV2;
            self.routeTransitionWasPlayingV2 = NO;
            self.routeTransitionFromBluetoothV2 = NO;
            self.iosIntentTerminalCauseV2 = nil;
        }
    } else if ([intent isEqualToString:@"playbackOnly"] &&
               self.iosInterruptionRecoveryPendingV2 &&
               !self.iosInterruptionActiveV2) {
        self.iosInterruptionRecoveryPendingV2 = NO;
        self.iosInterruptionPhaseV2 = @"failed";
        self.iosInterruptionRecoveryOutcomeV2 = @"failed";
        self.iosForegroundRecoveryPendingV2 = NO;
    } else if (([intent isEqualToString:@"preparingRecording"] ||
                monitoringIntent) &&
               recordingRouteMutationStarted) {
        NSDictionary<NSString *, id> *probeSource =
            self.iosRecordingOutputV2;
        const BOOL failedBluetoothProbe =
            self.iosIntentOperationActiveV2;
        if (failedBluetoothProbe) {
            [self claimIOSIntentCleanupV2];
            self.iosIntentLifecyclePhaseV2 = @"cleanup";
        }
        NSDictionary<NSString *, id> *currentProbeOutput =
            MixroomIOSSingleOutputEndpoint(session.currentRoute);
        const BOOL operationRouteStillPresent =
            MixroomIOSEndpointIdentitiesMatchStrict(
                probeSource, currentProbeOutput) ||
            MixroomIOSOutputIsBluetoothHFP(currentProbeOutput);
        const BOOL physicalRouteInvalidation =
            failedBluetoothProbe &&
            ([JuceBridge isIOSIntentRouteInvalidatedV2ObjC] ||
             !operationRouteStillPresent);
        if (physicalRouteInvalidation) {
            diagnosticCode = @"route_unstable";
            probeValidationStage = @"physicalRouteInvalidation";
        }
        [JuceBridge disableLiveInputMonitoringV2ObjC];
        [JuceBridge stopRecordingObjC];
        BOOL outputRestored = physicalRouteInvalidation
            ? NO : [JuceBridge
                reconfigurePlaybackRouteV2ObjC:@""
                sampleRate:MixroomIOSPlaybackOpenRate(
                    probeSource,
                    session,
                    self.preferredPlaybackSampleRateV2)
                bufferFrames:MixroomIOSPlaybackOpenBuffer(
                    probeSource,
                    session,
                    self.preferredPlaybackBufferFramesV2)];
        NSDictionary *restoredSnapshot = outputRestored
            ? [self buildAudioRouteSnapshotV2] : nil;
        NSArray *restoredOutputs =
            [restoredSnapshot[@"outputs"] isKindOfClass:[NSArray class]]
                ? restoredSnapshot[@"outputs"] : @[];
        NSDictionary *restoredOutput = restoredOutputs.count == 1
            ? restoredOutputs.firstObject : nil;
        if (failedBluetoothProbe) {
            outputRestored = outputRestored &&
                [restoredSnapshot[@"captureConsistency"]
                    isEqualToString:@"stable"] &&
                MixroomIOSEndpointIdentitiesMatchStrict(
                    probeSource, restoredOutput);
            self.iosLastDuplexProbeV2 = @{
                @"status": outputRestored ? @"failedRestored" : @"failed",
                @"diagnosticCode": diagnosticCode,
                @"validationStage": probeValidationStage,
                @"phase": @"cleanup",
                @"terminalCause": physicalRouteInvalidation
                    ? (self.iosIntentTerminalCauseV2 ?: @"physicalRouteInvalidation")
                    : [NSNull null],
                @"cleanupOutcome": outputRestored ? @"restored" : @"closed",
                @"selectionMode": systemSelectedRoute
                    ? @"systemSelected" : @"explicitHfp",
                @"categoryOptions": probeCandidateCategoryOptions,
                @"operationId": @(self.iosIntentOperationIdV2),
                @"actualCallbackCount": probeActualCallbackCount,
                @"elapsedMs": @((NSInteger)(
                    MixroomIOSMonotonicMilliseconds() -
                    self.iosIntentOperationStartedAtMsV2 + 0.5)),
                @"sourceOutput": probeSource ?: [NSNull null],
                @"duplexInput": probeCandidateInput ?: [NSNull null],
                @"duplexOutput":
                    probeCandidateOutput ?: [NSNull null],
                @"restoredOutput": restoredOutput ?: [NSNull null],
            };
            [JuceBridge endIOSIntentOperationV2ObjC];
            self.iosIntentOperationActiveV2 = NO;
            self.iosIntentOperationModeV2 = @"standard";
            self.iosIntentMonitoringTargetRowV2 = -1;
            self.iosIntentLifecyclePhaseV2 = @"idle";
            self.iosIntentRouteConditionV2 = nil;
            self.iosIntentOperationSourceFingerprintV2 = nil;
            self.iosIntentOperationPendingFingerprintV2 = nil;
            self.iosIntentOperationTargetFingerprintV2 = nil;
            self.iosIntentOperationTargetOutputV2 = nil;
        }
        self.iosRecordingOutputV2 = nil;
        self.iosRecordingInputV2 = nil;
        if (outputRestored) {
            self.currentAudioRouteIntentV2 = @"playbackOnly";
            self.audioRouteFingerprintV2 =
                MixroomIOSOutputFingerprint(session.currentRoute);
        } else {
            [JuceBridge quiescePlaybackRouteV2ObjC:YES];
        }
    }

    NSDictionary *snapshot = [self buildAudioRouteSnapshotV2];
    const NSInteger elapsedMs = (NSInteger)(
        MixroomIOSMonotonicMilliseconds() - startedAtMs + 0.5);
    return @{
        @"status": success
            ? (playbackRecoveryUsedFallback ? @"fallback" : @"success")
            : @"failure",
        @"generation": @(generation),
        @"transitionId": @(transitionID),
        @"diagnosticCode": diagnosticCode,
        @"elapsedMs": @(elapsedMs),
        @"transportWasPlaying": @NO,
        @"snapshot": snapshot,
    };
#endif
}

#if !TARGET_OS_OSX
- (BOOL)isIOSCaptureCurrentV2:(uint64_t)operationID generation:(uint64_t)generation {
    return !self.applicationTerminationStarted && !self.iosInterruptionActiveV2 &&
        self.audioRouteMonitoringV2 && operationID == self.iosIntentOperationIdV2 &&
        generation == self.audioRouteGenerationV2 &&
        (!self.iosIntentOperationActiveV2 ||
         (generation == self.iosIntentOperationGenerationV2 &&
          !self.iosIntentOperationCancelledV2 && !self.iosIntentCleanupClaimedV2)) &&
        ![JuceBridge isIOSIntentRouteInvalidatedV2ObjC];
}

- (BOOL)isIOSMonitorOwnedV2 {
    return self.iosIntentOperationActiveV2 &&
        [self.iosIntentOperationModeV2 isEqualToString:@"systemSelectedMonitoring"];
}

- (MixroomIOSCaptureLifecycleV2 *)newIOSCaptureV2 {
    return [[MixroomIOSCaptureLifecycleV2 alloc]
        initWithNative:[[[MixroomIOSCaptureBridgeV2 alloc] init] autorelease]
        preserveMonitoring:[self isIOSMonitorOwnedV2]
        targetRow:self.iosIntentMonitoringTargetRowV2
        channelStart:self.iosIntentRecordingChannelStartV2
        channelCount:self.iosIntentRecordingChannelCountV2
        streamGeneration:self.iosMonitorStreamGenerationV2];
}

- (BOOL)iosCaptureRouteReadyV2 {
    if (![JuceBridge validateRecordingRouteV2ObjC]) return NO;
    if (![self isIOSMonitorOwnedV2]) return YES;
    NSDictionary *snapshot = [self buildAudioRouteSnapshotV2];
    NSArray *inputs = snapshot[@"inputs"];
    NSArray *outputs = snapshot[@"outputs"];
    NSDictionary *input = inputs.count == 1 ? inputs.firstObject : nil;
    NSDictionary *output = outputs.count == 1 ? outputs.firstObject : nil;
    return [snapshot[@"captureConsistency"] isEqualToString:@"stable"] &&
        MixroomIOSMonitoringEndpointIsAllowed(input) &&
        MixroomIOSMonitoringEndpointIsAllowed(output) &&
        MixroomIOSEndpointIdentitiesMatchStrict(self.iosRecordingInputV2, input) &&
        MixroomIOSEndpointIdentitiesMatchStrict(self.iosIntentOperationTargetOutputV2, output) &&
        [self.iosIntentOperationTargetFingerprintV2 isEqualToString:
            MixroomIOSRouteFingerprint([AVAudioSession sharedInstance].currentRoute)] &&
        [JuceBridge isBluetoothDuplexProjectCallbackReadyV2ObjC];
}

- (void)startIOSCaptureV2:(NSDictionary *)args result:(FlutterResult)result {
    const BOOL monitor = [self isIOSMonitorOwnedV2];
    const BOOL admittedIntent = monitor
        ? [self.currentAudioRouteIntentV2 isEqualToString:@"monitoring"]
        : [self.currentAudioRouteIntentV2 isEqualToString:@"preparingRecording"];
    if (self.iosLifecycleTransitionActiveV2 || !admittedIntent) { result(@NO); return; }
    const uint64_t operationID = self.iosIntentOperationIdV2;
    const uint64_t generation = self.audioRouteGenerationV2;
    if (![self isIOSCaptureCurrentV2:operationID generation:generation]) { result(@NO); return; }
    MixroomIOSCaptureLifecycleV2 *capture = [[self newIOSCaptureV2] autorelease];
    self.iosCaptureV2 = capture;
    self.iosLifecycleTransitionActiveV2 = YES;
    const uint64_t transition = ++self.iosLifecycleCompletionTokenV2;
    dispatch_async(MixroomIOSLifecycleQueue(), ^{
        BOOL started = [capture start:args[@"path"]
            channelStart:[args[@"channelStart"] integerValue]
            channelCount:[args[@"channelCount"] integerValue]
            currentAndReady:^BOOL {
                return [self isIOSCaptureCurrentV2:operationID generation:generation] &&
                    self.iosCaptureV2 == capture && (!monitor || [self isIOSMonitorOwnedV2]) && [self iosCaptureRouteReadyV2];
            }];
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL current = [self isIOSCaptureCurrentV2:operationID generation:generation] &&
                self.iosCaptureV2 == capture && (!monitor || [self isIOSMonitorOwnedV2]);
            if (started && ![capture canDeliverStartWithCurrent:current]) {
                dispatch_async(MixroomIOSLifecycleQueue(), ^{
                    [capture discardWithCurrent:self.iosCaptureV2 == capture &&
                        operationID == self.iosIntentOperationIdV2];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (transition == self.iosLifecycleCompletionTokenV2)
                            self.iosLifecycleTransitionActiveV2 = NO;
                        result(@NO);
                    });
                });
            } else {
                if (transition == self.iosLifecycleCompletionTokenV2)
                    self.iosLifecycleTransitionActiveV2 = NO;
                // Box explicitly as a boolean for Dart's invokeMethod<bool>.
                // Boxing a C logical expression produces an NSNumber integer.
                result(started && current ? @YES : @NO);
            }
        });
    });
}

- (void)stopIOSCaptureV2:(FlutterResult)result {
    if (self.iosLifecycleTransitionActiveV2) {
        result(@{@"success": @NO, @"diagnosticCode": @"route_unstable"}); return;
    }
    const BOOL monitor = [self isIOSMonitorOwnedV2];
    const uint64_t operationID = self.iosIntentOperationIdV2;
    const uint64_t generation = self.audioRouteGenerationV2;
    MixroomIOSCaptureLifecycleV2 *capture = self.iosCaptureV2;
    if (capture == nil) capture = [[self newIOSCaptureV2] autorelease];
    self.iosCaptureV2 = capture;
    self.iosLifecycleTransitionActiveV2 = YES;
    const uint64_t transition = ++self.iosLifecycleCompletionTokenV2;
    dispatch_async(MixroomIOSLifecycleQueue(), ^{
        NSDictionary *report = [capture finalizeWithCurrent:^BOOL {
            return [self isIOSCaptureCurrentV2:operationID generation:generation] &&
                self.iosCaptureV2 == capture && (!monitor || [self isIOSMonitorOwnedV2]);
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (transition == self.iosLifecycleCompletionTokenV2)
                self.iosLifecycleTransitionActiveV2 = NO;
            BOOL current = [self isIOSCaptureCurrentV2:operationID generation:generation] &&
                self.iosCaptureV2 == capture && (!monitor || [self isIOSMonitorOwnedV2]);
            result(current ? report : @{@"success": @NO, @"diagnosticCode": @"stale_generation"});
        });
    });
}
#endif

- (void)setAudioRouteIntentV2:(NSDictionary *)args
                   completion:(void (^)(NSDictionary<NSString *, id> *))completion {
    if (completion == nil) {
        return;
    }

    NSDictionary *immutableArgs = [[args copy] autorelease] ?: @{};
#if TARGET_OS_OSX
    self.macLifecycleTransitionActiveV2 = YES;
    self.macLifecycleReconcilePendingV2 = NO;
    const BOOL beginsInvalidationRecovery =
        self.macIntentRecoveryPendingV2 &&
        [immutableArgs[@"intent"] isEqualToString:@"playbackOnly"];
    if (beginsInvalidationRecovery) {
        NSLog(@"[MacV2Recovery] admitted generation=%llu",
              (unsigned long long)[immutableArgs[@"generation"]
                  unsignedLongLongValue]);
    }
    dispatch_async(MixroomMacPlaybackStartupQueue(), ^{
        @autoreleasepool {
            NSDictionary<NSString *, id> *rawResponse =
                [self setAudioRouteIntentV2:immutableArgs] ?: @{
                    @"status": @"failure",
                    @"generation": @0,
                    @"transitionId": @0,
                    @"diagnosticCode": @"actual_state_unavailable",
                    @"elapsedMs": @0,
                    @"transportWasPlaying": @NO,
                    @"snapshot": @{},
                };
            NSDictionary<NSString *, id> *response = [rawResponse copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *diagnosticCode =
                    [response[@"diagnosticCode"] isKindOfClass:[NSString class]]
                        ? response[@"diagnosticCode"]
                        : @"actual_state_unavailable";
                NSDictionary *snapshot =
                    [response[@"snapshot"] isKindOfClass:[NSDictionary class]]
                        ? response[@"snapshot"]
                        : @{};
                const uint64_t attemptedGeneration =
                    [immutableArgs[@"generation"] unsignedLongLongValue];
                const uint64_t snapshotGeneration =
                    [snapshot[@"generation"] unsignedLongLongValue];
                const uint64_t finalGeneration = self.audioRouteGenerationV2;
                if (beginsInvalidationRecovery) {
                    const BOOL stalePreflight =
                        [diagnosticCode isEqualToString:@"stale_generation"];
                    if (!stalePreflight) {
                        self.macIntentRecoveryPendingV2 = NO;
                    }
                    NSLog(@"[MacV2Recovery] result attempted=%llu snapshot=%llu "
                          "final=%llu status=%@ code=%@",
                          (unsigned long long)attemptedGeneration,
                          (unsigned long long)snapshotGeneration,
                          (unsigned long long)finalGeneration,
                          response[@"status"] ?: @"failure",
                          diagnosticCode);
                }
                const BOOL reconcile = self.macLifecycleReconcilePendingV2;
                self.macLifecycleReconcilePendingV2 = NO;
                self.macLifecycleTransitionActiveV2 = NO;
                completion(response);
                if (reconcile) {
                    [self handleAudioRoutePropertyChangeV2:@"transitionReconcile"];
                }
                [response release];
            });
        }
    });
#else
    if (self.iosLifecycleTransitionActiveV2) {
        completion(@{@"status": @"failure", @"generation": immutableArgs[@"generation"] ?: @0,
            @"transitionId": @(self.audioRouteTransitionIdV2), @"diagnosticCode": @"route_unstable",
            @"elapsedMs": @0, @"transportWasPlaying": @NO, @"snapshot": [self buildAudioRouteSnapshotV2]});
        return;
    }
    self.iosIntentCompletionDeliveredV2 = NO;
    self.iosLifecycleTransitionActiveV2 = YES;
    const uint64_t transition = ++self.iosLifecycleCompletionTokenV2;
    dispatch_async(MixroomIOSLifecycleQueue(), ^{
        NSDictionary<NSString *, id> *response =
            [self setAudioRouteIntentV2:immutableArgs] ?: @{
                @"status": @"failure",
                @"generation": @0,
                @"transitionId": @0,
                @"diagnosticCode": @"actual_state_unavailable",
                @"elapsedMs": @0,
                @"transportWasPlaying": @NO,
                @"snapshot": @{},
            };
        const BOOL monitor = [self isIOSMonitorOwnedV2];
        const uint64_t operationID = self.iosIntentOperationIdV2;
        const uint64_t generation = [immutableArgs[@"generation"] unsignedLongLongValue];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (transition != self.iosLifecycleCompletionTokenV2 ||
                (monitor && (![self isIOSMonitorOwnedV2] || ![self isIOSCaptureCurrentV2:operationID generation:generation] ||
                 ([immutableArgs[@"intent"] isEqualToString:@"recording"] && self.iosCaptureV2.cancelled)))) {
                NSMutableDictionary *stale = [NSMutableDictionary dictionaryWithDictionary:response];
                stale[@"status"] = @"failure";
                stale[@"diagnosticCode"] = @"stale_generation";
                if (transition == self.iosLifecycleCompletionTokenV2)
                    self.iosLifecycleTransitionActiveV2 = NO;
                completion(stale);
                return;
            }
            self.iosLifecycleTransitionActiveV2 = NO;
            if (!self.iosIntentCompletionDeliveredV2) {
                self.iosIntentCompletionDeliveredV2 = YES;
                completion(response);
            }
        });
    });
#endif
}

- (void)updateObservedOutputDeviceV2:(uint32_t)deviceID {
#if TARGET_OS_OSX
    AudioObjectPropertyAddress aliveAddress = {
        kAudioDevicePropertyDeviceIsAlive,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    AudioObjectPropertyAddress rateAddress = {
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    AudioObjectPropertyAddress bufferAddress = {
        kAudioDevicePropertyBufferFrameSize,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    AudioObjectPropertyAddress streamsAddress = {
        kAudioDevicePropertyStreamConfiguration,
        kAudioDevicePropertyScopeOutput,
        kMixroomCoreAudioElement,
    };
    if (self.observedOutputDeviceV2 != kAudioObjectUnknown) {
        AudioObjectRemovePropertyListener(
            self.observedOutputDeviceV2,
            &aliveAddress,
            MixroomAudioRoutePropertyListenerV2,
            self);
        AudioObjectRemovePropertyListener(self.observedOutputDeviceV2,
            &rateAddress, MixroomAudioRoutePropertyListenerV2, self);
        AudioObjectRemovePropertyListener(self.observedOutputDeviceV2,
            &bufferAddress, MixroomAudioRoutePropertyListenerV2, self);
        AudioObjectRemovePropertyListener(self.observedOutputDeviceV2,
            &streamsAddress, MixroomAudioRoutePropertyListenerV2, self);
    }
    self.observedOutputDeviceV2 = deviceID;
    if (deviceID != kAudioObjectUnknown &&
        AudioObjectHasProperty(deviceID, &aliveAddress)) {
        AudioObjectAddPropertyListener(
            deviceID,
            &aliveAddress,
            MixroomAudioRoutePropertyListenerV2,
            self);
        AudioObjectAddPropertyListener(deviceID, &rateAddress,
            MixroomAudioRoutePropertyListenerV2, self);
        AudioObjectAddPropertyListener(deviceID, &bufferAddress,
            MixroomAudioRoutePropertyListenerV2, self);
        AudioObjectAddPropertyListener(deviceID, &streamsAddress,
            MixroomAudioRoutePropertyListenerV2, self);
    }
#else
    #pragma unused(deviceID)
#endif
}

- (BOOL)startIOSAudioRouteMonitoringV2 {
#if !TARGET_OS_OSX
    if (![[JuceBridge getAudioRouteImplementationObjC] isEqualToString:@"v2"]) {
        return NO;
    }
    if (self.audioRouteMonitoringV2) {
        return YES;
    }
    if (self.eventSink == nil) {
        return NO;
    }
    AVAudioSessionRouteDescription *route =
        [AVAudioSession sharedInstance].currentRoute;
    if (route == nil) {
        return NO;
    }
    NSDictionary<NSString *, id> *output =
        MixroomIOSSingleOutputEndpoint(route);
    self.audioRouteGenerationV2 = 0;
    self.audioRouteTransitionIdV2 = 0;
    self.routeTransitionWasPlayingV2 = NO;
    self.routeTransitionFromBluetoothV2 = NO;
    self.iosLastObservedRouteCauseV2 = nil;
    [JuceBridge endIOSIntentOperationV2ObjC];
    self.iosIntentOperationActiveV2 = NO;
    self.iosIntentOperationModeV2 = @"standard";
    self.iosIntentOperationCancelledV2 = NO;
    self.iosIntentOperationSourceFingerprintV2 = nil;
    self.iosIntentOperationPendingFingerprintV2 = nil;
    self.iosIntentOperationTargetFingerprintV2 = nil;
    self.iosIntentOperationTargetOutputV2 = nil;
    self.iosInterruptionActiveV2 = NO;
    self.iosInterruptionRecoveryPendingV2 = NO;
    self.iosInterruptionWasSuspendedV2 = NO;
    self.iosInterruptionShouldResumeV2 = NO;
    self.iosInterruptionPhaseV2 = @"idle";
    self.iosInterruptionReasonV2 = nil;
    self.iosInterruptionRecoveryOutcomeV2 = nil;
    self.iosForegroundRecoveryPendingV2 = NO;
    NSString *currentFingerprint = MixroomIOSOutputFingerprint(route);
    self.audioRouteFingerprintV2 =
        self.iosVerifiedPlaybackOutputFingerprintV2.length > 0
            ? self.iosVerifiedPlaybackOutputFingerprintV2
            : currentFingerprint;
    self.iosObservedOutputWasBluetoothV2 =
        self.iosVerifiedPlaybackOutputFingerprintV2.length > 0
            ? self.iosVerifiedPlaybackOutputWasBluetoothV2
            : (output != nil && MixroomIOSOutputIsBluetooth(output));
    self.audioRouteMonitoringV2 = YES;
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(handleIOSAudioRouteChangeV2:)
               name:AVAudioSessionRouteChangeNotification
             object:[AVAudioSession sharedInstance]];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(handleIOSAudioRouteChangeV2:)
               name:UIApplicationDidBecomeActiveNotification
             object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(handleIOSAudioRouteChangeV2:)
               name:UIApplicationDidEnterBackgroundNotification
             object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(handleIOSAudioRouteChangeV2:)
               name:AVAudioSessionInterruptionNotification
             object:[AVAudioSession sharedInstance]];
    if (![currentFingerprint isEqualToString:self.audioRouteFingerprintV2]) {
        [self handleIOSAudioRouteChangeV2:[NSNotification
            notificationWithName:UIApplicationDidBecomeActiveNotification
                         object:nil]];
    }
    return YES;
#else
    return NO;
#endif
}

- (void)stopIOSAudioRouteMonitoringV2 {
#if !TARGET_OS_OSX
    [JuceBridge disableLiveInputMonitoringV2ObjC];
    if (self.audioRouteMonitoringV2) {
        [[NSNotificationCenter defaultCenter]
            removeObserver:self
                      name:AVAudioSessionRouteChangeNotification
                    object:[AVAudioSession sharedInstance]];
        [[NSNotificationCenter defaultCenter]
            removeObserver:self
                      name:UIApplicationDidBecomeActiveNotification
                    object:nil];
        [[NSNotificationCenter defaultCenter]
            removeObserver:self
                      name:UIApplicationDidEnterBackgroundNotification
                    object:nil];
        [[NSNotificationCenter defaultCenter]
            removeObserver:self
                      name:AVAudioSessionInterruptionNotification
                    object:[AVAudioSession sharedInstance]];
    }
    self.audioRouteMonitoringV2 = NO;
    self.audioRouteGenerationV2 += 1;
    self.audioRouteFingerprintV2 = nil;
    self.routeTransitionWasPlayingV2 = NO;
    self.routeTransitionFromBluetoothV2 = NO;
    self.iosObservedOutputWasBluetoothV2 = NO;
    self.iosVerifiedPlaybackOutputFingerprintV2 = nil;
    self.iosVerifiedPlaybackOutputWasBluetoothV2 = NO;
    self.iosLastObservedRouteCauseV2 = nil;
    self.iosIntentOperationCancelledV2 = self.iosIntentOperationActiveV2;
    self.iosIntentTerminalCauseV2 = @"shutdown";
    self.iosInterruptionActiveV2 = NO;
    self.iosInterruptionRecoveryPendingV2 = NO;
    self.iosInterruptionPhaseV2 = @"shutdown";
    self.iosInterruptionRecoveryOutcomeV2 = @"shutdown";
    self.iosForegroundRecoveryPendingV2 = NO;
    [self signalIOSIntentRouteConditionV2];
#endif
}

#if !TARGET_OS_OSX
- (void)handleIOSAudioRouteChangeV2:(NSNotification *)notification {
    const BOOL routeNotification =
        [notification.name isEqualToString:AVAudioSessionRouteChangeNotification];
    const BOOL interruptionNotification =
        [notification.name isEqualToString:AVAudioSessionInterruptionNotification];
    const BOOL appBecameActiveNotification =
        [notification.name isEqualToString:UIApplicationDidBecomeActiveNotification];
    const BOOL appEnteredBackgroundNotification =
        [notification.name isEqualToString:UIApplicationDidEnterBackgroundNotification];
    NSNumber *interruptionTypeValue =
        interruptionNotification &&
        [notification.userInfo[AVAudioSessionInterruptionTypeKey]
            isKindOfClass:[NSNumber class]]
            ? notification.userInfo[AVAudioSessionInterruptionTypeKey]
            : nil;
    const BOOL interruptionEnded = interruptionNotification &&
        interruptionTypeValue != nil &&
        interruptionTypeValue.unsignedIntegerValue ==
            AVAudioSessionInterruptionTypeEnded;
    const BOOL interruptionBegan = interruptionNotification &&
        !interruptionEnded;
    NSNumber *interruptionOptionsValue =
        interruptionNotification &&
        [notification.userInfo[AVAudioSessionInterruptionOptionKey]
            isKindOfClass:[NSNumber class]]
            ? notification.userInfo[AVAudioSessionInterruptionOptionKey]
            : nil;
    const BOOL interruptionShouldResume = interruptionEnded &&
        (interruptionOptionsValue.unsignedIntegerValue &
         AVAudioSessionInterruptionOptionShouldResume) != 0;
    NSNumber *interruptionSuspendedValue =
        interruptionNotification &&
        [notification.userInfo[AVAudioSessionInterruptionWasSuspendedKey]
            isKindOfClass:[NSNumber class]]
            ? notification.userInfo[AVAudioSessionInterruptionWasSuspendedKey]
            : nil;
    const BOOL interruptionWasSuspended =
        interruptionBegan && interruptionSuspendedValue.boolValue;
    const BOOL duplicateSuspendedInterruption =
        interruptionWasSuspended && self.iosInterruptionRecoveryPendingV2;
    NSNumber *interruptionReasonValue =
        interruptionNotification &&
        [notification.userInfo[AVAudioSessionInterruptionReasonKey]
            isKindOfClass:[NSNumber class]]
            ? notification.userInfo[AVAudioSessionInterruptionReasonKey]
            : nil;
    NSNumber *reasonValue =
        routeNotification &&
        [notification.userInfo[AVAudioSessionRouteChangeReasonKey]
            isKindOfClass:[NSNumber class]]
            ? notification.userInfo[AVAudioSessionRouteChangeReasonKey]
            : nil;
    const AVAudioSessionRouteChangeReason reason = reasonValue == nil
        ? AVAudioSessionRouteChangeReasonUnknown
        : (AVAudioSessionRouteChangeReason)reasonValue.unsignedIntegerValue;
    const BOOL terminalRouteNotification = routeNotification &&
        (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable ||
         reason == AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory);
    if ((interruptionBegan && !duplicateSuspendedInterruption) ||
        terminalRouteNotification) {
        [JuceBridge markIOSIntentRouteInvalidatedV2ObjC];
        [self signalIOSIntentRouteConditionV2];
    }
    void (^observe)(void) = ^{
        if (!self.audioRouteMonitoringV2 ||
            ![[JuceBridge getAudioRouteImplementationObjC] isEqualToString:@"v2"]) {
            return;
        }
        if (appEnteredBackgroundNotification) {
            self.iosForegroundRecoveryPendingV2 = YES;
            return;
        }
        if (duplicateSuspendedInterruption) {
            return;
        }
        if (interruptionBegan && self.iosInterruptionActiveV2 &&
            !interruptionWasSuspended) {
            return;
        }
        if (interruptionEnded && !self.iosInterruptionActiveV2 &&
            ([self.iosInterruptionPhaseV2 isEqualToString:@"ended"] ||
             [self.iosInterruptionPhaseV2 isEqualToString:@"complete"])) {
            return;
        }
        if (appBecameActiveNotification && self.iosInterruptionActiveV2) {
            // Foregrounding does not prove that a call/Siri interruption ended.
            return;
        }
        const BOOL foregroundRecovery = appBecameActiveNotification &&
            self.iosForegroundRecoveryPendingV2;
        if (foregroundRecovery && self.iosInterruptionRecoveryPendingV2) {
            // A native interruption end already owns this foreground episode.
            self.iosForegroundRecoveryPendingV2 = NO;
            return;
        }
        AVAudioSessionRouteDescription *route =
            [AVAudioSession sharedInstance].currentRoute;
        if (route == nil && !interruptionNotification &&
            !foregroundRecovery &&
            !self.iosIntentOperationActiveV2) {
            return;
        }
        NSString *fingerprint = route == nil
            ? @"" : MixroomIOSOutputFingerprint(route);
        NSString *completeFingerprint = route == nil
            ? @"" : MixroomIOSRouteFingerprint(route);
        NSString *interruptionCause = nil;
        if (interruptionBegan) {
            self.iosIntentOperationCancelledV2 = YES;
            self.iosIntentTerminalCauseV2 = @"audioInterruptionBegan";
            self.iosInterruptionWasSuspendedV2 = interruptionWasSuspended;
            self.iosInterruptionShouldResumeV2 = NO;
            self.iosInterruptionReasonV2 = interruptionReasonValue;
            self.iosInterruptionRecoveryPendingV2 = YES;
            self.iosInterruptionRecoveryOutcomeV2 = @"pending";
            if (interruptionWasSuspended) {
                // A suspended-session notification is delivered only after the
                // app is running again, so it is already eligible for one
                // foreground recovery after cleanup.
                self.iosInterruptionActiveV2 = NO;
                self.iosInterruptionPhaseV2 = @"ended";
                interruptionCause = @"audioInterruptionEnded";
            } else {
                self.iosInterruptionActiveV2 = YES;
                self.iosInterruptionPhaseV2 = @"began";
                interruptionCause = @"audioInterruptionBegan";
            }
            [self signalIOSIntentRouteConditionV2];
        } else if (interruptionEnded) {
            self.iosInterruptionActiveV2 = NO;
            self.iosInterruptionRecoveryPendingV2 = YES;
            self.iosInterruptionPhaseV2 = @"ended";
            self.iosInterruptionShouldResumeV2 = interruptionShouldResume;
            self.iosInterruptionReasonV2 = interruptionReasonValue ?:
                self.iosInterruptionReasonV2;
            self.iosInterruptionRecoveryOutcomeV2 = @"pending";
            interruptionCause = @"audioInterruptionEnded";
        } else if (foregroundRecovery) {
            self.iosForegroundRecoveryPendingV2 = NO;
            self.iosInterruptionActiveV2 = NO;
            self.iosInterruptionRecoveryPendingV2 = YES;
            self.iosInterruptionWasSuspendedV2 = YES;
            self.iosInterruptionShouldResumeV2 = NO;
            self.iosInterruptionPhaseV2 = @"ended";
            self.iosInterruptionRecoveryOutcomeV2 = @"pending";
            interruptionCause = @"audioInterruptionEnded";
        } else if (self.iosIntentOperationActiveV2) {
            const BOOL matchesSource =
                self.iosIntentOperationSourceFingerprintV2.length > 0 &&
                [completeFingerprint isEqualToString:
                    self.iosIntentOperationSourceFingerprintV2];
            const BOOL matchesTarget =
                self.iosIntentOperationTargetFingerprintV2.length > 0 &&
                [completeFingerprint isEqualToString:
                    self.iosIntentOperationTargetFingerprintV2];
            if (matchesSource || matchesTarget) {
                self.audioRouteFingerprintV2 = fingerprint;
                NSDictionary<NSString *, id> *ownedOutput =
                    MixroomIOSSingleOutputEndpoint(route);
                self.iosObservedOutputWasBluetoothV2 =
                    ownedOutput != nil && MixroomIOSOutputIsBluetooth(ownedOutput);
                self.iosLastObservedRouteCauseV2 = routeNotification
                    ? MixroomIOSObservedRouteCause(reason)
                    : @"appBecameActive";
                return;
            }
            if (self.iosIntentOperationTargetFingerprintV2.length == 0 &&
                ((![self.iosIntentOperationModeV2
                       isEqualToString:@"standard"] &&
                  MixroomIOSSystemSelectedTargetMatchesSource(
                      self.iosRecordingOutputV2, route)) ||
                 ([self.iosIntentOperationModeV2
                       isEqualToString:@"standard"] &&
                  MixroomIOSRouteIsBluetoothHFPDuplex(route)))) {
                self.iosIntentOperationPendingFingerprintV2 =
                    completeFingerprint;
                [self signalIOSIntentRouteConditionV2];
                self.iosLastObservedRouteCauseV2 = routeNotification
                    ? MixroomIOSObservedRouteCause(reason)
                    : @"appBecameActive";
                return;
            }
            [JuceBridge markIOSIntentRouteInvalidatedV2ObjC];
            self.iosIntentOperationCancelledV2 = YES;
            self.iosIntentTerminalCauseV2 = terminalRouteNotification
                ? MixroomIOSObservedRouteCause(reason)
                : @"unrelatedRoute";
            [self signalIOSIntentRouteConditionV2];
        }
        if (!interruptionNotification && !foregroundRecovery &&
            !terminalRouteNotification &&
            !self.iosIntentOperationActiveV2 &&
            [fingerprint isEqualToString:self.audioRouteFingerprintV2]) {
            return;
        }
        const BOOL transportWasPlaying =
            [JuceBridge pausePlaybackForRouteChangeV2ObjC];
        self.routeTransitionWasPlayingV2 =
            self.routeTransitionWasPlayingV2 || transportWasPlaying;
        self.routeTransitionFromBluetoothV2 =
            self.routeTransitionFromBluetoothV2 ||
            self.iosObservedOutputWasBluetoothV2;
        self.audioRouteGenerationV2 += 1;
        self.audioRouteFingerprintV2 = fingerprint;
        NSDictionary<NSString *, id> *output = route == nil
            ? nil : MixroomIOSSingleOutputEndpoint(route);
        self.iosObservedOutputWasBluetoothV2 =
            output != nil && MixroomIOSOutputIsBluetooth(output);
        self.iosLastObservedRouteCauseV2 =
            (interruptionNotification || foregroundRecovery)
            ? (interruptionCause ?: @"audioInterruptionBegan")
            : (routeNotification
                ? MixroomIOSObservedRouteCause(reason)
                : @"appBecameActive");
        if (self.eventSink != nil) {
            self.eventSink(@{
                @"event": @"audioRouteChangedV2",
                @"generation": @(self.audioRouteGenerationV2),
                @"cause": self.iosLastObservedRouteCauseV2 ?: @"unknown",
                @"fingerprint": fingerprint ?: @"",
                @"transportWasPlaying": @(self.routeTransitionWasPlayingV2),
                @"snapshot": [self buildAudioRouteSnapshotV2],
            });
        }
    };
    if ([NSThread isMainThread]) {
        observe();
    } else {
        dispatch_async(dispatch_get_main_queue(), observe);
    }
}
#endif

- (NSDictionary<NSString *, id> *)startAudioRouteMonitoringV2 {
#if TARGET_OS_OSX
    if (![[JuceBridge getAudioRouteImplementationObjC] isEqualToString:@"v2"]) {
        return @{
            @"captureConsistency": @"unavailable",
            @"unavailableReasons": @{
                @"coordinator": @"implementation_conflict",
            },
        };
    }
    if (!self.audioRouteMonitoringV2) {
        self.audioRouteGenerationV2 = 0;
        self.audioRouteTransitionIdV2 = 0;
        self.routeTransitionWasPlayingV2 = NO;
        self.macIntentOperationActiveV2 = NO;
        self.macIntentOperationCancelledV2 = NO;
        self.macIntentCleanupClaimedV2 = NO;
        self.macLifecycleTransitionActiveV2 = NO;
        self.macLifecycleReconcilePendingV2 = NO;
        self.macIntentRecoveryPendingV2 = NO;
        self.macIntentListenersInstalledV2 = NO;
        self.macIntentOperationModeV2 = @"standard";
        self.macIntentLifecyclePhaseV2 = @"idle";
        self.macIntentTerminalCauseV2 = nil;
        self.macIntentSourceOutputV2 = nil;
        self.macIntentSourceFingerprintV2 = nil;
        self.macIntentTargetInputV2 = nil;
        self.macIntentTargetOutputV2 = nil;
        self.macIntentVerifiedOutputV2 = nil;
        self.macIntentInputFactsV2 = nil;
        self.macIntentMonitoringTargetRowV2 = -1;
        self.macIntentRouteConditionV2 = nil;
        self.macHardwareSettingsConditionV2 = nil;
        self.macIntentObservedInputDeviceV2 = kAudioObjectUnknown;
        self.macIntentObservedOutputDeviceV2 = kAudioObjectUnknown;
        self.macSelectedOutputUIDV2 = nil;
        self.macSelectedInputUIDV2 = nil;
        self.macIntentFollowsSystemInputV2 = YES;
        self.iosLastDuplexProbeV2 = nil;
        self.audioRouteFingerprintV2 =
            [self currentMacPlaybackOutputFingerprintV2];
        self.audioRouteMonitoringV2 = YES;

        AudioObjectPropertyAddress defaultOutputAddress = {
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioObjectPropertyScopeGlobal,
            kMixroomCoreAudioElement,
        };
        AudioObjectPropertyAddress devicesAddress = {
            kAudioHardwarePropertyDevices,
            kAudioObjectPropertyScopeGlobal,
            kMixroomCoreAudioElement,
        };
        AudioObjectAddPropertyListener(
            kAudioObjectSystemObject,
            &defaultOutputAddress,
            MixroomAudioRoutePropertyListenerV2,
            self);
        AudioObjectAddPropertyListener(
            kAudioObjectSystemObject,
            &devicesAddress,
            MixroomAudioRoutePropertyListenerV2,
            self);
        NSDictionary *observedOutput = [self currentMacPlaybackOutputV2:
            MixroomCoreAudioDeviceInventory() ?: @[]];
        [self updateObservedOutputDeviceV2:observedOutput == nil
            ? kAudioObjectUnknown
            : [observedOutput[@"deviceID"] unsignedIntValue]];
    }
    NSDictionary<NSString *, id> *snapshot = [self buildAudioRouteSnapshotV2];
    NSArray *outputs = [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
        ? snapshot[@"outputs"]
        : @[];
    NSDictionary *actualOutput = outputs.count == 1 ? outputs.firstObject : nil;
    NSArray<NSDictionary<NSString *, id> *> *inventory =
        MixroomCoreAudioDeviceInventory() ?: @[];
    NSDictionary<NSString *, id> *policyOutput =
        [self currentMacPlaybackOutputV2:inventory];
    const BOOL startupRouteMatchesDefault = policyOutput != nil &&
        actualOutput != nil &&
        [actualOutput[@"uid"] isEqualToString:policyOutput[@"uid"]];
    if (!startupRouteMatchesDefault) {
        if (self.eventSink == nil) {
            [self stopAudioRouteMonitoringV2];
            return @{
                @"captureConsistency": @"unavailable",
                @"unavailableReasons": @{
                    @"coordinator": @"eventListenerUnavailable",
                },
            };
        }
        NSString *currentFingerprint =
            [self currentMacPlaybackOutputFingerprintV2];
        self.audioRouteFingerprintV2 = currentFingerprint;
        const BOOL wasPlaying = [JuceBridge quiescePlaybackRouteV2ObjC:NO];
        self.routeTransitionWasPlayingV2 = wasPlaying;
        self.audioRouteGenerationV2 += 1;
        self.eventSink(@{
            @"event": @"audioRouteChangedV2",
            @"generation": @(self.audioRouteGenerationV2),
            @"cause": @"startupOutputChanged",
            @"fingerprint": currentFingerprint ?: @"",
            @"transportWasPlaying": @(wasPlaying),
            @"snapshot": [self buildAudioRouteSnapshotV2],
        });
    }
    return [self buildAudioRouteSnapshotV2];
#else
    if (![self startIOSAudioRouteMonitoringV2]) {
        return @{
            @"captureConsistency": @"unavailable",
            @"unavailableReasons": @{
                @"coordinator": self.eventSink == nil
                    ? @"eventListenerUnavailable"
                    : @"implementation_conflict",
            },
        };
    }
    return [self buildAudioRouteSnapshotV2];
#endif
}

- (void)handleAudioRoutePropertyChangeV2:(NSString *)cause {
#if TARGET_OS_OSX
    if (!self.audioRouteMonitoringV2 ||
        ![[JuceBridge getAudioRouteImplementationObjC] isEqualToString:@"v2"]) {
        return;
    }
    if (self.macIntentOperationActiveV2) {
        NSArray<NSDictionary<NSString *, id> *> *inventory =
            MixroomCoreAudioDeviceInventory() ?: @[];
        NSDictionary *expectedInput = self.macIntentTargetInputV2;
        NSDictionary *expectedOutput = self.macIntentSourceOutputV2;
        NSDictionary *currentInput =
            [self currentMacRecordingInputV2:inventory];
        NSDictionary *currentOutput =
            [self currentMacPlaybackOutputV2:inventory];
        NSDictionary *ownedInput = expectedInput == nil
            ? nil
            : MixroomInputForDeviceID(
                inventory,
                [expectedInput[@"deviceID"] unsignedIntValue]);
        NSDictionary *ownedOutput = expectedOutput == nil
            ? nil : MixroomOutputForUID(inventory, expectedOutput[@"uid"]);
        const BOOL monitoringWasActive =
            [self.macIntentOperationModeV2 isEqualToString:@"systemSelectedMonitoring"];
        NSDictionary *monitoringFacts = monitoringWasActive
            ? ([JuceBridge getMacIndependentInputMonitoringFactsV2ObjC] ?: @{})
            : @{};
        const BOOL monitoringProfileStable = !monitoringWasActive ||
            ([monitoringFacts[@"active"] boolValue] &&
             [monitoringFacts[@"targetRow"] integerValue] ==
                self.macIntentMonitoringTargetRowV2 &&
             [monitoringFacts[@"channelCount"] integerValue] ==
                self.macIntentRecordingChannelCountV2 &&
             fabs([ownedInput[@"sampleRateHz"] doubleValue] -
                  [self.macIntentInputFactsV2[@"sampleRateHz"] doubleValue]) <
                1.0 &&
             [ownedInput[@"bufferFrames"] integerValue] ==
                [self.macIntentInputFactsV2[@"bufferFrames"] integerValue] &&
             [MixroomOutputFingerprint(ownedOutput)
                isEqualToString:self.macIntentSourceFingerprintV2]);
        const BOOL invalidated = expectedInput == nil || expectedOutput == nil ||
            ownedInput == nil || ownedOutput == nil ||
            !MixroomCoreAudioDeviceIsAlive(
                [ownedInput[@"deviceID"] unsignedIntValue]) ||
            !MixroomCoreAudioDeviceIsAlive(
                [ownedOutput[@"deviceID"] unsignedIntValue]) ||
            currentInput == nil || currentOutput == nil ||
            ![currentInput[@"uid"] isEqualToString:expectedInput[@"uid"]] ||
            ![currentOutput[@"uid"] isEqualToString:expectedOutput[@"uid"]] ||
            !monitoringProfileStable;
        if (invalidated) {
            if (self.macSelectedOutputUIDV2.length > 0 &&
                !MixroomMacOutputIdentityIsUsable(inventory, ownedOutput)) {
                self.macSelectedOutputUIDV2 = nil;
            }
            const uint64_t operationID = self.macIntentOperationIdV2;
            const BOOL recordingWasActive =
                [self.currentAudioRouteIntentV2 isEqualToString:@"recording"] ||
                [JuceBridge isMacInputRecordingV2ObjC];
            NSDictionary *sourceOutput = self.macIntentSourceOutputV2;
            NSDictionary *duplexInput = self.macIntentTargetInputV2;
            NSDictionary *duplexOutput = self.macIntentVerifiedOutputV2;
            NSDictionary *inputFacts = self.macIntentInputFactsV2 ?: @{};
            self.macIntentOperationCancelledV2 = YES;
            self.macIntentTerminalCauseV2 = cause ?: @"routeChanged";
            self.macIntentLifecyclePhaseV2 = @"physicalRouteInvalidation";
            self.macIntentRecoveryPendingV2 = YES;
            [JuceBridge cancelMacInputProbeWaitV2ObjC];
            [JuceBridge cancelMacOutputCallbackProofV2ObjC];
            // CoreAudio may deliver concurrent property callbacks for one
            // physical change. Claim the terminal cleanup before enqueueing
            // it so only one callback can finish the operation and emit the
            // coordinator invalidation event.
            if (!self.macLifecycleTransitionActiveV2 &&
                [self claimMacIntentCleanupV2]) {
                self.macLifecycleTransitionActiveV2 = YES;
                dispatch_async(MixroomMacPlaybackStartupQueue(), ^{
                    NSDictionary *captureFacts =
                        [JuceBridge getMacInputCaptureFactsV2ObjC] ?: @{};
                    [JuceBridge disableMacIndependentInputMonitoringV2ObjC];
                    [JuceBridge quiescePlaybackRouteV2ObjC:YES];
                    [JuceBridge discardMacInputRecordingV2ObjC];
                    [JuceBridge stopMacInputProbeV2ObjC];
                    self.iosLastDuplexProbeV2 = @{
                        @"status": @"failed",
                        @"diagnosticCode": @"route_unstable",
                        @"validationStage": @"physicalRouteInvalidation",
                        @"phase": @"complete",
                        @"terminalCause": cause ?: @"routeChanged",
                        @"actualCallbackCount":
                            inputFacts[@"callbackCount"] ?: @0,
                        @"inputCallbackCount":
                            inputFacts[@"callbackCount"] ?: @0,
                        @"captureAttemptedSamples":
                            captureFacts[@"attemptedSamples"] ?: @0,
                        @"captureAcceptedSamples":
                            captureFacts[@"acceptedSamples"] ?: @0,
                        @"captureDroppedSamples":
                            captureFacts[@"droppedSamples"] ?: @0,
                        @"captureInvalidBlockCount":
                            captureFacts[@"invalidBlockCount"] ?: @0,
                        @"captureActive": @NO,
                        @"cleanupOutcome": @"closed",
                        @"selectionMode": @"macOSIndependentInput",
                        @"operationId": @(operationID),
                        @"sourceOutput": sourceOutput == nil
                            ? [NSNull null]
                            : MixroomRouteEndpoint(sourceOutput, NO, NO),
                        @"duplexInput": duplexInput == nil
                            ? [NSNull null]
                            : MixroomRouteEndpoint(
                                duplexInput, YES,
                                MixroomTransportIsBluetooth(
                                    [duplexInput[@"transport"]
                                        unsignedIntValue])),
                        @"duplexOutput": duplexOutput == nil
                            ? [NSNull null]
                            : MixroomRouteEndpoint(
                                duplexOutput, NO,
                                MixroomTransportIsBluetooth(
                                    [duplexInput[@"transport"]
                                        unsignedIntValue])),
                        @"restoredOutput": [NSNull null],
                    };
                    self.currentAudioRouteIntentV2 = @"playbackOnly";
                    [self signalMacIntentRouteConditionV2];
                    [self finishMacIntentOperationV2];
                    [self emitMacIntentRouteInvalidationEventV2:recordingWasActive
                                           monitoringWasActive:monitoringWasActive];
                });
            }
        }
        [self signalMacIntentRouteConditionV2];
        return;
    }
    if (self.macIntentRecoveryPendingV2) {
        self.macLifecycleReconcilePendingV2 = YES;
        return;
    }
    if (self.macLifecycleTransitionActiveV2) {
        self.macLifecycleReconcilePendingV2 = YES;
        [self signalMacHardwareSettingsConditionV2];
        if ([self currentMacPlaybackOutputV2:
                MixroomCoreAudioDeviceInventory() ?: @[]] != nil) {
            [self signalMacIntentRouteConditionV2];
        }
        return;
    }
    NSArray<NSDictionary<NSString *, id> *> *inventory =
        MixroomCoreAudioDeviceInventory() ?: @[];
    if (self.macSelectedInputUIDV2.length > 0) {
        NSDictionary *selectedInput =
            MixroomInputForUID(inventory, self.macSelectedInputUIDV2);
        if (!MixroomMacInputIsUsable(inventory, selectedInput)) {
            self.macSelectedInputUIDV2 = nil;
            if (self.eventSink != nil) {
                self.eventSink(@{
                    @"event": @"macV2InputPreferenceChanged",
                    @"followsSystemInput": @YES,
                });
            }
        }
    }
    if (self.macSelectedOutputUIDV2.length > 0) {
        NSDictionary *selected =
            MixroomOutputForUID(inventory, self.macSelectedOutputUIDV2);
        if (!MixroomMacOutputIdentityIsUsable(inventory, selected)) {
            self.macSelectedOutputUIDV2 = nil;
        } else if (!MixroomMacOutputIsUsable(inventory, selected)) {
            const BOOL wasPlaying =
                [JuceBridge quiescePlaybackRouteV2ObjC:NO];
            self.routeTransitionWasPlayingV2 =
                self.routeTransitionWasPlayingV2 || wasPlaying;
            return;
        }
    }
    NSDictionary *policyOutput = [self currentMacPlaybackOutputV2:inventory];
    NSString *fingerprint = policyOutput == nil
        ? @"missing" : MixroomOutputFingerprint(policyOutput);
    if ([fingerprint isEqualToString:self.audioRouteFingerprintV2]) {
        return;
    }

    const AudioDeviceID previousDevice = self.observedOutputDeviceV2;
    const BOOL removed = previousDevice != kAudioObjectUnknown &&
        (MixroomOutputForDeviceID(inventory, previousDevice) == nil ||
         !MixroomCoreAudioDeviceIsAlive(previousDevice));
    const BOOL wasPlaying =
        [JuceBridge quiescePlaybackRouteV2ObjC:removed];
    self.routeTransitionWasPlayingV2 =
        self.routeTransitionWasPlayingV2 || wasPlaying;
    self.audioRouteGenerationV2 += 1;
    self.audioRouteFingerprintV2 = fingerprint;
    [self updateObservedOutputDeviceV2:policyOutput == nil
        ? kAudioObjectUnknown
        : [policyOutput[@"deviceID"] unsignedIntValue]];

    if (self.eventSink != nil) {
        self.eventSink(@{
            @"event": @"audioRouteChangedV2",
            @"generation": @(self.audioRouteGenerationV2),
            @"cause": cause ?: @"unknown",
            @"fingerprint": fingerprint ?: @"",
            @"transportWasPlaying": @(self.routeTransitionWasPlayingV2),
            @"snapshot": [self buildAudioRouteSnapshotV2],
        });
    }
#else
    #pragma unused(cause)
#endif
}

- (NSDictionary<NSString *, id> *)applyMacHardwarePreferencesV2:
    (NSDictionary *)args
    startedAtMs:(double)startedAtMs
    generation:(uint64_t)generation
    transitionID:(uint64_t)transitionID {
#if TARGET_OS_OSX
    const double requestedRate = [args[@"preferredSampleRateHz"] doubleValue];
    const NSInteger requestedBuffer =
        [args[@"preferredBufferFrames"] integerValue];
    NSDictionary *sourceSnapshot = [self buildAudioRouteSnapshotV2];
    NSArray *sourceEndpoints =
        [sourceSnapshot[@"outputs"] isKindOfClass:[NSArray class]]
            ? sourceSnapshot[@"outputs"] : @[];
    NSDictionary *sourceEndpoint = sourceEndpoints.count == 1
        ? sourceEndpoints.firstObject : nil;
    NSArray *inventory = MixroomCoreAudioDeviceInventory() ?: @[];
    NSDictionary *target = [self currentMacPlaybackOutputV2:inventory];
    NSDictionary *source = sourceEndpoint == nil
        ? nil : MixroomOutputForUID(inventory, sourceEndpoint[@"uid"]);
    NSString *diagnosticCode = @"ok";
    if (!MixroomHardwareSampleRatePreferenceIsSupported(requestedRate) ||
        !MixroomHardwareBufferPreferenceIsSupported(requestedBuffer)) {
        diagnosticCode = @"unsupported_hardware_settings";
    } else if (generation != self.audioRouteGenerationV2) {
        diagnosticCode = @"stale_generation";
    } else if (![sourceSnapshot[@"captureConsistency"]
                    isEqualToString:@"stable"] ||
               ![self.currentAudioRouteIntentV2 ?: @"playbackOnly"
                    isEqualToString:@"playbackOnly"] ||
               self.macIntentOperationActiveV2 ||
               self.macIntentRecoveryPendingV2 ||
               !MixroomMacOutputIsUsable(inventory, target) ||
               source == nil ||
               ![source[@"uid"] isEqualToString:target[@"uid"]]) {
        diagnosticCode = @"route_unstable";
    } else if (!MixroomTransportIsBluetooth(
                   [target[@"transport"] unsignedIntValue]) &&
               !MixroomCoreAudioOutputSupportsHardwareSettings(
                   target, requestedRate, requestedBuffer)) {
        diagnosticCode = @"unsupported_hardware_settings";
    }

    const BOOL bluetoothRoute = target != nil &&
        MixroomTransportIsBluetooth([target[@"transport"] unsignedIntValue]);
    const double effectiveRate = bluetoothRoute
        ? [target[@"sampleRateHz"] doubleValue] : requestedRate;
    const NSInteger effectiveBuffer = bluetoothRoute
        ? [target[@"bufferFrames"] integerValue] : requestedBuffer;
    const BOOL alreadyApplied = [diagnosticCode isEqualToString:@"ok"] &&
        fabs([target[@"sampleRateHz"] doubleValue] - effectiveRate) < 1.0 &&
        [target[@"bufferFrames"] integerValue] == effectiveBuffer &&
        MixroomMacPlaybackSnapshotHasVerifiedClock(sourceSnapshot, target);

    NSDictionary *snapshot = sourceSnapshot;
    BOOL success = NO;
    BOOL sourceRestored = NO;
    BOOL routeReconfigured = NO;
    BOOL routeMutationStarted = NO;
    const BOOL transportWasPlaying = [JuceBridge isTransportPlayingObjC];
    if ([diagnosticCode isEqualToString:@"ok"] && alreadyApplied) {
        success = YES;
    } else if ([diagnosticCode isEqualToString:@"ok"]) {
        const double deadlineMs = startedAtMs + 2000.0;
        routeMutationStarted = YES;
        BOOL hardwareSettled = YES;
        if (!bluetoothRoute) {
            [JuceBridge quiescePlaybackRouteV2ObjC:YES];
            hardwareSettled = [self settleMacOutputHardwareSettingsV2:target
                sampleRate:effectiveRate
                bufferFrames:effectiveBuffer
                generation:generation
                deadlineMs:deadlineMs
                diagnosticCode:&diagnosticCode];
        }
        if (hardwareSettled) {
            [JuceBridge beginMacOutputCallbackProofV2ObjC];
        }
        const BOOL opened = hardwareSettled && [JuceBridge
            reconfigureMacPlaybackRouteV2ObjC:target[@"name"]
            sampleRate:effectiveRate
            bufferFrames:effectiveBuffer];
        routeReconfigured = opened;
        const NSInteger remainingMs = MAX(
            0, (NSInteger)(deadlineMs - MixroomMonotonicMilliseconds()));
        const BOOL callbackReady = opened && remainingMs > 0 &&
            [JuceBridge waitForMacOutputCallbackProofV2ObjC:remainingMs];
        NSArray *settledInventory = MixroomCoreAudioDeviceInventory() ?: @[];
        NSDictionary *settled = MixroomOutputForUID(
            settledInventory, target[@"uid"]);
        NSDictionary *settledPolicyOutput =
            [self currentMacPlaybackOutputV2:settledInventory];
        snapshot = [self buildAudioRouteSnapshotV2];
        const BOOL settledPreferenceSupported = bluetoothRoute ||
            (MixroomHardwareSampleRatePreferenceIsSupported(
                [settled[@"sampleRateHz"] doubleValue]) &&
             MixroomHardwareBufferPreferenceIsSupported(
                [settled[@"bufferFrames"] integerValue]));
        success = generation == self.audioRouteGenerationV2 &&
            callbackReady && settledPreferenceSupported &&
            MixroomMacOutputIsUsable(settledInventory, settled) &&
            [settled[@"uid"] isEqualToString:target[@"uid"]] &&
            [settledPolicyOutput[@"uid"] isEqualToString:target[@"uid"]] &&
            MixroomMacPlaybackSnapshotMatchesPlan(
                snapshot,
                settled,
                [JuceBridge getMacOutputCallbackProofSampleRateV2ObjC]
                    .doubleValue,
                [JuceBridge getMacOutputCallbackProofFramesV2ObjC]
                    .integerValue,
                [JuceBridge getMacOutputCallbackProofCountV2ObjC]
                    .unsignedLongLongValue);
        if (!success) {
            if ([diagnosticCode isEqualToString:@"ok"]) {
                diagnosticCode = generation == self.audioRouteGenerationV2
                    ? @"actual_state_unavailable" : @"stale_generation";
            }
        } else {
            target = settled;
        }
    }

    if (success && routeReconfigured && transportWasPlaying &&
        ![JuceBridge playObjC]) {
        success = NO;
        diagnosticCode = @"actual_state_unavailable";
    }

    if (!success &&
        routeMutationStarted &&
        ![diagnosticCode isEqualToString:@"stale_generation"] &&
        source != nil) {
        NSArray *restoreInventory = MixroomCoreAudioDeviceInventory() ?: @[];
        NSDictionary *presentSource = MixroomOutputForUID(
            restoreInventory, source[@"uid"]);
        if (MixroomMacOutputIdentityIsUsable(restoreInventory, presentSource)) {
            [JuceBridge quiescePlaybackRouteV2ObjC:YES];
            NSString *restoreDiagnosticCode = @"ok";
            const double restoreDeadlineMs =
                MixroomMonotonicMilliseconds() + 2000.0;
            const BOOL restoreSettled =
                [self settleMacOutputHardwareSettingsV2:presentSource
                    sampleRate:[source[@"sampleRateHz"] doubleValue]
                    bufferFrames:[source[@"bufferFrames"] integerValue]
                    generation:generation
                    deadlineMs:restoreDeadlineMs
                    diagnosticCode:&restoreDiagnosticCode];
            NSArray *settledRestorePlanInventory =
                MixroomCoreAudioDeviceInventory() ?: @[];
            NSDictionary *settledRestorePlan = MixroomOutputForUID(
                settledRestorePlanInventory, source[@"uid"]);
            if (restoreSettled) {
                [JuceBridge beginMacOutputCallbackProofV2ObjC];
            }
            const BOOL restored = restoreSettled && [JuceBridge
                reconfigureMacPlaybackRouteV2ObjC:settledRestorePlan[@"name"]
                sampleRate:[source[@"sampleRateHz"] doubleValue]
                bufferFrames:[source[@"bufferFrames"] integerValue]];
            const BOOL restoreCallbackReady = restored &&
                [JuceBridge waitForMacOutputCallbackProofV2ObjC:MAX(
                    0, (NSInteger)(restoreDeadlineMs -
                        MixroomMonotonicMilliseconds()))];
            NSArray *settledRestoreInventory =
                MixroomCoreAudioDeviceInventory() ?: @[];
            NSDictionary *settledSource = MixroomOutputForUID(
                settledRestoreInventory, source[@"uid"]);
            snapshot = [self buildAudioRouteSnapshotV2];
            sourceRestored = restoreCallbackReady &&
                fabs([settledSource[@"sampleRateHz"] doubleValue] -
                     [source[@"sampleRateHz"] doubleValue]) < 1.0 &&
                [settledSource[@"bufferFrames"] integerValue] ==
                    [source[@"bufferFrames"] integerValue] &&
                MixroomMacPlaybackSnapshotMatchesPlan(
                    snapshot,
                    settledSource,
                    [JuceBridge getMacOutputCallbackProofSampleRateV2ObjC]
                        .doubleValue,
                    [JuceBridge getMacOutputCallbackProofFramesV2ObjC]
                        .integerValue,
                    [JuceBridge getMacOutputCallbackProofCountV2ObjC]
                        .unsignedLongLongValue);
            if (sourceRestored && transportWasPlaying) {
                [JuceBridge playObjC];
            }
            if (sourceRestored) {
                self.audioRouteFingerprintV2 =
                    MixroomOutputFingerprint(settledSource);
                [self updateObservedOutputDeviceV2:
                    [settledSource[@"deviceID"] unsignedIntValue]];
            }
        }
    }
    if (!success && routeMutationStarted && !sourceRestored &&
        ![diagnosticCode isEqualToString:@"stale_generation"]) {
        [JuceBridge quiescePlaybackRouteV2ObjC:YES];
        snapshot = [self buildAudioRouteSnapshotV2];
    }
    if (success) {
        self.preferredPlaybackSampleRateV2 = bluetoothRoute
            ? requestedRate : [target[@"sampleRateHz"] doubleValue];
        self.preferredPlaybackBufferFramesV2 = bluetoothRoute
            ? requestedBuffer : [target[@"bufferFrames"] integerValue];
        self.audioRouteFingerprintV2 = MixroomOutputFingerprint(target);
        [self updateObservedOutputDeviceV2:
            [target[@"deviceID"] unsignedIntValue]];
    }
    return @{
        @"status": success ? @"success" : @"failure",
        @"generation": @(generation),
        @"transitionId": @(transitionID),
        @"diagnosticCode": diagnosticCode,
        @"elapsedMs": @((NSInteger)(
            MixroomMonotonicMilliseconds() - startedAtMs + 0.5)),
        @"transportWasPlaying": @(transportWasPlaying),
        @"snapshot": snapshot,
    };
#else
    #pragma unused(args, startedAtMs, generation, transitionID)
    return @{};
#endif
}

- (NSDictionary<NSString *, id> *)applyIOSHardwarePreferencesV2:
    (NSDictionary *)args
    startedAtMs:(double)startedAtMs
    generation:(uint64_t)generation
    transitionID:(uint64_t)transitionID {
#if !TARGET_OS_OSX
    const double requestedRate = [args[@"preferredSampleRateHz"] doubleValue];
    const NSInteger requestedBuffer =
        [args[@"preferredBufferFrames"] integerValue];
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSDictionary *sourceOutput =
        MixroomIOSSingleOutputEndpoint(session.currentRoute);
    NSDictionary *sourceSnapshot = [self buildAudioRouteSnapshotV2];
    NSString *diagnosticCode = @"ok";
    if (!MixroomHardwareSampleRatePreferenceIsSupported(requestedRate) ||
        !MixroomHardwareBufferPreferenceIsSupported(requestedBuffer)) {
        diagnosticCode = @"unsupported_hardware_settings";
    } else if (generation != self.audioRouteGenerationV2) {
        diagnosticCode = @"stale_generation";
    } else if (![sourceSnapshot[@"captureConsistency"]
                    isEqualToString:@"stable"] ||
               ![self.currentAudioRouteIntentV2 ?: @"playbackOnly"
                    isEqualToString:@"playbackOnly"] ||
               self.iosIntentOperationActiveV2 || sourceOutput == nil ||
               !MixroomIOSOutputIdentityIsObservable(sourceOutput) ||
               MixroomIOSOutputIsBluetoothDuplex(sourceOutput)) {
        diagnosticCode = @"route_unstable";
    }

    const BOOL bluetoothRoute =
        sourceOutput != nil && MixroomIOSOutputIsBluetooth(sourceOutput);
    const double sourceRate = session.sampleRate;
    const NSInteger sourceBuffer = MixroomIOSSessionBufferFrames(session);
    const double effectiveRate = bluetoothRoute ? sourceRate : requestedRate;
    const NSInteger effectiveBuffer = bluetoothRoute
        ? sourceBuffer : requestedBuffer;
    NSDictionary *sourceJuce =
        [sourceSnapshot[@"juce"] isKindOfClass:[NSDictionary class]]
            ? sourceSnapshot[@"juce"] : @{};
    const BOOL alreadyApplied = [diagnosticCode isEqualToString:@"ok"] &&
        fabs(sourceRate - effectiveRate) < 1.0 &&
        sourceBuffer == effectiveBuffer &&
        MixroomIOSPlaybackSnapshotMatchesClock(
            sourceSnapshot,
            sourceOutput,
            [sourceJuce[@"sampleRateHz"] doubleValue],
            [sourceJuce[@"bufferFrames"] integerValue],
            [sourceJuce[@"realtimeCallbackCount"] unsignedLongLongValue]);

    NSDictionary *snapshot = sourceSnapshot;
    BOOL success = NO;
    BOOL sourceRestored = NO;
    BOOL routeReconfigured = NO;
    const BOOL transportWasPlaying = [JuceBridge isTransportPlayingObjC];
    if ([diagnosticCode isEqualToString:@"ok"] && alreadyApplied) {
        success = YES;
    } else if ([diagnosticCode isEqualToString:@"ok"]) {
        [JuceBridge beginOutputCallbackProofV2ObjC];
        const BOOL opened = [JuceBridge
            reconfigurePlaybackRouteV2ObjC:@""
            sampleRate:effectiveRate
            bufferFrames:effectiveBuffer];
        routeReconfigured = opened;
        const BOOL callbackReady = opened &&
            [JuceBridge waitForOutputCallbackProofV2ObjC:2000];
        NSDictionary *settledOutput =
            MixroomIOSSingleOutputEndpoint(session.currentRoute);
        snapshot = [self buildAudioRouteSnapshotV2];
        const double settledRate = session.sampleRate;
        const NSInteger settledBuffer = MixroomIOSSessionBufferFrames(session);
        const BOOL settledPreferenceSupported = bluetoothRoute ||
            (MixroomHardwareSampleRatePreferenceIsSupported(settledRate) &&
             MixroomHardwareBufferPreferenceIsSupported(settledBuffer));
        success = generation == self.audioRouteGenerationV2 && callbackReady &&
            settledPreferenceSupported &&
            MixroomIOSOutputIdentitiesMatch(sourceOutput, settledOutput) &&
            MixroomIOSPlaybackSnapshotMatchesClock(
                snapshot,
                sourceOutput,
                [JuceBridge getOutputCallbackProofSampleRateV2ObjC]
                    .doubleValue,
                [JuceBridge getOutputCallbackProofFramesV2ObjC]
                    .integerValue,
                [JuceBridge getOutputCallbackProofCountV2ObjC]
                    .unsignedLongLongValue);
        if (!success) {
            diagnosticCode = generation == self.audioRouteGenerationV2
                ? @"actual_state_unavailable" : @"stale_generation";
        }
    }

    if (success && routeReconfigured && transportWasPlaying &&
        ![JuceBridge playObjC]) {
        success = NO;
        diagnosticCode = @"actual_state_unavailable";
    }

    NSDictionary *currentOutput =
        MixroomIOSSingleOutputEndpoint(session.currentRoute);
    if (!success &&
        ![diagnosticCode isEqualToString:@"stale_generation"] &&
        MixroomIOSOutputIdentitiesMatch(sourceOutput, currentOutput) &&
        sourceRate > 1000.0 && sourceBuffer > 0) {
        [JuceBridge beginOutputCallbackProofV2ObjC];
        const BOOL restored = [JuceBridge
            reconfigurePlaybackRouteV2ObjC:@""
            sampleRate:sourceRate
            bufferFrames:sourceBuffer];
        const BOOL restoreCallbackReady = restored &&
            [JuceBridge waitForOutputCallbackProofV2ObjC:2000];
        snapshot = [self buildAudioRouteSnapshotV2];
        sourceRestored = restoreCallbackReady &&
            MixroomIOSOutputIdentitiesMatch(
                sourceOutput,
                MixroomIOSSingleOutputEndpoint(session.currentRoute)) &&
            MixroomIOSPlaybackSnapshotMatchesClock(
                snapshot,
                sourceOutput,
                [JuceBridge getOutputCallbackProofSampleRateV2ObjC]
                    .doubleValue,
                [JuceBridge getOutputCallbackProofFramesV2ObjC]
                    .integerValue,
                [JuceBridge getOutputCallbackProofCountV2ObjC]
                    .unsignedLongLongValue);
        if (sourceRestored && transportWasPlaying) {
            [JuceBridge playObjC];
        }
    }
    if (!success && !sourceRestored &&
        ![diagnosticCode isEqualToString:@"stale_generation"]) {
        [JuceBridge quiescePlaybackRouteV2ObjC:YES];
        snapshot = [self buildAudioRouteSnapshotV2];
    }
    if (success) {
        self.preferredPlaybackSampleRateV2 = bluetoothRoute
            ? requestedRate : session.sampleRate;
        self.preferredPlaybackBufferFramesV2 = bluetoothRoute
            ? requestedBuffer : MixroomIOSSessionBufferFrames(session);
        self.audioRouteFingerprintV2 =
            MixroomIOSOutputFingerprint(session.currentRoute);
        self.iosVerifiedPlaybackOutputFingerprintV2 =
            self.audioRouteFingerprintV2;
        self.iosVerifiedPlaybackOutputWasBluetoothV2 = bluetoothRoute;
    }
    return @{
        @"status": success ? @"success" : @"failure",
        @"generation": @(generation),
        @"transitionId": @(transitionID),
        @"diagnosticCode": diagnosticCode,
        @"elapsedMs": @((NSInteger)(
            MixroomIOSMonotonicMilliseconds() - startedAtMs + 0.5)),
        @"transportWasPlaying": @(transportWasPlaying),
        @"snapshot": snapshot,
    };
#else
    #pragma unused(args, startedAtMs, generation, transitionID)
    return @{};
#endif
}

- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:(NSDictionary *)args {
#if TARGET_OS_OSX
    const double startedAtMs = MixroomMonotonicMilliseconds();
    const uint64_t generation = [args[@"generation"] unsignedLongLongValue];
    const BOOL transportWasPlaying = self.routeTransitionWasPlayingV2;
    self.audioRouteTransitionIdV2 += 1;
    const uint64_t transitionID = self.audioRouteTransitionIdV2;
    if (!self.audioRouteMonitoringV2) {
        return @{
            @"status": @"failure",
            @"generation": @(generation),
            @"transitionId": @(transitionID),
            @"diagnosticCode": @"coordinator_disposed",
            @"elapsedMs": @0,
            @"transportWasPlaying": @NO,
            @"snapshot": [self buildAudioRouteSnapshotV2],
        };
    }
    if (generation != self.audioRouteGenerationV2) {
        return @{
            @"status": @"failure",
            @"generation": @(generation),
            @"transitionId": @(transitionID),
            @"diagnosticCode": @"stale_generation",
            @"elapsedMs": @0,
            @"transportWasPlaying": @(transportWasPlaying),
            @"snapshot": [self buildAudioRouteSnapshotV2],
        };
    }
    if ([args[@"updateHardwarePreferences"] boolValue]) {
        return [self applyMacHardwarePreferencesV2:args
            startedAtMs:startedAtMs
            generation:generation
            transitionID:transitionID];
    }

    NSArray<NSDictionary<NSString *, id> *> *inventory =
        MixroomCoreAudioDeviceInventory() ?: @[];
    const BOOL updateInputPreference =
        [args[@"updateInputPreference"] boolValue];
    const BOOL followSystemInput = [args[@"followSystemInput"] boolValue];
    NSString *requestedInputName =
        [args[@"inputDeviceName"] isKindOfClass:[NSString class]]
            ? [args[@"inputDeviceName"]
                stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]]
            : @"";
    NSString *requestedInputUID =
        [args[@"inputDeviceUID"] isKindOfClass:[NSString class]]
            ? [args[@"inputDeviceUID"]
                stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]]
            : @"";
    NSString *requestedName =
        [args[@"outputDeviceName"] isKindOfClass:[NSString class]]
            ? [args[@"outputDeviceName"]
                stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]]
            : @"";

    if (updateInputPreference) {
        NSDictionary *snapshot = [self buildAudioRouteSnapshotV2];
        NSDictionary *juce =
            [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
                ? snapshot[@"juce"] : @{};
        NSArray *outputs =
            [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
                ? snapshot[@"outputs"] : @[];
        NSDictionary *policyOutput = [self currentMacPlaybackOutputV2:inventory];
        NSDictionary *actualOutput = outputs.count == 1
            ? outputs.firstObject : nil;
        const BOOL explicitInputUID = requestedInputUID.length > 0;
        const BOOL explicitInputName = requestedInputName.length > 0;
        const BOOL explicitInputSelection =
            explicitInputUID || explicitInputName;
        NSArray *inputMatches = !explicitInputUID && explicitInputName
            ? MixroomExactDeviceMatches(inventory, requestedInputName, YES)
            : @[];
        NSDictionary *selectedInput = explicitInputUID
            ? MixroomInputForUID(inventory, requestedInputUID)
            : (inputMatches.count == 1 ? inputMatches.firstObject : nil);
        NSString *diagnosticCode = @"ok";
        if (generation != self.audioRouteGenerationV2) {
            diagnosticCode = @"stale_generation";
        } else if (![snapshot[@"captureConsistency"] ?: @""
                isEqualToString:@"stable"] ||
            ![self.currentAudioRouteIntentV2 ?: @"playbackOnly"
                isEqualToString:@"playbackOnly"] ||
            self.macIntentOperationActiveV2 ||
            self.macIntentRecoveryPendingV2) {
            diagnosticCode = @"route_unstable";
        } else if (followSystemInput == explicitInputSelection) {
            diagnosticCode = @"input_selection_unavailable";
        } else if (!followSystemInput &&
                   ((!explicitInputUID && inputMatches.count != 1) ||
                    !MixroomMacInputIsUsable(inventory, selectedInput))) {
            diagnosticCode = @"input_selection_unavailable";
        } else if (policyOutput == nil || actualOutput == nil ||
                   ![actualOutput[@"uid"] isEqualToString:policyOutput[@"uid"]] ||
                   ![juce[@"deviceOpen"] boolValue] ||
                   ![juce[@"audioCallbackAttached"] boolValue] ||
                   [juce[@"activeInputChannels"] integerValue] != 0 ||
                   [juce[@"activeOutputChannels"] integerValue] <= 0 ||
                   fabs([juce[@"sampleRateHz"] doubleValue] -
                        [policyOutput[@"sampleRateHz"] doubleValue]) >= 1.0 ||
                   [juce[@"bufferFrames"] integerValue] !=
                        [policyOutput[@"bufferFrames"] integerValue]) {
            diagnosticCode = @"actual_state_unavailable";
        }

        const BOOL selectionSucceeded =
            [diagnosticCode isEqualToString:@"ok"];
        if (selectionSucceeded) {
            self.macSelectedInputUIDV2 = followSystemInput
                ? nil : selectedInput[@"uid"];
        }
        const NSInteger elapsedMs = (NSInteger)(
            MixroomMonotonicMilliseconds() - startedAtMs + 0.5);
        return @{
            @"status": selectionSucceeded ? @"success" : @"failure",
            @"generation": @(generation),
            @"transitionId": @(transitionID),
            @"diagnosticCode": diagnosticCode,
            @"elapsedMs": @(elapsedMs),
            @"transportWasPlaying": @NO,
            @"snapshot": snapshot,
        };
    }

    const BOOL explicitSelection = requestedName.length > 0;
    NSDictionary<NSString *, id> *sourceSnapshot =
        [self buildAudioRouteSnapshotV2];
    NSArray *sourceEndpoints =
        [sourceSnapshot[@"outputs"] isKindOfClass:[NSArray class]]
            ? sourceSnapshot[@"outputs"] : @[];
    NSDictionary *sourceEndpoint = sourceEndpoints.count == 1
        ? sourceEndpoints.firstObject : nil;
    NSDictionary *source = sourceEndpoint == nil
        ? nil : MixroomOutputForUID(inventory, sourceEndpoint[@"uid"]);

    if (self.macSelectedOutputUIDV2.length > 0) {
        NSDictionary *selected =
            MixroomOutputForUID(inventory, self.macSelectedOutputUIDV2);
        if (!MixroomMacOutputIdentityIsUsable(inventory, selected)) {
            self.macSelectedOutputUIDV2 = nil;
        }
    }
    NSArray *requestedMatches = explicitSelection
        ? MixroomExactDeviceMatches(inventory, requestedName, NO)
        : @[];
    NSDictionary<NSString *, id> *target = explicitSelection
        ? (requestedMatches.count == 1 ? requestedMatches.firstObject : nil)
        : [self currentMacPlaybackOutputV2:inventory];
    const BOOL targetUsable = MixroomMacOutputIsUsable(inventory, target);
    const double deadlineMs = startedAtMs + 2000.0;
    NSDictionary *targetPlan = MixroomMacPlaybackOpenPlan(
        target,
        self.preferredPlaybackSampleRateV2,
        self.preferredPlaybackBufferFramesV2);
    if (targetUsable) {
        [JuceBridge beginMacOutputCallbackProofV2ObjC];
    }
    const BOOL opened = targetUsable &&
        [JuceBridge
            reconfigureMacPlaybackRouteV2ObjC:target[@"name"]
            sampleRate:[targetPlan[@"sampleRateHz"] doubleValue]
            bufferFrames:[targetPlan[@"bufferFrames"] integerValue]];
    const NSInteger callbackRemainingMs = MAX(
        0, (NSInteger)(deadlineMs - MixroomMonotonicMilliseconds()));
    const BOOL callbackReady = opened && callbackRemainingMs > 0 &&
        [JuceBridge waitForMacOutputCallbackProofV2ObjC:callbackRemainingMs];
    const unsigned long long callbackCount =
        [JuceBridge getMacOutputCallbackProofCountV2ObjC]
            .unsignedLongLongValue;
    const NSInteger callbackFrames =
        [JuceBridge getMacOutputCallbackProofFramesV2ObjC].integerValue;
    const double callbackRate =
        [JuceBridge getMacOutputCallbackProofSampleRateV2ObjC].doubleValue;

    NSDictionary<NSString *, id> *snapshot = [self buildAudioRouteSnapshotV2];
    NSDictionary<NSString *, id> *juce =
        [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
            ? snapshot[@"juce"]
            : @{};
    NSArray *outputs = [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
        ? snapshot[@"outputs"]
        : @[];
    NSDictionary *actualOutput = outputs.count == 1 ? outputs.firstObject : nil;
    NSArray *settledInventory = MixroomCoreAudioDeviceInventory() ?: @[];
    NSDictionary *settledTarget = target == nil
        ? nil : MixroomOutputForUID(settledInventory, target[@"uid"]);
    NSString *actualFingerprint = settledTarget == nil
        ? @"missing" : MixroomOutputFingerprint(settledTarget);
    NSString *diagnosticCode = @"ok";
    if (explicitSelection && requestedMatches.count != 1) {
        diagnosticCode = @"output_selection_unavailable";
    } else if (!targetUsable) {
        diagnosticCode = explicitSelection
            ? @"output_selection_unavailable" : @"no_output";
    } else if (generation != self.audioRouteGenerationV2) {
        diagnosticCode = @"stale_generation";
    } else if (settledTarget == nil ||
               ![settledTarget[@"uid"] isEqualToString:target[@"uid"]]) {
        diagnosticCode = @"route_unstable";
    } else if (!opened) {
        diagnosticCode = @"juce_open_failed";
    } else if ([juce[@"activeInputChannels"] integerValue] != 0) {
        diagnosticCode = @"input_open";
    } else if (![juce[@"deviceOpen"] boolValue] ||
               [juce[@"activeOutputChannels"] integerValue] <= 0 ||
               outputs.count != 1) {
        diagnosticCode = @"no_output";
    } else if (!callbackReady ||
               !MixroomMacPlaybackSnapshotMatchesPlan(
                   snapshot, settledTarget, callbackRate, callbackFrames,
                   callbackCount) ||
               ![actualOutput[@"uid"] isEqualToString:target[@"uid"]]) {
        diagnosticCode = @"actual_state_unavailable";
    }

    BOOL success = [diagnosticCode isEqualToString:@"ok"];
    BOOL sourceRestored = NO;
    NSArray<NSDictionary<NSString *, id> *> *restoreInventory =
        MixroomCoreAudioDeviceInventory() ?: @[];
    NSDictionary *restorableSource = source == nil
        ? nil : MixroomOutputForUID(restoreInventory, source[@"uid"]);
    if (!success && targetUsable &&
        ![diagnosticCode isEqualToString:@"stale_generation"] &&
        MixroomMacOutputIsUsable(restoreInventory, restorableSource)) {
        [JuceBridge beginMacOutputCallbackProofV2ObjC];
        const BOOL sourceOpened = [JuceBridge
            reconfigureMacPlaybackRouteV2ObjC:restorableSource[@"name"]
            sampleRate:[restorableSource[@"sampleRateHz"] doubleValue]
            bufferFrames:[restorableSource[@"bufferFrames"] integerValue]];
        const double restoreDeadlineMs =
            MixroomMonotonicMilliseconds() + 2000.0;
        const NSInteger restoreRemainingMs = MAX(
            0,
            (NSInteger)(restoreDeadlineMs - MixroomMonotonicMilliseconds()));
        const BOOL sourceCallbackReady = sourceOpened &&
            restoreRemainingMs > 0 &&
            [JuceBridge waitForMacOutputCallbackProofV2ObjC:
                restoreRemainingMs];
        snapshot = [self buildAudioRouteSnapshotV2];
        sourceRestored = sourceCallbackReady &&
            MixroomMacPlaybackSnapshotMatchesPlan(
                snapshot,
                restorableSource,
                [JuceBridge getMacOutputCallbackProofSampleRateV2ObjC]
                    .doubleValue,
                [JuceBridge getMacOutputCallbackProofFramesV2ObjC]
                    .integerValue,
                [JuceBridge getMacOutputCallbackProofCountV2ObjC]
                    .unsignedLongLongValue);
        if (sourceRestored) {
            self.audioRouteFingerprintV2 =
                MixroomOutputFingerprint(restorableSource);
            [self updateObservedOutputDeviceV2:
                [restorableSource[@"deviceID"] unsignedIntValue]];
        }
    }
    if (!success && !sourceRestored &&
        ![diagnosticCode isEqualToString:@"stale_generation"] &&
        targetUsable) {
        [JuceBridge quiescePlaybackRouteV2ObjC:YES];
        snapshot = [self buildAudioRouteSnapshotV2];
    } else if ([diagnosticCode isEqualToString:@"stale_generation"]) {
        [JuceBridge quiescePlaybackRouteV2ObjC:NO];
    }
    if (success) {
        if (explicitSelection) {
            self.macSelectedOutputUIDV2 = target[@"uid"];
        }
        self.audioRouteFingerprintV2 = actualFingerprint;
        [self updateObservedOutputDeviceV2:
            [target[@"deviceID"] unsignedIntValue]];
        self.routeTransitionWasPlayingV2 = NO;
    }
    NSDictionary *defaultInput = MixroomInputForDeviceID(
        MixroomCoreAudioDeviceInventory() ?: @[],
        MixroomDefaultCoreAudioInputDevice());
    const BOOL reducedBluetoothQuality = success &&
        [settledTarget[@"transport"] unsignedIntValue] ==
            kAudioDeviceTransportTypeBluetooth &&
        [settledTarget[@"outputChannels"] integerValue] == 1 &&
        [defaultInput[@"transport"] unsignedIntValue] ==
            kAudioDeviceTransportTypeBluetooth;
    const NSInteger elapsedMs = (NSInteger)(
        MixroomMonotonicMilliseconds() - startedAtMs + 0.5);
    return @{
        @"status": success ? @"success" : @"failure",
        @"generation": @(generation),
        @"transitionId": @(transitionID),
        @"diagnosticCode": diagnosticCode,
        @"elapsedMs": @(elapsedMs),
        @"transportWasPlaying": @(transportWasPlaying),
        @"bluetoothCommunicationQualityReduced": @(reducedBluetoothQuality),
        @"snapshot": snapshot,
    };
#else
    const double startedAtMs = MixroomIOSMonotonicMilliseconds();
    const uint64_t generation = [args[@"generation"] unsignedLongLongValue];
    const BOOL transportWasPlaying = self.routeTransitionWasPlayingV2;
    self.audioRouteTransitionIdV2 += 1;
    const uint64_t transitionID = self.audioRouteTransitionIdV2;
    if (!self.audioRouteMonitoringV2) {
        return @{
            @"status": @"failure",
            @"generation": @(generation),
            @"transitionId": @(transitionID),
            @"diagnosticCode": @"coordinator_disposed",
            @"elapsedMs": @0,
            @"transportWasPlaying": @NO,
            @"snapshot": [self buildAudioRouteSnapshotV2],
        };
    }
    if (generation != self.audioRouteGenerationV2) {
        return @{
            @"status": @"failure",
            @"generation": @(generation),
            @"transitionId": @(transitionID),
            @"diagnosticCode": @"stale_generation",
            @"elapsedMs": @0,
            @"transportWasPlaying": @(transportWasPlaying),
            @"snapshot": [self buildAudioRouteSnapshotV2],
        };
    }
    if ([args[@"updateHardwarePreferences"] boolValue]) {
        return [self applyIOSHardwarePreferencesV2:args
            startedAtMs:startedAtMs
            generation:generation
            transitionID:transitionID];
    }

    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSString *eventFingerprint = [self.audioRouteFingerprintV2 copy];
    NSDictionary<NSString *, id> *target =
        MixroomIOSSingleOutputEndpoint(session.currentRoute);
    NSString *expectedFingerprint =
        MixroomIOSOutputFingerprint(session.currentRoute);
    NSString *diagnosticCode = @"ok";
    if (target == nil) {
        diagnosticCode = @"no_output";
    } else if (!MixroomIOSOutputIdentityIsObservable(target)) {
        diagnosticCode = @"actual_state_unavailable";
    } else if (MixroomIOSOutputIsBluetoothDuplex(target)) {
        diagnosticCode = @"bluetooth_duplex_forbidden";
    } else if (eventFingerprint.length == 0 ||
               ![expectedFingerprint isEqualToString:eventFingerprint]) {
        diagnosticCode = @"route_unstable";
    }

    if (generation != self.audioRouteGenerationV2) {
        diagnosticCode = @"stale_generation";
    }

    BOOL routeReopened = NO;
    BOOL routeCallbackReady = NO;
    if ([diagnosticCode isEqualToString:@"ok"]) {
        const double openRate = MixroomIOSPlaybackOpenRate(
            target, session, self.preferredPlaybackSampleRateV2);
        const NSInteger openBuffer = MixroomIOSPlaybackOpenBuffer(
            target, session, self.preferredPlaybackBufferFramesV2);
        [JuceBridge beginOutputCallbackProofV2ObjC];
        routeReopened = [JuceBridge
            reconfigurePlaybackRouteV2ObjC:@""
            sampleRate:openRate
            bufferFrames:openBuffer];
        routeCallbackReady = routeReopened &&
            [JuceBridge waitForOutputCallbackProofV2ObjC:2000];
    }

    NSDictionary<NSString *, id> *snapshot = [self buildAudioRouteSnapshotV2];
    NSDictionary *policyFacts = [JuceBridge getIOSAudioSessionPolicyFactsObjC];
    NSDictionary<NSString *, id> *sessionFacts =
        [snapshot[@"session"] isKindOfClass:[NSDictionary class]]
            ? snapshot[@"session"]
            : @{};
    NSDictionary<NSString *, id> *juce =
        [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
            ? snapshot[@"juce"]
            : @{};
    NSArray *outputs = [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
        ? snapshot[@"outputs"]
        : @[];
    NSDictionary *actualOutput = outputs.count == 1 ? outputs.firstObject : nil;
    NSString *actualFingerprint =
        MixroomIOSOutputFingerprint(session.currentRoute);
    NSString *consistency =
        [snapshot[@"captureConsistency"] isKindOfClass:[NSString class]]
            ? snapshot[@"captureConsistency"]
            : @"unavailable";

    if ([diagnosticCode isEqualToString:@"ok"]) {
        if (generation != self.audioRouteGenerationV2) {
            diagnosticCode = @"stale_generation";
        } else if (!routeReopened || !routeCallbackReady) {
            diagnosticCode = @"actual_state_unavailable";
        } else if (![policyFacts[@"policy"]
                       isEqualToString:@"v2PlaybackOnly"] ||
                   ![policyFacts[@"diagnosticCode"] isEqualToString:@"ok"] ||
                   [policyFacts[@"activationCount"] integerValue] != 1) {
            diagnosticCode = @"actual_state_unavailable";
        } else if (![actualFingerprint isEqualToString:eventFingerprint] ||
                   ![actualFingerprint isEqualToString:expectedFingerprint] ||
                   ![consistency isEqualToString:@"stable"] ||
                   !MixroomIOSOutputIdentitiesMatch(target, actualOutput)) {
            diagnosticCode = @"route_unstable";
        } else if (![sessionFacts[@"category"] isEqual:AVAudioSessionCategoryPlayback] ||
                   ![sessionFacts[@"mode"] isEqual:AVAudioSessionModeDefault]) {
            diagnosticCode = @"actual_state_unavailable";
        } else if ([juce[@"activeInputChannels"] integerValue] != 0 ||
                   [sessionFacts[@"inputChannelCount"] integerValue] != 0) {
            diagnosticCode = @"input_open";
        } else if (![juce[@"deviceOpen"] boolValue] ||
                   ![juce[@"audioCallbackAttached"] boolValue] ||
                   [juce[@"activeOutputChannels"] integerValue] <= 0 ||
                   outputs.count != 1) {
            diagnosticCode = @"no_output";
        } else if ([juce[@"sampleRateHz"] doubleValue] <= 1000.0 ||
                   [juce[@"bufferFrames"] integerValue] <= 0) {
            diagnosticCode = @"actual_state_unavailable";
        } else if (!MixroomIOSPlaybackSnapshotMatchesClock(
                       snapshot,
                       target,
                       [JuceBridge getOutputCallbackProofSampleRateV2ObjC]
                           .doubleValue,
                       [JuceBridge getOutputCallbackProofFramesV2ObjC]
                           .integerValue,
                       [JuceBridge getOutputCallbackProofCountV2ObjC]
                           .unsignedLongLongValue)) {
            diagnosticCode = @"actual_state_unavailable";
        } else if (MixroomIOSOutputIsBluetoothDuplex(actualOutput)) {
            diagnosticCode = @"bluetooth_duplex_forbidden";
        }
    }

    const BOOL usedFallback = [diagnosticCode isEqualToString:@"ok"] &&
        self.routeTransitionFromBluetoothV2 &&
        [actualOutput[@"normalizedKind"] isEqualToString:@"builtIn"];
    if (usedFallback) {
        diagnosticCode = @"fallback_succeeded";
    }
    const BOOL success = [diagnosticCode isEqualToString:@"ok"] ||
        [diagnosticCode isEqualToString:@"fallback_succeeded"];
    if (success) {
        self.routeTransitionWasPlayingV2 = NO;
        self.routeTransitionFromBluetoothV2 = NO;
        self.audioRouteFingerprintV2 = actualFingerprint;
        self.iosObservedOutputWasBluetoothV2 =
            MixroomIOSOutputIsBluetooth(actualOutput);
        self.iosVerifiedPlaybackOutputFingerprintV2 = actualFingerprint;
        self.iosVerifiedPlaybackOutputWasBluetoothV2 =
            MixroomIOSOutputIsBluetooth(actualOutput);
    }
    const NSInteger elapsedMs = (NSInteger)(
        MixroomIOSMonotonicMilliseconds() - startedAtMs + 0.5);
    return @{
        @"status": success ? (usedFallback ? @"fallback" : @"success") : @"failure",
        @"generation": @(generation),
        @"transitionId": @(transitionID),
        @"diagnosticCode": diagnosticCode,
        @"elapsedMs": @(elapsedMs),
        @"transportWasPlaying": @(transportWasPlaying),
        @"snapshot": snapshot,
    };
#endif
}

- (void)stopAudioRouteMonitoringV2 {
#if TARGET_OS_OSX
    if (!self.audioRouteMonitoringV2) {
        return;
    }
    const BOOL operationWasActive = self.macIntentOperationActiveV2;
    if (operationWasActive) {
        self.macIntentOperationCancelledV2 = YES;
        self.macIntentTerminalCauseV2 = @"shutdown";
        [JuceBridge cancelMacInputProbeWaitV2ObjC];
        [JuceBridge cancelMacOutputCallbackProofV2ObjC];
        [self signalMacIntentRouteConditionV2];
    }
    self.audioRouteMonitoringV2 = NO;
    [JuceBridge cancelMacOutputCallbackProofV2ObjC];
    [self signalMacIntentRouteConditionV2];
    [self signalMacHardwareSettingsConditionV2];
    self.audioRouteGenerationV2 += 1;
    AudioObjectPropertyAddress defaultOutputAddress = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    AudioObjectPropertyAddress devicesAddress = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    AudioObjectRemovePropertyListener(
        kAudioObjectSystemObject,
        &defaultOutputAddress,
        MixroomAudioRoutePropertyListenerV2,
        self);
    AudioObjectRemovePropertyListener(
        kAudioObjectSystemObject,
        &devicesAddress,
        MixroomAudioRoutePropertyListenerV2,
        self);
    [self updateObservedOutputDeviceV2:kAudioObjectUnknown];
    self.audioRouteFingerprintV2 = nil;
    self.routeTransitionWasPlayingV2 = NO;
    self.macLifecycleReconcilePendingV2 = NO;
    self.macIntentRecoveryPendingV2 = NO;
    self.macSelectedOutputUIDV2 = nil;
    self.macSelectedInputUIDV2 = nil;
    if (operationWasActive) {
        dispatch_async(MixroomMacPlaybackStartupQueue(), ^{
            if ([self claimMacIntentCleanupV2]) {
                [JuceBridge disableMacIndependentInputMonitoringV2ObjC];
                [JuceBridge quiescePlaybackRouteV2ObjC:YES];
                [JuceBridge discardMacInputRecordingV2ObjC];
                [JuceBridge stopMacInputProbeV2ObjC];
            }
            [self removeMacIntentDeviceListenersV2];
            self.macIntentFollowsSystemInputV2 = YES;
            self.macIntentOperationActiveV2 = NO;
            self.macLifecycleTransitionActiveV2 = NO;
            self.macIntentRouteConditionV2 = nil;
            self.currentAudioRouteIntentV2 = @"playbackOnly";
        });
    } else {
        self.macIntentFollowsSystemInputV2 = YES;
    }
#else
    [self stopIOSAudioRouteMonitoringV2];
#endif
}

- (BOOL)preferNonBluetoothRecordingInput {
#if TARGET_OS_OSX
    return NO;
#else
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;

    AVAudioSessionPortDescription *preferred = nil;
    for (AVAudioSessionPortDescription *input in session.availableInputs) {
        NSString *portType = input.portType ?: @"";
        if ([portType isEqualToString:AVAudioSessionPortBuiltInMic]) {
            preferred = input;
            break;
        }
        if ([portType isEqualToString:AVAudioSessionPortBluetoothHFP] ||
            [portType isEqualToString:AVAudioSessionPortBluetoothLE]) {
            continue;
        }
        if (preferred == nil) {
            preferred = input;
        }
    }

    if (preferred == nil) {
        return NO;
    }

    BOOL ok = [session setPreferredInput:preferred error:&error];
    if (!ok || error != nil) {
        NSLog(@"preferNonBluetoothRecordingInput setPreferredInput failed: %@", error);
        return NO;
    }

    [session overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
    [JuceBridge refreshAudioRouteObjC:@"preferNonBluetoothRecordingInput"];
    return YES;
#endif
}

- (void)restoreBluetoothPlaybackAfterRecordingStop {
#if TARGET_OS_OSX
    [JuceBridge refreshAudioRouteObjC:@"restoreBluetoothPlaybackAfterRecordingStop"];
#else
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;

    [session setPreferredInput:nil error:nil];
    [session overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
    [session setActive:YES error:&error];

    if (error != nil) {
        NSLog(@"restoreBluetoothPlaybackAfterRecordingStop failed: %@", error);
    }

    [JuceBridge refreshAudioRouteObjC:@"restoreBluetoothPlaybackAfterRecordingStop"];
#endif
}


// for printing logs
static JuceAudioEnginePlugin* _sharedInstance = nil;

+ (instancetype)sharedInstance {
    return _sharedInstance;
}

+ (void)shutdownForApplicationTermination {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        JuceAudioEnginePlugin *plugin = [JuceAudioEnginePlugin sharedInstance];
        plugin.applicationTerminationStarted = YES;
#if TARGET_OS_OSX
        plugin.macIntentOperationCancelledV2 = YES;
        [plugin signalMacIntentRouteConditionV2];
        [plugin signalMacHardwareSettingsConditionV2];
#else
        plugin.iosIntentOperationCancelledV2 = YES;
        [plugin signalIOSIntentRouteConditionV2];
#endif
        [plugin stopAudioRouteMonitoringV2];
        [JuceBridge shutdownForApplicationTerminationObjC];
    });
}

+ (void)panicLiveMidiNotesForApplicationDeactivation {
    [JuceBridge panicLiveMidiNotesForApplicationDeactivationObjC];
}

- (BOOL)hasActiveLogListener {
    return self.logSink != nil;
}

- (void)sendFlutterLog:(NSString*)message {
    if (self.logSink) {
        self.logSink(@{ @"message": message });
    }
}

- (void)sendFlutterEvent:(NSDictionary<NSString *, id> *)event {
    if (self.eventSink != nil && event != nil) {
        self.eventSink(event);
    }
}

- (void)bindEventSink:(FlutterEventSink)events {
    self.eventSink = events;
}

- (void)clearEventSink {
    self.eventSink = nil;
}

- (void)dealloc {
#if !TARGET_OS_OSX
    [_iosCaptureV2 release];
#endif
    [self stopAudioRouteMonitoringV2];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
    NSString *flutterAssetRootPath = MixroomFlutterAssetRootPath();
    if (flutterAssetRootPath.length > 0) {
        [JuceBridge setFlutterAssetRootObjC:flutterAssetRootPath];
        NSLog(@"🎹 Live MIDI flutter asset root: %@", flutterAssetRootPath);
    } else {
        NSLog(@"⚠️ Live MIDI flutter asset root could not be resolved");
    }
    

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
    [[NSNotificationCenter defaultCenter] addObserver:_sharedInstance
                                             selector:@selector(handlePluginLoadedNotification:)
                                                 name:@"MixroomHostedPluginEditorSpacebarNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:_sharedInstance
                                             selector:@selector(handlePluginLoadedNotification:)
                                                 name:@"MixroomHostedPluginEditorAutomationNotification"
                                               object:nil];
#if TARGET_OS_OSX
    NSString *ottAutotest =
        [[[NSProcessInfo processInfo] environment] objectForKey:@"MIXROOM_AUTOTEST_OTT"];
    if ([ottAutotest isEqualToString:@"1"]) {
        mixroomScheduleOttPluginEditorAutotest();
    }
#endif
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

    const BOOL terminationDiagnosticCall =
        [call.method isEqualToString:@"getEngineDiagnostics"];
#if MIXROOM_ENABLE_TEST_HOOKS
    const BOOL terminationTestCall =
        [call.method isEqualToString:@"debugShutdownForApplicationTermination"] ||
        [call.method isEqualToString:@"debugReleaseMidiClipLoadStall"] ||
        [call.method isEqualToString:@"debugGetMidiClipLoadStallState"];
#else
    const BOOL terminationTestCall = NO;
#endif
    if (self.applicationTerminationStarted &&
        !terminationDiagnosticCall && !terminationTestCall) {
        result([FlutterError errorWithCode:@"application_terminating"
                                   message:@"The audio engine is shutting down."
                                   details:nil]);
        return;
    }

    if ([call.method isEqualToString:@"initialise"]) {
        [JuceBridge initialiseEngineObjC];
        result(nil);
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
        result(@([JuceBridge playObjC]));
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
        BOOL forceIndividualRow = [call.arguments[@"forceIndividualRow"] boolValue];
        NSArray* arr = [JuceBridge getTrackPluginParametersObjC:row
                                                    effectIndex:effect
                                             forceIndividualRow:forceIndividualRow];
        result(arr);
    } else if ([call.method isEqualToString:@"getMasterPluginParameters"]) {
        NSInteger effect = [call.arguments[@"effect"] integerValue];
        NSArray* arr = [JuceBridge getMasterPluginParametersObjC:effect];
        result(arr);
    } else if ([call.method isEqualToString:@"scanPlugins"]) {
        NSArray *searchPaths = args[@"searchPaths"];
#if TARGET_OS_OSX
        dispatch_async(MixroomPluginScanQueue(), ^{
            NSArray *plugins = [JuceBridge scanPluginsObjC:searchPaths];
            dispatch_async(dispatch_get_main_queue(), ^{
                result(plugins);
            });
        });
#else
        NSArray* plugins = [JuceBridge scanPluginsObjC:searchPaths];
        result(plugins);
#endif
    } else if ([call.method isEqualToString:@"rescanPlugins"]) {
        NSArray *searchPaths = args[@"searchPaths"];
#if TARGET_OS_OSX
        dispatch_async(MixroomPluginScanQueue(), ^{
            NSArray *plugins = [JuceBridge rescanPluginsObjC:searchPaths];
            dispatch_async(dispatch_get_main_queue(), ^{
                result(plugins);
            });
        });
#else
        NSArray* plugins = [JuceBridge rescanPluginsObjC:searchPaths];
        result(plugins);
#endif
    } else if ([call.method isEqualToString:@"cancelPluginScan"]) {
        [JuceBridge cancelPluginScanObjC];
        result(nil);
    } else if ([call.method isEqualToString:@"getQuarantinedPlugins"]) {
        result([JuceBridge getQuarantinedPluginsObjC]);
    } else if ([call.method isEqualToString:@"isPluginQuarantined"]) {
        NSString *pluginId = args[@"pluginId"] ?: args[@"id"] ?: @"";
        result(@([JuceBridge isPluginQuarantinedObjC:pluginId]));
    } else if ([call.method isEqualToString:@"clearPluginQuarantine"]) {
        NSString *pluginId = args[@"pluginId"] ?: args[@"id"] ?: @"";
        [JuceBridge clearPluginQuarantineObjC:pluginId];
        result(nil);
    } else if ([call.method isEqualToString:@"clearAllPluginQuarantines"]) {
        [JuceBridge clearAllPluginQuarantinesObjC];
        result(nil);
    } else if ([call.method isEqualToString:@"getEngineDiagnostics"]) {
        NSDictionary* diagnostics = [JuceBridge getEngineDiagnosticsObjC];
        result(diagnostics);
    } else if ([call.method isEqualToString:@"resetRealtimePerformanceStats"]) {
        [JuceBridge resetRealtimePerformanceStatsObjC];
        result(nil);
    } else if ([call.method isEqualToString:@"runEngineStressTest"]) {
        NSInteger clipCount = [args[@"clipCount"] respondsToSelector:@selector(integerValue)] ? [args[@"clipCount"] integerValue] : 256;
        NSInteger blockCount = [args[@"blockCount"] respondsToSelector:@selector(integerValue)] ? [args[@"blockCount"] integerValue] : 1024;
        NSInteger blockSize = [args[@"blockSize"] respondsToSelector:@selector(integerValue)] ? [args[@"blockSize"] integerValue] : 512;
        double sampleRate = [args[@"sampleRate"] respondsToSelector:@selector(doubleValue)] ? [args[@"sampleRate"] doubleValue] : 48000.0;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSDictionary *stats = [JuceBridge runEngineStressTestObjC:clipCount
                                                            blockCount:blockCount
                                                             blockSize:blockSize
                                                            sampleRate:sampleRate];
            dispatch_async(dispatch_get_main_queue(), ^{
                result(stats);
            });
        });
    } else if ([call.method isEqualToString:@"getEngineCapabilities"]) {
#if TARGET_OS_OSX
        result(@{
            @"externalPluginHosting": @YES,
            @"supportedPluginFormats": @[@"AU", @"VST3"],
            @"nativePluginEditor": @YES
        });
#else
        result(@{
            @"externalPluginHosting": @NO,
            @"supportedPluginFormats": @[],
            @"nativePluginEditor": @NO
        });
#endif
    } else if ([call.method isEqualToString:@"exportMix"]) {
        NSDictionary *exportArgs = [args copy];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *out = [JuceBridge exportMixObjC:exportArgs[@"outPath"] settings:exportArgs];
            dispatch_async(dispatch_get_main_queue(), ^{
                result(out);
            });
        });
    } else if ([call.method isEqualToString:@"getExportProgress"]) {
        result(@([JuceBridge getExportProgressObjC]));
    } else if ([call.method isEqualToString:@"exportTrack"]) {
        NSDictionary *exportArgs = [args copy];
        NSInteger track = [exportArgs[@"track"] integerValue];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *out = [JuceBridge exportTrackObjC:track outPath:exportArgs[@"outPath"] settings:exportArgs];
            dispatch_async(dispatch_get_main_queue(), ^{
                result(out);
            });
        });
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
    } else if ([call.method isEqualToString:@"renderPitchLabAudio"]) {
        NSDictionary *renderArgs = [args copy];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *out = [JuceBridge renderPitchLabAudioObjC:renderArgs[@"sourcePath"] ?: @""
                                                        outPath:renderArgs[@"outPath"] ?: @""
                                                    trimStartMs:[renderArgs[@"trimStartMs"] doubleValue]
                                                      trimEndMs:[renderArgs[@"trimEndMs"] doubleValue]
                                       sourceTimelineDurationMs:[renderArgs[@"sourceTimelineDurationMs"] doubleValue]
                                               outputDurationMs:[renderArgs[@"outputDurationMs"] doubleValue]
                                               suppressedRanges:renderArgs[@"suppressedRanges"] ?: @[]
                                                       segments:renderArgs[@"segments"] ?: @[]];
            dispatch_async(dispatch_get_main_queue(), ^{
                result(out);
            });
        });
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
        [self stopAudioRouteMonitoringV2];
#if TARGET_OS_OSX
        FlutterResult shutdownResult = [result copy];
        dispatch_async(MixroomMacPlaybackStartupQueue(), ^{
            [JuceBridge discardMacInputRecordingV2ObjC];
            [JuceBridge stopMacInputProbeV2ObjC];
            [JuceBridge shutdownEngineObjC];
            [self restoreBluetoothPlaybackAfterRecordingStop];
            dispatch_async(dispatch_get_main_queue(), ^{
                shutdownResult(nil);
                [shutdownResult release];
            });
        });
#else
        self.iosLifecycleTransitionActiveV2 = YES;
        ++self.iosLifecycleCompletionTokenV2;
        dispatch_async(MixroomIOSLifecycleQueue(), ^{
            const BOOL wasV2 = [[JuceBridge getAudioRouteImplementationObjC]
                isEqualToString:@"v2"];
            [JuceBridge shutdownEngineObjC];
            if (!wasV2) {
                [self restoreBluetoothPlaybackAfterRecordingStop];
                AVAudioSession *session = [AVAudioSession sharedInstance];
                [session setActive:NO error:nil];
            }
            [JuceBridge endIOSIntentOperationV2ObjC];
            self.iosIntentOperationActiveV2 = NO;
            self.iosLifecycleTransitionActiveV2 = NO;
            self.iosIntentLifecyclePhaseV2 = @"idle";
            self.iosIntentRouteConditionV2 = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                result(nil);
            });
        });
#endif

    // ----------------------------------------
    // VIDEO AUDIO LANE
    // ----------------------------------------
    } else if ([call.method isEqualToString:@"loadVideoAudio"]) {
        NSString* path = [args[@"path"] ?: @"" copy];
        FlutterResult videoResult = [result copy];
        dispatch_async(MixroomMidiClipLoadQueue(), ^{
            [JuceBridge loadVideoAudioObjC:path];
            dispatch_async(dispatch_get_main_queue(), ^{
                videoResult(nil);
            });
        });
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
        NSString *instrumentId = [args[@"instrumentId"] ?: @"mixroom.basic_synth" copy];
        NSString *instrumentName = [args[@"instrumentName"] ?: @"Basic Synth" copy];
        NSArray *notes = [args[@"notes"] ?: @[] copy];
        NSDictionary *params = [args[@"params"] ?: @{} copy];
        double sourceTempoBpm = [args[@"sourceTempoBpm"] doubleValue];
        double startSec = [args[@"startSec"] doubleValue];
        double lengthSec = [args[@"lengthSec"] doubleValue];
        double inFileOffsetSec = [args[@"inFileOffsetSec"] doubleValue];
        int64_t loadRequestId = [args[@"loadRequestId"] longLongValue];
        FlutterResult loadResult = [result copy];
        const BOOL builtInInstrument =
            [JuceBridge isBuiltInMidiInstrumentObjC:instrumentId];
        dispatch_queue_t loadQueue = builtInInstrument
            ? MixroomBuiltInMidiClipPreparationQueue()
            : MixroomMidiClipLoadQueue();
        dispatch_async(loadQueue, ^{
#if MIXROOM_ENABLE_TEST_HOOKS
            if (builtInInstrument) {
                MixroomWaitForMidiClipLoadTestStall(loadRequestId);
            }
#endif
            if (self.applicationTerminationStarted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    loadResult(@(NO));
                });
                return;
            }
            BOOL ok = [JuceBridge loadMidiClipObjC:clip
                                             rowId:rowId
                                      instrumentId:instrumentId
                                    instrumentName:instrumentName
                                             notes:notes
                                            params:params
                                    sourceTempoBpm:sourceTempoBpm
                                          startSec:startSec
                                         lengthSec:lengthSec
                                   inFileOffsetSec:inFileOffsetSec
                                     loadRequestId:loadRequestId];
            dispatch_async(dispatch_get_main_queue(), ^{
                loadResult(@(ok));
            });
        });
    } else if ([call.method isEqualToString:@"cancelMidiClipLoad"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        int64_t loadRequestId = [args[@"loadRequestId"] longLongValue];
        result(@([JuceBridge cancelMidiClipLoadObjC:clip
                                             requestId:loadRequestId]));
#if MIXROOM_ENABLE_TEST_HOOKS
    } else if ([call.method isEqualToString:@"debugConfigureMidiClipLoadStall"]) {
        int64_t loadRequestId = [args[@"loadRequestId"] longLongValue];
        result(@(MixroomConfigureMidiClipLoadTestStall(loadRequestId)));
    } else if ([call.method isEqualToString:@"debugGetMidiClipLoadStallState"]) {
        result(MixroomMidiClipLoadTestState());
    } else if ([call.method isEqualToString:@"debugReleaseMidiClipLoadStall"]) {
        int64_t loadRequestId = [args[@"loadRequestId"] longLongValue];
        result(@(MixroomReleaseMidiClipLoadTestStall(loadRequestId)));
    } else if ([call.method isEqualToString:@"debugShutdownForApplicationTermination"]) {
        [JuceAudioEnginePlugin shutdownForApplicationTermination];
        result(nil);
#endif
    } else if ([call.method isEqualToString:@"updateMidiClipEvents"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        NSString *instrumentId = [args[@"instrumentId"] ?: @"mixroom.basic_synth" copy];
        NSString *instrumentName = [args[@"instrumentName"] ?: @"Basic Synth" copy];
        NSArray *notes = [args[@"notes"] ?: @[] copy];
        NSDictionary *params = [args[@"params"] ?: @{} copy];
        double sourceTempoBpm = [args[@"sourceTempoBpm"] doubleValue];
        FlutterResult updateResult = [result copy];
        dispatch_async(MixroomMidiClipLoadQueue(), ^{
            BOOL ok = [JuceBridge updateMidiClipObjC:clip
                                         instrumentId:instrumentId
                                       instrumentName:instrumentName
                                                notes:notes
                                               params:params
                                       sourceTempoBpm:sourceTempoBpm];
            dispatch_async(dispatch_get_main_queue(), ^{
                updateResult(@(ok));
            });
        });
    } else if ([call.method isEqualToString:@"setLiveMidiInputTargetClip"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        result(@([JuceBridge setLiveMidiInputTargetClipObjC:clip]));
    } else if ([call.method isEqualToString:@"setDesktopKeyboardMidiForwardingEnabled"]) {
        BOOL enabled = [args[@"enabled"] boolValue];
        [JuceBridge setDesktopKeyboardMidiForwardingEnabledObjC:enabled];
        result(@(YES));
    } else if ([call.method isEqualToString:@"sendLiveMidiInputEvent"]) {
        BOOL noteOn = [args[@"noteOn"] boolValue];
        NSInteger channel = [args[@"channel"] integerValue];
        NSInteger pitch = [args[@"pitch"] integerValue];
        float velocity = [args[@"velocity"] floatValue];
        result(@([JuceBridge sendLiveMidiInputEventObjC:noteOn
                                                channel:channel
                                                  pitch:pitch
                                               velocity:velocity]));
    } else if ([call.method isEqualToString:@"playPreviewMidiNote"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        NSInteger pitch = [args[@"pitch"] integerValue];
        float velocity = [args[@"velocity"] floatValue];
        NSInteger durationMs = [args[@"durationMs"] integerValue];
        result(@([JuceBridge playPreviewMidiNoteObjC:clip
                                               pitch:pitch
                                            velocity:velocity
                                          durationMs:durationMs]));
    } else if ([call.method isEqualToString:@"openMidiClipPluginEditor"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        result(@([JuceBridge openMidiClipPluginEditorObjC:clip]));
    } else if ([call.method isEqualToString:@"setMidiClipPluginParameter"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        NSString *paramId = args[@"paramId"] ?: @"";
        float value = [args[@"value"] floatValue];
        [JuceBridge setMidiClipPluginParameterObjC:clip
                                           paramId:paramId
                                  normalizedValue:value];
        result(nil);
    } else if ([call.method isEqualToString:@"setMidiClipPluginAutomationPoints"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        NSString *paramId = args[@"paramId"] ?: @"";
        NSArray *points = args[@"points"] ?: @[];
        [JuceBridge setMidiClipPluginAutomationPointsObjC:clip
                                                   paramId:paramId
                                                    points:points];
        result(nil);
    } else if ([call.method isEqualToString:@"clearMidiClipPluginAutomation"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        [JuceBridge clearMidiClipPluginAutomationObjC:clip];
        result(nil);
    } else if ([call.method isEqualToString:@"getMidiClipPluginState"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        result([JuceBridge getMidiClipPluginStateObjC:clip]);
    } else if ([call.method isEqualToString:@"setMidiClipPluginState"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        NSString *stateBase64 = [args[@"stateBase64"] ?: @"" copy];
#if TARGET_OS_OSX
        FlutterResult stateResult = [result copy];
        dispatch_async(MixroomMidiClipLoadQueue(), ^{
            BOOL applied = [JuceBridge setMidiClipPluginStateObjC:clip
                                                      stateBase64:stateBase64];
            dispatch_async(dispatch_get_main_queue(), ^{
                stateResult(@(applied));
            });
        });
#else
        result(@([JuceBridge setMidiClipPluginStateObjC:clip
                                            stateBase64:stateBase64]));
#endif
    } else if ([call.method isEqualToString:@"setHostedPluginWindowsDetached"]) {
        BOOL detached = [args[@"detached"] boolValue];
        [JuceBridge setHostedPluginWindowsDetachedObjC:detached];
        result(nil);
    } else if ([call.method isEqualToString:@"consumeLiveMidiInputEvents"]) {
        result([JuceBridge consumeLiveMidiInputEventsObjC]);
    } else if ([call.method isEqualToString:@"getConnectedMidiInputDevices"]) {
        result([JuceBridge getConnectedMidiInputDevicesObjC]);
    } else if ([call.method isEqualToString:@"beginProjectClipLoad"]) {
#if TARGET_OS_OSX
        FlutterResult beginResult = [result copy];
        dispatch_async(MixroomMidiClipLoadQueue(), ^{
            [JuceBridge beginProjectClipLoadObjC];
            dispatch_async(dispatch_get_main_queue(), ^{
                beginResult(nil);
            });
        });
#else
        [JuceBridge beginProjectClipLoadObjC];
        result(nil);
#endif
    } else if ([call.method isEqualToString:@"endProjectClipLoad"]) {
#if TARGET_OS_OSX
        FlutterResult endResult = [result copy];
        dispatch_async(MixroomMidiClipLoadQueue(), ^{
            [JuceBridge endProjectClipLoadObjC];
            dispatch_async(dispatch_get_main_queue(), ^{
                endResult(nil);
            });
        });
#else
        [JuceBridge endProjectClipLoadObjC];
        result(nil);
#endif
    } else if ([call.method isEqualToString:@"beginGraphMutationBatch"]) {
#if TARGET_OS_OSX
        FlutterResult beginResult = [result copy];
        dispatch_async(MixroomMidiClipLoadQueue(), ^{
            [JuceBridge beginGraphMutationBatchObjC];
            dispatch_async(dispatch_get_main_queue(), ^{
                beginResult(nil);
            });
        });
#else
        [JuceBridge beginGraphMutationBatchObjC];
        result(nil);
#endif
    } else if ([call.method isEqualToString:@"endGraphMutationBatch"]) {
#if TARGET_OS_OSX
        FlutterResult endResult = [result copy];
        dispatch_async(MixroomMidiClipLoadQueue(), ^{
            [JuceBridge endGraphMutationBatchObjC];
            dispatch_async(dispatch_get_main_queue(), ^{
                endResult(nil);
            });
        });
#else
        [JuceBridge endGraphMutationBatchObjC];
        result(nil);
#endif
    } else if ([call.method isEqualToString:@"loadClip"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        NSInteger rowId  = [args[@"rowId"] integerValue];
        if (args[@"row"] != nil) rowId = [args[@"row"] integerValue]; // backward compat
        NSString *path = [args[@"path"] ?: @"" copy];
        double startSec = [args[@"startSec"] doubleValue];
        double lengthSec = [args[@"lengthSec"] doubleValue];
        double inFileOffsetSec = [args[@"inFileOffsetSec"] doubleValue];
        FlutterResult loadResult = [result copy];
        dispatch_async(MixroomMidiClipLoadQueue(), ^{
            BOOL ok = [JuceBridge loadClipObjC:clip
                                         rowId:rowId
                                          path:path
                                      startSec:startSec
                                     lengthSec:lengthSec
                               inFileOffsetSec:inFileOffsetSec];
            dispatch_async(dispatch_get_main_queue(), ^{
                loadResult(@(ok));
            });
        });
    } else if ([call.method isEqualToString:@"unloadClip"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        [JuceBridge unloadClipObjC:clip];
        result(nil);
    } else if ([call.method isEqualToString:@"unloadClips"]) {
        NSArray *clips = [args[@"clips"] isKindOfClass:[NSArray class]] ? args[@"clips"] : @[];
        result(@([JuceBridge unloadClipsObjC:clips]));
    } else if ([call.method isEqualToString:@"setClipGain"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        float gain     = [args[@"gain"] floatValue];
        [JuceBridge setClipGainObjC:clip gain:gain];
        result(nil);
    } else if ([call.method isEqualToString:@"setClipExtraGainLinear"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        float gain     = [args[@"gain"] floatValue];
        [JuceBridge setClipExtraGainLinearObjC:clip gain:gain];
        result(nil);
    } else if ([call.method isEqualToString:@"setClipPan"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        float pan      = [args[@"pan"] floatValue];
        [JuceBridge setClipPanObjC:clip pan:pan];
        result(nil);
    } else if ([call.method isEqualToString:@"setClipFades"]) {
        NSInteger clip = [args[@"clip"] integerValue];
        double fadeInSec = [args[@"fadeInSec"] doubleValue];
        double fadeOutSec = [args[@"fadeOutSec"] doubleValue];
        NSInteger fadeCurve = [args[@"fadeCurve"] integerValue];
        [JuceBridge setClipFadesObjC:clip
                            fadeInSec:fadeInSec
                           fadeOutSec:fadeOutSec
                            fadeCurve:fadeCurve];
        result(nil);
    } else if ([call.method isEqualToString:@"updateClipFadesBatch"]) {
        NSArray *updates = [args[@"updates"] isKindOfClass:[NSArray class]] ? args[@"updates"] : @[];
        result(@([JuceBridge updateClipFadesBatchObjC:updates]));
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
    } else if ([call.method isEqualToString:@"updateClipTimelineBatch"]) {
        NSArray *updates = [args[@"updates"] isKindOfClass:[NSArray class]] ? args[@"updates"] : @[];
        result(@([JuceBridge updateClipTimelineBatchObjC:updates]));
    } else if ([call.method isEqualToString:@"addRow"]) {
        NSString *name = args[@"name"] ?: @"Row";
        NSInteger iconId = [args[@"iconId"] integerValue];
        NSInteger preferredRowId = args[@"preferredRowId"] == nil ? -1 : [args[@"preferredRowId"] integerValue];
        result([JuceBridge addRowObjC:name iconId:iconId preferredRowId:preferredRowId]);
    } else if ([call.method isEqualToString:@"insertRowAbove"]) {
        NSInteger referenceRowId = [args[@"referenceRowId"] integerValue];
        NSString *name = args[@"name"] ?: @"Row";
        NSInteger iconId = [args[@"iconId"] integerValue];
        NSInteger preferredRowId = args[@"preferredRowId"] == nil ? -1 : [args[@"preferredRowId"] integerValue];
        result([JuceBridge insertRowAboveObjC:referenceRowId name:name iconId:iconId preferredRowId:preferredRowId]);
    } else if ([call.method isEqualToString:@"insertRowBelow"]) {
        NSInteger referenceRowId = [args[@"referenceRowId"] integerValue];
        NSString *name = args[@"name"] ?: @"Row";
        NSInteger iconId = [args[@"iconId"] integerValue];
        NSInteger preferredRowId = args[@"preferredRowId"] == nil ? -1 : [args[@"preferredRowId"] integerValue];
        result([JuceBridge insertRowBelowObjC:referenceRowId name:name iconId:iconId preferredRowId:preferredRowId]);
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
    } else if ([call.method isEqualToString:@"setLoopRegion"]) {
        BOOL enabled = [args[@"enabled"] boolValue];
        double startSeconds = [args[@"startSeconds"] doubleValue];
        double endSeconds = [args[@"endSeconds"] doubleValue];
        [JuceBridge setLoopRegionObjC:enabled
                         startSeconds:startSeconds
                           endSeconds:endSeconds];
        result(nil);

    // ----------------------------------------
    // NEW ROW (TRACK BUS) API
    // ----------------------------------------
    } else if ([call.method isEqualToString:@"insertTrackEffect"]) {
        NSInteger row = [args[@"row"] integerValue];
        NSString *path = [args[@"path"] copy];
        BOOL forceIndividualRow = [args[@"forceIndividualRow"] boolValue];
#if TARGET_OS_OSX
        FlutterResult insertResult = [result copy];
        dispatch_async(MixroomMidiClipLoadQueue(), ^{
            BOOL ok = [JuceBridge insertTrackEffectObjC:row
                                                   path:path
                                     forceIndividualRow:forceIndividualRow];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (ok) {
                    insertResult(@(YES));
                } else {
                    insertResult([FlutterError errorWithCode:@"insert_track_effect_failed"
                                                     message:@"Failed to insert row effect"
                                                     details:@{@"row": @(row), @"path": path ?: @""}]);
                }
            });
        });
#else
        BOOL ok = [JuceBridge insertTrackEffectObjC:row
                                               path:path
                                 forceIndividualRow:forceIndividualRow];
        if (ok) {
            result(@(YES));
        } else {
            result([FlutterError errorWithCode:@"insert_track_effect_failed"
                                       message:@"Failed to insert row effect"
                                       details:@{@"row": @(row), @"path": path ?: @""}]);
        }
#endif
    } else if ([call.method isEqualToString:@"removeTrackEffect"]) {
        NSInteger row = [args[@"row"] integerValue];
        NSInteger effect = [args[@"effect"] integerValue];
        BOOL forceIndividualRow = [args[@"forceIndividualRow"] boolValue];
#if TARGET_OS_OSX
        FlutterResult removeResult = [result copy];
        dispatch_async(MixroomMidiClipLoadQueue(), ^{
            [JuceBridge removeTrackEffectObjC:row
                                  effectIndex:effect
                           forceIndividualRow:forceIndividualRow];
            dispatch_async(dispatch_get_main_queue(), ^{
                removeResult(nil);
            });
        });
#else
        [JuceBridge removeTrackEffectObjC:row
                              effectIndex:effect
                       forceIndividualRow:forceIndividualRow];
        result(nil);
#endif
    } else if ([call.method isEqualToString:@"reorderTrackEffects"]) {
        NSInteger row  = [args[@"row"] integerValue];
        NSInteger from = [args[@"from"] integerValue];
        NSInteger to   = [args[@"to"] integerValue];
        BOOL forceIndividualRow = [args[@"forceIndividualRow"] boolValue];
        [JuceBridge reorderTrackEffectsObjC:row
                                  fromIndex:from
                                    toIndex:to
                         forceIndividualRow:forceIndividualRow];
        result(nil);
    } else if ([call.method isEqualToString:@"getTrackEffectsForRow"]) {
        NSInteger row = [args[@"row"] integerValue];
        BOOL forceIndividualRow = [args[@"forceIndividualRow"] boolValue];
        result([JuceBridge getTrackEffectsForRowObjC:row
                                  forceIndividualRow:forceIndividualRow]);
    } else if ([call.method isEqualToString:@"getTrackEffectIdsForRow"]) {
        NSInteger row = [args[@"row"] integerValue];
        BOOL forceIndividualRow = [args[@"forceIndividualRow"] boolValue];
        result([JuceBridge getTrackEffectIdsForRowObjC:row
                                    forceIndividualRow:forceIndividualRow]);
    } else if ([call.method isEqualToString:@"getTrackEffectInstanceIdsForRow"]) {
        NSInteger row = [args[@"row"] integerValue];
        BOOL forceIndividualRow = [args[@"forceIndividualRow"] boolValue];
        result([JuceBridge getTrackEffectInstanceIdsForRowObjC:row
                                            forceIndividualRow:forceIndividualRow]);
    } else if ([call.method isEqualToString:@"getTrackEffectState"]) {
        NSInteger row = [args[@"row"] integerValue];
        NSInteger effect = [args[@"effect"] integerValue];
        BOOL forceIndividualRow = [args[@"forceIndividualRow"] boolValue];
        result([JuceBridge getTrackEffectStateObjC:row
                                         effectIndex:effect
                                  forceIndividualRow:forceIndividualRow]);
    } else if ([call.method isEqualToString:@"setTrackEffectState"]) {
        NSInteger row = [args[@"row"] integerValue];
        NSInteger effect = [args[@"effect"] integerValue];
        NSString *stateBase64 = [args[@"stateBase64"] ?: @"" copy];
        BOOL forceIndividualRow = [args[@"forceIndividualRow"] boolValue];
#if TARGET_OS_OSX
        FlutterResult stateResult = [result copy];
        dispatch_async(MixroomMidiClipLoadQueue(), ^{
            BOOL applied = [JuceBridge setTrackEffectStateObjC:row
                                                   effectIndex:effect
                                                   stateBase64:stateBase64
                                            forceIndividualRow:forceIndividualRow];
            dispatch_async(dispatch_get_main_queue(), ^{
                stateResult(@(applied));
            });
        });
#else
        result(@([JuceBridge setTrackEffectStateObjC:row
                                         effectIndex:effect
                                         stateBase64:stateBase64
                                  forceIndividualRow:forceIndividualRow]));
#endif
    } else if ([call.method isEqualToString:@"openTrackPluginEditor"]) {
        NSInteger row = [args[@"row"] integerValue];
        NSInteger effect = [args[@"effect"] integerValue];
        result(@([JuceBridge openTrackPluginEditorObjC:row effectIndex:effect]));
    } else if ([call.method isEqualToString:@"setTrackEffect"]) {
        NSInteger row    = [args[@"row"] integerValue];
        NSInteger effect = [args[@"effect"] integerValue];
        NSString *param  = args[@"paramId"];
        id value         = args[@"value"];
        BOOL forceIndividualRow = [args[@"forceIndividualRow"] boolValue];
        [JuceBridge setTrackEffectObjC:row
                           effectIndex:effect
                               paramId:param
                                 value:value
                    forceIndividualRow:forceIndividualRow];
        result(nil);
    } else if ([call.method isEqualToString:@"bypassRowEffect"]) {
        NSInteger row = [args[@"row"] integerValue];
        NSInteger effect = [args[@"effect"] integerValue];
        BOOL bypass = [args[@"bypass"] boolValue];
        BOOL forceIndividualRow = [args[@"forceIndividualRow"] boolValue];
        [JuceBridge bypassRowEffectObjC:row
                             effectIndex:effect
                                  bypass:bypass
                      forceIndividualRow:forceIndividualRow];
        result(nil);
    } else if ([call.method isEqualToString:@"getRowEffectBypassState"]) {
        NSInteger row = [args[@"row"] integerValue];
        NSInteger effect = [args[@"effect"] integerValue];
        BOOL forceIndividualRow = [args[@"forceIndividualRow"] boolValue];
        BOOL state = [JuceBridge getRowEffectBypassStateObjC:row
                                                effectIndex:effect
                                         forceIndividualRow:forceIndividualRow];
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
    } else if ([call.method isEqualToString:@"configureTrackGroups"]) {
        NSArray *groups = args[@"groups"];
        [JuceBridge configureTrackGroupsObjC:groups];
        result(nil);
    } else if ([call.method isEqualToString:@"assignRowToGroup"]) {
        NSInteger row = [args[@"row"] integerValue];
        NSString *groupId = args[@"groupId"] ?: @"";
        [JuceBridge assignRowToGroupObjC:row groupId:groupId];
        result(nil);
    } else if ([call.method isEqualToString:@"setTrackGroupMixState"]) {
        NSString *groupId = args[@"groupId"] ?: @"";
        float gain = args[@"gain"] != nil ? [args[@"gain"] floatValue] : 2.0f;
        float pan = args[@"pan"] != nil ? [args[@"pan"] floatValue] : 0.5f;
        BOOL muted = args[@"muted"] != nil ? [args[@"muted"] boolValue] : NO;
        BOOL soloed = args[@"soloed"] != nil ? [args[@"soloed"] boolValue] : NO;
        [JuceBridge setTrackGroupMixStateObjC:groupId
                                         gain:gain
                                          pan:pan
                                        muted:muted
                                       soloed:soloed];
        result(nil);

    // ----------------------------------------
    // NEW MASTER BUS API
    // ----------------------------------------
    } else if ([call.method isEqualToString:@"insertMasterEffect"]) {
        NSString *path = [args[@"path"] copy];
#if TARGET_OS_OSX
        FlutterResult insertResult = [result copy];
        dispatch_async(MixroomMidiClipLoadQueue(), ^{
            BOOL ok = [JuceBridge insertMasterEffectObjC:path];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (ok) {
                    insertResult(@(YES));
                } else {
                    insertResult([FlutterError errorWithCode:@"insert_master_effect_failed"
                                                     message:@"Failed to insert master effect"
                                                     details:@{@"path": path ?: @""}]);
                }
            });
        });
#else
        BOOL ok = [JuceBridge insertMasterEffectObjC:path];
        if (ok) {
            result(@(YES));
        } else {
            result([FlutterError errorWithCode:@"insert_master_effect_failed"
                                       message:@"Failed to insert master effect"
                                       details:@{@"path": path ?: @""}]);
        }
#endif
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
    } else if ([call.method isEqualToString:@"getMasterEffectInstanceIds"]) {
        result([JuceBridge getMasterEffectInstanceIdsObjC]);
    } else if ([call.method isEqualToString:@"getMasterEffectIds"]) {
        result([JuceBridge getMasterEffectIdsObjC]);
    } else if ([call.method isEqualToString:@"getMasterEffectState"]) {
        NSInteger effect = [args[@"effect"] integerValue];
        result([JuceBridge getMasterEffectStateObjC:effect]);
    } else if ([call.method isEqualToString:@"setMasterEffectState"]) {
        NSInteger effect = [args[@"effect"] integerValue];
        NSString *stateBase64 = [args[@"stateBase64"] ?: @"" copy];
#if TARGET_OS_OSX
        FlutterResult stateResult = [result copy];
        dispatch_async(MixroomMidiClipLoadQueue(), ^{
            BOOL applied = [JuceBridge setMasterEffectStateObjC:effect
                                                    stateBase64:stateBase64];
            dispatch_async(dispatch_get_main_queue(), ^{
                stateResult(@(applied));
            });
        });
#else
        result(@([JuceBridge setMasterEffectStateObjC:effect
                                          stateBase64:stateBase64]));
#endif
    } else if ([call.method isEqualToString:@"openMasterPluginEditor"]) {
        NSInteger effect = [args[@"effect"] integerValue];
        result(@([JuceBridge openMasterPluginEditorObjC:effect]));
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
    else if ([call.method isEqualToString:@"getRecentMasterWaveform"]) {
        NSInteger sampleCount = [call.arguments[@"sampleCount"] integerValue];
        NSArray* arr = [JuceBridge getRecentMasterWaveformObjC:sampleCount];
        result(arr);
    }
    else if ([call.method isEqualToString:@"getRecentMasterStereoWaveform"]) {
        NSInteger sampleCount = [call.arguments[@"sampleCount"] integerValue];
        NSArray* arr = [JuceBridge getRecentMasterStereoWaveformObjC:sampleCount];
        result(arr);
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
    }
    else if ([call.method isEqualToString:@"getRowStereoScope"]) {
        NSInteger row = [call.arguments[@"row"] integerValue];
        NSInteger effect = [call.arguments[@"effect"] integerValue];
        NSInteger pointCount = [call.arguments[@"pointCount"] integerValue];
        NSArray* arr = [JuceBridge getRowStereoScopeObjC:row effectIndex:effect pointCount:pointCount];
        result(arr);
    }
    else if ([call.method isEqualToString:@"getMasterStereoScope"]) {
        NSInteger effect = [call.arguments[@"effect"] integerValue];
        NSInteger pointCount = [call.arguments[@"pointCount"] integerValue];
        NSArray* arr = [JuceBridge getMasterStereoScopeObjC:effect pointCount:pointCount];
        result(arr);
    }
    else if ([call.method isEqualToString:@"getRowShaperPreview"]) {
        NSInteger row = [call.arguments[@"row"] integerValue];
        NSInteger effect = [call.arguments[@"effect"] integerValue];
        NSInteger pointCount = [call.arguments[@"pointCount"] integerValue];
        NSArray* arr = [JuceBridge getRowShaperPreviewObjC:row effectIndex:effect pointCount:pointCount];
        result(arr);
    }
    else if ([call.method isEqualToString:@"getMasterShaperPreview"]) {
        NSInteger effect = [call.arguments[@"effect"] integerValue];
        NSInteger pointCount = [call.arguments[@"pointCount"] integerValue];
        NSArray* arr = [JuceBridge getMasterShaperPreviewObjC:effect pointCount:pointCount];
        result(arr);
    }
    else if ([call.method isEqualToString:@"getRowDynamicSoftenerFrame"]) {
        NSInteger row = [call.arguments[@"row"] integerValue];
        NSInteger effect = [call.arguments[@"effect"] integerValue];
        NSArray* arr = [JuceBridge getRowDynamicSoftenerFrameObjC:row effectIndex:effect];
        result(arr);
    }
    else if ([call.method isEqualToString:@"getMasterDynamicSoftenerFrame"]) {
        NSInteger effect = [call.arguments[@"effect"] integerValue];
        NSArray* arr = [JuceBridge getMasterDynamicSoftenerFrameObjC:effect];
        result(arr);
    }
    else if ([call.method isEqualToString:@"getRowTransientShaperVisual"]) {
        NSInteger row = [call.arguments[@"row"] integerValue];
        NSInteger effect = [call.arguments[@"effect"] integerValue];
        NSInteger pointCount = [call.arguments[@"pointCount"] integerValue];
        NSArray* arr = [JuceBridge getRowTransientShaperVisualObjC:row effectIndex:effect pointCount:pointCount];
        result(arr);
    }
    else if ([call.method isEqualToString:@"getMasterTransientShaperVisual"]) {
        NSInteger effect = [call.arguments[@"effect"] integerValue];
        NSInteger pointCount = [call.arguments[@"pointCount"] integerValue];
        NSArray* arr = [JuceBridge getMasterTransientShaperVisualObjC:effect pointCount:pointCount];
        result(arr);
    }


    // ----------------------------------------
    // TRANSPORT / DEBUG
    // ----------------------------------------
    else if ([call.method isEqualToString:@"setAutomationTransport"]) {
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
    else if ([call.method isEqualToString:@"setMetronomeTimeSignature"]) {
        [JuceBridge setMetronomeTimeSignatureObjC:[args[@"numerator"] integerValue]
                                      denominator:[args[@"denominator"] integerValue]];
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
    } else if ([call.method isEqualToString:@"analyzeAudioForPrompt"]) {
        NSString *path = [args[@"path"] copy];
        double trimStartMs = [args[@"trimStartMs"] doubleValue];
        NSNumber *trimEndValue = args[@"trimEndMs"];
        double trimEndMs = trimEndValue == nil ? -1.0 : [trimEndValue doubleValue];
        dispatch_async(MixroomPromptAnalysisQueue(), ^{
            NSDictionary *analysis = [JuceBridge analyzeAudioForPromptObjC:path
                                                               trimStartMs:trimStartMs
                                                                 trimEndMs:trimEndMs];
            dispatch_async(dispatch_get_main_queue(), ^{
                result(analysis);
            });
        });
    } else if ([call.method isEqualToString:@"analyzeAudioStereo16k"]) {
        NSString *path = args[@"path"];
        NSDictionary *stats = [JuceBridge analyzeAudioStereo16kObjC:path];
        result(stats);
    } else if ([call.method isEqualToString:@"getInputDevices"]) {
        result([JuceBridge getInputDevicesObjC]);
    }
    else if ([call.method isEqualToString:@"getOutputDevices"]) {
        result([JuceBridge getOutputDevicesObjC]);
    }
    else if ([call.method isEqualToString:@"getInputDeviceInfos"]) {
#if TARGET_OS_OSX
        NSString *implementation =
            [JuceBridge getAudioRouteImplementationObjC] ?: @"none";
        result([implementation isEqualToString:@"v2"]
            ? MixroomMacV2InputDeviceInfos()
            : MixroomMacInputDeviceInfos());
#else
        AVAudioSession *session = [AVAudioSession sharedInstance];
        NSArray<AVAudioSessionPortDescription *> *availableInputs =
            session.availableInputs ?: @[];
        AVAudioSessionPortDescription *preferredInput = session.preferredInput;
        AVAudioSessionPortDescription *routedInput =
            session.currentRoute.inputs.count == 1
                ? session.currentRoute.inputs.firstObject
                : nil;
        NSMutableArray *infos = [NSMutableArray array];
        for (AVAudioSessionPortDescription *input in availableInputs) {
            NSString *portType = input.portType ?: @"";
            const BOOL isDefault =
                (preferredInput != nil &&
                 [preferredInput.UID isEqualToString:input.UID]) ||
                (preferredInput == nil && routedInput != nil &&
                 [routedInput.UID isEqualToString:input.UID]) ||
                (preferredInput == nil && routedInput == nil &&
                 availableInputs.count == 1);
            [infos addObject:@{
                @"uid": input.UID ?: @"",
                @"name": input.portName ?: @"",
                @"channelCount": input.channels == nil
                    ? @0 : @(input.channels.count),
                @"isBluetoothInput": @(
                    [portType isEqualToString:AVAudioSessionPortBluetoothHFP] ||
                    [portType isEqualToString:AVAudioSessionPortBluetoothLE]),
                @"isBuiltIn": @(
                    [portType isEqualToString:AVAudioSessionPortBuiltInMic]),
                @"isDefault": @(isDefault),
                @"transport": MixroomIOSRouteKind(portType),
            }];
        }
        result(infos);
#endif
    }
    else if ([call.method isEqualToString:@"selectInputDevice"]) {
        result(@([JuceBridge selectInputDeviceObjC:args[@"name"]]));
    }
    else if ([call.method isEqualToString:@"selectOutputDevice"]) {
        result(@([JuceBridge selectOutputDeviceObjC:args[@"name"]]));
    }
    else if ([call.method isEqualToString:@"getNumInputChannels"]) {
        result([JuceBridge getNumInputChannelsObjC]);
    }
    else if ([call.method isEqualToString:@"prepareRecordingInputs"]) {
        NSInteger desiredInputChannels = [args[@"desiredInputChannels"] integerValue];
        NSString *reason = args[@"reason"] ?: @"dart";
        result(@([JuceBridge prepareRecordingInputsObjC:desiredInputChannels reason:reason]));
    }
    else if ([call.method isEqualToString:@"configureAudioDevice"]) {
        double sampleRate = [args[@"sampleRate"] doubleValue];
        NSInteger bufferSize = [args[@"bufferSize"] integerValue];
        NSInteger desiredInputChannels = [args[@"desiredInputChannels"] integerValue];
        NSString *reason = args[@"reason"] ?: @"dart";
        result(@([JuceBridge configureAudioDeviceObjC:sampleRate
                                           bufferSize:bufferSize
                                  desiredInputChannels:desiredInputChannels
                                                reason:reason]));
    }
    else if ([call.method isEqualToString:@"preparePlaybackRoute"]) {
        NSString *reason = args[@"reason"] ?: @"dart";
        result(@([JuceBridge preparePlaybackRouteObjC:reason]));
    }
    else if ([call.method isEqualToString:@"preparePlaybackGraph"]) {
        NSString *reason = args[@"reason"] ?: @"dart";
        result(@([JuceBridge preparePlaybackGraphObjC:reason]));
    }
    else if ([call.method isEqualToString:@"refreshAudioRoute"]) {
        NSString *reason = args[@"reason"] ?: @"dart";
        [JuceBridge refreshAudioRouteObjC:reason];
        result(nil);
    }
    else if ([call.method isEqualToString:@"setMidiInputChannelFilter"]) {
        NSInteger channel = [args[@"channel"] integerValue];
        [JuceBridge setMidiInputChannelFilterObjC:channel];
        result(nil);
    }
    else if ([call.method isEqualToString:@"getMidiInputChannelFilter"]) {
        result([JuceBridge getMidiInputChannelFilterObjC]);
    }
    else if ([call.method isEqualToString:@"getRecordingPeak"]) {
        result([JuceBridge getRecordingPeakObjC]);
    }
    else if ([call.method isEqualToString:@"getCurrentDeviceName"]) {
        result([JuceBridge getCurrentDeviceNameObjC]);
    }
    else if ([call.method isEqualToString:@"getCurrentOutputDeviceName"]) {
        result([JuceBridge getCurrentOutputDeviceNameObjC]);
    }
    else if ([call.method isEqualToString:@"getAudioRouteInfo"]) {
        result([self buildAudioRouteInfo]);
    }
    else if ([call.method isEqualToString:@"getAudioRouteSnapshotV2"]) {
        result([self buildAudioRouteSnapshotV2]);
    }
    else if ([call.method isEqualToString:@"initialisePlaybackV2"]) {
#if TARGET_OS_OSX
        dispatch_async(MixroomMacPlaybackStartupQueue(), ^{
            NSDictionary<NSString *, id> *rawResponse =
                [self initialisePlaybackV2] ?: @{
                    @"success": @NO,
                    @"diagnosticCode": @"actual_state_unavailable",
                    @"snapshot": @{},
                };
            NSDictionary<NSString *, id> *response = [rawResponse copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                result(response);
                [response release];
            });
        });
#else
        result([self initialisePlaybackV2]);
#endif
    }
    else if ([call.method isEqualToString:@"startAudioRouteMonitoringV2"]) {
        result([self startAudioRouteMonitoringV2]);
    }
    else if ([call.method isEqualToString:@"applyAudioRouteConfigurationV2"]) {
#if TARGET_OS_OSX
        NSDictionary *transitionArgs = [args ?: @{} copy];
        dispatch_async(MixroomMacPlaybackStartupQueue(), ^{
            self.macLifecycleTransitionActiveV2 = YES;
            self.macLifecycleReconcilePendingV2 = NO;
            NSDictionary<NSString *, id> *rawResponse =
                [self applyAudioRouteConfigurationV2:transitionArgs] ?: @{
                    @"status": @"failure",
                    @"diagnosticCode": @"actual_state_unavailable",
                    @"snapshot": @{},
                };
            NSDictionary<NSString *, id> *response = [rawResponse copy];
            const BOOL reconcile = self.macLifecycleReconcilePendingV2;
            self.macLifecycleReconcilePendingV2 = NO;
            self.macLifecycleTransitionActiveV2 = NO;
            [transitionArgs release];
            dispatch_async(dispatch_get_main_queue(), ^{
                result(response);
                if (reconcile) {
                    [self handleAudioRoutePropertyChangeV2:@"transitionReconcile"];
                }
                [response release];
            });
        });
#else
        NSDictionary *transitionArgs = [args ?: @{} copy];
        self.iosLifecycleTransitionActiveV2 = YES;
        ++self.iosLifecycleCompletionTokenV2;
        dispatch_async(MixroomIOSLifecycleQueue(), ^{
            NSDictionary<NSString *, id> *rawResponse =
                [self applyAudioRouteConfigurationV2:transitionArgs] ?: @{
                    @"status": @"failure",
                    @"diagnosticCode": @"actual_state_unavailable",
                    @"snapshot": @{},
                };
            NSDictionary<NSString *, id> *response = [rawResponse copy];
            [transitionArgs release];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.iosLifecycleTransitionActiveV2 = NO;
                result(response);
                [response release];
            });
        });
#endif
    }
    else if ([call.method isEqualToString:@"setAudioRouteIntentV2"]) {
        [self setAudioRouteIntentV2:args ?: @{} completion:result];
    }
    else if ([call.method isEqualToString:@"abortRecordingV2"]) {
#if TARGET_OS_OSX
        // A cancel-only record tap must not cancel the monitor's input owner.
        // Dart waits for the in-flight start and finalizes any capture it armed.
        const BOOL cancelOnly = [args[@"cancelOnly"] boolValue];
        if (cancelOnly && self.macIntentOperationActiveV2 &&
            [self.macIntentOperationModeV2 isEqualToString:@"systemSelectedMonitoring"] &&
            ([self.currentAudioRouteIntentV2 isEqualToString:@"monitoring"] ||
             [self.currentAudioRouteIntentV2 isEqualToString:@"recording"])) {
            result(nil);
            return;
        }
        if (self.macIntentOperationActiveV2) {
            self.macIntentOperationCancelledV2 = YES;
            self.macIntentTerminalCauseV2 = @"cancelled";
            [JuceBridge cancelMacInputProbeWaitV2ObjC];
            [JuceBridge cancelMacOutputCallbackProofV2ObjC];
            [self signalMacIntentRouteConditionV2];
        }
#else
        if ([[JuceBridge getAudioRouteImplementationObjC] isEqualToString:@"v2"]) {
            const BOOL restoreRequested =
                ![args[@"restorePlayback"] isKindOfClass:[NSNumber class]] ||
                [args[@"restorePlayback"] boolValue];
            const BOOL cancelOnly =
                [args[@"cancelOnly"] isKindOfClass:[NSNumber class]] &&
                [args[@"cancelOnly"] boolValue];
            const BOOL requestedActiveProbe =
                self.iosIntentOperationActiveV2;
            const uint64_t requestedOperationID =
                self.iosIntentOperationIdV2;
            if (cancelOnly && [self isIOSMonitorOwnedV2]) {
                self.iosCaptureV2.cancelled = YES;
                result(nil);
                return;
            }
            self.iosIntentOperationCancelledV2 = YES;
            self.iosIntentTerminalCauseV2 = restoreRequested
                ? @"cancelled" : @"routeInvalidated";
            [self signalIOSIntentRouteConditionV2];
            if (cancelOnly) {
                result(nil);
                return;
            }
            self.iosLifecycleTransitionActiveV2 = YES;
        ++self.iosLifecycleCompletionTokenV2;
            dispatch_async(MixroomIOSLifecycleQueue(), ^{
                if (requestedActiveProbe &&
                    (!self.iosIntentOperationActiveV2 ||
                     self.iosIntentOperationIdV2 != requestedOperationID)) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.iosLifecycleTransitionActiveV2 = NO;
                        result(nil);
                    });
                    return;
                }
                const BOOL activeProbe = self.iosIntentOperationActiveV2;
                if (activeProbe && ![self claimIOSIntentCleanupV2]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.iosLifecycleTransitionActiveV2 = NO;
                        result(nil);
                    });
                    return;
                }
                NSDictionary<NSString *, id> *probeSource =
                    self.iosRecordingOutputV2;
                const BOOL terminal =
                    !restoreRequested ||
                    [JuceBridge isIOSIntentRouteInvalidatedV2ObjC];
                [JuceBridge disableLiveInputMonitoringV2ObjC];
                [JuceBridge discardRecordingCaptureObjC];
                BOOL restored = NO;
                NSDictionary *restoredOutput = nil;
                if (!terminal) {
                    AVAudioSession *session =
                        [AVAudioSession sharedInstance];
                    restored = [JuceBridge
                        reconfigurePlaybackRouteV2ObjC:@""
                        sampleRate:MixroomIOSPlaybackOpenRate(
                            probeSource,
                            session,
                            self.preferredPlaybackSampleRateV2)
                        bufferFrames:MixroomIOSPlaybackOpenBuffer(
                            probeSource,
                            session,
                            self.preferredPlaybackBufferFramesV2)];
                    NSDictionary *snapshot = restored
                        ? [self buildAudioRouteSnapshotV2] : nil;
                    NSArray *outputs =
                        [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
                            ? snapshot[@"outputs"] : @[];
                    restoredOutput = outputs.count == 1
                        ? outputs.firstObject : nil;
                    if (activeProbe) {
                        restored = restored &&
                            [snapshot[@"captureConsistency"]
                                isEqualToString:@"stable"] &&
                            MixroomIOSEndpointIdentitiesMatchStrict(
                                probeSource, restoredOutput);
                    }
                }
                if (terminal || !restored) {
                    [JuceBridge quiescePlaybackRouteV2ObjC:YES];
                }
                if (activeProbe) {
                    NSDictionary *probeFacts =
                        [self.iosLastDuplexProbeV2
                            isKindOfClass:[NSDictionary class]]
                            ? self.iosLastDuplexProbeV2 : @{};
                    self.iosLastDuplexProbeV2 = @{
                        @"status": restored
                            ? @"cancelledRestored" : @"cancelled",
                        @"diagnosticCode": restored ? @"ok" : @"route_unstable",
                        @"validationStage": terminal
                            ? @"physicalRouteInvalidation" : @"cancelled",
                        @"phase": self.iosIntentLifecyclePhaseV2 ?: @"cleanup",
                        @"terminalCause":
                            self.iosIntentTerminalCauseV2 ?: [NSNull null],
                        @"actualCallbackCount":
                            probeFacts[@"actualCallbackCount"] ?: @0,
                        @"cleanupOutcome": restored
                            ? @"restored" : @"closed",
                        @"selectionMode":
                            probeFacts[@"selectionMode"] ?:
                                (![self.iosIntentOperationModeV2
                                      isEqualToString:@"standard"]
                                    ? @"systemSelected" : @"explicitHfp"),
                        @"operationId": @(self.iosIntentOperationIdV2),
                        @"elapsedMs": @((NSInteger)(
                            MixroomIOSMonotonicMilliseconds() -
                            self.iosIntentOperationStartedAtMsV2 + 0.5)),
                        @"sourceOutput": probeSource ?: [NSNull null],
                        @"duplexInput":
                            self.iosRecordingInputV2 ?: [NSNull null],
                        @"duplexOutput":
                            self.iosIntentOperationTargetOutputV2 ?: [NSNull null],
                        @"restoredOutput": restoredOutput ?: [NSNull null],
                    };
                    [JuceBridge endIOSIntentOperationV2ObjC];
                    self.iosIntentOperationActiveV2 = NO;
                    self.iosIntentOperationModeV2 = @"standard";
                    self.iosIntentMonitoringTargetRowV2 = -1;
                }
                self.iosIntentLifecyclePhaseV2 = @"idle";
                self.iosIntentRouteConditionV2 = nil;
                self.iosRecordingOutputV2 = nil;
                self.iosRecordingInputV2 = nil;
                if (terminal || restored) {
                    self.currentAudioRouteIntentV2 = @"playbackOnly";
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.iosLifecycleTransitionActiveV2 = NO;
                    result(nil);
                });
            });
            return;
        }
#endif
        result(nil);
    }
    else if ([call.method isEqualToString:@"stopAudioRouteMonitoringV2"]) {
        [self stopAudioRouteMonitoringV2];
        result(nil);
    }
    else if ([call.method isEqualToString:@"preferNonBluetoothRecordingInput"]) {
        result(@([self preferNonBluetoothRecordingInput]));
    }
    else if ([call.method isEqualToString:@"setLiveInputMonitoringEnabled"]) {
        [JuceBridge setLiveInputMonitoringEnabledObjC:[args[@"enabled"] boolValue]];
        result(nil);
    }
    else if ([call.method isEqualToString:@"startRecording"]) {
#if TARGET_OS_OSX
        const BOOL macV2 = [[JuceBridge getAudioRouteImplementationObjC]
            isEqualToString:@"v2"];
        if (macV2) {
            NSString *path = [args[@"path"] copy];
            FlutterResult recordingResult = [result copy];
            dispatch_async(MixroomMacPlaybackStartupQueue(), ^{
                const BOOL started =
                    [self startMacIndependentInputRecordingV2:path
                                                  channelStart:[args[@"channelStart"] integerValue]
                                                  channelCount:[args[@"channelCount"] integerValue]];
                [path release];
                dispatch_async(dispatch_get_main_queue(), ^{
                    recordingResult(@(started));
                    [recordingResult release];
                });
            });
            return;
        }
#endif
#if !TARGET_OS_OSX
        if ([[JuceBridge getAudioRouteImplementationObjC] isEqualToString:@"v2"]) {
            [self startIOSCaptureV2:args result:result];
            return;
        }
#endif
        result(@([JuceBridge startRecordingObjC:args[@"path"]
                                channelStart:[args[@"channelStart"] integerValue]
                                channelCount:[args[@"channelCount"] integerValue]]));
    }
    else if ([call.method isEqualToString:@"stopRecording"]) {
#if TARGET_OS_OSX
        const BOOL macV2 = [[JuceBridge getAudioRouteImplementationObjC]
            isEqualToString:@"v2"];
        if (!macV2) {
            result([JuceBridge stopRecordingObjC]);
            return;
        }
        FlutterResult recordingResult = [result copy];
        self.macLifecycleTransitionActiveV2 = YES;
        dispatch_async(MixroomMacPlaybackStartupQueue(), ^{
            NSDictionary<NSString *, id> *stopResult =
                [[JuceBridge stopMacInputRecordingV2ObjC] copy];
            NSLog(@"[MacV2Capture] stop success=%d code=%@ attempted=%@ "
                  "accepted=%@ dropped=%@ invalid=%@ rate=%@ channels=%@ "
                  "inputCallbacks=%@ inputInvalid=%@ firstRenderError=%@ "
                  "lastRenderError=%@",
                  [stopResult[@"success"] boolValue],
                  stopResult[@"diagnosticCode"] ?: @"missing",
                  stopResult[@"attemptedSamples"] ?: @0,
                  stopResult[@"acceptedSamples"] ?: @0,
                  stopResult[@"droppedSamples"] ?: @0,
                  stopResult[@"invalidBlockCount"] ?: @0,
                  stopResult[@"actualSampleRate"] ?: @0,
                  stopResult[@"channelCount"] ?: @0,
                  stopResult[@"inputCallbackCount"] ?: @0,
                  stopResult[@"inputInvalidCallbackCount"] ?: @0,
                  stopResult[@"firstRenderErrorStatus"] ?: @0,
                  stopResult[@"lastRenderErrorStatus"] ?: @0);
            NSMutableDictionary<NSString *, id> *captureReport =
                [NSMutableDictionary dictionaryWithDictionary:
                    self.iosLastDuplexProbeV2 ?: @{}];
            captureReport[@"captureActive"] = @NO;
            captureReport[@"captureAttemptedSamples"] =
                stopResult[@"attemptedSamples"] ?: @0;
            captureReport[@"captureAcceptedSamples"] =
                stopResult[@"acceptedSamples"] ?: @0;
            captureReport[@"captureDroppedSamples"] =
                stopResult[@"droppedSamples"] ?: @0;
            captureReport[@"captureInvalidBlockCount"] =
                stopResult[@"invalidBlockCount"] ?: @0;
            captureReport[@"captureSampleRateHz"] =
                stopResult[@"actualSampleRate"] ?: @0;
            self.iosLastDuplexProbeV2 = captureReport;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.macLifecycleTransitionActiveV2 = NO;
                recordingResult(stopResult);
                [stopResult release];
                [recordingResult release];
            });
        });
#else
        const BOOL isV2 = [[JuceBridge getAudioRouteImplementationObjC]
            isEqualToString:@"v2"];
        if (!isV2) {
            result([JuceBridge stopRecordingObjC]);
            return;
        }
        [self stopIOSCaptureV2:result];
#endif
    }
    else if ([call.method isEqualToString:@"restoreBluetoothPlaybackAfterRecordingStop"]) {
        [self restoreBluetoothPlaybackAfterRecordingStop];
        result(nil);
    }
    else if ([call.method isEqualToString:@"isRecording"]) {
        result(@([JuceBridge isRecordingObjC]));
    } else {
        result(FlutterMethodNotImplemented);
    }
}


@end

void JuceAudioEnginePluginShutdownForApplicationTermination(void) {
    [JuceAudioEnginePlugin shutdownForApplicationTermination];
}

void JuceAudioEnginePluginPanicLiveMidiNotesForApplicationDeactivation(void) {
    [JuceAudioEnginePlugin panicLiveMidiNotesForApplicationDeactivation];
}

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
