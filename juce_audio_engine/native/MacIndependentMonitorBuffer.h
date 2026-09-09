#pragma once

#include <juce_audio_basics/juce_audio_basics.h>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>

// Independent macOS input -> output transport. Its lifetime belongs to
// monitoring, not to the WAV writer or the timeline transport.
class MacIndependentMonitorBuffer
{
public:
    static constexpr int maxBlockFrames = 8192;
    static constexpr int storageFrames = maxBlockFrames * 8;

    bool configure(int requestedRow,
                   int requestedChannels,
                   double inputSampleRate,
                   double outputSampleRate,
                   int inputBlockFrames,
                   int outputBlockFrames) noexcept
    {
        if (active.load(std::memory_order_acquire) || requestedRow < 0 ||
            requestedChannels < 1 || requestedChannels > 2 ||
            inputSampleRate <= 1000.0 || outputSampleRate <= 1000.0 ||
            std::abs(inputSampleRate - outputSampleRate) >= 1.0 ||
            inputBlockFrames <= 0 || inputBlockFrames > maxBlockFrames ||
            outputBlockFrames <= 0 || outputBlockFrames > maxBlockFrames)
            return false;

        generation.fetch_add(1, std::memory_order_acq_rel);
        readPosition.store(0, std::memory_order_relaxed);
        writePosition.store(0, std::memory_order_relaxed);
        targetRow.store(requestedRow, std::memory_order_relaxed);
        channelCount.store(requestedChannels, std::memory_order_relaxed);
        inputBlockLimit.store(inputBlockFrames, std::memory_order_relaxed);
        outputBlockLimit.store(outputBlockFrames, std::memory_order_relaxed);
        capacity.store(
            juce::jmin(storageFrames,
                       8 * juce::jmax(inputBlockFrames, outputBlockFrames)),
            std::memory_order_relaxed);
        startThreshold.store(2 * outputBlockFrames, std::memory_order_relaxed);
        consumerStarted.store(false, std::memory_order_relaxed);
        publishedCallbacks.store(0, std::memory_order_relaxed);
        underflows.store(0, std::memory_order_relaxed);
        overflows.store(0, std::memory_order_relaxed);
        invalidBlocks.store(0, std::memory_order_relaxed);
        return true;
    }

    void activate() noexcept
    {
        active.store(true, std::memory_order_release);
    }

    void disableAndClear() noexcept
    {
        active.store(false, std::memory_order_release);
        generation.fetch_add(1, std::memory_order_acq_rel);
        consumerStarted.store(false, std::memory_order_release);
        readPosition.store(0, std::memory_order_release);
        writePosition.store(0, std::memory_order_release);
    }

    bool push(const float *const *inputs,
              int numChannels,
              int numFrames) noexcept
    {
        const auto operationGeneration =
            generation.load(std::memory_order_acquire);
        if (!active.load(std::memory_order_acquire))
            return false;
        if (inputs == nullptr ||
            numChannels != channelCount.load(std::memory_order_relaxed) ||
            numFrames <= 0 ||
            numFrames > inputBlockLimit.load(std::memory_order_relaxed))
        {
            invalidBlocks.fetch_add(1, std::memory_order_relaxed);
            return false;
        }
        for (int channel = 0; channel < numChannels; ++channel)
        {
            if (inputs[channel] == nullptr)
            {
                invalidBlocks.fetch_add(1, std::memory_order_relaxed);
                return false;
            }
        }

        const auto write = writePosition.load(std::memory_order_relaxed);
        const auto read = readPosition.load(std::memory_order_acquire);
        const auto configuredCapacity =
            static_cast<std::uint64_t>(capacity.load(std::memory_order_relaxed));
        if (write < read || write - read + static_cast<std::uint64_t>(numFrames) >
                                configuredCapacity)
        {
            overflows.fetch_add(1, std::memory_order_relaxed);
            return false;
        }

        const int firstFrame = static_cast<int>(write % configuredCapacity);
        const int firstCount = juce::jmin(
            numFrames,
            static_cast<int>(configuredCapacity) - firstFrame);
        const int secondCount = numFrames - firstCount;
        for (int channel = 0; channel < numChannels; ++channel)
        {
            juce::FloatVectorOperations::copy(
                samples[(size_t)channel].data() + firstFrame,
                inputs[channel],
                firstCount);
            if (secondCount > 0)
                juce::FloatVectorOperations::copy(
                    samples[(size_t)channel].data(),
                    inputs[channel] + firstCount,
                    secondCount);
        }
        if (!active.load(std::memory_order_acquire) ||
            operationGeneration != generation.load(std::memory_order_acquire))
            return false;

        writePosition.store(
            write + static_cast<std::uint64_t>(numFrames),
            std::memory_order_release);
        publishedCallbacks.fetch_add(1, std::memory_order_relaxed);
        return true;
    }

    void read(juce::AudioBuffer<float> &output) noexcept
    {
        output.clear();
        const int numFrames = output.getNumSamples();
        const int configuredChannels =
            channelCount.load(std::memory_order_relaxed);
        if (!active.load(std::memory_order_acquire))
            return;
        if (numFrames <= 0 ||
            numFrames > outputBlockLimit.load(std::memory_order_relaxed) ||
            output.getNumChannels() < configuredChannels)
        {
            invalidBlocks.fetch_add(1, std::memory_order_relaxed);
            return;
        }

        const auto read = readPosition.load(std::memory_order_relaxed);
        const auto write = writePosition.load(std::memory_order_acquire);
        const auto ready = write >= read ? write - read : 0;
        if (!consumerStarted.load(std::memory_order_relaxed))
        {
            if (ready < static_cast<std::uint64_t>(
                            startThreshold.load(std::memory_order_relaxed)))
            {
                underflows.fetch_add(1, std::memory_order_relaxed);
                return;
            }
            consumerStarted.store(true, std::memory_order_relaxed);
        }
        if (ready < static_cast<std::uint64_t>(numFrames))
        {
            consumerStarted.store(false, std::memory_order_relaxed);
            underflows.fetch_add(1, std::memory_order_relaxed);
            return;
        }

        const auto configuredCapacity =
            static_cast<std::uint64_t>(capacity.load(std::memory_order_relaxed));
        const int firstFrame = static_cast<int>(read % configuredCapacity);
        const int firstCount = juce::jmin(
            numFrames,
            static_cast<int>(configuredCapacity) - firstFrame);
        const int secondCount = numFrames - firstCount;
        for (int channel = 0; channel < configuredChannels; ++channel)
        {
            juce::FloatVectorOperations::copy(
                output.getWritePointer(channel),
                samples[(size_t)channel].data() + firstFrame,
                firstCount);
            if (secondCount > 0)
                juce::FloatVectorOperations::copy(
                    output.getWritePointer(channel) + firstCount,
                    samples[(size_t)channel].data(),
                    secondCount);
        }
        readPosition.store(
            read + static_cast<std::uint64_t>(numFrames),
            std::memory_order_release);
    }

    bool isActive() const noexcept
    {
        return active.load(std::memory_order_acquire);
    }

    juce::NamedValueSet getFacts() const
    {
        const auto read = readPosition.load(std::memory_order_acquire);
        const auto write = writePosition.load(std::memory_order_acquire);
        juce::NamedValueSet facts;
        facts.set("active", isActive());
        facts.set("targetRow", targetRow.load(std::memory_order_relaxed));
        facts.set("channelCount", channelCount.load(std::memory_order_relaxed));
        facts.set("capacityFrames", capacity.load(std::memory_order_relaxed));
        facts.set("bufferedFrames", (juce::int64)(write >= read ? write - read : 0));
        facts.set("callbackCount", (juce::int64)publishedCallbacks.load(std::memory_order_relaxed));
        facts.set("underflowCount", (juce::int64)underflows.load(std::memory_order_relaxed));
        facts.set("overflowCount", (juce::int64)overflows.load(std::memory_order_relaxed));
        facts.set("invalidBlockCount", (juce::int64)invalidBlocks.load(std::memory_order_relaxed));
        return facts;
    }

private:
    std::array<std::array<float, storageFrames>, 2> samples{};
    std::atomic<bool> active{false};
    std::atomic<bool> consumerStarted{false};
    std::atomic<std::uint64_t> generation{1};
    std::atomic<std::uint64_t> readPosition{0};
    std::atomic<std::uint64_t> writePosition{0};
    std::atomic<int> channelCount{0};
    std::atomic<int> targetRow{-1};
    std::atomic<int> inputBlockLimit{0};
    std::atomic<int> outputBlockLimit{0};
    std::atomic<int> capacity{0};
    std::atomic<int> startThreshold{0};
    std::atomic<std::uint64_t> publishedCallbacks{0};
    std::atomic<std::uint64_t> underflows{0};
    std::atomic<std::uint64_t> overflows{0};
    std::atomic<std::uint64_t> invalidBlocks{0};
};
