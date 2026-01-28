#import <Flutter/Flutter.h>

@interface JuceAudioEnginePlugin : NSObject <FlutterPlugin, FlutterStreamHandler>

+ (instancetype)sharedInstance;
- (void)sendFlutterLog:(NSString *)message;

@end
