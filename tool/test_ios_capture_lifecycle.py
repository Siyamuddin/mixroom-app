#!/usr/bin/env python3
"""Run the production Foundation-only iOS capture lifecycle on the Mac host."""
import pathlib
import re
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='pro72-ios-lifecycle-') as temporary:
    binary = pathlib.Path(temporary) / 'ios_capture_lifecycle_test'
    subprocess.run([
        'xcrun', 'clang', '-fobjc-arc', '-fblocks', '-framework', 'Foundation',
        str(root / 'juce_audio_engine/native/tests/ios_capture_lifecycle_test.m'),
        str(root / 'juce_audio_engine/ios/Classes/MixroomIOSCaptureLifecycleV2.m'),
        '-o', str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True)

    # Compile the actual plugin reply expression: C logical expressions box as
    # NSNumber integers, which Flutter cannot decode as invokeMethod<bool>.
    plugin = (root / 'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m').read_text()
    start = plugin.split('- (void)startIOSCaptureV2:', 1)[1].split('- (void)stopIOSCaptureV2:', 1)[0]
    reply = re.findall(r'result\(([^;]+)\);', start)[-1]
    source = pathlib.Path(temporary) / 'capture_reply_test.m'
    source.write_text('''#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <assert.h>
int main(void) {
    @autoreleasepool {
        for (int a = 0; a < 2; ++a) {
            for (int b = 0; b < 2; ++b) {
                BOOL started = a, current = b;
                NSNumber *reply = REPLY;
                assert(CFGetTypeID((__bridge CFTypeRef)reply) == CFBooleanGetTypeID());
                assert(reply.boolValue == (started && current));
            }
        }
    }
    return 0;
}
'''.replace('REPLY', reply))
    reply_binary = pathlib.Path(temporary) / 'capture_reply_test'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation',
                    str(source), '-o', str(reply_binary)], check=True)
    subprocess.run([str(reply_binary)], check=True)
    print('PASS: iOS capture reply uses boolean objects for all start/current combinations')
