#!/usr/bin/env python3
"""Run the production Foundation-only iOS capture lifecycle on the Mac host."""
import pathlib
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
