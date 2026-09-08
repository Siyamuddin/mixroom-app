#include <juce_audio_formats/juce_audio_formats.h>
#include <juce_audio_processors/juce_audio_processors.h>
#include "../RealtimeWavCapture.h"
#include <iostream>
#include <stdexcept>

static void require(bool condition, const char* message)
{
    if (!condition) throw std::runtime_error(message);
}

// Host signal integration test for Android's existing callback fan-out:
// raw input feeds the actual WAV writer independently of the JUCE monitor graph.
// Device routing/JNI ownership is covered separately; this opens no hardware.
class MonitorGraph
{
public:
    explicit MonitorGraph(int channels, int blockFrames)
    {
        graph.setPlayConfigDetails(channels, 2, 48000, blockFrames);
        auto input = graph.addNode(std::make_unique<juce::AudioProcessorGraph::AudioGraphIOProcessor>(
            juce::AudioProcessorGraph::AudioGraphIOProcessor::audioInputNode));
        auto output = graph.addNode(std::make_unique<juce::AudioProcessorGraph::AudioGraphIOProcessor>(
            juce::AudioProcessorGraph::AudioGraphIOProcessor::audioOutputNode));
        for (int ch = 0; ch < channels; ++ch)
            require(graph.addConnection({{input->nodeID, ch}, {output->nodeID, ch}},
                juce::AudioProcessorGraph::UpdateKind::sync), "monitor connection");
        graph.prepareToPlay(48000, blockFrames);
    }
    void render(juce::AudioBuffer<float>& output)
    {
        juce::MidiBuffer midi;
        graph.processBlock(output, midi);
    }
    void disable()
    {
        for (const auto& connection : graph.getConnections())
            graph.removeConnection(connection, juce::AudioProcessorGraph::UpdateKind::sync);
    }
    int connections() const { return int(graph.getConnections().size()); }
private:
    juce::AudioProcessorGraph graph;
};

static void run(int channels, int blockFrames, const juce::File& directory)
{
    constexpr double rate = 48000;
    MonitorGraph monitor(channels, blockFrames);
    RealtimeWavCapture capture;
    juce::AudioBuffer<float> input(channels, blockFrames), output(2, blockFrames);
    int inputBlock = 0, outputBlock = 0;
    auto sample = [](int block, int channel, int frame) {
        return float(((block * 17 + frame * 3 + channel * 101) % 1000) - 500) / 1024.0f;
    };
    auto push = [&] {
        for (int ch = 0; ch < channels; ++ch)
            for (int n = 0; n < blockFrames; ++n)
                input.setSample(ch, n, sample(inputBlock, ch, n));
        if (capture.isActive())
            capture.capture(input.getArrayOfReadPointers(), channels, blockFrames);
        ++inputBlock;
    };
    auto read = [&] {
        output.clear();
        for (int ch = 0; ch < channels; ++ch)
            output.copyFrom(ch, 0, input, ch, 0, blockFrames);
        monitor.render(output);
        for (int ch = 0; ch < channels; ++ch)
            for (int n = 0; n < blockFrames; ++n)
                require(output.getSample(ch, n) == sample(outputBlock, ch, n), "monitor discontinuity");
        if (channels == 1)
            require(output.getMagnitude(1, 0, blockFrames) == 0, "unused channel not silent");
        ++outputBlock;
    };
    push(); read();
    for (int n = 0; n < 10; ++n) { push(); read(); }
    for (int take = 0; take < 3; ++take)
    {
        auto file = directory.getNonexistentChildFile("pro72-monitor-test", ".wav");
        const int captureFirstBlock = inputBlock;
        require(capture.start(file, rate, channels, 0), "capture start");
        require(!capture.start(file, rate, channels, 0), "double start accepted");
        constexpr int captureBlocks = 64;
        for (int n = 0; n < captureBlocks; ++n) { push(); read(); }
        const bool cancelled = take == 1;
        const auto result = capture.stop(cancelled);
        require(monitor.connections() == channels, "capture stop disabled monitoring");
        require(result.droppedSamples == 0 && result.invalidBlockCount == 0, "capture lost samples");
        if (cancelled)
            require(!file.existsAsFile(), "cancelled WAV retained");
        else
        {
            require(result.success, "capture stop");
            juce::WavAudioFormat wav;
            std::unique_ptr<juce::AudioFormatReader> reader(wav.createReaderFor(file.createInputStream().release(), true));
            require(reader != nullptr, "read WAV");
            require(reader->lengthInSamples == captureBlocks * blockFrames, "WAV length");
            require(reader->sampleRate == rate && reader->numChannels == (unsigned)channels, "WAV format");
            juce::AudioBuffer<float> recorded(channels, int(reader->lengthInSamples));
            require(reader->read(&recorded, 0, recorded.getNumSamples(), 0, true, true), "WAV samples");
            for (int ch = 0; ch < channels; ++ch)
                for (int n = 0; n < recorded.getNumSamples(); ++n)
                    require(std::abs(recorded.getSample(ch, n) - sample(captureFirstBlock + n / blockFrames, ch, n % blockFrames)) < 0.000001f, "WAV differs from input");
            reader.reset();
            require(file.deleteFile(), "remove WAV");
        }
        for (int n = 0; n < 10; ++n) { push(); read(); }
    }
    // Failed writer creation and recording with monitoring disabled.
    require(!capture.start(directory, rate, channels, 0), "writer accepted directory");
    push(); read();
    require(monitor.connections() == channels, "capture changed graph connections");
    monitor.disable();
    auto offFile = directory.getNonexistentChildFile("pro72-monitor-off", ".wav");
    require(capture.start(offFile, rate, channels, 0), "off capture start");
    capture.capture(input.getArrayOfReadPointers(), channels, blockFrames);
    output.clear();
    for (int ch = 0; ch < channels; ++ch)
        output.copyFrom(ch, 0, input, ch, 0, blockFrames);
    monitor.render(output);
    require(output.getMagnitude(0, blockFrames) == 0, "disabled monitor audible");
    require(capture.stop().success, "off capture stop");
    juce::WavAudioFormat wav;
    std::unique_ptr<juce::AudioFormatReader> reader(wav.createReaderFor(offFile.createInputStream().release(), true));
    require(reader != nullptr && reader->lengthInSamples == blockFrames, "monitor-off WAV length");
    juce::AudioBuffer<float> recorded(channels, blockFrames);
    require(reader->read(&recorded, 0, blockFrames, 0, true, true), "monitor-off WAV read");
    for (int ch = 0; ch < channels; ++ch)
        for (int n = 0; n < blockFrames; ++n)
            require(std::abs(recorded.getSample(ch, n) - input.getSample(ch, n)) < 0.000001f, "monitor-off WAV sample");
    reader.reset();
    offFile.deleteFile();
}

int main(int argc, char** argv)
{
    try {
        juce::ScopedJuceInitialiser_GUI initialise;
        require(argc == 2, "test directory required");
        for (int channels : {1, 2})
            for (int block : {64, 256, 1024}) run(channels, block, juce::File(argv[1]));
        std::cout << "PASS: mono/stereo monitor continuity, WAV samples, repeated takes, cancellation, failed start, monitoring off\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
}
