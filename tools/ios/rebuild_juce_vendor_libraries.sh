#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/juce_audio_engine/ios"
DEVICE_HEADERS="$IOS_DIR/JuceModules.xcframework/ios-arm64/Headers"
SIM_HEADERS="$IOS_DIR/JuceModules.xcframework/ios-arm64_x86_64-simulator/Headers"
WRAPPER_DIR="$ROOT_DIR/tools/ios/juce_vendor"
POLICY_PATCH="$WRAPPER_DIR/mixroom_ios_audio_session_policy.patch"
POLICY_INCLUDE_DIR="$IOS_DIR/Classes"
EXPECTED_IOS_AUDIO_SOURCE_SHA="cb90606887e7c9fc925f8c004a651135edf86880cfd2ddf8590239f0a0abca05"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/juce_vendor_rebuild.XXXXXX")"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

prepare_header_tree() {
  local source_root="$1"
  local destination_root="$2"
  local source_file="$source_root/juce_audio_devices/native/juce_Audio_ios.cpp"

  local source_sha
  source_sha="$(shasum -a 256 "$source_file" | awk '{print $1}')"
  if [[ "$source_sha" != "$EXPECTED_IOS_AUDIO_SOURCE_SHA" ]]; then
    echo "Unexpected JUCE iOS audio source revision: $source_sha" >&2
    exit 1
  fi

  mkdir -p "$destination_root"
  cp -R "$source_root/." "$destination_root"
  perl -pi -e 's/\r$//' \
    "$destination_root/juce_audio_devices/native/juce_Audio_ios.cpp"
  patch -d "$destination_root" -p1 < "$POLICY_PATCH"
}

DEVICE_PATCHED_HEADERS="$TMP_DIR/device-headers"
SIM_PATCHED_HEADERS="$TMP_DIR/simulator-headers"

device_source_sha="$(shasum -a 256 \
  "$DEVICE_HEADERS/juce_audio_devices/native/juce_Audio_ios.cpp" | awk '{print $1}')"
sim_source_sha="$(shasum -a 256 \
  "$SIM_HEADERS/juce_audio_devices/native/juce_Audio_ios.cpp" | awk '{print $1}')"
if [[ "$device_source_sha" != "$sim_source_sha" ]]; then
  echo "Device and simulator JUCE iOS sources differ." >&2
  exit 1
fi

prepare_header_tree "$DEVICE_HEADERS" "$DEVICE_PATCHED_HEADERS"
prepare_header_tree "$SIM_HEADERS" "$SIM_PATCHED_HEADERS"

compile_module() {
  local sdk="$1"
  local arch="$2"
  local config="$3"
  local header_root="$4"
  local wrapper="$5"
  local out="$6"

  local sdk_path
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"

  local -a defs=(
    -DJUCE_GLOBAL_MODULE_SETTINGS_INCLUDED=1
    -DJUCE_IOS=1
    -DJUCE_PLUGINHOST_AU=1
    -DJUCE_USE_CURL=0
    -DJUCE_WEB_BROWSER=0
    -DJUCE_USE_CAMERA=0
    -DJUCE_DONT_DECLARE_PROJECTINFO=1
    -DJUCE_MODAL_LOOPS_PERMITTED=1
    -DJUCE_STRICT_REFCOUNTEDPOINTER=1
  )

  if [[ "$config" == "debug" ]]; then
    defs+=(-DDEBUG=1 -DJUCE_IOS_AUDIO_EXPLICIT_SAMPLERATES=44100)
  else
    defs+=(-DNDEBUG=1)
  fi

  local min_flag
  if [[ "$sdk" == "iphoneos" ]]; then
    min_flag="-miphoneos-version-min=15.0"
  else
    min_flag="-mios-simulator-version-min=15.0"
  fi

  xcrun --sdk "$sdk" clang++ \
    -x objective-c++ \
    -std=c++17 \
    -stdlib=libc++ \
    -fno-objc-arc \
    -fPIC \
    -arch "$arch" \
    "$min_flag" \
    -isysroot "$sdk_path" \
    -I"$header_root" \
    -I"$WRAPPER_DIR" \
    -I"$POLICY_INCLUDE_DIR" \
    "${defs[@]}" \
    -c "$wrapper" \
    -o "$out"
}

replace_objects_in_archive() {
  local source_archive="$1"
  local dest_archive="$2"
  local new_devices_o="$3"
  local new_utils_o="$4"

  local work_dir="$TMP_DIR/$(basename "$dest_archive" .a)"
  mkdir -p "$work_dir"

  local manifest="$work_dir/manifest.txt"
  xcrun ar -t "$source_archive" > "$manifest"

  (
    cd "$work_dir"
    xcrun ar -x "$source_archive"
    cp "$new_devices_o" include_juce_audio_devices.o
    cp "$new_utils_o" include_juce_audio_utils.o

    local -a ordered_objects=()
    while IFS= read -r obj; do
      if [[ "$obj" == "__.SYMDEF" || "$obj" == "__.SYMDEF SORTED" ]]; then
        continue
      fi
      ordered_objects+=("$obj")
    done < "$manifest"

    local rebuilt_archive="$work_dir/rebuilt.a"
    rm -f "$rebuilt_archive"
    xcrun libtool -static -o "$rebuilt_archive" "${ordered_objects[@]}"
    mv "$rebuilt_archive" "$dest_archive"
  )
}

DEVICE_DEBUG_DEVICES_O="$TMP_DIR/include_juce_audio_devices.debug.device.o"
DEVICE_DEBUG_UTILS_O="$TMP_DIR/include_juce_audio_utils.debug.device.o"
DEVICE_RELEASE_DEVICES_O="$TMP_DIR/include_juce_audio_devices.release.device.o"
DEVICE_RELEASE_UTILS_O="$TMP_DIR/include_juce_audio_utils.release.device.o"
SIM_ARM64_DEVICES_O="$TMP_DIR/include_juce_audio_devices.debug.sim.arm64.o"
SIM_ARM64_UTILS_O="$TMP_DIR/include_juce_audio_utils.debug.sim.arm64.o"
SIM_X64_DEVICES_O="$TMP_DIR/include_juce_audio_devices.debug.sim.x86_64.o"
SIM_X64_UTILS_O="$TMP_DIR/include_juce_audio_utils.debug.sim.x86_64.o"

compile_module iphoneos arm64 debug "$DEVICE_PATCHED_HEADERS" "$WRAPPER_DIR/include_juce_audio_devices.mm" "$DEVICE_DEBUG_DEVICES_O"
compile_module iphoneos arm64 debug "$DEVICE_PATCHED_HEADERS" "$WRAPPER_DIR/include_juce_audio_utils.mm" "$DEVICE_DEBUG_UTILS_O"
compile_module iphoneos arm64 release "$DEVICE_PATCHED_HEADERS" "$WRAPPER_DIR/include_juce_audio_devices.mm" "$DEVICE_RELEASE_DEVICES_O"
compile_module iphoneos arm64 release "$DEVICE_PATCHED_HEADERS" "$WRAPPER_DIR/include_juce_audio_utils.mm" "$DEVICE_RELEASE_UTILS_O"
compile_module iphonesimulator arm64 debug "$SIM_PATCHED_HEADERS" "$WRAPPER_DIR/include_juce_audio_devices.mm" "$SIM_ARM64_DEVICES_O"
compile_module iphonesimulator arm64 debug "$SIM_PATCHED_HEADERS" "$WRAPPER_DIR/include_juce_audio_utils.mm" "$SIM_ARM64_UTILS_O"
compile_module iphonesimulator x86_64 debug "$SIM_PATCHED_HEADERS" "$WRAPPER_DIR/include_juce_audio_devices.mm" "$SIM_X64_DEVICES_O"
compile_module iphonesimulator x86_64 debug "$SIM_PATCHED_HEADERS" "$WRAPPER_DIR/include_juce_audio_utils.mm" "$SIM_X64_UTILS_O"

replace_objects_in_archive \
  "$IOS_DIR/JuceModules.xcframework/ios-arm64/libJuceModules_debug3.a" \
  "$IOS_DIR/JuceModules.xcframework/ios-arm64/libJuceModules_debug3.a" \
  "$DEVICE_DEBUG_DEVICES_O" \
  "$DEVICE_DEBUG_UTILS_O"

replace_objects_in_archive \
  "$IOS_DIR/JuceModules.xcframework/ios-arm64/libJuceModules.a" \
  "$IOS_DIR/JuceModules.xcframework/ios-arm64/libJuceModules.a" \
  "$DEVICE_RELEASE_DEVICES_O" \
  "$DEVICE_RELEASE_UTILS_O"

SIM_THIN_ARM64="$TMP_DIR/libJuceModules_sim.arm64.a"
SIM_THIN_X64="$TMP_DIR/libJuceModules_sim.x86_64.a"
SIM_REBUILT_ARM64="$TMP_DIR/libJuceModules_sim.arm64.rebuilt.a"
SIM_REBUILT_X64="$TMP_DIR/libJuceModules_sim.x86_64.rebuilt.a"

xcrun lipo "$IOS_DIR/JuceModules.xcframework/ios-arm64_x86_64-simulator/libJuceModules_sim.a" -thin arm64 -output "$SIM_THIN_ARM64"
xcrun lipo "$IOS_DIR/JuceModules.xcframework/ios-arm64_x86_64-simulator/libJuceModules_sim.a" -thin x86_64 -output "$SIM_THIN_X64"

replace_objects_in_archive "$SIM_THIN_ARM64" "$SIM_REBUILT_ARM64" "$SIM_ARM64_DEVICES_O" "$SIM_ARM64_UTILS_O"
replace_objects_in_archive "$SIM_THIN_X64" "$SIM_REBUILT_X64" "$SIM_X64_DEVICES_O" "$SIM_X64_UTILS_O"

xcrun lipo -create \
  "$SIM_REBUILT_ARM64" \
  "$SIM_REBUILT_X64" \
  -output "$IOS_DIR/JuceModules.xcframework/ios-arm64_x86_64-simulator/libJuceModules_sim.a"

echo "Rebuilt vendored JUCE libraries:"
echo "  $IOS_DIR/JuceModules.xcframework/ios-arm64/libJuceModules_debug3.a"
echo "  $IOS_DIR/JuceModules.xcframework/ios-arm64/libJuceModules.a"
echo "  $IOS_DIR/JuceModules.xcframework/ios-arm64_x86_64-simulator/libJuceModules_sim.a"
