#include <float.h>
#import "JuceBridge.h"
#import "JuceEngine.h"
#include "InstrumentRenderers.h"
#include "JuceHeader.h"
#import "JuceAudioEnginePlugin.h" // To access debugLogChannel
#import <TargetConditionals.h>
#if __has_include(<Flutter/Flutter.h>)
#import <Flutter/Flutter.h>
#elif __has_include(<FlutterMacOS/FlutterMacOS.h>)
#import <FlutterMacOS/FlutterMacOS.h>
#endif
#if TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#endif
#import <onnxruntime_objc/ort_env.h>
#import <onnxruntime_objc/ort_session.h>
#import <onnxruntime_objc/ort_value.h>
#if __has_include(<onnxruntime_objc/ort_session_internal.h>)
#import <onnxruntime_objc/ort_session_internal.h>
#define MIXROOM_ORT_HAS_INTERNAL_SESSION_OPTIONS 1
#elif __has_include("ort_session_internal.h")
#import "ort_session_internal.h"
#define MIXROOM_ORT_HAS_INTERNAL_SESSION_OPTIONS 1
#else
#define MIXROOM_ORT_HAS_INTERNAL_SESSION_OPTIONS 0
#endif

#if TARGET_OS_OSX
static NSString *const MixroomHostedPluginEditorSpacebarNotification =
    @"MixroomHostedPluginEditorSpacebarNotification";
static NSString *const MixroomHostedPluginEditorAutomationNotification =
    @"MixroomHostedPluginEditorAutomationNotification";
static const void *kMixroomHostedPluginWindowHelperKey =
    &kMixroomHostedPluginWindowHelperKey;
static BOOL gMixroomHostedPluginWindowsDetached = NO;
extern "C" void mixroomSetHostedPluginWindowsDetached(BOOL detached);
extern "C" void mixroomRequestHostedPluginEditorClose(void *ownerHandle);
extern "C" void mixroomSetHostedPluginWindowDetachedForOwner(void *ownerHandle,
                                                             bool detached);

@interface MixroomHostedPluginWindowHelper : NSObject
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, strong) id eventMonitor;
@property(nonatomic, strong) id closeObserver;
@property(nonatomic, copy) NSDictionary<NSString *, id> *metadata;
- (instancetype)initWithWindow:(NSWindow *)window
                      metadata:(NSDictionary<NSString *, id> *)metadata;
- (void)applyWindowMode;
@end

@implementation MixroomHostedPluginWindowHelper

- (instancetype)initWithWindow:(NSWindow *)window
                      metadata:(NSDictionary<NSString *, id> *)metadata {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _window = window;
    _metadata = [metadata copy];
    __weak MixroomHostedPluginWindowHelper *weakSelf = self;
    _closeObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSWindowWillCloseNotification
                    object:window
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification * _Nonnull note) {
                    MixroomHostedPluginWindowHelper *strongSelf = weakSelf;
                    if (strongSelf == nil) {
                        return;
                    }
                    if (strongSelf.eventMonitor != nil) {
                        [NSEvent removeMonitor:strongSelf.eventMonitor];
                        strongSelf.eventMonitor = nil;
                    }
                    if (strongSelf.window.parentWindow != nil) {
                        [strongSelf.window.parentWindow removeChildWindow:strongSelf.window];
                    }
                    NSMutableDictionary<NSString *, id> *payload =
                        [NSMutableDictionary dictionaryWithDictionary:strongSelf.metadata ?: @{}];
                    payload[@"event"] = @"pluginEditorClosed";
                    dispatch_after(
                        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{
                          [[NSNotificationCenter defaultCenter]
                              postNotificationName:MixroomHostedPluginEditorSpacebarNotification
                                            object:nil
                                          userInfo:payload];
                        });
                }];
    _eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:
        (NSEventMaskKeyDown |
         NSEventMaskRightMouseDown |
         NSEventMaskOtherMouseDown |
         NSEventMaskLeftMouseDown)
        handler:^NSEvent * _Nullable(NSEvent *event) {
            MixroomHostedPluginWindowHelper *strongSelf = weakSelf;
            if (strongSelf == nil || strongSelf.window == nil) {
                return event;
            }
            const BOOL targetsWindow =
                event.window == strongSelf.window ||
                (event.window != nil &&
                 event.window.parentWindow == strongSelf.window) ||
                (strongSelf.window.parentWindow != nil &&
                 event.window == strongSelf.window.parentWindow &&
                 strongSelf.window.isKeyWindow);
            if (!targetsWindow && !strongSelf.window.isKeyWindow) {
                return event;
            }
            if (event.type == NSEventTypeKeyDown &&
                event.keyCode == 49 &&
                (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask) == 0) {
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:MixroomHostedPluginEditorSpacebarNotification
                                  object:nil
                                userInfo:@{ @"event": @"pluginEditorSpacebar" }];
                return nil;
            }
            if (event.type == NSEventTypeKeyDown && event.keyCode == 53) {
                const uintptr_t ownerValue =
                    (uintptr_t)[strongSelf.metadata[@"ownerPtr"] unsignedLongLongValue];
                if (ownerValue != 0) {
                    mixroomRequestHostedPluginEditorClose((void *)ownerValue);
                }
                return nil;
            }
            const NSEventModifierFlags deviceIndependentModifiers =
                (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
            const BOOL isSecondaryClick =
                (event.type == NSEventTypeRightMouseDown) ||
                (event.type == NSEventTypeOtherMouseDown) ||
                (event.type == NSEventTypeLeftMouseDown &&
                 (deviceIndependentModifiers & NSEventModifierFlagControl) != 0);
            if (isSecondaryClick) {
                NSView *contentView = strongSelf.window.contentView;
                const NSInteger scopeKind =
                    [strongSelf.metadata[@"scopeKind"] integerValue];
                const NSInteger row = [strongSelf.metadata[@"row"] integerValue];
                const NSInteger effectIndex =
                    [strongSelf.metadata[@"effectIndex"] integerValue];
                const NSInteger clipId =
                    [strongSelf.metadata[@"clipId"] integerValue];
                if (contentView != nil) {
                    const NSPoint contentPoint =
                        [contentView convertPoint:event.locationInWindow fromView:nil];
                    const HostedPluginEditorMetadata metadata = {
                        static_cast<HostedPluginEditorScopeKind>(scopeKind),
                        (int)row,
                        (int)effectIndex,
                        (int)clipId,
                    };
                    if (JuceEngine::get().showHostedPluginAutomationContextMenu(
                            metadata,
                            (int)contentPoint.x,
                            (int)contentPoint.y)) {
                        return nil;
                    }
                }
            }
            return event;
        }];
    return self;
}

- (NSWindow *)mixroomHostWindow {
    NSWindow *window = self.window;
    if (window == nil) {
        return nil;
    }
    NSWindow *parent = window.parentWindow;
    if (parent != nil) {
        return parent;
    }
    for (NSWindow *candidate in NSApp.orderedWindows) {
        if (candidate == window) {
            continue;
        }
        if ([candidate.contentViewController isKindOfClass:NSClassFromString(@"FlutterViewController")]) {
            return candidate;
        }
    }
    for (NSWindow *candidate in NSApp.windows) {
        if (candidate == window) {
            continue;
        }
        if ([candidate.contentViewController isKindOfClass:NSClassFromString(@"FlutterViewController")]) {
            return candidate;
        }
    }
    return NSApp.mainWindow ?: NSApp.keyWindow;
}

- (void)applyWindowMode {
    NSWindow *pluginWindow = self.window;
    if (pluginWindow == nil) {
        return;
    }

    pluginWindow.releasedWhenClosed = NO;
    pluginWindow.titleVisibility = NSWindowTitleHidden;
    pluginWindow.titlebarAppearsTransparent = YES;
    pluginWindow.movableByWindowBackground = NO;
    pluginWindow.toolbar = nil;
    pluginWindow.level = NSNormalWindowLevel;
    pluginWindow.collectionBehavior = NSWindowCollectionBehaviorManaged;

    NSButton *closeButton =
        [pluginWindow standardWindowButton:NSWindowCloseButton];
    NSButton *miniButton =
        [pluginWindow standardWindowButton:NSWindowMiniaturizeButton];
    NSButton *zoomButton =
        [pluginWindow standardWindowButton:NSWindowZoomButton];

    NSWindow *hostWindow = [self mixroomHostWindow];
    if (gMixroomHostedPluginWindowsDetached) {
        if (pluginWindow.parentWindow != nil) {
            [pluginWindow.parentWindow removeChildWindow:pluginWindow];
        }
        pluginWindow.styleMask |= NSWindowStyleMaskTitled;
        pluginWindow.styleMask |= NSWindowStyleMaskResizable;
        pluginWindow.styleMask |= NSWindowStyleMaskClosable;
        pluginWindow.styleMask &= ~NSWindowStyleMaskFullSizeContentView;
        closeButton.hidden = YES;
        miniButton.hidden = YES;
        zoomButton.hidden = YES;
        return;
    }

    pluginWindow.styleMask |= NSWindowStyleMaskTitled;
    pluginWindow.styleMask |= NSWindowStyleMaskClosable;
    pluginWindow.styleMask |= NSWindowStyleMaskResizable;
    pluginWindow.styleMask |= NSWindowStyleMaskFullSizeContentView;
    closeButton.hidden = YES;
    miniButton.hidden = YES;
    zoomButton.hidden = YES;

    if (hostWindow != nil && pluginWindow.parentWindow != hostWindow) {
        if (pluginWindow.parentWindow != nil) {
            [pluginWindow.parentWindow removeChildWindow:pluginWindow];
        }
        [hostWindow addChildWindow:pluginWindow ordered:NSWindowAbove];
    }

    if (hostWindow != nil) {
        const NSRect hostRect = hostWindow.contentLayoutRect;
        NSRect frame = pluginWindow.frame;
        const CGFloat maxWidth = MAX(320.0, hostRect.size.width - 80.0);
        const CGFloat maxHeight = MAX(220.0, hostRect.size.height - 80.0);
        frame.size.width = MIN(frame.size.width, maxWidth);
        frame.size.height = MIN(frame.size.height, maxHeight);
        if (!NSIntersectsRect(frame, hostRect)) {
            frame.origin.x =
                NSMidX(hostRect) - (frame.size.width / 2.0);
            frame.origin.y =
                NSMidY(hostRect) - (frame.size.height / 2.0);
        }
        frame.origin.x = MIN(MAX(frame.origin.x, NSMinX(hostRect)),
                             NSMaxX(hostRect) - frame.size.width);
        frame.origin.y = MIN(MAX(frame.origin.y, NSMinY(hostRect)),
                             NSMaxY(hostRect) - frame.size.height);
        [pluginWindow setFrame:frame display:YES];
    }
}

- (void)dealloc {
    if (_eventMonitor != nil) {
        [NSEvent removeMonitor:_eventMonitor];
    }
    if (_closeObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:_closeObserver];
    }
}

@end

extern "C" void mixroomConfigureHostedPluginWindow(void *nativeHandle,
                                                    int scopeKind,
                                                    int row,
                                                    int effectIndex,
                                                    int clipId,
                                                    void *ownerHandle) {
    if (nativeHandle == nullptr) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSView *nativeView = (__bridge NSView *)nativeHandle;
        NSWindow *pluginWindow = nativeView.window;
        if (pluginWindow == nil) {
            return;
        }

        NSMutableDictionary<NSString *, id> *metadata = [NSMutableDictionary dictionary];
        metadata[@"scopeKind"] = @(scopeKind);
        metadata[@"row"] = @(row);
        metadata[@"effectIndex"] = @(effectIndex);
        metadata[@"clipId"] = @(clipId);
        metadata[@"ownerPtr"] = @((unsigned long long)(uintptr_t)ownerHandle);
        switch (scopeKind) {
            case 1:
                metadata[@"scope"] = @"track_fx";
                break;
            case 2:
                metadata[@"scope"] = @"master_fx";
                break;
            case 3:
                metadata[@"scope"] = @"midi_clip";
                break;
            default:
                metadata[@"scope"] = @"unknown";
                break;
        }

        pluginWindow.releasedWhenClosed = NO;

        MixroomHostedPluginWindowHelper *helper =
            [[MixroomHostedPluginWindowHelper alloc] initWithWindow:pluginWindow
                                                           metadata:metadata];
        [helper applyWindowMode];
        objc_setAssociatedObject(
            pluginWindow,
            kMixroomHostedPluginWindowHelperKey,
            helper,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

extern "C" void mixroomSetHostedPluginWindowsDetached(BOOL detached) {
    gMixroomHostedPluginWindowsDetached = detached;
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSWindow *window in NSApp.windows) {
            MixroomHostedPluginWindowHelper *helper =
                (MixroomHostedPluginWindowHelper *)objc_getAssociatedObject(
                    window,
                    kMixroomHostedPluginWindowHelperKey);
            if (helper != nil) {
                [helper applyWindowMode];
            }
        }
    });
}

extern "C" void mixroomRequestHostedPluginEditorClose(void *ownerHandle) {
    if (ownerHandle == nullptr) {
        return;
    }
    juce::MessageManager::callAsync([safeWindow = juce::Component::SafePointer<HostedPluginEditorWindow>(
                                         reinterpret_cast<HostedPluginEditorWindow *>(ownerHandle))]() mutable {
        if (safeWindow == nullptr) {
            return;
        }
        safeWindow->requestCloseFromHost();
    });
}

extern "C" void mixroomSetHostedPluginWindowDetachedForOwner(void *ownerHandle,
                                                             bool detached) {
    juce::ignoreUnused(ownerHandle, detached);
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSWindow *window in NSApp.windows) {
            MixroomHostedPluginWindowHelper *helper =
                (MixroomHostedPluginWindowHelper *)objc_getAssociatedObject(
                    window,
                    kMixroomHostedPluginWindowHelperKey);
            if (helper == nil) {
                continue;
            }
            const uintptr_t ownerValue =
                (uintptr_t)[helper.metadata[@"ownerPtr"] unsignedLongLongValue];
            if (ownerValue != (uintptr_t)ownerHandle) {
                continue;
            }
            if (detached) {
                if (window.parentWindow != nil) {
                    [window.parentWindow removeChildWindow:window];
                }
            } else {
                [helper applyWindowMode];
            }
            return;
        }
    });
}
#else
extern "C" void mixroomConfigureHostedPluginWindow(void *nativeHandle,
                                                    int scopeKind,
                                                    int row,
                                                    int effectIndex,
                                                    int clipId,
                                                    void *ownerHandle) {
    juce::ignoreUnused(
        nativeHandle,
        scopeKind,
        row,
        effectIndex,
        clipId,
        ownerHandle);
}

extern "C" void mixroomSetHostedPluginWindowsDetached(BOOL detached) {
    juce::ignoreUnused(detached);
}

extern "C" void mixroomRequestHostedPluginEditorClose(void *ownerHandle) {
    juce::ignoreUnused(ownerHandle);
}

extern "C" void mixroomSetHostedPluginWindowDetachedForOwner(void *ownerHandle,
                                                             bool detached) {
    juce::ignoreUnused(ownerHandle, detached);
}
#endif

#if TARGET_OS_OSX
extern "C" void mixroomPostHostedPluginAutomationSelection(
    int scopeKind,
    int row,
    int effectIndex,
    int clipId,
    const char *paramId,
    const char *paramName) {
    NSMutableDictionary<NSString *, id> *payload = [NSMutableDictionary dictionary];
    payload[@"event"] = @"pluginEditorAutomationRequest";
    payload[@"scopeKind"] = @(scopeKind);
    payload[@"row"] = @(row);
    payload[@"effectIndex"] = @(effectIndex);
    payload[@"clipId"] = @(clipId);
    payload[@"paramId"] = [NSString stringWithUTF8String:paramId != nullptr ? paramId : ""] ?: @"";
    payload[@"paramName"] =
        [NSString stringWithUTF8String:paramName != nullptr ? paramName : ""] ?: @"";
    switch (scopeKind) {
        case 1:
            payload[@"scope"] = @"track_fx";
            break;
        case 2:
            payload[@"scope"] = @"master_fx";
            break;
        case 3:
            payload[@"scope"] = @"midi_clip";
            break;
        default:
            payload[@"scope"] = @"unknown";
            break;
    }
    [[NSNotificationCenter defaultCenter]
        postNotificationName:MixroomHostedPluginEditorAutomationNotification
                      object:nil
                    userInfo:payload];
}
#else
extern "C" void mixroomPostHostedPluginAutomationSelection(
    int scopeKind,
    int row,
    int effectIndex,
    int clipId,
    const char *paramId,
    const char *paramName) {
    juce::ignoreUnused(
        scopeKind,
        row,
        effectIndex,
        clipId,
        paramId,
        paramName);
}
#endif

namespace
{
juce::String juceStringFromNSString(NSString *value)
{
    if (value == nil)
        return {};
    const char *utf8 = [value UTF8String];
    return utf8 != nullptr ? juce::String::fromUTF8(utf8) : juce::String();
}

juce::File juceFileFromNSString(NSString *value)
{
    return juce::File(juceStringFromNSString(value));
}

juce::Array<TimelineMidiNote> parseTimelineMidiNotes(NSArray<NSDictionary *> *notes)
{
    juce::Array<TimelineMidiNote> parsed;
    if (notes == nil)
        return parsed;

    parsed.ensureStorageAllocated((int)notes.count);
    for (NSDictionary *d in notes)
    {
        TimelineMidiNote note;
        id noteIdV = d[@"id"];
        id pitchV = d[@"pitch"];
        id startV = d[@"startBeat"];
        id lenV = d[@"lengthBeats"];
        id velV = d[@"velocity"];

        if ([noteIdV isKindOfClass:[NSString class]])
            note.noteId = juce::String::fromUTF8([(NSString *)noteIdV UTF8String]);
        if ([pitchV respondsToSelector:@selector(intValue)])
            note.pitch = (int)[pitchV intValue];
        if ([startV respondsToSelector:@selector(doubleValue)])
            note.startBeat = [startV doubleValue];
        if ([lenV respondsToSelector:@selector(doubleValue)])
            note.lengthBeats = [lenV doubleValue];
        if ([velV respondsToSelector:@selector(doubleValue)])
            note.velocity = [velV doubleValue];

        parsed.add(note);
    }
    return parsed;
}

juce::NamedValueSet parseMidiParams(NSDictionary<NSString *, NSNumber *> *params)
{
    juce::NamedValueSet parsed;
    if (params == nil)
        return parsed;

    for (NSString *key in params)
    {
        id raw = params[key];
        if (raw == nil || raw == [NSNull null])
            continue;
        if (![raw respondsToSelector:@selector(doubleValue)])
            continue;

        const juce::String juceKey = juce::String::fromUTF8([key UTF8String]);
        parsed.set(juce::Identifier(juceKey), juce::var((double)[raw doubleValue]));
    }

    return parsed;
}

NSDictionary<NSString *, NSNumber *> *namedValueStatsToNSDictionary(const juce::NamedValueSet &stats)
{
    NSMutableDictionary<NSString *, NSNumber *> *out = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)stats.size()];
    for (int i = 0; i < stats.size(); ++i)
    {
        const auto key = stats.getName(i).toString();
        const auto value = (double)stats.getValueAt(i);
        out[[NSString stringWithUTF8String:key.toRawUTF8()] ?: @""] = @(value);
    }
    return out;
}

NSDictionary<NSString *, NSNumber *> *fallbackPromptRoleProbs()
{
    return @{
        @"vocals" : @0.17,
        @"drums" : @0.17,
        @"bass" : @0.17,
        @"guitar" : @0.17,
        @"synth" : @0.16,
        @"other" : @0.16,
    };
}

NSDictionary<NSString *, NSNumber *> *normalizePromptRoleProbs(NSDictionary<NSString *, NSNumber *> *raw)
{
    double sum = 0.0;
    for (NSNumber *value in raw.objectEnumerator)
        sum += value.doubleValue;

    if (sum <= 0.0)
        return fallbackPromptRoleProbs();

    NSMutableDictionary<NSString *, NSNumber *> *out = [NSMutableDictionary dictionaryWithCapacity:raw.count];
    [raw enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *value, BOOL *stop) {
        out[key] = @(value.doubleValue / sum);
    }];
    return out;
}

NSString *yamnetModelPath()
{
    NSString *assetKey = [FlutterDartProject lookupKeyForAsset:@"assets/models/yamnet.onnx"];
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:assetKey ofType:nil];
    if (bundlePath != nil)
        return bundlePath;

    NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
    NSString *fallback = [resourcePath stringByAppendingPathComponent:assetKey];
    if ([[NSFileManager defaultManager] fileExistsAtPath:fallback])
        return fallback;

    return nil;
}
} // namespace

@interface MixroomPromptAnalysisService : NSObject
+ (instancetype)sharedService;
- (NSDictionary<NSString *, NSNumber *> *)classifyWindows:(const std::vector<std::vector<float>> &)windows;
@end

@implementation MixroomPromptAnalysisService
{
    NSLock *_lock;
    ORTEnv *_env;
    ORTSession *_session;
    NSString *_inputName;
    NSString *_outputName;
}

static NSString *const kMixroomYamnetScoresOutputName = @"output_0";

+ (instancetype)sharedService
{
    static MixroomPromptAnalysisService *service = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      service = [[MixroomPromptAnalysisService alloc] init];
    });
    return service;
}

- (instancetype)init
{
    self = [super init];
    if (self != nil)
        _lock = [[NSLock alloc] init];
    return self;
}

- (BOOL)ensureSession
{
    [_lock lock];
    @try
    {
        if (_session != nil)
            return YES;

        NSError *error = nil;
        if (_env == nil)
        {
            _env = [[ORTEnv alloc] initWithLoggingLevel:ORTLoggingLevelWarning error:&error];
            if (_env == nil || error != nil)
            {
                NSLog(@"[MixroomPromptAnalysis] Failed to create ORTEnv: %@", error);
                return NO;
            }
        }

        NSString *modelPath = yamnetModelPath();
        if (modelPath == nil)
        {
            NSLog(@"[MixroomPromptAnalysis] Could not resolve yamnet model path");
            return NO;
        }

        ORTSessionOptions *options = [[ORTSessionOptions alloc] initWithError:&error];
        if (options == nil || error != nil)
        {
            NSLog(@"[MixroomPromptAnalysis] Failed to create session options: %@", error);
            return NO;
        }

        if (![options setIntraOpNumThreads:1 error:&error] || error != nil)
        {
            NSLog(@"[MixroomPromptAnalysis] Failed to set intra-op threads: %@", error);
            return NO;
        }
#if MIXROOM_ORT_HAS_INTERNAL_SESSION_OPTIONS
        // Best effort parity with Android to avoid thread oversubscription.
        [options CXXAPIOrtSessionOptions].SetInterOpNumThreads(1);
#endif

        _session = [[ORTSession alloc] initWithEnv:_env modelPath:modelPath sessionOptions:options error:&error];
        if (_session == nil || error != nil)
        {
            NSLog(@"[MixroomPromptAnalysis] Failed to create session modelPath=%@: %@", modelPath, error);
            return NO;
        }

        NSArray<NSString *> *inputNames = [_session inputNamesWithError:&error];
        if (inputNames.count == 0 || error != nil)
        {
            NSLog(@"[MixroomPromptAnalysis] Failed to read input names: %@", error);
            return NO;
        }
        NSArray<NSString *> *outputNames = [_session outputNamesWithError:&error];
        if (outputNames.count == 0 || error != nil)
        {
            NSLog(@"[MixroomPromptAnalysis] Failed to read output names: %@", error);
            return NO;
        }

        _inputName = inputNames.firstObject;
        _outputName = [outputNames containsObject:kMixroomYamnetScoresOutputName]
                          ? kMixroomYamnetScoresOutputName
                          : outputNames.firstObject;
        return YES;
    }
    @finally
    {
        [_lock unlock];
    }
}

- (BOOL)runWindow:(const std::vector<float> &)window
        scoresOut:(std::vector<double> &)scoresOut
{
    if (window.empty() || ![self ensureSession])
        return NO;

    [_lock lock];
    @try
    {
        NSError *error = nil;
        NSMutableData *tensorData = [NSMutableData dataWithBytes:window.data()
                                                          length:window.size() * sizeof(float)];
        ORTValue *inputValue = [[ORTValue alloc] initWithTensorData:tensorData
                                                        elementType:ORTTensorElementDataTypeFloat
                                                              shape:@[ @((NSInteger)window.size()) ]
                                                              error:&error];
        if (inputValue == nil || error != nil)
        {
            NSLog(@"[MixroomPromptAnalysis] Failed to create input tensor: %@", error);
            return NO;
        }

        NSDictionary<NSString *, ORTValue *> *outputs =
            [_session runWithInputs:@{ _inputName : inputValue }
                        outputNames:[NSSet setWithObject:_outputName]
                         runOptions:nil
                              error:&error];
        if (outputs == nil || error != nil)
        {
            NSLog(@"[MixroomPromptAnalysis] Session run failed output=%@: %@", _outputName, error);
            return NO;
        }

        ORTValue *outputValue = outputs[_outputName];
        if (outputValue == nil)
        {
            NSLog(@"[MixroomPromptAnalysis] Missing output tensor for %@", _outputName);
            return NO;
        }

        NSMutableData *outputData = [outputValue tensorDataWithError:&error];
        if (outputData == nil || error != nil || outputData.length == 0)
        {
            NSLog(@"[MixroomPromptAnalysis] Failed to read output tensor data output=%@ error=%@", _outputName, error);
            return NO;
        }

        const float *values = (const float *)outputData.bytes;
        const NSUInteger count = outputData.length / sizeof(float);
        scoresOut.assign(count, 0.0);
        for (NSUInteger i = 0; i < count; ++i)
            scoresOut[(size_t)i] = (double)values[i];
        return YES;
    }
    @finally
    {
        [_lock unlock];
    }
}

- (NSDictionary<NSString *, NSNumber *> *)classifyWindows:(const std::vector<std::vector<float>> &)windows
{
    if (windows.empty())
    {
        NSLog(@"[MixroomPromptAnalysis] No windows available for classification");
        return fallbackPromptRoleProbs();
    }

    std::vector<double> accum;
    int used = 0;

    for (const auto &window : windows)
    {
        std::vector<double> scores;
        if (![self runWindow:window scoresOut:scores] || scores.empty())
            continue;

        if (accum.empty())
            accum.assign(scores.size(), 0.0);

        const size_t count = (size_t)juce::jmin((int)accum.size(), (int)scores.size());
        for (size_t i = 0; i < count; ++i)
            accum[i] += scores[i];
        used++;
    }

    if (accum.empty() || used <= 0)
    {
        NSLog(@"[MixroomPromptAnalysis] No usable YAMNet windows used=%d", used);
        return fallbackPromptRoleProbs();
    }

    for (double &value : accum)
        value /= (double)used;

    double vocals = 0.0;
    double guitar = 0.0;
    double bass = 0.0;
    double drums = 0.0;
    double synth = 0.0;

    for (size_t i = 0; i < accum.size(); ++i)
    {
        const double score = accum[i];
        if (i == 135 || i == 136 || i == 138 || i == 141)
            guitar += score;
        if (i == 137)
            bass += score;
        if (i >= 156 && i <= 168)
            drums += score;
        if (i == 0 || i == 24 || i == 31 || i == 249)
            vocals += score;
        if (i == 153 || i == 147 || i == 148)
            synth += score;
    }

    NSDictionary<NSString *, NSNumber *> *normalized = normalizePromptRoleProbs(@{
        @"vocals" : @(vocals),
        @"guitar" : @(guitar),
        @"bass" : @(bass),
        @"drums" : @(drums),
        @"synth" : @(synth),
        @"other" : @0.01,
    });
    NSLog(@"[MixroomPromptAnalysis] Classified %d windows roleProbs=%@", used, normalized);
    return normalized;
}

@end

@implementation JuceBridge

+ (void)setFlutterAssetRootObjC:(NSString *)rootPath
{
    const juce::String jucePath = juceStringFromNSString(rootPath).trim();
    TimelineMidiClipProcessor::setFlutterAssetRootPath(jucePath);
}

+ (void)initialiseEngineObjC
{
    // JuceEngine& engine = JuceEngine::get();
    // engine.initialiseEngine();
    // JuceEngine& engine = JuceEngine::get(); // 💥 Forces constructor immediately
    // juce::MessageManager::callAsync([&engine] {
    //     engine.initialiseEngine(); // Safe to call async now
    // });
    // JuceEngine::get().initialiseEngine();
    // juce::MessageManager::callAsync([] {
    //     JuceEngine::get().initialiseEngine();
    // });
    JuceEngine &engine = JuceEngine::get(); // Constructor runs here
    engine.initialiseEngine();              // on main thread! don't do async or diff thread
    // std::thread([&engine] {
    //     engine.initialiseEngine();
    // }).detach();
}

+ (void)initializeMessageManager
{
    static bool initialized = false;
    if (!initialized)
    {
        juce::MessageManager::getInstance();
        initialized = true;
    }
}

+ (void)shutdownEngineObjC
{
    // juceLogToFlutter("🔻 JuceBridge: shutdownEngineObjC called");
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().shutdownEngine(); });
}

// DEPRECATED: use loadClipObjC:rowId:path:startSec:lengthSec:inFileOffsetSec: instead
+ (void)loadTrackObjC:(NSInteger)idx path:(NSString *)path
{

    // [[JuceAudioEnginePlugin sharedInstance] sendFlutterLog:@"✅ Objective-C: Entering loadTrackObjC"];

    // juce::String jucePath = juceStringFromNSString(path);
    // juce::MessageManager::callAsync([idx, jucePath] {
    //     JuceEngine::get().loadTrack((int)idx, juce::File(jucePath));
    // });
    juce::String jucePath = juceStringFromNSString(path);

    JuceEngine::get().loadTrack((int)idx, juce::File(jucePath)); // CALL DIRECTLY!
}

+ (void)playObjC
{
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().play(); });
}

+ (void)pauseObjC
{
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().pause(); });
}

+ (void)removeTrackObjC:(NSInteger)trackIndex
{
    juce::MessageManager::callAsync([trackIndex]
                                    { JuceEngine::get().removeTrack((int)trackIndex); });
}

+ (NSArray<NSString *> *)getTrackEffectsObjC:(NSInteger)trackIndex
{
    auto names = JuceEngine::get().getTrackEffects((int)trackIndex);
    NSMutableArray *out = [NSMutableArray array];
    for (auto &s : names)
        [out addObject:[NSString stringWithUTF8String:s.toRawUTF8()]];
    return out;
}

+ (void)removeEffectObjC:(NSInteger)trackIndex effectIndex:(NSInteger)effectIndex
{
    juce::MessageManager::callAsync([trackIndex, effectIndex]
                                    { JuceEngine::get().removePluginEffect((int)trackIndex, (int)effectIndex); });
}

+ (void)reorderEffectsObjC:(NSInteger)trackIndex
                 fromIndex:(NSInteger)fromIdx
                   toIndex:(NSInteger)toIdx
{
    juce::MessageManager::callAsync([trackIndex, fromIdx, toIdx]
                                    { JuceEngine::get().reorderPluginEffects((int)trackIndex, (int)fromIdx, (int)toIdx); });
}

+ (void)seekObjC:(NSInteger)trackIndex position:(double)seconds
{
    juce::MessageManager::callAsync([trackIndex, seconds]
                                    { JuceEngine::get().seek((int)trackIndex, seconds); });
}

+ (double)getCurrentPositionObjC:(NSInteger)trackIndex
{
    std::atomic<double> result{0.0};
    juce::MessageManager::getInstance()->callSync([trackIndex, &result]
                                                  { result = JuceEngine::get().getCurrentPosition((int)trackIndex); });
    return result.load();
}

+ (double)getTrackDurationObjC:(NSInteger)trackIndex
{
    std::atomic<double> result{0.0};
    juce::MessageManager::getInstance()->callSync([trackIndex, &result]
                                                  { result = JuceEngine::get().getTrackDuration((int)trackIndex); });
    return result.load();
}

+ (void)insertEffectObjC:(NSInteger)track path:(NSString *)pluginPath
{
    juce::String jucePath = juceStringFromNSString(pluginPath);

    // Remove juce::MessageManager::callAsync here!
    // Let JuceEngine::insertPluginEffect handle threading internally.
    JuceEngine::get().insertPluginEffect(
        (int)track,
        jucePath,
        [track, pluginPath](bool success) { // Add callback
            // Notify Flutter via event channel
            [[NSNotificationCenter defaultCenter] postNotificationName:@"JUCEPluginLoaded"
                                                                object:nil
                                                              userInfo:@{
                                                                  @"event" : @"pluginLoaded",
                                                                  @"track" : @(track),
                                                                  @"path" : pluginPath,
                                                                  @"success" : @(success)
                                                              }];
        });
}

// DEPRECATED: use setEffectObjC-style APIs that are track/row/master specific
+ (void)setEffectObjC:(NSInteger)track
          pluginIndex:(NSInteger)pindex
              paramId:(NSString *)param
                value:(id)value
{
    juce::var newVal;
    if ([value isKindOfClass:[NSNumber class]])
    {
        const char *t = [(NSNumber *)value objCType];
        if (strcmp(t, @encode(BOOL)) == 0)
            newVal = (bool)[(NSNumber *)value boolValue];
        else if (strcmp(t, @encode(int)) == 0 || strcmp(t, @encode(NSInteger)) == 0)
            newVal = (int)[(NSNumber *)value integerValue];
        else
            newVal = (float)[(NSNumber *)value floatValue];
    }
    else if ([value isKindOfClass:[NSString class]])
    {
        newVal = juceStringFromNSString((NSString *)value);
    }

    juce::String juceParam = juceStringFromNSString(param);
    juce::MessageManager::callAsync([track, pindex, juceParam, newVal]
                                    { JuceEngine::get().setEffectParameter((int)track, (int)pindex, juceParam, newVal); });
}

+ (void)setTrackVolumeObjC:(NSInteger)track volume:(float)v
{
    juce::MessageManager::callAsync([track, v]
                                    { JuceEngine::get().setTrackVolume((int)track, v); });
}

+ (NSArray<NSDictionary *> *)getPluginParametersObjC:(NSInteger)track
                                         effectIndex:(NSInteger)effect
{
    __unsafe_unretained NSMutableArray *__result = nil;

    juce::MessageManager::getInstance()->callSync([track, effect, &__result]
                                                  {
        NSMutableArray* arr = [NSMutableArray array];
        auto list = JuceEngine::get().getPluginParameterInfo((int)track, (int)effect);
        for (auto& e : list) {
            const char* cid   = e["id"].toString().toRawUTF8();
            const char* cname = e["name"].toString().toRawUTF8();
            const char* ctype = e["type"].toString().toRawUTF8();

            NSMutableDictionary* d = [NSMutableDictionary dictionary];
            d[@"id"]   = [NSString stringWithUTF8String:cid] ?: @"";
            d[@"name"] = [NSString stringWithUTF8String:cname] ?: @"";
            d[@"type"] = [NSString stringWithUTF8String:ctype] ?: @"";
            if (e.contains("unit"))
            {
                const char* cunit = e["unit"].toString().toRawUTF8();
                d[@"unit"] = [NSString stringWithUTF8String:cunit] ?: @"";
            }
            if (e.contains("min"))     d[@"min"] = @(static_cast<float>(e["min"]));
            if (e.contains("max"))     d[@"max"] = @(static_cast<float>(e["max"]));

            auto extractVar = ^(const juce::var& v) {
                if (v.isBool())
                    return (id)@(static_cast<bool>(v));
                else if (v.isDouble() || v.isInt())
                    return (id)@(static_cast<float>(v));
                else {
                    auto s = v.toString();
                    return (id)([NSString stringWithUTF8String:s.toRawUTF8()] ?: @"");
                }
            };
            if (e.contains("default")) {
                juce::var defVar = e["default"];
                d[@"defaultValue"] = extractVar(defVar);
            }
            if (e.contains("value")) {
                juce::var valVar = e["value"];
                d[@"value"] = extractVar(valVar);
            }

            for (int i = 0; ; ++i)
            {
                juce::String key = "choice_" + juce::String(i);
                if (! e.contains(key))
                    break;

                // JUCE var → NSString
                juce::var v = e[key];
                juce::String vs = v.toString();
                NSString* skey   = [NSString stringWithUTF8String:key.toRawUTF8()];
                NSString* svalue = [NSString stringWithUTF8String:vs.toRawUTF8()] ?: @"";
                d[skey] = svalue;
            }

            [arr addObject:d];
        }
        __result = [arr copy]; });

    return __result;
}

+ (NSArray<NSDictionary *> *)getTrackPluginParametersObjC:(NSInteger)row
                                              effectIndex:(NSInteger)effect
{
    __unsafe_unretained NSMutableArray *__result = nil;

    juce::MessageManager::getInstance()->callSync([row, effect, &__result]
                                                  {
        NSMutableArray* arr = [NSMutableArray array];
        auto list = JuceEngine::get().getTrackPluginParameterInfo((int)row, (int)effect);

        for (auto& e : list)
        {
            const char* cid   = e["id"].toString().toRawUTF8();
            const char* cname = e["name"].toString().toRawUTF8();
            const char* ctype = e["type"].toString().toRawUTF8();

            NSMutableDictionary* d = [NSMutableDictionary dictionary];
            d[@"id"]   = [NSString stringWithUTF8String:cid] ?: @"";
            d[@"name"] = [NSString stringWithUTF8String:cname] ?: @"";
            d[@"type"] = [NSString stringWithUTF8String:ctype] ?: @"";
            if (e.contains("unit"))
            {
                const char* cunit = e["unit"].toString().toRawUTF8();
                d[@"unit"] = [NSString stringWithUTF8String:cunit] ?: @"";
            }

            if (e.contains("min"))  d[@"min"] = @(static_cast<float>(e["min"]));
            if (e.contains("max"))  d[@"max"] = @(static_cast<float>(e["max"]));

            auto extractVar = ^(const juce::var& v) {
                if (v.isBool())
                    return (id)@(static_cast<bool>(v));
                else if (v.isInt() || v.isDouble())
                    return (id)@(static_cast<float>(v));
                else {
                    auto s = v.toString();
                    return (id)([NSString stringWithUTF8String:s.toRawUTF8()] ?: @"");
                }
            };

            if (e.contains("default"))
                d[@"defaultValue"] = extractVar(e["default"]);

            if (e.contains("value"))
                d[@"value"] = extractVar(e["value"]);

            // Choices: choice_0, choice_1, ...
            for (int i = 0; ; ++i)
            {
                juce::String key = "choice_" + juce::String(i);
                if (! e.contains(key))
                    break;

                auto txt  = e[key].toString();
                NSString* skey   = [NSString stringWithUTF8String:key.toRawUTF8()];
                NSString* svalue = [NSString stringWithUTF8String:txt.toRawUTF8()] ?: @"";
                d[skey] = svalue;
            }

            [arr addObject:d];
        }

        __result = [arr copy]; });

    return __result;
}

+ (NSArray<NSDictionary *> *)getMasterPluginParametersObjC:(NSInteger)effect
{
    __unsafe_unretained NSMutableArray *__result = nil;

    juce::MessageManager::getInstance()->callSync([effect, &__result]
                                                  {
        NSMutableArray* arr = [NSMutableArray array];
        auto list = JuceEngine::get().getMasterPluginParameterInfo((int)effect);

        for (auto& e : list)
        {
            const char* cid   = e["id"].toString().toRawUTF8();
            const char* cname = e["name"].toString().toRawUTF8();
            const char* ctype = e["type"].toString().toRawUTF8();

            NSMutableDictionary* d = [NSMutableDictionary dictionary];
            d[@"id"]   = [NSString stringWithUTF8String:cid] ?: @"";
            d[@"name"] = [NSString stringWithUTF8String:cname] ?: @"";
            d[@"type"] = [NSString stringWithUTF8String:ctype] ?: @"";
            if (e.contains("unit"))
            {
                const char* cunit = e["unit"].toString().toRawUTF8();
                d[@"unit"] = [NSString stringWithUTF8String:cunit] ?: @"";
            }

            if (e.contains("min"))  d[@"min"] = @(static_cast<float>(e["min"]));
            if (e.contains("max"))  d[@"max"] = @(static_cast<float>(e["max"]));

            auto extractVar = ^(const juce::var& v) {
                if (v.isBool())
                    return (id)@(static_cast<bool>(v));
                else if (v.isInt() || v.isDouble())
                    return (id)@(static_cast<float>(v));
                else {
                    auto s = v.toString();
                    return (id)([NSString stringWithUTF8String:s.toRawUTF8()] ?: @"");
                }
            };

            if (e.contains("default"))
                d[@"defaultValue"] = extractVar(e["default"]);

            if (e.contains("value"))
                d[@"value"] = extractVar(e["value"]);

            for (int i = 0; ; ++i)
            {
                juce::String key = "choice_" + juce::String(i);
                if (! e.contains(key))
                    break;

                auto txt = e[key].toString();
                NSString* skey   = [NSString stringWithUTF8String:key.toRawUTF8()];
                NSString* svalue = [NSString stringWithUTF8String:txt.toRawUTF8()] ?: @"";
                d[skey] = svalue;
            }

            [arr addObject:d];
        }

        __result = [arr copy]; });

    return __result;
}

+ (NSString *)exportMixObjC:(NSString *)outPath settings:(NSDictionary *)settings
{
    juce::String jucePath = juceStringFromNSString(outPath);
    JuceEngine::ExportOptions options;
    NSString *format = settings[@"format"];
    if ([format isKindOfClass:[NSString class]] && format.length > 0)
        options.format = juceStringFromNSString(format);
    NSNumber *sampleRate = settings[@"sampleRate"];
    if ([sampleRate isKindOfClass:[NSNumber class]])
        options.sampleRate = [sampleRate doubleValue];
    NSNumber *wavBitDepth = settings[@"wavBitDepth"];
    if ([wavBitDepth isKindOfClass:[NSNumber class]])
        options.wavBitDepth = [wavBitDepth intValue];
    NSNumber *wavDithering = settings[@"wavDithering"];
    if ([wavDithering isKindOfClass:[NSNumber class]])
        options.wavDithering = [wavDithering boolValue];
    NSNumber *mp3BitrateKbps = settings[@"mp3BitrateKbps"];
    if ([mp3BitrateKbps isKindOfClass:[NSNumber class]])
        options.mp3BitrateKbps = [mp3BitrateKbps intValue];
    NSNumber *dryClipRender = settings[@"dryClipRender"];
    if ([dryClipRender isKindOfClass:[NSNumber class]])
        options.dryClipRender = [dryClipRender boolValue];
    NSString *clipSnapshotJson = settings[@"clipSnapshotJson"];
    if ([clipSnapshotJson isKindOfClass:[NSString class]] && clipSnapshotJson.length > 0)
        options.clipSnapshotJson = juceStringFromNSString(clipSnapshotJson);
    juce::String result;

    juce::MessageManager::getInstance()->callSync([&]
                                                  { result = JuceEngine::get().exportMix(juce::File(jucePath), options); });

    return [NSString stringWithUTF8String:result.toRawUTF8()];
}

+ (double)getExportProgressObjC
{
    double progress = 0.0;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { progress = JuceEngine::get().getExportProgress(); });
    return progress;
}

+ (NSString *)exportTrackObjC:(NSInteger)track outPath:(NSString *)outPath settings:(NSDictionary *)settings
{
    juce::String result;
    juce::String jucePath = juceStringFromNSString(outPath);
    JuceEngine::ExportOptions options;
    NSString *format = settings[@"format"];
    if ([format isKindOfClass:[NSString class]] && format.length > 0)
        options.format = juceStringFromNSString(format);
    NSNumber *sampleRate = settings[@"sampleRate"];
    if ([sampleRate isKindOfClass:[NSNumber class]])
        options.sampleRate = [sampleRate doubleValue];
    NSNumber *wavBitDepth = settings[@"wavBitDepth"];
    if ([wavBitDepth isKindOfClass:[NSNumber class]])
        options.wavBitDepth = [wavBitDepth intValue];
    NSNumber *wavDithering = settings[@"wavDithering"];
    if ([wavDithering isKindOfClass:[NSNumber class]])
        options.wavDithering = [wavDithering boolValue];
    NSNumber *mp3BitrateKbps = settings[@"mp3BitrateKbps"];
    if ([mp3BitrateKbps isKindOfClass:[NSNumber class]])
        options.mp3BitrateKbps = [mp3BitrateKbps intValue];

    juce::MessageManager::getInstance()->callSync([track, jucePath, options, &result]
                                                  { result = JuceEngine::get().exportTrack((int)track, juce::File(jucePath), options); });

    return [NSString stringWithUTF8String:result.toRawUTF8()];
}

+ (NSString *)renderInstrumentClipObjC:(NSString *)outPath
                          instrumentId:(NSString *)instrumentId
                        instrumentName:(NSString *)instrumentName
                                   bpm:(double)bpm
                                 notes:(NSArray<NSDictionary *> *)notes
                                params:(NSDictionary<NSString *, NSNumber *> *)params
{
    mixroom::instruments::InstrumentRenderRequest request;
    request.outFile = juce::File(
        outPath != nil ? juceStringFromNSString(outPath)
                       : juce::String());
    request.instrumentId =
        instrumentId != nil ? juceStringFromNSString(instrumentId)
                            : juce::String();
    request.instrumentName =
        instrumentName != nil ? juceStringFromNSString(instrumentName)
                              : juce::String();
    request.bpm = bpm;

    if (notes != nil)
    {
        request.notes.ensureStorageAllocated((int)notes.count);
        for (NSDictionary *d in notes)
        {
            mixroom::instruments::MidiRenderNote note;
            id pitchV = d[@"pitch"];
            id startV = d[@"startBeat"];
            id lenV = d[@"lengthBeats"];
            id velV = d[@"velocity"];

            if ([pitchV respondsToSelector:@selector(intValue)])
                note.pitch = (int)[pitchV intValue];
            if ([startV respondsToSelector:@selector(doubleValue)])
                note.startBeat = [startV doubleValue];
            if ([lenV respondsToSelector:@selector(doubleValue)])
                note.lengthBeats = [lenV doubleValue];
            if ([velV respondsToSelector:@selector(doubleValue)])
                note.velocity = [velV doubleValue];

            request.notes.add(note);
        }
    }

    if (params != nil)
    {
        for (NSString *key in params)
        {
            id raw = params[key];
            if (raw == nil || raw == [NSNull null])
                continue;
            if (![raw respondsToSelector:@selector(doubleValue)])
                continue;

            const juce::String juceKey = juce::String::fromUTF8([key UTF8String]);
            request.params.set(juce::Identifier(juceKey), juce::var((double)[raw doubleValue]));
        }
    }

    const juce::String renderedPath = mixroom::instruments::renderInstrumentClipToWav(request);
    if (renderedPath.isEmpty())
        return @"";
    return [NSString stringWithUTF8String:renderedPath.toRawUTF8()];
}

+ (NSArray<NSDictionary *> *)scanPluginsObjC:(NSArray<NSString *> *)searchPaths
{
    NSMutableArray *resultArray = nil;
    juce::StringArray jucePaths;
    for (NSString *path in searchPaths ?: @[])
    {
        jucePaths.addIfNotAlreadyThere(juceStringFromNSString(path));
    }

    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&]
                     {
            JuceEngine::get().setAdditionalPluginSearchPaths(jucePaths);
            NSMutableArray *arr = [NSMutableArray array];
            NSMutableSet<NSString *> *seenIds = [NSMutableSet set];
            auto types = JuceEngine::get().getKnownPlugins();
            for (const auto &desc : types) {
                NSString *formatName = [NSString stringWithUTF8String:desc.pluginFormatName.toRawUTF8()] ?: @"";
                // iOS "On Device" tab should expose AudioUnit plugins only.
#if TARGET_OS_IOS
                if (formatName.length > 0 && ![formatName isEqualToString:@"AudioUnit"])
                    continue;
#endif

                NSString *name = [NSString stringWithUTF8String:desc.name.toRawUTF8()] ?: @"";
                NSString *ident = [NSString stringWithUTF8String:desc.fileOrIdentifier.toRawUTF8()] ?: @"";
                NSString *manufacturer = [NSString stringWithUTF8String:desc.manufacturerName.toRawUTF8()] ?: @"";
                NSString *rawCategory = [NSString stringWithUTF8String:desc.category.toRawUTF8()] ?: @"";
                BOOL isInstrument = desc.isInstrument;
                if (ident.length == 0 || name.length == 0)
                    continue;
                if ([seenIds containsObject:ident])
                    continue;

                [seenIds addObject:ident];
                NSMutableDictionary *entry = [@{
                    @"name" : name,
                    @"id" : ident,
                    @"format" : formatName
                } mutableCopy];
                if (manufacturer.length > 0) {
                    entry[@"manufacturer"] = manufacturer;
                }
                if (rawCategory.length > 0) {
                    entry[@"category"] = isInstrument ? @"instrument" : rawCategory;
                } else if (isInstrument) {
                    entry[@"category"] = @"instrument";
                } else {
                    entry[@"category"] = @"effect";
                }
                entry[@"isInstrument"] = @(isInstrument);
                [arr addObject:entry];
            }
            resultArray = [arr copy]; });
    }

    if (resultArray == nil)
        resultArray = [NSMutableArray array];

    return resultArray;
}

+ (NSArray<NSDictionary *> *)rescanPluginsObjC:(NSArray<NSString *> *)searchPaths
{
    NSMutableArray *resultArray = nil;
    juce::StringArray jucePaths;
    for (NSString *path in searchPaths ?: @[])
    {
        jucePaths.addIfNotAlreadyThere(juceStringFromNSString(path));
    }

    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&]
                     {
            NSMutableArray *arr = [NSMutableArray array];
            NSMutableSet<NSString *> *seenIds = [NSMutableSet set];
            auto types = JuceEngine::get().rescanPlugins(jucePaths);
            for (const auto &desc : types) {
                NSString *formatName = [NSString stringWithUTF8String:desc.pluginFormatName.toRawUTF8()] ?: @"";
#if TARGET_OS_IOS
                if (formatName.length > 0 && ![formatName isEqualToString:@"AudioUnit"])
                    continue;
#endif
                NSString *name = [NSString stringWithUTF8String:desc.name.toRawUTF8()] ?: @"";
                NSString *ident = [NSString stringWithUTF8String:desc.fileOrIdentifier.toRawUTF8()] ?: @"";
                NSString *manufacturer = [NSString stringWithUTF8String:desc.manufacturerName.toRawUTF8()] ?: @"";
                NSString *rawCategory = [NSString stringWithUTF8String:desc.category.toRawUTF8()] ?: @"";
                BOOL isInstrument = desc.isInstrument;
                if (ident.length == 0 || name.length == 0)
                    continue;
                if ([seenIds containsObject:ident])
                    continue;
                [seenIds addObject:ident];
                NSMutableDictionary *entry = [@{
                    @"name" : name,
                    @"id" : ident,
                    @"format" : formatName,
                } mutableCopy];
                if (manufacturer.length > 0) {
                    entry[@"manufacturer"] = manufacturer;
                }
                if (rawCategory.length > 0) {
                    entry[@"category"] = isInstrument ? @"instrument" : rawCategory;
                } else if (isInstrument) {
                    entry[@"category"] = @"instrument";
                } else {
                    entry[@"category"] = @"effect";
                }
                entry[@"isInstrument"] = @(isInstrument);
                [arr addObject:entry];
            }
            resultArray = [arr copy]; });
    }

    if (resultArray == nil)
        resultArray = [NSMutableArray array];

    return resultArray;
}

+ (NSDictionary<NSString *, id> *)getEngineDiagnosticsObjC
{
    NSDictionary<NSString *, id> *result = nil;
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&result]
                     {
            const auto diagnostics = JuceEngine::get().getEngineDiagnostics();
            NSMutableDictionary<NSString *, id> *dict = [NSMutableDictionary dictionary];
            for (const auto &entry : diagnostics)
            {
                NSString *key = [NSString stringWithUTF8String:entry.name.toString().toRawUTF8()] ?: @"";
                const auto value = entry.value;
                if (value.isBool())
                    dict[key] = @((BOOL)static_cast<bool>(value));
                else if (value.isInt() || value.isInt64())
                    dict[key] = @((long long)static_cast<juce::int64>(value));
                else if (value.isDouble())
                    dict[key] = @((double)static_cast<double>(value));
                else if (value.isArray())
                {
                    NSMutableArray<NSString *> *values = [NSMutableArray array];
                    if (auto *array = value.getArray())
                    {
                        for (const auto &entryValue : *array)
                        {
                            NSString *entryString = [NSString stringWithUTF8String:entryValue.toString().toRawUTF8()] ?: @"";
                            if (entryString.length > 0)
                                [values addObject:entryString];
                        }
                    }
                    dict[key] = [values copy];
                }
                else
                    dict[key] = [NSString stringWithUTF8String:value.toString().toRawUTF8()] ?: @"";
            }
            result = [dict copy]; });
    }
    return result ?: @{};
}

+ (BOOL)openTrackPluginEditorObjC:(NSInteger)trackRow
                     effectIndex:(NSInteger)effectIndex
{
    bool opened = false;
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&]
                     { opened = JuceEngine::get().openTrackPluginEditor((int)trackRow, (int)effectIndex); });
    }
    return (BOOL)opened;
}

#pragma mark - Transport

+ (void)setTransportSecondsObjC:(double)seconds
{
    juce::MessageManager::callAsync([seconds]
                                    { JuceEngine::get().setTransportSeconds(seconds); });
}

+ (double)getTransportSecondsObjC
{
    std::atomic<double> result{0.0};
    juce::MessageManager::getInstance()->callSync([&result]
                                                  { result = JuceEngine::get().getTransportSeconds(); });
    return result.load();
}

+ (BOOL)insertTrackEffectObjC:(NSInteger)trackRow path:(NSString *)pluginPath
{
    if (pluginPath == nil || pluginPath.length == 0)
        return NO;

    juce::String jucePath = juceStringFromNSString(pluginPath);
    bool success = false;

    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&]
                     { success = JuceEngine::get().insertTrackEffect((int)trackRow, jucePath); });
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:@"JUCERowEffectLoaded"
                                                        object:nil
                                                      userInfo:@{
                                                          @"event" : @"rowEffectLoaded",
                                                          @"row" : @(trackRow),
                                                          @"path" : pluginPath ?: @"",
                                                          @"success" : @(success)
                                                      }];
    return success ? YES : NO;
}

+ (void)removeTrackEffectObjC:(NSInteger)trackRow effectIndex:(NSInteger)effectIndex
{
    juce::MessageManager::getInstance()->callSync([trackRow, effectIndex]
                                                  { JuceEngine::get().removeTrackEffect((int)trackRow, (int)effectIndex); });
}

+ (void)reorderTrackEffectsObjC:(NSInteger)trackRow
                      fromIndex:(NSInteger)fromIdx
                        toIndex:(NSInteger)toIdx
{
    juce::MessageManager::getInstance()->callSync([trackRow, fromIdx, toIdx]
                                                  { JuceEngine::get().reorderTrackEffects((int)trackRow, (int)fromIdx, (int)toIdx); });
}

+ (NSArray<NSString *> *)getTrackEffectsForRowObjC:(NSInteger)trackRow
{
    auto names = JuceEngine::get().getTrackEffectsForRow((int)trackRow);
    NSMutableArray *out = [NSMutableArray array];
    for (auto &s : names)
    {
        [out addObject:[NSString stringWithUTF8String:s.toRawUTF8()]];
    }
    return out;
}

+ (NSArray<NSString *> *)getTrackEffectIdsForRowObjC:(NSInteger)trackRow
{
    auto ids = JuceEngine::get().getTrackEffectIdsForRow((int)trackRow);
    NSMutableArray *out = [NSMutableArray array];
    for (auto &s : ids)
    {
        [out addObject:[NSString stringWithUTF8String:s.toRawUTF8()]];
    }
    return out;
}

+ (NSArray<NSString *> *)getTrackEffectInstanceIdsForRowObjC:(NSInteger)trackRow
{
    auto ids = JuceEngine::get().getTrackEffectInstanceIdsForRow((int)trackRow);
    NSMutableArray *out = [NSMutableArray array];
    for (auto &s : ids)
    {
        [out addObject:[NSString stringWithUTF8String:s.toRawUTF8()]];
    }
    return out;
}

+ (NSString *)getTrackEffectStateObjC:(NSInteger)trackRow
                          effectIndex:(NSInteger)effectIndex
{
    juce::String state;
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([trackRow, effectIndex, &state]
                     { state = JuceEngine::get().getTrackEffectStateBase64((int)trackRow, (int)effectIndex); });
    }
    return [NSString stringWithUTF8String:state.toRawUTF8()] ?: @"";
}

+ (BOOL)setTrackEffectStateObjC:(NSInteger)trackRow
                    effectIndex:(NSInteger)effectIndex
                    stateBase64:(NSString *)stateBase64
{
    bool applied = false;
    const juce::String state = juceStringFromNSString(stateBase64 ?: @"");
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([trackRow, effectIndex, &applied, state]
                     { applied = JuceEngine::get().setTrackEffectStateBase64((int)trackRow, (int)effectIndex, state); });
    }
    return (BOOL)applied;
}

+ (void)setTrackEffectObjC:(NSInteger)trackRow
               effectIndex:(NSInteger)effectIndex
                   paramId:(NSString *)param
                     value:(id)value
{
    juce::var newVal;
    if ([value isKindOfClass:[NSNumber class]])
    {
        const char *t = [(NSNumber *)value objCType];
        if (strcmp(t, @encode(BOOL)) == 0)
            newVal = (bool)[(NSNumber *)value boolValue];
        else if (strcmp(t, @encode(int)) == 0 || strcmp(t, @encode(NSInteger)) == 0)
            newVal = (int)[(NSNumber *)value integerValue];
        else
            newVal = (float)[(NSNumber *)value floatValue];
    }
    else if ([value isKindOfClass:[NSString class]])
    {
        newVal = juceStringFromNSString((NSString *)value);
    }

    juce::String juceParam = juceStringFromNSString(param);
    juce::MessageManager::getInstance()->callSync([trackRow, effectIndex, juceParam, newVal]
                                                  { JuceEngine::get().setTrackEffectParameter((int)trackRow, (int)effectIndex, juceParam, newVal); });
}

+ (void)bypassRowEffectObjC:(NSInteger)rowIndex
                effectIndex:(NSInteger)effectIndex
                     bypass:(BOOL)shouldBypass
{
    juce::MessageManager::getInstance()->callSync([rowIndex, effectIndex, shouldBypass]
                                                  { JuceEngine::get().bypassRowEffect((int)rowIndex, (int)effectIndex, (bool)shouldBypass); });
}

+ (bool)getRowEffectBypassStateObjC:(NSInteger)rowIndex
                        effectIndex:(NSInteger)effectIndex
{
    bool result = false;
    juce::MessageManager::getInstance()->callSync([rowIndex, effectIndex, &result]
                                                  { result = JuceEngine::get().getRowEffectBypassState((int)rowIndex, (int)effectIndex); });
    return result;
}

+ (void)setRowGainObjC:(NSInteger)row gain:(float)gain
{
    juce::MessageManager::getInstance()->callSync([row, gain]
                                                  { JuceEngine::get().setRowGain((int)row, gain); });
}

+ (void)muteRowObjC:(NSInteger)row shouldMute:(BOOL)shouldMute
{
    juce::MessageManager::getInstance()->callSync([row, shouldMute]
                                                  { JuceEngine::get().muteRow((int)row, (bool)shouldMute); });
}

+ (bool)isRowMutedObjC:(NSInteger)row
{
    bool result = false;
    juce::MessageManager::getInstance()->callSync([row, &result]
                                                  { result = JuceEngine::get().isRowMuted((int)row); });
    return result;
}

+ (void)setRowPanObjC:(NSInteger)row pan:(float)pan
{
    juce::MessageManager::getInstance()->callSync([row, pan]
                                                  { JuceEngine::get().setRowPan((int)row, pan); });
}

#pragma mark - Master bus FX and controls

+ (BOOL)insertMasterEffectObjC:(NSString *)pluginPath
{
    if (pluginPath == nil || pluginPath.length == 0)
        return NO;

    juce::String jucePath = juceStringFromNSString(pluginPath);
    bool success = false;

    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&]
                     { success = JuceEngine::get().insertMasterEffect(jucePath); });
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:@"JUCEMasterEffectLoaded"
                                                        object:nil
                                                      userInfo:@{
                                                          @"event" : @"masterEffectLoaded",
                                                          @"path" : pluginPath ?: @"",
                                                          @"success" : @(success)
                                                      }];
    return success ? YES : NO;
}

+ (void)removeMasterEffectObjC:(NSInteger)effectIndex
{
    juce::MessageManager::getInstance()->callSync([effectIndex]
                                                  { JuceEngine::get().removeMasterEffect((int)effectIndex); });
}

+ (void)reorderMasterEffectsObjC:(NSInteger)fromIndex
                         toIndex:(NSInteger)toIndex
{
    juce::MessageManager::getInstance()->callSync([fromIndex, toIndex]
                                                  { JuceEngine::get().reorderMasterEffects((int)fromIndex, (int)toIndex); });
}

+ (NSArray<NSString *> *)getMasterEffectsObjC
{
    auto names = JuceEngine::get().getMasterEffects();
    NSMutableArray *out = [NSMutableArray array];
    for (auto &s : names)
    {
        [out addObject:[NSString stringWithUTF8String:s.toRawUTF8()]];
    }
    return out;
}

+ (NSArray<NSString *> *)getMasterEffectIdsObjC
{
    auto ids = JuceEngine::get().getMasterEffectIds();
    NSMutableArray *out = [NSMutableArray array];
    for (auto &s : ids)
    {
        [out addObject:[NSString stringWithUTF8String:s.toRawUTF8()]];
    }
    return out;
}

+ (NSString *)getMasterEffectStateObjC:(NSInteger)effectIndex
{
    juce::String state;
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([effectIndex, &state]
                     { state = JuceEngine::get().getMasterEffectStateBase64((int)effectIndex); });
    }
    return [NSString stringWithUTF8String:state.toRawUTF8()] ?: @"";
}

+ (BOOL)setMasterEffectStateObjC:(NSInteger)effectIndex
                     stateBase64:(NSString *)stateBase64
{
    bool applied = false;
    const juce::String state = juceStringFromNSString(stateBase64 ?: @"");
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([effectIndex, &applied, state]
                     { applied = JuceEngine::get().setMasterEffectStateBase64((int)effectIndex, state); });
    }
    return (BOOL)applied;
}

+ (BOOL)openMasterPluginEditorObjC:(NSInteger)effectIndex
{
    bool opened = false;
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&]
                     { opened = JuceEngine::get().openMasterPluginEditor((int)effectIndex); });
    }
    return (BOOL)opened;
}

+ (void)setMasterEffectObjC:(NSInteger)effectIndex
                    paramId:(NSString *)param
                      value:(id)value
{
    juce::var newVal;
    if ([value isKindOfClass:[NSNumber class]])
    {
        const char *t = [(NSNumber *)value objCType];
        if (strcmp(t, @encode(BOOL)) == 0)
            newVal = (bool)[(NSNumber *)value boolValue];
        else if (strcmp(t, @encode(int)) == 0 || strcmp(t, @encode(NSInteger)) == 0)
            newVal = (int)[(NSNumber *)value integerValue];
        else
            newVal = (float)[(NSNumber *)value floatValue];
    }
    else if ([value isKindOfClass:[NSString class]])
    {
        newVal = juceStringFromNSString((NSString *)value);
    }

    juce::String juceParam = juceStringFromNSString(param);
    juce::MessageManager::getInstance()->callSync([effectIndex, juceParam, newVal]
                                                  { JuceEngine::get().setMasterEffectParameter((int)effectIndex, juceParam, newVal); });
}

+ (void)bypassMasterEffectObjC:(NSInteger)effectIndex bypass:(BOOL)shouldBypass
{
    juce::MessageManager::getInstance()->callSync([effectIndex, shouldBypass]
                                                  { JuceEngine::get().bypassMasterEffect((int)effectIndex, (bool)shouldBypass); });
}

+ (bool)getMasterEffectBypassStateObjC:(NSInteger)effectIndex
{
    bool result = false;
    juce::MessageManager::getInstance()->callSync([effectIndex, &result]
                                                  { result = JuceEngine::get().getMasterEffectBypassState((int)effectIndex); });
    return result;
}

+ (void)setMasterGainObjC:(float)gain
{
    juce::MessageManager::getInstance()->callSync([gain]
                                                  { JuceEngine::get().setMasterGain(gain); });
}

+ (void)muteMasterObjC:(BOOL)shouldMute
{
    juce::MessageManager::getInstance()->callSync([shouldMute]
                                                  { JuceEngine::get().muteMaster((bool)shouldMute); });
}

+ (void)setMasterPanObjC:(float)pan
{
    juce::MessageManager::getInstance()->callSync([pan]
                                                  { JuceEngine::get().setMasterPan(pan); });
}

+ (void)bypassPluginObjC:(NSInteger)trackIndex
             effectIndex:(NSInteger)effectIndex
                  bypass:(BOOL)shouldBypass
{
    juce::MessageManager::callAsync([trackIndex, effectIndex, shouldBypass]
                                    { JuceEngine::get().bypassPlugin((int)trackIndex, (int)effectIndex, (bool)shouldBypass); });
}

+ (bool)getPluginBypassStateObjC:(NSInteger)trackIndex
                     effectIndex:(NSInteger)effectIndex
{
    bool result;
    juce::MessageManager::getInstance()->callSync([trackIndex, effectIndex, &result]
                                                  { result = JuceEngine::get().getPluginBypassState((int)trackIndex, (int)effectIndex); });
    return result;
}

+ (void)bypassTrackObjC:(NSInteger)trackIndex
           shouldBypass:(BOOL)shouldBypass
{
    juce::MessageManager::callAsync([trackIndex, shouldBypass]
                                    { JuceEngine::get().bypassTrack((int)trackIndex, (bool)shouldBypass); });
}

+ (void)loadVideoAudioObjC:(NSString *)path
{
    juce::String jucePath = juceStringFromNSString(path);
    juce::MessageManager::callAsync([jucePath]
                                    { JuceEngine::get().loadVideoAudio(juce::File(jucePath)); });
}

+ (void)unloadVideoAudioObjC
{
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().unloadVideoAudio(); });
}

+ (void)setVideoAudioGainObjC:(float)gain
{
    juce::MessageManager::callAsync([gain]
                                    { JuceEngine::get().setVideoAudioGain(gain); });
}

+ (void)seekVideoAudioObjC:(double)seconds
{
    juce::MessageManager::callAsync([seconds]
                                    { JuceEngine::get().seekVideoAudio(seconds); });
}

// ===============================================================
// NEW DAW-STYLE API (clip / row / master / automation)
// ===============================================================

#pragma mark - Debug graph

+ (void)debugPrintGraphObjC:(NSString *)title
{
    juce::String juceTitle = juceStringFromNSString(title);
    juce::MessageManager::callAsync([juceTitle]
                                    { JuceEngine::get().debugPrintGraph(juceTitle); });
}

+ (void)debugPrintGraphStructureObjC
{
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().debugPrintGraphStructure(); });
}

#pragma mark - Clip-level control

+ (BOOL)loadClipObjC:(NSInteger)clipIndex
               rowId:(NSInteger)rowId
                path:(NSString *)path
            startSec:(double)startSec
           lengthSec:(double)lengthSec
     inFileOffsetSec:(double)inFileOffsetSec
{
    juce::String jucePath = juceStringFromNSString(path);
    return JuceEngine::get().loadClip((int)clipIndex,
                                      (int)rowId,
                                      juce::File(jucePath),
                                      startSec,
                                      lengthSec,
                                      inFileOffsetSec);
}

+ (void)beginProjectClipLoadObjC
{
    JuceEngine::get().beginProjectClipLoad();
}

+ (void)endProjectClipLoadObjC
{
    JuceEngine::get().endProjectClipLoad();
}

+ (BOOL)supportsLiveMidiClipPlaybackObjC
{
    bool supported = false;
    juce::MessageManager::getInstance()->callSync([&supported]
                                                  { supported = JuceEngine::get().supportsLiveMidiClipPlayback(); });
    return (BOOL)supported;
}

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
{
    const juce::String iid =
        instrumentId != nil ? juceStringFromNSString(instrumentId)
                            : juce::String();
    const juce::String iname =
        instrumentName != nil ? juceStringFromNSString(instrumentName)
                              : juce::String();
    const auto parsedNotes = parseTimelineMidiNotes(notes);
    const auto parsedParams = parseMidiParams(params);

    bool ok = false;
    juce::MessageManager::getInstance()->callSync([&]
                                                  {
        ok = JuceEngine::get().loadMidiClip((int)clipIndex,
                                            (int)rowId,
                                            iid,
                                            iname,
                                            parsedNotes,
                                            parsedParams,
                                            sourceTempoBpm,
                                            startSec,
                                            lengthSec,
                                            inFileOffsetSec); });
    return (BOOL)ok;
}

+ (BOOL)updateMidiClipObjC:(NSInteger)clipIndex
              instrumentId:(NSString *)instrumentId
            instrumentName:(NSString *)instrumentName
                     notes:(NSArray<NSDictionary *> *)notes
                    params:(NSDictionary<NSString *, NSNumber *> *)params
            sourceTempoBpm:(double)sourceTempoBpm
{
    const juce::String iid =
        instrumentId != nil ? juceStringFromNSString(instrumentId)
                            : juce::String();
    const juce::String iname =
        instrumentName != nil ? juceStringFromNSString(instrumentName)
                              : juce::String();
    const auto parsedNotes = parseTimelineMidiNotes(notes);
    const auto parsedParams = parseMidiParams(params);

    bool ok = false;
    juce::MessageManager::getInstance()->callSync([&]
                                                  {
        ok = JuceEngine::get().updateMidiClipEvents((int)clipIndex,
                                                    iid,
                                                    iname,
                                                    parsedNotes,
                                                    parsedParams,
                                                    sourceTempoBpm); });
    return (BOOL)ok;
}

+ (BOOL)setLiveMidiInputTargetClipObjC:(NSInteger)clipIndex
{
    bool ok = false;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ok = JuceEngine::get().setLiveMidiInputTargetClip((int)clipIndex); });
    return (BOOL)ok;
}

+ (BOOL)sendLiveMidiInputEventObjC:(BOOL)noteOn
                           channel:(NSInteger)channel
                             pitch:(NSInteger)pitch
                          velocity:(float)velocity
{
    bool ok = false;
    juce::MessageManager::getInstance()->callSync([&]
                                                  {
        ok = JuceEngine::get().sendLiveMidiInputEvent((bool)noteOn,
                                                      (int)channel,
                                                      (int)pitch,
                                                      velocity); });
    return (BOOL)ok;
}

+ (BOOL)playPreviewMidiNoteObjC:(NSInteger)clipIndex
                          pitch:(NSInteger)pitch
                       velocity:(float)velocity
                     durationMs:(NSInteger)durationMs
{
    bool ok = false;
    juce::MessageManager::getInstance()->callSync([&]
                                                  {
        ok = JuceEngine::get().playPreviewMidiNote((int)clipIndex,
                                                   (int)pitch,
                                                   velocity,
                                                   (int)durationMs); });
    return (BOOL)ok;
}

+ (BOOL)openMidiClipPluginEditorObjC:(NSInteger)clipIndex
{
    bool opened = false;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { opened = JuceEngine::get().openMidiClipPluginEditor((int)clipIndex); });
    return (BOOL)opened;
}

+ (NSString *)getMidiClipPluginStateObjC:(NSInteger)clipIndex
{
    juce::String state;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { state = JuceEngine::get().getMidiClipPluginStateBase64((int)clipIndex); });
    return [NSString stringWithUTF8String:state.toRawUTF8()] ?: @"";
}

+ (void)setHostedPluginWindowsDetachedObjC:(BOOL)detached
{
    mixroomSetHostedPluginWindowsDetached(detached);
}

+ (BOOL)setMidiClipPluginStateObjC:(NSInteger)clipIndex
                        stateBase64:(NSString *)stateBase64
{
    const juce::String state =
        stateBase64 != nil ? juceStringFromNSString(stateBase64)
                           : juce::String();
    bool applied = false;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { applied = JuceEngine::get().setMidiClipPluginStateBase64((int)clipIndex, state); });
    return (BOOL)applied;
}

+ (NSArray<NSDictionary *> *)consumeLiveMidiInputEventsObjC
{
    std::vector<JuceEngine::LiveMidiInputEvent> events;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { events = JuceEngine::get().consumeLiveMidiInputEvents(); });

    NSMutableArray<NSDictionary *> *out =
        [NSMutableArray arrayWithCapacity:events.size()];
    for (const auto &event : events)
    {
        [out addObject:@{
            @"clip" : @(event.clipId),
            @"type" : event.noteOn ? @"noteOn" : @"noteOff",
            @"channel" : @(event.channel),
            @"pitch" : @(event.pitch),
            @"velocity" : @((double)event.velocity),
            @"transportSec" : @(event.transportSec),
        }];
    }
    return out;
}

+ (NSArray<NSDictionary *> *)getConnectedMidiInputDevicesObjC
{
    NSArray<NSDictionary *> *resultArray = nil;
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&]
                     {
            NSMutableArray<NSDictionary *> *arr = [NSMutableArray array];
            const auto devices = juce::MidiInput::getAvailableDevices();
            for (const auto &device : devices)
            {
                NSString *identifier =
                    [NSString stringWithUTF8String:device.identifier.toRawUTF8()] ?: @"";
                if (identifier.length == 0)
                    continue;

                NSString *name =
                    [NSString stringWithUTF8String:device.name.toRawUTF8()] ?: @"";
                if (name.length == 0)
                    name = identifier;

                [arr addObject:@{
                    @"id" : identifier,
                    @"name" : name,
                }];
            }
            resultArray = [arr copy]; });
    }

    if (resultArray == nil)
        resultArray = @[];

    return resultArray;
}

+ (void)unloadClipObjC:(NSInteger)clipIndex
{
    juce::MessageManager::callAsync([clipIndex]
                                    { JuceEngine::get().unloadClip((int)clipIndex); });
}

+ (void)setClipGainObjC:(NSInteger)clipIndex gain:(float)gain
{
    juce::MessageManager::getInstance()->callSync([clipIndex, gain]
                                                  { JuceEngine::get().setClipGain((int)clipIndex, gain); });
}

+ (void)setClipExtraGainLinearObjC:(NSInteger)clipIndex gain:(float)gain
{
    juce::MessageManager::getInstance()->callSync([clipIndex, gain]
                                                  { JuceEngine::get().setClipExtraGainLinear((int)clipIndex, gain); });
}

+ (void)muteClipObjC:(NSInteger)clipIndex shouldMute:(BOOL)shouldMute
{
    juce::MessageManager::getInstance()->callSync([clipIndex, shouldMute]
                                                  { JuceEngine::get().muteClip((int)clipIndex, (bool)shouldMute); });
}

+ (void)setClipPanObjC:(NSInteger)clipIndex pan:(float)pan
{
    juce::MessageManager::getInstance()->callSync([clipIndex, pan]
                                                  { JuceEngine::get().setClipPan((int)clipIndex, pan); });
}

+ (void)setClipFadesObjC:(NSInteger)clipIndex
               fadeInSec:(double)fadeInSec
              fadeOutSec:(double)fadeOutSec
               fadeCurve:(NSInteger)fadeCurve
{
    juce::MessageManager::getInstance()->callSync([clipIndex, fadeInSec, fadeOutSec, fadeCurve]
                                                  { JuceEngine::get().setClipFades((int)clipIndex, fadeInSec, fadeOutSec, (int)fadeCurve); });
}

+ (void)setClipPitchObjC:(NSInteger)clipIndex semitones:(float)semitones
{
    juce::MessageManager::getInstance()->callSync([clipIndex, semitones]
                                                  { JuceEngine::get().setClipPitch((int)clipIndex, semitones); });
}

+ (void)setClipReversedObjC:(NSInteger)clipIndex reversed:(BOOL)reversed
{
    juce::MessageManager::getInstance()->callSync([clipIndex, reversed]
                                                  { JuceEngine::get().setClipReversed((int)clipIndex, (bool)reversed); });
}

+ (void)setClipStretchOptionsObjC:(NSInteger)clipIndex
                       tempoRatio:(double)tempoRatio
                    preservePitch:(BOOL)preservePitch
{
    juce::MessageManager::getInstance()->callSync([clipIndex, tempoRatio, preservePitch]
                                                  { JuceEngine::get().setClipStretchOptions((int)clipIndex, tempoRatio, (bool)preservePitch); });
}

+ (void)moveClipToRowObjC:(NSInteger)clipIndex newRowId:(NSInteger)newRowId
{
    juce::MessageManager::getInstance()->callSync([clipIndex, newRowId]
                                                  { JuceEngine::get().moveClipToRow((int)clipIndex, (int)newRowId); });
}

+ (void)setClipTimeObjC:(NSInteger)clipIndex
               startSec:(double)startSec
              lengthSec:(double)lengthSec
        inFileOffsetSec:(double)inFileOffsetSec
{
    juce::MessageManager::getInstance()->callSync([clipIndex, startSec, lengthSec, inFileOffsetSec]
                                                  { JuceEngine::get().setClipTime((int)clipIndex, startSec, lengthSec, inFileOffsetSec); });
}

#pragma mark - Row management

+ (NSNumber *)addRowObjC:(NSString *)name iconId:(NSInteger)iconId
{
    juce::String n = juceStringFromNSString(name);
    int rowId = JuceEngine::get().addRow(n, (int)iconId);
    return @(rowId);
}

+ (NSNumber *)insertRowAboveObjC:(NSInteger)referenceRowId name:(NSString *)name iconId:(NSInteger)iconId
{
    juce::String n = juceStringFromNSString(name);
    int rowId = JuceEngine::get().insertRowAbove((int)referenceRowId, n, (int)iconId);
    return @(rowId);
}

+ (NSNumber *)insertRowBelowObjC:(NSInteger)referenceRowId name:(NSString *)name iconId:(NSInteger)iconId
{
    juce::String n = juceStringFromNSString(name);
    int rowId = JuceEngine::get().insertRowBelow((int)referenceRowId, n, (int)iconId);
    return @(rowId);
}

+ (BOOL)removeRowObjC:(NSInteger)rowId
{
    return (BOOL)JuceEngine::get().removeRow((int)rowId);
}

+ (BOOL)moveRowOrderObjC:(NSInteger)fromIndex toIndex:(NSInteger)toIndex
{
    return (BOOL)JuceEngine::get().moveRowOrder((int)fromIndex, (int)toIndex);
}

+ (BOOL)renameRowObjC:(NSInteger)rowId name:(NSString *)name
{
    juce::String n = juceStringFromNSString(name);
    return (BOOL)JuceEngine::get().renameRow((int)rowId, n);
}

+ (BOOL)setRowIconObjC:(NSInteger)rowId iconId:(NSInteger)iconId
{
    return (BOOL)JuceEngine::get().setRowIcon((int)rowId, (int)iconId);
}

+ (NSArray<NSDictionary *> *)getRowsObjC
{
    auto rows = JuceEngine::get().getRows();
    NSMutableArray *out = [NSMutableArray array];

    for (const auto &r : rows)
    {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        d[@"rowId"] = @((int)r["rowId"]);
        d[@"name"] = [NSString stringWithUTF8String:r["name"].toString().toRawUTF8()] ?: @"";
        d[@"iconId"] = @((int)r["iconId"]);
        [out addObject:d];
    }

    return out;
}

#pragma mark - Automation

+ (void)setTrackAutomationPointsObjC:(NSInteger)trackRow
                              points:(NSArray<NSDictionary *> *)points
{
    std::vector<AutomationPoint> cppPoints;
    cppPoints.reserve(points.count);

    for (NSDictionary *dict in points)
    {
        AutomationPoint p;

        id xVal = dict[@"x"];
        id volVal = dict[@"volume"];

        if ([xVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [xVal doubleValue];
        else
            p.timeMs = 0.0;

        if ([volVal respondsToSelector:@selector(doubleValue)])
            p.value = (float)[volVal doubleValue];
        else
            p.value = 1.0f;

        cppPoints.push_back(p);
    }

    juce::MessageManager::getInstance()->callSync([trackRow, cppPoints]() mutable
                                                  { JuceEngine::get().setTrackAutomationPoints((int)trackRow, cppPoints); });
}

+ (void)setTrackEffectAutomationPointsObjC:(NSInteger)trackRow
                                effectIndex:(NSInteger)effectIndex
                                    paramId:(NSString *)paramId
                                   minValue:(double)minValue
                                   maxValue:(double)maxValue
                                     points:(NSArray<NSDictionary *> *)points
{
    std::vector<AutomationPoint> cppPoints;
    cppPoints.reserve(points.count);

    for (NSDictionary *dict in points)
    {
        AutomationPoint p;

        id xVal = dict[@"x"];
        id timeMsVal = dict[@"timeMs"];
        id timeSecondsVal = dict[@"timeSeconds"];
        id valueVal = dict[@"value"];
        id volumeVal = dict[@"volume"];

        if ([xVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [xVal doubleValue];
        else if ([timeMsVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [timeMsVal doubleValue];
        else if ([timeSecondsVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [timeSecondsVal doubleValue] * 1000.0;
        else
            p.timeMs = 0.0;

        if ([valueVal respondsToSelector:@selector(doubleValue)])
            p.value = (float)[valueVal doubleValue];
        else if ([volumeVal respondsToSelector:@selector(doubleValue)])
            p.value = (float)[volumeVal doubleValue];
        else
            p.value = 0.0f;

        cppPoints.push_back(p);
    }

    juce::String juceParam = juceStringFromNSString(paramId ?: @"");
    juce::MessageManager::getInstance()->callSync([trackRow, effectIndex, juceParam, minValue, maxValue, cppPoints]() mutable
                                                  { JuceEngine::get().setTrackEffectAutomationPoints((int)trackRow, (int)effectIndex, juceParam, (float)minValue, (float)maxValue, cppPoints); });
}

+ (void)clearTrackEffectAutomationForRowObjC:(NSInteger)trackRow
{
    juce::MessageManager::getInstance()->callSync([trackRow]
                                                  { JuceEngine::get().clearTrackEffectAutomationForRow((int)trackRow); });
}

+ (void)setRowGainAutomationPointsObjC:(NSInteger)row
                               points:(NSArray<NSDictionary *> *)points
{
    std::vector<AutomationPoint> cppPoints;
    cppPoints.reserve(points.count);

    for (NSDictionary *dict in points)
    {
        AutomationPoint p;
        id xVal = dict[@"x"];
        id timeMsVal = dict[@"timeMs"];
        id timeSecondsVal = dict[@"timeSeconds"];
        id valueVal = dict[@"value"];
        id volumeVal = dict[@"volume"];

        if ([xVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [xVal doubleValue];
        else if ([timeMsVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [timeMsVal doubleValue];
        else if ([timeSecondsVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [timeSecondsVal doubleValue] * 1000.0;
        else
            p.timeMs = 0.0;

        if ([valueVal respondsToSelector:@selector(doubleValue)])
            p.value = (float)[valueVal doubleValue];
        else if ([volumeVal respondsToSelector:@selector(doubleValue)])
            p.value = (float)[volumeVal doubleValue];
        else
            p.value = 0.0f;

        cppPoints.push_back(p);
    }

    juce::MessageManager::getInstance()->callSync([row, cppPoints]() mutable
                                                  { JuceEngine::get().setRowGainAutomationPoints((int)row, cppPoints); });
}

+ (void)setRowPanAutomationPointsObjC:(NSInteger)row
                              points:(NSArray<NSDictionary *> *)points
{
    std::vector<AutomationPoint> cppPoints;
    cppPoints.reserve(points.count);

    for (NSDictionary *dict in points)
    {
        AutomationPoint p;
        id xVal = dict[@"x"];
        id timeMsVal = dict[@"timeMs"];
        id timeSecondsVal = dict[@"timeSeconds"];
        id valueVal = dict[@"value"];
        id volumeVal = dict[@"volume"];

        if ([xVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [xVal doubleValue];
        else if ([timeMsVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [timeMsVal doubleValue];
        else if ([timeSecondsVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [timeSecondsVal doubleValue] * 1000.0;
        else
            p.timeMs = 0.0;

        if ([valueVal respondsToSelector:@selector(doubleValue)])
            p.value = (float)[valueVal doubleValue];
        else if ([volumeVal respondsToSelector:@selector(doubleValue)])
            p.value = (float)[volumeVal doubleValue];
        else
            p.value = 0.0f;

        cppPoints.push_back(p);
    }

    juce::MessageManager::getInstance()->callSync([row, cppPoints]() mutable
                                                  { JuceEngine::get().setRowPanAutomationPoints((int)row, cppPoints); });
}

+ (void)setMasterEffectAutomationPointsObjC:(NSInteger)effectIndex
                                  paramId:(NSString *)paramId
                                 minValue:(double)minValue
                                 maxValue:(double)maxValue
                                   points:(NSArray<NSDictionary *> *)points
{
    std::vector<AutomationPoint> cppPoints;
    cppPoints.reserve(points.count);

    for (NSDictionary *dict in points)
    {
        AutomationPoint p;
        id xVal = dict[@"x"];
        id timeMsVal = dict[@"timeMs"];
        id timeSecondsVal = dict[@"timeSeconds"];
        id valueVal = dict[@"value"];
        id volumeVal = dict[@"volume"];

        if ([xVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [xVal doubleValue];
        else if ([timeMsVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [timeMsVal doubleValue];
        else if ([timeSecondsVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [timeSecondsVal doubleValue] * 1000.0;
        else
            p.timeMs = 0.0;

        if ([valueVal respondsToSelector:@selector(doubleValue)])
            p.value = (float)[valueVal doubleValue];
        else if ([volumeVal respondsToSelector:@selector(doubleValue)])
            p.value = (float)[volumeVal doubleValue];
        else
            p.value = 0.0f;

        cppPoints.push_back(p);
    }

    juce::String juceParam = juceStringFromNSString(paramId ?: @"");
    juce::MessageManager::getInstance()->callSync([effectIndex, juceParam, minValue, maxValue, cppPoints]() mutable
                                                  { JuceEngine::get().setMasterEffectAutomationPoints((int)effectIndex, juceParam, (float)minValue, (float)maxValue, cppPoints); });
}

+ (void)clearMasterEffectAutomationObjC
{
    juce::MessageManager::getInstance()->callSync([]
                                                  { JuceEngine::get().clearMasterEffectAutomation(); });
}

+ (void)setMasterGainAutomationPointsObjC:(NSArray<NSDictionary *> *)points
{
    std::vector<AutomationPoint> cppPoints;
    cppPoints.reserve(points.count);

    for (NSDictionary *dict in points)
    {
        AutomationPoint p;
        id xVal = dict[@"x"];
        id timeMsVal = dict[@"timeMs"];
        id timeSecondsVal = dict[@"timeSeconds"];
        id valueVal = dict[@"value"];
        id volumeVal = dict[@"volume"];

        if ([xVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [xVal doubleValue];
        else if ([timeMsVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [timeMsVal doubleValue];
        else if ([timeSecondsVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [timeSecondsVal doubleValue] * 1000.0;
        else
            p.timeMs = 0.0;

        if ([valueVal respondsToSelector:@selector(doubleValue)])
            p.value = (float)[valueVal doubleValue];
        else if ([volumeVal respondsToSelector:@selector(doubleValue)])
            p.value = (float)[volumeVal doubleValue];
        else
            p.value = 0.0f;

        cppPoints.push_back(p);
    }

    juce::MessageManager::getInstance()->callSync([cppPoints]() mutable
                                                  { JuceEngine::get().setMasterGainAutomationPoints(cppPoints); });
}

+ (void)setMasterPanAutomationPointsObjC:(NSArray<NSDictionary *> *)points
{
    std::vector<AutomationPoint> cppPoints;
    cppPoints.reserve(points.count);

    for (NSDictionary *dict in points)
    {
        AutomationPoint p;
        id xVal = dict[@"x"];
        id timeMsVal = dict[@"timeMs"];
        id timeSecondsVal = dict[@"timeSeconds"];
        id valueVal = dict[@"value"];
        id volumeVal = dict[@"volume"];

        if ([xVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [xVal doubleValue];
        else if ([timeMsVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [timeMsVal doubleValue];
        else if ([timeSecondsVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [timeSecondsVal doubleValue] * 1000.0;
        else
            p.timeMs = 0.0;

        if ([valueVal respondsToSelector:@selector(doubleValue)])
            p.value = (float)[valueVal doubleValue];
        else if ([volumeVal respondsToSelector:@selector(doubleValue)])
            p.value = (float)[volumeVal doubleValue];
        else
            p.value = 0.0f;

        cppPoints.push_back(p);
    }

    juce::MessageManager::getInstance()->callSync([cppPoints]() mutable
                                                  { JuceEngine::get().setMasterPanAutomationPoints(cppPoints); });
}

+ (void)setAutomationTransportObjC:(double)timeSeconds
{
    juce::MessageManager::callAsync([timeSeconds]
                                    { JuceEngine::get().setAutomationTransport(timeSeconds); });
}

+ (void)setMetronomeEnabledObjC:(BOOL)enabled
{
    juce::MessageManager::callAsync([enabled]
                                    { JuceEngine::get().setMetronomeEnabled((bool)enabled); });
}

+ (void)setMetronomeVolumeObjC:(float)vol
{
    juce::MessageManager::callAsync([vol]
                                    { JuceEngine::get().setMetronomeVolume(vol); });
}

+ (void)setMetronomeBpmObjC:(double)bpm
{
    juce::MessageManager::callAsync([bpm]
                                    { JuceEngine::get().setMetronomeBpm(bpm); });
}

+ (void)setMetronomeTransportMsObjC:(double)ms
{
    juce::MessageManager::callAsync([ms]
                                    { JuceEngine::get().setMetronomeTransportMs(ms); });
}

+ (NSArray<NSNumber *> *)decodeAudioMono16kObjC:(NSString *)path
{
    juce::File file = juceFileFromNSString(path);

    auto samples = JuceEngine::get().decodeAudioMono16k(file);

    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:samples.size()];
    for (float v : samples)
    {
        [arr addObject:@(v)];
    }
    return arr;
}

+ (NSDictionary<NSString *, NSNumber *> *)analyzeAudioStereo16kObjC:(NSString *)path
{
    juce::File file = juceFileFromNSString(path);
    auto stats = JuceEngine::get().analyzeAudioStereo16k(file);

    return @{
        @"phase_corr" : @((double)stats.getWithDefault("phase_corr", 1.0)),
        @"side_ratio" : @((double)stats.getWithDefault("side_ratio", 0.0)),
        @"stereo_imbalance" : @((double)stats.getWithDefault("stereo_imbalance", 0.0)),
    };
}

+ (NSDictionary<NSString *, id> *)analyzeAudioForPromptObjC:(NSString *)path
                                                trimStartMs:(double)trimStartMs
                                                  trimEndMs:(double)trimEndMs
{
    juce::File file = juceFileFromNSString(path);
    auto stats = JuceEngine::get().analyzeAudioPrompt16k(file, trimStartMs, trimEndMs);
    auto windows = JuceEngine::get().sampleAudioMono16kWindows(file, 15600, 3, trimStartMs, trimEndMs);
    NSLog(@"[MixroomPromptAnalysis] analyzeAudioForPrompt path=%@ windows=%lu", path, (unsigned long)windows.size());
    NSDictionary<NSString *, NSNumber *> *roleProbs =
        [[MixroomPromptAnalysisService sharedService] classifyWindows:windows];
    return @{
        @"audioStats" : namedValueStatsToNSDictionary(stats),
        @"roleProbs" : roleProbs ?: fallbackPromptRoleProbs(),
    };
}

+ (NSArray<NSString *> *)getInputDevicesObjC
{
    auto arr = JuceEngine::get().getAvailableInputDevices();

    NSMutableArray *out = [NSMutableArray arrayWithCapacity:arr.size()];
    for (auto &s : arr)
        [out addObject:[NSString stringWithUTF8String:s.toRawUTF8()]];

    return out;
}

+ (BOOL)selectInputDeviceObjC:(NSString *)name
{
    juce::String dev = juceStringFromNSString(name);
    return JuceEngine::get().selectInputDevice(dev);
}

+ (NSNumber *)getNumInputChannelsObjC
{
    return @(JuceEngine::get().getNumInputChannels());
}

+ (NSString *)getCurrentDeviceNameObjC
{
    auto s = JuceEngine::get().getCurrentInputDeviceName();
    return [NSString stringWithUTF8String:s.toRawUTF8()];
}

+ (NSString *)getCurrentOutputDeviceNameObjC
{
    auto s = JuceEngine::get().getCurrentOutputDeviceName();
    return [NSString stringWithUTF8String:s.toRawUTF8()];
}

+ (BOOL)prepareRecordingInputsObjC:(NSInteger)desiredInputChannels
                            reason:(NSString *)reason
{
    const auto why = reason == nil ? juce::String("dart") : juceStringFromNSString(reason);
    return JuceEngine::get().prepareRecordingInputs((int)desiredInputChannels, why);
}

+ (BOOL)preparePlaybackRouteObjC:(NSString *)reason
{
    const auto why = reason == nil ? juce::String("dart") : juceStringFromNSString(reason);
    return JuceEngine::get().preparePlaybackRoute(why);
}

+ (void)refreshAudioRouteObjC:(NSString *)reason
{
    const auto why = reason == nil ? juce::String("dart") : juceStringFromNSString(reason);
    JuceEngine::get().requestAudioDeviceRefreshAsync(why);
}

+ (void)setLiveInputMonitoringEnabledObjC:(BOOL)enabled
{
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([enabled]
                     { JuceEngine::get().setLiveInputMonitoringEnabled(enabled); });
        return;
    }

    JuceEngine::get().setLiveInputMonitoringEnabled(enabled);
}

+ (BOOL)startRecordingObjC:(NSString *)path
              channelStart:(NSInteger)start
              channelCount:(NSInteger)count
{
    // juce::File f = juceFileFromNSString(path);
    juce::String jucePath = juceStringFromNSString(path);
    juce::File f(jucePath);

    return JuceEngine::get()
        .startRecordingToWav(
            f, (int)start, (int)count);
}

+ (NSNumber *)getRecordingPeakObjC
{
    return @(JuceEngine::get().getRecordingPeak());
}

+ (void)stopRecordingObjC
{
    JuceEngine::get().stopRecording();
}

+ (BOOL)isRecordingObjC
{
    return JuceEngine::get().isRecording();
}

// ===============================
// MASTER METER
// ===============================
+ (void)setMasterMeterEnabledObjC:(BOOL)enabled
{
    JuceEngine::get().setMasterMeterEnabled((bool)enabled);
}

// [peakL, peakR, rmsL, rmsR]
+ (NSArray<NSNumber*>*)getMasterMeterValuesObjC
{
    auto v = JuceEngine::get().getMasterMeterValues();
    return @[@(v[0]), @(v[1]), @(v[2]), @(v[3])];
}

+ (BOOL)getMasterClipLatchedObjC
{
    return (BOOL)JuceEngine::get().getMasterClipLatched();
}

+ (void)clearMasterClipLatchedObjC
{
    JuceEngine::get().clearMasterClipLatched();
}

// ===============================
// ROW METERS
// ===============================
+ (void)setRowMetersEnabledObjC:(BOOL)enabled
{
    JuceEngine::get().setRowMetersEnabled((bool)enabled);
}

// [peakL, peakR, rmsL, rmsR]
+ (NSArray<NSNumber*>*)getRowMeterValuesObjC:(NSInteger)row
{
    auto v = JuceEngine::get().getRowMeterValues((int)row);
    return @[@(v[0]), @(v[1]), @(v[2]), @(v[3])];
}

+ (NSArray<NSNumber*>*)getAllMeterValues
{
    const auto packed = JuceEngine::get().getAllMeterValues();

    NSMutableArray<NSNumber*>* arr = [NSMutableArray arrayWithCapacity:packed.size()];
    for (float v : packed) {
        [arr addObject:@(v)];
    }
    return arr;
}

// ===============================
// COMPRESSOR METER STRIPS
// [inRmsL, inRmsR, grDb, outRmsL, outRmsR]
// ===============================
+ (NSArray<NSNumber*>*)getClipCompressorMeterObjC:(NSInteger)clipIndex effectIndex:(NSInteger)effectIndex
{
    auto v = JuceEngine::get().getClipCompressorMeter((int)clipIndex, (int)effectIndex);
    return @[@(v[0]), @(v[1]), @(v[2]), @(v[3]), @(v[4])];
}

+ (NSArray<NSNumber*>*)getRowCompressorMeterObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex
{
    auto v = JuceEngine::get().getRowCompressorMeter((int)row, (int)effectIndex);
    return @[@(v[0]), @(v[1]), @(v[2]), @(v[3]), @(v[4])];
}

+ (NSArray<NSNumber*>*)getMasterCompressorMeterObjC:(NSInteger)effectIndex
{
    auto v = JuceEngine::get().getMasterCompressorMeter((int)effectIndex);
    return @[@(v[0]), @(v[1]), @(v[2]), @(v[3]), @(v[4])];
}

+ (double)getHostSampleRateObjC
{
    return JuceEngine::get().getHostSampleRate();
}

+ (NSArray<NSNumber*>*)getRecentMasterWaveformObjC:(NSInteger)sampleCount
{
    const auto v = JuceEngine::get().getRecentMasterWaveform((int)sampleCount);
    NSMutableArray<NSNumber*>* arr = [NSMutableArray arrayWithCapacity:v.size()];
    for (float s : v)
        [arr addObject:@(s)];
    return arr;
}

+ (NSArray<NSNumber*>*)getRowEqWaveformObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex sampleCount:(NSInteger)sampleCount
{
    const auto v = JuceEngine::get().getRowEqWaveform((int)row, (int)effectIndex, (int)sampleCount);
    NSMutableArray<NSNumber*>* arr = [NSMutableArray arrayWithCapacity:v.size()];
    for (float s : v)
        [arr addObject:@(s)];
    return arr;
}

+ (NSArray<NSNumber*>*)getMasterEqWaveformObjC:(NSInteger)effectIndex sampleCount:(NSInteger)sampleCount
{
    const auto v = JuceEngine::get().getMasterEqWaveform((int)effectIndex, (int)sampleCount);
    NSMutableArray<NSNumber*>* arr = [NSMutableArray arrayWithCapacity:v.size()];
    for (float s : v)
        [arr addObject:@(s)];
    return arr;
}

+ (NSArray<NSNumber*>*)getRowStereoScopeObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex pointCount:(NSInteger)pointCount
{
    const auto v = JuceEngine::get().getRowStereoScope((int)row, (int)effectIndex, (int)pointCount);
    NSMutableArray<NSNumber*>* arr = [NSMutableArray arrayWithCapacity:v.size()];
    for (float s : v)
        [arr addObject:@(s)];
    return arr;
}

+ (NSArray<NSNumber*>*)getMasterStereoScopeObjC:(NSInteger)effectIndex pointCount:(NSInteger)pointCount
{
    const auto v = JuceEngine::get().getMasterStereoScope((int)effectIndex, (int)pointCount);
    NSMutableArray<NSNumber*>* arr = [NSMutableArray arrayWithCapacity:v.size()];
    for (float s : v)
        [arr addObject:@(s)];
    return arr;
}

+ (NSArray<NSNumber*>*)getRowShaperPreviewObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex pointCount:(NSInteger)pointCount
{
    const auto v = JuceEngine::get().getRowShaperPreview((int)row, (int)effectIndex, (int)pointCount);
    NSMutableArray<NSNumber*>* arr = [NSMutableArray arrayWithCapacity:v.size()];
    for (float s : v)
        [arr addObject:@(s)];
    return arr;
}

+ (NSArray<NSNumber*>*)getMasterShaperPreviewObjC:(NSInteger)effectIndex pointCount:(NSInteger)pointCount
{
    const auto v = JuceEngine::get().getMasterShaperPreview((int)effectIndex, (int)pointCount);
    NSMutableArray<NSNumber*>* arr = [NSMutableArray arrayWithCapacity:v.size()];
    for (float s : v)
        [arr addObject:@(s)];
    return arr;
}


@end
