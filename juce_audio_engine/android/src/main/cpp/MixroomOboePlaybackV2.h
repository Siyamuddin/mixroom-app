#pragma once

#include <cstdint>
#include <string>

namespace mixroom::android_audio_v2
{
enum class StreamPolicy : int32_t
{
    normal = 0,
    bluetoothMedia = 1,
    bluetoothCommunicationDuplex = 2,
};

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

struct StreamFacts
{
    bool available = false;
    bool running = false;
    uint64_t streamEpoch = 0;
    int32_t routedDeviceId = 0;
    int32_t channelCount = 0;
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

using OutputStreamFacts = StreamFacts;
using InputStreamFacts = StreamFacts;

void setBluetoothMediaPolicyEnabled (bool enabled);
void setStreamPolicy (StreamPolicy policy);
void resetPlaybackPolicy();
bool isBluetoothMediaPolicyEnabled();
bool isBluetoothCommunicationDuplexPolicyEnabled();
StreamPolicy getStreamPolicy();
OutputStreamFacts getOutputStreamFacts();
InputStreamFacts getInputStreamFacts();
uint64_t beginBluetoothMediaRouteMigration();
bool waitForBluetoothMediaRouteMigration (uint64_t token, int timeoutMs);
void finishBluetoothMediaRouteMigration (uint64_t token);
} // namespace mixroom::android_audio_v2
