#!/usr/bin/env python3
"""Build and run deterministic JUCE graph-liveness regression coverage."""

import pathlib
import subprocess
import sys
import tempfile


if sys.platform != "darwin":
    raise SystemExit("This native test requires macOS and Xcode command-line tools.")

root = pathlib.Path(__file__).resolve().parents[1]
modules = root / "juce_audio_engine/android/src/main/cpp/juce/modules"
library = (
    root
    / "build/macos/Build/Products/Debug/juce_audio_engine/"
    "juce_audio_engine.framework/Versions/A/juce_audio_engine"
)
if not library.is_file():
    raise SystemExit("Missing Debug JUCE library; run the local macOS Debug build first.")

with tempfile.TemporaryDirectory(prefix="pro17-graph-liveness-") as temporary:
    binary = pathlib.Path(temporary) / "audio_processor_graph_liveness_test"
    command = [
        "xcrun",
        "clang++",
        "-std=c++20",
        "-O1",
        "-Wno-deprecated-declarations",
        "-mmacosx-version-min=14.0",
        "-DDEBUG=1",
        "-D_DEBUG=1",
        "-DMIXROOM_ENABLE_TEST_HOOKS=1",
        "-DMIXROOM_VERIFY_GRAPH_LIVENESS=1",
        "-DJUCE_GLOBAL_MODULE_SETTINGS_INCLUDED=1",
        "-DJUCE_PLUGINHOST_AU=1",
        "-DJUCE_PLUGINHOST_VST3=1",
        "-DJUCE_PLUGINHOST_VST=0",
        "-DJUCE_WEB_BROWSER=0",
        "-DJUCE_USE_CURL=0",
        "-DJUCE_USE_CAMERA=0",
        "-DJUCE_DONT_DECLARE_PROJECTINFO=1",
        "-DJUCE_MODAL_LOOPS_PERMITTED=1",
        "-DJUCE_USE_HARFBUZZ=0",
        "-DJUCE_STRICT_REFCOUNTEDPOINTER=1",
        "-I",
        str(modules),
        str(
            root
            / "juce_audio_engine/native/tests/audio_processor_graph_liveness_test.cpp"
        ),
        str(library),
    ]
    for framework in (
        "Cocoa",
        "AVFoundation",
        "CoreServices",
        "IOKit",
        "Security",
        "QuartzCore",
        "CoreImage",
        "CoreVideo",
        "CoreAudio",
        "CoreAudioKit",
        "CoreMIDI",
        "AudioUnit",
        "AudioToolbox",
        "Accelerate",
    ):
        command += ["-framework", framework]
    subprocess.run(command + ["-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
