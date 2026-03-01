#import "JuceLogBridge.h"
#import "JuceAudioEnginePlugin.h"

extern "C" void juceLogToFlutter(const char* cstr) {
    JuceAudioEnginePlugin *plugin = [JuceAudioEnginePlugin sharedInstance];
    if (plugin == nil || ![plugin hasActiveLogListener] || cstr == nullptr) {
        return;
    }

    NSString *nsmsg = [NSString stringWithUTF8String:cstr];
    if (nsmsg == nil) {
        return;
    }

    [plugin sendFlutterLog:nsmsg];
}
