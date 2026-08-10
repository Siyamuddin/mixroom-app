#pragma once

#include <cstdint>
#include <string>

namespace mixroom::android_audio_v2
{
constexpr int conservativeBufferTarget (int framesPerBurst, int capacity)
{
    if (framesPerBurst <= 0 || capacity <= 0)
        return 0;
    const auto burstTarget = 4 * framesPerBurst;
    const auto floorTarget = burstTarget > 1024 ? burstTarget : 1024;
    const auto cappedTarget = floorTarget < 2048 ? floorTarget : 2048;
    return cappedTarget < capacity ? cappedTarget : capacity;
}

static_assert (conservativeBufferTarget (240, 1920) == 1024);
static_assert (conservativeBufferTarget (512, 4096) == 2048);
static_assert (conservativeBufferTarget (128, 768) == 768);
static_assert (conservativeBufferTarget (0, 2048) == 0);

struct OutputStreamFacts
{
    bool available = false;
    bool running = false;
    int32_t routedDeviceId = 0;
    int32_t requestedSampleRate = 0;
    int32_t sampleRate = 0;
    int32_t requestedBufferSizeFrames = 0;
    int32_t bufferSizeFrames = 0;
    int32_t bufferCapacityFrames = 0;
    int32_t framesPerBurst = 0;
    int32_t framesPerCallback = 0;
    int32_t xRunCount = -1;
    std::string audioApi;
    std::string performanceMode;
    std::string sharingMode;
    std::string streamState;
};

void setBluetoothMediaPolicyEnabled (bool enabled);
void resetPlaybackPolicy();
bool isBluetoothMediaPolicyEnabled();
OutputStreamFacts getOutputStreamFacts();
} // namespace mixroom::android_audio_v2
