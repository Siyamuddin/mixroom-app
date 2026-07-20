#pragma once
#include <juce_audio_processors/juce_audio_processors.h>
#include <atomic>
#include <cmath>

#include "JuceLogBridge.h" // Bring in the function

extern "C" void juceLogToFlutter(const char *msg);

class SimpleGainProcessor : public juce::AudioProcessor
{
public:
    static constexpr float kUiMin = 0.0f;
    static constexpr float kUiMax = 3.0f;
    static constexpr float kDbMin = -60.0f;
    static constexpr float kDbMax = 6.0f;
    static constexpr float kUiUnity = 2.0f;

    SimpleGainProcessor()
        : juce::AudioProcessor(BusesProperties()
                                   .withInput("Input", juce::AudioChannelSet::stereo(), true)
                                   .withOutput("Output", juce::AudioChannelSet::stereo(), true))
    {
        addParameter(gain = new juce::AudioParameterFloat(
                         "volume", "Volume", kUiMin, kUiMax, kUiUnity));
    }

    void setMuted(bool m) { muted.store(m, std::memory_order_relaxed); }
    bool isMuted() const { return muted.load(std::memory_order_relaxed); }
    void setAutomationGainUiRealtime(float userGain) noexcept
    {
        automationGainUi.store(juce::jlimit(kUiMin, kUiMax, userGain),
                               std::memory_order_relaxed);
        automationGainOverrideActive.store(true, std::memory_order_release);
    }
    void clearAutomationGainOverride() noexcept
    {
        automationGainOverrideActive.store(false, std::memory_order_release);
    }

    // Lifecycle
    void prepareToPlay(double sampleRate, int samplesPerBlock) override {}
    void releaseResources() override {}

    // Processing
    // void processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer&) override
    // {
    //     buffer.applyGain(gain->get());
    // }

    void processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &) override
    {
        const bool useAutomationGain =
            automationGainOverrideActive.load(std::memory_order_acquire);
        const float userGain = juce::jlimit(
            kUiMin,
            kUiMax,
            useAutomationGain ? automationGainUi.load(std::memory_order_relaxed)
                              : gain->get());
        float db = 0.0f;

        if (userGain <= kUiUnity)
        {
            const float t = (kUiUnity <= kUiMin)
                                ? 0.0f
                                : (userGain - kUiMin) / (kUiUnity - kUiMin);
            db = kDbMin + ((0.0f - kDbMin) * juce::jlimit(0.0f, 1.0f, t));
        }
        else
        {
            const float t = (kUiMax <= kUiUnity)
                                ? 0.0f
                                : (userGain - kUiUnity) / (kUiMax - kUiUnity);
            db = 0.0f + ((kDbMax - 0.0f) * juce::jlimit(0.0f, 1.0f, t));
        }

        const float linearGain = (db <= kDbMin + 0.001f)
                                     ? 0.0f
                                     : std::pow(10.0f, db / 20.0f);

        if (muted.load(std::memory_order_relaxed))
        {
            buffer.applyGain(0.0f); // clean mute (no clicks)
        }
        else
        {
            buffer.applyGain(linearGain);
        }
    }

    // Metadata
    const juce::String getName() const override { return "Gain"; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }

    // Programs (Not used)
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}

    // State (optional for now)
    void getStateInformation(juce::MemoryBlock &) override {}
    void setStateInformation(const void *, int) override {}

    // GUI
    bool hasEditor() const override { return false; }
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }

    // Layout
    bool isBusesLayoutSupported(const BusesLayout &layout) const override
    {
        return layout.getMainInputChannels() == layout.getMainOutputChannels() && layout.getMainInputChannels() > 0;
    }

    juce::AudioParameterFloat *gain;

private:
    std::atomic<bool> muted{false};
    std::atomic<bool> automationGainOverrideActive{false};
    std::atomic<float> automationGainUi{kUiUnity};
};
