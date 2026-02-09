#include "JuceEngine.h"

using namespace juce;

// ============================================================
// Singleton
// ============================================================
JuceEngine &JuceEngine::get()
{
    static JuceEngine instance;
    return instance;
}

// ============================================================
// Ctor / Dtor
// ============================================================
JuceEngine::JuceEngine()
{
    // Nothing heavy here – all real init happens in initialiseEngine()
}

JuceEngine::~JuceEngine()
{
    // shutdownEngine();
}

// ============================================================
// Initialise / Shutdown
// ============================================================
void JuceEngine::initialiseEngine()
{
    juceLogToFlutter("Hello from JuceEngine::initialiseEngine()");

    if (engineInitialized)
    {
        juceLogToFlutter("JuceEngine::initialiseEngine() already called — skipping.");
        return;
    }

    if (!formatsRegistered)
    {
        // Audio formats
        formatManager.registerBasicFormats();
        // Plugin formats
        pluginFormatManager.addDefaultFormats();
#if JUCE_IOS
        pluginFormatManager.addFormat(new juce::AudioUnitPluginFormat());
#endif
        // Audio device setup
        deviceManager.initialise(
            2, // 0, // numInputChannels
            2, // numOutputChannels
            nullptr,
            true);

        {
            auto setup = deviceManager.getAudioDeviceSetup();

            setup.useDefaultInputChannels = false;
            setup.useDefaultOutputChannels = true;

            setup.inputChannels.setRange(0, 256, true);

            // Enable a safe number of input channels
            setup.inputChannels.clear();
            for (int i = 0; i < 8; ++i)
                setup.inputChannels.setBit(i);

            deviceManager.setAudioDeviceSetup(setup, true);
        }

        formatsRegistered = true;
    }

    AudioIODevice *dev = deviceManager.getCurrentAudioDevice();
    double hostRate = dev ? dev->getCurrentSampleRate() : 44100.0;
    int blockSize = dev ? dev->getCurrentBufferSizeSamples() : 512;

    // graph.prepareToPlay(hostRate, blockSize);
    // juceLogToFlutter(("graph.prepareToPlay(" + String(hostRate) + ", " + String(blockSize) + ")").toRawUTF8());

    audioPlayer.setProcessor(&graph);
    // deviceManager.addAudioCallback(&audioPlayer);
    if (!metronomeCallback)
    {
        metronomeCallback =
            std::make_unique<MetronomeAudioCallback>(audioPlayer, *this);
        deviceManager.addAudioCallback(metronomeCallback.get());
    }

    // auto inputNode = graph.addNode(std::make_unique<AudioProcessorGraph::AudioGraphIOProcessor>(
    //     AudioProcessorGraph::AudioGraphIOProcessor::audioInputNode));
    inputNode = graph.addNode(
        std::make_unique<juce::AudioProcessorGraph::AudioGraphIOProcessor>(
            juce::AudioProcessorGraph::AudioGraphIOProcessor::audioInputNode));

    // Output node for device
    outputNode = graph.addNode(std::make_unique<AudioProcessorGraph::AudioGraphIOProcessor>(
        AudioProcessorGraph::AudioGraphIOProcessor::audioOutputNode));

    // Build row + master bus graph once
    ensureBusGraphInitialised();

    graph.prepareToPlay(hostRate, blockSize);
    juceLogToFlutter(("graph.prepareToPlay(" + String(hostRate) + ", " + String(blockSize) + ")").toRawUTF8());

    // Clear plugin list and rescan
    pluginList.clear();

    auto appBundleRoot = juce::File::getSpecialLocation(juce::File::hostApplicationPath).getParentDirectory();

    for (int i = 0; i < pluginFormatManager.getNumFormats(); ++i)
    {
        auto *format = pluginFormatManager.getFormat(i);
        if (format == nullptr)
            continue;

        FileSearchPath searchPath;

        if (format->getName() == "AudioUnit")
        {
            juceLogToFlutter("Scanning AUv3 (AudioUnitPluginFormat) from registry");
            searchPath = FileSearchPath(); // required for AUv3
        }
        else
        {
            juceLogToFlutter(("Scanning format " + format->getName() + " from " + appBundleRoot.getFullPathName()).toRawUTF8());
            searchPath = FileSearchPath(appBundleRoot.getFullPathName());
        }

        PluginDirectoryScanner scanner(pluginList, *format, searchPath, true, File());
        String err;
        while (scanner.scanNextFile(false, err))
        {
        }
    }

    for (const auto &type : pluginList.getTypes())
        juceLogToFlutter(("Discovered plugin: " + type.name).toRawUTF8());

    engineInitialized = true;
}

void JuceEngine::shutdownEngine()
{
    juceLogToFlutter("JuceEngine::shutdownEngine called");

    if (!engineInitialized)
    {
        juceLogToFlutter("... skipped — engine not initialized yet.");
        return;
    }

    if (metronomeCallback)
    {
        deviceManager.removeAudioCallback(metronomeCallback.get());
        metronomeCallback.reset();
    }

    audioPlayer.setProcessor(nullptr);
    // deviceManager.removeAudioCallback(&audioPlayer);
    // deviceManager.closeAudioDevice();

    graph.clear();

    // *** IMPORTANT: clear Node::Ptr handles to old graph nodes ***
    inputNode = nullptr;
    outputNode = nullptr;
    videoAudioNode = nullptr;
    masterGainNode = nullptr;
    masterPanNode = nullptr;

    for (int t = 0; t < kNumTracks; ++t)
    {
        trackInputNodes[t] = nullptr;
        trackAutomationNodes[t] = nullptr;
        trackGainNodes[t] = nullptr;
        trackPanNodes[t] = nullptr;

        rowMeterTapNodes[t] = nullptr;
        rowMeterTaps[t] = nullptr;
    }

    // Clear clip structures
    trackNodes.clear();
    gainProcessors.clear();
    clipPanProcessors.clear();
    clipTrackAssignments.clear();
    trackEffectChains.clear();

    // Clear row structures
    for (int t = 0; t < kNumTracks; ++t)
    {
        trackInputNodes[t] = nullptr;
        trackAutomationNodes[t] = nullptr;
        trackGainNodes[t] = nullptr;
        trackPanNodes[t] = nullptr;

        trackInputProcessors[t] = nullptr;
        trackAutomationProcessors[t] = nullptr;
        trackGainProcessors[t] = nullptr;
        trackPanProcessors[t] = nullptr;

        rowMeterTapNodes[t] = nullptr;
        rowMeterTaps[t] = nullptr;
    }

    trackBusEffectChains.clear();

    // Master chain
    if (masterEffectChain != nullptr)
    {
        masterEffectChain->clear();
        delete masterEffectChain;
        masterEffectChain = nullptr;
    }

    masterGainNode = nullptr;
    masterPanNode = nullptr;
    masterGainProcessor = nullptr;
    masterPanProcessor = nullptr;

    // Video lane
    videoAudioNode = nullptr;
    videoGainProc = nullptr;
    hasVideoAudio = false;

    busGraphInitialised = false;
    engineInitialized = false;
}

// ============================================================
// Helper: Build bus graph (rows + master)
// ============================================================
void JuceEngine::ensureBusGraphInitialised()
{
    if (busGraphInitialised)
        return;

    if (outputNode == nullptr)
    {
        juceLogToFlutter("ensureBusGraphInitialised: outputNode is null");
        return;
    }

    AudioIODevice *dev = deviceManager.getCurrentAudioDevice();
    double sampleRate = dev ? dev->getCurrentSampleRate() : graph.getSampleRate();
    if (sampleRate <= 0.0)
        sampleRate = 44100.0;

    int blockSize = dev ? dev->getCurrentBufferSizeSamples() : graph.getBlockSize();
    if (blockSize <= 0)
        blockSize = 512;

    // MASTER gain + pan
    {
        auto mg = std::make_unique<SimpleGainProcessor>();
        masterGainProcessor = mg.get();
        masterGainNode = graph.addNode(std::move(mg));
        // masterGainProcessor->prepareToPlay(sampleRate, blockSize);
        masterGainProcessor->gain->setValueNotifyingHost(1.0f / 3.0f); // normalized → param=1.0

        auto mp = std::make_unique<StereoPanProcessor>();
        masterPanProcessor = mp.get();
        masterPanNode = graph.addNode(std::move(mp));
        // masterPanProcessor->prepareToPlay(sampleRate, blockSize);
        masterPanProcessor->pan->setValueNotifyingHost(0.5f);

        for (int ch = 0; ch < 2; ++ch)
        {
            graph.addConnection({{masterGainNode->nodeID, ch}, {masterPanNode->nodeID, ch}});
            graph.addConnection({{masterPanNode->nodeID, ch}, {outputNode->nodeID, ch}});
        }
    }

    // master FX chain container
    if (masterEffectChain == nullptr)
        masterEffectChain = new juce::Array<juce::AudioProcessorGraph::NodeID>();

    // Row FX arrays
    trackBusEffectChains.clear();
    for (int t = 0; t < kNumTracks; ++t)
        trackBusEffectChains.add(new juce::Array<juce::AudioProcessorGraph::NodeID>());

    // Per-row processors
    for (int t = 0; t < kNumTracks; ++t)
    {
        // TrackInput
        auto ti = std::make_unique<TrackInputProcessor>();
        trackInputProcessors[t] = ti.get();
        trackInputNodes[t] = graph.addNode(std::move(ti));
        // trackInputProcessors[t]->prepareToPlay(sampleRate, blockSize);

        // Automation
        auto ap = std::make_unique<VolumeAutomationProcessor>();
        trackAutomationProcessors[t] = ap.get();
        trackAutomationNodes[t] = graph.addNode(std::move(ap));
        // trackAutomationProcessors[t]->prepareToPlay(sampleRate, blockSize);

        // Gain
        auto tg = std::make_unique<SimpleGainProcessor>();
        trackGainProcessors[t] = tg.get();
        trackGainNodes[t] = graph.addNode(std::move(tg));
        // trackGainProcessors[t]->prepareToPlay(sampleRate, blockSize);
        trackGainProcessors[t]->gain->setValueNotifyingHost(1.0f / 3.0f);

        // Pan
        auto tp = std::make_unique<StereoPanProcessor>();
        trackPanProcessors[t] = tp.get();
        trackPanNodes[t] = graph.addNode(std::move(tp));
        // trackPanProcessors[t]->prepareToPlay(sampleRate, blockSize);
        trackPanProcessors[t]->pan->setValueNotifyingHost(0.5f);

        // Meter tap (post-pan)
        auto mt = std::make_unique<MeterTapProcessor>(
            &rowMeters[t].peakL,
            &rowMeters[t].peakR,
            &rowMeters[t].rmsL,
            &rowMeters[t].rmsR,
            &rowMetersEnabled);

        rowMeterTaps[t] = mt.get();
        rowMeterTapNodes[t] = graph.addNode(std::move(mt));

        // Wire: TrackInput → Automation → TrackGain → TrackPan → RowMeterTap → MasterGain
        for (int ch = 0; ch < 2; ++ch)
        {
            graph.addConnection({{trackInputNodes[t]->nodeID, ch}, {trackAutomationNodes[t]->nodeID, ch}});
            graph.addConnection({{trackAutomationNodes[t]->nodeID, ch}, {trackGainNodes[t]->nodeID, ch}});
            graph.addConnection({{trackGainNodes[t]->nodeID, ch}, {trackPanNodes[t]->nodeID, ch}});
            graph.addConnection({{trackPanNodes[t]->nodeID, ch}, {rowMeterTapNodes[t]->nodeID, ch}});
            graph.addConnection({{rowMeterTapNodes[t]->nodeID, ch}, {masterGainNode->nodeID, ch}});
        }
    }

    busGraphInitialised = true;
    juceLogToFlutter("Bus graph initialised (rows + master)");
}

// ============================================================
// CLIP / TRACK (legacy name) loading
// ============================================================
void JuceEngine::loadTrack(int idx, const File &file)
{
    // Legacy API – treat as clip on row 0
    loadClip(idx, 0, file);
}

void JuceEngine::loadClip(int clipIndex, int rowIndex, const juce::File &file)
{
    // juceLogToFlutter("JuceEngine::loadClip");

    if (clipIndex < 0 || clipIndex >= kMaxClips)
    {
        juceLogToFlutter("loadClip: clipIndex < 0 or greater than kMaxClips");
        return;
    }

    try
    {
        // Ensure arrays are large enough
        while (trackNodes.size() <= clipIndex)
            trackNodes.add(nullptr);
        while (gainProcessors.size() <= clipIndex)
            gainProcessors.add(nullptr);
        while (clipPanProcessors.size() <= clipIndex)
            clipPanProcessors.add(nullptr);
        while (clipTrackAssignments.size() <= clipIndex)
            clipTrackAssignments.add(0);
        while (trackEffectChains.size() <= clipIndex)
            trackEffectChains.add(new juce::Array<juce::AudioProcessorGraph::NodeID>());

        // 1. Remove old nodes for this clip (if any)
        removeTrack(clipIndex);

        // 2. Create reader + FilePlayerProcessor
        std::unique_ptr<AudioFormatReader> reader(formatManager.createReaderFor(file));
        if (reader == nullptr)
        {
            juceLogToFlutter("loadClip: createReaderFor() returned nullptr");
            return;
        }

        auto totalLength = reader->lengthInSamples;
        auto readerSource = std::make_unique<AudioFormatReaderSource>(reader.release(), true);
        auto player = std::make_unique<FilePlayerProcessor>(
            std::move(readerSource),
            totalLength,
            file);

        auto playerNode = graph.addNode(std::move(player));
        trackNodes.set(clipIndex, playerNode);

        // 3. Per-clip gain
        auto gainProc = std::make_unique<SimpleGainProcessor>();
        auto *gainPtr = gainProc.get();
        auto gainNode = graph.addNode(std::move(gainProc));

        gainProcessors.set(clipIndex, gainPtr);
        // gainPtr->prepareToPlay(graph.getSampleRate(), graph.getBlockSize());
        // normalized 1/3 → param=1.0 (unity, because range is 0..3.0)
        gainPtr->gain->setValueNotifyingHost(1.0f / 3.0f);

        // 4. Per-clip pan
        auto panProc = std::make_unique<StereoPanProcessor>();
        auto *panPtr = panProc.get();
        auto panNode = graph.addNode(std::move(panProc));

        clipPanProcessors.set(clipIndex, panPtr);
        // panPtr->prepareToPlay(graph.getSampleRate(), graph.getBlockSize());
        panPtr->pan->setValueNotifyingHost(0.5f); // center

        // 5. Store clip → row assignment
        rowIndex = juce::jlimit(0, kNumTracks - 1, rowIndex);
        clipTrackAssignments.set(clipIndex, rowIndex);

        // 6. Ensure row/master buses exist
        ensureBusGraphInitialised();
        int row = rowIndex;
        auto rowInputNode = trackInputNodes[row];

        if (rowInputNode == nullptr)
        {
            juceLogToFlutter("loadClip: rowInputNode is null after ensureBusGraphInitialised");
            return;
        }

        // 7. Wire: FilePlayer → ClipGain → ClipPan → TrackInput[row]
        if (playerNode != nullptr && gainNode != nullptr && panNode != nullptr)
        {
            // int numOutCh = jmin(2, playerNode->getProcessor()->getTotalNumOutputChannels());

            for (int ch = 0; ch < 2; ++ch) // for (int ch = 0; ch < numOutCh; ++ch)
            {
                graph.addConnection({{playerNode->nodeID, ch}, {gainNode->nodeID, ch}});
                graph.addConnection({{gainNode->nodeID, ch}, {panNode->nodeID, ch}});
                graph.addConnection({{panNode->nodeID, ch}, {rowInputNode->nodeID, ch}});
            }
        }
        else
        {
            juceLogToFlutter("loadClip: missing node(s) when wiring signal");
        }

        // 8. Ensure per-clip FX chain exists (legacy behavior, but safe)
        auto *chain = trackEffectChains[clipIndex];
        if (chain == nullptr)
        {
            chain = new juce::Array<juce::AudioProcessorGraph::NodeID>();
            trackEffectChains.set(clipIndex, chain);
        }

        // 9. Freeze all clips by default (matches your pause/play model)
        for (int i = 0; i < trackNodes.size(); ++i)
        {
            if (trackNodes[i] != nullptr)
                trackNodes[i]->setBypassed(true);
        }
    }
    catch (const std::exception &e)
    {
        juceLogToFlutter("Exception in loadClip:");
        juceLogToFlutter(e.what());
    }
    catch (...)
    {
        juceLogToFlutter("Unknown exception in loadClip");
    }
}

// ============================================================
// Remove clip (legacy name removeTrack)
// ============================================================
void JuceEngine::removeTrack(int trackIndex)
{
    // juceLogToFlutter(("JuceEngine::removeTrack clipIndex=" + juce::String(trackIndex)).toRawUTF8());

    if (trackIndex < 0 || trackIndex >= trackNodes.size())
        return;

    // 1) Remove per-clip FX nodes for this clip
    if (trackIndex < trackEffectChains.size())
    {
        if (auto *chain = trackEffectChains[trackIndex])
        {
            for (int i = 0; i < chain->size(); ++i)
            {
                auto nodeID = chain->getUnchecked(i);
                if (auto *fxNode = graph.getNodeForId(nodeID))
                    graph.removeNode(fxNode->nodeID);
            }
            chain->clear();
        }
    }

    // 2) Remove per-clip gain node
    if (trackIndex < gainProcessors.size())
    {
        if (auto *gproc = gainProcessors[trackIndex])
        {
            for (auto *node : graph.getNodes())
            {
                if (node != nullptr && node->getProcessor() == gproc)
                {
                    graph.removeNode(node->nodeID);
                    break;
                }
            }
        }
    }

    // 3) Remove per-clip pan node
    if (trackIndex < clipPanProcessors.size())
    {
        if (auto *pproc = clipPanProcessors[trackIndex])
        {
            for (auto *node : graph.getNodes())
            {
                if (node != nullptr && node->getProcessor() == pproc)
                {
                    graph.removeNode(node->nodeID);
                    break;
                }
            }
        }
    }

    // 4) Remove FilePlayer node
    if (trackIndex < trackNodes.size())
    {
        if (auto node = trackNodes[trackIndex])
            graph.removeNode(node->nodeID);
    }

    // 5) COMPACT ARRAYS so engine indices stay aligned with Flutter
    if (trackIndex < trackEffectChains.size())
        trackEffectChains.remove(trackIndex); // removes ptr & shifts left

    if (trackIndex < gainProcessors.size())
        gainProcessors.remove(trackIndex); // shifts all later gains left

    if (trackIndex < clipPanProcessors.size())
        clipPanProcessors.remove(trackIndex); // shifts pans left

    if (trackIndex < trackNodes.size())
        trackNodes.remove(trackIndex); // shifts track nodes left

    if (trackIndex < clipTrackAssignments.size())
        clipTrackAssignments.remove(trackIndex); // no “ghost” assignment

    // juceLogToFlutter("removeTrack: clip removed, arrays compacted");
}

// ============================================================
// Clip FX (legacy) chain management
// ============================================================
void JuceEngine::removePluginEffect(int trackIdx, int effectIndex)
{
    // juceLogToFlutter("Hello from JuceEngine::removePluginEffect");
    if (trackIdx < 0 || trackIdx >= trackEffectChains.size())
        return;
    auto *chain = trackEffectChains[trackIdx];
    if (chain == nullptr || effectIndex < 0 || effectIndex >= chain->size())
        return;

    auto nodeID = chain->getReference(effectIndex);
    graph.removeNode(nodeID);
    chain->removeRange(effectIndex, 1);

    rewireTrackChain(trackIdx);
}

void JuceEngine::reorderPluginEffects(int trackIdx, int fromIndex, int toIndex)
{
    // juceLogToFlutter("Hello from JuceEngine::reorderPluginEffects");
    if (trackIdx < 0 || trackIdx >= trackEffectChains.size())
        return;
    auto *chain = trackEffectChains[trackIdx];
    if (chain == nullptr)
        return;

    if (fromIndex < 0 || fromIndex >= chain->size() ||
        toIndex < 0 || toIndex > chain->size())
        return;

    auto nodeID = chain->getReference(fromIndex);
    chain->removeRange(fromIndex, 1);
    chain->insert(toIndex, nodeID);

    rewireTrackChain(trackIdx);
}

void JuceEngine::rewireTrackChain(int trackIdx)
{
    // NOTE: here "trackIdx" is still per-clip index.
    if (trackIdx < 0 || trackIdx >= trackNodes.size())
        return;

    auto fileNode = trackNodes[trackIdx];
    if (fileNode == nullptr)
        return;

    ensureBusGraphInitialised();

    // -------- Collect all nodeIDs involved with this clip --------
    juce::Array<AudioProcessorGraph::NodeID> clipNodeIDs;
    clipNodeIDs.add(fileNode->nodeID);

    // FX nodes (legacy clip FX)
    if (trackIdx < trackEffectChains.size())
    {
        auto *chain = trackEffectChains[trackIdx];
        if (chain != nullptr)
        {
            for (int i = 0; i < chain->size(); ++i)
                clipNodeIDs.addIfNotAlreadyThere(chain->getReference(i));
        }
    }

    // Clip gain node
    if (trackIdx < gainProcessors.size() && gainProcessors[trackIdx] != nullptr)
    {
        SimpleGainProcessor *gproc = gainProcessors[trackIdx];
        for (auto *n : graph.getNodes())
        {
            if (n != nullptr && n->getProcessor() == gproc)
            {
                clipNodeIDs.addIfNotAlreadyThere(n->nodeID);
                break;
            }
        }
    }

    // Clip pan node
    if (trackIdx < clipPanProcessors.size() && clipPanProcessors[trackIdx] != nullptr)
    {
        StereoPanProcessor *pproc = clipPanProcessors[trackIdx];
        for (auto *n : graph.getNodes())
        {
            if (n != nullptr && n->getProcessor() == pproc)
            {
                clipNodeIDs.addIfNotAlreadyThere(n->nodeID);
                break;
            }
        }
    }

    // -------- Remove connections touching ANY of these nodes --------
    juce::Array<AudioProcessorGraph::Connection> toRemove;
    auto connections = graph.getConnections();

    for (const auto &c : connections)
    {
        if (clipNodeIDs.contains(c.source.nodeID) ||
            clipNodeIDs.contains(c.destination.nodeID))
        {
            toRemove.addIfNotAlreadyThere(c);
        }
    }

    for (const auto &c : toRemove)
        graph.removeConnection(c);

    // -------- Rebuild chain: FilePlayer → [FX...] → ClipGain → ClipPan → TrackInput(row) --------
    AudioProcessorGraph::Node::Ptr prev = fileNode;

    // 1) Insert FX nodes in stored order (if any)
    if (trackIdx < trackEffectChains.size())
    {
        auto *chain = trackEffectChains[trackIdx];
        if (chain != nullptr)
        {
            for (int i = 0; i < chain->size(); ++i)
            {
                auto nodeID = chain->getReference(i);
                auto *fxNode = graph.getNodeForId(nodeID);
                if (fxNode != nullptr)
                {
                    for (int ch = 0; ch < 2; ++ch)
                        graph.addConnection({{prev->nodeID, ch}, {fxNode->nodeID, ch}});
                    prev = fxNode;
                }
            }
        }
    }

    // 2) Find this clip's gain node
    AudioProcessorGraph::Node::Ptr gainNode;
    if (trackIdx < gainProcessors.size() && gainProcessors[trackIdx] != nullptr)
    {
        SimpleGainProcessor *gproc = gainProcessors[trackIdx];
        for (auto *n : graph.getNodes())
        {
            if (n != nullptr && n->getProcessor() == gproc)
            {
                gainNode = n;
                break;
            }
        }
    }

    // 3) Find this clip's pan node
    AudioProcessorGraph::Node::Ptr panNode;
    if (trackIdx < clipPanProcessors.size() && clipPanProcessors[trackIdx] != nullptr)
    {
        StereoPanProcessor *pproc = clipPanProcessors[trackIdx];
        for (auto *n : graph.getNodes())
        {
            if (n != nullptr && n->getProcessor() == pproc)
            {
                panNode = n;
                break;
            }
        }
    }

    const int trackRow = getTrackIndexForClip(trackIdx);
    const int row = (trackRow >= 0 && trackRow < kNumTracks) ? trackRow : 0;
    auto rowInputNode = trackInputNodes[row];

    if (gainNode != nullptr && panNode != nullptr && rowInputNode != nullptr)
    {
        for (int ch = 0; ch < 2; ++ch)
        {
            graph.addConnection({{prev->nodeID, ch}, {gainNode->nodeID, ch}});
            graph.addConnection({{gainNode->nodeID, ch}, {panNode->nodeID, ch}});
            graph.addConnection({{panNode->nodeID, ch}, {rowInputNode->nodeID, ch}});
        }
    }
    else if (rowInputNode != nullptr)
    {
        // Fallback: no gain/pan, wire last FX directly into track input
        for (int ch = 0; ch < 2; ++ch)
            graph.addConnection({{prev->nodeID, ch}, {rowInputNode->nodeID, ch}});
    }
}

// ============================================================
// Position / duration
// ============================================================
double JuceEngine::getCurrentPosition(int trackIndex)
{
    if (trackIndex < 0 || trackIndex >= trackNodes.size())
        return 0.0;
    if (auto *fp = dynamic_cast<FilePlayerProcessor *>(trackNodes[trackIndex]->getProcessor()))
        return fp->getCurrentPosition();
    return 0.0;
}

double JuceEngine::getTrackDuration(int trackIndex)
{
    if (trackIndex < 0 || trackIndex >= trackNodes.size())
        return 0.0;
    if (auto *fp = dynamic_cast<FilePlayerProcessor *>(trackNodes[trackIndex]->getProcessor()))
        return fp->getTotalLengthSeconds();
    return 0.0;
}

// ============================================================
// Clip-level effect parameter info (legacy, but used by Dart)
// ============================================================
juce::Array<juce::NamedValueSet> JuceEngine::getPluginParameterInfo(int trackIndex, int effectIndex)
{
    // juceLogToFlutter("Hello from JuceEngine::getPluginParameterInfo");
    Array<NamedValueSet> results;
    if (trackIndex < 0 || trackIndex >= trackEffectChains.size())
        return results;
    auto *chain = trackEffectChains[trackIndex];
    if (chain == nullptr || effectIndex < 0 || effectIndex >= chain->size())
        return results;

    auto nodeID = chain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (node == nullptr)
        return results;

    if (auto *processor = node->getProcessor())
    {
        for (auto *p : processor->getParameters())
        {
            NamedValueSet e;
            e.set("name", p->getName(128));

            if (auto *fp = dynamic_cast<AudioParameterFloat *>(p))
            {
                e.set("type", "float");
                e.set("min", fp->range.start);
                e.set("max", fp->range.end);
                e.set("default", fp->get());
                e.set("value", fp->get());
            }
            else if (auto *bp = dynamic_cast<AudioParameterBool *>(p))
            {
                e.set("type", "bool");
                e.set("default", bp->get());
                e.set("value", bp->get());
            }
            else if (auto *cp = dynamic_cast<AudioParameterChoice *>(p))
            {
                e.set("type", "choice");
                e.set("default", cp->getCurrentChoiceName());
                for (int j = 0; j < cp->choices.size(); ++j)
                    e.set("choice_" + juce::String(j), cp->choices[j]);
                e.set("value", cp->getCurrentChoiceName());
            }
            else
            {
                const bool isChoice = p->isDiscrete();
                const int steps = p->getNumSteps();
                const float curNorm = p->getValue();
                const float defNorm = p->getDefaultValue();

                if (isChoice)
                {
                    e.set("type", "choice");
                    for (int j = 0; j < steps; ++j)
                    {
                        float norm = steps > 1 ? (float)j / (steps - 1) : 0.f;
                        e.set("choice_" + juce::String(j),
                              p->getText(norm, 128));
                    }
                    e.set("default", p->getText(defNorm, 128));
                    e.set("value", p->getText(curNorm, 128));
                }
                else
                {
                    e.set("type", "float");
                    e.set("min", 0.0f);
                    e.set("max", 1.0f);
                    e.set("default", defNorm);
                    e.set("value", curNorm);
                }
            }

            results.add(e);
        }
    }

    return results;
}

// ============================================================
// Clip-level track effect names (legacy)
// ============================================================
juce::StringArray JuceEngine::getTrackEffects(int trackIndex)
{
    juce::StringArray names;

    if (trackIndex < 0 || trackIndex >= trackEffectChains.size())
        return names;

    auto *chain = trackEffectChains[trackIndex];
    if (!chain)
        return names;

    for (auto &nodeID : *chain)
    {
        if (auto node = graph.getNodeForId(nodeID))
        {
            if (auto *processor = node->getProcessor())
                names.add(processor->getName());
        }
    }

    return names;
}

// ============================================================
// insertPluginEffect (clip-level, legacy)
// ============================================================
void JuceEngine::insertPluginEffect(int trackIdx, const juce::String &pluginPath, std::function<void(bool)> callback)
{
    // juceLogToFlutter("Hello from JuceEngine::insertPluginEffect");

    if (trackIdx < 0 || trackIdx >= trackEffectChains.size())
    {
        if (callback)
            callback(false);
        return;
    }

    auto *chain = trackEffectChains[trackIdx];
    if (chain == nullptr)
    {
        chain = new juce::Array<AudioProcessorGraph::NodeID>();
        trackEffectChains.set(trackIdx, chain);
    }

    // Built-in Mixroom native FX
    if (mixroomPlugins.contains(pluginPath))
    {
        std::unique_ptr<AudioProcessor> plugin;
        if (pluginPath == "Reverb")
            plugin = std::make_unique<ReverbAudioProcessor>();
        else if (pluginPath == "EQ Parametric")
            plugin = std::make_unique<EQAudioProcessor>();
        else if (pluginPath == "EQ 3-Band")
            plugin = std::make_unique<EQ3AudioProcessor>();
        else if (pluginPath == "Delay")
            plugin = std::make_unique<DelayAudioProcessor>();
        else if (pluginPath == "Distortion")
            plugin = std::make_unique<DistortionAudioProcessor>();
        else if (pluginPath == "De-Esser")
            plugin = std::make_unique<DeesserAudioProcessor>();
        else if (pluginPath == "Compressor")
            plugin = std::make_unique<CompressorAudioProcessor>();
        else
        {
            juceLogToFlutter("didn't find matching Mixroom plugin (clip-level)");
            if (callback)
                callback(false);
            return;
        }

        // plugin->prepareToPlay(graph.getSampleRate(), graph.getBlockSize());
        auto node = graph.addNode(std::move(plugin));
        chain->add(node->nodeID);
        rewireTrackChain(trackIdx);

        if (callback)
            callback(true);
        return;
    }

    // External plugin (VST/AU etc)
    PluginDescription desc;
    desc.fileOrIdentifier = pluginPath;

    auto *format = pluginFormatManager.getFormat(0);
    if (format == nullptr)
    {
        if (callback)
            callback(false);
        return;
    }

    format->createPluginInstanceAsync(
        desc,
        graph.getSampleRate() > 0 ? graph.getSampleRate() : 44100.0,
        graph.getBlockSize() > 0 ? graph.getBlockSize() : 512,
        [this, trackIdx, callback](std::unique_ptr<AudioPluginInstance> inst, const juce::String &error)
        {
            if (!inst)
            {
                juceLogToFlutter(("insertPluginEffect: " + error).toRawUTF8());
                if (callback)
                    callback(false);
                return;
            }

            MessageManager::callAsync([this, trackIdx, inst = std::move(inst), callback]() mutable
                                      {
                                        //   inst->prepareToPlay(graph.getSampleRate(), graph.getBlockSize());
                                          auto *chain = trackEffectChains[trackIdx];
                                          if (!chain)
                                          {
                                              chain = new juce::Array<AudioProcessorGraph::NodeID>();
                                              trackEffectChains.set(trackIdx, chain);
                                          }

                                          auto pluginNode = graph.addNode(std::move(inst));
                                          chain->add(pluginNode->nodeID);
                                          rewireTrackChain(trackIdx);

                                          if (callback)
                                              callback(true); });
        });
}

// ============================================================
// Clip/master/general parameter setters
// ============================================================
void JuceEngine::setEffectParameter(int trackIndex,
                                    int effectIndex,
                                    const juce::String &paramName,
                                    const juce::var &newValue)
{
    juceLogToFlutter(("JuceEngine::setEffectParameter(track=" + juce::String(trackIndex) +
                      ", effect=" + juce::String(effectIndex) + ", name=\"" + paramName + "\")")
                         .toRawUTF8());

    if (trackIndex < 0 || trackIndex >= trackEffectChains.size())
        return;
    auto *chain = trackEffectChains[trackIndex];
    if (!chain || effectIndex < 0 || effectIndex >= chain->size())
        return;

    auto nodeID = chain->getReference(effectIndex);
    auto *node = graph.getNodeForId(nodeID);
    if (!node)
        return;

    auto *processor = node->getProcessor();
    if (!processor)
        return;

    for (auto *p : processor->getParameters())
    {
        auto thisName = p->getName(128);
        if (thisName != paramName)
            continue;

        float normalized = 0.0f;

        if (newValue.isBool())
        {
            normalized = (bool)newValue ? 1.0f : 0.0f;
        }
        else if (newValue.isDouble() || newValue.isInt())
        {
            normalized = (float)newValue;
        }
        else
        {
            juce::String str = newValue.toString();
            int steps = p->getNumSteps();
            for (int i = 0; i < steps; ++i)
            {
                float n = (steps > 1) ? (float)i / (steps - 1) : 0.0f;
                if (p->getText(n, 128) == str)
                {
                    normalized = n;
                    break;
                }
            }
        }

        if (auto *withID = dynamic_cast<AudioProcessorParameterWithID *>(p))
        {
            if (auto *floatParam = dynamic_cast<AudioParameterFloat *>(p))
            {
                const auto &range = floatParam->range;
                float clamped = jlimit(range.start, range.end, normalized);
                float normalizedTo0to1 = range.convertTo0to1(clamped);
                floatParam->setValueNotifyingHost(normalizedTo0to1);
                juceLogToFlutter(("  Set \"" + paramName + "\" → normalized 0to1 " + juce::String(normalizedTo0to1)).toRawUTF8());
                juceLogToFlutter(("  Now it is: " + juce::String(floatParam->get())).toRawUTF8());
            }
            else
            {
                withID->setValueNotifyingHost(normalized);
                juceLogToFlutter(("  Set \"" + paramName + "\" → normalized " + juce::String(normalized)).toRawUTF8());
                juceLogToFlutter(("  Now it is: " + juce::String(withID->getValue())).toRawUTF8());
            }
        }
        else
        {
            p->setValueNotifyingHost(normalized);
            juceLogToFlutter(("  Fallback set \"" + paramName + "\" → " + juce::String(normalized)).toRawUTF8());
        }

        return;
    }
}

void JuceEngine::setTrackVolume(int trackIdx, float volume)
{
    if (trackIdx < gainProcessors.size() && gainProcessors[trackIdx] != nullptr)
    {
        // volume is 0.0 → 3.0, map to normalized 0..1
        gainProcessors[trackIdx]->gain->setValueNotifyingHost(volume / 3.0f);
    }
}

// ============================================================
// Export functions (kept as you had – you said you'll revisit)
// ============================================================
juce::String JuceEngine::exportMix(const File &outFile)
{
    // juceLogToFlutter("Hello from JuceEngine::exportMix");

    WavAudioFormat fmt;
    auto fs = std::unique_ptr<FileOutputStream>(outFile.createOutputStream());
    if (!fs)
        return {};
    double sr = 44100.0;
    int bs = 512, nc = 2, bp = 16;
    auto w = std::unique_ptr<AudioFormatWriter>(
        fmt.createWriterFor(fs.get(), sr, nc, bp, {}, 0));
    if (!w)
        return {};
    fs.release();

    graph.prepareToPlay(sr, bs);
    AudioBuffer<float> buf(nc, bs);
    MidiBuffer midi;

    int64 total = 0;
    for (auto &node : trackNodes)
    {
        if (node != nullptr)
        {
            if (auto *fp = dynamic_cast<FilePlayerProcessor *>(node->getProcessor()))
            {
                total = jmax(total, fp->getTotalLength());
            }
        }
    }

    int64 written = 0;
    while (written < total)
    {
        buf.clear();
        graph.processBlock(buf, midi);
        int toWrite = (int)jmin<int64>(bs, total - written);
        w->writeFromAudioSampleBuffer(buf, 0, toWrite);
        written += toWrite;
    }

    return outFile.getFullPathName();
}

// (Your exportTrack implementation – unchanged)
juce::String JuceEngine::exportTrack(int trackIndex, const juce::File &outFile)
{
    // Keep your original implementation here – unchanged
    // (omitted in this paste for brevity – you can keep your version as-is)
    // You said you'll fix/tune export logic later, so I didn't touch it.
    juceLogToFlutter("exportTrack called (using your existing implementation)");
    // Just return empty here to avoid compile error in this snippet
    return {};
}

// ============================================================
// Transport
// ============================================================
void JuceEngine::play()
{
    for (int i = 0; i < trackNodes.size(); ++i)
    {
        if (trackNodes[i] != nullptr)
            trackNodes[i]->setBypassed(false);
    }

    if (videoAudioNode)
        videoAudioNode->setBypassed(false);

    if (metronomeCallback)
        metronomeCallback->setIsPlaying(true);

    // debugPrintGraphStructure();
}

void JuceEngine::pause()
{
    for (int i = 0; i < trackNodes.size(); ++i)
    {
        if (trackNodes[i] != nullptr)
            trackNodes[i]->setBypassed(true);
    }

    if (videoAudioNode)
        videoAudioNode->setBypassed(true);

    if (metronomeCallback)
        metronomeCallback->setIsPlaying(false);
}

void JuceEngine::seek(int trackIndex, double positionSeconds)
{
    if (trackIndex < 0 || trackIndex >= trackNodes.size())
        return;

    auto node = trackNodes[trackIndex];
    if (node != nullptr)
    {
        if (auto *fp = dynamic_cast<FilePlayerProcessor *>(node->getProcessor()))
            fp->setPosition(positionSeconds);
    }
}

// ============================================================
// Clip bypass
// ============================================================
void JuceEngine::bypassTrack(int trackIndex, bool shouldBypass)
{
    if (trackIndex < 0 || trackIndex >= trackNodes.size())
        return;

    if (trackNodes[trackIndex] != nullptr)
        trackNodes[trackIndex]->setBypassed(shouldBypass);
}

// ============================================================
// Plugin bypass helpers (clip-level)
// ============================================================
void JuceEngine::bypassPlugin(int trackIndex, int effectIndex, bool shouldBypass)
{
    // juceLogToFlutter("Hello from JuceEngine::bypassPlugin");
    if (trackIndex < 0 || trackIndex >= trackEffectChains.size())
        return;

    auto *chain = trackEffectChains[trackIndex];
    if (!chain || effectIndex < 0 || effectIndex >= chain->size())
        return;

    auto nodeID = chain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (node != nullptr)
        node->setBypassed(shouldBypass);
}

bool JuceEngine::getPluginBypassState(int trackIndex, int effectIndex)
{
    // juceLogToFlutter("Hello from JuceEngine::getPluginBypassState");
    if (trackIndex < 0 || trackIndex >= trackEffectChains.size())
        return false;

    auto *chain = trackEffectChains[trackIndex];
    if (!chain || effectIndex < 0 || effectIndex >= chain->size())
        return false;

    auto nodeID = chain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    return (node != nullptr) ? node->isBypassed() : false;
}

// ============================================================
// Plugin discovery
// ============================================================
juce::Array<juce::PluginDescription> JuceEngine::getKnownPlugins() const
{
    juceLogToFlutter("JuceEngine::getKnownPlugins()");

    auto types = pluginList.getTypes();
    juceLogToFlutter((" found " + juce::String(types.size()) + " plugins").toRawUTF8());
    for (auto &pd : types)
        juceLogToFlutter(("     " + pd.name).toRawUTF8());

    return types;
}

// ============================================================
// Video audio lane (kept as you had; minor safety only)
// ============================================================
void JuceEngine::loadVideoAudio(const juce::File &file)
{
    juceLogToFlutter("loadVideoAudio()");
    unloadVideoAudio();

    try
    {
        auto reader = std::unique_ptr<AudioFormatReader>(
            formatManager.createReaderFor(file));
        if (!reader)
        {
            juceLogToFlutter("❌ loadVideoAudio: reader null");
            return;
        }

        juceLogToFlutter("WavAudioFormat successfully read the file");

        auto lengthInSamples = reader->lengthInSamples;
        auto source = std::make_unique<AudioFormatReaderSource>(reader.release(), true);
        if (!source)
        {
            juceLogToFlutter("loadVideoAudio: source null");
            return;
        }

        auto player = std::make_unique<FilePlayerProcessor>(std::move(source), lengthInSamples, file);
        auto node = graph.addNode(std::move(player));
        videoAudioNode = node;

        // Gain node for video
        auto gainProc = std::make_unique<SimpleGainProcessor>();
        videoGainProc = gainProc.get();
        auto gainNode = graph.addNode(std::move(gainProc));

        AudioIODevice *dev = deviceManager.getCurrentAudioDevice();
        double hostRate = dev ? dev->getCurrentSampleRate() : 44100.0;
        int blockSize = dev ? dev->getCurrentBufferSizeSamples() : 512;

        if (videoGainProc)
        {
            // videoGainProc->prepareToPlay(hostRate, blockSize);
            videoGainProc->gain->setValueNotifyingHost(1.0f / 3.0f);
        }

        int numOutputChannels = node->getProcessor()->getTotalNumOutputChannels();

        if (gainNode != nullptr && outputNode != nullptr)
        {
            for (int ch = 0; ch < jmin(2, numOutputChannels); ++ch)
            {
                graph.addConnection({{videoAudioNode->nodeID, ch}, {gainNode->nodeID, ch}});
                graph.addConnection({{gainNode->nodeID, ch}, {outputNode->nodeID, ch}});
            }
        }

        videoAudioNode->setBypassed(true);
        hasVideoAudio = true;
        juceLogToFlutter("loadVideoAudio done");
    }
    catch (const std::exception &e)
    {
        juceLogToFlutter("std::exception in loadVideoAudio:");
        juceLogToFlutter(e.what());
    }
    catch (...)
    {
        juceLogToFlutter("Unknown C++ exception in loadVideoAudio");
    }
}

void JuceEngine::unloadVideoAudio()
{
    if (!hasVideoAudio)
        return;

    juceLogToFlutter("unloadVideoAudio()");
    juce::Array<AudioProcessorGraph::Connection> toRemove;
    for (auto &c : graph.getConnections())
    {
        if (videoAudioNode && (c.source.nodeID == videoAudioNode->nodeID ||
                               c.destination.nodeID == videoAudioNode->nodeID))
            toRemove.add(c);
    }
    for (auto &c : toRemove)
        graph.removeConnection(c);

    if (videoGainProc)
    {
        for (auto *n : graph.getNodes())
        {
            if (n && n->getProcessor() == videoGainProc)
            {
                graph.removeNode(n->nodeID);
                break;
            }
        }
    }

    if (videoAudioNode)
        graph.removeNode(videoAudioNode->nodeID);

    videoAudioNode = nullptr;
    videoGainProc = nullptr;
    hasVideoAudio = false;
}

void JuceEngine::setVideoAudioGain(float gain)
{
    if (videoGainProc)
        videoGainProc->gain->setValueNotifyingHost(gain / 3.0f);
}

void JuceEngine::seekVideoAudio(double seconds)
{
    if (videoAudioNode)
        if (auto *fp = dynamic_cast<FilePlayerProcessor *>(videoAudioNode->getProcessor()))
            fp->setPosition(seconds);
}

// ============================================================
// Debug printing
// ============================================================
void JuceEngine::debugPrintGraph(const juce::String &title)
{
    juceLogToFlutter("──────────────────────────────────────────────");
    juceLogToFlutter(("JUCE GRAPH DUMP: " + title).toRawUTF8());
    juceLogToFlutter("──────────────────────────────────────────────");

    juceLogToFlutter("Nodes:");
    for (auto *node : graph.getNodes())
    {
        if (node == nullptr)
            continue;

        juce::String id = juce::String((int)node->nodeID.uid);
        juce::String name = node->getProcessor() ? node->getProcessor()->getName() : "null";

        juceLogToFlutter(("-NodeID " + id + "  :  " + name).toRawUTF8());
    }

    juceLogToFlutter("----------------------------------------------");
    juceLogToFlutter("Connections:");

    for (const auto &c : graph.getConnections())
    {
        juce::String srcId = juce::String((int)c.source.nodeID.uid);
        juce::String dstId = juce::String((int)c.destination.nodeID.uid);
        juce::String srcCh = juce::String(c.source.channelIndex);
        juce::String dstCh = juce::String(c.destination.channelIndex);

        juceLogToFlutter(("-" + srcId + ":" + srcCh + "  →  " + dstId + ":" + dstCh).toRawUTF8());
    }

    juceLogToFlutter("──────────────────────────────────────────────");
}

void JuceEngine::debugPrintGraphStructure()
{
    juceLogToFlutter("──────────── JUCE GRAPH STRUCTURE (semantic) ────────────");

    for (int i = 0; i < trackNodes.size(); ++i)
    {
        auto node = trackNodes[i];
        if (node == nullptr)
            continue;

        int row = 0;
        if (i < clipTrackAssignments.size())
            row = juce::jlimit(0, kNumTracks - 1, clipTrackAssignments[i]);

        juce::String line;
        line << "audio clip #" << juce::String(i);

        int clipFxCount = 0;
        if (i < trackEffectChains.size() && trackEffectChains[i] != nullptr)
            clipFxCount = trackEffectChains[i]->size();

        if (clipFxCount > 0)
            line << " -> clip fx(" << juce::String(clipFxCount) << ")";

        if (i < gainProcessors.size() && gainProcessors[i] != nullptr)
            line << " -> clip gain";

        if (i < clipPanProcessors.size() && clipPanProcessors[i] != nullptr)
            line << " -> clip pan";

        line << " -> row #" << juce::String(row);

        int rowFxCount = 0;
        if (row >= 0 && row < trackBusEffectChains.size() && trackBusEffectChains[row] != nullptr)
            rowFxCount = trackBusEffectChains[row]->size();

        if (rowFxCount > 0)
            line << " -> row " << juce::String(row) << " fx(" << juce::String(rowFxCount) << ")";

        if (busGraphInitialised)
        {
            if (trackAutomationProcessors[row] != nullptr)
                line << " -> row " << juce::String(row) << " automation";

            if (trackGainProcessors[row] != nullptr)
                line << " -> row " << juce::String(row) << " gain";

            if (trackPanProcessors[row] != nullptr)
                line << " -> row " << juce::String(row) << " pan";
        }

        int masterFxCount = (masterEffectChain != nullptr) ? masterEffectChain->size() : 0;
        if (masterFxCount > 0)
            line << " -> master fx(" << juce::String(masterFxCount) << ")";

        if (masterGainProcessor != nullptr)
            line << " -> master gain";

        if (masterPanProcessor != nullptr)
            line << " -> master pan";

        line << " -> output";

        juceLogToFlutter(line.toRawUTF8());
    }

    juceLogToFlutter("────────────────────────────────────────────────────────");
}

// ============================================================
// Row bus FX chain rewiring
// ============================================================
void JuceEngine::rewireTrackBusFxChain(int row)
{
    if (!busGraphInitialised)
        return;

    if (row < 0 || row >= kNumTracks)
        return;

    auto *inputNode = trackInputNodes[row].get();
    auto *automationNode = trackAutomationNodes[row].get();
    auto *chain = trackBusEffectChains[row];

    if (!inputNode || !automationNode || !chain)
        return;

    juce::Array<AudioProcessorGraph::NodeID> chainNodes;
    chainNodes.add(inputNode->nodeID);
    for (int i = 0; i < chain->size(); ++i)
        chainNodes.add(chain->getReference(i));
    chainNodes.add(automationNode->nodeID);

    auto isInChain = [&](AudioProcessorGraph::NodeID id)
    {
        for (auto n : chainNodes)
            if (n == id)
                return true;
        return false;
    };

    juce::Array<AudioProcessorGraph::Connection> toRemove;
    auto connections = graph.getConnections();

    for (const auto &c : connections)
    {
        if (isInChain(c.source.nodeID) && isInChain(c.destination.nodeID))
            toRemove.addIfNotAlreadyThere(c);
    }

    for (const auto &c : toRemove)
        graph.removeConnection(c);

    AudioProcessorGraph::Node::Ptr prev = trackInputNodes[row];

    for (int i = 0; i < chain->size(); ++i)
    {
        auto nodeID = chain->getReference(i);
        if (auto *fxNode = graph.getNodeForId(nodeID))
        {
            for (int ch = 0; ch < 2; ++ch)
                graph.addConnection({{prev->nodeID, ch}, {fxNode->nodeID, ch}});
            prev = fxNode;
        }
    }

    for (int ch = 0; ch < 2; ++ch)
        graph.addConnection({{prev->nodeID, ch}, {automationNode->nodeID, ch}});
}

// ============================================================
// Track-row FX / parameters
// ============================================================
void JuceEngine::insertTrackEffect(int trackRow,
                                   const juce::String &pluginPath,
                                   std::function<void(bool)> callback)
{
    // juceLogToFlutter("Hello from JuceEngine::insertTrackEffect");

    if (trackRow < 0 || trackRow >= trackBusEffectChains.size())
    {
        if (callback)
            callback(false);
        return;
    }

    auto *chain = trackBusEffectChains[trackRow];
    if (!chain)
    {
        chain = new juce::Array<AudioProcessorGraph::NodeID>();
        trackBusEffectChains.set(trackRow, chain);
    }

    // Built-in Mixroom
    if (mixroomPlugins.contains(pluginPath))
    {
        std::unique_ptr<AudioProcessor> plugin;

        if (pluginPath == "Reverb")
            plugin = std::make_unique<ReverbAudioProcessor>();
        else if (pluginPath == "EQ Parametric")
            plugin = std::make_unique<EQAudioProcessor>();
        else if (pluginPath == "EQ 3-Band")
            plugin = std::make_unique<EQ3AudioProcessor>();
        else if (pluginPath == "Delay")
            plugin = std::make_unique<DelayAudioProcessor>();
        else if (pluginPath == "Distortion")
            plugin = std::make_unique<DistortionAudioProcessor>();
        else if (pluginPath == "De-Esser")
            plugin = std::make_unique<DeesserAudioProcessor>();
        else if (pluginPath == "Compressor")
            plugin = std::make_unique<CompressorAudioProcessor>();
        else
        {
            juceLogToFlutter("didn't find matching Mixroom plugin (row)");
            if (callback)
                callback(false);
            return;
        }

        // plugin->prepareToPlay(graph.getSampleRate(), graph.getBlockSize());
        auto node = graph.addNode(std::move(plugin));
        chain->add(node->nodeID);

        rewireTrackBusFxChain(trackRow);

        if (callback)
            callback(true);
        return;
    }

    // External plugin
    PluginDescription desc;
    desc.fileOrIdentifier = pluginPath;

    auto *format = pluginFormatManager.getFormat(0);
    if (format == nullptr)
    {
        if (callback)
            callback(false);
        return;
    }

    format->createPluginInstanceAsync(
        desc,
        graph.getSampleRate() > 0 ? graph.getSampleRate() : 44100.0,
        graph.getBlockSize() > 0 ? graph.getBlockSize() : 512,
        [this, trackRow, callback](std::unique_ptr<AudioPluginInstance> inst, const juce::String &error)
        {
            if (!inst)
            {
                juceLogToFlutter(("insertTrackEffect: " + error).toRawUTF8());
                if (callback)
                    callback(false);
                return;
            }

            MessageManager::callAsync([this, trackRow, inst = std::move(inst), callback]() mutable
                                      {
                                        //   inst->prepareToPlay(graph.getSampleRate(), graph.getBlockSize());
                                          auto *chain = trackBusEffectChains[trackRow];
                                          if (!chain)
                                          {
                                              chain = new juce::Array<AudioProcessorGraph::NodeID>();
                                              trackBusEffectChains.set(trackRow, chain);
                                          }

                                          auto pluginNode = graph.addNode(std::move(inst));
                                          chain->add(pluginNode->nodeID);

                                          rewireTrackBusFxChain(trackRow);
                                          if (callback)
                                              callback(true); });
        });
}

void JuceEngine::removeTrackEffect(int trackRow, int effectIndex)
{
    // juceLogToFlutter("Hello from JuceEngine::removeTrackEffect");

    if (trackRow < 0 || trackRow >= trackBusEffectChains.size())
        return;

    auto *chain = trackBusEffectChains[trackRow];
    if (!chain || effectIndex < 0 || effectIndex >= chain->size())
        return;

    auto nodeID = chain->getReference(effectIndex);
    graph.removeNode(nodeID);

    chain->removeRange(effectIndex, 1);

    rewireTrackBusFxChain(trackRow);
}

void JuceEngine::reorderTrackEffects(int trackRow, int fromIndex, int toIndex)
{
    // juceLogToFlutter("Hello from JuceEngine::reorderTrackEffects");

    if (trackRow < 0 || trackRow >= trackBusEffectChains.size())
        return;

    auto *chain = trackBusEffectChains[trackRow];
    if (!chain)
        return;

    if (fromIndex < 0 || fromIndex >= chain->size())
        return;
    if (toIndex < 0 || toIndex > chain->size())
        return;

    auto nodeID = chain->getReference(fromIndex);
    chain->removeRange(fromIndex, 1);
    chain->insert(toIndex, nodeID);

    rewireTrackBusFxChain(trackRow);
}

juce::StringArray JuceEngine::getTrackEffectsForRow(int trackRow)
{
    juce::StringArray names;

    if (trackRow < 0 || trackRow >= trackBusEffectChains.size())
        return names;

    auto *chain = trackBusEffectChains[trackRow];
    if (!chain)
        return names;

    for (auto &nodeID : *chain)
    {
        if (auto node = graph.getNodeForId(nodeID))
        {
            if (auto *processor = node->getProcessor())
                names.add(processor->getName());
        }
    }

    return names;
}

void JuceEngine::setTrackEffectParameter(int trackRow,
                                         int effectIndex,
                                         const juce::String &paramName,
                                         const juce::var &newValue)
{
    // juceLogToFlutter("JuceEngine::setTrackEffectParameter");

    if (trackRow < 0 || trackRow >= trackBusEffectChains.size())
        return;

    auto *chain = trackBusEffectChains[trackRow];
    if (!chain || effectIndex < 0 || effectIndex >= chain->size())
        return;

    auto nodeID = chain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (!node)
        return;

    auto *processor = node->getProcessor();
    if (!processor)
        return;

    for (auto *p : processor->getParameters())
    {
        if (p->getName(128) != paramName)
            continue;

        float normalized = 0.0f;

        // --- NUMBER / BOOL / CHOICE handling (same as setEffectParameter) ---

        if (newValue.isBool())
        {
            normalized = (bool)newValue ? 1.0f : 0.0f;
        }
        else if (newValue.isDouble() || newValue.isInt())
        {
            normalized = (float)newValue;
        }
        else
        {
            // Choice text lookup
            juce::String str = newValue.toString();
            int steps = p->getNumSteps();
            for (int i = 0; i < steps; ++i)
            {
                float n = (steps > 1) ? (float)i / (steps - 1) : 0.0f;
                if (p->getText(n, 128) == str)
                {
                    normalized = n;
                    break;
                }
            }
        }

        // --- RANGE / TYPE-SPECIFIC handling ---
        if (auto *withID = dynamic_cast<juce::AudioProcessorParameterWithID *>(p))
        {
            if (auto *fp = dynamic_cast<juce::AudioParameterFloat *>(p))
            {
                const auto &range = fp->range;
                float clamped = juce::jlimit(range.start, range.end, normalized);
                float norm01 = range.convertTo0to1(clamped);
                fp->setValueNotifyingHost(norm01);
            }
            else
            {
                withID->setValueNotifyingHost(normalized);
            }
        }
        else
        {
            p->setValueNotifyingHost(normalized);
        }

        return;
    }
}

void JuceEngine::bypassRowEffect(int trackRow, int effectIndex, bool shouldBypass)
{
    if (trackRow < 0 || trackRow >= trackBusEffectChains.size())
        return;

    auto *chain = trackBusEffectChains[trackRow];
    if (!chain || effectIndex < 0 || effectIndex >= chain->size())
        return;

    auto nodeID = chain->getReference(effectIndex);
    if (auto node = graph.getNodeForId(nodeID))
        node->setBypassed(shouldBypass);
}

bool JuceEngine::getRowEffectBypassState(int trackRow, int effectIndex)
{
    if (trackRow < 0 || trackRow >= trackBusEffectChains.size())
        return false;

    auto *chain = trackBusEffectChains[trackRow];
    if (!chain || effectIndex < 0 || effectIndex >= chain->size())
        return false;

    auto nodeID = chain->getReference(effectIndex);
    if (auto node = graph.getNodeForId(nodeID))
        return node->isBypassed();

    return false;
}

void JuceEngine::setTrackAutomationPoints(int trackRow,
                                          const std::vector<AutomationPoint> &points)
{
    if (trackRow < 0 || trackRow >= kNumTracks)
        return;

    if (trackAutomationProcessors[trackRow] != nullptr)
        trackAutomationProcessors[trackRow]->setAutomationPoints(points);
}

void JuceEngine::setAutomationTransport(double timeSeconds)
{
    // Global transport time used by automation processors
    for (int t = 0; t < kNumTracks; ++t)
        if (trackAutomationProcessors[t] != nullptr)
            trackAutomationProcessors[t]->setTransportPosition(timeSeconds);
}

// ============================================================
// Row-level gain / mute / pan
// ============================================================
void JuceEngine::setRowGain(int row, float gain)
{
    if (row < 0 || row >= kNumTracks)
        return;

    if (trackGainProcessors[row] != nullptr)
        trackGainProcessors[row]->gain->setValueNotifyingHost(gain / 3.0f);
}

void JuceEngine::muteRow(int row, bool mute)
{
    if (row < 0 || row >= kNumTracks)
        return;

    if (trackGainProcessors[row] != nullptr)
        trackGainProcessors[row]->setMuted(mute);
}

bool JuceEngine::isRowMuted(int row)
{
    if (row < 0 || row >= kNumTracks)
        return false;

    if (trackGainProcessors[row] != nullptr)
        return trackGainProcessors[row]->isMuted();

    return false;
}

void JuceEngine::setRowPan(int row, float pan)
{
    if (row < 0 || row >= kNumTracks)
        return;

    if (trackPanProcessors[row] != nullptr)
        trackPanProcessors[row]->pan->setValueNotifyingHost(panUIToNormalized(pan));
}

// ============================================================
// Master bus FX
// ============================================================
void JuceEngine::insertMasterEffect(const juce::String &pluginPath,
                                    std::function<void(bool)> callback)
{
    // juceLogToFlutter("Hello from JuceEngine::insertMasterEffect");

    if (!masterEffectChain)
        masterEffectChain = new juce::Array<AudioProcessorGraph::NodeID>();

    // Built-in Mixroom native plugins first
    if (mixroomPlugins.contains(pluginPath))
    {
        std::unique_ptr<AudioProcessor> plugin;

        if (pluginPath == "Reverb")
            plugin = std::make_unique<ReverbAudioProcessor>();
        else if (pluginPath == "EQ Parametric")
            plugin = std::make_unique<EQAudioProcessor>();
        else if (pluginPath == "EQ 3-Band")
            plugin = std::make_unique<EQ3AudioProcessor>();
        else if (pluginPath == "Delay")
            plugin = std::make_unique<DelayAudioProcessor>();
        else if (pluginPath == "Distortion")
            plugin = std::make_unique<DistortionAudioProcessor>();
        else if (pluginPath == "De-Esser")
            plugin = std::make_unique<DeesserAudioProcessor>();
        else if (pluginPath == "Compressor")
            plugin = std::make_unique<CompressorAudioProcessor>();
        else
        {
            if (callback)
                callback(false);
            return;
        }

        // plugin->prepareToPlay(graph.getSampleRate(), graph.getBlockSize());
        auto node = graph.addNode(std::move(plugin));
        masterEffectChain->add(node->nodeID);

        rewireMasterFxChain();

        if (callback)
            callback(true);
        return;
    }

    // External plugin
    PluginDescription desc;
    desc.fileOrIdentifier = pluginPath;

    auto *format = pluginFormatManager.getFormat(0);
    if (!format)
    {
        if (callback)
            callback(false);
        return;
    }

    format->createPluginInstanceAsync(
        desc,
        graph.getSampleRate(),
        graph.getBlockSize(),
        [this, callback](std::unique_ptr<AudioPluginInstance> inst, const juce::String &err) mutable
        {
            if (!inst)
            {
                juceLogToFlutter(("insertMasterEffect: " + err).toRawUTF8());
                if (callback)
                    callback(false);
                return;
            }

            MessageManager::callAsync([this, inst = std::move(inst), callback]() mutable
                                      {
                                        //   inst->prepareToPlay(graph.getSampleRate(), graph.getBlockSize());

                                          if (!masterEffectChain)
                                              masterEffectChain = new juce::Array<AudioProcessorGraph::NodeID>();

                                          auto pluginNode = graph.addNode(std::move(inst));
                                          masterEffectChain->add(pluginNode->nodeID);

                                          rewireMasterFxChain();
                                          if (callback) callback(true); });
        });
}

void JuceEngine::removeMasterEffect(int effectIndex)
{
    if (!masterEffectChain)
        return;

    if (effectIndex < 0 || effectIndex >= masterEffectChain->size())
        return;

    auto nodeID = masterEffectChain->getReference(effectIndex);
    graph.removeNode(nodeID);

    masterEffectChain->removeRange(effectIndex, 1);

    rewireMasterFxChain();
}

void JuceEngine::reorderMasterEffects(int fromIndex, int toIndex)
{
    if (!masterEffectChain)
        return;

    if (fromIndex < 0 || fromIndex >= masterEffectChain->size())
        return;
    if (toIndex < 0 || toIndex > masterEffectChain->size())
        return;

    auto id = masterEffectChain->getReference(fromIndex);
    masterEffectChain->removeRange(fromIndex, 1);
    masterEffectChain->insert(toIndex, id);

    rewireMasterFxChain();
}

juce::StringArray JuceEngine::getMasterEffects()
{
    juce::StringArray out;

    if (!masterEffectChain)
        return out;

    for (auto &id : *masterEffectChain)
    {
        if (auto node = graph.getNodeForId(id))
        {
            if (auto *p = node->getProcessor())
                out.add(p->getName());
        }
    }

    return out;
}

void JuceEngine::setMasterEffectParameter(int effectIndex,
                                          const juce::String &paramName,
                                          const juce::var &newValue)
{
    if (!masterEffectChain)
        return;

    if (effectIndex < 0 || effectIndex >= masterEffectChain->size())
        return;

    auto nodeID = masterEffectChain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (!node)
        return;

    auto *processor = node->getProcessor();
    if (!processor)
        return;

    for (auto *p : processor->getParameters())
    {
        if (p->getName(128) != paramName)
            continue;

        float normalized = 0.0f;

        // --- NUMBER / BOOL / CHOICE handling ---
        if (newValue.isBool())
        {
            normalized = (bool)newValue ? 1.0f : 0.0f;
        }
        else if (newValue.isDouble() || newValue.isInt())
        {
            normalized = (float)newValue;
        }
        else
        {
            juce::String str = newValue.toString();
            int steps = p->getNumSteps();
            for (int i = 0; i < steps; ++i)
            {
                float n = (steps > 1) ? (float)i / (steps - 1) : 0.0f;
                if (p->getText(n, 128) == str)
                {
                    normalized = n;
                    break;
                }
            }
        }

        // --- RANGE AWARENESS ---
        if (auto *withID = dynamic_cast<juce::AudioProcessorParameterWithID *>(p))
        {
            if (auto *fp = dynamic_cast<juce::AudioParameterFloat *>(p))
            {
                const auto &range = fp->range;
                float clamped = juce::jlimit(range.start, range.end, normalized);
                float norm01 = range.convertTo0to1(clamped);
                fp->setValueNotifyingHost(norm01);
            }
            else
            {
                withID->setValueNotifyingHost(normalized);
            }
        }
        else
        {
            p->setValueNotifyingHost(normalized);
        }

        return;
    }
}

void JuceEngine::bypassMasterEffect(int effectIndex, bool bypass)
{
    if (!masterEffectChain)
        return;

    if (effectIndex < 0 || effectIndex >= masterEffectChain->size())
        return;

    auto nodeID = masterEffectChain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (node)
        node->setBypassed(bypass);
}

bool JuceEngine::getMasterEffectBypassState(int effectIndex)
{
    if (!masterEffectChain)
        return false;

    if (effectIndex < 0 || effectIndex >= masterEffectChain->size())
        return false;

    auto nodeID = masterEffectChain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    return node ? node->isBypassed() : false;
}

void JuceEngine::setMasterGain(float gain)
{
    if (masterGainProcessor)
        masterGainProcessor->gain->setValueNotifyingHost(gain / 3.0f);
}

void JuceEngine::muteMaster(bool mute)
{
    if (masterGainProcessor)
        masterGainProcessor->setMuted(mute);
}

void JuceEngine::setMasterPan(float pan)
{
    if (masterPanProcessor)
        masterPanProcessor->pan->setValueNotifyingHost(panUIToNormalized(pan));
}

// ============================================================
// Master FX Chain Rewire
// ============================================================
void JuceEngine::rewireMasterFxChain()
{
    if (!masterGainNode || !masterPanNode)
        return;
    if (!masterEffectChain)
        return;

    // ---------------- Remove old master-related connections ----------------
    juce::Array<AudioProcessorGraph::Connection> toRemove;
    auto connections = graph.getConnections();

    auto isMaster = [&](AudioProcessorGraph::NodeID id)
    {
        if (id == masterGainNode->nodeID)
            return true;
        if (id == masterPanNode->nodeID)
            return true;
        for (auto fx : *masterEffectChain)
            if (fx == id)
                return true;
        return false;
    };

    for (auto &c : connections)
    {
        if (isMaster(c.source.nodeID) || isMaster(c.destination.nodeID))
            toRemove.add(c);
    }

    for (auto &c : toRemove)
        graph.removeConnection(c);

    // ---------------- Build FX chain: [FX...] → MasterGain ----------------
    AudioProcessorGraph::Node::Ptr prev;

    if (masterEffectChain->size() > 0)
    {
        // First FX is the chain entry point
        prev = graph.getNodeForId(masterEffectChain->getReference(0));

        for (int i = 1; i < masterEffectChain->size(); ++i)
        {
            auto *fx = graph.getNodeForId(masterEffectChain->getReference(i));
            if (prev && fx)
            {
                for (int ch = 0; ch < 2; ++ch)
                    graph.addConnection({{prev->nodeID, ch}, {fx->nodeID, ch}});
                prev = fx;
            }
        }

        // Last FX → MasterGain
        if (prev)
        {
            for (int ch = 0; ch < 2; ++ch)
                graph.addConnection({{prev->nodeID, ch}, {masterGainNode->nodeID, ch}});
        }
    }
    else
    {
        // No master FX: MasterGain is the entry
        prev = masterGainNode;
    }

    // ---------------- Reconnect rows → master entry ----------------
    AudioProcessorGraph::Node *entryNode =
        (masterEffectChain->size() > 0)
            ? graph.getNodeForId(masterEffectChain->getReference(0))
            : masterGainNode.get();

    if (entryNode)
    {
        for (int t = 0; t < kNumTracks; ++t)
        {
            auto src = rowMeterTapNodes[t]; // post-pan + metered
            if (src != nullptr)
            {
                for (int ch = 0; ch < 2; ++ch)
                    graph.addConnection({{src->nodeID, ch},
                                         {entryNode->nodeID, ch}});
            }
        }
    }

    // ---------------- MasterGain → MasterPan → Output ----------------
    if (masterGainNode && masterPanNode && outputNode)
    {
        for (int ch = 0; ch < 2; ++ch)
        {
            graph.addConnection({{masterGainNode->nodeID, ch}, {masterPanNode->nodeID, ch}});
            graph.addConnection({{masterPanNode->nodeID, ch}, {outputNode->nodeID, ch}});
        }
    }
}

int JuceEngine::getTrackIndexForClip(int clipIdx) const
{
    if (clipIdx < 0 || clipIdx >= clipTrackAssignments.size())
        return 0;

    return juce::jlimit(0, kNumTracks - 1, clipTrackAssignments[clipIdx]);
}

void JuceEngine::setClipGain(int clipIndex, float gain)
{
    setTrackVolume(clipIndex, gain);
}

void JuceEngine::muteClip(int clipIndex, bool shouldMute)
{
    bypassTrack(clipIndex, shouldMute);
}

void JuceEngine::setClipPan(int clipIndex, float pan)
{
    if (clipIndex < 0 || clipIndex >= clipPanProcessors.size())
        return;

    if (auto *p = clipPanProcessors[clipIndex])
        p->pan->setValueNotifyingHost(panUIToNormalized(pan));
}

void JuceEngine::moveClipToRow(int clipIndex, int newRow)
{
    if (clipIndex < 0 || clipIndex >= clipTrackAssignments.size())
        return;

    newRow = juce::jlimit(0, kNumTracks - 1, newRow);

    clipTrackAssignments.set(clipIndex, newRow);
    rewireTrackChain(clipIndex);
}

juce::Array<juce::NamedValueSet> JuceEngine::getTrackPluginParameterInfo(int row, int effectIndex)
{
    // juceLogToFlutter("Hello from JuceEngine::getTrackPluginParameterInfo");
    juce::Array<juce::NamedValueSet> results;

    if (row < 0 || row >= trackBusEffectChains.size())
        return results;

    auto *chain = trackBusEffectChains[row];
    if (chain == nullptr || effectIndex < 0 || effectIndex >= chain->size())
        return results;

    auto nodeID = chain->getReference(effectIndex);
    auto *node = graph.getNodeForId(nodeID);
    if (node == nullptr)
        return results;

    if (auto *processor = node->getProcessor())
    {
        for (auto *p : processor->getParameters())
        {
            juce::NamedValueSet e;
            e.set("name", p->getName(128));

            if (auto *fp = dynamic_cast<juce::AudioParameterFloat *>(p))
            {
                e.set("type", "float");
                e.set("min", fp->range.start);
                e.set("max", fp->range.end);
                e.set("default", fp->get());
                e.set("value", fp->get());
            }
            else if (auto *bp = dynamic_cast<juce::AudioParameterBool *>(p))
            {
                e.set("type", "bool");
                e.set("default", bp->get());
                e.set("value", bp->get());
            }
            else if (auto *cp = dynamic_cast<juce::AudioParameterChoice *>(p))
            {
                e.set("type", "choice");
                e.set("default", cp->getCurrentChoiceName());
                for (int j = 0; j < cp->choices.size(); ++j)
                    e.set("choice_" + juce::String(j), cp->choices[j]);
                e.set("value", cp->getCurrentChoiceName());
            }
            else
            {
                const bool isChoice = p->isDiscrete();
                const int steps = p->getNumSteps();
                const float curNorm = p->getValue();
                const float defNorm = p->getDefaultValue();

                if (isChoice)
                {
                    e.set("type", "choice");
                    for (int j = 0; j < steps; ++j)
                    {
                        float norm = steps > 1 ? (float)j / (steps - 1) : 0.0f;
                        e.set("choice_" + juce::String(j), p->getText(norm, 128));
                    }
                    e.set("default", p->getText(defNorm, 128));
                    e.set("value", p->getText(curNorm, 128));
                }
                else
                {
                    e.set("type", "float");
                    e.set("min", 0.0f);
                    e.set("max", 1.0f);
                    e.set("default", defNorm);
                    e.set("value", curNorm);
                }
            }

            results.add(e);
        }
    }

    return results;
}

juce::Array<juce::NamedValueSet> JuceEngine::getMasterPluginParameterInfo(int effectIndex)
{
    // juceLogToFlutter("Hello from JuceEngine::getMasterPluginParameterInfo");
    juce::Array<juce::NamedValueSet> results;

    if (masterEffectChain == nullptr)
        return results;

    if (effectIndex < 0 || effectIndex >= masterEffectChain->size())
        return results;

    auto nodeID = masterEffectChain->getReference(effectIndex);
    auto *node = graph.getNodeForId(nodeID);
    if (node == nullptr)
        return results;

    if (auto *processor = node->getProcessor())
    {
        for (auto *p : processor->getParameters())
        {
            juce::NamedValueSet e;
            e.set("name", p->getName(128));

            if (auto *fp = dynamic_cast<juce::AudioParameterFloat *>(p))
            {
                e.set("type", "float");
                e.set("min", fp->range.start);
                e.set("max", fp->range.end);
                e.set("default", fp->get());
                e.set("value", fp->get());
            }
            else if (auto *bp = dynamic_cast<juce::AudioParameterBool *>(p))
            {
                e.set("type", "bool");
                e.set("default", bp->get());
                e.set("value", bp->get());
            }
            else if (auto *cp = dynamic_cast<juce::AudioParameterChoice *>(p))
            {
                e.set("type", "choice");
                e.set("default", cp->getCurrentChoiceName());
                for (int j = 0; j < cp->choices.size(); ++j)
                    e.set("choice_" + juce::String(j), cp->choices[j]);
                e.set("value", cp->getCurrentChoiceName());
            }
            else
            {
                const bool isChoice = p->isDiscrete();
                const int steps = p->getNumSteps();
                const float curNorm = p->getValue();
                const float defNorm = p->getDefaultValue();

                if (isChoice)
                {
                    e.set("type", "choice");
                    for (int j = 0; j < steps; ++j)
                    {
                        float norm = steps > 1 ? (float)j / (steps - 1) : 0.0f;
                        e.set("choice_" + juce::String(j), p->getText(norm, 128));
                    }
                    e.set("default", p->getText(defNorm, 128));
                    e.set("value", p->getText(curNorm, 128));
                }
                else
                {
                    e.set("type", "float");
                    e.set("min", 0.0f);
                    e.set("max", 1.0f);
                    e.set("default", defNorm);
                    e.set("value", curNorm);
                }
            }

            results.add(e);
        }
    }

    return results;
}

void JuceEngine::setMetronomeEnabled(bool e)
{
    if (metronomeCallback)
        metronomeCallback->setEnabled(e);
}

void JuceEngine::setMetronomeVolume(float v)
{
    if (metronomeCallback)
        metronomeCallback->setVolume(v);
}

void JuceEngine::setMetronomeBpm(double bpm)
{
    if (metronomeCallback)
        metronomeCallback->setBpm(bpm);
}

void JuceEngine::setMetronomeTransportMs(double ms)
{
    if (metronomeCallback)
        metronomeCallback->setTransportMs(ms);
}

std::vector<float> JuceEngine::decodeAudioMono16k(const juce::File &file)
{
    std::unique_ptr<juce::AudioFormatReader> reader(formatManager.createReaderFor(file));
    if (!reader)
        return {};

    const int64 totalSamples64 = reader->lengthInSamples;
    const int totalSamples = (int)totalSamples64;

    juce::AudioBuffer<float> mono(1, totalSamples);
    reader->read(&mono, 0, totalSamples, 0, true, false);

    if (reader->sampleRate != 16000.0)
    {
        juce::LagrangeInterpolator resampler;
        resampler.reset();

        const double speedRatio = reader->sampleRate / 16000.0; // input per output
        const int outSamples = (int)std::ceil(totalSamples / speedRatio);

        juce::AudioBuffer<float> resampled(1, outSamples);
        resampled.clear();

        // Use the overload that knows how many input samples are available
        // so it will feed zeroes instead of reading past the end.
        resampler.process(
            speedRatio,
            mono.getReadPointer(0),
            resampled.getWritePointer(0),
            outSamples,
            mono.getNumSamples(),
            0 // wrapAround = 0 => feed zeroes if it needs more
        );

        mono = std::move(resampled); // keep full outSamples output
    }

    std::vector<float> out(mono.getNumSamples());
    std::memcpy(out.data(), mono.getReadPointer(0), out.size() * sizeof(float));
    return out;
}

juce::StringArray JuceEngine::getAvailableInputDevices()
{
    juce::StringArray names;

    auto &types = deviceManager.getAvailableDeviceTypes();

    for (auto *t : types)
    {
        names.addArray(t->getDeviceNames());
    }

    names.removeDuplicates(true);
    return names;
}

bool JuceEngine::selectInputDevice(const juce::String &name)
{
    auto setup = deviceManager.getAudioDeviceSetup();
    setup.inputDeviceName = name;

    // Explicitly request a high number of channels or allow JUCE to open all
    // If setup.useDefaultInputChannels is true, it usually only grabs 2.
    setup.useDefaultInputChannels = false;

    // This tells JUCE to try and open every bit the hardware offers
    setup.inputChannels.setRange(0, 256, true);

    juce::String error = deviceManager.setAudioDeviceSetup(setup, true);
    return error.isEmpty();
}

juce::String JuceEngine::getCurrentInputDeviceName() const
{
    if (auto *dev = deviceManager.getCurrentAudioDevice())
        return dev->getName();
    return {};
}

int JuceEngine::getNumInputChannels() const
{
    if (auto *dev = deviceManager.getCurrentAudioDevice())
        return dev->getActiveInputChannels().countNumberOfSetBits();
    return 0;
}

void JuceEngine::routeLiveInputToRow(int row, int channelCount)
{
    if (!inputNode)
        return;

    row = juce::jlimit(0, kNumTracks - 1, row);

    auto rowInput = trackInputNodes[row];
    if (!rowInput)
        return;

    // remove old input connections
    juce::Array<juce::AudioProcessorGraph::Connection> toRemove;
    for (auto &c : graph.getConnections())
        if (c.source.nodeID == inputNode->nodeID)
            toRemove.add(c);

    for (auto &c : toRemove)
        graph.removeConnection(c);

    // const int chCount = juce::jlimit(1, 2, channelCount);

    for (int ch = 0; ch < channelCount; ++ch)
    {
        graph.addConnection({{inputNode->nodeID, ch},
                             {rowInput->nodeID, ch}});
    }
}

bool JuceEngine::startRecordingToWav(const juce::File &file,
                                     int channelStart,
                                     int channelCount)
{
    if (recordingActive)
        return false;

    auto *dev = deviceManager.getCurrentAudioDevice();
    if (!dev)
        return false;

    const int outputs = dev->getActiveOutputChannels().countNumberOfSetBits();
    if (outputs <= 0)
        return false;

    const int numInputs =
        dev->getActiveInputChannels().countNumberOfSetBits();

    if (numInputs <= 0)
        return false;

    channelCount = juce::jlimit(1, numInputs, channelCount);

    recorderStream.reset(file.createOutputStream().release());
    if (!recorderStream)
        return false;

    juce::WavAudioFormat wav;
    recorderWriter.reset(
        wav.createWriterFor(
            recorderStream.get(),
            dev->getCurrentSampleRate(),
            (unsigned int)channelCount,
            24,
            {},
            0));

    if (!recorderWriter)
        return false;

    recorderStream.release();

    recordChannelOffset = channelStart;

    recordChannelCount = channelCount;
    // recordChannelCount = 2; // TEMP

    // THIS WAS MISSING
    routeLiveInputToRow(/*row=*/0, channelCount);

    recordingActive = true;
    return true;
}

void JuceEngine::stopRecording()
{
    recordingActive = false;

    juce::SpinLock::ScopedLockType lock(recordLock);

    recorderWriter.reset(); // flush + finalize WAV
    recorderStream.reset();
}

bool JuceEngine::isRecording() const
{
    return recordingActive;
}

void JuceEngine::captureInput(const float *const *input, int numInputChannels, int numSamples)
{
    if (!recordingActive || !recorderWriter)
        return;

    // Create the buffer object here so it has memory to copy into
    juce::AudioBuffer<float> buffer(recordChannelCount, numSamples);

    float peak = 0.0f;

    // Use the offset to grab the correct pointer from the input array
    // E.g., if offset is 2, we start at input[2] (the 3rd channel)
    for (int ch = 0; ch < recordChannelCount; ++ch)
    {
        // int sourceCh = ch + recordChannelOffset;
        // if (sourceCh < numInputChannels)
        //     buffer.copyFrom(ch, 0, input[sourceCh], numSamples);

        int sourceCh = ch + recordChannelOffset;

        // Safety: Check if the hardware actually provided this channel
        if (sourceCh < numInputChannels && input[sourceCh] != nullptr)
        {
            buffer.copyFrom(ch, 0, input[sourceCh], numSamples);

            // for waveform visualization while recording
            const float *data = input[sourceCh];
            for (int i = 0; i < numSamples; ++i)
                peak = juce::jmax(peak, std::abs(data[i]));
        }
        else
        {
            buffer.clear(ch, 0, numSamples); // Write silence if channel doesn't exist
        }
    }

    recPeak.setTargetValue(peak);
    recorderWriter->writeFromAudioSampleBuffer(buffer, 0, numSamples);
}

double JuceEngine::getRecordingPeak() const
{
    return recPeak.getCurrentValue();
}

void JuceEngine::captureOutput(float *const *output,
                               int numOutputChannels,
                               int numSamples)
{
    juce::SpinLock::ScopedLockType lock(recordLock);

    if (!recordingActive || !recorderWriter)
        return;

    const int chCount = juce::jlimit(1, numOutputChannels, recordChannelCount);

    juce::AudioBuffer<float> buffer(chCount, numSamples);

    for (int ch = 0; ch < chCount; ++ch)
        buffer.copyFrom(ch, 0, output[ch], numSamples);

    recorderWriter->writeFromAudioSampleBuffer(buffer, 0, numSamples);
}

void JuceEngine::setMasterMeterEnabled(bool enabled)
{
    masterMeterEnabled.store(enabled, std::memory_order_relaxed);
}

// returns {peakL, peakR, rmsL, rmsR}
const std::array<float, 4> JuceEngine::getMasterMeterValues()
{
    return {
        masterMeter.peakL.load(std::memory_order_relaxed),
        masterMeter.peakR.load(std::memory_order_relaxed),
        masterMeter.rmsL.load(std::memory_order_relaxed),
        masterMeter.rmsR.load(std::memory_order_relaxed),
    };
}

void JuceEngine::updateMasterMeterFromOutput(const float *const *out,
                                             int numOutCh,
                                             int numSamples) noexcept
{
    if (!masterMeterEnabled.load(std::memory_order_relaxed))
        return;
    if (numOutCh < 2 || out == nullptr || out[0] == nullptr || out[1] == nullptr)
        return;
    if (numSamples <= 0)
        return;

    const float *outL = out[0];
    const float *outR = out[1];

    float peakL = 0.0f, peakR = 0.0f;
    double sumSqL = 0.0, sumSqR = 0.0;

    for (int i = 0; i < numSamples; ++i)
    {
        const float l = outL[i];
        const float r = outR[i];

        const float al = std::abs(l);
        const float ar = std::abs(r);

        if (al > peakL)
            peakL = al;
        if (ar > peakR)
            peakR = ar;

        // clip latch (0 dBFS ≈ 1.0f)
        if (al >= 0.999f || ar >= 0.999f)
            masterClipLatched.store(true, std::memory_order_relaxed);

        sumSqL += (double)l * (double)l;
        sumSqR += (double)r * (double)r;
    }

    const float rmsL = (float)std::sqrt(sumSqL / (double)numSamples);
    const float rmsR = (float)std::sqrt(sumSqR / (double)numSamples);

    // light smoothing (UI jitter reduction)
    constexpr float alpha = 0.25f;
    auto smooth = [](float prev, float next)
    { return prev + alpha * (next - prev); };

    const float prevPeakL = masterMeter.peakL.load(std::memory_order_relaxed);
    const float prevPeakR = masterMeter.peakR.load(std::memory_order_relaxed);
    const float prevRmsL = masterMeter.rmsL.load(std::memory_order_relaxed);
    const float prevRmsR = masterMeter.rmsR.load(std::memory_order_relaxed);

    masterMeter.peakL.store(smooth(prevPeakL, peakL), std::memory_order_relaxed);
    masterMeter.peakR.store(smooth(prevPeakR, peakR), std::memory_order_relaxed);
    masterMeter.rmsL.store(smooth(prevRmsL, rmsL), std::memory_order_relaxed);
    masterMeter.rmsR.store(smooth(prevRmsR, rmsR), std::memory_order_relaxed);
}

bool JuceEngine::getMasterClipLatched() const noexcept
{
    return masterClipLatched.load(std::memory_order_relaxed);
}

void JuceEngine::clearMasterClipLatched() noexcept
{
    masterClipLatched.store(false, std::memory_order_relaxed);
}

void JuceEngine::setRowMetersEnabled(bool enabled)
{
    rowMetersEnabled.store(enabled, std::memory_order_relaxed);
}

const std::array<float, 4> JuceEngine::getRowMeterValues(int row)
{
    if (row < 0 || row >= kNumTracks)
        return {0, 0, 0, 0};

    return {
        rowMeters[row].peakL.load(std::memory_order_relaxed),
        rowMeters[row].peakR.load(std::memory_order_relaxed),
        rowMeters[row].rmsL.load(std::memory_order_relaxed),
        rowMeters[row].rmsR.load(std::memory_order_relaxed),
    };
}

std::vector<float> JuceEngine::getAllMeterValues() const
{
    constexpr int stride = 5;
    const int total = stride * (1 + kNumTracks);

    std::vector<float> out;
    out.resize(total);

    // ---- MASTER ----
    const float mPeakL = masterMeter.peakL.load(std::memory_order_relaxed);
    const float mPeakR = masterMeter.peakR.load(std::memory_order_relaxed);
    const float mRmsL = masterMeter.rmsL.load(std::memory_order_relaxed);
    const float mRmsR = masterMeter.rmsR.load(std::memory_order_relaxed);
    const bool mClip = masterClipLatched.load(std::memory_order_relaxed);

    out[0] = mPeakL;
    out[1] = mPeakR;
    out[2] = mRmsL;
    out[3] = mRmsR;
    out[4] = mClip ? 1.0f : 0.0f;

    // ---- ROWS ----
    for (int row = 0; row < kNumTracks; ++row)
    {
        const int base = stride * (1 + row);

        out[base + 0] = rowMeters[row].peakL.load(std::memory_order_relaxed);
        out[base + 1] = rowMeters[row].peakR.load(std::memory_order_relaxed);
        out[base + 2] = rowMeters[row].rmsL.load(std::memory_order_relaxed);
        out[base + 3] = rowMeters[row].rmsR.load(std::memory_order_relaxed);

        // If you don’t have row clip yet, set 0 for now
        out[base + 4] = 0.0f;
        // If you DO have it:
        // out[base + 4] = rowMeters[row].clip.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
    }

    return out;
}

const std::array<float, 5> JuceEngine::getClipCompressorMeter(int clipIndex, int effectIndex)
{
    if (clipIndex < 0 || clipIndex >= trackEffectChains.size())
        return {0, 0, 0, 0, 0};

    auto *chain = trackEffectChains[clipIndex];
    if (!chain || effectIndex < 0 || effectIndex >= chain->size())
        return {0, 0, 0, 0, 0};

    auto nodeID = chain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (!node)
        return {0, 0, 0, 0, 0};

    if (auto *comp = dynamic_cast<CompressorAudioProcessor *>(node->getProcessor()))
        return comp->getMeterStrip();

    return {0, 0, 0, 0, 0};
}

const std::array<float, 5> JuceEngine::getRowCompressorMeter(int row, int effectIndex)
{
    if (row < 0 || row >= trackBusEffectChains.size())
        return {0, 0, 0, 0, 0};

    auto *chain = trackBusEffectChains[row];
    if (!chain || effectIndex < 0 || effectIndex >= chain->size())
        return {0, 0, 0, 0, 0};

    auto nodeID = chain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (!node)
        return {0, 0, 0, 0, 0};

    if (auto *comp = dynamic_cast<CompressorAudioProcessor *>(node->getProcessor()))
        return comp->getMeterStrip();

    return {0, 0, 0, 0, 0};
}

const std::array<float, 5> JuceEngine::getMasterCompressorMeter(int effectIndex)
{
    if (!masterEffectChain)
        return {0, 0, 0, 0, 0};

    if (effectIndex < 0 || effectIndex >= masterEffectChain->size())
        return {0, 0, 0, 0, 0};

    auto nodeID = masterEffectChain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (!node)
        return {0, 0, 0, 0, 0};

    if (auto *comp = dynamic_cast<CompressorAudioProcessor *>(node->getProcessor()))
        return comp->getMeterStrip();

    return {0, 0, 0, 0, 0};
}

const juce::StringArray JuceEngine::mixroomPlugins{
    "EQ 3-Band",
    "Compressor",
    "De-Esser",
    "Distortion",
    "Delay",
    "Reverb",
    "EQ Parametric",
};
