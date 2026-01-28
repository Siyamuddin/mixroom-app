#pragma once
#include <juce_audio_processors/juce_audio_processors.h>

#include "JuceLogBridge.h" // Bring in the function

extern "C" void juceLogToFlutter(const char *msg);

class SimpleGainProcessor : public juce::AudioProcessor
{
public:
    SimpleGainProcessor()
        : juce::AudioProcessor(BusesProperties()
                                   .withInput("Input", juce::AudioChannelSet::stereo(), true)
                                   .withOutput("Output", juce::AudioChannelSet::stereo(), true))
    {
        addParameter(gain = new juce::AudioParameterFloat("volume", "Volume", 0.0f, 3.0f, 1.0f));
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
        float userGain = gain->get(); // value from 0.0 → 3.0
        // juceLogToFlutter(("Gain value: " + juce::String(userGain)).toRawUTF8());
        float perceptualGain = juce::jmin(userGain * userGain, 9.0f); // Apply loudness curve and clamp

        buffer.applyGain(perceptualGain);
    }

    // Metadata
    const juce::String getName() const override { return "SimpleGain"; }
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
};
