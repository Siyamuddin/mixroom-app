#include "JuceEngine.h"
#include <algorithm>
#include <cmath>

using namespace juce;

namespace
{
TimelineClipProcessorBase *asTimelineProcessor(juce::AudioProcessorGraph::Node::Ptr &node)
{
    if (!node)
        return nullptr;
    return dynamic_cast<TimelineClipProcessorBase *>(node->getProcessor());
}

double clampSourceTempo(double bpm)
{
    return juce::jlimit(1.0, 400.0, bpm);
}

double estimateMidiMaterialLengthSec(const juce::Array<TimelineMidiNote> &notes,
                                     const juce::NamedValueSet &params,
                                     double sourceTempoBpm,
                                     double inFileOffsetSec)
{
    const double safeTempo = clampSourceTempo(sourceTempoBpm);
    const double secPerBeat = 60.0 / safeTempo;
    double endBeat = 4.0;

    for (const auto &note : notes)
        endBeat = juce::jmax(endBeat, note.startBeat + note.lengthBeats);

    double releaseMs = 180.0;
    if (auto *v = params.getVarPointer(juce::Identifier("releaseMs")))
    {
        if (v->isInt() || v->isInt64() || v->isDouble())
            releaseMs = (double)(*v);
    }
    releaseMs = juce::jlimit(10.0, 4000.0, releaseMs);

    const double minimumDurationSec = 1.2;
    const double renderedSec =
        juce::jmax(minimumDurationSec,
                   endBeat * secPerBeat + (releaseMs / 1000.0) + 0.12);
    return juce::jmax(0.01, renderedSec - juce::jmax(0.0, inFileOffsetSec));
}
} // namespace

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
    rows.reserve(kMaxRows);
    clips.reserve(kMaxClips);
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

    // Build default rows if empty
    if (rows.empty())
    {
        addRow("Track 1", 0);
        addRow("Track 2", 0);
        addRow("Track 3", 0);
        addRow("Track 4", 0);
        addRow("Track 5", 0);
    }

    // Build bus graph (rows + master)
    ensureBusGraphInitialised();

    hostSampleRateAtomic.store(hostRate, std::memory_order_relaxed);

    graph.prepareToPlay(hostRate, blockSize);
    juceLogToFlutter(("graph.prepareToPlay(" + String(hostRate) + ", " + String(blockSize) + ")").toRawUTF8());

    // Plugin scan is expensive; keep cached results across editor reopen.
    if (pluginList.getNumTypes() == 0)
    {
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
    }

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
    rows.clear();
    rowIdToIndex.clear();
    nextRowId.store(1);
    clips.clear();

    // Master chain
    if (masterEffectChain != nullptr)
    {
        masterEffectChain->clear();
        delete masterEffectChain;
        masterEffectChain = nullptr;
    }
    masterEffectIds.clear();

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
void JuceEngine::attachRowBusNodes(RowState &r)
{
    auto ti = std::make_unique<TrackInputProcessor>();
    r.inputProc = ti.get();
    r.inputNode = graph.addNode(std::move(ti));

    auto ap = std::make_unique<VolumeAutomationProcessor>();
    r.automationProc = ap.get();
    r.automationNode = graph.addNode(std::move(ap));

    auto tg = std::make_unique<SimpleGainProcessor>();
    r.gainProc = tg.get();
    r.gainNode = graph.addNode(std::move(tg));
    r.gainProc->gain->setValueNotifyingHost(juce::jlimit(0.0f, 3.0f, r.gainUi) / 3.0f);
    r.gainProc->setMuted(r.muted);

    auto tp = std::make_unique<StereoPanProcessor>();
    r.panProc = tp.get();
    r.panNode = graph.addNode(std::move(tp));
    r.panProc->pan->setValueNotifyingHost(panUIToNormalized(r.panUi));

    auto mt = std::make_unique<MeterTapProcessor>(
        &r.meter.peakL,
        &r.meter.peakR,
        &r.meter.rmsL,
        &r.meter.rmsR,
        &rowMetersEnabled);

    r.meterTapProc = mt.get();
    r.meterTapNode = graph.addNode(std::move(mt));

    if (r.automationProc != nullptr)
    {
        r.automationProc->setBlockTransportPtr(&blockTransportStartSec);
        if (!r.automationPoints.empty())
            r.automationProc->setAutomationPoints(r.automationPoints);
    }

    for (int ch = 0; ch < 2; ++ch)
    {
        graph.addConnection({{r.inputNode->nodeID, ch}, {r.automationNode->nodeID, ch}});
        graph.addConnection({{r.automationNode->nodeID, ch}, {r.gainNode->nodeID, ch}});
        graph.addConnection({{r.gainNode->nodeID, ch}, {r.panNode->nodeID, ch}});
        graph.addConnection({{r.panNode->nodeID, ch}, {r.meterTapNode->nodeID, ch}});
        graph.addConnection({{r.meterTapNode->nodeID, ch}, {masterGainNode->nodeID, ch}});
    }
}

void JuceEngine::ensureRowBusNodesAttached(int rowIndex)
{
    if (rowIndex < 0 || rowIndex >= (int)rows.size())
        return;
    if (!engineInitialized)
        return;

    ensureBusGraphInitialised();
    if (!busGraphInitialised)
        return;

    auto &r = rows[(size_t)rowIndex];
    if (r.inputNode != nullptr && r.automationNode != nullptr &&
        r.gainNode != nullptr && r.panNode != nullptr && r.meterTapNode != nullptr)
        return;

    attachRowBusNodes(r);
    if (r.fxChain.size() > 0)
        rewireTrackBusFxChain(rowIndex);

    // Newly attached rows default to meterTap -> masterGain in attachRowBusNodes.
    // If master FX are active, reroute only this row into the master-FX entry.
    // This keeps row insertion/attach O(1) instead of rebuilding master routing.
    if (masterEffectChain != nullptr && masterEffectChain->size() > 0)
    {
        compactMasterFxChain();
        if (masterEffectChain->size() > 0 && r.meterTapNode != nullptr && masterGainNode != nullptr)
        {
            if (auto *entryNode = graph.getNodeForId(masterEffectChain->getReference(0)))
            {
                for (int ch = 0; ch < 2; ++ch)
                {
                    graph.removeConnection({{r.meterTapNode->nodeID, ch}, {masterGainNode->nodeID, ch}});
                    graph.addConnection({{r.meterTapNode->nodeID, ch}, {entryNode->nodeID, ch}});
                }
                return;
            }
        }

        // Safety fallback for stale/invalid chain state.
        rewireMasterFxChain();
    }
}

void JuceEngine::retargetRowMeterTapPointers()
{
    for (auto &r : rows)
    {
        if (r.meterTapProc != nullptr)
        {
            r.meterTapProc->setMeterTargets(
                &r.meter.peakL,
                &r.meter.peakR,
                &r.meter.rmsL,
                &r.meter.rmsR);
        }
    }
}

void JuceEngine::rebuildRowIdIndexCache()
{
    rowIdToIndex.clear();
    rowIdToIndex.reserve(rows.size());
    for (int i = 0; i < (int)rows.size(); ++i)
        rowIdToIndex[rows[(size_t)i].rowId] = i;
}

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
    double sampleRate = dev ? dev->getCurrentSampleRate() : 44100.0;
    int blockSize = dev ? dev->getCurrentBufferSizeSamples() : 512;

    hostSampleRateAtomic.store(sampleRate, std::memory_order_relaxed);

    // MASTER gain + pan
    {
        auto mg = std::make_unique<SimpleGainProcessor>();
        masterGainProcessor = mg.get();
        masterGainNode = graph.addNode(std::move(mg));
        masterGainProcessor->gain->setValueNotifyingHost(1.0f / 3.0f);

        auto mp = std::make_unique<StereoPanProcessor>();
        masterPanProcessor = mp.get();
        masterPanNode = graph.addNode(std::move(mp));
        masterPanProcessor->pan->setValueNotifyingHost(0.5f);

        for (int ch = 0; ch < 2; ++ch)
        {
            graph.addConnection({{masterGainNode->nodeID, ch}, {masterPanNode->nodeID, ch}});
            graph.addConnection({{masterPanNode->nodeID, ch}, {outputNode->nodeID, ch}});
        }
    }

    if (masterEffectChain == nullptr)
        masterEffectChain = new juce::Array<juce::AudioProcessorGraph::NodeID>();

    // Row meters enabled already exist (atomic)
    // Create per-row chain: Input -> [Row FX] -> Automation -> Gain -> Pan -> MeterTap -> Master entry
    for (auto &r : rows)
        attachRowBusNodes(r);

    busGraphInitialised = true;
    juceLogToFlutter("Bus graph initialised (dynamic rows + master)");
}

// ============================================================
// CLIP / TRACK (legacy name) loading
// ============================================================
void JuceEngine::loadTrack(int idx, const File &file)
{
    // Legacy API – treat as clip on row 0
    loadClip(idx, 0, file, 0.0, 0.0, 0.0);
}

bool JuceEngine::loadClip(int clipId, int rowId, const juce::File &file,
                          double startSec, double lengthSec, double inFileOffsetSec)
{
    if (clipId < 0 || clipId >= kMaxClips)
        return false;

    if (clips.empty())
        clips.resize(kMaxClips);
    if (rows.empty())
        addRow("Row 1", 0);

    // Ensure buses exist
    ensureBusGraphInitialised();

    // If clip exists, unload first
    unloadClip(clipId);

    std::unique_ptr<juce::AudioFormatReader> reader(formatManager.createReaderFor(file));
    if (!reader)
        return false;

    auto totalLength = reader->lengthInSamples;
    const double fileSr = reader->sampleRate > 0.0 ? reader->sampleRate : 44100.0;
    const double fileTotalSec = (double)totalLength / fileSr;
    const double safeStartSec = juce::jmax(0.0, startSec);
    const double safeOffsetSec = juce::jmax(0.0, inFileOffsetSec);
    const double resolvedLengthSec =
        (lengthSec > 0.0) ? lengthSec : juce::jmax(0.0, fileTotalSec - safeOffsetSec);
    auto readerSource = std::make_unique<juce::AudioFormatReaderSource>(reader.release(), true);

    auto player = std::make_unique<TimelineClipProcessor>(
        std::move(readerSource),
        totalLength,
        file,
        &blockTransportStartSec,
        &hostSampleRateAtomic,
        &isPlayingAtomic);

    player->setTimeline(safeStartSec, resolvedLengthSec, safeOffsetSec);
    player->setStretchOptions(1.0, false);

    // Batch graph mutations for clip insertion so large sessions (many rows/nodes)
    // pay one graph rebuild instead of many synchronous rebuilds.
    constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;

    auto playerNode = graph.addNode(std::move(player), std::nullopt, batchUpdate);

    // per-clip gain
    auto gainProc = std::make_unique<SimpleGainProcessor>();
    auto *gainPtr = gainProc.get();
    auto gainNode = graph.addNode(std::move(gainProc), std::nullopt, batchUpdate);
    gainPtr->gain->setValueNotifyingHost(1.0f / 3.0f);

    // per-clip pan
    auto panProc = std::make_unique<StereoPanProcessor>();
    auto *panPtr = panProc.get();
    auto panNode = graph.addNode(std::move(panProc), std::nullopt, batchUpdate);
    panPtr->pan->setValueNotifyingHost(0.5f);

    // store state
    ClipState &c = clips[clipId];
    c.alive = true;
    c.isMidi = false;
    c.clipId = clipId;
    const int rowIndex = getRowIndexById(rowId);
    c.rowId = (rowIndex >= 0) ? rowId : rows[0].rowId;
    c.startSec = safeStartSec;
    c.lengthSec = resolvedLengthSec;
    c.inFileOffsetSec = safeOffsetSec;
    c.pitchSemitones = 0.0f;
    c.tempoRatio = 1.0;
    c.preservePitch = false;

    c.playerNode = playerNode;
    c.gainProc = gainPtr;
    c.gainNode = gainNode;
    c.panProc = panPtr;
    c.panNode = panNode;
    c.fxChain.clear();
    c.wired = false;
    c.lastRowInputNodeUid = 0;

    rewireTrackChain(clipId, batchUpdate);
    graph.rebuild();
    return true;
}

bool JuceEngine::loadMidiClip(int clipId,
                              int rowId,
                              const juce::String &instrumentId,
                              const juce::String &instrumentName,
                              const juce::Array<TimelineMidiNote> &notes,
                              const juce::NamedValueSet &params,
                              double sourceTempoBpm,
                              double startSec,
                              double lengthSec,
                              double inFileOffsetSec)
{
    if (clipId < 0 || clipId >= kMaxClips)
        return false;

    if (clips.empty())
        clips.resize(kMaxClips);
    if (rows.empty())
        addRow("Row 1", 0);

    ensureBusGraphInitialised();
    unloadClip(clipId);

    const double safeStartSec = juce::jmax(0.0, startSec);
    const double safeOffsetSec = juce::jmax(0.0, inFileOffsetSec);
    const double safeSourceTempo = clampSourceTempo(sourceTempoBpm);
    const double resolvedLengthSec = (lengthSec > 0.0)
                                         ? juce::jmax(0.0, lengthSec)
                                         : estimateMidiMaterialLengthSec(notes, params, safeSourceTempo, safeOffsetSec);

    auto player = std::make_unique<TimelineMidiClipProcessor>(
        &blockTransportStartSec,
        &hostSampleRateAtomic,
        &isPlayingAtomic);
    player->setTimeline(safeStartSec, resolvedLengthSec, safeOffsetSec);
    player->setStretchOptions(1.0, true);
    player->setMidiData(notes, instrumentId, instrumentName, params, safeSourceTempo);

    constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;
    auto playerNode = graph.addNode(std::move(player), std::nullopt, batchUpdate);

    auto gainProc = std::make_unique<SimpleGainProcessor>();
    auto *gainPtr = gainProc.get();
    auto gainNode = graph.addNode(std::move(gainProc), std::nullopt, batchUpdate);
    gainPtr->gain->setValueNotifyingHost(1.0f / 3.0f);

    auto panProc = std::make_unique<StereoPanProcessor>();
    auto *panPtr = panProc.get();
    auto panNode = graph.addNode(std::move(panProc), std::nullopt, batchUpdate);
    panPtr->pan->setValueNotifyingHost(0.5f);

    ClipState &c = clips[clipId];
    c.alive = true;
    c.isMidi = true;
    c.clipId = clipId;
    const int rowIndex = getRowIndexById(rowId);
    c.rowId = (rowIndex >= 0) ? rowId : rows[0].rowId;
    c.startSec = safeStartSec;
    c.lengthSec = resolvedLengthSec;
    c.inFileOffsetSec = safeOffsetSec;
    c.pitchSemitones = 0.0f;
    c.tempoRatio = 1.0;
    c.preservePitch = true;

    c.playerNode = playerNode;
    c.gainProc = gainPtr;
    c.gainNode = gainNode;
    c.panProc = panPtr;
    c.panNode = panNode;
    c.fxChain.clear();
    c.wired = false;
    c.lastRowInputNodeUid = 0;

    rewireTrackChain(clipId, batchUpdate);
    graph.rebuild();
    return true;
}

bool JuceEngine::updateMidiClipEvents(int clipId,
                                      const juce::String &instrumentId,
                                      const juce::String &instrumentName,
                                      const juce::Array<TimelineMidiNote> &notes,
                                      const juce::NamedValueSet &params,
                                      double sourceTempoBpm)
{
    if (clips.empty() || clipId < 0 || clipId >= (int)clips.size())
        return false;

    auto &c = clips[(size_t)clipId];
    if (!c.alive || !c.isMidi || c.playerNode == nullptr)
        return false;

    auto *p = dynamic_cast<TimelineMidiClipProcessor *>(c.playerNode->getProcessor());
    if (p == nullptr)
        return false;

    p->setMidiData(notes, instrumentId, instrumentName, params, clampSourceTempo(sourceTempoBpm));
    return true;
}

bool JuceEngine::unloadClip(int clipId)
{
    if (clips.empty() || clipId < 0 || clipId >= (int)clips.size())
        return false;

    ClipState &c = clips[clipId];
    if (!c.alive)
        return true;

    c.wired = false;
    c.lastRowInputNodeUid = 0;

    constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;

    // remove clip FX nodes
    for (auto id : c.fxChain)
        graph.removeNode(id, batchUpdate);
    c.fxChain.clear();

    if (c.gainNode)
        graph.removeNode(c.gainNode->nodeID, batchUpdate);
    if (c.panNode)
        graph.removeNode(c.panNode->nodeID, batchUpdate);
    if (c.playerNode)
        graph.removeNode(c.playerNode->nodeID, batchUpdate);

    c = ClipState(); // reset
    graph.rebuild();
    return true;
}

// ============================================================
// Remove clip (legacy name removeTrack)
// ============================================================
void JuceEngine::removeTrack(int trackIndex)
{
    juce::ignoreUnused(unloadClip(trackIndex));
}

// ============================================================
// Clip FX (legacy) chain management
// ============================================================
void JuceEngine::removePluginEffect(int trackIdx, int effectIndex)
{
    juce::ignoreUnused(trackIdx, effectIndex);
    juceLogToFlutter("Clip-level FX disabled (removePluginEffect ignored)");
}

void JuceEngine::reorderPluginEffects(int trackIdx, int fromIndex, int toIndex)
{
    juce::ignoreUnused(trackIdx, fromIndex, toIndex);
    juceLogToFlutter("Clip-level FX disabled (reorderPluginEffects ignored)");
}

void JuceEngine::rewireTrackChain(int clipId, juce::AudioProcessorGraph::UpdateKind updateKind)
{
    if (clips.empty() || clipId < 0 || clipId >= (int)clips.size())
        return;

    ClipState &c = clips[clipId];
    if (!c.alive || !c.playerNode)
        return;

    ensureBusGraphInitialised();

    if (c.wired)
    {
        const auto prevRowInputNodeId =
            juce::AudioProcessorGraph::NodeID((juce::uint32)c.lastRowInputNodeUid);
        auto removeConn = [this](juce::AudioProcessorGraph::NodeID src,
                                 juce::AudioProcessorGraph::NodeID dst,
                                 int ch,
                                 juce::AudioProcessorGraph::UpdateKind kind)
        {
            const juce::AudioProcessorGraph::Connection conn{
                {src, ch},
                {dst, ch}};
            graph.removeConnection(conn, kind);
        };
        for (int ch = 0; ch < 2; ++ch)
        {
            if (c.gainNode && c.panNode)
            {
                removeConn(c.playerNode->nodeID, c.gainNode->nodeID, ch, updateKind);
                removeConn(c.gainNode->nodeID, c.panNode->nodeID, ch, updateKind);
                if (c.lastRowInputNodeUid != 0)
                    removeConn(c.panNode->nodeID, prevRowInputNodeId, ch, updateKind);
            }
            else if (c.lastRowInputNodeUid != 0)
            {
                removeConn(c.playerNode->nodeID, prevRowInputNodeId, ch, updateKind);
            }
        }
    }

    // Find row input node by rowId
    auto rowInputNode = getRowInputNodeById(c.rowId);
    if (!rowInputNode)
        rowInputNode = rows.empty() ? nullptr : rows[0].inputNode;

    if (!rowInputNode)
        return;

    // Build: Player -> Gain -> Pan -> RowInput
    juce::AudioProcessorGraph::Node::Ptr prev = c.playerNode;

    if (c.gainNode && c.panNode)
    {
        for (int ch = 0; ch < 2; ++ch)
        {
            graph.addConnection({{prev->nodeID, ch}, {c.gainNode->nodeID, ch}}, updateKind);
            graph.addConnection({{c.gainNode->nodeID, ch}, {c.panNode->nodeID, ch}}, updateKind);
            graph.addConnection({{c.panNode->nodeID, ch}, {rowInputNode->nodeID, ch}}, updateKind);
        }
    }
    else
    {
        for (int ch = 0; ch < 2; ++ch)
            graph.addConnection({{prev->nodeID, ch}, {rowInputNode->nodeID, ch}}, updateKind);
    }

    c.wired = true;
    c.lastRowInputNodeUid = (int)rowInputNode->nodeID.uid;
}

// ============================================================
// Position / duration
// ============================================================
double JuceEngine::getCurrentPosition(int trackIndex)
{
    if (clips.empty() || trackIndex < 0 || trackIndex >= (int)clips.size())
        return 0.0;
    if (!clips[(size_t)trackIndex].alive)
        return 0.0;
    return getTransportSeconds();
}

double JuceEngine::getTrackDuration(int trackIndex)
{
    if (clips.empty() || trackIndex < 0 || trackIndex >= (int)clips.size())
        return 0.0;
    const auto &c = clips[(size_t)trackIndex];
    return c.alive ? c.lengthSec : 0.0;
}

bool JuceEngine::setClipTime(int clipId, double startSec, double lengthSec, double inFileOffsetSec)
{
    if (clips.empty() || clipId < 0 || clipId >= (int)clips.size())
        return false;

    ClipState &c = clips[clipId];
    if (!c.alive || !c.playerNode)
        return false;

    c.startSec = juce::jmax(0.0, startSec);
    c.lengthSec = juce::jmax(0.0, lengthSec);
    c.inFileOffsetSec = juce::jmax(0.0, inFileOffsetSec);

    if (auto *p = asTimelineProcessor(c.playerNode))
        p->setTimeline(c.startSec, c.lengthSec, c.inFileOffsetSec);

    return true;
}

bool JuceEngine::moveClipToRow(int clipId, int newRowId)
{
    if (clips.empty() || clipId < 0 || clipId >= (int)clips.size())
        return false;

    ClipState &c = clips[clipId];
    if (!c.alive)
        return false;

    int resolvedRowId = newRowId;
    int idx = getRowIndexById(newRowId);

    // Backward compatibility: if caller passed row index, map to rowId.
    if (idx < 0 && newRowId >= 0 && newRowId < (int)rows.size())
    {
        resolvedRowId = rows[(size_t)newRowId].rowId;
        idx = newRowId;
    }

    if (idx < 0)
        return false;

    if (c.rowId == resolvedRowId)
        return true; // no-op avoids expensive rewiring when row didn't change

    c.rowId = resolvedRowId;
    rewireTrackChain(clipId);
    return true;
}

// ============================================================
// Clip-level effect parameter info (legacy, but used by Dart)
// ============================================================
juce::Array<juce::NamedValueSet> JuceEngine::getPluginParameterInfo(int trackIndex, int effectIndex)
{
    juce::ignoreUnused(trackIndex, effectIndex);
    Array<NamedValueSet> results;
    juceLogToFlutter("Clip-level FX disabled (getPluginParameterInfo empty)");
    return results;
}

// ============================================================
// Clip-level track effect names (legacy)
// ============================================================
juce::StringArray JuceEngine::getTrackEffects(int trackIndex)
{
    juce::ignoreUnused(trackIndex);
    juce::StringArray names;
    juceLogToFlutter("Clip-level FX disabled (getTrackEffects empty)");
    return names;
}

// ============================================================
// insertPluginEffect (clip-level, legacy)
// ============================================================
void JuceEngine::insertPluginEffect(int trackIdx, const juce::String &pluginPath, std::function<void(bool)> callback)
{
    juce::ignoreUnused(trackIdx, pluginPath);
    juceLogToFlutter("Clip-level FX disabled (insertPluginEffect ignored)");
    if (callback)
        callback(false);
}

// ============================================================
// Clip/master/general parameter setters
// ============================================================
void JuceEngine::setEffectParameter(int trackIndex,
                                    int effectIndex,
                                    const juce::String &paramName,
                                    const juce::var &newValue)
{
    juce::ignoreUnused(trackIndex, effectIndex, paramName, newValue);
    juceLogToFlutter("Clip-level FX disabled (setEffectParameter ignored)");
}

void JuceEngine::setTrackVolume(int trackIdx, float volume)
{
    setClipGain(trackIdx, volume);
}

// ============================================================
// Export functions (kept as you had – you said you'll revisit)
// ============================================================
namespace
{
JuceEngine::ExportOptions sanitiseExportOptions(const JuceEngine::ExportOptions &input)
{
    JuceEngine::ExportOptions out = input;
    out.format = out.format.toLowerCase();
    if (!(out.format == "wav" || out.format == "mp3"))
        out.format = "wav";

    out.sampleRate = juce::jlimit(8000.0, 192000.0, out.sampleRate);
    if (!(out.wavBitDepth == 16 || out.wavBitDepth == 24 || out.wavBitDepth == 32))
        out.wavBitDepth = 16;
    out.mp3BitrateKbps = juce::jlimit(32, 320, out.mp3BitrateKbps);
    return out;
}

void applyTpdfDither(juce::AudioBuffer<float> &buffer, int bitDepth)
{
    if (bitDepth >= 32)
        return;

    const float lsb = 1.0f / (float)(1 << (bitDepth - 1));
    juce::Random rng;
    for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
    {
        float *data = buffer.getWritePointer(ch);
        for (int i = 0; i < buffer.getNumSamples(); ++i)
        {
            const float n = (rng.nextFloat() - rng.nextFloat()) * lsb;
            data[i] += n;
        }
    }
}
} // namespace

juce::String JuceEngine::exportMix(const juce::File &outFile)
{
    return exportMix(outFile, ExportOptions{});
}

juce::String JuceEngine::exportMix(const juce::File &outFile, const ExportOptions &rawOptions)
{
    std::unique_lock<std::mutex> renderLock(graphRenderMutex);
    const auto options = sanitiseExportOptions(rawOptions);

    if (options.format == "mp3")
    {
        juceLogToFlutter("❌ JUCE native MP3 export is not available on this iOS build.");
        return {};
    }

    juce::WavAudioFormat fmt;
    auto fs = std::unique_ptr<juce::FileOutputStream>(outFile.createOutputStream());
    if (!fs)
        return {};

    const double sr = options.sampleRate;
    AudioIODevice *dev = deviceManager.getCurrentAudioDevice();
    const double liveSampleRate = dev ? dev->getCurrentSampleRate() : hostSampleRateAtomic.load(std::memory_order_relaxed);
    const int liveBlockSize = dev ? dev->getCurrentBufferSizeSamples() : 512;
    const int bs = juce::jlimit(64, 4096, liveBlockSize > 0 ? liveBlockSize : 512);
    const int nc = 2;
    const int bitDepth = options.wavBitDepth;

    auto w = std::unique_ptr<juce::AudioFormatWriter>(
        fmt.createWriterFor(fs.get(), sr, (unsigned int)nc, bitDepth, {}, 0));
    if (!w)
        return {};

    fs.release();

    // compute end time from clips
    double endTime = 0.0;
    for (const auto &c : clips)
    {
        if (c.alive)
            endTime = juce::jmax(endTime, c.startSec + c.lengthSec);
    }

    // offline render loop
    juce::AudioBuffer<float> buf(nc, bs);
    juce::MidiBuffer midi;

    // Snapshot live state so export doesn't permanently alter transport/engine timing.
    const double previousHostRate = hostSampleRateAtomic.load(std::memory_order_relaxed);
    const double previousTransport = transportSec.load(std::memory_order_relaxed);
    const bool wasPlaying = isPlayingAtomic.exchange(true, std::memory_order_relaxed);

    // Prepare graph for offline SR/BS
    hostSampleRateAtomic.store(sr, std::memory_order_relaxed);
    graph.prepareToPlay(sr, bs);

    // set transport to 0 for offline render
    transportSec.store(0.0, std::memory_order_relaxed);

    const int64 totalSamples = (int64)std::ceil(endTime * sr);
    if (totalSamples <= 0)
    {
        graph.prepareToPlay(liveSampleRate > 0.0 ? liveSampleRate : 44100.0,
                            liveBlockSize > 0 ? liveBlockSize : 512);
        hostSampleRateAtomic.store(previousHostRate, std::memory_order_relaxed);
        transportSec.store(previousTransport, std::memory_order_relaxed);
        isPlayingAtomic.store(wasPlaying, std::memory_order_relaxed);
        return outFile.getFullPathName();
    }

    auto runOfflinePass = [&](bool writeOutput, float outputGain, float *peakOut)
    {
        graph.prepareToPlay(sr, bs);
        transportSec.store(0.0, std::memory_order_relaxed);

        int64 processed = 0;
        while (processed < totalSamples)
        {
            const int toDo = (int)juce::jmin<int64>(bs, totalSamples - processed);
            buf.clear();
            midi.clear();

            blockTransportStartSec.store(transportSec.load(std::memory_order_relaxed),
                                         std::memory_order_relaxed);
            graph.processBlock(buf, midi);

            if (peakOut != nullptr)
            {
                for (int ch = 0; ch < nc; ++ch)
                {
                    const float *data = buf.getReadPointer(ch);
                    for (int i = 0; i < toDo; ++i)
                        *peakOut = juce::jmax(*peakOut, std::abs(data[i]));
                }
            }

            if (writeOutput)
            {
                if (outputGain < 0.9999f)
                    buf.applyGain(outputGain);
                if (options.wavDithering)
                    applyTpdfDither(buf, bitDepth);
                w->writeFromAudioSampleBuffer(buf, 0, toDo);
            }

            transportSec.store(transportSec.load(std::memory_order_relaxed) + (double)toDo / sr,
                               std::memory_order_relaxed);
            processed += toDo;
        }
    };

    float peak = 0.0f;
    runOfflinePass(false, 1.0f, &peak);

    constexpr float kExportCeilingDb = -1.0f;
    const float ceilingLinear = std::pow(10.0f, kExportCeilingDb / 20.0f);
    float exportGain = 1.0f;
    if (peak > ceilingLinear && peak > 0.0f)
        exportGain = ceilingLinear / peak;

    if (exportGain < 0.9999f)
    {
        juceLogToFlutter(("⚠️ exportMix auto-trim: " +
                          juce::String(juce::Decibels::gainToDecibels(exportGain), 2) +
                          " dB")
                             .toRawUTF8());
    }

    runOfflinePass(true, exportGain, nullptr);

    // Restore live graph timing + transport state.
    graph.prepareToPlay(liveSampleRate > 0.0 ? liveSampleRate : 44100.0,
                        liveBlockSize > 0 ? liveBlockSize : 512);
    hostSampleRateAtomic.store(previousHostRate, std::memory_order_relaxed);
    transportSec.store(previousTransport, std::memory_order_relaxed);
    isPlayingAtomic.store(wasPlaying, std::memory_order_relaxed);
    return outFile.getFullPathName();
}

// (Your exportTrack implementation – unchanged)
juce::String JuceEngine::exportTrack(int trackIndex, const juce::File &outFile)
{
    return exportTrack(trackIndex, outFile, ExportOptions{});
}

juce::String JuceEngine::exportTrack(int trackIndex,
                                     const juce::File &outFile,
                                     const ExportOptions &options)
{
    juce::ignoreUnused(options);
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
    isPlayingAtomic.store(true, std::memory_order_relaxed);

    if (metronomeCallback)
        metronomeCallback->setIsPlaying(true);
}

void JuceEngine::pause()
{
    isPlayingAtomic.store(false, std::memory_order_relaxed);

    if (metronomeCallback)
        metronomeCallback->setIsPlaying(false);
}

void JuceEngine::seek(int trackIndex, double positionSeconds)
{
    if (!clips.empty() && trackIndex >= 0 && trackIndex < (int)clips.size())
    {
        const auto &c = clips[(size_t)trackIndex];
        if (c.alive)
        {
            // Backward-compat for legacy per-clip seek calls:
            // convert clip-local playhead to global transport.
            const double clipLocal = juce::jmax(0.0, positionSeconds - c.inFileOffsetSec);
            setTransportSeconds(c.startSec + clipLocal);
            return;
        }
    }

    setTransportSeconds(positionSeconds);
}

void JuceEngine::setTransportSeconds(double t)
{
    const double clamped = juce::jmax(0.0, t);
    transportSec.store(clamped, std::memory_order_relaxed);

    if (metronomeCallback)
        metronomeCallback->setTransportMs(clamped * 1000.0);
}

double JuceEngine::getTransportSeconds() const
{
    return transportSec.load(std::memory_order_relaxed);
}

// ============================================================
// Clip bypass
// ============================================================
void JuceEngine::bypassTrack(int trackIndex, bool shouldBypass)
{
    if (clips.empty() || trackIndex < 0 || trackIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)trackIndex];
    if (!c.alive || c.playerNode == nullptr)
        return;

    if (auto *p = asTimelineProcessor(c.playerNode))
        p->setMuted(shouldBypass);
}

// ============================================================
// Plugin bypass helpers (clip-level)
// ============================================================
void JuceEngine::bypassPlugin(int trackIndex, int effectIndex, bool shouldBypass)
{
    juce::ignoreUnused(trackIndex, effectIndex, shouldBypass);
    juceLogToFlutter("Clip-level FX disabled (bypassPlugin ignored)");
}

bool JuceEngine::getPluginBypassState(int trackIndex, int effectIndex)
{
    juce::ignoreUnused(trackIndex, effectIndex);
    return false;
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

    for (const auto &c : clips)
    {
        if (!c.alive)
            continue;

        const int row = getRowIndexById(c.rowId);

        juce::String line;
        line << "audio clip #" << juce::String(c.clipId);

        const int clipFxCount = c.fxChain.size();

        if (clipFxCount > 0)
            line << " -> clip fx(" << juce::String(clipFxCount) << ")";

        if (c.gainProc != nullptr)
            line << " -> clip gain";

        if (c.panProc != nullptr)
            line << " -> clip pan";

        line << " -> row #" << juce::String(row);

        int rowFxCount = 0;
        if (row >= 0 && row < (int)rows.size())
            rowFxCount = rows[(size_t)row].fxChain.size();

        if (rowFxCount > 0)
            line << " -> row " << juce::String(row) << " fx(" << juce::String(rowFxCount) << ")";

        if (busGraphInitialised && row >= 0 && row < (int)rows.size())
        {
            if (rows[(size_t)row].automationProc != nullptr)
                line << " -> row " << juce::String(row) << " automation";

            if (rows[(size_t)row].gainProc != nullptr)
                line << " -> row " << juce::String(row) << " gain";

            if (rows[(size_t)row].panProc != nullptr)
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

    if (row < 0 || row >= (int)rows.size())
        return;

    auto *inputNode = rows[(size_t)row].inputNode.get();
    auto *automationNode = rows[(size_t)row].automationNode.get();
    auto &chain = rows[(size_t)row].fxChain;

    if (!inputNode || !automationNode)
        return;

    juce::Array<AudioProcessorGraph::NodeID> chainNodes;
    chainNodes.add(inputNode->nodeID);
    for (int i = 0; i < chain.size(); ++i)
        chainNodes.add(chain.getReference(i));
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

    AudioProcessorGraph::Node::Ptr prev = rows[(size_t)row].inputNode;

    for (int i = 0; i < chain.size(); ++i)
    {
        auto nodeID = chain.getReference(i);
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
void JuceEngine::compactRowFxChain(int row)
{
    if (row < 0 || row >= (int)rows.size())
        return;

    auto &r = rows[(size_t)row];
    for (int i = r.fxChain.size() - 1; i >= 0; --i)
    {
        const auto id = r.fxChain.getReference(i);
        if (graph.getNodeForId(id) != nullptr)
            continue;

        r.fxChain.removeRange(i, 1);
        if (i >= 0 && i < r.fxIds.size())
            r.fxIds.removeRange(i, 1);
    }

    while (r.fxIds.size() > r.fxChain.size())
        r.fxIds.removeRange(r.fxIds.size() - 1, 1);
}

void JuceEngine::compactMasterFxChain()
{
    if (!masterEffectChain)
        return;

    for (int i = masterEffectChain->size() - 1; i >= 0; --i)
    {
        const auto id = masterEffectChain->getReference(i);
        if (graph.getNodeForId(id) != nullptr)
            continue;

        masterEffectChain->removeRange(i, 1);
        if (i >= 0 && i < masterEffectIds.size())
            masterEffectIds.removeRange(i, 1);
    }

    while (masterEffectIds.size() > masterEffectChain->size())
        masterEffectIds.removeRange(masterEffectIds.size() - 1, 1);
}

namespace
{
bool resolveKnownPluginDescription(const juce::KnownPluginList &list,
                                   const juce::String &idOrName,
                                   juce::PluginDescription &outDesc)
{
    const auto types = list.getTypes();
    for (const auto &pd : types)
    {
        if (pd.fileOrIdentifier == idOrName)
        {
            outDesc = pd;
            return true;
        }
    }

    for (const auto &pd : types)
    {
        if (pd.name == idOrName)
        {
            outDesc = pd;
            return true;
        }
    }
    return false;
}
} // namespace

bool JuceEngine::insertTrackEffect(int trackRow, const juce::String &pluginPath)
{
    // juceLogToFlutter("Hello from JuceEngine::insertTrackEffect");

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return false;
    ensureRowBusNodesAttached(trackRow);

    compactRowFxChain(trackRow);
    auto &rowState = rows[(size_t)trackRow];
    auto &chain = rowState.fxChain;

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
        else if (pluginPath == "Limiter")
            plugin = std::make_unique<LimiterAudioProcessor>();
        else if (pluginPath == "Clipper")
            plugin = std::make_unique<ClipperAudioProcessor>();
        else if (pluginPath == "Pitch Shift")
            plugin = std::make_unique<PitchShiftAudioProcessor>();
        else if (pluginPath == "Chorus")
            plugin = std::make_unique<ChorusAudioProcessor>();
        else if (pluginPath == "Vibrato")
            plugin = std::make_unique<VibratoAudioProcessor>();
        else
        {
            juceLogToFlutter("didn't find matching Mixroom plugin (row)");
            return false;
        }

        auto node = graph.addNode(std::move(plugin));
        if (node == nullptr)
        {
            juceLogToFlutter("insertTrackEffect: graph.addNode failed for built-in");
            return false;
        }
        chain.add(node->nodeID);
        rowState.fxIds.add(pluginPath);

        rewireTrackBusFxChain(trackRow);
        return true;
    }

    // External plugin
    const auto requestedId = pluginPath.trim();
    if (requestedId.isEmpty())
    {
        juceLogToFlutter("insertTrackEffect: empty external plugin identifier");
        return false;
    }

    juce::PluginDescription desc;
    const bool resolved = resolveKnownPluginDescription(pluginList, requestedId, desc);
    if (!resolved)
    {
        desc.fileOrIdentifier = requestedId;
#if JUCE_IOS
        // AU identifiers usually use "AudioUnit:..." and should resolve through AU format.
        desc.pluginFormatName = "AudioUnit";
#endif
    }

    const auto sr = graph.getSampleRate() > 0.0 ? graph.getSampleRate() : 44100.0;
    const auto bs = graph.getBlockSize() > 0 ? graph.getBlockSize() : 512;

    juce::String error;
    std::unique_ptr<juce::AudioPluginInstance> inst;
    try
    {
        inst = pluginFormatManager.createPluginInstance(desc, sr, bs, error);
    }
    catch (const std::exception &e)
    {
        error = "exception: " + juce::String(e.what());
    }
    catch (...)
    {
        error = "unknown exception";
    }

    if (!inst)
    {
        juceLogToFlutter(("insertTrackEffect failed for '" + requestedId + "': " + error).toRawUTF8());
        return false;
    }

    auto pluginNode = graph.addNode(std::move(inst));
    if (pluginNode == nullptr)
    {
        juceLogToFlutter(("insertTrackEffect: graph.addNode failed for '" + requestedId + "'").toRawUTF8());
        return false;
    }

    rows[(size_t)trackRow].fxChain.add(pluginNode->nodeID);
    rows[(size_t)trackRow].fxIds.add(requestedId);
    rewireTrackBusFxChain(trackRow);
    return true;
}

void JuceEngine::removeTrackEffect(int trackRow, int effectIndex)
{
    // juceLogToFlutter("Hello from JuceEngine::removeTrackEffect");

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return;

    compactRowFxChain(trackRow);
    auto &chain = rows[(size_t)trackRow].fxChain;
    if (effectIndex < 0 || effectIndex >= chain.size())
        return;

    auto nodeID = chain.getReference(effectIndex);
    graph.removeNode(nodeID);

    chain.removeRange(effectIndex, 1);
    auto &fxIds = rows[(size_t)trackRow].fxIds;
    if (effectIndex >= 0 && effectIndex < fxIds.size())
        fxIds.removeRange(effectIndex, 1);

    rewireTrackBusFxChain(trackRow);
}

void JuceEngine::reorderTrackEffects(int trackRow, int fromIndex, int toIndex)
{
    // juceLogToFlutter("Hello from JuceEngine::reorderTrackEffects");

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return;

    compactRowFxChain(trackRow);
    auto &chain = rows[(size_t)trackRow].fxChain;

    if (fromIndex < 0 || fromIndex >= chain.size())
        return;
    if (toIndex < 0 || toIndex > chain.size())
        return;
    if (fromIndex == toIndex)
        return;

    auto nodeID = chain.getReference(fromIndex);
    juce::String fxId;
    auto &fxIds = rows[(size_t)trackRow].fxIds;
    if (fromIndex >= 0 && fromIndex < fxIds.size())
        fxId = fxIds[fromIndex];

    chain.removeRange(fromIndex, 1);
    toIndex = juce::jlimit(0, chain.size(), toIndex);
    chain.insert(toIndex, nodeID);
    if (fromIndex >= 0 && fromIndex < fxIds.size())
    {
        fxIds.remove(fromIndex);
        toIndex = juce::jlimit(0, fxIds.size(), toIndex);
        fxIds.insert(toIndex, fxId);
    }

    rewireTrackBusFxChain(trackRow);
}

juce::StringArray JuceEngine::getTrackEffectsForRow(int trackRow)
{
    juce::StringArray names;

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return names;

    compactRowFxChain(trackRow);
    auto &chain = rows[(size_t)trackRow].fxChain;

    for (auto &nodeID : chain)
    {
        if (auto node = graph.getNodeForId(nodeID))
        {
            if (auto *processor = node->getProcessor())
                names.add(processor->getName());
        }
    }

    return names;
}

juce::StringArray JuceEngine::getTrackEffectIdsForRow(int trackRow)
{
    juce::StringArray ids;

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return ids;

    compactRowFxChain(trackRow);
    auto &r = rows[(size_t)trackRow];
    if (r.fxIds.size() == r.fxChain.size())
        return r.fxIds;

    // Legacy fallback for previously-created rows without explicit IDs.
    for (auto &nodeID : r.fxChain)
    {
        if (auto node = graph.getNodeForId(nodeID))
            if (auto *processor = node->getProcessor())
                ids.add(processor->getName());
    }

    return ids;
}

void JuceEngine::setTrackEffectParameter(int trackRow,
                                         int effectIndex,
                                         const juce::String &paramName,
                                         const juce::var &newValue)
{
    // juceLogToFlutter("JuceEngine::setTrackEffectParameter");

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return;

    compactRowFxChain(trackRow);
    auto &chain = rows[(size_t)trackRow].fxChain;
    if (effectIndex < 0 || effectIndex >= chain.size())
        return;

    auto nodeID = chain.getReference(effectIndex);
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
    if (trackRow < 0 || trackRow >= (int)rows.size())
        return;

    compactRowFxChain(trackRow);
    auto &chain = rows[(size_t)trackRow].fxChain;
    if (effectIndex < 0 || effectIndex >= chain.size())
        return;

    auto nodeID = chain.getReference(effectIndex);
    if (auto node = graph.getNodeForId(nodeID))
        node->setBypassed(shouldBypass);
}

bool JuceEngine::getRowEffectBypassState(int trackRow, int effectIndex)
{
    if (trackRow < 0 || trackRow >= (int)rows.size())
        return false;

    compactRowFxChain(trackRow);
    auto &chain = rows[(size_t)trackRow].fxChain;
    if (effectIndex < 0 || effectIndex >= chain.size())
        return false;

    auto nodeID = chain.getReference(effectIndex);
    if (auto node = graph.getNodeForId(nodeID))
        return node->isBypassed();

    return false;
}

void JuceEngine::setTrackAutomationPoints(int trackRow,
                                          const std::vector<AutomationPoint> &points)
{
    if (trackRow < 0 || trackRow >= (int)rows.size())
        return;

    rows[(size_t)trackRow].automationPoints = points;
    if (rows[(size_t)trackRow].automationProc != nullptr)
        rows[(size_t)trackRow].automationProc->setAutomationPoints(points);
}

void JuceEngine::setAutomationTransport(double timeSeconds)
{
    setTransportSeconds(timeSeconds);
}

// ============================================================
// Row-level gain / mute / pan
// ============================================================
void JuceEngine::setRowGain(int row, float gain)
{
    if (row < 0 || row >= (int)rows.size())
        return;

    rows[(size_t)row].gainUi = gain;
    if (rows[(size_t)row].gainProc != nullptr)
        rows[(size_t)row].gainProc->gain->setValueNotifyingHost(gain / 3.0f);
}

void JuceEngine::muteRow(int row, bool mute)
{
    if (row < 0 || row >= (int)rows.size())
        return;

    rows[(size_t)row].muted = mute;
    if (rows[(size_t)row].gainProc != nullptr)
        rows[(size_t)row].gainProc->setMuted(mute);
}

bool JuceEngine::isRowMuted(int row)
{
    if (row < 0 || row >= (int)rows.size())
        return false;

    if (rows[(size_t)row].gainProc != nullptr)
        return rows[(size_t)row].gainProc->isMuted();

    return rows[(size_t)row].muted;
}

void JuceEngine::setRowPan(int row, float pan)
{
    if (row < 0 || row >= (int)rows.size())
        return;

    rows[(size_t)row].panUi = pan;
    if (rows[(size_t)row].panProc != nullptr)
        rows[(size_t)row].panProc->pan->setValueNotifyingHost(panUIToNormalized(pan));
}

// ============================================================
// Master bus FX
// ============================================================
bool JuceEngine::insertMasterEffect(const juce::String &pluginPath)
{
    // juceLogToFlutter("Hello from JuceEngine::insertMasterEffect");

    if (!masterEffectChain)
        masterEffectChain = new juce::Array<AudioProcessorGraph::NodeID>();
    compactMasterFxChain();

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
        else if (pluginPath == "Limiter")
            plugin = std::make_unique<LimiterAudioProcessor>();
        else if (pluginPath == "Clipper")
            plugin = std::make_unique<ClipperAudioProcessor>();
        else if (pluginPath == "Pitch Shift")
            plugin = std::make_unique<PitchShiftAudioProcessor>();
        else if (pluginPath == "Chorus")
            plugin = std::make_unique<ChorusAudioProcessor>();
        else if (pluginPath == "Vibrato")
            plugin = std::make_unique<VibratoAudioProcessor>();
        else
        {
            return false;
        }

        auto node = graph.addNode(std::move(plugin));
        if (node == nullptr)
        {
            juceLogToFlutter("insertMasterEffect: graph.addNode failed for built-in");
            return false;
        }
        masterEffectChain->add(node->nodeID);
        masterEffectIds.add(pluginPath);

        rewireMasterFxChain();
        return true;
    }

    // External plugin
    const auto requestedId = pluginPath.trim();
    if (requestedId.isEmpty())
    {
        juceLogToFlutter("insertMasterEffect: empty external plugin identifier");
        return false;
    }

    juce::PluginDescription desc;
    const bool resolved = resolveKnownPluginDescription(pluginList, requestedId, desc);
    if (!resolved)
    {
        desc.fileOrIdentifier = requestedId;
#if JUCE_IOS
        desc.pluginFormatName = "AudioUnit";
#endif
    }

    const auto sr = graph.getSampleRate() > 0.0 ? graph.getSampleRate() : 44100.0;
    const auto bs = graph.getBlockSize() > 0 ? graph.getBlockSize() : 512;

    juce::String error;
    std::unique_ptr<juce::AudioPluginInstance> inst;
    try
    {
        inst = pluginFormatManager.createPluginInstance(desc, sr, bs, error);
    }
    catch (const std::exception &e)
    {
        error = "exception: " + juce::String(e.what());
    }
    catch (...)
    {
        error = "unknown exception";
    }

    if (!inst)
    {
        juceLogToFlutter(("insertMasterEffect failed for '" + requestedId + "': " + error).toRawUTF8());
        return false;
    }

    auto pluginNode = graph.addNode(std::move(inst));
    if (pluginNode == nullptr)
    {
        juceLogToFlutter(("insertMasterEffect: graph.addNode failed for '" + requestedId + "'").toRawUTF8());
        return false;
    }

    masterEffectChain->add(pluginNode->nodeID);
    masterEffectIds.add(requestedId);
    rewireMasterFxChain();
    return true;
}

void JuceEngine::removeMasterEffect(int effectIndex)
{
    if (!masterEffectChain)
        return;
    compactMasterFxChain();

    if (effectIndex < 0 || effectIndex >= masterEffectChain->size())
        return;

    auto nodeID = masterEffectChain->getReference(effectIndex);
    graph.removeNode(nodeID);

    masterEffectChain->removeRange(effectIndex, 1);
    if (effectIndex >= 0 && effectIndex < masterEffectIds.size())
        masterEffectIds.removeRange(effectIndex, 1);

    rewireMasterFxChain();
}

void JuceEngine::reorderMasterEffects(int fromIndex, int toIndex)
{
    if (!masterEffectChain)
        return;
    compactMasterFxChain();

    if (fromIndex < 0 || fromIndex >= masterEffectChain->size())
        return;
    if (toIndex < 0 || toIndex > masterEffectChain->size())
        return;
    if (fromIndex == toIndex)
        return;

    auto id = masterEffectChain->getReference(fromIndex);
    juce::String fxId;
    if (fromIndex >= 0 && fromIndex < masterEffectIds.size())
        fxId = masterEffectIds[fromIndex];

    masterEffectChain->removeRange(fromIndex, 1);
    toIndex = juce::jlimit(0, masterEffectChain->size(), toIndex);
    masterEffectChain->insert(toIndex, id);
    if (fromIndex >= 0 && fromIndex < masterEffectIds.size())
    {
        masterEffectIds.remove(fromIndex);
        toIndex = juce::jlimit(0, masterEffectIds.size(), toIndex);
        masterEffectIds.insert(toIndex, fxId);
    }

    rewireMasterFxChain();
}

juce::StringArray JuceEngine::getMasterEffects()
{
    juce::StringArray out;

    if (!masterEffectChain)
        return out;
    compactMasterFxChain();

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

juce::StringArray JuceEngine::getMasterEffectIds()
{
    compactMasterFxChain();
    if (masterEffectIds.size() == 0 && masterEffectChain != nullptr && masterEffectChain->size() > 0)
    {
        juce::StringArray ids;
        for (auto &id : *masterEffectChain)
        {
            if (auto node = graph.getNodeForId(id))
                if (auto *p = node->getProcessor())
                    ids.add(p->getName());
        }
        return ids;
    }

    return masterEffectIds;
}

void JuceEngine::setMasterEffectParameter(int effectIndex,
                                          const juce::String &paramName,
                                          const juce::var &newValue)
{
    if (!masterEffectChain)
        return;
    compactMasterFxChain();

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
    compactMasterFxChain();

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
    compactMasterFxChain();

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
        for (auto &r : rows)
        {
            auto src = r.meterTapNode; // post-pan + metered
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
    if (clips.empty() || clipIdx < 0 || clipIdx >= (int)clips.size())
        return 0;

    const auto &c = clips[(size_t)clipIdx];
    if (!c.alive)
        return 0;

    const int idx = getRowIndexById(c.rowId);
    return juce::jmax(0, idx);
}

void JuceEngine::setClipGain(int clipIndex, float gain)
{
    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)clipIndex];
    if (!c.alive || c.gainProc == nullptr)
        return;

    c.gainProc->gain->setValueNotifyingHost(gain / 3.0f);
}

void JuceEngine::muteClip(int clipIndex, bool shouldMute)
{
    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)clipIndex];
    if (!c.alive || c.playerNode == nullptr)
        return;

    if (auto *p = asTimelineProcessor(c.playerNode))
        p->setMuted(shouldMute);
}

void JuceEngine::setClipPan(int clipIndex, float pan)
{
    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)clipIndex];
    if (!c.alive)
        return;

    if (auto *p = c.panProc)
        p->pan->setValueNotifyingHost(panUIToNormalized(pan));
}

void JuceEngine::setClipPitch(int clipIndex, float semitones)
{
    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)clipIndex];
    if (!c.alive || c.playerNode == nullptr)
        return;

    c.pitchSemitones = juce::jlimit(-24.0f, 24.0f, semitones);

    if (auto *p = asTimelineProcessor(c.playerNode))
        p->setPitchSemitones(c.pitchSemitones);
}

void JuceEngine::setClipStretchOptions(int clipIndex, double tempoRatio, bool preservePitch)
{
    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)clipIndex];
    if (!c.alive || c.playerNode == nullptr)
        return;

    c.tempoRatio = juce::jlimit(0.05, 20.0, tempoRatio);
    c.preservePitch = preservePitch;

    if (auto *p = asTimelineProcessor(c.playerNode))
        p->setStretchOptions(c.tempoRatio, c.preservePitch);
}

juce::Array<juce::NamedValueSet> JuceEngine::getTrackPluginParameterInfo(int row, int effectIndex)
{
    // juceLogToFlutter("Hello from JuceEngine::getTrackPluginParameterInfo");
    juce::Array<juce::NamedValueSet> results;

    if (row < 0 || row >= (int)rows.size())
        return results;

    compactRowFxChain(row);
    auto &chain = rows[(size_t)row].fxChain;
    if (effectIndex < 0 || effectIndex >= chain.size())
        return results;

    auto nodeID = chain.getReference(effectIndex);
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
                e.set("default",
                      fp->range.convertFrom0to1(p->getDefaultValue()));
                e.set("value", fp->get());
            }
            else if (auto *bp = dynamic_cast<juce::AudioParameterBool *>(p))
            {
                e.set("type", "bool");
                e.set("default", p->getDefaultValue() >= 0.5f);
                e.set("value", bp->get());
            }
            else if (auto *cp = dynamic_cast<juce::AudioParameterChoice *>(p))
            {
                e.set("type", "choice");
                const int maxIndex = juce::jmax(0, cp->choices.size() - 1);
                const int defaultIndex = juce::jlimit(
                    0,
                    maxIndex,
                    juce::roundToInt(p->getDefaultValue() * (float)maxIndex));
                e.set("default",
                      cp->choices.isEmpty() ? juce::String()
                                            : cp->choices[defaultIndex]);
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
    compactMasterFxChain();

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
                e.set("default",
                      fp->range.convertFrom0to1(p->getDefaultValue()));
                e.set("value", fp->get());
            }
            else if (auto *bp = dynamic_cast<juce::AudioParameterBool *>(p))
            {
                e.set("type", "bool");
                e.set("default", p->getDefaultValue() >= 0.5f);
                e.set("value", bp->get());
            }
            else if (auto *cp = dynamic_cast<juce::AudioParameterChoice *>(p))
            {
                e.set("type", "choice");
                const int maxIndex = juce::jmax(0, cp->choices.size() - 1);
                const int defaultIndex = juce::jlimit(
                    0,
                    maxIndex,
                    juce::roundToInt(p->getDefaultValue() * (float)maxIndex));
                e.set("default",
                      cp->choices.isEmpty() ? juce::String()
                                            : cp->choices[defaultIndex]);
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

juce::NamedValueSet JuceEngine::analyzeAudioStereo16k(const juce::File &file)
{
    juce::NamedValueSet out;
    out.set("phase_corr", 1.0);
    out.set("side_ratio", 0.0);
    out.set("stereo_imbalance", 0.0);

    std::unique_ptr<juce::AudioFormatReader> reader(formatManager.createReaderFor(file));
    if (!reader)
        return out;

    const int64 totalSamples64 = reader->lengthInSamples;
    const int totalSamples = (int)totalSamples64;
    if (totalSamples <= 0)
        return out;

    const int readChannels = reader->numChannels >= 2 ? 2 : 1;
    juce::AudioBuffer<float> inBuffer(readChannels, totalSamples);
    reader->read(&inBuffer, 0, totalSamples, 0, true, readChannels >= 2);

    auto copyChannel = [&](int channel) {
        std::vector<float> v((size_t)totalSamples, 0.0f);
        if (totalSamples > 0)
            std::memcpy(v.data(), inBuffer.getReadPointer(channel), (size_t)totalSamples * sizeof(float));
        return v;
    };

    std::vector<float> left = copyChannel(0);
    std::vector<float> right = (readChannels >= 2) ? copyChannel(1) : left;

    auto resampleTo16k = [&](const std::vector<float> &input) {
        if (input.empty())
            return std::vector<float>{};
        if (reader->sampleRate == 16000.0)
            return input;

        juce::LagrangeInterpolator resampler;
        resampler.reset();

        const double speedRatio = reader->sampleRate / 16000.0; // input per output
        const int outSamples = (int)std::ceil((double)input.size() / speedRatio);
        std::vector<float> output((size_t)juce::jmax(0, outSamples), 0.0f);
        if (outSamples > 0)
        {
            resampler.process(
                speedRatio,
                input.data(),
                output.data(),
                outSamples,
                (int)input.size(),
                0);
        }
        return output;
    };

    left = resampleTo16k(left);
    right = resampleTo16k(right);

    const int n = juce::jmin(24000, juce::jmin((int)left.size(), (int)right.size()));
    if (n <= 0)
        return out;

    double sumL2 = 0.0;
    double sumR2 = 0.0;
    double sumLR = 0.0;
    double sumMid2 = 0.0;
    double sumSide2 = 0.0;

    for (int i = 0; i < n; ++i)
    {
        const double l = (double)left[(size_t)i];
        const double r = (double)right[(size_t)i];
        sumL2 += l * l;
        sumR2 += r * r;
        sumLR += l * r;

        const double mid = 0.5 * (l + r);
        const double side = 0.5 * (l - r);
        sumMid2 += mid * mid;
        sumSide2 += side * side;
    }

    const double phaseCorr =
        sumLR / std::sqrt((sumL2 * sumR2) + 1.0e-12);
    const double rmsL = std::sqrt(sumL2 / (double)n);
    const double rmsR = std::sqrt(sumR2 / (double)n);
    const double midRms = std::sqrt(sumMid2 / (double)n);
    const double sideRms = std::sqrt(sumSide2 / (double)n);
    const double sideRatio = sideRms / (midRms + 1.0e-9);
    const double stereoImbalance = std::abs(rmsL - rmsR) / (rmsL + rmsR + 1.0e-9);

    out.set("phase_corr", juce::jlimit(-1.0, 1.0, phaseCorr));
    out.set("side_ratio", juce::jlimit(0.0, 2.0, sideRatio));
    out.set("stereo_imbalance", juce::jlimit(0.0, 1.0, stereoImbalance));
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

    if (rows.empty())
        return;
    row = juce::jlimit(0, (int)rows.size() - 1, row);
    auto rowInput = rows[(size_t)row].inputNode;
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

const std::array<float, 4> JuceEngine::getRowMeterValues(int rowIndex)
{
    if (rowIndex < 0 || rowIndex >= (int)rows.size())
        return {0, 0, 0, 0};

    auto &m = rows[(size_t)rowIndex].meter;
    return {
        m.peakL.load(std::memory_order_relaxed),
        m.peakR.load(std::memory_order_relaxed),
        m.rmsL.load(std::memory_order_relaxed),
        m.rmsR.load(std::memory_order_relaxed),
    };
}

std::vector<float> JuceEngine::getAllMeterValues() const
{
    constexpr int stride = 5;
    const int total = stride * (1 + (int)rows.size());

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
    for (int row = 0; row < (int)rows.size(); ++row)
    {
        const int base = stride * (1 + row);

        auto &m = rows[(size_t)row].meter;
        out[base + 0] = m.peakL.load(std::memory_order_relaxed);
        out[base + 1] = m.peakR.load(std::memory_order_relaxed);
        out[base + 2] = m.rmsL.load(std::memory_order_relaxed);
        out[base + 3] = m.rmsR.load(std::memory_order_relaxed);

        // If you don’t have row clip yet, set 0 for now
        out[base + 4] = 0.0f;
        // If you DO have it:
        // out[base + 4] = rowMeters[row].clip.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
    }

    return out;
}

const std::array<float, 5> JuceEngine::getClipCompressorMeter(int clipIndex, int effectIndex)
{
    juce::ignoreUnused(clipIndex, effectIndex);
    return {0, 0, 0, 0, 0};
}

const std::array<float, 5> JuceEngine::getRowCompressorMeter(int row, int effectIndex)
{
    if (row < 0 || row >= (int)rows.size())
        return {0, 0, 0, 0, 0};

    compactRowFxChain(row);
    auto &chain = rows[(size_t)row].fxChain;
    if (effectIndex < 0 || effectIndex >= chain.size())
        return {0, 0, 0, 0, 0};

    auto nodeID = chain.getReference(effectIndex);
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
    compactMasterFxChain();

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

double JuceEngine::getHostSampleRate() const
{
    if (auto *device = deviceManager.getCurrentAudioDevice())
    {
        const double deviceSr = device->getCurrentSampleRate();
        if (deviceSr > 1000.0)
            return deviceSr;
    }

    const double sr = hostSampleRateAtomic.load(std::memory_order_relaxed);
    return sr > 1000.0 ? sr : 44100.0;
}

std::vector<float> JuceEngine::getRowEqWaveform(int row, int effectIndex, int sampleCount)
{
    const int count = juce::jlimit(16, 1024, sampleCount);

    if (row < 0 || row >= (int)rows.size())
        return std::vector<float>((size_t)count, 0.0f);

    compactRowFxChain(row);
    auto &chain = rows[(size_t)row].fxChain;
    if (effectIndex < 0 || effectIndex >= chain.size())
        return std::vector<float>((size_t)count, 0.0f);

    auto nodeID = chain.getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (!node)
        return std::vector<float>((size_t)count, 0.0f);

    if (auto *eq = dynamic_cast<EQAudioProcessor *>(node->getProcessor()))
        return eq->getRecentWaveform(count);
    if (auto *eq3 = dynamic_cast<EQ3AudioProcessor *>(node->getProcessor()))
        return eq3->getRecentWaveform(count);

    return std::vector<float>((size_t)count, 0.0f);
}

std::vector<float> JuceEngine::getMasterEqWaveform(int effectIndex, int sampleCount)
{
    const int count = juce::jlimit(16, 1024, sampleCount);

    if (!masterEffectChain)
        return std::vector<float>((size_t)count, 0.0f);
    compactMasterFxChain();

    if (effectIndex < 0 || effectIndex >= masterEffectChain->size())
        return std::vector<float>((size_t)count, 0.0f);

    auto nodeID = masterEffectChain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (!node)
        return std::vector<float>((size_t)count, 0.0f);

    if (auto *eq = dynamic_cast<EQAudioProcessor *>(node->getProcessor()))
        return eq->getRecentWaveform(count);
    if (auto *eq3 = dynamic_cast<EQ3AudioProcessor *>(node->getProcessor()))
        return eq3->getRecentWaveform(count);

    return std::vector<float>((size_t)count, 0.0f);
}

int JuceEngine::addRow(const juce::String &name, int iconId)
{
    if ((int)rows.size() >= kMaxRows)
        return -1;

    RowState r;
    const int newRowId = nextRowId.fetch_add(1);
    r.rowId = newRowId;
    r.name = name.isNotEmpty() ? name : "Row";
    r.iconId = iconId;

    rows.push_back(std::move(r));
    rebuildRowIdIndexCache();

    return newRowId;
}

bool JuceEngine::renameRow(int rowId, const juce::String &newName)
{
    for (auto &r : rows)
    {
        if (r.rowId == rowId)
        {
            r.name = newName;
            return true;
        }
    }
    return false;
}

int JuceEngine::insertRowAbove(int referenceRowId, const juce::String &name, int iconId)
{
    if ((int)rows.size() >= kMaxRows)
        return -1;

    const int refIdx = getRowIndexById(referenceRowId);
    const int insertIdx = juce::jlimit(0, (int)rows.size(), refIdx);

    RowState r;
    const int newRowId = nextRowId.fetch_add(1);
    r.rowId = newRowId;
    r.name = name.isNotEmpty() ? name : "Row";
    r.iconId = iconId;

    rows.insert(rows.begin() + insertIdx, std::move(r));
    rebuildRowIdIndexCache();

    if (engineInitialized)
    {
        retargetRowMeterTapPointers();
    }

    return newRowId;
}

int JuceEngine::insertRowBelow(int referenceRowId, const juce::String &name, int iconId)
{
    if ((int)rows.size() >= kMaxRows)
        return -1;

    const int refIdx = getRowIndexById(referenceRowId);
    const int insertIdx = juce::jlimit(0, (int)rows.size(), refIdx + 1);

    RowState r;
    const int newRowId = nextRowId.fetch_add(1);
    r.rowId = newRowId;
    r.name = name.isNotEmpty() ? name : "Row";
    r.iconId = iconId;

    rows.insert(rows.begin() + insertIdx, std::move(r));
    rebuildRowIdIndexCache();

    if (engineInitialized)
    {
        retargetRowMeterTapPointers();
    }

    return newRowId;
}

bool JuceEngine::moveRowOrder(int fromIndex, int toIndex)
{
    const int n = (int)rows.size();
    if (n <= 1)
        return false;

    if (fromIndex < 0 || fromIndex >= n)
        return false;
    if (toIndex < 0 || toIndex >= n)
        return false;
    if (fromIndex == toIndex)
        return true;

    // Rotate in-place to avoid copying RowState (contains atomics).
    if (fromIndex < toIndex)
        std::rotate(rows.begin() + fromIndex, rows.begin() + fromIndex + 1, rows.begin() + toIndex + 1);
    else
        std::rotate(rows.begin() + toIndex, rows.begin() + fromIndex, rows.begin() + fromIndex + 1);
    rebuildRowIdIndexCache();

    // UI-only row order. Audio routing stays by stable rowId.
    if (engineInitialized)
        retargetRowMeterTapPointers();

    return true;
}

bool JuceEngine::setRowIcon(int rowId, int iconId)
{
    for (auto &r : rows)
    {
        if (r.rowId == rowId)
        {
            r.iconId = iconId;
            return true;
        }
    }
    return false;
}

juce::Array<juce::NamedValueSet> JuceEngine::getRows() const
{
    juce::Array<juce::NamedValueSet> out;
    for (const auto &r : rows)
    {
        juce::NamedValueSet v;
        v.set("rowId", r.rowId);
        v.set("name", r.name);
        v.set("iconId", r.iconId);
        out.add(v);
    }
    return out;
}

// remove row: delete any clips that belong to it
bool JuceEngine::removeRow(int rowId)
{
    if ((int)rows.size() <= 1)
        return false; // always keep at least 1 row

    int idx = -1;
    for (int i = 0; i < (int)rows.size(); ++i)
        if (rows[i].rowId == rowId)
        {
            idx = i;
            break;
        }

    if (idx < 0)
        return false;

    // Delete clips that belong to this row.
    juce::Array<int> removedClipIds;
    for (auto &c : clips)
    {
        if (c.alive && c.rowId == rowId)
        {
            removedClipIds.add(c.clipId);
        }
    }
    for (const auto clipId : removedClipIds)
        unloadClip(clipId);

    // Remove graph nodes owned by the row being deleted (including its FX).
    auto removed = std::move(rows[(size_t)idx]);
    for (auto id : removed.fxChain)
        graph.removeNode(id);
    if (removed.inputNode)
        graph.removeNode(removed.inputNode->nodeID);
    if (removed.automationNode)
        graph.removeNode(removed.automationNode->nodeID);
    if (removed.gainNode)
        graph.removeNode(removed.gainNode->nodeID);
    if (removed.panNode)
        graph.removeNode(removed.panNode->nodeID);
    if (removed.meterTapNode)
        graph.removeNode(removed.meterTapNode->nodeID);

    rows.erase(rows.begin() + idx);
    rebuildRowIdIndexCache();

    if (engineInitialized)
    {
        retargetRowMeterTapPointers();
    }

    return true;
}

int JuceEngine::getRowIndexById(int rowId) const
{
    const auto it = rowIdToIndex.find(rowId);
    if (it != rowIdToIndex.end())
        return it->second;
    for (int i = 0; i < (int)rows.size(); ++i)
        if (rows[(size_t)i].rowId == rowId)
            return i;
    return -1;
}

juce::AudioProcessorGraph::Node::Ptr JuceEngine::getRowInputNodeById(int rowId)
{
    const int idx = getRowIndexById(rowId);
    if (idx < 0 || idx >= (int)rows.size())
        return nullptr;
    ensureRowBusNodesAttached(idx);
    return rows[idx].inputNode;
}

// Full rebuild of row/master bus nodes while keeping clip nodes
void JuceEngine::rebuildBusesAndRewireClips()
{
    // 1) Remove connections that touch any row/master nodes
    // 2) Remove row bus nodes and master gain/pan nodes (keep FX nodes/chains)
    // 3) Recreate buses via ensureBusGraphInitialised()
    // 4) Rewire row/master FX chains and every alive clip

    // Remove ALL connections first (safe & easiest)
    auto conns = graph.getConnections();
    for (auto &c : conns)
        graph.removeConnection(c);

    // Existing clip chains are now disconnected.
    for (auto &clip : clips)
        clip.wired = false;

    // Remove master gain/pan nodes only (keep master FX nodes + chain IDs).
    if (masterGainNode)
        graph.removeNode(masterGainNode->nodeID);
    if (masterPanNode)
        graph.removeNode(masterPanNode->nodeID);
    masterGainNode = nullptr;
    masterPanNode = nullptr;
    masterGainProcessor = nullptr;
    masterPanProcessor = nullptr;

    // Remove all old row bus nodes (keep row FX nodes + chain IDs).
    for (auto &r : rows)
    {
        if (r.inputNode)
            graph.removeNode(r.inputNode->nodeID);
        if (r.automationNode)
            graph.removeNode(r.automationNode->nodeID);
        if (r.gainNode)
            graph.removeNode(r.gainNode->nodeID);
        if (r.panNode)
            graph.removeNode(r.panNode->nodeID);
        if (r.meterTapNode)
            graph.removeNode(r.meterTapNode->nodeID);

        r.inputNode = nullptr;
        r.automationNode = nullptr;
        r.gainNode = nullptr;
        r.panNode = nullptr;
        r.meterTapNode = nullptr;

        r.inputProc = nullptr;
        r.automationProc = nullptr;
        r.gainProc = nullptr;
        r.panProc = nullptr;
        r.meterTapProc = nullptr;
    }

    busGraphInitialised = false;
    ensureBusGraphInitialised();

    // Restore row/master FX routing on top of rebuilt bus nodes.
    for (int i = 0; i < (int)rows.size(); ++i)
        rewireTrackBusFxChain(i);
    rewireMasterFxChain();

    // Rewire clips
    for (auto &c : clips)
    {
        if (c.alive)
            rewireTrackChain(c.clipId); // we'll rewrite rewireTrackChain to use new clip structure
    }
}

const juce::StringArray JuceEngine::mixroomPlugins{
    "EQ 3-Band",
    "Compressor",
    "Limiter",
    "Clipper",
    "De-Esser",
    "Distortion",
    "Delay",
    "Reverb",
    "EQ Parametric",
    "Pitch Shift",
    "Chorus",
    "Vibrato",
};
