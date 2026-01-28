#pragma once

#include "JuceHeader.h"
#include "SimpleGainProcessor.h"
#include "NativeEffects.h"

#include "JuceLogBridge.h"
#include <jni.h>

extern "C" void juceLogToFlutter(const char *msg);

class FilePlayerProcessor : public juce::AudioProcessor
{
public:
    FilePlayerProcessor(std::unique_ptr<juce::AudioFormatReaderSource> src,
                        juce::int64 totalLengthInSamples,
                        const juce::File &file)
        : source(std::move(src)), totalLength(totalLengthInSamples), sourceFile(file)
    {
        if (source)
        {
            // grab the file's native sample rate
            fileSampleRate = source->getAudioFormatReader()->sampleRate;
            currentSampleRate = fileSampleRate;
            // ensure reader starts at zero
            source->setNextReadPosition(0);

            juceLogToFlutter(("audio sample rate is: " + juce::String(fileSampleRate)).toRawUTF8());
        }
        else
        {
            fileSampleRate = 44100.0;
            currentSampleRate = 44100.0;
        }
    }

    FilePlayerProcessor(const juce::File &file)
        : sourceFile(file)
    {
        juce::AudioFormatManager formatManager;
        formatManager.registerBasicFormats();
        reader.reset(formatManager.createReaderFor(file));

        if (reader != nullptr)
        {
            source = std::make_unique<juce::AudioFormatReaderSource>(reader.get(), true);
            fileSampleRate = reader->sampleRate;
            totalLength = source->getTotalLength();
        }
        else
        {
            totalLength = 0;
            source = nullptr;
        }
    }

    void prepareToPlay(double sampleRate, int samplesPerBlockExpected) override
    {
        currentSampleRate = sampleRate;

        // 👇 Required to tell the host how many input/output channels this processor has
        int numOut = source->getAudioFormatReader()->numChannels;
        setPlayConfigDetails(0, numOut, sampleRate, samplesPerBlockExpected);

        source->prepareToPlay(samplesPerBlockExpected, sampleRate);
        source->setNextReadPosition(0);
    }

    void releaseResources() override
    {
        source->releaseResources();
    }

    void processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &) override
    {
        buffer.clear();
        if (source)
        {
            juce::AudioSourceChannelInfo info(&buffer, 0, buffer.getNumSamples());
            source->getNextAudioBlock(info); // Use source only
        }
    }

    // Seeking
    void setPosition(double seconds)
    {
        source->setNextReadPosition((juce::int64)(seconds * fileSampleRate));
    }

    // Position & duration
    double getCurrentPosition() const
    {
        return (double)source->getNextReadPosition() / fileSampleRate;
    }
    double getTotalLengthSeconds() const
    {
        return (double)totalLength / fileSampleRate;
    }

    double getSampleRate() const { return fileSampleRate; }
    const juce::File &getSourceFile() const { return sourceFile; }
    const juce::String getName() const override { return "FilePlayerProcessor"; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}

    void getStateInformation(juce::MemoryBlock &) override {}
    void setStateInformation(const void *, int) override {}

    juce::int64 getTotalLength() const { return totalLength; }

    bool isBusesLayoutSupported(const BusesLayout &) const override { return true; }
    bool hasEditor() const override { return false; }
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }

private:
    std::unique_ptr<juce::AudioFormatReaderSource> source;
    std::unique_ptr<juce::AudioFormatReader> reader;
    juce::File sourceFile;
    juce::int64 totalLength;
    double currentSampleRate = 44100.0;
    double fileSampleRate = 44100.0;
};

class JuceEngine
{
public:
    static JuceEngine &get();

    void initialiseEngine();
    void loadTrack(int idx, const juce::File &file);
    void removeTrack(int trackIndex);
    juce::StringArray getTrackEffects(int trackIndex);
    void removePluginEffect(int trackIdx, int effectIndex);
    void reorderPluginEffects(int trackIdx, int fromIndex, int toIndex);
    void setEffectParameter(int trackIndex,
                            int effectIndex,
                            const juce::String &paramID,
                            const juce::var &newValue);
    void setTrackVolume(int trackIdx, float volume);
    double getCurrentPosition(int trackIndex);
    double getTrackDuration(int trackIndex);
    juce::Array<juce::NamedValueSet> getPluginParameterInfo(int trackIndex, int effectIndex);
    juce::String exportMix(const juce::File &outFile);
    juce::String exportTrack(int trackIndex, const juce::File &outFile);
    void play();
    void pause();
    void seek(int trackIndex, double positionSeconds);
    void bypassPlugin(int trackIndex, int effectIndex, bool shouldBypass);
    bool getPluginBypassState(int trackIndex, int effectIndex);
    void bypassTrack(int trackIndex, bool shouldBypass);
    juce::Array<juce::PluginDescription> getKnownPlugins() const;
    // void insertPluginEffect(int trackIdx, const juce::String& pluginPath);
    void insertPluginEffect(int trackIdx, const juce::String &pluginPath, std::function<void(bool)> callback);
    void shutdownEngine();

    // special functions for "video audio" lane
    void loadVideoAudio(const juce::File &file);
    void unloadVideoAudio();
    void setVideoAudioGain(float gain);
    void seekVideoAudio(double seconds);

private:
    JuceEngine();
    ~JuceEngine();

    void rewireTrackChain(int trackIdx);

    bool engineInitialized = false;

    juce::AudioFormatManager formatManager;
    juce::AudioPluginFormatManager pluginFormatManager;
    juce::AudioProcessorGraph graph;
    juce::AudioProcessorGraph exportGraph;

    juce::AudioProcessorGraph::Node::Ptr outputNode;
    // juce::OwnedArray<juce::AudioProcessorGraph::Node> trackNodes;
    juce::Array<juce::AudioProcessorGraph::Node::Ptr> trackNodes;
    // juce::OwnedArray<juce::AudioProcessorGraph::Node> gainNodes;
    juce::Array<SimpleGainProcessor *> gainProcessors;
    // juce::OwnedArray<juce::Array<juce::AudioProcessorGraph::Node::Ptr>> trackEffectChains;
    juce::OwnedArray<juce::Array<juce::AudioProcessorGraph::NodeID>> trackEffectChains;

    // Playback-only "video audio" lane (excluded from exports)
    juce::AudioProcessorGraph::Node::Ptr videoAudioNode{nullptr};
    SimpleGainProcessor *videoGainProc{nullptr};
    bool hasVideoAudio{false};

    juce::KnownPluginList pluginList;

    std::vector<juce::String> getExposedParametersForPlugin(const juce::String &pluginId);

    juce::AudioDeviceManager deviceManager;
    juce::AudioProcessorPlayer audioPlayer;
};
