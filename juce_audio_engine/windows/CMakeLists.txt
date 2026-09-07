cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "juce_audio_engine")
project(${PROJECT_NAME} LANGUAGES C CXX)

cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "juce_audio_engine_plugin")

list(APPEND PLUGIN_SOURCES
  "juce_audio_engine_plugin.cpp"
  "juce_audio_engine_plugin.h"
  "JuceLogBridgeWindows.cpp"
  "../ios/Classes/JuceEngine.cpp"
  "../ios/Classes/NativeEffects.cpp"
  "../ios/Classes/InstrumentRenderers.cpp"
  "../android/src/main/cpp/juce/modules/juce_core/juce_core.cpp"
  "../android/src/main/cpp/juce/modules/juce_core/juce_core_CompilationTime.cpp"
  "../android/src/main/cpp/juce/modules/juce_events/juce_events.cpp"
  "../android/src/main/cpp/juce/modules/juce_data_structures/juce_data_structures.cpp"
  "../android/src/main/cpp/juce/modules/juce_graphics/juce_graphics.cpp"
  "../android/src/main/cpp/juce/modules/juce_graphics/juce_graphics_Harfbuzz.cpp"
  "../android/src/main/cpp/juce/modules/juce_graphics/juce_graphics_Sheenbidi.c"
  "../android/src/main/cpp/juce/modules/juce_gui_basics/juce_gui_basics.cpp"
  "../android/src/main/cpp/juce/modules/juce_gui_extra/juce_gui_extra.cpp"
  "../android/src/main/cpp/juce/modules/juce_audio_basics/juce_audio_basics.cpp"
  "../android/src/main/cpp/juce/modules/juce_audio_devices/juce_audio_devices.cpp"
  "../android/src/main/cpp/juce/modules/juce_audio_formats/juce_audio_formats.cpp"
  "../android/src/main/cpp/juce/modules/juce_audio_processors/juce_audio_processors.cpp"
  "../android/src/main/cpp/juce/modules/juce_audio_utils/juce_audio_utils.cpp"
  "../android/src/main/cpp/juce/modules/juce_dsp/juce_dsp.cpp"
)

add_library(${PLUGIN_NAME} SHARED
  "include/juce_audio_engine/juce_audio_engine_plugin_c_api.h"
  "juce_audio_engine_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_17)
target_compile_definitions(${PLUGIN_NAME} PRIVATE
  FLUTTER_PLUGIN_IMPL
  JUCE_GLOBAL_MODULE_SETTINGS_INCLUDED=1
  JUCE_PLUGINHOST_VST3=1
  JUCE_PLUGINHOST_AU=0
  JUCE_PLUGINHOST_VST=0
  JUCE_WEB_BROWSER=0
  JUCE_USE_CURL=0
  JUCE_USE_CAMERA=0
  JUCE_DONT_DECLARE_PROJECTINFO=1
  JUCE_MODAL_LOOPS_PERMITTED=1
  JUCE_USE_HARFBUZZ=0
  JUCE_STRICT_REFCOUNTEDPOINTER=1
  NOMINMAX
  _USE_MATH_DEFINES
)

target_include_directories(${PLUGIN_NAME}
  INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include"
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes"
    "${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/juce/modules"
    "${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/juce/modules/juce_audio_processors/format_types/VST3_SDK"
)

if(MSVC)
  # Flutter's standard Windows settings enable /WX. The shared JUCE sources
  # contain upstream deprecation and conversion warnings, so keep warnings
  # visible without failing this plugin's Windows build.
  target_compile_options(${PLUGIN_NAME} PRIVATE /bigobj /EHsc /WX-)
endif()

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  avrt
  comdlg32
  crypt32
  dwmapi
  gdi32
  imm32
  ole32
  oleaut32
  setupapi
  shell32
  shlwapi
  user32
  uuid
  version
  winmm
  ws2_32
)

set(juce_audio_engine_bundled_libraries
  ""
  PARENT_SCOPE
)
