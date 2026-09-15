#!/usr/bin/env python3
"""Compile/run the production identity cache against JUCE properties, without audio."""
import pathlib
import subprocess
import sys
import tempfile

if sys.platform != "darwin":
    raise SystemExit("This test runner requires macOS and Xcode command-line tools.")
root = pathlib.Path(__file__).resolve().parents[1]
modules = root / "juce_audio_engine/android/src/main/cpp/juce/modules"
with tempfile.TemporaryDirectory(prefix="pro20-identity-cache-") as temporary:
    binary = pathlib.Path(temporary) / "identity_cache_test"
    command = ["xcrun", "clang++", "-std=c++17", "-O1", "-DNDEBUG=1",
               "-DJUCE_GLOBAL_MODULE_SETTINGS_INCLUDED=1", "-DJUCE_USE_CURL=0",
               "-I", str(modules),
               str(root / "juce_audio_engine/native/tests/producer_plugin_identity_cache_test.cpp"),
               str(modules / "juce_core/juce_core.mm"),
               str(modules / "juce_core/juce_core_CompilationTime.cpp")]
    for framework in ("Cocoa", "CoreServices", "IOKit", "Security"):
        command += ["-framework", framework]
    subprocess.run(command + ["-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
