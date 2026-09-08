#import <Foundation/Foundation.h>
#import "../../ios/Classes/MixroomIOSCaptureLifecycleV2.h"

static void check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}
@interface FakeCapture : NSObject <MixroomIOSCaptureNativeV2>
@property BOOL recording;
@property BOOL startFails;
@property BOOL stopFails;
@property BOOL throwsStart;
@property BOOL throwsStop;
@property BOOL monitor;
@property NSInteger epoch;
@property NSInteger target;
@property NSInteger channels;
@property BOOL connectionsValid;
@property NSInteger starts;
@property NSInteger stops;
@property NSInteger discards;
@property NSInteger routeCleanups;
@property (copy) void (^onStart)(void);
@property (copy) void (^onStop)(void);
@end
@implementation FakeCapture
- (instancetype)init { if ((self = [super init])) { _monitor = YES; _epoch = 42; _target = 3; _channels = 1; _connectionsValid = YES; } return self; }
- (BOOL)isRecording { return self.recording; }
- (NSDictionary *)monitorFacts { return @{@"active": @(self.monitor), @"targetRow": @(self.target), @"channelStart": @1, @"channelCount": @(self.channels), @"connectionCount": @(self.channels), @"connectionsValid": @(self.connectionsValid), @"streamGeneration": @(self.epoch)}; }
- (BOOL)start:(NSString *)path channelStart:(NSInteger)start channelCount:(NSInteger)count {
    self.starts++; self.recording = !self.startFails;
    if (self.onStart) self.onStart();
    if (self.throwsStart) [NSException raise:@"Writer" format:@"start"];
    return self.recording;
}
- (NSDictionary *)finalizePreservingMonitor:(BOOL)preserve {
    self.stops++;
    if (self.throwsStop) [NSException raise:@"Writer" format:@"stop"];
    self.recording = NO;
    if (!preserve) { self.routeCleanups++; self.monitor = NO; self.epoch++; }
    if (self.onStop) self.onStop();
    return @{@"success": @(!self.stopFails)};
}
- (void)discardPreservingMonitor:(BOOL)preserve {
    self.discards++; self.recording = NO;
    if (!preserve) { self.routeCleanups++; self.monitor = NO; self.epoch++; }
}
@end
static MixroomIOSCaptureLifecycleV2 *capture(FakeCapture *native) {
    return [[MixroomIOSCaptureLifecycleV2 alloc] initWithNative:native preserveMonitoring:YES targetRow:3 channelStart:1 channelCount:1 streamGeneration:42];
}
int main(void) { @autoreleasepool {
    FakeCapture *native = [FakeCapture new];
    for (int take = 0; take < 3; ++take) {
        MixroomIOSCaptureLifecycleV2 *op = capture(native);
        check([op start:@"take.wav" channelStart:1 channelCount:1 currentAndReady:^{ return YES; }], @"start");
        check(![op start:@"duplicate.wav" channelStart:1 channelCount:1 currentAndReady:^{ return YES; }], @"duplicate");
        check([[op finalizeWithCurrent:^{ return YES; }][@"success"] boolValue], @"finalize");
        check(native.monitor && native.epoch == 42 && native.routeCleanups == 0, @"monitor unchanged");
    }
    MixroomIOSCaptureLifecycleV2 *op = capture(native);
    check(![op start:@"mismatch" channelStart:0 channelCount:1 currentAndReady:^{ return YES; }], @"mismatched channels");
    op.cancelled = YES;
    check(![op start:@"cancel" channelStart:1 channelCount:1 currentAndReady:^{ return YES; }], @"cancel before start");
    op = capture(native);
    native.onStart = ^{ op.cancelled = YES; };
    check(![op start:@"cancel" channelStart:1 channelCount:1 currentAndReady:^{ return YES; }], @"cancel during start");
    check(!native.recording && native.monitor, @"capture-only discard");
    native.onStart = nil;
    for (int failure = 0; failure < 2; ++failure) {
        op = capture(native); native.startFails = failure == 0; native.throwsStart = failure == 1;
        check(![op start:@"failure" channelStart:1 channelCount:1 currentAndReady:^{ return YES; }], @"writer-start failure");
        check(!native.recording && native.monitor, @"writer failure preserves monitor");
    }
    native.startFails = NO; native.throwsStart = NO;
    for (int failure = 0; failure < 2; ++failure) {
        op = capture(native);
        check([op start:@"take" channelStart:1 channelCount:1 currentAndReady:^{ return YES; }], @"start before finalize failure");
        native.stopFails = failure == 0; native.throwsStop = failure == 1;
        check(![[op finalizeWithCurrent:^{ return YES; }][@"success"] boolValue], @"finalize failure");
        check(native.monitor && !native.recording, @"failed finalize preserves monitor");
    }
    native.stopFails = NO; native.throwsStop = NO;
    // A different recording destination never enters capture routing arguments.
    // Exact owned channel/graph facts still govern admission.
    native.target = 4; op = capture(native);
    check(![op start:@"wrong-monitor" channelStart:1 channelCount:1 currentAndReady:^{ return YES; }], @"target mismatch");
    native.target = 3; native.connectionsValid = NO;
    check(![op start:@"broken-graph" channelStart:1 channelCount:1 currentAndReady:^{ return YES; }], @"graph mismatch");
    native.connectionsValid = YES; native.channels = 2;
    op = [[MixroomIOSCaptureLifecycleV2 alloc] initWithNative:native preserveMonitoring:YES targetRow:3 channelStart:1 channelCount:2 streamGeneration:42];
    check([op start:@"stereo-monitor" channelStart:1 channelCount:2 currentAndReady:^{ return YES; }], @"monitored stereo");
    check([[op finalizeWithCurrent:^{ return YES; }][@"success"] boolValue], @"stereo finalize");
    check(native.target == 3 && native.monitor && native.epoch == 42, @"stereo ownership");
    native.channels = 1;
    // Same endpoint reopened: unchanged names are insufficient evidence.
    op = capture(native); native.epoch++;
    check(![op start:@"stale" channelStart:1 channelCount:1 currentAndReady:^{ return YES; }], @"stream epoch");
    native.epoch = 42;
    // Invalidation/interrupt/shutdown races must not restore the old monitor.
    for (int race = 0; race < 3; ++race) {
        __block BOOL current = YES;
        op = capture(native); native.monitor = YES;
        __weak FakeCapture *weakNative = native;
        native.onStart = ^{ current = NO; weakNative.monitor = NO; };
        check(![op start:@"stale" channelStart:1 channelCount:1 currentAndReady:^{ return current; }], @"stale start");
        check(!native.monitor && !native.recording, @"no resurrection");
    }
    native.onStart = nil; native.monitor = YES;
    op = capture(native);
    check([op start:@"take" channelStart:1 channelCount:1 currentAndReady:^{ return YES; }], @"late cancel start");
    op.cancelled = YES;
    check(![op canDeliverStartWithCurrent:YES], @"late delivery cancellation");
    [op discardWithCurrent:YES];
    check(native.monitor && !native.recording, @"late cancellation cleanup");
    op = capture(native); native.recording = YES;
    NSInteger before = native.discards;
    [op discardWithCurrent:NO];
    check(native.recording && native.discards == before, @"replacement untouched");
    check(![[op finalizeWithCurrent:^{ return NO; }][@"success"] boolValue], @"stale stop");
    __block BOOL current = YES;
    __weak FakeCapture *weakNative = native;
    native.onStop = ^{ current = NO; weakNative.monitor = NO; };
    check(![[op finalizeWithCurrent:^{ return current; }][@"success"] boolValue], @"invalidation during stop");
    check(!native.monitor, @"stop cannot reactivate");
    native.onStop = nil;
    op = [[MixroomIOSCaptureLifecycleV2 alloc] initWithNative:native preserveMonitoring:NO targetRow:-1 channelStart:0 channelCount:2 streamGeneration:0];
    check([op start:@"stereo" channelStart:0 channelCount:2 currentAndReady:^{ return YES; }], @"recording-only stereo");
    check([[op finalizeWithCurrent:^{ return YES; }][@"success"] boolValue] && native.routeCleanups == 1, @"recording-only cleanup");
    NSLog(@"PASS: iOS capture lifecycle, failures, cancellation, stream identity, stale completions");
} return 0; }
