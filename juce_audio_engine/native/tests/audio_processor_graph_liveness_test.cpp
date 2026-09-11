#include <juce_audio_processors/juce_audio_processors.h>

#include <cmath>
#include <iostream>
#include <stdexcept>

namespace
{
void require (bool condition, const char* message)
{
    if (! condition)
        throw std::runtime_error (message);
}

class TestProcessor final : public juce::AudioProcessor
{
public:
    explicit TestProcessor (float scaleToUse = 1.0f,
                            int latency = 0,
                            bool acceptsMidiToUse = false,
                            bool producesMidiToUse = false)
        : AudioProcessor (BusesProperties()
                              .withInput ("Input", juce::AudioChannelSet::stereo(), true)
                              .withOutput ("Output", juce::AudioChannelSet::stereo(), true)),
          scale (scaleToUse),
          acceptsMidiValue (acceptsMidiToUse),
          producesMidiValue (producesMidiToUse)
    {
        setLatencySamples (latency);
    }

    const juce::String getName() const override { return "GraphLivenessTestProcessor"; }
    void prepareToPlay (double, int) override {}
    void releaseResources() override {}
    bool isBusesLayoutSupported (const BusesLayout& layouts) const override
    {
        return layouts.getMainInputChannelSet() == juce::AudioChannelSet::stereo()
            && layouts.getMainOutputChannelSet() == juce::AudioChannelSet::stereo();
    }
    void processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer&) override
    {
        buffer.applyGain (scale);
    }
    bool acceptsMidi() const override { return acceptsMidiValue; }
    bool producesMidi() const override { return producesMidiValue; }
    juce::AudioProcessorEditor* createEditor() override { return nullptr; }
    bool hasEditor() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram (int) override {}
    const juce::String getProgramName (int) override { return {}; }
    void changeProgramName (int, const juce::String&) override {}
    void getStateInformation (juce::MemoryBlock&) override {}
    void setStateInformation (const void*, int) override {}

private:
    float scale;
    bool acceptsMidiValue;
    bool producesMidiValue;
};

using Graph = juce::AudioProcessorGraph;

void configureGraph (Graph& graph, int blockSize = 128)
{
    graph.setPlayConfigDetails (2, 2, 48000.0, blockSize);
}

Graph::Node::Ptr addInput (Graph& graph)
{
    return graph.addNode (std::make_unique<Graph::AudioGraphIOProcessor> (
                              Graph::AudioGraphIOProcessor::audioInputNode),
                          std::nullopt,
                          Graph::UpdateKind::none);
}

Graph::Node::Ptr addOutput (Graph& graph)
{
    return graph.addNode (std::make_unique<Graph::AudioGraphIOProcessor> (
                              Graph::AudioGraphIOProcessor::audioOutputNode),
                          std::nullopt,
                          Graph::UpdateKind::none);
}

Graph::Node::Ptr addMidiInput (Graph& graph)
{
    return graph.addNode (std::make_unique<Graph::AudioGraphIOProcessor> (
                              Graph::AudioGraphIOProcessor::midiInputNode),
                          std::nullopt,
                          Graph::UpdateKind::none);
}

Graph::Node::Ptr addMidiOutput (Graph& graph)
{
    return graph.addNode (std::make_unique<Graph::AudioGraphIOProcessor> (
                              Graph::AudioGraphIOProcessor::midiOutputNode),
                          std::nullopt,
                          Graph::UpdateKind::none);
}

Graph::Node::Ptr addTestNode (Graph& graph, float scale = 1.0f, int latency = 0)
{
    return graph.addNode (std::make_unique<TestProcessor> (scale, latency),
                          std::nullopt,
                          Graph::UpdateKind::none);
}

Graph::Node::Ptr addMidiPassNode (Graph& graph)
{
    return graph.addNode (std::make_unique<TestProcessor> (1.0f, 0, true, true),
                          std::nullopt,
                          Graph::UpdateKind::none);
}

void connect (Graph& graph, Graph::Node::Ptr source, int sourceChannel,
              Graph::Node::Ptr destination, int destinationChannel)
{
    if (! graph.addConnection ({{ source->nodeID, sourceChannel },
                                { destination->nodeID, destinationChannel }},
                               Graph::UpdateKind::none))
    {
        throw std::runtime_error (
            "connection rejected: " + std::to_string (source->nodeID.uid)
            + ":" + std::to_string (sourceChannel)
            + " -> " + std::to_string (destination->nodeID.uid)
            + ":" + std::to_string (destinationChannel));
    }
}

juce::AudioBuffer<float> deterministicInput (int samples)
{
    juce::AudioBuffer<float> result (2, samples);
    for (int channel = 0; channel < result.getNumChannels(); ++channel)
        for (int sample = 0; sample < samples; ++sample)
            result.setSample (channel, sample,
                              static_cast<float> ((channel + 1) * 100 + sample) / 4096.0f);
    return result;
}

void prepareAndRender (Graph& graph, juce::AudioBuffer<float>& audio)
{
    graph.setPlayConfigDetails (2, 2, 48000.0, audio.getNumSamples());
    graph.prepareToPlay (48000.0, audio.getNumSamples());
    juce::MidiBuffer midi;
    graph.processBlock (audio, midi);
}

void testMidiFanOutAndFanIn()
{
    Graph graph;
    configureGraph (graph, 64);
    auto input = addMidiInput (graph);
    auto first = addMidiPassNode (graph);
    auto second = addMidiPassNode (graph);
    auto output = addMidiOutput (graph);

    connect (graph, input, Graph::midiChannelIndex, first, Graph::midiChannelIndex);
    connect (graph, input, Graph::midiChannelIndex, second, Graph::midiChannelIndex);
    connect (graph, first, Graph::midiChannelIndex, output, Graph::midiChannelIndex);
    connect (graph, second, Graph::midiChannelIndex, output, Graph::midiChannelIndex);

    graph.prepareToPlay (48000.0, 64);
    juce::AudioBuffer<float> audio (2, 64);
    audio.clear();
    juce::MidiBuffer midi;
    midi.addEvent (juce::MidiMessage::noteOn (1, 60, (juce::uint8) 96), 11);
    graph.processBlock (audio, midi);

    require (midi.getNumEvents() == 2, "MIDI fan-out/fan-in render changed");
    for (const auto metadata : midi)
    {
        require (metadata.samplePosition == 11, "MIDI timestamp changed");
        require (metadata.getMessage().isNoteOn(), "MIDI message type changed");
        require (metadata.getMessage().getNoteNumber() == 60, "MIDI note changed");
    }
}

void testFanOutAndFanIn()
{
    Graph graph;
    configureGraph (graph);
    auto input = addInput (graph);
    auto left = addTestNode (graph, 2.0f);
    auto right = addTestNode (graph, 3.0f);
    auto mixer = addTestNode (graph);
    auto output = addOutput (graph);

    for (int channel = 0; channel < 2; ++channel)
    {
        connect (graph, input, channel, left, channel);
        connect (graph, input, channel, right, channel);
        connect (graph, left, channel, mixer, channel);
        connect (graph, right, channel, mixer, channel);
        connect (graph, mixer, channel, output, channel);
    }

    auto audio = deterministicInput (128);
    juce::AudioBuffer<float> expected;
    expected.makeCopyOf (audio);
    expected.applyGain (5.0f);
    prepareAndRender (graph, audio);
    require (graph.getLatencySamples() == 0, "fan-in latency changed");
    for (int channel = 0; channel < 2; ++channel)
        for (int sample = 0; sample < audio.getNumSamples(); ++sample)
            require (std::abs (audio.getSample (channel, sample)
                               - expected.getSample (channel, sample)) <= 1.0e-7f,
                     "fan-out/fan-in render changed");
}

void testLatencyReporting()
{
    Graph graph;
    configureGraph (graph, 64);
    auto input = addInput (graph);
    auto first = addTestNode (graph, 1.0f, 7);
    auto second = addTestNode (graph, 1.0f, 11);
    auto output = addOutput (graph);

    for (int channel = 0; channel < 2; ++channel)
    {
        connect (graph, input, channel, first, channel);
        connect (graph, first, channel, second, channel);
        connect (graph, second, channel, output, channel);
    }

    auto audio = deterministicInput (64);
    prepareAndRender (graph, audio);
    require (graph.getLatencySamples() == 18, "serial latency changed");
}

void testSameNodeMultiChannelUse()
{
    Graph graph;
    configureGraph (graph, 64);
    auto input = addInput (graph);
    auto processor = addTestNode (graph);
    auto output = addOutput (graph);

    connect (graph, input, 0, processor, 0);
    connect (graph, input, 0, processor, 1);
    connect (graph, processor, 0, output, 0);
    connect (graph, processor, 1, output, 1);

    auto audio = deterministicInput (64);
    const auto expected = audio.getSample (0, 17);
    prepareAndRender (graph, audio);
    require (std::abs (audio.getSample (0, 17) - expected) <= 1.0e-7f,
             "primary channel changed");
    require (std::abs (audio.getSample (1, 17) - expected) <= 1.0e-7f,
             "same-node secondary channel changed");
}

void testDisconnectedAndFeedbackGraphs()
{
    {
        Graph graph;
        configureGraph (graph, 32);
        addTestNode (graph);
        auto audio = deterministicInput (32);
        prepareAndRender (graph, audio);
    }

    {
        Graph graph;
        configureGraph (graph, 32);
        auto first = addTestNode (graph);
        auto second = addTestNode (graph);
        connect (graph, first, 0, second, 0);
        connect (graph, second, 0, first, 0);
        auto audio = deterministicInput (32);
        prepareAndRender (graph, audio);
    }
}
}

int main()
{
    try
    {
        juce::ScopedJuceInitialiser_GUI initialise;
        testFanOutAndFanIn();
        testMidiFanOutAndFanIn();
        testLatencyReporting();
        testSameNodeMultiChannelUse();
        testDisconnectedAndFeedbackGraphs();
        std::cout << "PASS: graph liveness audio/MIDI fan-out, fan-in, channels, latency, disconnected, feedback\n";
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
}
