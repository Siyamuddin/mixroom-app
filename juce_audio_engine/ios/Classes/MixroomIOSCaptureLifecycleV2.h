#import <Foundation/Foundation.h>

@protocol MixroomIOSCaptureNativeV2 <NSObject>
- (BOOL)isRecording;
- (NSDictionary *)monitorFacts;
- (BOOL)start:(NSString *)path channelStart:(NSInteger)start channelCount:(NSInteger)count;
- (NSDictionary *)finalizePreservingMonitor:(BOOL)preserve;
- (void)discardPreservingMonitor:(BOOL)preserve;
@end

// One capture's ownership. Invoke native work on the serialized lifecycle queue.
// This helper never acquires or restores a device route.
@interface MixroomIOSCaptureLifecycleV2 : NSObject
@property (atomic, assign) BOOL cancelled;
- (instancetype)initWithNative:(id<MixroomIOSCaptureNativeV2>)native
           preserveMonitoring:(BOOL)preserve targetRow:(NSInteger)row
                 channelStart:(NSInteger)start channelCount:(NSInteger)count
             streamGeneration:(uint64_t)generation;
- (BOOL)monitorMatches;
- (BOOL)start:(NSString *)path channelStart:(NSInteger)start channelCount:(NSInteger)count
 currentAndReady:(BOOL (^)(void))current;
- (NSDictionary *)finalizeWithCurrent:(BOOL (^)(void))current;
- (BOOL)canDeliverStartWithCurrent:(BOOL)current;
- (void)discardWithCurrent:(BOOL)current;
@end
