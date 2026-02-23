#include "NativeEffects.h"

// ****REVERB****

ReverbAudioProcessor::ReverbAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
#if !JucePlugin_IsMidiEffect
#if !JucePlugin_IsSynth
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
#endif
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)
#endif
                         ),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("roomSize",
                                                                                 "Room Size", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 50.0f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("damping",
                                                                                 "Damping", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 50.0f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("mix",
                                                                                 "Mix", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 20.0f, "%"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("predelay",
                                                                                 "Predelay", juce::NormalisableRange<float>(0.0f, 200.0f, 1.0f), 0.0f, "ms"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("modRate",
                                                                                 "Mod Rate", juce::NormalisableRange<float>(0.0f, 10.0f, 0.1f), 1.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("modDepth",
                                                                                 "Mod Depth", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 0.0f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("hpfFreq",
                                                                                 "HPF Frequency", juce::NormalisableRange<float>(20.0f, 2000.0f, 1.0f, 0.35f), 20.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("lpfFreq",
                                                                                 "LPF Frequency", juce::NormalisableRange<float>(500.0f, 20000.0f, 1.0f, 0.35f), 20000.0f, "Hz"));
    parameters.state = juce::ValueTree("savedParams");
}

void ReverbAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    reverb.prepare(sampleRate, samplesPerBlock);
    reverb.setParameters(parameters);
}

void ReverbAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;
    for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
        buffer.clear(i, 0, buffer.getNumSamples());

    reverb.setParameters(parameters);
    reverb.process(buffer);
}

void ReverbAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    // create xml with state information
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    // save xml to binary
    copyXmlToBinary(*outputXml, destData);
}

void ReverbAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    // create xml from binary
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    // check that inputXml returned correctly
    if (inputXml != nullptr)
    {
        // if inputXml tag name matches tree state tag name
        if (inputXml->hasTagName(parameters.state.getType()))
        {
            // copy xml into tree state
            parameters.state = juce::ValueTree::fromXml(*inputXml);
        }
    }
}

//==============================================================================
//==============================================================================
//==============================================================================

bool ReverbAudioProcessor::acceptsMidi() const
{
#if JucePlugin_WantsMidiInput
    return true;
#else
    return false;
#endif
}

bool ReverbAudioProcessor::producesMidi() const
{
#if JucePlugin_ProducesMidiOutput
    return true;
#else
    return false;
#endif
}

bool ReverbAudioProcessor::isMidiEffect() const
{
#if JucePlugin_IsMidiEffect
    return true;
#else
    return false;
#endif
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool ReverbAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// ****EQ****

EQAudioProcessor::EQAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
#if !JucePlugin_IsMidiEffect
#if !JucePlugin_IsSynth
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
#endif
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)
#endif
                         ),
      parameters(*this, nullptr)
#endif
{
    // create parameters for the highpass filter
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("hpfFreq",
                                                                                 "HPF Frequency", juce::NormalisableRange<float>(20.0f, 20000.0f, 1.0f, 0.25f), 20.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterChoice>("hpfSlope",
                                                                                  "HPF Slope", filterSlopes, 0));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterBool>("hpfBypass",
                                                                                "HPF Bypass", false));
    // create parameters for the lowpass filter
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("lpfFreq",
                                                                                 "LPF Frequency", juce::NormalisableRange<float>(20.0f, 20000.0f, 1.0f, 0.25f), 20000.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterChoice>("lpfSlope",
                                                                                  "LPF Slope", filterSlopes, 0));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterBool>("lpfBypass",
                                                                                "LPF Bypass", false));
    // create parameters for peak bands
    for (int band = 1; band <= numBands; band++)
    {
        parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>(
            "band" + juce::String(band) + "Freq", "Band " + juce::String(band) + " Frequency",
            juce::NormalisableRange<float>(20.0f, 20000.0f, 1.0f, 0.25f), defaultFreq[band - 1], "Hz"));
        parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>(
            "band" + juce::String(band) + "Gain", "Band " + juce::String(band) + " Gain",
            juce::NormalisableRange<float>(-20.0f, 20.0f, 0.25f), 0.0f, "dB"));
        parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>(
            "band" + juce::String(band) + "Q", "Band " + juce::String(band) + " Q",
            juce::NormalisableRange<float>(0.1f, 10.0f, 0.1f, 0.4f), 1.0f, "Q"));
        // create shelf/bell switch for bands 1 and 4
        if (band == 1 || band == 4)
        {
            parameters.createAndAddParameter(std::make_unique<juce::AudioParameterBool>(
                "band" + juce::String(band) + "Bell", "Band " + juce::String(band) + " Bell", false));
        }
    }
    parameters.state = juce::ValueTree("savedParams");
}

void EQAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    equalizer.prepare(sampleRate, samplesPerBlock);
    equalizer.setParameters(parameters);
    waveformRing.fill(0.0f);
    waveformWritePos.store(0, std::memory_order_relaxed);
}

void EQAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;
    for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
        buffer.clear(i, 0, buffer.getNumSamples());

    equalizer.setParameters(parameters);
    equalizer.process(buffer);
    pushWaveformSamples(buffer);
}

void EQAudioProcessor::pushWaveformSamples(const juce::AudioBuffer<float> &buffer) noexcept
{
    const int numSamples = buffer.getNumSamples();
    const int channels = juce::jmin(buffer.getNumChannels(), 2);
    if (numSamples <= 0 || channels <= 0)
        return;

    const float *left = buffer.getReadPointer(0);
    const float *right = channels > 1 ? buffer.getReadPointer(1) : nullptr;

    int writePos = waveformWritePos.load(std::memory_order_relaxed);

    for (int i = 0; i < numSamples; ++i)
    {
        const float s = right != nullptr ? 0.5f * (left[i] + right[i]) : left[i];
        waveformRing[(size_t)writePos] = juce::jlimit(-1.0f, 1.0f, s);
        writePos = (writePos + 1) % kWaveformRingSize;
    }

    waveformWritePos.store(writePos, std::memory_order_release);
}

std::vector<float> EQAudioProcessor::getRecentWaveform(int sampleCount) const
{
    const int count = juce::jlimit(16, kWaveformRingSize, sampleCount);
    std::vector<float> out((size_t)count, 0.0f);

    const int writePos = waveformWritePos.load(std::memory_order_acquire);
    int readPos = writePos - count;
    while (readPos < 0)
        readPos += kWaveformRingSize;

    for (int i = 0; i < count; ++i)
    {
        out[(size_t)i] = waveformRing[(size_t)readPos];
        readPos = (readPos + 1) % kWaveformRingSize;
    }

    return out;
}

void EQAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    // create xml with state information
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    // save xml to binary
    copyXmlToBinary(*outputXml, destData);
}

void EQAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    // create xml from binary
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    // check that theParams returned correctly
    if (inputXml != nullptr)
    {
        // if theParams tag name matches tree state tag name
        if (inputXml->hasTagName(parameters.state.getType()))
        {
            // copy xml into tree state
            parameters.state = juce::ValueTree::fromXml(*inputXml);
        }
    }
}

//==============================================================================
//==============================================================================
//==============================================================================

bool EQAudioProcessor::acceptsMidi() const
{
#if JucePlugin_WantsMidiInput
    return true;
#else
    return false;
#endif
}

bool EQAudioProcessor::producesMidi() const
{
#if JucePlugin_ProducesMidiOutput
    return true;
#else
    return false;
#endif
}

bool EQAudioProcessor::isMidiEffect() const
{
#if JucePlugin_IsMidiEffect
    return true;
#else
    return false;
#endif
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool EQAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// ****DELAY****

DelayAudioProcessor::DelayAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
#if !JucePlugin_IsMidiEffect
#if !JucePlugin_IsSynth
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
#endif
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)
#endif
                         ),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("delayTime",
                                                                                 "Delay Time", juce::NormalisableRange<float>(1.0f, 2000.0f, 1.0f), 100.0f, "ms"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("feedback",
                                                                                 "Feedback", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 15.0f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("width",
                                                                                 "Width", juce::NormalisableRange<float>(0.0f, 10.0f, 1.0f), 0.0f, "ms"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("mix",
                                                                                 "Mix", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 13.0f, "%"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("modRate",
                                                                                 "Mod Rate", juce::NormalisableRange<float>(0.0f, 10.0f, 0.1f), 1.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("modDepth",
                                                                                 "Mod Depth", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 0.0f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("hpfFreq",
                                                                                 "HPF Frequency", juce::NormalisableRange<float>(20.0f, 2000.0f, 1.0f, 0.35f), 20.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("lpfFreq",
                                                                                 "LPF Frequency", juce::NormalisableRange<float>(500.0f, 20000.0f, 1.0f, 0.35f), 20000.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("drive",
                                                                                 "Drive", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 0.0f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterBool>("bpmSync",
                                                                                "BPM Sync", false));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterChoice>("subdivisionIndex",
                                                                                  "Subdivision", delaySubdivisions, 6));
    parameters.state = juce::ValueTree("savedParams");
}

void DelayAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    delay.prepare(sampleRate, samplesPerBlock);
    delay.setParameters(parameters, 120.0);
}

void DelayAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;
    for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
        buffer.clear(i, 0, buffer.getNumSamples());
    // get host bpm
    playHead = this->getPlayHead();
    if (playHead != nullptr)
    {
        playHead->getCurrentPosition(cpi);
    }
    const double bpm = cpi.bpm;
    // apply delay
    delay.setParameters(parameters, bpm);
    delay.process(buffer);
}

void DelayAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    // create xml with state information
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    // save xml to binary
    copyXmlToBinary(*outputXml, destData);
}

void DelayAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    // create xml from binary
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    // check that inputXml returned correctly
    if (inputXml != nullptr)
    {
        // if inputXml tag name matches tree state tag name
        if (inputXml->hasTagName(parameters.state.getType()))
        {
            // copy xml into tree state
            parameters.state = juce::ValueTree::fromXml(*inputXml);
        }
    }
}

//==============================================================================
//==============================================================================
//==============================================================================

bool DelayAudioProcessor::acceptsMidi() const
{
#if JucePlugin_WantsMidiInput
    return true;
#else
    return false;
#endif
}

bool DelayAudioProcessor::producesMidi() const
{
#if JucePlugin_ProducesMidiOutput
    return true;
#else
    return false;
#endif
}

bool DelayAudioProcessor::isMidiEffect() const
{
#if JucePlugin_IsMidiEffect
    return true;
#else
    return false;
#endif
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool DelayAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// ****DISTORTION****

DistortionAudioProcessor::DistortionAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
#if !JucePlugin_IsMidiEffect
#if !JucePlugin_IsSynth
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
#endif
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)
#endif
                         ),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("drive",
                                                                                 "Drive", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 0.0f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("volume",
                                                                                 "Volume", juce::NormalisableRange<float>(-20.0f, 20.0f, 0.5f), 0.0f, "dB"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("mix",
                                                                                 "Mix", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 100.0f, "%"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("anger",
                                                                                 "Anger", juce::NormalisableRange<float>(0.0f, 1.0f, 0.1f), 0.5f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("offset",
                                                                                 "DC Offset", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 0.0f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("hpf",
                                                                                 "HPF Frequency", juce::NormalisableRange<float>(20.0f, 10000.0f, 1.0f, 0.25f), 20.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("lpf",
                                                                                 "LPF Frequency", juce::NormalisableRange<float>(200.0f, 20000.0f, 1.0f, 0.25f), 20000.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("shape",
                                                                                 "Pre Shape", juce::NormalisableRange<float>(-6.0f, 6.0f, 0.1f), 0.0f, "dB"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterBool>("shapeTilt",
                                                                                "Shape Tilt", true));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterChoice>("type",
                                                                                  "Distortion Type", distortionTypes, 0));
    parameters.state = juce::ValueTree("savedParams");
}

void DistortionAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    distortion.prepare(sampleRate, samplesPerBlock);
    distortion.setParameters(parameters);
    setLatencySamples(distortion.getOversamplerLatency());
}

void DistortionAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;
    for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
        buffer.clear(i, 0, buffer.getNumSamples());

    juce::dsp::AudioBlock<float> block(buffer);
    juce::dsp::ProcessContextReplacing<float> context(block);
    distortion.setParameters(parameters);
    distortion.process(context);
}

void DistortionAudioProcessor::processBlockBypassed(juce::AudioBuffer<float> &buffer,
                                                    juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    // Make sure output bus extras are cleared (standard JUCE pattern)
    for (auto ch = getTotalNumInputChannels(); ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    // IMPORTANT: drop any residual/latency state so no stale samples leak
    distortion.reset();

    // Leave buffer contents untouched = dry signal passes through
}

void DistortionAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    // create xml with state information
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    // save xml to binary
    copyXmlToBinary(*outputXml, destData);
}

void DistortionAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    // create xml from binary
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    // check that inputXml returned correctly
    if (inputXml != nullptr)
    {
        // if inputXml tag name matches tree state tag name
        if (inputXml->hasTagName(parameters.state.getType()))
        {
            // copy xml into tree state
            parameters.state = juce::ValueTree::fromXml(*inputXml);
        }
    }
}

//==============================================================================
//==============================================================================
//==============================================================================

bool DistortionAudioProcessor::acceptsMidi() const
{
#if JucePlugin_WantsMidiInput
    return true;
#else
    return false;
#endif
}

bool DistortionAudioProcessor::producesMidi() const
{
#if JucePlugin_ProducesMidiOutput
    return true;
#else
    return false;
#endif
}

bool DistortionAudioProcessor::isMidiEffect() const
{
#if JucePlugin_IsMidiEffect
    return true;
#else
    return false;
#endif
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool DistortionAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// ****DE-ESSER****

DeesserAudioProcessor::DeesserAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
#if !JucePlugin_IsMidiEffect
#if !JucePlugin_IsSynth
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
#endif
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)
#endif
                         ),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("threshold",
                                                                                 "Threshold", juce::NormalisableRange<float>(-40.0f, 0.0f, 0.5f), 0.0f, "dB"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("crossoverFreq",
                                                                                 "Frequency", juce::NormalisableRange<float>(200.0f, 15000.0f, 1.0f, 0.25f), 4000.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("attack",
                                                                                 "Attack", juce::NormalisableRange<float>(0.1f, 50.0f, 0.1f, 0.35f), 0.1f, "ms"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("release",
                                                                                 "Release", juce::NormalisableRange<float>(5.0f, 100.0f, 0.1f, 0.35f), 10.0f, "ms"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterBool>("stereo", "Stereo", true));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterBool>("wide", "Wide Band", false));
    parameters.state = juce::ValueTree("savedParams");
}

void DeesserAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    deesser.prepare(sampleRate, samplesPerBlock);
    deesser.setParameters(parameters, listen);
}

void DeesserAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;
    for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
        buffer.clear(i, 0, buffer.getNumSamples());

    deesser.setParameters(parameters, listen);
    deesser.process(buffer);
    gainReduction = deesser.getGainReduction();
}

void DeesserAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    // create xml with state information
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    // save xml to binary
    copyXmlToBinary(*outputXml, destData);
}

void DeesserAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    // create xml from binary
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    // check that inputXml returned correctly
    if (inputXml != nullptr)
    {
        // if inputXml tag name matches tree state tag name
        if (inputXml->hasTagName(parameters.state.getType()))
        {
            // copy xml into tree state
            parameters.state = juce::ValueTree::fromXml(*inputXml);
        }
    }
}

//==============================================================================
//==============================================================================
//==============================================================================

bool DeesserAudioProcessor::acceptsMidi() const
{
#if JucePlugin_WantsMidiInput
    return true;
#else
    return false;
#endif
}

bool DeesserAudioProcessor::producesMidi() const
{
#if JucePlugin_ProducesMidiOutput
    return true;
#else
    return false;
#endif
}

bool DeesserAudioProcessor::isMidiEffect() const
{
#if JucePlugin_IsMidiEffect
    return true;
#else
    return false;
#endif
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool DeesserAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// =====================
// **** EQ 3-BAND ****
// =====================

EQ3AudioProcessor::EQ3AudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
#if !JucePlugin_IsMidiEffect
#if !JucePlugin_IsSynth
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
#endif
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)
#endif
                         ),
      parameters(*this, nullptr)
#endif
{
    // Expose ONLY 3 gain parameters
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>(
        "lowGain", "Low Gain",
        juce::NormalisableRange<float>(-24.0f, 24.0f, 0.25f),
        0.0f, "dB"));

    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>(
        "midGain", "Mid Gain",
        juce::NormalisableRange<float>(-24.0f, 24.0f, 0.25f),
        0.0f, "dB"));

    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>(
        "highGain", "High Gain",
        juce::NormalisableRange<float>(-24.0f, 24.0f, 0.25f),
        0.0f, "dB"));

    parameters.state = juce::ValueTree("savedParams");
}

void EQ3AudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    eq3.prepare(sampleRate, samplesPerBlock);
    eq3.setParameters(parameters);
    waveformRing.fill(0.0f);
    waveformWritePos.store(0, std::memory_order_relaxed);
}

void EQ3AudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (auto ch = getTotalNumInputChannels(); ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    eq3.setParameters(parameters);
    eq3.process(buffer);
    pushWaveformSamples(buffer);
}

void EQ3AudioProcessor::pushWaveformSamples(const juce::AudioBuffer<float> &buffer) noexcept
{
    const int numSamples = buffer.getNumSamples();
    const int channels = juce::jmin(buffer.getNumChannels(), 2);
    if (numSamples <= 0 || channels <= 0)
        return;

    const float *left = buffer.getReadPointer(0);
    const float *right = channels > 1 ? buffer.getReadPointer(1) : nullptr;

    int writePos = waveformWritePos.load(std::memory_order_relaxed);
    for (int i = 0; i < numSamples; ++i)
    {
        const float s = right != nullptr ? 0.5f * (left[i] + right[i]) : left[i];
        waveformRing[(size_t)writePos] = juce::jlimit(-1.0f, 1.0f, s);
        writePos = (writePos + 1) % kWaveformRingSize;
    }
    waveformWritePos.store(writePos, std::memory_order_release);
}

std::vector<float> EQ3AudioProcessor::getRecentWaveform(int sampleCount) const
{
    const int count = juce::jlimit(16, kWaveformRingSize, sampleCount);
    std::vector<float> out((size_t)count, 0.0f);

    const int writePos = waveformWritePos.load(std::memory_order_acquire);
    int readPos = writePos - count;
    while (readPos < 0)
        readPos += kWaveformRingSize;

    for (int i = 0; i < count; ++i)
    {
        out[(size_t)i] = waveformRing[(size_t)readPos];
        readPos = (readPos + 1) % kWaveformRingSize;
    }
    return out;
}

void EQ3AudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> xml(parameters.state.createXml());
    copyXmlToBinary(*xml, destData);
}

void EQ3AudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> xml(getXmlFromBinary(data, sizeInBytes));
    if (xml != nullptr && xml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*xml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool EQ3AudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;

#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// =====================
// **** COMPRESSOR ****
// =====================

CompressorAudioProcessor::CompressorAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "threshold", "Threshold",
            juce::NormalisableRange<float>(-50.0f, 0.0f, 0.1f), -12.0f, "dB"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "attack", "Attack",
            juce::NormalisableRange<float>(0.5f, 100.0f, 0.1f), 10.0f, "ms"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "release", "Release",
            juce::NormalisableRange<float>(5.0f, 1000.0f, 1.0f), 80.0f, "ms"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "ratio", "Ratio",
            juce::NormalisableRange<float>(1.0f, 20.0f, 0.1f), 4.0f));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "makeUp", "Makeup",
            juce::NormalisableRange<float>(-10.0f, 20.0f, 0.1f), 0.0f, "dB"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "scFreq", "Sidechain HPF",
            juce::NormalisableRange<float>(20.0f, 2000.0f, 1.0f), 100.0f, "Hz"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterBool>(
            "scBypass", "SC Bypass", true));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterBool>(
            "stereo", "Stereo", true));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "mix", "Mix",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 100.0f, "%"));

    parameters.state = juce::ValueTree("savedParams");
}

void CompressorAudioProcessor::prepareToPlay(double sr, int bs)
{
    compressor.prepare(sr, bs);
    compressor.setParameters(parameters);
}

void CompressorAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    const int numCh = buffer.getNumChannels();
    const int n = buffer.getNumSamples();

    // ===== IN RMS (stereo) =====
    if (numCh >= 2 && n > 0)
    {
        const float *L = buffer.getReadPointer(0);
        const float *R = buffer.getReadPointer(1);

        double ssL = 0.0, ssR = 0.0;
        for (int i = 0; i < n; ++i)
        {
            const double l = (double)L[i];
            const double r = (double)R[i];
            ssL += l * l;
            ssR += r * r;
        }

        const float rmL = (float)std::sqrt(ssL / (double)n);
        const float rmR = (float)std::sqrt(ssR / (double)n);

        // smoothing (VU-ish)
        constexpr float alpha = 0.12f;
        auto smooth = [](float prev, float next)
        { return prev + alpha * (next - prev); };

        inRmsL.store(smooth(inRmsL.load(std::memory_order_relaxed), rmL), std::memory_order_relaxed);
        inRmsR.store(smooth(inRmsR.load(std::memory_order_relaxed), rmR), std::memory_order_relaxed);
    }

    // ===== PROCESS =====
    compressor.setParameters(parameters);
    compressor.process(buffer);

    // ===== GR =====
    gainReduction = compressor.getGainReduction(); // keep your existing variable if you want
    const float gr = juce::jmax(gainReduction[0], gainReduction[1]);
    grDb.store(gr, std::memory_order_relaxed); // max between L/R, rather than an average

    // ===== OUT RMS (stereo) =====
    if (numCh >= 2 && n > 0)
    {
        const float *L = buffer.getReadPointer(0);
        const float *R = buffer.getReadPointer(1);

        double ssL = 0.0, ssR = 0.0;
        for (int i = 0; i < n; ++i)
        {
            const double l = (double)L[i];
            const double r = (double)R[i];
            ssL += l * l;
            ssR += r * r;
        }

        const float rmL = (float)std::sqrt(ssL / (double)n);
        const float rmR = (float)std::sqrt(ssR / (double)n);

        constexpr float alpha = 0.12f;
        auto smooth = [](float prev, float next)
        { return prev + alpha * (next - prev); };

        outRmsL.store(smooth(outRmsL.load(std::memory_order_relaxed), rmL), std::memory_order_relaxed);
        outRmsR.store(smooth(outRmsR.load(std::memory_order_relaxed), rmR), std::memory_order_relaxed);
    }
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool CompressorAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// =====================
// **** LIMITER ****
// =====================

LimiterAudioProcessor::LimiterAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "threshold", "Threshold",
            juce::NormalisableRange<float>(-40.0f, 0.0f, 0.1f),
            0.0f, "dB"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "release", "Release",
            juce::NormalisableRange<float>(0.1f, 200.0f, 0.1f, 0.35f),
            1.0f, "ms"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "ceiling", "Ceiling",
            juce::NormalisableRange<float>(-40.0f, 0.0f, 0.1f),
            0.0f, "dB"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterBool>(
            "stereo", "Stereo", true));

    parameters.state = juce::ValueTree("savedParams");
}

void LimiterAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    limiter.prepare(sampleRate, samplesPerBlock);
    limiter.setParameters(parameters);
}

void LimiterAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    limiter.setParameters(parameters);
    limiter.process(buffer);
    gainReduction = limiter.getGainReduction();
}

void LimiterAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    copyXmlToBinary(*outputXml, destData);
}

void LimiterAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    if (inputXml != nullptr && inputXml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*inputXml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool LimiterAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// =====================
// **** CLIPPER ****
// =====================

ClipperAudioProcessor::ClipperAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "threshold", "Threshold",
            juce::NormalisableRange<float>(-40.0f, 0.0f, 0.1f),
            0.0f, "dB"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "ceiling", "Ceiling",
            juce::NormalisableRange<float>(-40.0f, 0.0f, 0.1f),
            0.0f, "dB"));

    parameters.state = juce::ValueTree("savedParams");
}

void ClipperAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    clipper.prepare(sampleRate, samplesPerBlock);
    clipper.setParameters(parameters);
    setLatencySamples(clipper.getOversamplerLatency());
}

void ClipperAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    clipper.setParameters(parameters);
    juce::dsp::AudioBlock<float> block(buffer);
    juce::dsp::ProcessContextReplacing<float> ctx(block);
    clipper.process(ctx);
    gainReduction = clipper.getGainReduction();
}

void ClipperAudioProcessor::processBlockBypassed(juce::AudioBuffer<float> &buffer,
                                                 juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    // Latency-reporting processors must override bypass processing.
    clipper.reset();
}

void ClipperAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    copyXmlToBinary(*outputXml, destData);
}

void ClipperAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    if (inputXml != nullptr && inputXml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*inputXml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool ClipperAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// =====================
// **** PITCH SHIFT ****
// =====================

PitchShiftAudioProcessor::PitchShiftAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "semitones", "Semitones",
            juce::NormalisableRange<float>(-12.0f, 12.0f, 0.1f),
            0.0f, "st"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "mix", "Mix",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            100.0f, "%"));

    parameters.state = juce::ValueTree("savedParams");
}

void PitchShiftAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    pitchShift.prepare(sampleRate, samplesPerBlock);
    pitchShift.setParameters(parameters);
}

void PitchShiftAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    pitchShift.setParameters(parameters);
    pitchShift.process(buffer);
}

void PitchShiftAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    copyXmlToBinary(*outputXml, destData);
}

void PitchShiftAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    if (inputXml != nullptr && inputXml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*inputXml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool PitchShiftAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// =================
// **** CHORUS ****
// =================

ChorusAudioProcessor::ChorusAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "rate", "Rate",
            juce::NormalisableRange<float>(0.05f, 8.0f, 0.01f),
            0.8f, "Hz"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "depth", "Depth",
            juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f),
            0.35f));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "centreDelay", "Centre Delay",
            juce::NormalisableRange<float>(1.0f, 30.0f, 0.1f),
            7.0f, "ms"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "feedback", "Feedback",
            juce::NormalisableRange<float>(-95.0f, 95.0f, 0.1f),
            10.0f, "%"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "mix", "Mix",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            35.0f, "%"));

    parameters.state = juce::ValueTree("savedParams");
}

void ChorusAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    chorusFx.prepare(sampleRate, samplesPerBlock);
    chorusFx.setParameters(parameters);
}

void ChorusAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    chorusFx.setParameters(parameters);
    chorusFx.process(buffer);
}

void ChorusAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    copyXmlToBinary(*outputXml, destData);
}

void ChorusAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    if (inputXml != nullptr && inputXml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*inputXml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool ChorusAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// ==================
// **** VIBRATO ****
// ==================

VibratoAudioProcessor::VibratoAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "rate", "Rate",
            juce::NormalisableRange<float>(0.1f, 12.0f, 0.01f),
            4.5f, "Hz"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "depth", "Depth",
            juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f),
            0.6f));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "centreDelay", "Centre Delay",
            juce::NormalisableRange<float>(1.0f, 15.0f, 0.1f),
            7.0f, "ms"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "mix", "Mix",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            100.0f, "%"));

    parameters.state = juce::ValueTree("savedParams");
}

void VibratoAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    vibratoFx.prepare(sampleRate, samplesPerBlock);
    vibratoFx.setParameters(parameters);
}

void VibratoAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    vibratoFx.setParameters(parameters);
    vibratoFx.process(buffer);
}

void VibratoAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    copyXmlToBinary(*outputXml, destData);
}

void VibratoAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    if (inputXml != nullptr && inputXml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*inputXml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool VibratoAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif
