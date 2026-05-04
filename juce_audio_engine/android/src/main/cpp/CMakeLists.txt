cmake_minimum_required(VERSION 3.22)
project(juce_audio_engine)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Ensure PIC everywhere (shared libs require this; static libs benefit too)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ---- 16KB page-size alignment for Android 15+ devices ----
# Apply both globally (safety net) and per-target (belt & suspenders).
set(_ALIGN_16K "-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${_ALIGN_16K}")
set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} ${_ALIGN_16K}")
set(CMAKE_EXE_LINKER_FLAGS    "${CMAKE_EXE_LINKER_FLAGS} ${_ALIGN_16K}")


add_definitions(-DJUCE_ANDROID=1)
add_definitions(-DJUCE_GUI_BASICS_INCLUDE_ANDROID=1)
add_definitions(-DJUCE_USE_ANDROID_OBOE=1)

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/juce/modules/juce_audio_devices/native/oboe)           
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/juce/modules/juce_audio_devices/native/oboe/include)

# Paths
include_directories(${CMAKE_CURRENT_SOURCE_DIR})
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/juce/modules)
include_directories(${ANDROID_NDK}/sources/android/cpufeatures)

# Find Harfbuzz
add_subdirectory(harfbuzz)
include_directories(harfbuzz/src)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/juce/modules/sheenbidi/Headers)

file(GLOB_RECURSE SHEENBIDI_SRC
    ${CMAKE_CURRENT_SOURCE_DIR}/juce/modules/sheenbidi/Source/*.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/juce/modules/sheenbidi/Source/*.c
)

add_library(sheenbidi STATIC ${SHEENBIDI_SRC})

find_library(log-lib log)

# Engine source files
set(SRC_FILES
    JuceBridge.cpp
    JuceEngine.cpp
    NativeEffects.cpp
    InstrumentRenderers.cpp
    JuceLogBridge.cpp
)

# Manually add NDK's cpu-features (JUCE core uses it)
add_library(cpu-features STATIC ${ANDROID_NDK}/sources/android/cpufeatures/cpu-features.c)

# Create the shared plugin library
add_library(juce_audio_engine SHARED ${SRC_FILES})

# Apply 16KB alignment flags directly to the target as well
target_link_options(juce_audio_engine PRIVATE
    -Wl,-z,max-page-size=16384
    -Wl,-z,common-page-size=16384
)

# Link all libraries
target_link_libraries(juce_audio_engine
    ${CMAKE_CURRENT_SOURCE_DIR}/libJuceModules.a

    oboe
    cpu-features
    sheenbidi
    harfbuzz
    ${log-lib}
    log
    android
    m
    atomic
)

# cmake_minimum_required(VERSION 3.22.1)
# project(JuceModules)

# set(CMAKE_CXX_STANDARD 17)

# # Set JUCE root relative to current folder
# set(JUCE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/juce")

# # JUCE flags
# add_definitions(
#     -DJUCE_ANDROID=1
#     -DJUCE_ANDROID_API_VERSION=29
#     -DJUCE_GLOBAL_MODULE_SETTINGS_INCLUDED=1
#     -DJUCE_USE_HARFBUZZ=0
#     -DJUCE_USE_ANDROID_OBOE=1
#     -DJUCE_USE_ANDROID_OPENSLES=0
# )

# # Include JUCE headers
# include_directories(${JUCE_ROOT}/modules)

# include(FetchContent)
# FetchContent_Declare(
#   oboe
#   GIT_REPOSITORY https://github.com/google/oboe.git
#   GIT_TAG 1.8.1 # or a known good version
# )
# FetchContent_MakeAvailable(oboe)

# # Define JUCE source files
# set(JUCE_SOURCES
#     ${JUCE_ROOT}/modules/juce_core/juce_core.cpp
#     ${JUCE_ROOT}/modules/juce_events/juce_events.cpp
#     ${JUCE_ROOT}/modules/juce_data_structures/juce_data_structures.cpp
#     ${JUCE_ROOT}/modules/juce_audio_basics/juce_audio_basics.cpp
#     ${JUCE_ROOT}/modules/juce_audio_devices/juce_audio_devices.cpp
#     ${JUCE_ROOT}/modules/juce_audio_formats/juce_audio_formats.cpp
#     ${JUCE_ROOT}/modules/juce_audio_processors/juce_audio_processors.cpp
#     ${JUCE_ROOT}/modules/juce_audio_utils/juce_audio_utils.cpp
#     ${JUCE_ROOT}/modules/juce_gui_basics/juce_gui_basics.cpp
#     ${JUCE_ROOT}/modules/juce_gui_extra/juce_gui_extra.cpp
#     ${JUCE_ROOT}/modules/juce_graphics/juce_graphics.cpp
#     ${JUCE_ROOT}/modules/juce_dsp/juce_dsp.cpp
# )

# # Add include path for cpu-features.h
# if(ANDROID)
#     set(CPU_FEATURES_DIR "${ANDROID_NDK}/sources/android/cpufeatures")
#     include_directories(${CPU_FEATURES_DIR})
# endif()

# # Build static library
# add_library(JuceModules STATIC ${JUCE_SOURCES})

# # Android native libs needed by JUCE
# target_link_libraries(JuceModules PRIVATE log cpufeatures oboe)
