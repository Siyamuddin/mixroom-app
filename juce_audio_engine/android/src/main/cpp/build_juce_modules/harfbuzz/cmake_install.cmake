# Install script for directory: /Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz

# Set the install prefix
if(NOT DEFINED CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX "/usr/local")
endif()
string(REGEX REPLACE "/$" "" CMAKE_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}")

# Set the install configuration name.
if(NOT DEFINED CMAKE_INSTALL_CONFIG_NAME)
  if(BUILD_TYPE)
    string(REGEX REPLACE "^[^A-Za-z0-9_]+" ""
           CMAKE_INSTALL_CONFIG_NAME "${BUILD_TYPE}")
  else()
    set(CMAKE_INSTALL_CONFIG_NAME "Release")
  endif()
  message(STATUS "Install configuration: \"${CMAKE_INSTALL_CONFIG_NAME}\"")
endif()

# Set the component getting installed.
if(NOT CMAKE_INSTALL_COMPONENT)
  if(COMPONENT)
    message(STATUS "Install component: \"${COMPONENT}\"")
    set(CMAKE_INSTALL_COMPONENT "${COMPONENT}")
  else()
    set(CMAKE_INSTALL_COMPONENT)
  endif()
endif()

# Install shared libraries without execute permission?
if(NOT DEFINED CMAKE_INSTALL_SO_NO_EXE)
  set(CMAKE_INSTALL_SO_NO_EXE "0")
endif()

# Is this installation the result of a crosscompile?
if(NOT DEFINED CMAKE_CROSSCOMPILING)
  set(CMAKE_CROSSCOMPILING "TRUE")
endif()

# Set path to fallback-tool for dependency-resolution.
if(NOT DEFINED CMAKE_OBJDUMP)
  set(CMAKE_OBJDUMP "/Users/andrewhyungulee/Library/Android/sdk/ndk/25.1.8937393/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-objdump")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/include/harfbuzz" TYPE FILE FILES
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-aat-layout.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-aat.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-blob.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-buffer.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-common.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-cplusplus.hh"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-deprecated.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-draw.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-face.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-font.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-map.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-ot-color.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-ot-deprecated.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-ot-font.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-ot-layout.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-ot-math.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-ot-meta.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-ot-metrics.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-ot-name.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-ot-shape.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-ot-var.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-ot.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-paint.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-set.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-script-list.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-shape-plan.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-shape.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-style.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-unicode.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-version.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-subset.h"
    "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/harfbuzz/src/hb-subset-serialize.h"
    )
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib" TYPE STATIC_LIBRARY FILES "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/harfbuzz/libharfbuzz.a")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "pkgconfig" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/pkgconfig" TYPE FILE FILES "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/harfbuzz/harfbuzz.pc")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  if(EXISTS "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/harfbuzz/harfbuzzConfig.cmake")
    file(DIFFERENT _cmake_export_file_changed FILES
         "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/harfbuzz/harfbuzzConfig.cmake"
         "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/harfbuzz/CMakeFiles/Export/6988f0906c47366608790bc51d4c19aa/harfbuzzConfig.cmake")
    if(_cmake_export_file_changed)
      file(GLOB _cmake_old_config_files "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/harfbuzz/harfbuzzConfig-*.cmake")
      if(_cmake_old_config_files)
        string(REPLACE ";" ", " _cmake_old_config_files_text "${_cmake_old_config_files}")
        message(STATUS "Old export file \"$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/lib/cmake/harfbuzz/harfbuzzConfig.cmake\" will be replaced.  Removing files [${_cmake_old_config_files_text}].")
        unset(_cmake_old_config_files_text)
        file(REMOVE ${_cmake_old_config_files})
      endif()
      unset(_cmake_old_config_files)
    endif()
    unset(_cmake_export_file_changed)
  endif()
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/cmake/harfbuzz" TYPE FILE FILES "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/harfbuzz/CMakeFiles/Export/6988f0906c47366608790bc51d4c19aa/harfbuzzConfig.cmake")
  if(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Rr][Ee][Ll][Ee][Aa][Ss][Ee])$")
    file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/cmake/harfbuzz" TYPE FILE FILES "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/harfbuzz/CMakeFiles/Export/6988f0906c47366608790bc51d4c19aa/harfbuzzConfig-release.cmake")
  endif()
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib" TYPE STATIC_LIBRARY FILES "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/harfbuzz/libharfbuzz-subset.a")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "pkgconfig" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/pkgconfig" TYPE FILE FILES "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/harfbuzz/harfbuzz-subset.pc")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  file(INSTALL DESTINATION "${CMAKE_INSTALL_PREFIX}/include/harfbuzz" TYPE FILE FILES "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/harfbuzz/src/hb-features.h")
endif()

string(REPLACE ";" "\n" CMAKE_INSTALL_MANIFEST_CONTENT
       "${CMAKE_INSTALL_MANIFEST_FILES}")
if(CMAKE_INSTALL_LOCAL_ONLY)
  file(WRITE "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/harfbuzz/install_local_manifest.txt"
     "${CMAKE_INSTALL_MANIFEST_CONTENT}")
endif()
