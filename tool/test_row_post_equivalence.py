#!/usr/bin/env python3
"""Build and run the deterministic macOS row-post DSP equivalence test."""

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
    / "build/macos/Build/Products/Profile/juce_audio_engine/"
    "juce_audio_engine.framework/Versions/A/juce_audio_engine"
)
if not library.is_file():
    raise SystemExit(
        "Missing Profile JUCE library; run the local macOS Profile build first."
    )

with tempfile.TemporaryDirectory(prefix="pro17-row-post-") as temporary:
    binary = pathlib.Path(temporary) / "row_post_equivalence_test"
    command = [
        "xcrun",
        "clang++",
        "-std=c++20",
        "-O1",
        "-Wno-deprecated-declarations",
        "-mmacosx-version-min=14.0",
        "-DDEBUG=1",
        "-D_DEBUG=1",
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
            / "juce_audio_engine/native/tests/row_post_equivalence_test.cpp"
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
