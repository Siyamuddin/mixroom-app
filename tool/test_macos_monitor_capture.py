#!/usr/bin/env python3
"""Build/run the native monitor + WAV signal test without accessing devices."""
import pathlib
import subprocess
import sys
import tempfile

if sys.platform != "darwin":
    raise SystemExit("This native test requires macOS and Xcode command-line tools.")
root = pathlib.Path(__file__).resolve().parents[1]
modules = root / "juce_audio_engine/android/src/main/cpp/juce/modules"
with tempfile.TemporaryDirectory(prefix="pro72-native-") as temporary:
    binary = pathlib.Path(temporary) / "monitor_capture_test"
    command = ["xcrun", "clang++", "-std=c++17", "-O1", "-mmacosx-version-min=14.0",
               "-DNDEBUG=1", "-DJUCE_GLOBAL_MODULE_SETTINGS_INCLUDED=1", "-DJUCE_USE_CURL=0",
               "-DJUCE_USE_FLAC=0", "-DJUCE_USE_OGGVORBIS=0", "-DJUCE_WEB_BROWSER=0",
               "-I", str(modules),
               str(root / "juce_audio_engine/native/tests/mac_monitor_capture_test.cpp")]
    for module in ("juce_core", "juce_audio_basics", "juce_audio_formats"):
        command += [str(modules / module / f"{module}.mm")]
    command += [str(modules / "juce_core/juce_core_CompilationTime.cpp")]
    for framework in ("Cocoa", "CoreServices", "IOKit", "Security", "CoreAudio", "AudioToolbox", "Accelerate"):
        command += ["-framework", framework]
    subprocess.run(command + ["-o", str(binary)], check=True)
    subprocess.run([str(binary), temporary], check=True)
