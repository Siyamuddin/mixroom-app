#pragma once

#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <memory>
#include <mutex>

// A bounded disk-capture queue. Device routing and graph ownership remain with
// JuceEngine; this class owns only the WAV writer and its preallocated FIFO.
class RealtimeWavCapture final
{
public:
    struct StopResult
    {
        bool success = false;
        juce::String diagnosticCode{"writer_finalize_failed"};
        std::int64_t attemptedSamples = 0;
        std::int64_t acceptedSamples = 0;
        std::int64_t droppedSamples = 0;
        double actualSampleRate = 0.0;
        int channelCount = 0;

        juce::NamedValueSet toNamedValueSet() const
        {
            juce::NamedValueSet values;
            values.set("success", success);
            values.set("diagnosticCode", diagnosticCode);
            values.set("attemptedSamples", (juce::int64)attemptedSamples);
            values.set("acceptedSamples", (juce::int64)acceptedSamples);
            values.set("droppedSamples", (juce::int64)droppedSamples);
            values.set("actualSampleRate", actualSampleRate);
            values.set("channelCount", channelCount);
            return values;
        }
    };

    RealtimeWavCapture() = default;
    ~RealtimeWavCapture() { stop(); }

    bool start(const juce::File &targetFile,
               double sampleRate,
               int channelCount,
               int channelOffset)
    {
        const std::lock_guard<std::mutex> lock(controlMutex);
        if (admissionOpen.load(std::memory_order_acquire) || threadedWriter != nullptr)
            return false;

        if (sampleRate <= 0.0 || channelCount < 1 || channelCount > 2 || channelOffset < 0)
            return false;

        auto stream = targetFile.createOutputStream();
        if (stream == nullptr)
            return false;

        juce::WavAudioFormat wav;
        auto *rawWriter = wav.createWriterFor(
            stream.get(),
            sampleRate,
            (unsigned int)channelCount,
            24,
            {},
            0);
        if (rawWriter == nullptr)
        {
            stream.reset();
            targetFile.deleteFile();
            return false;
        }
        stream.release(); // AudioFormatWriter owns the stream from this point.

        auto nextThread = std::make_unique<juce::TimeSliceThread>(
            "Mixroom WAV capture writer");
        if (!nextThread->startThread())
        {
            delete rawWriter;
            targetFile.deleteFile();
            return false;
        }

        const int fifoSamples = juce::jmax(
            1,
            (int)std::ceil(sampleRate * 2.0));
        auto nextWriter = std::make_unique<juce::AudioFormatWriter::ThreadedWriter>(
            rawWriter,
            *nextThread,
            fifoSamples);

        file = targetFile;
        actualSampleRate = sampleRate;
        captureChannelCount = channelCount;
        captureChannelOffset = channelOffset;
        attemptedSamples.store(0, std::memory_order_relaxed);
        acceptedSamples.store(0, std::memory_order_relaxed);
        droppedSamples.store(0, std::memory_order_relaxed);
        invalidBlockCount.store(0, std::memory_order_relaxed);
        blockPeak.store(0.0f, std::memory_order_relaxed);
        callbacksDrained.reset();
        drainRequested.store(false, std::memory_order_relaxed);

        writerThread = std::move(nextThread);
        threadedWriter = std::move(nextWriter);
        captureSessionPresent = true;
        activeWriter.store(threadedWriter.get(), std::memory_order_release);
        admissionOpen.store(true, std::memory_order_release);
        return true;
    }

    StopResult stop(bool discardFile = false)
    {
        const std::lock_guard<std::mutex> lock(controlMutex);

        if (!captureSessionPresent)
            return lastStopResult;

        admissionOpen.store(false, std::memory_order_release);
        drainRequested.store(true, std::memory_order_release);
        if (inFlightCallbacks.load(std::memory_order_acquire) > 0)
            callbacksDrained.wait();

        activeWriter.store(nullptr, std::memory_order_release);
        threadedWriter.reset(); // Flushes the FIFO and finalizes the WAV.
        if (writerThread != nullptr)
        {
            writerThread->stopThread(1000);
            writerThread.reset();
        }

        StopResult result;
        result.attemptedSamples = attemptedSamples.load(std::memory_order_relaxed);
        result.acceptedSamples = acceptedSamples.load(std::memory_order_relaxed);
        result.droppedSamples = droppedSamples.load(std::memory_order_relaxed);
        result.actualSampleRate = actualSampleRate;
        result.channelCount = captureChannelCount;

        const bool invalidShape = invalidBlockCount.load(std::memory_order_relaxed) > 0;
        const bool overrun = result.droppedSamples > 0 && !invalidShape;
        const bool fileValid = validateFinalizedFile(result.acceptedSamples);

        if (invalidShape)
            result.diagnosticCode = "capture_shape_invalid";
        else if (overrun)
            result.diagnosticCode = "capture_overrun";
        else if (!fileValid)
            result.diagnosticCode = "writer_finalize_failed";
        else
        {
            result.success = true;
            result.diagnosticCode = "ok";
        }

        if ((discardFile || !result.success) && file != juce::File{})
            file.deleteFile();

        if (discardFile)
        {
            result.success = false;
            result.diagnosticCode = "writer_finalize_failed";
        }

        file = juce::File();
        actualSampleRate = 0.0;
        captureChannelCount = 0;
        captureChannelOffset = 0;
        captureSessionPresent = false;
        lastStopResult = result;
        drainRequested.store(false, std::memory_order_release);
        return result;
    }

    bool isActive() const noexcept
    {
        return admissionOpen.load(std::memory_order_acquire);
    }

    double consumePeak() const noexcept
    {
        return (double)blockPeak.exchange(0.0f, std::memory_order_acq_rel);
    }

    void capture(const float *const *channels,
                 int availableChannelCount,
                 int numSamples,
                 int channelOffsetOverride = -1) noexcept
    {
        inFlightCallbacks.fetch_add(1, std::memory_order_acq_rel);
        const auto leave = [this]() noexcept
        {
            const int remaining = inFlightCallbacks.fetch_sub(1, std::memory_order_acq_rel) - 1;
            if (remaining == 0 && drainRequested.load(std::memory_order_acquire))
                callbacksDrained.signal();
        };

        if (!admissionOpen.load(std::memory_order_acquire))
        {
            leave();
            return;
        }

        const int selectedOffset = channelOffsetOverride >= 0
            ? channelOffsetOverride
            : captureChannelOffset;
        const int selectedCount = captureChannelCount;
        const std::int64_t attempted = numSamples > 0 ? (std::int64_t)numSamples : 0;
        attemptedSamples.fetch_add(attempted, std::memory_order_relaxed);

        juce::AudioFormatWriter::ThreadedWriter *writer =
            activeWriter.load(std::memory_order_acquire);
        bool shapeValid = writer != nullptr && channels != nullptr &&
            numSamples > 0 && selectedCount >= 1 && selectedCount <= 2 &&
            selectedOffset >= 0 && selectedOffset + selectedCount <= availableChannelCount;

        std::array<const float *, 2> selected{{nullptr, nullptr}};
        if (shapeValid)
        {
            for (int channel = 0; channel < selectedCount; ++channel)
            {
                selected[(size_t)channel] = channels[selectedOffset + channel];
                if (selected[(size_t)channel] == nullptr)
                    shapeValid = false;
            }
        }

        if (!shapeValid)
        {
            invalidBlockCount.fetch_add(1, std::memory_order_relaxed);
            droppedSamples.fetch_add(attempted, std::memory_order_relaxed);
            leave();
            return;
        }

        float peak = 0.0f;
        for (int channel = 0; channel < selectedCount; ++channel)
            for (int sample = 0; sample < numSamples; ++sample)
                peak = juce::jmax(peak, std::abs(selected[(size_t)channel][sample]));
        publishPeak(peak);

        if (writer->write(selected.data(), numSamples))
            acceptedSamples.fetch_add((std::int64_t)numSamples, std::memory_order_relaxed);
        else
            droppedSamples.fetch_add((std::int64_t)numSamples, std::memory_order_relaxed);
        leave();
    }

private:
    void publishPeak(float peak) noexcept
    {
        float previous = blockPeak.load(std::memory_order_relaxed);
        while (peak > previous &&
               !blockPeak.compare_exchange_weak(previous,
                                                peak,
                                                std::memory_order_release,
                                                std::memory_order_relaxed))
        {}
    }

    bool validateFinalizedFile(std::int64_t expectedSamples) const
    {
        if (file == juce::File{} || !file.existsAsFile() || expectedSamples <= 0)
            return false;

        juce::WavAudioFormat wav;
        auto inputStream = file.createInputStream();
        if (inputStream == nullptr)
            return false;

        std::unique_ptr<juce::AudioFormatReader> reader(
            wav.createReaderFor(inputStream.release(), true));
        if (reader == nullptr)
            return false;

        return (int)reader->numChannels == captureChannelCount &&
            std::abs(reader->sampleRate - actualSampleRate) < 0.5 &&
            reader->lengthInSamples == expectedSamples;
    }

    std::mutex controlMutex;
    juce::File file;
    std::unique_ptr<juce::TimeSliceThread> writerThread;
    std::unique_ptr<juce::AudioFormatWriter::ThreadedWriter> threadedWriter;
    std::atomic<juce::AudioFormatWriter::ThreadedWriter *> activeWriter{nullptr};
    std::atomic<bool> admissionOpen{false};
    std::atomic<int> inFlightCallbacks{0};
    std::atomic<bool> drainRequested{false};
    juce::WaitableEvent callbacksDrained;
    std::atomic<std::int64_t> attemptedSamples{0};
    std::atomic<std::int64_t> acceptedSamples{0};
    std::atomic<std::int64_t> droppedSamples{0};
    std::atomic<std::int64_t> invalidBlockCount{0};
    mutable std::atomic<float> blockPeak{0.0f};
    double actualSampleRate = 0.0;
    int captureChannelCount = 0;
    int captureChannelOffset = 0;
    bool captureSessionPresent = false;
    StopResult lastStopResult;
};
