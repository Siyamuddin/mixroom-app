# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file LICENSE.rst or https://cmake.org/licensing for details.

cmake_minimum_required(VERSION ${CMAKE_VERSION}) # this file comes with cmake

# If CMAKE_DISABLE_SOURCE_CHANGES is set to true and the source directory is an
# existing directory in our source tree, calling file(MAKE_DIRECTORY) on it
# would cause a fatal error, even though it would be a no-op.
if(NOT EXISTS "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/_deps/oboe-src")
  file(MAKE_DIRECTORY "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/_deps/oboe-src")
endif()
file(MAKE_DIRECTORY
  "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/_deps/oboe-build"
  "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/_deps/oboe-subbuild/oboe-populate-prefix"
  "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/_deps/oboe-subbuild/oboe-populate-prefix/tmp"
  "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/_deps/oboe-subbuild/oboe-populate-prefix/src/oboe-populate-stamp"
  "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/_deps/oboe-subbuild/oboe-populate-prefix/src"
  "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/_deps/oboe-subbuild/oboe-populate-prefix/src/oboe-populate-stamp"
)

set(configSubDirs )
foreach(subDir IN LISTS configSubDirs)
    file(MAKE_DIRECTORY "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/_deps/oboe-subbuild/oboe-populate-prefix/src/oboe-populate-stamp/${subDir}")
endforeach()
if(cfgdir)
  file(MAKE_DIRECTORY "/Users/andrewhyungulee/Mixroom/mixroom-app/juce_audio_engine/android/src/main/cpp/build_juce_modules/_deps/oboe-subbuild/oboe-populate-prefix/src/oboe-populate-stamp${cfgdir}") # cfgdir has leading slash
endif()
