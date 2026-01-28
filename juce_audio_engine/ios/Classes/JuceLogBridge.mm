#import "JuceLogBridge.h"
#import "JuceAudioEnginePlugin.h"

extern "C" void juceLogToFlutter(const char* cstr) {
    NSString* nsmsg = [NSString stringWithUTF8String:cstr];
    [[JuceAudioEnginePlugin sharedInstance] sendFlutterLog:nsmsg];
}
