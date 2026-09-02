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

extern "C" void mixroomPluginScanProgress(const char* json) {
    if (json == nullptr) {
        return;
    }

    NSString *jsonString = [NSString stringWithUTF8String:json];
    NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        return;
    }

    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data
                                                             options:0
                                                               error:nil];
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [[JuceAudioEnginePlugin sharedInstance] sendFlutterEvent:payload];
    });
}
