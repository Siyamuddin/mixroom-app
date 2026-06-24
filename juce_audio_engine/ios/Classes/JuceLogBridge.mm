#import "JuceLogBridge.h"
#import "JuceAudioEnginePlugin.h"

extern "C" void juceLogToFlutter(const char* cstr) {
    if (cstr == nullptr) {
        return;
    }

    NSString *nsmsg = [NSString stringWithUTF8String:cstr];
    if (nsmsg == nil) {
        return;
    }

    NSString *message = [nsmsg copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        JuceAudioEnginePlugin *plugin = [JuceAudioEnginePlugin sharedInstance];
        if (plugin == nil || ![plugin hasActiveLogListener]) {
            return;
        }
        [plugin sendFlutterLog:message];
    });
}
