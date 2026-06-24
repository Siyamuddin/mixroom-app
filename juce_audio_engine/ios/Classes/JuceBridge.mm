#include <float.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <memory>
#include <vector>
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
#import <QuartzCore/QuartzCore.h>
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
static const void *kMixroomEmbeddedPluginChromeHelperKey =
    &kMixroomEmbeddedPluginChromeHelperKey;
static BOOL gMixroomHostedPluginWindowsDetached = NO;
static BOOL gMixroomDesktopKeyboardMidiForwardingEnabled = NO;
extern "C" void mixroomSetHostedPluginWindowsDetached(BOOL detached);
extern "C" void mixroomSetDesktopKeyboardMidiForwardingEnabled(BOOL enabled);
extern "C" void mixroomRequestHostedPluginEditorClose(void *ownerHandle);
extern "C" void mixroomRequestHostedPluginAutomationForOwner(void *ownerHandle);
extern "C" void mixroomSetHostedPluginWindowDetachedForOwner(void *ownerHandle,
                                                             bool detached);
extern "C" void *mixroomGetFlutterHostNativeView(void);
extern "C" bool mixroomGetNativeViewSize(void *nativeView,
                                          double *width,
                                          double *height);
extern "C" bool mixroomGetFlutterHostWindowContentSize(double *width,
                                                        double *height);
extern "C" void mixroomSetNativeViewFrameScale(void *nativeView,
                                                double x,
                                                double y,
                                                double logicalWidth,
                                                double logicalHeight,
                                                double scale);
extern "C" void mixroomConfigureEmbeddedPluginChrome(void *nativeView,
                                                      const char *title,
                                                      void *ownerHandle,
                                                      double scale);
extern "C" void mixroomReleaseEmbeddedPluginChrome(void *nativeView);
extern "C" void mixroomScheduleOttPluginEditorAutotest(void);
extern "C" void mixroomAdoptHostedPluginAuxiliaryWindows(int scopeKind,
                                                          int row,
                                                          int effectIndex,
                                                          int clipId,
                                                          void *ownerHandle);

static NSRect mixroomScreenContentRectForWindow(NSWindow *window) {
    if (window == nil) {
        return NSZeroRect;
    }
    NSRect rect = [window contentRectForFrameRect:window.frame];
    if (NSIsEmptyRect(rect)) {
        rect = window.frame;
    }
    NSScreen *screen = window.screen ?: NSScreen.mainScreen;
    if (screen != nil && !NSIsEmptyRect(screen.visibleFrame)) {
        rect = NSIntersectionRect(rect, screen.visibleFrame);
        if (NSIsEmptyRect(rect)) {
            rect = screen.visibleFrame;
        }
    }
    return rect;
}

static void mixroomPositionHostedPluginWindowInHost(NSWindow *pluginWindow,
                                                    NSWindow *hostWindow,
                                                    BOOL forceCenter) {
    if (pluginWindow == nil || hostWindow == nil) {
        return;
    }
    NSRect hostRect = mixroomScreenContentRectForWindow(hostWindow);
    if (NSIsEmptyRect(hostRect)) {
        return;
    }

    NSScreen *screen = hostWindow.screen ?: pluginWindow.screen ?: NSScreen.mainScreen;
    NSRect visibleRect = screen != nil && !NSIsEmptyRect(screen.visibleFrame)
                             ? screen.visibleFrame
                             : hostRect;
    NSRect usableRect = visibleRect;
    usableRect = NSInsetRect(usableRect, 24.0, 24.0);
    if (usableRect.size.width < 360.0 || usableRect.size.height < 240.0) {
        usableRect = visibleRect;
    }
    if (NSIsEmptyRect(usableRect)) {
        return;
    }

    NSSize desiredContentSize =
        pluginWindow.contentView != nil ? pluginWindow.contentView.bounds.size : NSZeroSize;
    for (NSView *subview in pluginWindow.contentView.subviews) {
        desiredContentSize.width =
            MAX(desiredContentSize.width, MAX(subview.bounds.size.width, subview.frame.size.width));
        desiredContentSize.height =
            MAX(desiredContentSize.height, MAX(subview.bounds.size.height, subview.frame.size.height));
    }
    const CGFloat maxContentWidth = MAX(320.0, MIN(1400.0, usableRect.size.width));
    const CGFloat maxContentHeight = MAX(220.0, MIN(920.0, usableRect.size.height));
    if (desiredContentSize.width > 0.0 && desiredContentSize.height > 0.0) {
        desiredContentSize.width =
            MIN(MAX(desiredContentSize.width, 320.0), maxContentWidth);
        desiredContentSize.height =
            MIN(MAX(desiredContentSize.height, 220.0), maxContentHeight);
    }

    NSRect frame = pluginWindow.frame;
    if (desiredContentSize.width > 0.0 && desiredContentSize.height > 0.0) {
        NSRect contentFrame = [pluginWindow frameRectForContentRect:
            NSMakeRect(0.0, 0.0, desiredContentSize.width, desiredContentSize.height)];
        frame.size.width = MAX(frame.size.width, contentFrame.size.width);
        frame.size.height = MAX(frame.size.height, contentFrame.size.height);
    }

    NSRect maxContentFrame = [pluginWindow frameRectForContentRect:
        NSMakeRect(0.0, 0.0, maxContentWidth, maxContentHeight)];
    const CGFloat maxWidth =
        MAX(320.0, MIN(maxContentFrame.size.width, usableRect.size.width));
    const CGFloat maxHeight =
        MAX(220.0, MIN(maxContentFrame.size.height, usableRect.size.height));
    frame.size.width = MIN(MAX(frame.size.width, 320.0), maxWidth);
    frame.size.height = MIN(MAX(frame.size.height, 220.0), maxHeight);

    if (forceCenter || !NSIntersectsRect(frame, hostRect)) {
        frame.origin.x = NSMidX(hostRect) - (frame.size.width / 2.0);
        frame.origin.y = NSMidY(hostRect) - (frame.size.height / 2.0);
    }

    frame.origin.x = MIN(MAX(frame.origin.x, NSMinX(usableRect)),
                         NSMaxX(usableRect) - frame.size.width);
    frame.origin.y = MIN(MAX(frame.origin.y, NSMinY(usableRect)),
                         NSMaxY(usableRect) - frame.size.height);
    [pluginWindow setFrame:frame display:YES animate:NO];
}

static NSWindow *mixroomFindFlutterHostWindow(void) {
    for (NSWindow *candidate in NSApp.orderedWindows) {
        if ([candidate.contentViewController isKindOfClass:NSClassFromString(@"FlutterViewController")]) {
            return candidate;
        }
    }
    for (NSWindow *candidate in NSApp.windows) {
        if ([candidate.contentViewController isKindOfClass:NSClassFromString(@"FlutterViewController")]) {
            return candidate;
        }
    }
    return NSApp.mainWindow ?: NSApp.keyWindow;
}

extern "C" void *mixroomGetFlutterHostNativeView(void) {
    __block NSView *hostView = nil;
    void (^resolveHostView)(void) = ^{
        NSWindow *hostWindow = mixroomFindFlutterHostWindow();
        hostView = hostWindow.contentView;
    };
    if ([NSThread isMainThread]) {
        resolveHostView();
    } else {
        dispatch_sync(dispatch_get_main_queue(), resolveHostView);
    }
    return (__bridge void *)hostView;
}

extern "C" bool mixroomGetNativeViewSize(void *nativeView,
                                          double *width,
                                          double *height) {
    if (nativeView == nullptr) {
        return false;
    }
    __block NSSize size = NSZeroSize;
    void (^readSize)(void) = ^{
        NSView *view = (__bridge NSView *)nativeView;
        size = view.bounds.size;
    };
    if ([NSThread isMainThread]) {
        readSize();
    } else {
        dispatch_sync(dispatch_get_main_queue(), readSize);
    }
    if (width != nullptr) {
        *width = (double)size.width;
    }
    if (height != nullptr) {
        *height = (double)size.height;
    }
    return size.width > 0.0 && size.height > 0.0;
}

extern "C" bool mixroomGetFlutterHostWindowContentSize(double *width,
                                                        double *height) {
    __block NSSize size = NSZeroSize;
    void (^readSize)(void) = ^{
        NSWindow *hostWindow = mixroomFindFlutterHostWindow();
        NSScreen *screen = hostWindow.screen ?: NSScreen.mainScreen;
        NSRect rect = screen != nil ? screen.visibleFrame : NSZeroRect;
        if (NSIsEmptyRect(rect)) {
            rect = mixroomScreenContentRectForWindow(hostWindow);
        }
        if (!NSIsEmptyRect(rect)) {
            size = rect.size;
        }
    };
    if ([NSThread isMainThread]) {
        readSize();
    } else {
        dispatch_sync(dispatch_get_main_queue(), readSize);
    }
    if (width != nullptr) {
        *width = (double)size.width;
    }
    if (height != nullptr) {
        *height = (double)size.height;
    }
    return size.width > 0.0 && size.height > 0.0;
}

extern "C" void mixroomSetNativeViewFrameScale(void *nativeView,
                                                double x,
                                                double y,
                                                double logicalWidth,
                                                double logicalHeight,
                                                double scale) {
    if (nativeView == nullptr || logicalWidth <= 0.0 || logicalHeight <= 0.0) {
        return;
    }
    void (^applyFrame)(void) = ^{
        NSView *view = (__bridge NSView *)nativeView;
        NSView *hostView = view.superview;
        if (hostView == nil) {
            return;
        }
        const CGFloat safeScale = MAX(0.25, MIN(1.0, (CGFloat)scale));
        const CGFloat displayWidth = (CGFloat)logicalWidth * safeScale;
        const CGFloat displayHeight = (CGFloat)logicalHeight * safeScale;
        CGFloat frameY = (CGFloat)y;
        if (!hostView.isFlipped) {
            frameY = hostView.bounds.size.height - (CGFloat)y - displayHeight;
        }
        view.frame = NSMakeRect((CGFloat)x, frameY, displayWidth, displayHeight);
        view.bounds = NSMakeRect(0.0, 0.0, (CGFloat)logicalWidth, (CGFloat)logicalHeight);
    };
    if ([NSThread isMainThread]) {
        applyFrame();
    } else {
        dispatch_async(dispatch_get_main_queue(), applyFrame);
    }
}

@class MixroomEmbeddedPluginChromeHelper;

@interface MixroomEmbeddedPluginChromeView : NSVisualEffectView
@property(nonatomic, assign) MixroomEmbeddedPluginChromeHelper *helper;
@end

@interface MixroomEmbeddedPluginChromeHelper : NSObject
@property(nonatomic, assign) NSView *pluginView;
@property(nonatomic, strong) MixroomEmbeddedPluginChromeView *barView;
@property(nonatomic, strong) NSTextField *titleField;
@property(nonatomic, strong) CATextLayer *titleLayer;
@property(nonatomic, strong) NSButton *titleButton;
@property(nonatomic, strong) NSButton *optionsButton;
@property(nonatomic, strong) NSButton *closeButton;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, assign) void *ownerHandle;
@property(nonatomic, assign) CGFloat scale;
@property(nonatomic, assign) NSPoint dragStartPoint;
@property(nonatomic, assign) NSRect dragStartPluginFrame;
@property(nonatomic, assign) id keyMonitor;
- (instancetype)initWithPluginView:(NSView *)pluginView
                              title:(NSString *)title
                        ownerHandle:(void *)ownerHandle
                              scale:(CGFloat)scale;
- (void)updateLayout;
- (void)beginDragWithEvent:(NSEvent *)event;
- (void)dragWithEvent:(NSEvent *)event;
- (void)closePlugin;
- (void)detach;
- (void)invalidate;
@end

@implementation MixroomEmbeddedPluginChromeView

- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    MixroomEmbeddedPluginChromeHelper *helper = self.helper;
    if (helper != nil) {
        [helper beginDragWithEvent:event];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    MixroomEmbeddedPluginChromeHelper *helper = self.helper;
    if (helper != nil) {
        [helper dragWithEvent:event];
    }
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53) {
        MixroomEmbeddedPluginChromeHelper *helper = self.helper;
        if (helper != nil) {
            [helper closePlugin];
        }
        return;
    }
    [super keyDown:event];
}

@end

@implementation MixroomEmbeddedPluginChromeHelper

- (instancetype)initWithPluginView:(NSView *)pluginView
                              title:(NSString *)title
                        ownerHandle:(void *)ownerHandle
                              scale:(CGFloat)scale {
    self = [super init];
    if (self != nil) {
        _pluginView = pluginView;
        _title = [title copy] ?: @"Plugin";
        _ownerHandle = ownerHandle;
        _scale = scale;

        _barView = [[MixroomEmbeddedPluginChromeView alloc] initWithFrame:NSZeroRect];
        _barView.helper = self;
        _barView.material = NSVisualEffectMaterialHeaderView;
        _barView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
        _barView.state = NSVisualEffectStateActive;
        _barView.wantsLayer = YES;
        _barView.layer.cornerRadius = 10.0;
        _barView.layer.masksToBounds = YES;
        _barView.layer.backgroundColor =
            [NSColor colorWithCalibratedRed:0.055 green:0.075 blue:0.105 alpha:0.98].CGColor;
        _barView.layer.borderWidth = 1.0;
        _barView.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.14].CGColor;

        CALayer *accent = [CALayer layer];
        accent.name = @"accent";
        accent.backgroundColor = [NSColor colorWithCalibratedRed:0.33 green:0.78 blue:1.0 alpha:0.42].CGColor;
        accent.cornerRadius = 2.0;
        [_barView.layer addSublayer:accent];

        _titleField = [NSTextField labelWithString:_title];
        _titleField.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
        _titleField.textColor = [NSColor colorWithWhite:1.0 alpha:0.90];
        _titleField.lineBreakMode = NSLineBreakByTruncatingTail;
        [_barView addSubview:_titleField];
        _titleField.hidden = YES;

        _titleLayer = [CATextLayer layer];
        _titleLayer.string = _title;
        _titleLayer.fontSize = 13.0;
        _titleLayer.truncationMode = kCATruncationEnd;
        _titleLayer.alignmentMode = kCAAlignmentLeft;
        _titleLayer.contentsScale = NSScreen.mainScreen.backingScaleFactor;
        _titleLayer.foregroundColor = [NSColor colorWithWhite:1.0 alpha:0.90].CGColor;
        [_barView.layer addSublayer:_titleLayer];

        _titleButton = [NSButton buttonWithTitle:_title target:nil action:nil];
        _titleButton.bordered = NO;
        _titleButton.enabled = NO;
        _titleButton.hidden = YES;
        _titleButton.alignment = NSTextAlignmentLeft;
        _titleButton.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
        _titleButton.contentTintColor = [NSColor colorWithWhite:1.0 alpha:0.92];
        [_barView addSubview:_titleButton];

        _optionsButton = [NSButton buttonWithTitle:@"..."
                                            target:self
                                            action:@selector(showOptions:)];
        _closeButton = [NSButton buttonWithTitle:@"x"
                                          target:self
                                          action:@selector(closePlugin:)];
        for (NSButton *button in @[_optionsButton, _closeButton]) {
            button.bezelStyle = NSBezelStyleTexturedRounded;
            button.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
            button.contentTintColor = [NSColor colorWithWhite:1.0 alpha:0.85];
            button.focusRingType = NSFocusRingTypeNone;
            [_barView addSubview:button];
        }

        MixroomEmbeddedPluginChromeHelper *blockSelf = self;
        _keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                            handler:^NSEvent *(NSEvent *event) {
            MixroomEmbeddedPluginChromeHelper *strongSelf = blockSelf;
            if (strongSelf == nil || event.keyCode != 53) {
                return event;
            }
            if (strongSelf.barView.window == nil ||
                event.window != strongSelf.barView.window) {
                return event;
            }
            [strongSelf closePlugin];
            return nil;
        }];
    }
    return self;
}

- (void)showOptions:(id)sender {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *floatItem = [[NSMenuItem alloc] initWithTitle:@"Float Plugin Window"
                                                       action:@selector(floatPlugin:)
                                                keyEquivalent:@""];
    floatItem.target = self;
    [menu addItem:floatItem];
    [menu popUpMenuPositioningItem:nil
                        atLocation:NSMakePoint(0.0, self.optionsButton.bounds.size.height + 4.0)
                            inView:self.optionsButton];
}

- (void)floatPlugin:(id)sender {
    [self detach];
}

- (void)closePlugin:(id)sender {
    [self closePlugin];
}

- (void)closePlugin {
    void *ownerHandle = self.ownerHandle;
    [self invalidate];
    if (ownerHandle != nullptr) {
        mixroomRequestHostedPluginEditorClose(ownerHandle);
    }
}

- (void)detach {
    if (self.ownerHandle != nullptr) {
        mixroomSetHostedPluginWindowDetachedForOwner(self.ownerHandle, true);
    }
}

- (NSPoint)hostPointForEvent:(NSEvent *)event {
    NSView *hostView = self.pluginView.superview;
    if (hostView == nil) {
        return NSZeroPoint;
    }
    return [hostView convertPoint:event.locationInWindow fromView:nil];
}

- (void)beginDragWithEvent:(NSEvent *)event {
    self.dragStartPoint = [self hostPointForEvent:event];
    self.dragStartPluginFrame = self.pluginView.frame;
}

- (void)dragWithEvent:(NSEvent *)event {
    NSView *pluginView = self.pluginView;
    NSView *hostView = pluginView.superview;
    if (pluginView == nil || hostView == nil) {
        return;
    }
    NSPoint point = [self hostPointForEvent:event];
    NSRect frame = self.dragStartPluginFrame;
    frame.origin.x += point.x - self.dragStartPoint.x;
    frame.origin.y += point.y - self.dragStartPoint.y;
    frame.origin.x = MAX(0.0, MIN(frame.origin.x, hostView.bounds.size.width - frame.size.width));
    frame.origin.y = MAX(0.0, MIN(frame.origin.y, hostView.bounds.size.height - frame.size.height));
    pluginView.frame = frame;
    [self updateLayout];
}

- (void)updateLayout {
    NSView *pluginView = self.pluginView;
    NSView *hostView = pluginView.superview;
    if (pluginView == nil || hostView == nil) {
        [self.barView removeFromSuperview];
        return;
    }
    if (self.barView.superview != hostView) {
        [hostView addSubview:self.barView positioned:NSWindowAbove relativeTo:pluginView];
    }

    const CGFloat pluginScale = MAX(0.45, MIN(1.0, self.scale));
    const CGFloat barHeight = MAX(34.0, round(42.0 * pluginScale));
    NSRect pluginFrame = pluginView.frame;
    NSRect barFrame = pluginFrame;
    barFrame.size.height = barHeight;
    if (hostView.isFlipped) {
        barFrame.origin.y = pluginFrame.origin.y;
    } else {
        barFrame.origin.y = NSMaxY(pluginFrame) - barHeight;
    }
    self.barView.frame = NSIntegralRect(barFrame);

    CALayer *accent = [self.barView.layer.sublayers firstObject];
    accent.frame = CGRectMake(12.0, round((barHeight - 20.0) * 0.5), 4.0, 20.0);

    const CGFloat controlWidth = 34.0;
    const CGFloat controlHeight = 24.0;
    const CGFloat controlGap = 8.0;
    const CGFloat rightInset = 12.0;
    const CGFloat controlY = round((barHeight - controlHeight) * 0.5);
    self.closeButton.frame = NSMakeRect(NSWidth(self.barView.bounds) - rightInset - controlWidth,
                                        controlY,
                                        controlWidth,
                                        controlHeight);
    self.optionsButton.frame = NSMakeRect(NSMinX(self.closeButton.frame) - controlGap - controlWidth,
                                          controlY,
                                          controlWidth,
                                          controlHeight);
    self.titleField.frame = NSMakeRect(26.0,
                                       controlY + 2.0,
                                       MAX(80.0, NSMinX(self.optionsButton.frame) - 34.0),
                                       controlHeight);
    self.titleLayer.frame = CGRectMake(26.0,
                                       controlY + 4.0,
                                       MAX(80.0, NSMinX(self.optionsButton.frame) - 34.0),
                                       controlHeight);
    self.titleButton.frame = NSMakeRect(24.0,
                                        controlY,
                                        MAX(80.0, NSMinX(self.optionsButton.frame) - 32.0),
                                        controlHeight);
}

- (void)invalidate {
    if (self.keyMonitor != nil) {
        [NSEvent removeMonitor:self.keyMonitor];
        self.keyMonitor = nil;
    }
    self.barView.helper = nil;
    [self.barView removeFromSuperview];
    self.pluginView = nil;
    self.ownerHandle = nullptr;
}

- (void)dealloc {
    [self invalidate];
}

@end

extern "C" void mixroomConfigureEmbeddedPluginChrome(void *nativeView,
                                                      const char *title,
                                                      void *ownerHandle,
                                                      double scale) {
    if (nativeView == nullptr) {
        return;
    }
    NSString *copiedTitle =
        title != nullptr ? [NSString stringWithUTF8String:title] : nil;
    if (copiedTitle == nil || copiedTitle.length == 0) {
        copiedTitle = @"Plugin";
    }
    void (^configureChrome)(void) = ^{
        NSView *pluginView = (__bridge NSView *)nativeView;
        NSString *headerTitle = copiedTitle;
        MixroomEmbeddedPluginChromeHelper *helper =
            objc_getAssociatedObject(pluginView, kMixroomEmbeddedPluginChromeHelperKey);
        if (helper == nil) {
            helper = [[MixroomEmbeddedPluginChromeHelper alloc] initWithPluginView:pluginView
                                                                             title:headerTitle
                                                                       ownerHandle:ownerHandle
                                                                             scale:(CGFloat)scale];
            objc_setAssociatedObject(pluginView,
                                     kMixroomEmbeddedPluginChromeHelperKey,
                                     helper,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else {
            helper.title = headerTitle;
            helper.titleField.stringValue = headerTitle;
            helper.titleLayer.string = headerTitle;
            helper.titleButton.title = headerTitle;
            [helper.titleLayer setNeedsDisplay];
            helper.ownerHandle = ownerHandle;
            helper.scale = (CGFloat)scale;
        }
        [helper updateLayout];
    };
    if ([NSThread isMainThread]) {
        configureChrome();
    } else {
        dispatch_async(dispatch_get_main_queue(), configureChrome);
    }
}

extern "C" void mixroomReleaseEmbeddedPluginChrome(void *nativeView) {
    if (nativeView == nullptr) {
        return;
    }
    void (^releaseChrome)(void) = ^{
        NSView *pluginView = (__bridge NSView *)nativeView;
        MixroomEmbeddedPluginChromeHelper *helper =
            objc_getAssociatedObject(pluginView, kMixroomEmbeddedPluginChromeHelperKey);
        if (helper != nil) {
            [helper invalidate];
            objc_setAssociatedObject(pluginView,
                                     kMixroomEmbeddedPluginChromeHelperKey,
                                     nil,
                                     OBJC_ASSOCIATION_ASSIGN);
        }
    };
    if ([NSThread isMainThread]) {
        releaseChrome();
    } else {
        dispatch_async(dispatch_get_main_queue(), releaseChrome);
    }
}

static void mixroomLogMacWindowSnapshot(NSString *label) {
    NSLog(@"[Mixroom OTT Autotest] %@ windowCount=%lu", label,
          (unsigned long)NSApp.windows.count);
    for (NSWindow *window in NSApp.windows) {
        NSLog(@"[Mixroom OTT Autotest] window title='%@' class=%@ parent=%@ contentView=%@ controller=%@ frame=%@",
              window.title ?: @"",
              NSStringFromClass(window.class),
              window.parentWindow != nil ? @"yes" : @"no",
              window.contentView != nil ? NSStringFromClass(window.contentView.class) : @"nil",
              window.contentViewController != nil ? NSStringFromClass(window.contentViewController.class) : @"nil",
              NSStringFromRect(window.frame));
    }
}

extern "C" void mixroomScheduleOttPluginEditorAutotest(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSLog(@"[Mixroom OTT Autotest] starting");
        mixroomLogMacWindowSnapshot(@"before");
        juce::MessageManager::callAsync([] {
            auto &engine = JuceEngine::get();
            engine.initialiseEngine();
            const auto previousRows = engine.getRows();
            int rowIndex = previousRows.size();
            const int rowId = engine.addRow("OTT Autotest", 0);
            if (rowId < 0) {
                const auto rows = engine.getRows();
                rowIndex = juce::jmax(0, rows.size() - 1);
            }

            const char *pluginPathEnv = std::getenv("MIXROOM_AUTOTEST_PLUGIN_PATH");
            const juce::String pluginPath(
                pluginPathEnv != nullptr && std::strlen(pluginPathEnv) > 0
                    ? pluginPathEnv
                    : "/Library/Audio/Plug-Ins/VST3/OTT.vst3");
            const bool inserted = engine.insertTrackEffect(rowIndex, pluginPath);
            const bool opened = inserted && engine.openTrackPluginEditor(rowIndex, 0);
            const juce::String result =
                "OTT autotest inserted=" + juce::String(inserted ? "true" : "false") +
                " opened=" + juce::String(opened ? "true" : "false") +
                " rowIndex=" + juce::String(rowIndex) +
                " path=" + pluginPath;
            juceLogToFlutter(result.toRawUTF8());
            NSLog(@"[Mixroom OTT Autotest] %s", result.toRawUTF8());
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                mixroomLogMacWindowSnapshot(@"after-open");
                const char *closeEnv = std::getenv("MIXROOM_AUTOTEST_OTT_CLOSE");
                if (closeEnv == nullptr || std::strcmp(closeEnv, "1") != 0) {
                    return;
                }
                for (NSWindow *window in [NSApp.windows copy]) {
                    if (![window.title isEqualToString:@"Track FX: OTT"]) {
                        continue;
                    }
                    NSLog(@"[Mixroom OTT Autotest] closing hosted OTT window");
                    [window close];
                    dispatch_after(
                        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{
                            mixroomLogMacWindowSnapshot(@"after-close");
                        });
                    return;
                }
                NSLog(@"[Mixroom OTT Autotest] close requested but hosted OTT window was not found");
            });
        });
    });
}

@interface MixroomHostedPluginWindowHelper : NSObject
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, assign) id eventMonitor;
@property(nonatomic, strong) id closeObserver;
@property(nonatomic, strong) NSTitlebarAccessoryViewController *automationAccessory;
@property(nonatomic, strong) NSButton *automationButton;
@property(nonatomic, copy) NSDictionary<NSString *, id> *metadata;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *heldDesktopMidiKeyCodes;
@property(nonatomic, assign) BOOL positionedOnce;
@property(nonatomic, assign) BOOL closing;
- (instancetype)initWithWindow:(NSWindow *)window
                      metadata:(NSDictionary<NSString *, id> *)metadata;
- (void)applyWindowMode;
- (void)removeEventMonitorIfNeeded;
- (void)installAutomationAccessoryIfNeededForWindow:(id)window;
- (void)removeDuplicateAutomationAccessoriesFromWindow:(id)window;
- (void)removeAutomationAccessoryFromWindow:(id)window;
- (void)releaseHeldDesktopMidiNotes;
- (void)requestAutomation:(id)sender;
@end

static MixroomHostedPluginWindowHelper *mixroomHostedPluginHelperForWindow(
    NSWindow *window) {
    if (window == nil) {
        return nil;
    }
    id helper = objc_getAssociatedObject(
        window,
        kMixroomHostedPluginWindowHelperKey);
    if (![helper isKindOfClass:MixroomHostedPluginWindowHelper.class]) {
        return nil;
    }
    return (MixroomHostedPluginWindowHelper *)helper;
}

static NSInteger mixroomDesktopMidiPitchForMacKeyCode(unsigned short keyCode) {
    switch (keyCode) {
        case 0: return 60;   // A
        case 13: return 61;  // W
        case 1: return 62;   // S
        case 14: return 63;  // E
        case 2: return 64;   // D
        case 3: return 65;   // F
        case 17: return 66;  // T
        case 5: return 67;   // G
        case 16: return 68;  // Y
        case 4: return 69;   // H
        case 32: return 70;  // U
        case 38: return 71;  // J
        case 40: return 72;  // K
        case 31: return 73;  // O
        case 37: return 74;  // L
        case 35: return 75;  // P
        case 41: return 76;  // ;
        case 39: return 77;  // '
        default: return -1;
    }
}

static BOOL mixroomRemoveTitlebarAccessoryFromWindow(
    id window,
    NSTitlebarAccessoryViewController *accessory) {
    if (window == nil ||
        accessory == nil ||
        ![window respondsToSelector:@selector(titlebarAccessoryViewControllers)] ||
        ![window respondsToSelector:@selector(removeTitlebarAccessoryViewControllerAtIndex:)]) {
        return NO;
    }
    NSArray<NSTitlebarAccessoryViewController *> *controllers =
        [(NSWindow *)window titlebarAccessoryViewControllers];
    const NSUInteger index = [controllers indexOfObject:accessory];
    if (index == NSNotFound) {
        return NO;
    }
    @try {
        [(NSWindow *)window removeTitlebarAccessoryViewControllerAtIndex:(NSInteger)index];
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"Mixroom: ignored hosted plugin titlebar accessory removal exception: %@", exception);
        return NO;
    }
}

static void mixroomRetainObjectThroughPendingAppKitLayerFlush(id object) {
    if (object == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        static NSMutableArray *retainedObjects = nil;
        if (retainedObjects == nil) {
            retainedObjects = [[NSMutableArray alloc] init];
        }
        [retainedObjects addObject:object];
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                [retainedObjects removeObject:object];
            });
    });
}

@implementation MixroomHostedPluginWindowHelper

- (instancetype)initWithWindow:(NSWindow *)window
                      metadata:(NSDictionary<NSString *, id> *)metadata {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    self.window = window;
    self.metadata = metadata;
    self.heldDesktopMidiKeyCodes = [NSMutableSet set];
    self.closing = NO;
    MixroomHostedPluginWindowHelper *blockSelf = self;
    self.closeObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSWindowWillCloseNotification
                    object:window
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification * _Nonnull note) {
                    MixroomHostedPluginWindowHelper *strongSelf = blockSelf;
                    if (strongSelf == nil) {
                        return;
                    }
                    strongSelf.closing = YES;
                    NSWindow *closingWindow =
                        [note.object isKindOfClass:NSWindow.class]
                            ? (NSWindow *)note.object
                            : strongSelf.window;
                    [strongSelf removeEventMonitorIfNeeded];
                    [strongSelf releaseHeldDesktopMidiNotes];
                    if (closingWindow.parentWindow != nil) {
                        [closingWindow.parentWindow removeChildWindow:closingWindow];
                    }
                    [strongSelf removeAutomationAccessoryFromWindow:closingWindow];
                    NSMutableDictionary<NSString *, id> *payload =
                        [NSMutableDictionary dictionaryWithDictionary:strongSelf.metadata ?: @{}];
                    payload[@"event"] = @"pluginEditorClosed";
                    if (strongSelf.closeObserver != nil) {
                        [[NSNotificationCenter defaultCenter] removeObserver:strongSelf.closeObserver];
                        strongSelf.closeObserver = nil;
                    }
                    if (closingWindow != nil) {
                        objc_setAssociatedObject(
                            closingWindow,
                            kMixroomHostedPluginWindowHelperKey,
                            nil,
                            OBJC_ASSOCIATION_ASSIGN);
                    }
                    strongSelf.window = nil;
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
         NSEventMaskKeyUp |
         NSEventMaskRightMouseDown |
         NSEventMaskOtherMouseDown |
         NSEventMaskLeftMouseDown)
        handler:^NSEvent * _Nullable(NSEvent *event) {
            MixroomHostedPluginWindowHelper *strongSelf = blockSelf;
            if (strongSelf == nil || strongSelf.closing || strongSelf.window == nil) {
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
            const BOOL isMidiClipWindow =
                [strongSelf.metadata[@"scopeKind"] integerValue] == 3 &&
                [strongSelf.metadata[@"clipId"] integerValue] >= 0;
            const NSEventModifierFlags modifierMask =
                event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
            const BOOL hasCommandControlOrOption =
                (modifierMask & (NSEventModifierFlagCommand |
                                 NSEventModifierFlagControl |
                                 NSEventModifierFlagOption)) != 0;
            const BOOL isKeyEvent =
                event.type == NSEventTypeKeyDown ||
                event.type == NSEventTypeKeyUp;
            if (isKeyEvent &&
                gMixroomDesktopKeyboardMidiForwardingEnabled &&
                isMidiClipWindow &&
                !hasCommandControlOrOption) {
                const NSInteger pitch =
                    mixroomDesktopMidiPitchForMacKeyCode(event.keyCode);
                if (pitch >= 0) {
                    NSMutableSet<NSNumber *> *heldKeys =
                        strongSelf.heldDesktopMidiKeyCodes;
                    if (heldKeys == nil) {
                        heldKeys = [NSMutableSet set];
                        strongSelf.heldDesktopMidiKeyCodes = heldKeys;
                    }
                    NSNumber *keyNumber = @(event.keyCode);
                    if (event.type == NSEventTypeKeyDown) {
                        if (![heldKeys containsObject:keyNumber]) {
                            [heldKeys addObject:keyNumber];
                            JuceEngine::get().sendLiveMidiInputEventForClip(
                                (int)[strongSelf.metadata[@"clipId"] integerValue],
                                true,
                                1,
                                (int)pitch,
                                0.92f);
                        }
                        return nil;
                    }
                    if (event.type == NSEventTypeKeyUp) {
                        if ([heldKeys containsObject:keyNumber]) {
                            [heldKeys removeObject:keyNumber];
                            JuceEngine::get().sendLiveMidiInputEventForClip(
                                (int)[strongSelf.metadata[@"clipId"] integerValue],
                                false,
                                1,
                                (int)pitch,
                                0.0f);
                        }
                        return nil;
                    }
                }
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
                    [strongSelf releaseHeldDesktopMidiNotes];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        mixroomRequestHostedPluginEditorClose((void *)ownerValue);
                    });
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
    NSWindow *hostWindow = mixroomFindFlutterHostWindow();
    return hostWindow != window ? hostWindow : (NSApp.mainWindow ?: NSApp.keyWindow);
}

- (void)removeEventMonitorIfNeeded {
    id monitor = self.eventMonitor;
    self.eventMonitor = nil;
    if (monitor == nil) {
        return;
    }
    @try {
        [NSEvent removeMonitor:monitor];
    } @catch (NSException *exception) {
        NSLog(@"Mixroom: ignored hosted plugin event monitor removal exception: %@", exception);
    }
}

- (void)applyWindowMode {
    NSWindow *pluginWindow = self.window;
    if (pluginWindow == nil) {
        return;
    }

    pluginWindow.releasedWhenClosed = NO;
    pluginWindow.toolbar = nil;
    pluginWindow.level = NSNormalWindowLevel;
    pluginWindow.collectionBehavior = NSWindowCollectionBehaviorManaged;

    const BOOL usesMixroomShell =
        [self.metadata[@"mixroomShell"] boolValue];
    NSButton *closeButton =
        [pluginWindow standardWindowButton:NSWindowCloseButton];
    NSButton *miniButton =
        [pluginWindow standardWindowButton:NSWindowMiniaturizeButton];
    NSButton *zoomButton =
        [pluginWindow standardWindowButton:NSWindowZoomButton];
    const NSInteger scopeKind = [self.metadata[@"scopeKind"] integerValue];
    const BOOL supportsAutomationButton = scopeKind == 1 || scopeKind == 2 || scopeKind == 3;

    NSWindow *hostWindow = [self mixroomHostWindow];
    if (gMixroomHostedPluginWindowsDetached || !usesMixroomShell) {
        if (gMixroomHostedPluginWindowsDetached) {
            if (pluginWindow.parentWindow != nil) {
                [pluginWindow.parentWindow removeChildWindow:pluginWindow];
            }
        } else if (hostWindow != nil && pluginWindow.parentWindow != hostWindow) {
            if (pluginWindow.parentWindow != nil) {
                [pluginWindow.parentWindow removeChildWindow:pluginWindow];
            }
            [hostWindow addChildWindow:pluginWindow ordered:NSWindowAbove];
        }
        pluginWindow.styleMask |= NSWindowStyleMaskTitled;
        pluginWindow.styleMask |= NSWindowStyleMaskClosable;
        pluginWindow.styleMask |= NSWindowStyleMaskMiniaturizable;
        pluginWindow.styleMask |= NSWindowStyleMaskResizable;
        pluginWindow.styleMask &= ~NSWindowStyleMaskFullSizeContentView;
        pluginWindow.titleVisibility = NSWindowTitleVisible;
        pluginWindow.titlebarAppearsTransparent = NO;
        pluginWindow.movableByWindowBackground = NO;
        pluginWindow.hasShadow = YES;
        pluginWindow.opaque = NO;
        pluginWindow.backgroundColor =
            [NSColor colorWithCalibratedRed:0.045 green:0.055 blue:0.070 alpha:1.0];
        pluginWindow.contentView.wantsLayer = YES;
        pluginWindow.contentView.layer.backgroundColor =
            [NSColor colorWithCalibratedRed:0.045 green:0.055 blue:0.070 alpha:1.0].CGColor;
        closeButton.hidden = NO;
        miniButton.hidden = NO;
        zoomButton.hidden = NO;
        if (supportsAutomationButton) {
            [self installAutomationAccessoryIfNeededForWindow:pluginWindow];
        } else {
            [self removeAutomationAccessoryFromWindow:pluginWindow];
        }
        if (hostWindow != nil) {
            mixroomPositionHostedPluginWindowInHost(
                pluginWindow,
                hostWindow,
                !self.positionedOnce);
            self.positionedOnce = YES;
        }
        return;
    }

    pluginWindow.titleVisibility = NSWindowTitleHidden;
    pluginWindow.titlebarAppearsTransparent = YES;
    pluginWindow.movableByWindowBackground = NO;
    pluginWindow.styleMask &= ~NSWindowStyleMaskTitled;
    pluginWindow.styleMask &= ~NSWindowStyleMaskClosable;
    pluginWindow.styleMask &= ~NSWindowStyleMaskMiniaturizable;
    pluginWindow.styleMask &= ~NSWindowStyleMaskResizable;
    pluginWindow.styleMask &= ~NSWindowStyleMaskFullSizeContentView;
    pluginWindow.hasShadow = YES;
    pluginWindow.opaque = NO;
    pluginWindow.backgroundColor = NSColor.clearColor;
    closeButton.hidden = YES;
    miniButton.hidden = YES;
    zoomButton.hidden = YES;
    [self removeAutomationAccessoryFromWindow:pluginWindow];

    const BOOL wasChildOfHost = hostWindow != nil &&
        pluginWindow.parentWindow == hostWindow;
    if (hostWindow != nil && !wasChildOfHost) {
        if (pluginWindow.parentWindow != nil) {
            [pluginWindow.parentWindow removeChildWindow:pluginWindow];
        }
        [hostWindow addChildWindow:pluginWindow ordered:NSWindowAbove];
    }

    if (hostWindow != nil) {
        mixroomPositionHostedPluginWindowInHost(
            pluginWindow,
            hostWindow,
            !self.positionedOnce);
        self.positionedOnce = YES;
    }
}

- (void)installAutomationAccessoryIfNeededForWindow:(id)window {
    if (window == nil ||
        ![window respondsToSelector:@selector(addTitlebarAccessoryViewController:)]) {
        return;
    }
    [self removeDuplicateAutomationAccessoriesFromWindow:window];
    if (self.automationAccessory != nil) {
        return;
    }
    NSButton *button = [NSButton buttonWithTitle:@"Automate"
                                         target:self
                                         action:@selector(requestAutomation:)];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold];
    button.toolTip = @"Automate the last touched plugin parameter";
    button.focusRingType = NSFocusRingTypeNone;
    button.frame = NSMakeRect(0.0, 0.0, 86.0, 26.0);

    NSTitlebarAccessoryViewController *accessory =
        [[NSTitlebarAccessoryViewController alloc] init];
    accessory.view = button;
    accessory.layoutAttribute = NSLayoutAttributeRight;
    @try {
        [(NSWindow *)window addTitlebarAccessoryViewController:accessory];
    } @catch (NSException *exception) {
        NSLog(@"Mixroom: ignored hosted plugin titlebar accessory add exception: %@", exception);
        return;
    }
    self.automationButton = button;
    self.automationAccessory = accessory;
}

- (void)removeDuplicateAutomationAccessoriesFromWindow:(id)window {
    if (window == nil ||
        ![window respondsToSelector:@selector(titlebarAccessoryViewControllers)] ||
        ![window respondsToSelector:@selector(removeTitlebarAccessoryViewControllerAtIndex:)]) {
        return;
    }
    for (NSTitlebarAccessoryViewController *accessory in
         [[(NSWindow *)window titlebarAccessoryViewControllers] copy]) {
        if (accessory == self.automationAccessory) {
            continue;
        }
        if (![accessory.view isKindOfClass:NSButton.class]) {
            continue;
        }
        NSButton *button = (NSButton *)accessory.view;
        if (![button.title isEqualToString:@"Automate"]) {
            continue;
        }
        button.target = nil;
        button.action = nil;
        mixroomRemoveTitlebarAccessoryFromWindow(window, accessory);
        mixroomRetainObjectThroughPendingAppKitLayerFlush(button);
        mixroomRetainObjectThroughPendingAppKitLayerFlush(accessory);
    }
}

- (void)removeAutomationAccessoryFromWindow:(id)window {
    NSTitlebarAccessoryViewController *accessory = self.automationAccessory;
    NSButton *button = self.automationButton;
    if (button != nil) {
        button.target = nil;
        button.action = nil;
    }
    if (window != nil && accessory != nil) {
        mixroomRemoveTitlebarAccessoryFromWindow(window, accessory);
    }
    if (button != nil) {
        mixroomRetainObjectThroughPendingAppKitLayerFlush(button);
    }
    if (accessory != nil) {
        mixroomRetainObjectThroughPendingAppKitLayerFlush(accessory);
        if (accessory.view != nil) {
            mixroomRetainObjectThroughPendingAppKitLayerFlush(accessory.view);
        }
    }
    self.automationAccessory = nil;
    self.automationButton = nil;
}

- (void)releaseHeldDesktopMidiNotes {
    NSMutableSet<NSNumber *> *heldKeys = self.heldDesktopMidiKeyCodes;
    if (heldKeys == nil) {
        self.heldDesktopMidiKeyCodes = [NSMutableSet set];
        return;
    }
    if (heldKeys.count == 0) {
        return;
    }
    const int clipId = (int)[self.metadata[@"clipId"] integerValue];
    for (NSNumber *keyNumber in [heldKeys copy]) {
        if (![keyNumber isKindOfClass:NSNumber.class]) {
            continue;
        }
        const NSInteger pitch =
            mixroomDesktopMidiPitchForMacKeyCode((unsigned short)keyNumber.unsignedShortValue);
        if (pitch >= 0 && clipId >= 0) {
            JuceEngine::get().sendLiveMidiInputEventForClip(
                clipId,
                false,
                1,
                (int)pitch,
                0.0f);
        }
    }
    [heldKeys removeAllObjects];
}

- (void)requestAutomation:(id)sender {
    const uintptr_t ownerValue =
        (uintptr_t)[self.metadata[@"ownerPtr"] unsignedLongLongValue];
    if (ownerValue != 0) {
        mixroomRequestHostedPluginAutomationForOwner((void *)ownerValue);
    }
}

- (void)dealloc {
    self.closing = YES;
    [self removeEventMonitorIfNeeded];
    [self releaseHeldDesktopMidiNotes];
    if (_closeObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:_closeObserver];
    }
    [self removeAutomationAccessoryFromWindow:self.window];
}

@end

static NSMutableDictionary<NSString *, id> *mixroomHostedPluginMetadata(
    int scopeKind,
    int row,
    int effectIndex,
    int clipId,
    void *ownerHandle) {
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
    return metadata;
}

static BOOL mixroomShouldAdoptPluginAuxiliaryWindow(NSWindow *window,
                                                     NSWindow *hostWindow) {
    if (window == nil || window == hostWindow) {
        return NO;
    }
    if (mixroomHostedPluginHelperForWindow(window) != nil) {
        return NO;
    }
    if (window.parentWindow == hostWindow) {
        return NO;
    }
    if ([window.contentViewController isKindOfClass:NSClassFromString(@"FlutterViewController")]) {
        return NO;
    }

    NSString *className = NSStringFromClass(window.class);
    if ([className isEqualToString:@"TUINSWindow"]) {
        return NO;
    }
    if ([className hasPrefix:@"JUCEWindow_"]) {
        return NO;
    }

    if (window.frame.size.width < 120.0 || window.frame.size.height < 120.0) {
        return NO;
    }
    return YES;
}

extern "C" void mixroomAdoptHostedPluginAuxiliaryWindows(int scopeKind,
                                                          int row,
                                                          int effectIndex,
                                                          int clipId,
                                                          void *ownerHandle) {
    void (^adoptAttempt)(void) = ^{
        NSWindow *hostWindow = mixroomFindFlutterHostWindow();
        if (hostWindow == nil) {
            return;
        }

        NSMutableDictionary<NSString *, id> *metadata =
            mixroomHostedPluginMetadata(scopeKind,
                                        row,
                                        effectIndex,
                                        clipId,
                                        ownerHandle);
        metadata[@"primaryWindow"] = @NO;
        for (NSWindow *window in NSApp.windows) {
            if (!mixroomShouldAdoptPluginAuxiliaryWindow(window, hostWindow)) {
                continue;
            }
            MixroomHostedPluginWindowHelper *helper =
                [[MixroomHostedPluginWindowHelper alloc] initWithWindow:window
                                                               metadata:metadata];
            [helper applyWindowMode];
            objc_setAssociatedObject(
                window,
                kMixroomHostedPluginWindowHelperKey,
                helper,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSLog(@"[Mixroom Plugin Host] adopted auxiliary plugin window class=%@ frame=%@",
                  NSStringFromClass(window.class),
                  NSStringFromRect(window.frame));
        }
    };

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   adoptAttempt);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.00 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   adoptAttempt);
}

extern "C" void mixroomCloseHostedPluginNativeWindowsForOwner(void *ownerHandle) {
    if (ownerHandle == nullptr) {
        return;
    }

    void (^closeWindows)(void) = ^{
        NSArray<NSWindow *> *windows = [NSApp.windows copy];
        for (NSWindow *window in windows) {
            MixroomHostedPluginWindowHelper *helper =
                mixroomHostedPluginHelperForWindow(window);
            if (helper == nil) {
                continue;
            }

            const uintptr_t ownerValue =
                (uintptr_t)[helper.metadata[@"ownerPtr"] unsignedLongLongValue];
            if (ownerValue != (uintptr_t)ownerHandle) {
                continue;
            }
            if ([helper.metadata[@"primaryWindow"] boolValue]) {
                continue;
            }

            helper.closing = YES;
            [helper removeEventMonitorIfNeeded];
            [helper releaseHeldDesktopMidiNotes];
            [helper removeAutomationAccessoryFromWindow:window];
            if (window.parentWindow != nil) {
                [window.parentWindow removeChildWindow:window];
            }
            objc_setAssociatedObject(
                window,
                kMixroomHostedPluginWindowHelperKey,
                nil,
                OBJC_ASSOCIATION_ASSIGN);
            [window close];
        }
    };

    if ([NSThread isMainThread]) {
        closeWindows();
    } else {
        dispatch_async(dispatch_get_main_queue(), closeWindows);
    }
}

extern "C" void mixroomConfigureHostedPluginWindow(void *nativeHandle,
                                                    int scopeKind,
                                                    int row,
                                                    int effectIndex,
                                                    int clipId,
                                                    void *ownerHandle,
                                                    bool usesMixroomShell) {
    if (nativeHandle == nullptr) {
        return;
    }
    NSView *nativeView = (__bridge NSView *)nativeHandle;
    __block int attemptsRemaining = 8;
    __block void (^configureAttempt)(void);
    configureAttempt = ^{
        NSWindow *pluginWindow = nativeView.window;
        if (pluginWindow == nil) {
            attemptsRemaining -= 1;
            if (attemptsRemaining > 0) {
                dispatch_after(
                    dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.03 * NSEC_PER_SEC)),
                    dispatch_get_main_queue(),
                    configureAttempt);
            } else {
                configureAttempt = nil;
            }
            return;
        }

        NSMutableDictionary<NSString *, id> *metadata = [NSMutableDictionary dictionary];
        metadata[@"scopeKind"] = @(scopeKind);
        metadata[@"row"] = @(row);
        metadata[@"effectIndex"] = @(effectIndex);
        metadata[@"clipId"] = @(clipId);
        metadata[@"ownerPtr"] = @((unsigned long long)(uintptr_t)ownerHandle);
        metadata[@"mixroomShell"] = @(usesMixroomShell);
        metadata[@"primaryWindow"] = @YES;
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
            mixroomHostedPluginHelperForWindow(pluginWindow);
        if (helper == nil) {
            helper = [[MixroomHostedPluginWindowHelper alloc] initWithWindow:pluginWindow
                                                                   metadata:metadata];
            objc_setAssociatedObject(
                pluginWindow,
                kMixroomHostedPluginWindowHelperKey,
                helper,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else {
            helper.window = pluginWindow;
            helper.metadata = metadata;
        }
        [helper applyWindowMode];
        configureAttempt = nil;
    };
    if ([NSThread isMainThread]) {
        configureAttempt();
    } else {
        dispatch_async(dispatch_get_main_queue(), configureAttempt);
    }
}

extern "C" void mixroomSetHostedPluginWindowsDetached(BOOL detached) {
    gMixroomHostedPluginWindowsDetached = detached;
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSWindow *window in NSApp.windows) {
            MixroomHostedPluginWindowHelper *helper =
                mixroomHostedPluginHelperForWindow(window);
            if (helper != nil) {
                [helper applyWindowMode];
            }
        }
    });
}

extern "C" void mixroomSetDesktopKeyboardMidiForwardingEnabled(BOOL enabled) {
    gMixroomDesktopKeyboardMidiForwardingEnabled = enabled;
    if (enabled) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSWindow *window in NSApp.windows) {
            MixroomHostedPluginWindowHelper *helper =
                mixroomHostedPluginHelperForWindow(window);
            if (helper != nil) {
                [helper releaseHeldDesktopMidiNotes];
            }
        }
    });
}

extern "C" void mixroomRequestHostedPluginEditorClose(void *ownerHandle) {
    JuceEngine::get().requestHostedPluginEditorCloseForOwner(ownerHandle);
}

extern "C" void mixroomRequestHostedPluginAutomationForOwner(void *ownerHandle) {
    JuceEngine::get().requestHostedPluginAutomationForOwner(ownerHandle);
}

extern "C" void mixroomSetHostedPluginWindowDetachedForOwner(void *ownerHandle,
                                                             bool detached) {
    JuceEngine::get().setHostedPluginEditorDetachedForOwner(ownerHandle, detached);
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSWindow *window in NSApp.windows) {
            MixroomHostedPluginWindowHelper *helper =
                mixroomHostedPluginHelperForWindow(window);
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
extern "C" void *mixroomGetFlutterHostNativeView(void) {
    return nullptr;
}

extern "C" bool mixroomGetNativeViewSize(void *nativeView,
                                          double *width,
                                          double *height) {
    juce::ignoreUnused(nativeView, width, height);
    return false;
}

extern "C" bool mixroomGetFlutterHostWindowContentSize(double *width,
                                                        double *height) {
    juce::ignoreUnused(width, height);
    return false;
}

extern "C" void mixroomSetNativeViewFrameScale(void *nativeView,
                                                double x,
                                                double y,
                                                double logicalWidth,
                                                double logicalHeight,
                                                double scale) {
    juce::ignoreUnused(nativeView, x, y, logicalWidth, logicalHeight, scale);
}

extern "C" void mixroomConfigureEmbeddedPluginChrome(void *nativeView,
                                                      const char *title,
                                                      void *ownerHandle,
                                                      double scale) {
    juce::ignoreUnused(nativeView, title, ownerHandle, scale);
}

extern "C" void mixroomReleaseEmbeddedPluginChrome(void *nativeView) {
    juce::ignoreUnused(nativeView);
}

extern "C" void mixroomCloseHostedPluginNativeWindowsForOwner(void *ownerHandle) {
    juce::ignoreUnused(ownerHandle);
}

extern "C" void mixroomConfigureHostedPluginWindow(void *nativeHandle,
                                                    int scopeKind,
                                                    int row,
                                                    int effectIndex,
                                                    int clipId,
                                                    void *ownerHandle,
                                                    bool usesMixroomShell) {
    juce::ignoreUnused(
        nativeHandle,
        scopeKind,
        row,
        effectIndex,
        clipId,
        ownerHandle,
        usesMixroomShell);
}

extern "C" void mixroomAdoptHostedPluginAuxiliaryWindows(int scopeKind,
                                                          int row,
                                                          int effectIndex,
                                                          int clipId,
                                                          void *ownerHandle) {
    juce::ignoreUnused(scopeKind, row, effectIndex, clipId, ownerHandle);
}

extern "C" void mixroomSetHostedPluginWindowsDetached(BOOL detached) {
    juce::ignoreUnused(detached);
}

extern "C" void mixroomSetDesktopKeyboardMidiForwardingEnabled(BOOL enabled) {
    juce::ignoreUnused(enabled);
}

extern "C" void mixroomRequestHostedPluginEditorClose(void *ownerHandle) {
    juce::ignoreUnused(ownerHandle);
}

extern "C" void mixroomRequestHostedPluginAutomationForOwner(void *ownerHandle) {
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

struct PitchLabRange
{
    double startMs = 0.0;
    double endMs = 0.0;
};

struct PitchLabSegment
{
    double originalStartMs = 0.0;
    double originalEndMs = 0.0;
    double targetStartMs = 0.0;
    double targetEndMs = 0.0;
    double semitones = 0.0;
};

double pitchLabNumber(NSDictionary *dict, NSString *key, double fallback)
{
    id raw = dict[key];
    if (![raw respondsToSelector:@selector(doubleValue)])
        return fallback;
    const double value = [raw doubleValue];
    return std::isfinite(value) ? value : fallback;
}

std::vector<PitchLabRange> parsePitchLabRanges(NSArray<NSDictionary *> *ranges)
{
    std::vector<PitchLabRange> out;
    if (ranges == nil)
        return out;
    out.reserve((size_t)ranges.count);

    for (id item in ranges)
    {
        if (![item isKindOfClass:[NSDictionary class]])
            continue;
        NSDictionary *entry = (NSDictionary *)item;
        PitchLabRange range;
        range.startMs = pitchLabNumber(entry, @"startMs", 0.0);
        range.endMs = pitchLabNumber(entry, @"endMs", 0.0);
        if (!std::isfinite(range.startMs) || !std::isfinite(range.endMs))
            continue;
        if (range.endMs < range.startMs)
            std::swap(range.startMs, range.endMs);
        if (range.endMs > range.startMs + 1.0)
            out.push_back(range);
    }

    return out;
}

std::vector<PitchLabSegment> parsePitchLabSegments(NSArray<NSDictionary *> *segments)
{
    std::vector<PitchLabSegment> out;
    if (segments == nil)
        return out;
    out.reserve((size_t)std::min<NSUInteger>(segments.count, 256));

    NSUInteger index = 0;
    for (id item in segments)
    {
        if (index++ >= 256)
            break;
        if (![item isKindOfClass:[NSDictionary class]])
            continue;
        NSDictionary *entry = (NSDictionary *)item;
        PitchLabSegment segment;
        segment.originalStartMs = pitchLabNumber(entry, @"originalStartMs", 0.0);
        segment.originalEndMs = pitchLabNumber(entry, @"originalEndMs", 0.0);
        segment.targetStartMs = pitchLabNumber(entry, @"targetStartMs", 0.0);
        segment.targetEndMs = pitchLabNumber(entry, @"targetEndMs", 0.0);
        segment.semitones = juce::jlimit(-48.0, 48.0, pitchLabNumber(entry, @"semitones", 0.0));
        if (std::isfinite(segment.originalStartMs) &&
            std::isfinite(segment.originalEndMs) &&
            std::isfinite(segment.targetStartMs) &&
            std::isfinite(segment.targetEndMs) &&
            segment.originalEndMs > segment.originalStartMs + 1.0 &&
            segment.targetEndMs > segment.targetStartMs + 1.0)
        {
            out.push_back(segment);
        }
    }

    return out;
}

double pitchLabLocalMsToFileSec(double localMs, double trimStartMs, double trimEndMs, double sourceTimelineDurationMs)
{
    const double activeSourceMs = juce::jmax(1.0, trimEndMs - trimStartMs);
    const double timelineMs = juce::jmax(1.0, sourceTimelineDurationMs);
    return (trimStartMs + juce::jlimit(0.0, timelineMs, localMs) * (activeSourceMs / timelineMs)) / 1000.0;
}

float pitchLabReadInterpolated(const juce::AudioBuffer<float> &buffer, int channel, double sourcePos)
{
    const int n = buffer.getNumSamples();
    if (n <= 0)
        return 0.0f;
    const int ch = juce::jlimit(0, buffer.getNumChannels() - 1, channel);
    const double clamped = juce::jlimit(0.0, (double)(n - 1), sourcePos);
    const int i0 = (int)std::floor(clamped);
    const int i1 = juce::jmin(n - 1, i0 + 1);
    const float frac = (float)(clamped - (double)i0);
    const float a = buffer.getSample(ch, i0);
    return a + (buffer.getSample(ch, i1) - a) * frac;
}

void pitchLabApplyPitchCompensation(juce::AudioBuffer<float> &buffer, double sampleRate, double semitones)
{
    if (buffer.getNumSamples() <= 0 || std::abs(semitones) < 0.01)
        return;
    const int passes = juce::jlimit(1, 8, (int)std::ceil(std::abs(semitones) / 12.0));
    const float semitonesPerPass = (float)(semitones / (double)passes);
    juce::MidiBuffer midi;
    for (int i = 0; i < passes; ++i)
    {
        PitchShiftAudioProcessor shifter;
        shifter.prepareToPlay(sampleRate, juce::jmax(512, buffer.getNumSamples()));
        if (auto *mix = shifter.parameters.getRawParameterValue("mix"))
            mix->store(100.0f, std::memory_order_relaxed);
        if (auto *semitonesParam = shifter.parameters.getRawParameterValue("semitones"))
            semitonesParam->store(juce::jlimit(-12.0f, 12.0f, semitonesPerPass), std::memory_order_relaxed);
        midi.clear();
        shifter.processBlock(buffer, midi);
    }
}

void pitchLabStreamSourceRange(juce::AudioFormatReader &reader,
                               juce::AudioBuffer<float> &output,
                               juce::int64 sourceStart,
                               int sourceCount,
                               int targetStart,
                               int targetCount)
{
    if (sourceCount <= 1 || targetCount <= 0)
        return;
    constexpr int blockSize = 4096;
    const int sourceChannels = juce::jmax(1, (int)reader.numChannels);
    const double sourceSpan = (double)juce::jmax(1, sourceCount - 1);
    const double denom = (double)juce::jmax(1, targetCount - 1);

    for (int targetOffset = 0; targetOffset < targetCount; targetOffset += blockSize)
    {
        const int blockCount = juce::jmin(blockSize, targetCount - targetOffset);
        const double blockSourceStart = ((double)targetOffset / denom) * sourceSpan;
        const double blockSourceEnd = ((double)(targetOffset + blockCount - 1) / denom) * sourceSpan;
        const int readOffset = juce::jlimit(0, sourceCount - 1, (int)std::floor(blockSourceStart));
        const int readEnd = juce::jlimit(readOffset + 1, sourceCount + 1, (int)std::ceil(blockSourceEnd) + 2);
        const int readCount = juce::jmax(1, readEnd - readOffset);
        juce::AudioBuffer<float> scratch(sourceChannels, readCount);
        scratch.clear();
        reader.read(&scratch, 0, readCount, sourceStart + readOffset, true, true);

        for (int i = 0; i < blockCount; ++i)
        {
            const double sourcePos = (((double)(targetOffset + i) / denom) * sourceSpan) - (double)readOffset;
            for (int ch = 0; ch < 2; ++ch)
            {
                output.addSample(ch,
                                 targetStart + targetOffset + i,
                                 pitchLabReadInterpolated(scratch, sourceChannels == 1 ? 0 : ch, sourcePos));
            }
        }
    }
}

void pitchLabMixSourceRange(juce::AudioFormatReader &reader,
                            juce::AudioBuffer<float> &output,
                            double outputSampleRate,
                            double sourceStartSec,
                            double sourceEndSec,
                            double targetStartMs,
                            double targetEndMs,
                            double pitchSemitones)
{
    if (sourceEndSec <= sourceStartSec + 0.0005 || targetEndMs <= targetStartMs + 0.5)
        return;
    const juce::int64 sourceStart = juce::jlimit<juce::int64>(0, reader.lengthInSamples, (juce::int64)std::floor(sourceStartSec * reader.sampleRate));
    const juce::int64 sourceEnd = juce::jlimit<juce::int64>(0, reader.lengthInSamples, (juce::int64)std::ceil(sourceEndSec * reader.sampleRate));
    const juce::int64 sourceCount64 = std::max<juce::int64>(0, sourceEnd - sourceStart);
    if (sourceCount64 <= 1 || sourceCount64 > (juce::int64)std::numeric_limits<int>::max() - 8)
        return;
    const int sourceCount = (int)sourceCount64;
    const int targetStart = juce::jlimit(0, output.getNumSamples(), (int)std::floor(targetStartMs * outputSampleRate / 1000.0));
    const int targetEnd = juce::jlimit(0, output.getNumSamples(), (int)std::ceil(targetEndMs * outputSampleRate / 1000.0));
    const int targetCount = juce::jmax(0, targetEnd - targetStart);
    if (targetCount <= 0)
        return;

    const double sourceDurationSec = juce::jmax(0.001, sourceEndSec - sourceStartSec);
    const double targetDurationSec = juce::jmax(0.001, (targetEndMs - targetStartMs) / 1000.0);
    const double resampleSpeed = sourceDurationSec / targetDurationSec;
    const double stretchPitchDrift = 12.0 * (std::log(resampleSpeed) / std::log(2.0));
    if (std::abs(pitchSemitones) < 0.01 && std::abs(stretchPitchDrift) < 0.03)
    {
        pitchLabStreamSourceRange(reader, output, sourceStart, sourceCount, targetStart, targetCount);
        return;
    }

    juce::AudioBuffer<float> source(juce::jmax(1, (int)reader.numChannels), sourceCount + 2);
    source.clear();
    reader.read(&source, 0, sourceCount, sourceStart, true, true);

    juce::AudioBuffer<float> rendered(2, targetCount);
    rendered.clear();
    const double sourceSpan = (double)juce::jmax(1, sourceCount - 1);
    const double denom = (double)juce::jmax(1, targetCount - 1);
    for (int i = 0; i < targetCount; ++i)
    {
        const double sourcePos = ((double)i / denom) * sourceSpan;
        for (int ch = 0; ch < 2; ++ch)
            rendered.setSample(ch, i, pitchLabReadInterpolated(source, source.getNumChannels() == 1 ? 0 : ch, sourcePos));
    }

    pitchLabApplyPitchCompensation(rendered, outputSampleRate, juce::jlimit(-96.0, 96.0, pitchSemitones - stretchPitchDrift));
    for (int ch = 0; ch < 2; ++ch)
        output.addFrom(ch, targetStart, rendered, ch, 0, targetCount);
}

juce::String renderPitchLabAudioNative(const juce::File &sourceFile,
                                       const juce::File &outFile,
                                       double trimStartMs,
                                       double trimEndMs,
                                       double sourceTimelineDurationMs,
                                       double outputDurationMs,
                                       std::vector<PitchLabRange> suppressedRanges,
                                       const std::vector<PitchLabSegment> &segments)
{
    juce::AudioFormatManager formatManager;
    formatManager.registerBasicFormats();
    std::unique_ptr<juce::AudioFormatReader> reader(formatManager.createReaderFor(sourceFile));
    if (!reader)
        return {};
    if (trimEndMs <= trimStartMs)
        trimEndMs = (double)reader->lengthInSamples * 1000.0 / juce::jmax(1.0, reader->sampleRate);

    const double outputSampleRate = 48000.0;
    const int outputSamples = juce::jlimit(1, (int)(outputSampleRate * 60.0 * 12.0), (int)std::ceil(outputDurationMs * outputSampleRate / 1000.0));
    juce::AudioBuffer<float> output(2, outputSamples);
    output.clear();
    std::sort(suppressedRanges.begin(), suppressedRanges.end(), [](const PitchLabRange &a, const PitchLabRange &b)
              { return a.startMs < b.startMs; });

    double cursorMs = 0.0;
    for (const auto &range : suppressedRanges)
    {
        const double startMs = juce::jlimit(0.0, sourceTimelineDurationMs, range.startMs);
        const double endMs = juce::jlimit(0.0, sourceTimelineDurationMs, range.endMs);
        if (startMs > cursorMs + 4.0)
            pitchLabMixSourceRange(*reader, output, outputSampleRate,
                                   pitchLabLocalMsToFileSec(cursorMs, trimStartMs, trimEndMs, sourceTimelineDurationMs),
                                   pitchLabLocalMsToFileSec(startMs, trimStartMs, trimEndMs, sourceTimelineDurationMs),
                                   cursorMs, startMs, 0.0);
        cursorMs = juce::jmax(cursorMs, endMs);
    }
    if (cursorMs < sourceTimelineDurationMs - 4.0)
        pitchLabMixSourceRange(*reader, output, outputSampleRate,
                               pitchLabLocalMsToFileSec(cursorMs, trimStartMs, trimEndMs, sourceTimelineDurationMs),
                               pitchLabLocalMsToFileSec(sourceTimelineDurationMs, trimStartMs, trimEndMs, sourceTimelineDurationMs),
                               cursorMs, sourceTimelineDurationMs, 0.0);

    for (const auto &segment : segments)
        pitchLabMixSourceRange(*reader, output, outputSampleRate,
                               pitchLabLocalMsToFileSec(segment.originalStartMs, trimStartMs, trimEndMs, sourceTimelineDurationMs),
                               pitchLabLocalMsToFileSec(segment.originalEndMs, trimStartMs, trimEndMs, sourceTimelineDurationMs),
                               segment.targetStartMs, segment.targetEndMs, segment.semitones);

    for (int ch = 0; ch < output.getNumChannels(); ++ch)
    {
        auto *samples = output.getWritePointer(ch);
        for (int i = 0; i < output.getNumSamples(); ++i)
            samples[i] = std::tanh(samples[i] * 0.98f);
    }

    outFile.deleteFile();
    std::unique_ptr<juce::FileOutputStream> stream(outFile.createOutputStream());
    if (!stream)
        return {};
    juce::WavAudioFormat wav;
    std::unique_ptr<juce::AudioFormatWriter> writer(wav.createWriterFor(stream.get(), outputSampleRate, 2, 24, {}, 0));
    if (!writer)
        return {};
    stream.release();
    if (!writer->writeFromAudioSampleBuffer(output, 0, output.getNumSamples()))
        return {};
    return outFile.getFullPathName();
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
#if JUCE_MAC && !JUCE_IOS
    if (auto *messageManager = juce::MessageManager::getInstance())
    {
        if (messageManager->isThisTheMessageThread())
            JuceEngine::get().shutdownEngine();
        else
            messageManager->callSync([] { JuceEngine::get().shutdownEngine(); });
    }
    else
    {
        JuceEngine::get().shutdownEngine();
    }
#else
    juce::MessageManager::callAsync([] { JuceEngine::get().shutdownEngine(); });
#endif
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

            if (e.contains("displayMin"))
                d[@"displayMin"] = extractVar(e["displayMin"]);
            if (e.contains("displayMid"))
                d[@"displayMid"] = extractVar(e["displayMid"]);
            if (e.contains("displayMax"))
                d[@"displayMax"] = extractVar(e["displayMax"]);
            if (e.contains("displayDefault"))
                d[@"displayDefault"] = extractVar(e["displayDefault"]);
            if (e.contains("displayValue"))
                d[@"displayValue"] = extractVar(e["displayValue"]);
            if (e.contains("defaultNormalized"))
                d[@"defaultNormalized"] = extractVar(e["defaultNormalized"]);
            if (e.contains("valueNormalized"))
                d[@"valueNormalized"] = extractVar(e["valueNormalized"]);

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

            if (e.contains("displayMin"))
                d[@"displayMin"] = extractVar(e["displayMin"]);
            if (e.contains("displayMid"))
                d[@"displayMid"] = extractVar(e["displayMid"]);
            if (e.contains("displayMax"))
                d[@"displayMax"] = extractVar(e["displayMax"]);
            if (e.contains("displayDefault"))
                d[@"displayDefault"] = extractVar(e["displayDefault"]);
            if (e.contains("displayValue"))
                d[@"displayValue"] = extractVar(e["displayValue"]);
            if (e.contains("defaultNormalized"))
                d[@"defaultNormalized"] = extractVar(e["defaultNormalized"]);
            if (e.contains("valueNormalized"))
                d[@"valueNormalized"] = extractVar(e["valueNormalized"]);

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

+ (NSString *)renderPitchLabAudioObjC:(NSString *)sourcePath
                              outPath:(NSString *)outPath
                          trimStartMs:(double)trimStartMs
                            trimEndMs:(double)trimEndMs
             sourceTimelineDurationMs:(double)sourceTimelineDurationMs
                     outputDurationMs:(double)outputDurationMs
                     suppressedRanges:(NSArray<NSDictionary *> *)suppressedRanges
                             segments:(NSArray<NSDictionary *> *)segments
{
    const juce::String renderedPath = renderPitchLabAudioNative(
        juceFileFromNSString(sourcePath),
        juceFileFromNSString(outPath),
        trimStartMs,
        trimEndMs,
        sourceTimelineDurationMs,
        outputDurationMs,
        parsePitchLabRanges(suppressedRanges),
        parsePitchLabSegments(segments));
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

    auto buildResult = [&]() {
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
                entry[@"quarantined"] = @(
                    JuceEngine::get().isHostedPluginQuarantined(desc.fileOrIdentifier));
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
            resultArray = [arr copy];
    };

#if TARGET_OS_OSX
    buildResult();
#else
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync(buildResult);
    }
#endif

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

    auto buildResult = [&]() {
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
                entry[@"quarantined"] = @(
                    JuceEngine::get().isHostedPluginQuarantined(desc.fileOrIdentifier));
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
            resultArray = [arr copy];
    };

#if TARGET_OS_OSX
    buildResult();
#else
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync(buildResult);
    }
#endif

    if (resultArray == nil)
        resultArray = [NSMutableArray array];

    return resultArray;
}

+ (NSArray<NSDictionary *> *)getQuarantinedPluginsObjC
{
    NSMutableArray<NSDictionary *> *resultArray = nil;
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&resultArray]
                     {
            NSMutableArray<NSDictionary *> *arr = [NSMutableArray array];
            const auto records = JuceEngine::get().getQuarantinedHostedPlugins();
            for (const auto &record : records)
            {
                NSMutableDictionary<NSString *, id> *entry =
                    [NSMutableDictionary dictionary];
                for (const auto &value : record)
                {
                    NSString *key =
                        [NSString stringWithUTF8String:value.name.toString().toRawUTF8()] ?: @"";
                    NSString *stringValue =
                        [NSString stringWithUTF8String:value.value.toString().toRawUTF8()] ?: @"";
                    if (key.length > 0)
                        entry[key] = stringValue;
                }
                if (entry.count > 0)
                    [arr addObject:[entry copy]];
            }
            resultArray = [arr copy]; });
    }
    return resultArray ?: @[];
}

+ (BOOL)isPluginQuarantinedObjC:(NSString *)pluginId
{
    if (pluginId == nil || pluginId.length == 0)
        return NO;

    bool quarantined = false;
    const juce::String juceId = juceStringFromNSString(pluginId);
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&]
                     { quarantined = JuceEngine::get().isHostedPluginQuarantined(juceId); });
    }
    return quarantined;
}

+ (void)clearPluginQuarantineObjC:(NSString *)pluginId
{
    if (pluginId == nil || pluginId.length == 0)
        return;

    const juce::String juceId = juceStringFromNSString(pluginId);
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&]
                     { JuceEngine::get().clearHostedPluginQuarantine(juceId); });
    }
}

+ (void)clearAllPluginQuarantinesObjC
{
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([]
                     { JuceEngine::get().clearAllHostedPluginQuarantines(); });
    }
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

    NSLog(@"[MixroomPluginRestore] bridge insertTrackEffect convert start row=%ld path=%@", (long)trackRow, pluginPath ?: @"");
    juce::String jucePath = juceStringFromNSString(pluginPath);
    NSLog(@"[MixroomPluginRestore] bridge insertTrackEffect convert done row=%ld path=%@", (long)trackRow, pluginPath ?: @"");
    bool success = false;

#if JUCE_MAC && !JUCE_IOS
    NSLog(@"[MixroomPluginRestore] bridge insertTrackEffect engine call start row=%ld path=%@", (long)trackRow, pluginPath ?: @"");
    success = JuceEngine::get().insertTrackEffect((int)trackRow, jucePath);
    NSLog(@"[MixroomPluginRestore] bridge insertTrackEffect engine call done row=%ld path=%@ success=%@", (long)trackRow, pluginPath ?: @"", success ? @"YES" : @"NO");
#else
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&]
                     { success = JuceEngine::get().insertTrackEffect((int)trackRow, jucePath); });
    }
#endif

#if !(JUCE_MAC && !JUCE_IOS)
    [[NSNotificationCenter defaultCenter] postNotificationName:@"JUCERowEffectLoaded"
                                                        object:nil
                                                      userInfo:@{
                                                          @"event" : @"rowEffectLoaded",
                                                          @"row" : @(trackRow),
                                                          @"path" : pluginPath ?: @"",
                                                          @"success" : @(success)
                                                      }];
#endif
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
#if JUCE_MAC && !JUCE_IOS
    applied = JuceEngine::get().setTrackEffectStateBase64(
        (int)trackRow,
        (int)effectIndex,
        state);
#else
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([trackRow, effectIndex, &applied, state]
                     { applied = JuceEngine::get().setTrackEffectStateBase64((int)trackRow, (int)effectIndex, state); });
    }
#endif
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

+ (void)configureTrackGroupsObjC:(NSArray<NSDictionary *> *)groups
{
    juce::Array<juce::NamedValueSet> cppGroups;
    for (NSDictionary *group in groups ?: @[])
    {
        if (![group isKindOfClass:[NSDictionary class]])
            continue;

        juce::NamedValueSet values;
        values.set("id", juceStringFromNSString(group[@"id"] ?: @""));

        juce::Array<juce::var> rowIds;
        NSArray *rawRowIds = group[@"rowIds"];
        if ([rawRowIds isKindOfClass:[NSArray class]])
        {
            for (id value in rawRowIds)
            {
                if ([value respondsToSelector:@selector(integerValue)])
                    rowIds.add((int)[value integerValue]);
            }
        }
        values.set("rowIds", juce::var(rowIds));
        values.set("gain", group[@"gain"] != nil ? [group[@"gain"] floatValue] : 2.0f);
        values.set("pan", group[@"pan"] != nil ? [group[@"pan"] floatValue] : 0.5f);
        values.set("muted", group[@"muted"] != nil ? (bool)[group[@"muted"] boolValue] : false);
        values.set("soloed", group[@"soloed"] != nil ? (bool)[group[@"soloed"] boolValue] : false);
        cppGroups.add(values);
    }

    juce::MessageManager::getInstance()->callSync([cppGroups]
                                                  { JuceEngine::get().configureTrackGroups(cppGroups); });
}

+ (void)assignRowToGroupObjC:(NSInteger)row groupId:(NSString *)groupId
{
    const juce::String juceGroupId = juceStringFromNSString(groupId ?: @"");
    juce::MessageManager::getInstance()->callSync([row, juceGroupId]
                                                  { JuceEngine::get().assignRowToGroup((int)row, juceGroupId); });
}

+ (void)setTrackGroupMixStateObjC:(NSString *)groupId
                             gain:(float)gain
                              pan:(float)pan
                            muted:(BOOL)muted
                           soloed:(BOOL)soloed
{
    const juce::String juceGroupId = juceStringFromNSString(groupId ?: @"");
    juce::MessageManager::getInstance()->callSync([juceGroupId, gain, pan, muted, soloed]
                                                  { JuceEngine::get().setTrackGroupMixState(juceGroupId, gain, pan, (bool)muted, (bool)soloed); });
}

#pragma mark - Master bus FX and controls

+ (BOOL)insertMasterEffectObjC:(NSString *)pluginPath
{
    if (pluginPath == nil || pluginPath.length == 0)
        return NO;

    juce::String jucePath = juceStringFromNSString(pluginPath);
    bool success = false;

#if JUCE_MAC && !JUCE_IOS
    success = JuceEngine::get().insertMasterEffect(jucePath);
#else
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&]
                     { success = JuceEngine::get().insertMasterEffect(jucePath); });
    }
#endif

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
#if JUCE_MAC && !JUCE_IOS
    applied = JuceEngine::get().setMasterEffectStateBase64(
        (int)effectIndex,
        state);
#else
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([effectIndex, &applied, state]
                     { applied = JuceEngine::get().setMasterEffectStateBase64((int)effectIndex, state); });
    }
#endif
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
#if JUCE_MAC && !JUCE_IOS
    ok = JuceEngine::get().loadMidiClip((int)clipIndex,
                                        (int)rowId,
                                        iid,
                                        iname,
                                        parsedNotes,
                                        parsedParams,
                                        sourceTempoBpm,
                                        startSec,
                                        lengthSec,
                                        inFileOffsetSec);
#else
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
#endif
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

+ (void)setDesktopKeyboardMidiForwardingEnabledObjC:(BOOL)enabled
{
    mixroomSetDesktopKeyboardMidiForwardingEnabled(enabled);
}

+ (BOOL)setMidiClipPluginStateObjC:(NSInteger)clipIndex
                        stateBase64:(NSString *)stateBase64
{
    const juce::String state =
        stateBase64 != nil ? juceStringFromNSString(stateBase64)
                           : juce::String();
    bool applied = false;
#if JUCE_MAC && !JUCE_IOS
    applied = JuceEngine::get().setMidiClipPluginStateBase64(
        (int)clipIndex,
        state);
#else
    juce::MessageManager::getInstance()->callSync([&]
                                                  { applied = JuceEngine::get().setMidiClipPluginStateBase64((int)clipIndex, state); });
#endif
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
    return [out copy];
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
#if JUCE_MAC && !JUCE_IOS
    JuceEngine::get().setClipGain((int)clipIndex, gain);
#else
    juce::MessageManager::getInstance()->callSync([clipIndex, gain]
                                                  { JuceEngine::get().setClipGain((int)clipIndex, gain); });
#endif
}

+ (void)setClipExtraGainLinearObjC:(NSInteger)clipIndex gain:(float)gain
{
#if JUCE_MAC && !JUCE_IOS
    JuceEngine::get().setClipExtraGainLinear((int)clipIndex, gain);
#else
    juce::MessageManager::getInstance()->callSync([clipIndex, gain]
                                                  { JuceEngine::get().setClipExtraGainLinear((int)clipIndex, gain); });
#endif
}

+ (void)muteClipObjC:(NSInteger)clipIndex shouldMute:(BOOL)shouldMute
{
#if JUCE_MAC && !JUCE_IOS
    JuceEngine::get().muteClip((int)clipIndex, (bool)shouldMute);
#else
    juce::MessageManager::getInstance()->callSync([clipIndex, shouldMute]
                                                  { JuceEngine::get().muteClip((int)clipIndex, (bool)shouldMute); });
#endif
}

+ (void)setClipPanObjC:(NSInteger)clipIndex pan:(float)pan
{
#if JUCE_MAC && !JUCE_IOS
    JuceEngine::get().setClipPan((int)clipIndex, pan);
#else
    juce::MessageManager::getInstance()->callSync([clipIndex, pan]
                                                  { JuceEngine::get().setClipPan((int)clipIndex, pan); });
#endif
}

+ (void)setClipFadesObjC:(NSInteger)clipIndex
               fadeInSec:(double)fadeInSec
              fadeOutSec:(double)fadeOutSec
               fadeCurve:(NSInteger)fadeCurve
{
#if JUCE_MAC && !JUCE_IOS
    JuceEngine::get().setClipFades((int)clipIndex, fadeInSec, fadeOutSec, (int)fadeCurve);
#else
    juce::MessageManager::getInstance()->callSync([clipIndex, fadeInSec, fadeOutSec, fadeCurve]
                                                  { JuceEngine::get().setClipFades((int)clipIndex, fadeInSec, fadeOutSec, (int)fadeCurve); });
#endif
}

+ (void)setClipPitchObjC:(NSInteger)clipIndex semitones:(float)semitones
{
#if JUCE_MAC && !JUCE_IOS
    JuceEngine::get().setClipPitch((int)clipIndex, semitones);
#else
    juce::MessageManager::getInstance()->callSync([clipIndex, semitones]
                                                  { JuceEngine::get().setClipPitch((int)clipIndex, semitones); });
#endif
}

+ (void)setClipReversedObjC:(NSInteger)clipIndex reversed:(BOOL)reversed
{
#if JUCE_MAC && !JUCE_IOS
    JuceEngine::get().setClipReversed((int)clipIndex, (bool)reversed);
#else
    juce::MessageManager::getInstance()->callSync([clipIndex, reversed]
                                                  { JuceEngine::get().setClipReversed((int)clipIndex, (bool)reversed); });
#endif
}

+ (void)setClipStretchOptionsObjC:(NSInteger)clipIndex
                       tempoRatio:(double)tempoRatio
                    preservePitch:(BOOL)preservePitch
{
#if JUCE_MAC && !JUCE_IOS
    JuceEngine::get().setClipStretchOptions((int)clipIndex, tempoRatio, (bool)preservePitch);
#else
    juce::MessageManager::getInstance()->callSync([clipIndex, tempoRatio, preservePitch]
                                                  { JuceEngine::get().setClipStretchOptions((int)clipIndex, tempoRatio, (bool)preservePitch); });
#endif
}

+ (void)moveClipToRowObjC:(NSInteger)clipIndex newRowId:(NSInteger)newRowId
{
#if JUCE_MAC && !JUCE_IOS
    JuceEngine::get().moveClipToRow((int)clipIndex, (int)newRowId);
#else
    juce::MessageManager::getInstance()->callSync([clipIndex, newRowId]
                                                  { JuceEngine::get().moveClipToRow((int)clipIndex, (int)newRowId); });
#endif
}

+ (void)setClipTimeObjC:(NSInteger)clipIndex
               startSec:(double)startSec
              lengthSec:(double)lengthSec
        inFileOffsetSec:(double)inFileOffsetSec
{
#if JUCE_MAC && !JUCE_IOS
    JuceEngine::get().setClipTime((int)clipIndex, startSec, lengthSec, inFileOffsetSec);
#else
    juce::MessageManager::getInstance()->callSync([clipIndex, startSec, lengthSec, inFileOffsetSec]
                                                  { JuceEngine::get().setClipTime((int)clipIndex, startSec, lengthSec, inFileOffsetSec); });
#endif
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

+ (void)setMetronomeTimeSignatureObjC:(NSInteger)numerator
                          denominator:(NSInteger)denominator
{
    juce::MessageManager::callAsync([numerator, denominator]
                                    { JuceEngine::get().setMetronomeTimeSignature((int)numerator, (int)denominator); });
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

+ (BOOL)configureAudioDeviceObjC:(double)sampleRate
                       bufferSize:(NSInteger)bufferSize
              desiredInputChannels:(NSInteger)desiredInputChannels
                            reason:(NSString *)reason
{
    const auto why = reason == nil ? juce::String("dart") : juceStringFromNSString(reason);
    return JuceEngine::get().configureAudioDevice(
        sampleRate,
        (int)bufferSize,
        (int)desiredInputChannels,
        why);
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
        if (mm->isThisTheMessageThread())
        {
            JuceEngine::get().setLiveInputMonitoringEnabled(enabled);
            return;
        }

        mm->callSync([enabled]
                     { JuceEngine::get().setLiveInputMonitoringEnabled(enabled); });
        return;
    }

    JuceEngine::get().setLiveInputMonitoringEnabled(enabled);
}

+ (void)setMidiInputChannelFilterObjC:(NSInteger)channel
{
    JuceEngine::get().setMidiInputChannelFilter((int)channel);
}

+ (NSNumber *)getMidiInputChannelFilterObjC
{
    return @(JuceEngine::get().getMidiInputChannelFilter());
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

+ (NSArray<NSNumber*>*)getRowDynamicSoftenerFrameObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex
{
    const auto v = JuceEngine::get().getRowDynamicSoftenerFrame((int)row, (int)effectIndex);
    NSMutableArray<NSNumber*>* arr = [NSMutableArray arrayWithCapacity:v.size()];
    for (float s : v)
        [arr addObject:@(s)];
    return arr;
}

+ (NSArray<NSNumber*>*)getMasterDynamicSoftenerFrameObjC:(NSInteger)effectIndex
{
    const auto v = JuceEngine::get().getMasterDynamicSoftenerFrame((int)effectIndex);
    NSMutableArray<NSNumber*>* arr = [NSMutableArray arrayWithCapacity:v.size()];
    for (float s : v)
        [arr addObject:@(s)];
    return arr;
}

+ (NSArray<NSNumber*>*)getRowTransientShaperVisualObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex pointCount:(NSInteger)pointCount
{
    const auto v = JuceEngine::get().getRowTransientShaperVisual((int)row, (int)effectIndex, (int)pointCount);
    NSMutableArray<NSNumber*>* arr = [NSMutableArray arrayWithCapacity:v.size()];
    for (float s : v)
        [arr addObject:@(s)];
    return arr;
}

+ (NSArray<NSNumber*>*)getMasterTransientShaperVisualObjC:(NSInteger)effectIndex pointCount:(NSInteger)pointCount
{
    const auto v = JuceEngine::get().getMasterTransientShaperVisual((int)effectIndex, (int)pointCount);
    NSMutableArray<NSNumber*>* arr = [NSMutableArray arrayWithCapacity:v.size()];
    for (float s : v)
        [arr addObject:@(s)];
    return arr;
}


@end
