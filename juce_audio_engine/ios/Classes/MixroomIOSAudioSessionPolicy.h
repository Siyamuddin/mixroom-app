#pragma once

#include <cstdint>

enum class MixroomIOSAudioSessionPolicy : std::int32_t
{
    legacyManaged = 0,
    v2PlaybackOnly = 1,
    v2BuiltInDuplex = 2,
    v2BluetoothHfpDuplex = 3,
};

enum class MixroomIOSAudioSessionPolicyStatus : std::int32_t
{
    ok = 0,
    sessionConfigurationFailed = 1,
    sessionActivationFailed = 2,
    noInput = 3,
    ambiguousInput = 4,
    preferredInputFailed = 5,
};

struct MixroomIOSAudioSessionPolicyFacts
{
    MixroomIOSAudioSessionPolicy policy;
    MixroomIOSAudioSessionPolicyStatus status;
    std::int32_t activationCount;
    double mutationElapsedMilliseconds;
};

extern "C" void mixroomIOSSetAudioSessionPolicy(
    MixroomIOSAudioSessionPolicy policy) noexcept;

extern "C" bool mixroomIOSPrepareAudioSessionPolicy() noexcept;

extern "C" MixroomIOSAudioSessionPolicyFacts
mixroomIOSGetAudioSessionPolicyFacts() noexcept;
