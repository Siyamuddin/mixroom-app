#include "../../ios/Classes/JuceEngine.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace
{
constexpr double kSampleRate = 48000.0;
constexpr int kBlockSize = 257;
constexpr float kTolerance = 1.0e-7f;

struct MeterState
{
    std::atomic<float> peakL{0.0f};
    std::atomic<float> peakR{0.0f};
    std::atomic<float> rmsL{0.0f};
    std::atomic<float> rmsR{0.0f};
};

struct Settings
{
    float gainUi = SimpleGainProcessor::kUiUnity;
    bool muted = false;
    float pan = 0.0f;
    bool meterEnabled = true;
    std::vector<AutomationPoint> volumeAutomation;
};

void require(bool condition, const std::string &message)
{
    if (!condition)
        throw std::runtime_error(message);
}

void configure(VolumeAutomationProcessor &automation,
               SimpleGainProcessor &gain,
               StereoPanProcessor &pan,
               std::atomic<double> &blockStartSeconds,
               const Settings &settings)
{
    automation.setBlockTransportPtr(&blockStartSeconds);
    automation.setAutomationPoints(settings.volumeAutomation);
    gain.gain->setValueNotifyingHost(
        juce::jlimit(0.0f, 1.0f, settings.gainUi / SimpleGainProcessor::kUiMax));
    gain.setMuted(settings.muted);
    pan.pan->setValueNotifyingHost(
        juce::jlimit(0.0f, 1.0f, (settings.pan + 1.0f) * 0.5f));
}

juce::AudioBuffer<float> makeInput(int shape, int blockIndex)
{
    juce::AudioBuffer<float> buffer(2, kBlockSize);
    buffer.clear();
    for (int sample = 0; sample < kBlockSize; ++sample)
    {
        const int absolute = blockIndex * kBlockSize + sample;
        if (shape == 1 && absolute == 0)
        {
            buffer.setSample(0, sample, 1.0f);
            buffer.setSample(1, sample, -0.5f);
        }
        else if (shape == 2)
        {
            buffer.setSample(0, sample, 0.6f);
            buffer.setSample(1, sample, -0.2f);
        }
        else if (shape == 3)
        {
            const auto left = float(((absolute * 37 + 11) % 997) - 498) / 512.0f;
            const auto right = float(((absolute * 53 + 29) % 991) - 495) / 512.0f;
            buffer.setSample(0, sample, left);
            buffer.setSample(1, sample, right);
        }
    }
    return buffer;
}

float maximumDifference(const juce::AudioBuffer<float> &left,
                        const juce::AudioBuffer<float> &right)
{
    float maximum = 0.0f;
    for (int channel = 0; channel < left.getNumChannels(); ++channel)
        for (int sample = 0; sample < left.getNumSamples(); ++sample)
            maximum = std::max(
                maximum,
                std::abs(left.getSample(channel, sample) -
                         right.getSample(channel, sample)));
    return maximum;
}

void compareMeters(const MeterState &legacy,
                   const MeterState &candidate,
                   const std::string &label)
{
    const std::array<std::pair<float, float>, 4> values{{
        {legacy.peakL.load(), candidate.peakL.load()},
        {legacy.peakR.load(), candidate.peakR.load()},
        {legacy.rmsL.load(), candidate.rmsL.load()},
        {legacy.rmsR.load(), candidate.rmsR.load()},
    }};
    for (const auto &[expected, actual] : values)
        require(std::abs(expected - actual) <= kTolerance,
                label + ": meter mismatch");
}

void runScenario(const std::string &label, const Settings &settings)
{
    auto legacyMeter = std::make_shared<MeterState>();
    auto candidateMeter = std::make_shared<MeterState>();
    std::atomic<bool> meterEnabled{settings.meterEnabled};
    std::atomic<double> legacyStart{0.0};
    std::atomic<double> candidateStart{0.0};

    VolumeAutomationProcessor legacyAutomation;
    SimpleGainProcessor legacyGain;
    StereoPanProcessor legacyPan;
    MeterTapProcessor legacyMeterTap(legacyMeter, &meterEnabled);
    RowPostProcessor candidate(candidateMeter, &meterEnabled);

    configure(legacyAutomation, legacyGain, legacyPan, legacyStart, settings);
    configure(candidate.automationProcessor(),
              candidate.gainProcessor(),
              candidate.panProcessor(),
              candidateStart,
              settings);

    legacyAutomation.prepareToPlay(kSampleRate, kBlockSize);
    legacyGain.prepareToPlay(kSampleRate, kBlockSize);
    legacyPan.prepareToPlay(kSampleRate, kBlockSize);
    legacyMeterTap.prepareToPlay(kSampleRate, kBlockSize);
    candidate.prepareToPlay(kSampleRate, kBlockSize);

    for (int shape = 0; shape < 4; ++shape)
    {
        legacyAutomation.reset();
        legacyGain.reset();
        legacyPan.reset();
        legacyMeterTap.reset();
        candidate.reset();
        legacyMeter->peakL = legacyMeter->peakR = 0.0f;
        legacyMeter->rmsL = legacyMeter->rmsR = 0.0f;
        candidateMeter->peakL = candidateMeter->peakR = 0.0f;
        candidateMeter->rmsL = candidateMeter->rmsR = 0.0f;

        for (int block = 0; block < 5; ++block)
        {
            auto legacyBuffer = makeInput(shape, block);
            auto candidateBuffer = makeInput(shape, block);
            const double blockStart = double(block * kBlockSize) / kSampleRate;
            legacyStart.store(blockStart);
            candidateStart.store(blockStart);
            juce::MidiBuffer legacyMidi;
            juce::MidiBuffer candidateMidi;

            legacyAutomation.processBlock(legacyBuffer, legacyMidi);
            legacyGain.processBlock(legacyBuffer, legacyMidi);
            legacyPan.processBlock(legacyBuffer, legacyMidi);
            legacyMeterTap.processBlock(legacyBuffer, legacyMidi);
            candidate.processBlock(candidateBuffer, candidateMidi);

            const float difference = maximumDifference(legacyBuffer, candidateBuffer);
            require(difference <= kTolerance,
                    label + ": audio mismatch for shape " +
                        std::to_string(shape) + ", block " +
                        std::to_string(block) + ", max difference " +
                        std::to_string(difference));
            compareMeters(*legacyMeter, *candidateMeter, label);
        }
    }

    legacyAutomation.releaseResources();
    legacyGain.releaseResources();
    legacyPan.releaseResources();
    legacyMeterTap.releaseResources();
    candidate.releaseResources();
}
} // namespace

int main()
{
    try
    {
        runScenario("unity", {});
        runScenario("minimum-gain", {.gainUi = SimpleGainProcessor::kUiMin});
        runScenario("maximum-gain", {.gainUi = SimpleGainProcessor::kUiMax});
        runScenario("gain", {.gainUi = 1.35f});
        runScenario("mute", {.muted = true});
        runScenario("left-pan", {.pan = -1.0f});
        runScenario("right-pan", {.pan = 1.0f});
        runScenario("meter-disabled", {.meterEnabled = false});
        runScenario("combined", {
                                    .gainUi = 2.7f,
                                    .pan = 0.35f,
                                    .volumeAutomation = {
                                        {0.0, 0.1f},
                                        {7.5, 0.75f},
                                        {18.0, 1.0f},
                                    },
                                });
        std::cout << "PASS: legacy row post chain and RowPostProcessor are "
                     "sample- and meter-equivalent\n";
        return 0;
    }
    catch (const std::exception &error)
    {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
}
