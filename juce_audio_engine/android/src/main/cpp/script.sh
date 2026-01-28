#!/bin/bash
set -e

BUILD_DIR=build_juce_modules
INSTALL_DIR=../../../JuceModules.android-arm64

mkdir -p $BUILD_DIR && cd $BUILD_DIR

cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-29 \
  -DCMAKE_BUILD_TYPE=Release \
  -DJUCE_USE_ANDROID_OBOE=1 \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5


cmake --build . --target JuceModules -- -j8

# Copy artifacts
mkdir -p $INSTALL_DIR
cp libJuceModules.a $INSTALL_DIR/
cp -r ../juce/modules $INSTALL_DIR/Headers
