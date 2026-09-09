#!/usr/bin/env python3
"""Host JUCE graph/WAV signal test; does not establish Android device audibility.

Pass a Debug macOS JUCE framework archive built by `flutter build macos --debug`.
The archive supplies JUCE modules; the test compiles the current WAV capture header.
"""
import argparse
import pathlib
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--juce-library', type=pathlib.Path, required=True)
args = parser.parse_args()
if sys.platform != 'darwin':
    raise SystemExit('This host test requires macOS and Xcode command-line tools.')
root = pathlib.Path(__file__).resolve().parents[1]
modules = root / 'juce_audio_engine/android/src/main/cpp/juce/modules'
with tempfile.TemporaryDirectory(prefix='pro72-android-signal-') as temporary:
    binary = pathlib.Path(temporary) / 'android_monitor_capture_test'
    command = ['xcrun', 'clang++', '-std=c++17', '-O1', '-mmacosx-version-min=14.0',
               '-I', str(modules)]
    for define in ('DEBUG=1', '_DEBUG=1', 'JUCE_GLOBAL_MODULE_SETTINGS_INCLUDED=1',
                   'JUCE_PLUGINHOST_AU=1', 'JUCE_PLUGINHOST_VST3=1', 'JUCE_PLUGINHOST_VST=0',
                   'JUCE_WEB_BROWSER=0', 'JUCE_USE_CURL=0', 'JUCE_USE_CAMERA=0',
                   'JUCE_DONT_DECLARE_PROJECTINFO=1', 'JUCE_MODAL_LOOPS_PERMITTED=1',
                   'JUCE_USE_HARFBUZZ=0', 'JUCE_STRICT_REFCOUNTEDPOINTER=1'):
        command.append('-D' + define)
    command += [str(root / 'juce_audio_engine/native/tests/android_monitor_capture_test.cpp'),
                str(args.juce_library.resolve())]
    for framework in ('Cocoa', 'AVFoundation', 'CoreServices', 'IOKit', 'Security',
                      'QuartzCore', 'CoreImage', 'CoreVideo', 'CoreAudio', 'CoreAudioKit', 'CoreMIDI', 'AudioUnit', 'AudioToolbox', 'Accelerate'):
        command += ['-framework', framework]
    subprocess.run(command + ['-o', str(binary)], check=True)
    subprocess.run([str(binary), temporary], check=True)
