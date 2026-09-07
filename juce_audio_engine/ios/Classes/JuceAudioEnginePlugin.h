#if __has_include(<Flutter/Flutter.h>)
#import <Flutter/Flutter.h>
#elif __has_include(<FlutterMacOS/FlutterMacOS.h>)
#import <FlutterMacOS/FlutterMacOS.h>
#endif

@interface JuceAudioEnginePlugin : NSObject <FlutterPlugin, FlutterStreamHandler>

+ (instancetype)sharedInstance;
+ (void)shutdownForApplicationTermination;
+ (void)panicLiveMidiNotesForApplicationDeactivation;
- (BOOL)hasActiveLogListener;
- (void)sendFlutterLog:(NSString *)message;
- (void)sendFlutterEvent:(NSDictionary<NSString *, id> *)event;

@end
