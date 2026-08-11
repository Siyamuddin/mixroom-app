#import "JuceAudioEnginePlugin.h"
#import "JuceBridge.h"
#import "JuceLogBridge.h"  // Add this import
#import <AVFoundation/AVFoundation.h>
#import <TargetConditionals.h>

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

@class JuceAudioEnginePlugin;

@interface JucePluginEventStreamHandler : NSObject <FlutterStreamHandler>
- (instancetype)initWithPlugin:(JuceAudioEnginePlugin *)plugin;
@end

@interface JuceAudioEnginePlugin ()
@property (nonatomic, copy) FlutterEventSink eventSink;
@property (nonatomic, copy) FlutterEventSink logSink;
@property (nonatomic, assign) BOOL audioRouteMonitoringV2;
@property (nonatomic, assign) uint64_t audioRouteGenerationV2;
@property (nonatomic, assign) uint64_t audioRouteTransitionIdV2;
@property (nonatomic, assign) uint32_t observedOutputDeviceV2;
@property (nonatomic, copy) NSString *audioRouteFingerprintV2;
@property (nonatomic, assign) BOOL routeTransitionWasPlayingV2;
@property (nonatomic, assign) BOOL routeTransitionFromBluetoothV2;
@property (nonatomic, assign) BOOL iosObservedOutputWasBluetoothV2;
@property (nonatomic, copy) NSString *iosVerifiedPlaybackOutputFingerprintV2;
@property (nonatomic, assign) BOOL iosVerifiedPlaybackOutputWasBluetoothV2;
@property (nonatomic, copy) NSString *iosLastObservedRouteCauseV2;
@property (nonatomic, copy) NSString *currentAudioRouteIntentV2;
- (void)bindEventSink:(FlutterEventSink)events;
- (void)clearEventSink;
- (NSDictionary<NSString *, id> *)buildAudioRouteSnapshotV2;
- (NSDictionary<NSString *, id> *)initialisePlaybackV2;
- (NSDictionary<NSString *, id> *)startAudioRouteMonitoringV2;
- (NSDictionary<NSString *, id> *)applyAudioRouteConfigurationV2:(NSDictionary *)args;
- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args;
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
               addresses[0].mSelector == kAudioDevicePropertyDeviceIsAlive) {
        cause = @"activeOutputRemoved";
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

static dispatch_queue_t MixroomPluginScanQueue(void) {
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
            "com.mixroom.juce_audio_engine.plugin_scan",
            attr
        );
    });
    return queue;
}

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

static BOOL MixroomConfigureIOSPlaybackSession(NSError **error) {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (![session setCategory:AVAudioSessionCategoryPlayback
                  withOptions:AVAudioSessionCategoryOptionMixWithOthers
                        error:error]) {
        return NO;
    }
    return [session setMode:AVAudioSessionModeDefault error:error];
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

static NSString *MixroomRawTransportValue(UInt32 transport) {
    return [NSString stringWithFormat:@"0x%08x", (unsigned int)transport];
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
    // covered by this checkpoint. Requiring stereo output also rejects the
    // observable call-quality shape without guessing a profile from its name.
    return transport == kAudioDeviceTransportTypeBluetooth &&
        channels.integerValue >= 2;
}

static NSString *MixroomEffectiveOutputFingerprint(void) {
    AudioDeviceID deviceID = MixroomDefaultCoreAudioOutputDevice();
    NSArray<NSDictionary<NSString *, id> *> *inventory =
        MixroomCoreAudioDeviceInventory();
    NSDictionary<NSString *, id> *device =
        MixroomOutputForDeviceID(inventory ?: @[], deviceID);
    if (device == nil) {
        return [NSString stringWithFormat:@"%u|missing", (unsigned int)deviceID];
    }
    NSString *identity = [device[@"uid"] length] > 0
        ? device[@"uid"]
        : [device[@"deviceID"] stringValue];
    return [NSString stringWithFormat:@"%@|%@|%@|%@",
            identity,
            device[@"rawTransport"],
            device[@"outputChannels"],
            MixroomCoreAudioDeviceIsAlive(deviceID) ? @"alive" : @"dead"];
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
    if (name.length == 0) {
        return @[];
    }
    NSMutableArray<NSDictionary<NSString *, id> *> *matches = [NSMutableArray array];
    NSString *channelKey = input ? @"inputChannels" : @"outputChannels";
    for (NSDictionary<NSString *, id> *device in inventory) {
        NSNumber *channels = device[channelKey];
        if ([device[@"name"] isEqualToString:name] &&
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
    NSDictionary<NSString *, id> *firstDiagnostics =
        [JuceBridge getEngineDiagnosticsObjC];
    NSArray<NSDictionary<NSString *, id> *> *secondInventory =
        MixroomCoreAudioDeviceInventory();
    NSDictionary<NSString *, id> *secondDiagnostics =
        [JuceBridge getEngineDiagnosticsObjC];

    NSMutableDictionary<NSString *, NSString *> *unavailable =
        [NSMutableDictionary dictionary];
    NSString *captureConsistency = @"unavailable";
    if (firstInventory == nil || secondInventory == nil) {
        unavailable[@"coreAudio.inventory"] = @"coreAudioReadFailed";
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

    NSDictionary<NSString *, id> *selectedInput =
        inputMatches.count == 1 ? inputMatches.firstObject : nil;
    NSDictionary<NSString *, id> *selectedOutput =
        outputMatches.count == 1 ? outputMatches.firstObject : nil;
    NSNumber *activeInputChannels =
        [diagnostics[@"inputChannelCount"] isKindOfClass:[NSNumber class]]
            ? diagnostics[@"inputChannelCount"]
            : nil;
    const BOOL selectedInputIsBluetooth = selectedInput != nil &&
        MixroomTransportIsBluetooth([selectedInput[@"transport"] unsignedIntValue]);
    const BOOL bluetoothInputActive = selectedInputIsBluetooth &&
        activeInputChannels != nil &&
        activeInputChannels.integerValue > 0;
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
            : selectedInput[@"inputChannels"],
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
    NSDictionary<NSString *, id> *diagnostics =
        [JuceBridge getEngineDiagnosticsObjC] ?: @{};
    AVAudioSessionRouteDescription *secondRoute = session.currentRoute;

    NSMutableDictionary<NSString *, NSString *> *unavailable =
        [NSMutableDictionary dictionary];
    NSString *captureConsistency = @"unavailable";
    if (firstRoute == nil || secondRoute == nil) {
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
        @"captureConsistency": captureConsistency,
        @"inputs": inputs,
        @"outputs": outputs,
        @"session": @{
            @"category": session.category ?: [NSNull null],
            @"mode": session.mode ?: [NSNull null],
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
            @"sampleRateHz": diagnosticValue(@"sampleRate"),
            @"bufferFrames": diagnosticValue(@"bufferSize"),
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
#if TARGET_OS_OSX
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
        MixroomOutputNameIsUnique(inventory, target);
    if (!targetUsable) {
        return @{
            @"success": @NO,
            @"diagnosticCode": target == nil ? @"no_output" : @"actual_state_unavailable",
            @"snapshot": [self buildAudioRouteSnapshotV2],
        };
    }
    NSString *expectedFingerprint = MixroomEffectiveOutputFingerprint();
    if (![JuceBridge initialisePlaybackV2ObjC:target[@"name"]]) {
        return @{
            @"success": @NO,
            @"diagnosticCode": @"juce_open_failed",
            @"snapshot": [self buildAudioRouteSnapshotV2],
        };
    }

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
    }

    const BOOL success = [diagnosticCode isEqualToString:@"ok"];
    if (!success) {
        [JuceBridge shutdownEngineObjC];
    }
    return @{
        @"success": @(success),
        @"diagnosticCode": diagnosticCode,
        @"snapshot": snapshot,
    };
#else
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
    NSError *sessionError = nil;
    if (!MixroomConfigureIOSPlaybackSession(&sessionError)) {
        [session setActive:NO error:nil];
        return @{
            @"success": @NO,
            @"diagnosticCode": @"actual_state_unavailable",
            @"snapshot": [self buildAudioRouteSnapshotV2],
        };
    }

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
        [session setActive:NO error:nil];
        return @{
            @"success": @NO,
            @"diagnosticCode": preflightCode,
            @"snapshot": [self buildAudioRouteSnapshotV2],
        };
    }

    if (![JuceBridge initialisePlaybackV2ObjC:@""]) {
        [session setActive:NO error:nil];
        return @{
            @"success": @NO,
            @"diagnosticCode": @"juce_open_failed",
            @"snapshot": [self buildAudioRouteSnapshotV2],
        };
    }

    sessionError = nil;
    const BOOL sessionConfigured = MixroomConfigureIOSPlaybackSession(&sessionError);
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
        [session setActive:NO error:nil];
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

- (NSDictionary<NSString *, id> *)setAudioRouteIntentV2:(NSDictionary *)args {
#if TARGET_OS_OSX
    const double startedAtMs = MixroomMonotonicMilliseconds();
    const uint64_t generation = [args[@"generation"] unsignedLongLongValue];
    NSString *intent = [args[@"intent"] isKindOfClass:[NSString class]]
        ? args[@"intent"]
        : @"";
    self.audioRouteTransitionIdV2 += 1;
    const uint64_t transitionID = self.audioRouteTransitionIdV2;
    NSString *diagnosticCode = @"ok";
    BOOL success = NO;

    if (!self.audioRouteMonitoringV2 ||
        ![[JuceBridge getAudioRouteImplementationObjC] isEqualToString:@"v2"]) {
        diagnosticCode = @"coordinator_disposed";
    } else if (generation != self.audioRouteGenerationV2) {
        diagnosticCode = @"stale_generation";
    } else if (![intent isEqualToString:@"playbackOnly"] &&
               ![intent isEqualToString:@"preparingRecording"] &&
               ![intent isEqualToString:@"recording"]) {
        diagnosticCode = @"recording_route_unsupported";
    } else {
        NSArray<NSDictionary<NSString *, id> *> *inventory =
            MixroomCoreAudioDeviceInventory() ?: @[];
        const AudioDeviceID defaultOutputID = MixroomDefaultCoreAudioOutputDevice();
        NSDictionary<NSString *, id> *output =
            MixroomOutputForDeviceID(inventory, defaultOutputID);
        NSString *expectedFingerprint = MixroomEffectiveOutputFingerprint();
        const BOOL supportedRecordingOutput =
            MixroomOutputSupportsV2Recording(inventory, output);

        if (!supportedRecordingOutput) {
            diagnosticCode = @"recording_route_unsupported";
        } else if ([intent isEqualToString:@"preparingRecording"]) {
            NSDictionary<NSString *, id> *input = MixroomUniqueBuiltInInput(inventory);
            if (input == nil) {
                diagnosticCode = @"no_input";
            } else if (MixroomTransportIsBluetooth(
                           [input[@"transport"] unsignedIntValue])) {
                diagnosticCode = @"bluetooth_input_forbidden";
            } else if (MixroomExactDeviceMatches(
                           inventory, input[@"name"], YES).count != 1) {
                diagnosticCode = @"actual_state_unavailable";
            } else if (![JuceBridge reconfigureRecordingRouteV2ObjC:output[@"name"]
                                                               inputName:input[@"name"]]) {
                diagnosticCode = @"juce_reopen_failed";
            } else {
                NSDictionary *snapshot = [self buildAudioRouteSnapshotV2];
                if (generation != self.audioRouteGenerationV2 ||
                    ![MixroomEffectiveOutputFingerprint() isEqualToString:expectedFingerprint]) {
                    diagnosticCode = @"stale_generation";
                } else if (![snapshot[@"captureConsistency"] isEqualToString:@"stable"]) {
                    diagnosticCode = @"route_unstable";
                } else if (!MixroomSnapshotMatchesRecordingRoute(
                               snapshot, input, output)) {
                    diagnosticCode = @"actual_state_unavailable";
                } else {
                    success = YES;
                }
            }
        } else if ([intent isEqualToString:@"recording"]) {
            NSDictionary<NSString *, id> *input = MixroomUniqueBuiltInInput(inventory);
            NSDictionary *snapshot = [self buildAudioRouteSnapshotV2];
            if (generation != self.audioRouteGenerationV2) {
                diagnosticCode = @"stale_generation";
            } else if (![MixroomEffectiveOutputFingerprint()
                           isEqualToString:expectedFingerprint] ||
                       ![snapshot[@"captureConsistency"] isEqualToString:@"stable"]) {
                diagnosticCode = @"route_unstable";
            } else {
                success = input != nil &&
                    MixroomSnapshotMatchesRecordingRoute(snapshot, input, output) &&
                    [JuceBridge validateRecordingRouteV2ObjC] &&
                    [JuceBridge isRecordingObjC];
                if (!success) diagnosticCode = @"actual_state_unavailable";
            }
        } else {
            [JuceBridge stopRecordingObjC];
            success = [JuceBridge reconfigurePlaybackRouteV2ObjC:output[@"name"]];
            if (!success) {
                diagnosticCode = @"juce_reopen_failed";
            } else {
                NSDictionary *snapshot = [self buildAudioRouteSnapshotV2];
                NSDictionary *juce = [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
                    ? snapshot[@"juce"] : @{};
                NSArray *outputs = [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
                    ? snapshot[@"outputs"] : @[];
                NSDictionary *actualOutput = outputs.count == 1 ? outputs.firstObject : nil;
                success = generation == self.audioRouteGenerationV2 &&
                    [MixroomEffectiveOutputFingerprint() isEqualToString:expectedFingerprint] &&
                    [snapshot[@"captureConsistency"] isEqualToString:@"stable"] &&
                    [juce[@"deviceOpen"] boolValue] &&
                    [juce[@"audioCallbackAttached"] boolValue] &&
                    [juce[@"activeInputChannels"] integerValue] == 0 &&
                    [juce[@"activeOutputChannels"] integerValue] > 0 &&
                    [juce[@"sampleRateHz"] doubleValue] > 1000.0 &&
                    [juce[@"bufferFrames"] integerValue] > 0 &&
                    [actualOutput[@"uid"] isEqualToString:output[@"uid"]];
                if (!success) diagnosticCode = @"actual_state_unavailable";
            }
        }
    }

    if (success) {
        self.currentAudioRouteIntentV2 = intent;
    } else if ([intent isEqualToString:@"preparingRecording"] &&
               ![diagnosticCode isEqualToString:@"stale_generation"]) {
        NSArray *inventory = MixroomCoreAudioDeviceInventory() ?: @[];
        NSDictionary *output = MixroomOutputForDeviceID(
            inventory, MixroomDefaultCoreAudioOutputDevice());
        if (output != nil && MixroomOutputNameIsUnique(inventory, output)) {
            [JuceBridge reconfigurePlaybackRouteV2ObjC:output[@"name"]];
        } else {
            [JuceBridge quiescePlaybackRouteV2ObjC:YES];
        }
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
    #pragma unused(args)
    return @{
        @"status": @"failure",
        @"generation": @0,
        @"transitionId": @0,
        @"diagnosticCode": @"recording_route_unsupported",
        @"elapsedMs": @0,
        @"transportWasPlaying": @NO,
        @"snapshot": [self buildAudioRouteSnapshotV2],
    };
#endif
}

- (void)updateObservedOutputDeviceV2:(uint32_t)deviceID {
#if TARGET_OS_OSX
    AudioObjectPropertyAddress aliveAddress = {
        kAudioDevicePropertyDeviceIsAlive,
        kAudioObjectPropertyScopeGlobal,
        kMixroomCoreAudioElement,
    };
    if (self.observedOutputDeviceV2 != kAudioObjectUnknown) {
        AudioObjectRemovePropertyListener(
            self.observedOutputDeviceV2,
            &aliveAddress,
            MixroomAudioRoutePropertyListenerV2,
            self);
    }
    self.observedOutputDeviceV2 = deviceID;
    if (deviceID != kAudioObjectUnknown &&
        AudioObjectHasProperty(deviceID, &aliveAddress)) {
        AudioObjectAddPropertyListener(
            deviceID,
            &aliveAddress,
            MixroomAudioRoutePropertyListenerV2,
            self);
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
    if (self.audioRouteMonitoringV2) {
        [[NSNotificationCenter defaultCenter]
            removeObserver:self
                      name:AVAudioSessionRouteChangeNotification
                    object:[AVAudioSession sharedInstance]];
        [[NSNotificationCenter defaultCenter]
            removeObserver:self
                      name:UIApplicationDidBecomeActiveNotification
                    object:nil];
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
#endif
}

#if !TARGET_OS_OSX
- (void)handleIOSAudioRouteChangeV2:(NSNotification *)notification {
    const BOOL routeNotification =
        [notification.name isEqualToString:AVAudioSessionRouteChangeNotification];
    NSNumber *reasonValue =
        routeNotification &&
        [notification.userInfo[AVAudioSessionRouteChangeReasonKey]
            isKindOfClass:[NSNumber class]]
            ? notification.userInfo[AVAudioSessionRouteChangeReasonKey]
            : nil;
    const AVAudioSessionRouteChangeReason reason = reasonValue == nil
        ? AVAudioSessionRouteChangeReasonUnknown
        : (AVAudioSessionRouteChangeReason)reasonValue.unsignedIntegerValue;
    void (^observe)(void) = ^{
        if (!self.audioRouteMonitoringV2 ||
            ![[JuceBridge getAudioRouteImplementationObjC] isEqualToString:@"v2"]) {
            return;
        }
        AVAudioSessionRouteDescription *route =
            [AVAudioSession sharedInstance].currentRoute;
        if (route == nil) {
            return;
        }
        NSString *fingerprint = MixroomIOSOutputFingerprint(route);
        if ([fingerprint isEqualToString:self.audioRouteFingerprintV2]) {
            return;
        }
        const BOOL removed =
            routeNotification &&
            reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable;
        const BOOL transportWasPlaying =
            [JuceBridge quiescePlaybackRouteV2ObjC:removed];
        self.routeTransitionWasPlayingV2 =
            self.routeTransitionWasPlayingV2 || transportWasPlaying;
        self.routeTransitionFromBluetoothV2 =
            self.routeTransitionFromBluetoothV2 ||
            self.iosObservedOutputWasBluetoothV2;
        self.audioRouteGenerationV2 += 1;
        self.audioRouteFingerprintV2 = fingerprint;
        NSDictionary<NSString *, id> *output =
            MixroomIOSSingleOutputEndpoint(route);
        self.iosObservedOutputWasBluetoothV2 =
            output != nil && MixroomIOSOutputIsBluetooth(output);
        self.iosLastObservedRouteCauseV2 = routeNotification
            ? MixroomIOSObservedRouteCause(reason)
            : @"appBecameActive";
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
        self.audioRouteFingerprintV2 = MixroomEffectiveOutputFingerprint();
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
        [self updateObservedOutputDeviceV2:MixroomDefaultCoreAudioOutputDevice()];
    }
    NSDictionary<NSString *, id> *snapshot = [self buildAudioRouteSnapshotV2];
    NSArray *outputs = [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
        ? snapshot[@"outputs"]
        : @[];
    NSDictionary *actualOutput = outputs.count == 1 ? outputs.firstObject : nil;
    NSArray<NSDictionary<NSString *, id> *> *inventory =
        MixroomCoreAudioDeviceInventory() ?: @[];
    NSDictionary<NSString *, id> *defaultOutput = MixroomOutputForDeviceID(
        inventory,
        MixroomDefaultCoreAudioOutputDevice());
    const BOOL startupRouteMatchesDefault = defaultOutput != nil &&
        actualOutput != nil &&
        [actualOutput[@"uid"] isEqualToString:defaultOutput[@"uid"]];
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
        NSString *currentFingerprint = MixroomEffectiveOutputFingerprint();
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
    NSString *fingerprint = MixroomEffectiveOutputFingerprint();
    if ([fingerprint isEqualToString:self.audioRouteFingerprintV2]) {
        return;
    }

    const AudioDeviceID previousDevice = self.observedOutputDeviceV2;
    NSArray<NSDictionary<NSString *, id> *> *inventory =
        MixroomCoreAudioDeviceInventory() ?: @[];
    const BOOL removed = previousDevice != kAudioObjectUnknown &&
        (MixroomOutputForDeviceID(inventory, previousDevice) == nil ||
         !MixroomCoreAudioDeviceIsAlive(previousDevice));
    const BOOL wasPlaying =
        [JuceBridge quiescePlaybackRouteV2ObjC:removed];
    self.routeTransitionWasPlayingV2 =
        self.routeTransitionWasPlayingV2 || wasPlaying;
    self.audioRouteGenerationV2 += 1;
    self.audioRouteFingerprintV2 = fingerprint;
    [self updateObservedOutputDeviceV2:MixroomDefaultCoreAudioOutputDevice()];

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

    NSArray<NSDictionary<NSString *, id> *> *inventory =
        MixroomCoreAudioDeviceInventory() ?: @[];
    const AudioDeviceID expectedDefault = MixroomDefaultCoreAudioOutputDevice();
    NSString *expectedFingerprint = MixroomEffectiveOutputFingerprint();
    NSDictionary<NSString *, id> *target =
        MixroomOutputForDeviceID(inventory, expectedDefault);
    const BOOL targetUsable = target != nil &&
        MixroomCoreAudioDeviceIsAlive(expectedDefault) &&
        MixroomOutputNameIsUnique(inventory, target);
    BOOL opened = targetUsable &&
        [JuceBridge reconfigurePlaybackRouteV2ObjC:target[@"name"]];
    BOOL usedFallback = NO;

    if (!opened && [args[@"allowBuiltInFallback"] boolValue]) {
        NSDictionary<NSString *, id> *fallback =
            MixroomUniqueBuiltInOutput(inventory);
        const BOOL fallbackDistinct = fallback != nil &&
            ![fallback[@"uid"] isEqualToString:target[@"uid"]];
        if (fallbackDistinct && MixroomOutputNameIsUnique(inventory, fallback)) {
            opened = [JuceBridge reconfigurePlaybackRouteV2ObjC:fallback[@"name"]];
            if (opened) {
                target = fallback;
                usedFallback = YES;
            }
        }
    }

    NSDictionary<NSString *, id> *snapshot = [self buildAudioRouteSnapshotV2];
    NSDictionary<NSString *, id> *juce =
        [snapshot[@"juce"] isKindOfClass:[NSDictionary class]]
            ? snapshot[@"juce"]
            : @{};
    NSArray *outputs = [snapshot[@"outputs"] isKindOfClass:[NSArray class]]
        ? snapshot[@"outputs"]
        : @[];
    NSDictionary *actualOutput = outputs.count == 1 ? outputs.firstObject : nil;
    NSString *actualFingerprint = MixroomEffectiveOutputFingerprint();
    NSString *diagnosticCode = @"ok";
    if (generation != self.audioRouteGenerationV2 ||
        MixroomDefaultCoreAudioOutputDevice() != expectedDefault) {
        diagnosticCode = @"stale_generation";
    } else if (![actualFingerprint isEqualToString:expectedFingerprint]) {
        diagnosticCode = @"route_unstable";
    } else if (!opened) {
        diagnosticCode = @"fallback_failed";
    } else if ([juce[@"activeInputChannels"] integerValue] != 0) {
        diagnosticCode = @"input_open";
    } else if (![juce[@"deviceOpen"] boolValue] ||
               [juce[@"activeOutputChannels"] integerValue] <= 0 ||
               outputs.count != 1) {
        diagnosticCode = @"no_output";
    } else if ([juce[@"sampleRateHz"] doubleValue] <= 1000.0 ||
               [juce[@"bufferFrames"] integerValue] <= 0 ||
               target == nil ||
               ![actualOutput[@"uid"] isEqualToString:target[@"uid"]]) {
        diagnosticCode = @"actual_state_unavailable";
    } else if (usedFallback) {
        diagnosticCode = @"fallback_succeeded";
    }

    const BOOL success = [diagnosticCode isEqualToString:@"ok"] ||
        [diagnosticCode isEqualToString:@"fallback_succeeded"];
    if (!success && ![diagnosticCode isEqualToString:@"stale_generation"]) {
        [JuceBridge quiescePlaybackRouteV2ObjC:YES];
        snapshot = [self buildAudioRouteSnapshotV2];
    } else if ([diagnosticCode isEqualToString:@"stale_generation"]) {
        [JuceBridge quiescePlaybackRouteV2ObjC:NO];
    }
    if (success) {
        self.routeTransitionWasPlayingV2 = NO;
    }
    const NSInteger elapsedMs = (NSInteger)(
        MixroomMonotonicMilliseconds() - startedAtMs + 0.5);
    return @{
        @"status": success ? (usedFallback ? @"fallback" : @"success") : @"failure",
        @"generation": @(generation),
        @"transitionId": @(transitionID),
        @"diagnosticCode": diagnosticCode,
        @"elapsedMs": @(elapsedMs),
        @"transportWasPlaying": @(transportWasPlaying),
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

    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *sessionError = nil;
    const BOOL sessionConfigured =
        MixroomConfigureIOSPlaybackSession(&sessionError);
    NSDictionary<NSString *, id> *target =
        MixroomIOSSingleOutputEndpoint(session.currentRoute);
    NSString *expectedFingerprint =
        MixroomIOSOutputFingerprint(session.currentRoute);
    NSString *diagnosticCode = @"ok";
    if (!sessionConfigured) {
        diagnosticCode = @"actual_state_unavailable";
    } else if (target == nil) {
        diagnosticCode = @"no_output";
    } else if (!MixroomIOSOutputIdentityIsObservable(target)) {
        diagnosticCode = @"actual_state_unavailable";
    } else if (MixroomIOSOutputIsBluetoothDuplex(target)) {
        diagnosticCode = @"bluetooth_duplex_forbidden";
    }

    BOOL opened = NO;
    if ([diagnosticCode isEqualToString:@"ok"] &&
        generation == self.audioRouteGenerationV2) {
        opened = [JuceBridge reconfigurePlaybackRouteV2ObjC:@""];
        if (!opened) {
            diagnosticCode = @"juce_reopen_failed";
        }
    } else if (generation != self.audioRouteGenerationV2) {
        diagnosticCode = @"stale_generation";
    }

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
        } else if (![actualFingerprint isEqualToString:expectedFingerprint] ||
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
    if (!success && ![diagnosticCode isEqualToString:@"stale_generation"]) {
        [JuceBridge quiescePlaybackRouteV2ObjC:YES];
        snapshot = [self buildAudioRouteSnapshotV2];
    } else if ([diagnosticCode isEqualToString:@"stale_generation"]) {
        [JuceBridge quiescePlaybackRouteV2ObjC:NO];
    }
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
    self.audioRouteMonitoringV2 = NO;
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

- (void)dealloc {
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
#if !TARGET_OS_OSX
        const BOOL wasV2 = [[JuceBridge getAudioRouteImplementationObjC]
            isEqualToString:@"v2"];
#endif
        [JuceBridge shutdownEngineObjC];
#if TARGET_OS_OSX
        [self restoreBluetoothPlaybackAfterRecordingStop];
#else
        if (!wasV2) {
            [self restoreBluetoothPlaybackAfterRecordingStop];
        }
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setActive:NO error:nil];
#endif
        result(nil);

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
        FlutterResult loadResult = [result copy];
        dispatch_async(MixroomMidiClipLoadQueue(), ^{
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
            dispatch_async(dispatch_get_main_queue(), ^{
                loadResult(@(ok));
            });
        });
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
        result(MixroomMacInputDeviceInfos());
#else
        NSMutableArray *infos = [NSMutableArray array];
        for (NSString *name in [JuceBridge getInputDevicesObjC]) {
            [infos addObject:@{
                @"name": name ?: @"",
                @"isBluetoothInput": @NO,
                @"isBuiltIn": @NO,
                @"isDefault": @NO,
                @"transport": @"unknown",
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
        result([self initialisePlaybackV2]);
    }
    else if ([call.method isEqualToString:@"startAudioRouteMonitoringV2"]) {
        result([self startAudioRouteMonitoringV2]);
    }
    else if ([call.method isEqualToString:@"applyAudioRouteConfigurationV2"]) {
        result([self applyAudioRouteConfigurationV2:args ?: @{}]);
    }
    else if ([call.method isEqualToString:@"setAudioRouteIntentV2"]) {
        result([self setAudioRouteIntentV2:args ?: @{}]);
    }
    else if ([call.method isEqualToString:@"abortRecordingV2"]) {
#if TARGET_OS_OSX
        if ([[JuceBridge getAudioRouteImplementationObjC] isEqualToString:@"v2"]) {
            [JuceBridge stopRecordingObjC];
            [JuceBridge quiescePlaybackRouteV2ObjC:YES];
            self.currentAudioRouteIntentV2 = @"playbackOnly";
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
        result(@([JuceBridge startRecordingObjC:args[@"path"]
                                channelStart:[args[@"channelStart"] integerValue]
                                channelCount:[args[@"channelCount"] integerValue]]));
    }
    else if ([call.method isEqualToString:@"stopRecording"]) {
        [JuceBridge stopRecordingObjC];
        result(nil);
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
