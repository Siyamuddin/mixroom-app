#import "MixroomIOSCaptureLifecycleV2.h"
@interface MixroomIOSCaptureLifecycleV2 ()
@property (nonatomic, retain) id<MixroomIOSCaptureNativeV2> native;
@property BOOL preserve;
@property NSInteger row;
@property NSInteger startChannel;
@property NSInteger channels;
@property uint64_t streamGeneration;
@end
@implementation MixroomIOSCaptureLifecycleV2
- (instancetype)initWithNative:(id<MixroomIOSCaptureNativeV2>)native
           preserveMonitoring:(BOOL)preserve targetRow:(NSInteger)row
                 channelStart:(NSInteger)start channelCount:(NSInteger)count
             streamGeneration:(uint64_t)generation {
    if ((self = [super init])) {
        self.native = native; self.preserve = preserve; self.row = row;
        self.startChannel = start; self.channels = count; self.streamGeneration = generation;
    }
    return self;
}
- (void)dealloc {
#if !__has_feature(objc_arc)
    [_native release];
    [super dealloc];
#endif
}
- (BOOL)monitorMatches {
    if (!self.preserve) return YES;
    NSDictionary *facts = [self.native monitorFacts];
    return [facts[@"active"] boolValue] && [facts[@"connectionsValid"] boolValue] &&
        [facts[@"targetRow"] integerValue] == self.row &&
        [facts[@"channelStart"] integerValue] == self.startChannel &&
        [facts[@"channelCount"] integerValue] == self.channels &&
        [facts[@"connectionCount"] integerValue] == self.channels &&
        self.streamGeneration != 0 &&
        [facts[@"streamGeneration"] unsignedLongLongValue] == self.streamGeneration;
}
- (BOOL)start:(NSString *)path channelStart:(NSInteger)start channelCount:(NSInteger)count
 currentAndReady:(BOOL (^)(void))current {
    @try {
        if (path.length == 0 || start != self.startChannel || count != self.channels ||
        start < 0 || count < 1 || count > 2 || self.cancelled || !current() ||
        ![self monitorMatches] || [self.native isRecording]) return NO;
        BOOL started = [self.native start:path channelStart:start channelCount:count];
        if (!started || self.cancelled || !current() || ![self monitorMatches]) {
            // No replacement capture can start on this serialized queue yet.
            if ([self.native isRecording]) [self.native discardPreservingMonitor:self.preserve];
            return NO;
        }
        return YES;
    } @catch (NSException *exception) {
        [self.native discardPreservingMonitor:self.preserve];
        return NO;
    }
}
- (NSDictionary *)finalizeWithCurrent:(BOOL (^)(void))current {
    if (!current()) return @{@"success": @NO, @"diagnosticCode": @"stale_generation"};
    NSDictionary *result;
    @try { result = [self.native finalizePreservingMonitor:self.preserve]; }
    @catch (NSException *exception) {
        [self.native discardPreservingMonitor:self.preserve];
        result = @{@"success": @NO, @"diagnosticCode": @"writer_finalize_failed"};
    }
    if (current()) return result;
    NSMutableDictionary *stale = [NSMutableDictionary dictionaryWithDictionary:result ?: @{}];
    stale[@"success"] = @NO; stale[@"diagnosticCode"] = @"stale_generation";
    return stale;
}
- (BOOL)canDeliverStartWithCurrent:(BOOL)current { return current && !self.cancelled; }
- (void)discardWithCurrent:(BOOL)current {
    if (current && [self.native isRecording]) [self.native discardPreservingMonitor:self.preserve];
}
@end
