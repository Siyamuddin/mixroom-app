#include "JuceEngine.h"
#include <algorithm>
#include <cmath>
#include <unordered_set>

using namespace juce;

namespace
{
void requestGraphRebuildAsync(juce::AudioProcessorGraph &graph)
{
    graph.removeIllegalConnections(juce::AudioProcessorGraph::UpdateKind::async);
}

void updateAtomicMax(std::atomic<std::int64_t> &target, std::int64_t value) noexcept
{
    auto current = target.load(std::memory_order_relaxed);
    while (value > current &&
           !target.compare_exchange_weak(current,
                                         value,
                                         std::memory_order_relaxed,
                                         std::memory_order_relaxed))
    {
    }
}

void updateAtomicMax(std::atomic<int> &target, int value) noexcept
{
    auto current = target.load(std::memory_order_relaxed);
    while (value > current &&
           !target.compare_exchange_weak(current,
                                         value,
                                         std::memory_order_relaxed,
                                         std::memory_order_relaxed))
    {
    }
}

double ticksToMilliseconds(std::int64_t ticks, std::int64_t ticksPerSecond) noexcept
{
    if (ticks <= 0 || ticksPerSecond <= 0)
        return 0.0;
    return (1000.0 * (double)ticks) / (double)ticksPerSecond;
}

juce::StringArray getAvailableInputDeviceNamesForManager(juce::AudioDeviceManager &deviceManager)
{
    juce::StringArray names;
    auto &types = deviceManager.getAvailableDeviceTypes();

    for (auto *type : types)
    {
        if (type == nullptr)
            continue;

        type->scanForDevices();
        names.addArray(type->getDeviceNames(true));
    }

    names.removeDuplicates(true);
    return names;
}

juce::String getDefaultInputDeviceNameForManager(juce::AudioDeviceManager &deviceManager)
{
    auto &types = deviceManager.getAvailableDeviceTypes();

    for (auto *type : types)
    {
        if (type == nullptr)
            continue;

        type->scanForDevices();
        const auto names = type->getDeviceNames(true);
        if (names.isEmpty())
            continue;

        const int defaultIndex = type->getDefaultDeviceIndex(true);
        if (juce::isPositiveAndBelow(defaultIndex, names.size()))
            return names[defaultIndex];

        return names[0];
    }

    return {};
}

juce::StringArray getAvailableOutputDeviceNamesForManager(juce::AudioDeviceManager &deviceManager)
{
    juce::StringArray names;
    auto &types = deviceManager.getAvailableDeviceTypes();

    for (auto *type : types)
    {
        if (type == nullptr)
            continue;

        type->scanForDevices();
        names.addArray(type->getDeviceNames(false));
    }

    names.removeDuplicates(true);
    return names;
}

juce::String getDefaultOutputDeviceNameForManager(juce::AudioDeviceManager &deviceManager)
{
    auto &types = deviceManager.getAvailableDeviceTypes();

    for (auto *type : types)
    {
        if (type == nullptr)
            continue;

        type->scanForDevices();
        const auto names = type->getDeviceNames(false);
        if (names.isEmpty())
            continue;

        const int defaultIndex = type->getDefaultDeviceIndex(false);
        if (juce::isPositiveAndBelow(defaultIndex, names.size()))
            return names[defaultIndex];

        return names[0];
    }

    return {};
}

std::string decodedClipAssetCacheKeyForFile(const juce::File &file)
{
    return file.getFullPathName().toStdString() + "\n" +
           juce::String(file.getSize()).toStdString() + "\n" +
           juce::String(file.getLastModificationTime().toMilliseconds()).toStdString();
}

std::shared_ptr<DecodedClipAudioAsset> decodeReaderToStereoAsset(
    juce::AudioFormatReader &reader)
{
    if (reader.numChannels <= 0 ||
        reader.lengthInSamples <= 0 ||
        reader.lengthInSamples > (juce::int64)std::numeric_limits<int>::max())
    {
        return nullptr;
    }

    const int totalSamples = (int)reader.lengthInSamples;
    auto decoded = std::make_shared<DecodedClipAudioAsset>();
    decoded->sampleRate = reader.sampleRate > 0.0 ? reader.sampleRate : 44100.0;
    decoded->audio.setSize(2, totalSamples, false, true, true);
    decoded->audio.clear();

    const bool readLeft = reader.numChannels > 0;
    const bool readRight = reader.numChannels > 1;
    if (!reader.read(&decoded->audio, 0, totalSamples, 0, readLeft, readRight))
        return nullptr;

    if (!readRight)
        decoded->audio.copyFrom(1, 0, decoded->audio, 0, 0, totalSamples);

    return decoded;
}

int resolveStableAndroidBufferSize(juce::AudioIODevice *device, int currentBufferSize)
{
    constexpr int kTargetStableBufferSize = 512;
    constexpr int kMaxPreferredBufferSize = 1024;

    if (device == nullptr)
        return currentBufferSize > 0 ? juce::jmax(currentBufferSize, kTargetStableBufferSize)
                                     : kTargetStableBufferSize;

    const auto sizes = device->getAvailableBufferSizes();
    if (sizes.isEmpty())
        return currentBufferSize > 0 ? juce::jmax(currentBufferSize, kTargetStableBufferSize)
                                     : kTargetStableBufferSize;

    int preferredAtOrAboveTarget = 0;
    int preferredBelowTarget = 0;
    int fallback = 0;
    for (const auto size : sizes)
    {
        if (size <= 0)
            continue;

        if (fallback <= 0 || size < fallback)
            fallback = size;

        if (size >= kTargetStableBufferSize && size <= kMaxPreferredBufferSize)
        {
            if (preferredAtOrAboveTarget <= 0 || size < preferredAtOrAboveTarget)
                preferredAtOrAboveTarget = size;
            continue;
        }

        if (size < kTargetStableBufferSize && size > preferredBelowTarget)
            preferredBelowTarget = size;
    }

    if (preferredAtOrAboveTarget > 0)
        return preferredAtOrAboveTarget;
    if (preferredBelowTarget > 0)
        return preferredBelowTarget;
    if (fallback > 0)
        return fallback;

    return currentBufferSize > 0 ? currentBufferSize : kTargetStableBufferSize;
}

void sanitiseAutomationPoints(std::vector<AutomationPoint> &points, float maxValue);

TimelineClipProcessorBase *asTimelineProcessor(juce::AudioProcessorGraph::Node::Ptr &node)
{
    if (!node)
        return nullptr;
    return dynamic_cast<TimelineClipProcessorBase *>(node->getProcessor());
}

TimelineClipProcessorBase *asTimelineProcessor(juce::AudioProcessor *processor)
{
    return dynamic_cast<TimelineClipProcessorBase *>(processor);
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

double getKnownDeviceSampleRate(const juce::AudioDeviceManager &deviceManager, double fallbackRate)
{
    const auto setup = deviceManager.getAudioDeviceSetup();
    return setup.sampleRate > 1000.0 ? setup.sampleRate : fallbackRate;
}

int getKnownDeviceBufferSize(const juce::AudioDeviceManager &deviceManager, int fallbackBufferSize)
{
    const auto setup = deviceManager.getAudioDeviceSetup();
    return setup.bufferSize > 0 ? setup.bufferSize : fallbackBufferSize;
}

class OfflineExportPlayHead final : public juce::AudioPlayHead
{
public:
    void setTransport(double timeSeconds, double sampleRate, double bpm, bool isPlaying)
    {
        juce::AudioPlayHead::PositionInfo next;
        const double safeSeconds = juce::jmax(0.0, timeSeconds);
        const double safeSampleRate = sampleRate > 0.0 ? sampleRate : 44100.0;
        const double safeBpm = juce::jlimit(1.0, 400.0, bpm);
        const double ppq = safeSeconds * safeBpm / 60.0;
        constexpr int numerator = 4;
        constexpr int denominator = 4;
        const double beatsPerBar =
            (double)numerator * (4.0 / (double)denominator);
        const double lastBarStartPpq =
            std::floor(ppq / juce::jmax(1.0, beatsPerBar)) *
            juce::jmax(1.0, beatsPerBar);

        next.setTimeInSeconds(safeSeconds);
        next.setTimeInSamples((int64_t)std::llround(safeSeconds * safeSampleRate));
        next.setBpm(safeBpm);
        next.setTimeSignature(juce::AudioPlayHead::TimeSignature{numerator, denominator});
        next.setPpqPosition(ppq);
        next.setPpqPositionOfLastBarStart(lastBarStartPpq);
        next.setIsPlaying(isPlaying);
        next.setIsRecording(false);
        position = next;
    }

    juce::Optional<juce::AudioPlayHead::PositionInfo> getPosition() const override
    {
        return position;
    }

private:
    juce::AudioPlayHead::PositionInfo position;
};

void connectStereo(juce::AudioProcessorGraph &graph,
                   juce::AudioProcessorGraph::NodeID src,
                   juce::AudioProcessorGraph::NodeID dst,
                   juce::AudioProcessorGraph::UpdateKind updateKind = juce::AudioProcessorGraph::UpdateKind::sync)
{
    for (int ch = 0; ch < 2; ++ch)
        graph.addConnection({{src, ch}, {dst, ch}}, updateKind);
}

void disconnectStereo(juce::AudioProcessorGraph &graph,
                      juce::AudioProcessorGraph::NodeID src,
                      juce::AudioProcessorGraph::NodeID dst,
                      juce::AudioProcessorGraph::UpdateKind updateKind = juce::AudioProcessorGraph::UpdateKind::sync)
{
    for (int ch = 0; ch < 2; ++ch)
        graph.removeConnection({{src, ch}, {dst, ch}}, updateKind);
}

void clearStereoConnectionsBetweenNodes(
    juce::AudioProcessorGraph &graph,
    const juce::Array<juce::AudioProcessorGraph::NodeID> &nodeIds,
    juce::AudioProcessorGraph::UpdateKind updateKind = juce::AudioProcessorGraph::UpdateKind::sync)
{
    std::unordered_set<juce::uint32> localNodeUids;
    localNodeUids.reserve((size_t)nodeIds.size());
    for (auto nodeId : nodeIds)
        localNodeUids.insert(nodeId.uid);

    juce::Array<juce::AudioProcessorGraph::Connection> toRemove;
    for (const auto &connection : graph.getConnections())
    {
        if (connection.source.channelIndex < 0 || connection.source.channelIndex >= 2 ||
            connection.destination.channelIndex < 0 || connection.destination.channelIndex >= 2)
            continue;
        if (localNodeUids.find(connection.source.nodeID.uid) == localNodeUids.end() ||
            localNodeUids.find(connection.destination.nodeID.uid) == localNodeUids.end())
            continue;
        toRemove.add(connection);
    }

    for (const auto &connection : toRemove)
        graph.removeConnection(connection, updateKind);
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
    for (std::size_t i = 0; i < liveMidiInputAudioQueue.size(); ++i)
        liveMidiInputAudioQueue[i].sequence.store(i, std::memory_order_relaxed);
}

JuceEngine::~JuceEngine()
{
    // shutdownEngine();
}

struct JuceEngine::PreparedMidiClipLoad
{
    int clipId = -1;
    int rowId = -1;
    juce::String instrumentId;
    juce::String instrumentName;
    juce::Array<TimelineMidiNote> notes;
    juce::NamedValueSet params;
    double sourceTempoBpm = 120.0;
    double startSec = 0.0;
    double lengthSec = 0.0;
    double inFileOffsetSec = 0.0;
    std::int64_t loadRequestId = 0;
    std::uint64_t engineGeneration = 0;
    std::unique_ptr<juce::AudioProcessor> processor;
};

bool JuceEngine::isBuiltInMidiInstrumentIdentifier(
    const juce::String &instrumentId)
{
    const auto id = instrumentId.trim().toLowerCase();
    return id.startsWith("mixroom.") ||
           id.startsWith("sfz.") ||
           id.startsWith("sfz_asset:");
}

void JuceEngine::logCurrentAudioDeviceState(const juce::String &reason) const
{
    auto *device = deviceManager.getCurrentAudioDevice();
    if (device == nullptr)
    {
        juceLogToFlutter(("AudioDevice[" + reason + "]: none").toRawUTF8());
        return;
    }

    const auto inActive = device->getActiveInputChannels().countNumberOfSetBits();
    const auto outActive = device->getActiveOutputChannels().countNumberOfSetBits();
    const auto inTotal = device->getInputChannelNames().size();
    const auto outTotal = device->getOutputChannelNames().size();
    const double sampleRate =
        getKnownDeviceSampleRate(deviceManager, hostSampleRateAtomic.load(std::memory_order_relaxed));
    const int bufferSize = getKnownDeviceBufferSize(deviceManager, 512);

    juceLogToFlutter(("AudioDevice[" + reason + "]: " + device->getName() +
                      " sr=" + juce::String(sampleRate, 2) +
                      " bs=" + juce::String(bufferSize) +
                      " inActive=" + juce::String(inActive) +
                      " outActive=" + juce::String(outActive) +
                      " inTotal=" + juce::String(inTotal) +
                      " outTotal=" + juce::String(outTotal))
                         .toRawUTF8());
}

bool JuceEngine::applyPreferredAudioDeviceSetup(int desiredInputChannels,
                                                bool forceReopen,
                                                const juce::String &reason)
{
    desiredInputChannels = juce::jmax(0, desiredInputChannels);
    const int previousDesiredInputs =
        desiredInputOpenChannels.load(std::memory_order_relaxed);

#if JUCE_ANDROID
    if (desiredInputChannels > 0 &&
        juce::RuntimePermissions::isRequired(juce::RuntimePermissions::recordAudio) &&
        !juce::RuntimePermissions::isGranted(juce::RuntimePermissions::recordAudio))
    {
        juceLogToFlutter(("setAudioDeviceSetup blocked [" + reason + "]: RECORD_AUDIO not granted").toRawUTF8());
        // Drop back to playback-only target so route-refresh logic does not
        // repeatedly re-arm inputs while permission is denied.
        desiredInputOpenChannels.store(0, std::memory_order_relaxed);
        return false;
    }
#endif

    auto setup = deviceManager.getAudioDeviceSetup();
    const auto currentSetup = setup;
    captureRecordingRestorePlaybackSetupIfNeeded(desiredInputChannels, currentSetup);

    // Preserve the existing output route when possible, but recover from stale
    // zero-output configurations caused by route churn.
    const auto availableOutputNames = getAvailableOutputDeviceNamesForManager(deviceManager);
    if (!availableOutputNames.isEmpty() && !availableOutputNames.contains(setup.outputDeviceName))
    {
        const auto defaultOutputName = getDefaultOutputDeviceNameForManager(deviceManager);
        setup.outputDeviceName = defaultOutputName.isNotEmpty() ? defaultOutputName
                                                                : availableOutputNames[0];
    }
    if (desiredInputChannels <= 0)
    {
        setup.useDefaultOutputChannels = true;
        setup.outputChannels.clear();
    }
    else if (!setup.useDefaultOutputChannels && setup.outputChannels.isZero())
        setup.useDefaultOutputChannels = true;

#if JUCE_ANDROID
    auto *device = deviceManager.getCurrentAudioDevice();
    const int stableBufferSize = resolveStableAndroidBufferSize(device, setup.bufferSize);
    if (stableBufferSize > 0)
        setup.bufferSize = stableBufferSize;
#endif

    setup.useDefaultInputChannels = false;
    setup.inputChannels.clear();

    int inputsToOpen = desiredInputChannels;
    if (inputsToOpen > 0)
    {
        const auto availableInputNames = getAvailableInputDeviceNamesForManager(deviceManager);
        if (!availableInputNames.isEmpty() && !availableInputNames.contains(setup.inputDeviceName))
        {
            const auto defaultInputName = getDefaultInputDeviceNameForManager(deviceManager);
            setup.inputDeviceName = defaultInputName.isNotEmpty() ? defaultInputName
                                                                  : availableInputNames[0];
        }

        if (auto *device = deviceManager.getCurrentAudioDevice())
        {
            const int availableInputs = device->getInputChannelNames().size();
            if (availableInputs > 0)
                inputsToOpen = juce::jmin(inputsToOpen, availableInputs);
        }

        inputsToOpen = juce::jlimit(1, 32, inputsToOpen);
        for (int ch = 0; ch < inputsToOpen; ++ch)
            setup.inputChannels.setBit(ch);
    }

    const bool nonBufferSetupChanged =
        currentSetup.useDefaultOutputChannels != setup.useDefaultOutputChannels ||
        currentSetup.outputChannels != setup.outputChannels ||
        currentSetup.useDefaultInputChannels != setup.useDefaultInputChannels ||
        currentSetup.inputChannels != setup.inputChannels;
    const bool bufferSizeChanged = currentSetup.bufferSize != setup.bufferSize;
#if JUCE_ANDROID
    constexpr int kProblematicAndroidBufferSize = 1024;
    const bool shouldForceBufferOnlyReopen =
        !nonBufferSetupChanged &&
        bufferSizeChanged &&
        currentSetup.bufferSize > kProblematicAndroidBufferSize &&
        setup.bufferSize > 0;
#else
    const bool shouldForceBufferOnlyReopen = false;
#endif

    const auto routeMatchesDesiredInputs = [&]() -> bool
    {
        auto *device = deviceManager.getCurrentAudioDevice();
        if (device == nullptr)
            return false;

        const int activeOutputs = device->getActiveOutputChannels().countNumberOfSetBits();
        if (activeOutputs <= 0)
            return false;

        const int activeInputs = device->getActiveInputChannels().countNumberOfSetBits();
        if (desiredInputChannels <= 0)
            return true;

        int availableInputs = device->getInputChannelNames().size();
        if (availableInputs <= 0)
            availableInputs = activeInputs;
        const int expectedInputs = juce::jlimit(
            1,
            32,
            juce::jmin(desiredInputChannels, juce::jmax(1, availableInputs)));
        return activeInputs >= expectedInputs;
    };

    if (!nonBufferSetupChanged &&
        routeMatchesDesiredInputs() &&
        !shouldForceBufferOnlyReopen)
    {
        if (bufferSizeChanged)
        {
            juceLogToFlutter(("Skipping Android buffer-only reopen [" + reason +
                              "] current=" + juce::String(currentSetup.bufferSize) +
                              " target=" + juce::String(setup.bufferSize))
                                 .toRawUTF8());
        }
        const double sr =
            getKnownDeviceSampleRate(deviceManager, hostSampleRateAtomic.load(std::memory_order_relaxed));
        if (sr > 1000.0)
            hostSampleRateAtomic.store(sr, std::memory_order_relaxed);
        desiredInputOpenChannels.store(desiredInputChannels, std::memory_order_relaxed);
        return true;
    }

    juce::String error = deviceManager.setAudioDeviceSetup(setup, false);
    if (error.isEmpty())
        ignoredDeviceChangeCallbacks.fetch_add(1, std::memory_order_relaxed);
    if (!error.isEmpty())
    {
        if (forceReopen)
        {
            // Fallback when non-reopen apply fails on certain routes.
            error = deviceManager.setAudioDeviceSetup(setup, true);
            if (error.isEmpty())
                ignoredDeviceChangeCallbacks.fetch_add(1, std::memory_order_relaxed);
        }
    }
    else if (!routeMatchesDesiredInputs())
    {
        if (forceReopen)
        {
            // Fallback when non-reopen apply reports success but route state is stale.
            error = deviceManager.setAudioDeviceSetup(setup, true);
            if (error.isEmpty())
                ignoredDeviceChangeCallbacks.fetch_add(1, std::memory_order_relaxed);
        }
        else
        {
            juceLogToFlutter(("setAudioDeviceSetup stale route [" + reason + "]").toRawUTF8());
            logCurrentAudioDeviceState(reason + "-stale");
            desiredInputOpenChannels.store(previousDesiredInputs, std::memory_order_relaxed);
            return false;
        }
    }

    if (!error.isEmpty())
    {
        juceLogToFlutter(("setAudioDeviceSetup failed [" + reason + "]: " + error).toRawUTF8());
        logCurrentAudioDeviceState(reason + "-error");
        desiredInputOpenChannels.store(previousDesiredInputs, std::memory_order_relaxed);
        return false;
    }

    // Important on Android: a reopen can report success while the route still
    // resolves to zero active outputs after Bluetooth/device churn.
    if (!routeMatchesDesiredInputs())
    {
        juceLogToFlutter(("setAudioDeviceSetup route mismatch [" + reason + "]").toRawUTF8());
        logCurrentAudioDeviceState(reason + "-post-verify-mismatch");
        desiredInputOpenChannels.store(previousDesiredInputs, std::memory_order_relaxed);
        return false;
    }

    const double sr =
        getKnownDeviceSampleRate(deviceManager, hostSampleRateAtomic.load(std::memory_order_relaxed));
    if (sr > 1000.0)
        hostSampleRateAtomic.store(sr, std::memory_order_relaxed);

    desiredInputOpenChannels.store(desiredInputChannels, std::memory_order_relaxed);
    armOutputSafetyForCurrentRoute(true);
    logCurrentAudioDeviceState(reason);
    return true;
}

void JuceEngine::captureRecordingRestorePlaybackSetupIfNeeded(
    int desiredInputChannels,
    const juce::AudioDeviceManager::AudioDeviceSetup &currentSetup)
{
    if (desiredInputChannels <= 0 || wavCapture.isActive())
        return;

    const int previousDesiredInputs =
        desiredInputOpenChannels.load(std::memory_order_relaxed);
    if (previousDesiredInputs > 0 || hasRecordingRestorePlaybackSetup)
        return;

    auto setup = currentSetup;
    setup.useDefaultOutputChannels = true;
    setup.outputChannels.clear();
    setup.useDefaultInputChannels = false;
    setup.inputChannels.clear();

    recordingRestorePlaybackSetup = setup;
    hasRecordingRestorePlaybackSetup = true;
}

bool JuceEngine::restoreRecordingPlaybackSetup(const juce::String &reason)
{
    if (!hasRecordingRestorePlaybackSetup)
        return false;

    auto setup = recordingRestorePlaybackSetup;

    const auto availableOutputNames = getAvailableOutputDeviceNamesForManager(deviceManager);
    if (!availableOutputNames.isEmpty() && !availableOutputNames.contains(setup.outputDeviceName))
    {
        const auto defaultOutputName = getDefaultOutputDeviceNameForManager(deviceManager);
        setup.outputDeviceName = defaultOutputName.isNotEmpty() ? defaultOutputName
                                                                : availableOutputNames[0];
    }
    setup.useDefaultOutputChannels = true;
    setup.outputChannels.clear();

    setup.useDefaultInputChannels = false;
    setup.inputChannels.clear();

#if JUCE_ANDROID
    if (auto *device = deviceManager.getCurrentAudioDevice())
    {
        const int stableBufferSize = resolveStableAndroidBufferSize(device, setup.bufferSize);
        if (stableBufferSize > 0)
            setup.bufferSize = stableBufferSize;
    }
#endif

    deviceManager.removeChangeListener(this);
    deviceManager.closeAudioDevice();
    const juce::String error = deviceManager.setAudioDeviceSetup(setup, true);
    deviceManager.addChangeListener(this);

    if (!error.isEmpty())
    {
        juceLogToFlutter(("restoreRecordingPlaybackSetup failed [" + reason + "]: " + error).toRawUTF8());
        logCurrentAudioDeviceState(reason + "-error");
        return false;
    }

    auto *device = deviceManager.getCurrentAudioDevice();
    const int activeOutputs = device != nullptr
                                  ? device->getActiveOutputChannels().countNumberOfSetBits()
                                  : 0;
    if (activeOutputs <= 0)
    {
        juceLogToFlutter(("restoreRecordingPlaybackSetup missing output route [" + reason + "]").toRawUTF8());
        logCurrentAudioDeviceState(reason + "-post-verify-mismatch");
        return false;
    }

    const double sr =
        getKnownDeviceSampleRate(deviceManager, hostSampleRateAtomic.load(std::memory_order_relaxed));
    if (sr > 1000.0)
        hostSampleRateAtomic.store(sr, std::memory_order_relaxed);

    desiredInputOpenChannels.store(0, std::memory_order_relaxed);
    recordingRestoreDesiredInputs.store(0, std::memory_order_relaxed);
    hasRecordingRestorePlaybackSetup = false;
    armOutputSafetyForCurrentRoute(true);
    logCurrentAudioDeviceState(reason);
    return true;
}

void JuceEngine::requestAudioDeviceRefreshAsync(const juce::String &reason)
{
    audioRouteRefreshPending.store(true, std::memory_order_release);
    flushDeferredAudioRouteRefreshAsync(reason);
}

void JuceEngine::flushDeferredAudioRouteRefreshAsync(const juce::String &reason)
{
    juce::MessageManager::callAsync([this, reason]
                                    {
        if (!engineInitialized)
        {
            audioRouteRefreshPending.store(false, std::memory_order_release);
            return;
        }

        if (exportInProgressAtomic.load(std::memory_order_relaxed))
            return;

        if (!audioRouteRefreshPending.exchange(false, std::memory_order_acq_rel))
            return;

        const int requestedInputs = desiredInputOpenChannels.load(std::memory_order_relaxed);
        applyPreferredAudioDeviceSetup(requestedInputs, true, "async-refresh:" + reason);
        const bool midiLiveInputActive =
            liveMidiInputTargetClip.load(std::memory_order_relaxed) >= 0;
        if (midiLiveInputActive || midiInputCallbacksInitialized.load(std::memory_order_relaxed))
            refreshMidiInputCallbacks();

        if (wavCapture.isActive())
            routeLiveInputToRow(/*row=*/0,
                                liveMonitorChannelCount,
                                liveMonitorChannelStart); });
}

void JuceEngine::prepareRecordingInputsAsync(int desiredInputChannels,
                                             const juce::String &reason)
{
    desiredInputChannels = juce::jmax(0, desiredInputChannels);
    desiredInputOpenChannels.store(desiredInputChannels, std::memory_order_relaxed);
    requestAudioDeviceRefreshAsync("prepareRecordingInputs:" + reason);
}

bool JuceEngine::prepareRecordingInputs(int desiredInputChannels,
                                        const juce::String &reason)
{
    desiredInputChannels = juce::jmax(0, desiredInputChannels);

    if (applyPreferredAudioDeviceSetup(desiredInputChannels,
                                       false,
                                       "prepareRecordingInputs:" + reason))
        return true;

    return applyPreferredAudioDeviceSetup(desiredInputChannels,
                                          true,
                                          "prepareRecordingInputs-reopen:" + reason);
}

void JuceEngine::refreshAudioRouteAsync(const juce::String &reason)
{
    requestAudioDeviceRefreshAsync("manual-refresh:" + reason);
}

bool JuceEngine::preparePlaybackGraph(const juce::String &reason)
{
    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
        ensureMasterOutputRouting();
    }

    auto *device = deviceManager.getCurrentAudioDevice();
    const bool ready =
        device != nullptr &&
        device->getActiveOutputChannels().countNumberOfSetBits() > 0;
    if (!ready)
        juceLogToFlutter(("preparePlaybackGraph failed [" + reason + "]").toRawUTF8());
    return ready;
}

bool JuceEngine::hardResetPlaybackOnlyRoute(const juce::String &reason)
{
    desiredInputOpenChannels.store(0, std::memory_order_relaxed);
    recordingRestoreDesiredInputs.store(0, std::memory_order_relaxed);

    if (restoreRecordingPlaybackSetup(reason + "-snapshot"))
        return true;

    auto setup = deviceManager.getAudioDeviceSetup();

    const auto availableOutputNames = getAvailableOutputDeviceNamesForManager(deviceManager);
    if (!availableOutputNames.isEmpty() && !availableOutputNames.contains(setup.outputDeviceName))
    {
        const auto defaultOutputName = getDefaultOutputDeviceNameForManager(deviceManager);
        setup.outputDeviceName = defaultOutputName.isNotEmpty() ? defaultOutputName
                                                                : availableOutputNames[0];
    }
    setup.useDefaultOutputChannels = true;
    setup.outputChannels.clear();

    setup.useDefaultInputChannels = false;
    setup.inputChannels.clear();

#if JUCE_ANDROID
    if (auto *device = deviceManager.getCurrentAudioDevice())
    {
        const int stableBufferSize = resolveStableAndroidBufferSize(device, setup.bufferSize);
        if (stableBufferSize > 0)
            setup.bufferSize = stableBufferSize;
    }
#endif

    deviceManager.removeChangeListener(this);
    deviceManager.closeAudioDevice();
    const juce::String error = deviceManager.setAudioDeviceSetup(setup, true);
    deviceManager.addChangeListener(this);

    if (!error.isEmpty())
    {
        juceLogToFlutter(("hardResetPlaybackOnlyRoute failed [" + reason + "]: " + error).toRawUTF8());
        logCurrentAudioDeviceState(reason + "-error");
        return false;
    }

    const double sr =
        getKnownDeviceSampleRate(deviceManager, hostSampleRateAtomic.load(std::memory_order_relaxed));
    if (sr > 1000.0)
        hostSampleRateAtomic.store(sr, std::memory_order_relaxed);

    armOutputSafetyForCurrentRoute(true);
    logCurrentAudioDeviceState(reason);
    return true;
}

void JuceEngine::changeListenerCallback(juce::ChangeBroadcaster *source)
{
    if (source != &deviceManager || !engineInitialized)
        return;

    int ignored = ignoredDeviceChangeCallbacks.load(std::memory_order_relaxed);
    while (ignored > 0)
    {
        if (ignoredDeviceChangeCallbacks.compare_exchange_weak(
                ignored,
                ignored - 1,
                std::memory_order_acq_rel,
                std::memory_order_relaxed))
            return;
    }

    const double sr =
        getKnownDeviceSampleRate(deviceManager, hostSampleRateAtomic.load(std::memory_order_relaxed));
    if (sr > 1000.0)
        hostSampleRateAtomic.store(sr, std::memory_order_relaxed);
    prepareLiveClipProcessorsForCurrentDevice();

    logCurrentAudioDeviceState("device-change");
    armOutputSafetyForCurrentRoute(true);

    auto *device = deviceManager.getCurrentAudioDevice();
    const int desiredInputs = desiredInputOpenChannels.load(std::memory_order_relaxed);
    const int activeInputs = device != nullptr
                                 ? device->getActiveInputChannels().countNumberOfSetBits()
                                 : 0;
    const int availableInputs = device != nullptr
                                    ? device->getInputChannelNames().size()
                                    : 0;

    bool inputRouteMismatch = (device == nullptr);
    if (!inputRouteMismatch && desiredInputs > 0)
    {
        const int expectedInputs = juce::jlimit(
            1,
            32,
            juce::jmin(desiredInputs, juce::jmax(1, availableInputs > 0 ? availableInputs : activeInputs)));
        inputRouteMismatch = activeInputs < expectedInputs;
    }

    const int activeOutputs = device != nullptr
                                  ? device->getActiveOutputChannels().countNumberOfSetBits()
                                  : 0;
    const bool playbackRouteMismatch = (device == nullptr) || activeOutputs <= 0;

    if (playbackRouteMismatch || inputRouteMismatch)
        requestAudioDeviceRefreshAsync("device-change");
}

void JuceEngine::armOutputSafetyForCurrentRoute(bool fadeIn) noexcept
{
    if (fadeIn)
    {
        const int fadeSamples = juce::jlimit(
            64,
            9600,
            (int)std::lround(juce::jmax(
                                 8000.0,
                                 getKnownDeviceSampleRate(
                                     deviceManager,
                                     hostSampleRateAtomic.load(std::memory_order_relaxed))) *
                             0.05));
        outputSafetyRequestedFadeSamples.store(fadeSamples, std::memory_order_release);
        outputSafetyControlRequest.store(kOutputSafetyRequestFadeIn, std::memory_order_release);
        return;
    }

    outputSafetyControlRequest.store(kOutputSafetyRequestClear, std::memory_order_release);
}

void JuceEngine::recordRealtimeAudioCallback(int numSamples,
                                             double sampleRate,
                                             std::int64_t elapsedTicks) noexcept
{
    if (elapsedTicks <= 0)
        return;

    auto ticksPerSecond = realtimeTicksPerSecond.load(std::memory_order_relaxed);
    if (ticksPerSecond <= 0)
    {
        const auto detectedTicksPerSecond =
            (std::int64_t)juce::Time::getHighResolutionTicksPerSecond();
        std::int64_t expected = 0;
        realtimeTicksPerSecond.compare_exchange_strong(
            expected,
            detectedTicksPerSecond,
            std::memory_order_relaxed,
            std::memory_order_relaxed);
        ticksPerSecond = realtimeTicksPerSecond.load(std::memory_order_relaxed);
    }

    realtimeCallbackCount.fetch_add(1, std::memory_order_relaxed);
    if (androidV2CallbackProofPending.exchange(false, std::memory_order_acq_rel))
        androidV2CallbackReady.signal();
    realtimeCallbackTotalTicks.fetch_add((std::uint64_t)elapsedTicks, std::memory_order_relaxed);
    realtimeCallbackLastTicks.store(elapsedTicks, std::memory_order_relaxed);
    updateAtomicMax(realtimeCallbackMaxTicks, elapsedTicks);
    updateAtomicMax(realtimeCallbackMaxSamples, juce::jmax(0, numSamples));

    if (sampleRate > 0.0 && numSamples > 0 && ticksPerSecond > 0)
    {
        const auto budgetTicks =
            (std::int64_t)(((double)ticksPerSecond * (double)numSamples) / sampleRate);
        if (budgetTicks > 0 && elapsedTicks > budgetTicks)
            realtimeCallbackOverBudgetCount.fetch_add(1, std::memory_order_relaxed);
    }
}

void JuceEngine::resetRealtimePerformanceStats() noexcept
{
    realtimeTicksPerSecond.store(
        (std::int64_t)juce::Time::getHighResolutionTicksPerSecond(),
        std::memory_order_relaxed);
    realtimeCallbackCount.store(0, std::memory_order_relaxed);
    realtimeCallbackTotalTicks.store(0, std::memory_order_relaxed);
    realtimeCallbackLastTicks.store(0, std::memory_order_relaxed);
    realtimeCallbackMaxTicks.store(0, std::memory_order_relaxed);
    realtimeCallbackOverBudgetCount.store(0, std::memory_order_relaxed);
    realtimeCallbackMaxSamples.store(0, std::memory_order_relaxed);
    graphRebuildImmediateCount.store(0, std::memory_order_relaxed);
    graphRebuildDeferredCount.store(0, std::memory_order_relaxed);
    graphRebuildBatchCommitCount.store(0, std::memory_order_relaxed);
    graphRebuildProjectLoadCommitCount.store(0, std::memory_order_relaxed);
}

void JuceEngine::recordGraphRebuildRequest(bool deferred,
                                           bool batchCommit,
                                           bool projectLoadCommit) noexcept
{
    if (deferred)
    {
        graphRebuildDeferredCount.fetch_add(1, std::memory_order_relaxed);
        return;
    }

    if (batchCommit)
    {
        graphRebuildBatchCommitCount.fetch_add(1, std::memory_order_relaxed);
        return;
    }

    if (projectLoadCommit)
    {
        graphRebuildProjectLoadCommitCount.fetch_add(1, std::memory_order_relaxed);
        return;
    }

    graphRebuildImmediateCount.fetch_add(1, std::memory_order_relaxed);
}

void JuceEngine::commitGraphMutationLocked(bool armOutputSafety) noexcept
{
    if (projectClipLoadTransactionDepth > 0)
    {
        recordGraphRebuildRequest(true, false, false);
        projectClipLoadNeedsGraphRebuild = true;
        projectClipLoadNeedsOutputSafety =
            projectClipLoadNeedsOutputSafety || armOutputSafety;
        return;
    }

    if (graphMutationBatchDepth > 0)
    {
        recordGraphRebuildRequest(true, false, false);
        graphMutationBatchNeedsRebuild = true;
        graphMutationBatchNeedsOutputSafety =
            graphMutationBatchNeedsOutputSafety || armOutputSafety;
        return;
    }

    recordGraphRebuildRequest(false, false, false);
    requestGraphRebuildAsync(graph);
    if (armOutputSafety)
        armOutputSafetyForCurrentRoute();
}

void JuceEngine::refreshMidiInputCallbacks()
{
    const auto devices = juce::MidiInput::getAvailableDevices();
    std::vector<juce::String> nextIds;
    nextIds.reserve((size_t)devices.size());

    for (const auto &device : devices)
    {
        nextIds.push_back(device.identifier);
        const bool alreadyRegistered = std::find(
                                           midiInputCallbackDeviceIds.begin(),
                                           midiInputCallbackDeviceIds.end(),
                                           device.identifier) != midiInputCallbackDeviceIds.end();

        deviceManager.setMidiInputDeviceEnabled(device.identifier, true);
        if (!alreadyRegistered)
        {
            deviceManager.addMidiInputDeviceCallback(device.identifier, this);
            midiInputCallbackDeviceIds.push_back(device.identifier);
        }
    }

    for (auto it = midiInputCallbackDeviceIds.begin();
         it != midiInputCallbackDeviceIds.end();)
    {
        if (std::find(nextIds.begin(), nextIds.end(), *it) != nextIds.end())
        {
            ++it;
            continue;
        }

        deviceManager.removeMidiInputDeviceCallback(*it, this);
        deviceManager.setMidiInputDeviceEnabled(*it, false);
        it = midiInputCallbackDeviceIds.erase(it);
    }

    midiInputCallbacksInitialized.store(true, std::memory_order_relaxed);
}

void JuceEngine::clearMidiInputCallbacks()
{
    for (const auto &id : midiInputCallbackDeviceIds)
    {
        deviceManager.removeMidiInputDeviceCallback(id, this);
        deviceManager.setMidiInputDeviceEnabled(id, false);
    }
    midiInputCallbackDeviceIds.clear();
    midiInputCallbacksInitialized.store(false, std::memory_order_relaxed);
}

// ============================================================
// Initialise / Shutdown
// ============================================================
void JuceEngine::registerFormatsIfNeeded()
{
    if (formatsRegistered)
        return;

    formatManager.registerBasicFormats();
    pluginFormatManager.addDefaultFormats();
#if JUCE_IOS
    pluginFormatManager.addFormat(new juce::AudioUnitPluginFormat());
#endif
    formatsRegistered = true;
}

void JuceEngine::initialiseSharedPlaybackGraph()
{
    const double hostRate = getKnownDeviceSampleRate(deviceManager, 44100.0);
    const int blockSize = getKnownDeviceBufferSize(deviceManager, 512);

    // graph.prepareToPlay(hostRate, blockSize);
    // juceLogToFlutter(("graph.prepareToPlay(" + String(hostRate) + ", " + String(blockSize) + ")").toRawUTF8());

    audioPlayer.setProcessor(&graph);
    if (!metronomeCallback)
        metronomeCallback =
            std::make_unique<MetronomeAudioCallback>(audioPlayer, *this);

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
    }

    // Build bus graph (rows + master)
    ensureBusGraphInitialised();

    hostSampleRateAtomic.store(hostRate, std::memory_order_relaxed);

    graph.prepareToPlay(hostRate, blockSize);
    prepareLiveClipProcessorsForCurrentDevice();
    juceLogToFlutter(("graph.prepareToPlay(" + String(hostRate) + ", " + String(blockSize) + ")").toRawUTF8());

    // Only expose the live callback after the graph and IO nodes are fully ready.
    deviceManager.addAudioCallback(metronomeCallback.get());
    audioCallbackAttached = true;

    // Register plugin/MIDI input callbacks lazily on demand.
    // Eager scanning here can stall first project open on iOS route discovery.
    engineInitialized = true;
}

void JuceEngine::initialiseEngine()
{
    const std::lock_guard<std::mutex> lifecycleLock(engineLifecycleMutex);
    juceLogToFlutter("Hello from JuceEngine::initialiseEngine()");

    if (engineInitialized)
    {
        juceLogToFlutter("JuceEngine::initialiseEngine() already called — skipping.");
        return;
    }

    desiredInputOpenChannels.store(0, std::memory_order_relaxed);
    recordingRestoreDesiredInputs.store(0, std::memory_order_relaxed);
    hasRecordingRestorePlaybackSetup = false;
    ignoredDeviceChangeCallbacks.store(0, std::memory_order_relaxed);

    const bool shouldOpenInitialDevice = !formatsRegistered;
    registerFormatsIfNeeded();
    if (shouldOpenInitialDevice)
    {
        // Android startup should not depend on mic input availability/permission.
        // Arm inputs only when recording is explicitly requested.
        juce::String initError = deviceManager.initialise(
            0, // numInputChannels
            2, // numOutputChannels
            nullptr,
            true);
        if (!initError.isEmpty())
        {
            juceLogToFlutter(("AudioDevice initialise failed [0-in/2-out]: " + initError).toRawUTF8());
            // Last-resort fallback to JUCE default route selection.
            initError = deviceManager.initialise(0, 2, nullptr, true, {}, nullptr);
            if (!initError.isEmpty())
            {
                juceLogToFlutter(("AudioDevice initialise fallback failed: " + initError).toRawUTF8());
            }
        }
        logCurrentAudioDeviceState("initialise");
    }
    deviceManager.removeChangeListener(this);
    deviceManager.addChangeListener(this);

#if JUCE_ANDROID
    if (applyPreferredAudioDeviceSetup(0, true, "initialise-playback-buffer"))
        logCurrentAudioDeviceState("initialise-playback-buffer");
#endif

    initialiseSharedPlaybackGraph();
}

bool JuceEngine::initialisePlaybackV2Android()
{
#if JUCE_ANDROID
    const std::lock_guard<std::mutex> lifecycleLock(engineLifecycleMutex);
    if (engineInitialized)
        return false;

    desiredInputOpenChannels.store(0, std::memory_order_relaxed);
    recordingRestoreDesiredInputs.store(0, std::memory_order_relaxed);
    hasRecordingRestorePlaybackSetup = false;
    androidV2RecordingPrepared = false;
    androidV2CallbackReady.reset();
    androidV2CallbackProofPending.store(false, std::memory_order_release);
    ignoredDeviceChangeCallbacks.store(0, std::memory_order_relaxed);

    registerFormatsIfNeeded();
    const juce::String initError = deviceManager.initialise(
        0, // numInputChannels
        2, // numOutputChannels
        nullptr,
        true);
    auto *device = deviceManager.getCurrentAudioDevice();
    if (!initError.isEmpty() || device == nullptr || !device->isOpen() ||
        device->getActiveOutputChannels().countNumberOfSetBits() <= 0 ||
        device->getActiveInputChannels().countNumberOfSetBits() != 0)
    {
        juceLogToFlutter(("Android V2 output-only initialise failed: " + initError).toRawUTF8());
        androidV2CallbackProofPending.store(false, std::memory_order_release);
        deviceManager.closeAudioDevice();
        return false;
    }

    deviceManager.removeChangeListener(this);
    androidV2CallbackProofPending.store(true, std::memory_order_release);
    initialiseSharedPlaybackGraph();
    v2PlaybackCallbackDetached = false;
    logCurrentAudioDeviceState("android-v2-initialise");
    const bool initialised = engineInitialized && audioCallbackAttached;
    if (!initialised)
    {
        androidV2CallbackProofPending.store(false, std::memory_order_release);
        androidV2CallbackReady.reset();
    }
    return initialised;
#else
    return false;
#endif
}

bool JuceEngine::quiescePlaybackV2Android(bool closeDevice)
{
#if JUCE_ANDROID
    if (!engineInitialized || metronomeCallback == nullptr)
        return false;

    const bool wasPlaying = isPlayingAtomic.load(std::memory_order_relaxed);
    pause();
    if (!v2PlaybackCallbackDetached && audioCallbackAttached)
    {
        deviceManager.removeAudioCallback(metronomeCallback.get());
        audioCallbackAttached = false;
        v2PlaybackCallbackDetached = true;
    }
    if (closeDevice)
        deviceManager.closeAudioDevice();
    return wasPlaying;
#else
    juce::ignoreUnused(closeDevice);
    return false;
#endif
}

bool JuceEngine::reconfigurePlaybackV2Android()
{
#if JUCE_ANDROID
    if (!engineInitialized || metronomeCallback == nullptr)
        return false;

    androidV2RecordingPrepared = false;
    androidV2CallbackReady.reset();
    androidV2CallbackProofPending.store(false, std::memory_order_release);
    quiescePlaybackV2Android(false);
    deviceManager.closeAudioDevice();
    const juce::String initError = deviceManager.initialise(
        0, // numInputChannels
        2, // numOutputChannels
        nullptr,
        true);
    auto *device = deviceManager.getCurrentAudioDevice();
    const bool valid = initError.isEmpty() && device != nullptr && device->isOpen() &&
        device->getActiveOutputChannels().countNumberOfSetBits() > 0 &&
        device->getActiveInputChannels().countNumberOfSetBits() == 0 &&
        device->getCurrentSampleRate() > 1000.0 &&
        device->getCurrentBufferSizeSamples() > 0;
    if (!valid)
    {
        juceLogToFlutter(("Android V2 route reopen failed: " + initError).toRawUTF8());
        androidV2CallbackProofPending.store(false, std::memory_order_release);
        deviceManager.closeAudioDevice();
        return false;
    }

    hostSampleRateAtomic.store(device->getCurrentSampleRate(), std::memory_order_relaxed);
    desiredInputOpenChannels.store(0, std::memory_order_relaxed);
    prepareLiveClipProcessorsForCurrentDevice();
    armOutputSafetyForCurrentRoute(true);
    androidV2CallbackProofPending.store(true, std::memory_order_release);
    deviceManager.addAudioCallback(metronomeCallback.get());
    audioCallbackAttached = true;
    v2PlaybackCallbackDetached = false;
    logCurrentAudioDeviceState("android-v2-route-transition");
    return true;
#else
    return false;
#endif
}

bool JuceEngine::prepareRecordingV2Android(int inputChannels)
{
    return prepareDefaultDuplexV2Android(inputChannels);
}

bool JuceEngine::prepareSystemSelectedMediaDuplexV2Android(int inputChannels)
{
    return prepareDefaultDuplexV2Android(inputChannels);
}

bool JuceEngine::prepareDefaultDuplexV2Android(int inputChannels)
{
#if JUCE_ANDROID
    const int requestedInputs = juce::jlimit(1, 32, inputChannels);
    if (requestedInputs != inputChannels || !engineInitialized ||
        metronomeCallback == nullptr || wavCapture.isActive())
        return false;

    pause();
    androidV2RecordingPrepared = false;
    androidV2CallbackReady.reset();
    androidV2CallbackProofPending.store(false, std::memory_order_release);
    if (!v2PlaybackCallbackDetached && audioCallbackAttached)
    {
        deviceManager.removeAudioCallback(metronomeCallback.get());
        audioCallbackAttached = false;
        v2PlaybackCallbackDetached = true;
    }

    deviceManager.closeAudioDevice();
    const juce::String initError = deviceManager.initialise(
        requestedInputs,
        2,
        nullptr,
        true);
    auto *device = deviceManager.getCurrentAudioDevice();
    const bool valid = initError.isEmpty() && device != nullptr && device->isOpen() &&
        device->getActiveInputChannels().countNumberOfSetBits() == requestedInputs &&
        device->getActiveOutputChannels().countNumberOfSetBits() > 0 &&
        device->getCurrentSampleRate() > 1000.0 &&
        device->getCurrentBufferSizeSamples() > 0;
    if (!valid)
    {
        juceLogToFlutter(("Android V2 built-in recording open failed: " + initError).toRawUTF8());
        androidV2CallbackProofPending.store(false, std::memory_order_release);
        deviceManager.closeAudioDevice();
        return false;
    }

    desiredInputOpenChannels.store(requestedInputs, std::memory_order_relaxed);
    recordingRestoreDesiredInputs.store(0, std::memory_order_relaxed);
    liveInputMonitoringEnabled = false;
    hostSampleRateAtomic.store(device->getCurrentSampleRate(), std::memory_order_relaxed);
    prepareLiveClipProcessorsForCurrentDevice();
    armOutputSafetyForCurrentRoute(true);
    androidV2CallbackProofPending.store(true, std::memory_order_release);
    deviceManager.addAudioCallback(metronomeCallback.get());
    audioCallbackAttached = true;
    v2PlaybackCallbackDetached = false;
    androidV2RecordingPrepared = true;
    logCurrentAudioDeviceState("android-v2-recording-prepared");
    return true;
#else
    juce::ignoreUnused(inputChannels);
    return false;
#endif
}

bool JuceEngine::prepareBluetoothDuplexV2Android()
{
#if JUCE_ANDROID
    if (!engineInitialized || metronomeCallback == nullptr || wavCapture.isActive())
        return false;

    pause();
    androidV2RecordingPrepared = false;
    androidV2CallbackReady.reset();
    androidV2CallbackProofPending.store(false, std::memory_order_release);
    if (!v2PlaybackCallbackDetached && audioCallbackAttached)
    {
        deviceManager.removeAudioCallback(metronomeCallback.get());
        audioCallbackAttached = false;
        v2PlaybackCallbackDetached = true;
    }

    deviceManager.closeAudioDevice();
    const juce::String initError = deviceManager.initialise(1, 1, nullptr, true);
    auto *device = deviceManager.getCurrentAudioDevice();
    const bool valid = initError.isEmpty() && device != nullptr && device->isOpen() &&
        device->getActiveInputChannels().countNumberOfSetBits() == 1 &&
        device->getActiveOutputChannels().countNumberOfSetBits() == 1 &&
        device->getCurrentSampleRate() > 1000.0 &&
        device->getCurrentBufferSizeSamples() > 0;
    if (!valid)
    {
        juceLogToFlutter(("Android V2 Bluetooth duplex open failed: " + initError).toRawUTF8());
        androidV2CallbackProofPending.store(false, std::memory_order_release);
        deviceManager.closeAudioDevice();
        return false;
    }

    desiredInputOpenChannels.store(1, std::memory_order_relaxed);
    recordingRestoreDesiredInputs.store(0, std::memory_order_relaxed);
    liveInputMonitoringEnabled = false;
    hostSampleRateAtomic.store(device->getCurrentSampleRate(), std::memory_order_relaxed);
    prepareLiveClipProcessorsForCurrentDevice();
    armOutputSafetyForCurrentRoute(true);
    androidV2CallbackProofPending.store(true, std::memory_order_release);
    deviceManager.addAudioCallback(metronomeCallback.get());
    audioCallbackAttached = true;
    v2PlaybackCallbackDetached = false;
    androidV2RecordingPrepared = true;
    logCurrentAudioDeviceState("android-v2-bluetooth-recording");
    return true;
#else
    return false;
#endif
}

bool JuceEngine::waitForV2CallbackReady(int timeoutMs)
{
#if JUCE_ANDROID
    const bool ready = androidV2CallbackReady.wait(juce::jlimit(1, 5000, timeoutMs));
    androidV2CallbackProofPending.store(false, std::memory_order_release);
    return ready;
#else
    juce::ignoreUnused(timeoutMs);
    return false;
#endif
}

void JuceEngine::shutdownEngine()
{
    const std::lock_guard<std::mutex> lifecycleLock(engineLifecycleMutex);
    engineLifecycleGeneration.fetch_add(1, std::memory_order_acq_rel);
    juceLogToFlutter("JuceEngine::shutdownEngine called");
    requestLiveMidiPanicForAll(LiveMidiPanicMode::full);

    wavCapture.stop(true);
    androidV2RecordingPrepared = false;
    androidV2CallbackReady.reset();
    androidV2CallbackProofPending.store(false, std::memory_order_relaxed);

    if (!engineInitialized)
    {
        juceLogToFlutter("... skipped — engine not initialized yet.");
        return;
    }

    if (metronomeCallback)
    {
        deviceManager.removeAudioCallback(metronomeCallback.get());
        audioCallbackAttached = false;
        metronomeCallback.reset();
    }
    deviceManager.removeChangeListener(this);
    clearMidiInputCallbacks();

    audioPlayer.setProcessor(nullptr);
    deviceManager.closeAudioDevice();

    graph.clear();

    // *** IMPORTANT: clear Node::Ptr handles to old graph nodes ***
    inputNode = nullptr;
    outputNode = nullptr;
    videoAudioNode = nullptr;
    masterInputNode = nullptr;
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
    rowIdToClipIds.clear();
    publishMeterReadoutSnapshotLocked();
    clearRoutedClipSchedules();
    nextRowId.store(1);
    clips.clear();
    {
        const std::lock_guard<std::mutex> lock(decodedClipAssetCacheMutex);
        decodedClipAssetCache.clear();
    }

    // Master chain
    if (masterEffectChain != nullptr)
    {
        masterEffectChain->clear();
        delete masterEffectChain;
        masterEffectChain = nullptr;
    }
    masterEffectIds.clear();

    masterInputProcessor = nullptr;
    masterGainNode = nullptr;
    masterPanNode = nullptr;
    masterGainProcessor = nullptr;
    masterPanProcessor = nullptr;

    // Video lane
    videoAudioNode = nullptr;
    videoGainProc = nullptr;
    hasVideoAudio = false;

    desiredInputOpenChannels.store(0, std::memory_order_relaxed);
    recordingRestoreDesiredInputs.store(0, std::memory_order_relaxed);
    hasRecordingRestorePlaybackSetup = false;
    audioRouteRefreshPending.store(false, std::memory_order_relaxed);
    liveMidiInputTargetClip.store(-1, std::memory_order_relaxed);
    clearLiveMidiInputAudioQueue();
    {
        const std::lock_guard<std::mutex> lock(liveMidiInputQueueMutex);
        liveMidiInputPendingForFlutter.clear();
    }
    busGraphInitialised = false;
    engineInitialized = false;
    audioCallbackAttached = false;
    v2PlaybackCallbackDetached = false;
    androidV2RecordingPrepared = false;
    androidV2CallbackReady.reset();
    androidV2CallbackProofPending.store(false, std::memory_order_relaxed);
}

// ============================================================
// Helper: Build bus graph (rows + master)
// ============================================================
void JuceEngine::attachRowBusNodes(
    RowState &r,
    juce::AudioProcessorGraph::UpdateKind updateKind)
{
    auto ti = std::make_unique<TrackInputProcessor>();
    ti->setRoutedClipSource(this, r.rowId);
    if (rowRoutedClipScheduleSnapshot != nullptr)
    {
        if (const auto it = rowRoutedClipScheduleSnapshot->find(r.rowId);
            it != rowRoutedClipScheduleSnapshot->end() &&
            it->second != nullptr)
        {
            ti->setRoutedClipSchedule(it->second.get());
        }
    }
    ti->prepareToPlay(
        getKnownDeviceSampleRate(deviceManager, hostSampleRateAtomic.load(std::memory_order_relaxed)),
        getKnownDeviceBufferSize(deviceManager, 512));
    r.inputProc = ti.get();
    r.inputNode = graph.addNode(std::move(ti), std::nullopt, updateKind);

    auto ap = std::make_unique<VolumeAutomationProcessor>();
    r.automationProc = ap.get();
    r.automationNode = graph.addNode(std::move(ap), std::nullopt, updateKind);

    auto tg = std::make_unique<SimpleGainProcessor>();
    r.gainProc = tg.get();
    r.gainNode = graph.addNode(std::move(tg), std::nullopt, updateKind);
    r.gainProc->gain->setValueNotifyingHost(
        juce::jlimit(kGainUiMin, kGainUiMax, r.gainUi) / kGainUiMax);
    r.gainProc->setMuted(r.muted);

    auto tp = std::make_unique<StereoPanProcessor>();
    r.panProc = tp.get();
    r.panNode = graph.addNode(std::move(tp), std::nullopt, updateKind);
    r.panProc->pan->setValueNotifyingHost(panUIToNormalized(r.panUi));

    if (r.meter == nullptr)
        r.meter = std::make_shared<StereoMeterState>();

    auto mt = std::make_unique<MeterTapProcessor>(
        &r.meter->peakL,
        &r.meter->peakR,
        &r.meter->rmsL,
        &r.meter->rmsR,
        &rowMetersEnabled);

    r.meterTapProc = mt.get();
    r.meterTapNode = graph.addNode(std::move(mt), std::nullopt, updateKind);

    if (r.automationProc != nullptr)
    {
        r.automationProc->setBlockTransportPtr(&blockTransportStartSec);
        r.automationProc->setAudioRenderGenerationPtr(&routedAudioRenderGeneration);
        if (!r.automationPoints.empty())
        {
            sanitiseAutomationPoints(r.automationPoints, 1.0f);
            r.automationProc->setAutomationPoints(r.automationPoints);
        }
    }

    for (int ch = 0; ch < 2; ++ch)
    {
        graph.addConnection({{r.inputNode->nodeID, ch}, {r.automationNode->nodeID, ch}}, updateKind);
        graph.addConnection({{r.automationNode->nodeID, ch}, {r.gainNode->nodeID, ch}}, updateKind);
        graph.addConnection({{r.gainNode->nodeID, ch}, {r.panNode->nodeID, ch}}, updateKind);
        graph.addConnection({{r.panNode->nodeID, ch}, {r.meterTapNode->nodeID, ch}}, updateKind);
    }

    reconnectAllRowOutputsToBuses(updateKind);
}

void JuceEngine::ensureRowBusNodesAttached(
    int rowIndex,
    juce::AudioProcessorGraph::UpdateKind updateKind)
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

    attachRowBusNodes(r, updateKind);
    if (r.fxChain.size() > 0)
        rewireTrackBusFxChain(rowIndex, updateKind);

    if (updateKind != juce::AudioProcessorGraph::UpdateKind::none &&
        !isProjectClipLoadTransactionActive())
        armOutputSafetyForCurrentRoute();
}

void JuceEngine::retargetRowMeterTapPointers()
{
    for (auto &r : rows)
    {
        if (r.meter == nullptr)
            r.meter = std::make_shared<StereoMeterState>();

        if (r.meterTapProc != nullptr)
        {
            r.meterTapProc->setMeterTargets(
                &r.meter->peakL,
                &r.meter->peakR,
                &r.meter->rmsL,
                &r.meter->rmsR);
        }
    }

    for (auto &group : trackGroups)
    {
        if (group.meter == nullptr)
            group.meter = std::make_shared<StereoMeterState>();

        if (group.meterTapProc != nullptr)
        {
            group.meterTapProc->setMeterTargets(
                &group.meter->peakL,
                &group.meter->peakR,
                &group.meter->rmsL,
                &group.meter->rmsR);
        }
    }
}

void JuceEngine::rebuildRowIdIndexCache()
{
    rowIdToIndex.clear();
    rowIdToIndex.reserve(rows.size());
    for (int i = 0; i < (int)rows.size(); ++i)
        rowIdToIndex[rows[(size_t)i].rowId] = i;
    publishMeterReadoutSnapshotLocked();
}

JuceEngine::TrackGroupState *JuceEngine::trackGroupForId(const juce::String &groupId)
{
    const auto normalized = groupId.trim();
    if (normalized.isEmpty())
        return nullptr;
    for (auto &group : trackGroups)
        if (group.id == normalized)
            return &group;
    return nullptr;
}

const JuceEngine::TrackGroupState *JuceEngine::trackGroupForId(const juce::String &groupId) const
{
    const auto normalized = groupId.trim();
    if (normalized.isEmpty())
        return nullptr;
    for (const auto &group : trackGroups)
        if (group.id == normalized)
            return &group;
    return nullptr;
}

JuceEngine::TrackGroupState *JuceEngine::trackGroupForLeadRowIndex(int rowIndex)
{
    if (rowIndex < 0 || rowIndex >= (int)rows.size())
        return nullptr;
    const int rowId = rows[(size_t)rowIndex].rowId;
    for (auto &group : trackGroups)
        if (!group.rowIds.isEmpty() && group.rowIds[0] == rowId)
            return &group;
    return nullptr;
}

const JuceEngine::TrackGroupState *JuceEngine::trackGroupForLeadRowIndex(int rowIndex) const
{
    if (rowIndex < 0 || rowIndex >= (int)rows.size())
        return nullptr;
    const int rowId = rows[(size_t)rowIndex].rowId;
    for (const auto &group : trackGroups)
        if (!group.rowIds.isEmpty() && group.rowIds[0] == rowId)
            return &group;
    return nullptr;
}

void JuceEngine::publishMeterReadoutSnapshotLocked()
{
    auto next = std::make_shared<MeterReadoutSnapshot>();
    next->rowMeters.reserve(rows.size());

    for (int row = 0; row < (int)rows.size(); ++row)
    {
        auto &rowState = rows[(size_t)row];
        if (rowState.meter == nullptr)
            rowState.meter = std::make_shared<StereoMeterState>();

        std::shared_ptr<StereoMeterState> meter = rowState.meter;
        const auto *group = trackGroupForLeadRowIndex(row);
        if (group != nullptr && group->meter != nullptr)
            meter = group->meter;

        next->rowMeters.push_back(std::move(meter));
    }

    std::shared_ptr<const MeterReadoutSnapshot> published = std::move(next);
    std::atomic_store_explicit(&meterReadoutSnapshot, published, std::memory_order_release);
}

JuceEngine::TrackGroupState *JuceEngine::trackGroupForMemberRowId(int rowId)
{
    for (auto &group : trackGroups)
        if (group.rowIds.contains(rowId))
            return &group;
    return nullptr;
}

void JuceEngine::attachTrackGroupBusNodes(
    TrackGroupState &group,
    juce::AudioProcessorGraph::UpdateKind updateKind)
{
    if (group.inputNode == nullptr)
    {
        auto input = std::make_unique<TrackInputProcessor>();
        group.inputProc = input.get();
        group.inputNode = graph.addNode(std::move(input), std::nullopt, updateKind);
    }

    if (group.gainNode == nullptr)
    {
        auto gain = std::make_unique<SimpleGainProcessor>();
        group.gainProc = gain.get();
        group.gainNode = graph.addNode(std::move(gain), std::nullopt, updateKind);
        group.gainProc->gain->setValueNotifyingHost(
            juce::jlimit(kGainUiMin, kGainUiMax, group.gainUi) / kGainUiMax);
        group.gainProc->setMuted(group.muted);
    }

    if (group.panNode == nullptr)
    {
        auto pan = std::make_unique<StereoPanProcessor>();
        group.panProc = pan.get();
        group.panNode = graph.addNode(std::move(pan), std::nullopt, updateKind);
        group.panProc->pan->setValueNotifyingHost(panUIToNormalized(group.panUi));
    }

    if (group.meterTapNode == nullptr)
    {
        if (group.meter == nullptr)
            group.meter = std::make_shared<StereoMeterState>();

        auto meterTap = std::make_unique<MeterTapProcessor>(
            &group.meter->peakL,
            &group.meter->peakR,
            &group.meter->rmsL,
            &group.meter->rmsR,
            &rowMetersEnabled);
        group.meterTapProc = meterTap.get();
        group.meterTapNode = graph.addNode(std::move(meterTap), std::nullopt, updateKind);
    }

    rewireTrackGroupFxChain(group.id, updateKind);
}

void JuceEngine::ensureTrackGroupBusNodesAttached(
    TrackGroupState &group,
    juce::AudioProcessorGraph::UpdateKind updateKind)
{
    if (!engineInitialized || !busGraphInitialised)
        return;
    if (group.inputNode != nullptr && group.gainNode != nullptr &&
        group.panNode != nullptr && group.meterTapNode != nullptr)
        return;
    attachTrackGroupBusNodes(group, updateKind);
}

void JuceEngine::ensureBusGraphInitialised(bool commitImmediately)
{
    if (busGraphInitialised)
        return;

    if (outputNode == nullptr)
    {
        juceLogToFlutter("ensureBusGraphInitialised: outputNode is null");
        return;
    }

    const double sampleRate =
        getKnownDeviceSampleRate(deviceManager, hostSampleRateAtomic.load(std::memory_order_relaxed));
    const int blockSize = getKnownDeviceBufferSize(deviceManager, 512);

    hostSampleRateAtomic.store(sampleRate, std::memory_order_relaxed);
    constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;

    // MASTER gain + pan
    {
        auto mi = std::make_unique<TrackInputProcessor>();
        masterInputProcessor = mi.get();
        masterInputNode = graph.addNode(std::move(mi), std::nullopt, batchUpdate);

        auto mg = std::make_unique<SimpleGainProcessor>();
        masterGainProcessor = mg.get();
        masterGainNode = graph.addNode(std::move(mg), std::nullopt, batchUpdate);
        masterGainProcessor->gain->setValueNotifyingHost(
            juce::jlimit(kGainUiMin, kGainUiMax, masterGainUi) / kGainUiMax);
        masterGainProcessor->setMuted(masterMuted);

        auto mp = std::make_unique<StereoPanProcessor>();
        masterPanProcessor = mp.get();
        masterPanNode = graph.addNode(std::move(mp), std::nullopt, batchUpdate);
        masterPanProcessor->pan->setValueNotifyingHost(
            panUIToNormalized(masterPanUi));

        if (masterInputNode != nullptr)
            connectStereo(graph, masterInputNode->nodeID, masterGainNode->nodeID, batchUpdate);
        connectStereo(graph, masterGainNode->nodeID, masterPanNode->nodeID, batchUpdate);
        connectStereo(graph, masterPanNode->nodeID, outputNode->nodeID, batchUpdate);
    }

    if (masterEffectChain == nullptr)
        masterEffectChain = new juce::Array<juce::AudioProcessorGraph::NodeID>();

    for (auto &group : trackGroups)
        attachTrackGroupBusNodes(group, batchUpdate);

    // Row meters enabled already exist (atomic)
    // Create per-row chain: Input -> [Row FX] -> Automation -> Gain -> Pan -> MeterTap -> Master/group input
    for (auto &r : rows)
        attachRowBusNodes(r, batchUpdate);

    retargetRowMeterTapPointers();
    publishMeterReadoutSnapshotLocked();

    busGraphInitialised = true;
    if (commitImmediately)
        commitGraphMutationLocked(!isProjectClipLoadTransactionActive());
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

std::shared_ptr<DecodedClipAudioAsset> JuceEngine::getOrDecodeClipAudioAsset(const juce::File &file)
{
    if (!file.existsAsFile())
        return nullptr;

    const auto cacheKey = decodedClipAssetCacheKeyForFile(file);
    {
        const std::lock_guard<std::mutex> lock(decodedClipAssetCacheMutex);
        if (auto cached = decodedClipAssetCache[cacheKey].lock())
            return cached;
    }

    std::unique_ptr<juce::AudioFormatReader> reader(formatManager.createReaderFor(file));
    if (!reader)
        return nullptr;

    auto decoded = decodeReaderToStereoAsset(*reader);
    if (decoded == nullptr)
        return nullptr;

    {
        const std::lock_guard<std::mutex> lock(decodedClipAssetCacheMutex);
        for (auto it = decodedClipAssetCache.begin(); it != decodedClipAssetCache.end();)
        {
            if (it->second.expired())
                it = decodedClipAssetCache.erase(it);
            else
                ++it;
        }

        if (auto cached = decodedClipAssetCache[cacheKey].lock())
            return cached;

        decodedClipAssetCache[cacheKey] = decoded;
    }

    return decoded;
}

void JuceEngine::beginProjectClipLoadTransaction()
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    if (projectClipLoadTransactionDepth == 0)
    {
        projectClipLoadNeedsGraphRebuild = false;
        projectClipLoadNeedsOutputSafety = false;
    }
    ++projectClipLoadTransactionDepth;
}

void JuceEngine::endProjectClipLoadTransaction()
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    if (projectClipLoadTransactionDepth <= 0)
        return;

    --projectClipLoadTransactionDepth;
    if (projectClipLoadTransactionDepth > 0)
        return;

    if (projectClipLoadNeedsGraphRebuild)
    {
        if (graphMutationBatchDepth > 0)
        {
            recordGraphRebuildRequest(true, false, false);
            graphMutationBatchNeedsRebuild = true;
            graphMutationBatchNeedsOutputSafety =
                graphMutationBatchNeedsOutputSafety || projectClipLoadNeedsOutputSafety;
        }
        else
        {
            recordGraphRebuildRequest(false, false, true);
            requestGraphRebuildAsync(graph);
        }
        projectClipLoadNeedsGraphRebuild = false;
    }
    if (projectClipLoadNeedsOutputSafety)
    {
        if (graphMutationBatchDepth > 0)
            graphMutationBatchNeedsOutputSafety = true;
        else
            armOutputSafetyForCurrentRoute();
        projectClipLoadNeedsOutputSafety = false;
    }
    if (routedClipSchedulePublishPending)
    {
        routedClipSchedulePublishPending = false;
        publishRoutedClipSchedulesLocked();
    }
}

void JuceEngine::markGraphMutationBatchRowFxDirtyLocked(int rowIndex)
{
    if (graphMutationBatchDepth <= 0 || rowIndex < 0)
        return;
    graphMutationBatchDirtyRowFxChains.insert(rowIndex);
}

void JuceEngine::markGraphMutationBatchTrackGroupFxDirtyLocked(const juce::String &groupId)
{
    if (graphMutationBatchDepth <= 0 || groupId.trim().isEmpty())
        return;
    graphMutationBatchDirtyTrackGroupFxChains.addIfNotAlreadyThere(groupId);
}

void JuceEngine::markGraphMutationBatchMasterFxDirtyLocked()
{
    if (graphMutationBatchDepth <= 0)
        return;
    graphMutationBatchDirtyMasterFxChain = true;
}

void JuceEngine::flushGraphMutationBatchFxRewiresLocked()
{
    constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;
    for (const auto &groupId : graphMutationBatchDirtyTrackGroupFxChains)
        rewireTrackGroupFxChain(groupId, batchUpdate);
    graphMutationBatchDirtyTrackGroupFxChains.clear();

    for (const int rowIndex : graphMutationBatchDirtyRowFxChains)
        rewireTrackBusFxChain(rowIndex, batchUpdate);
    graphMutationBatchDirtyRowFxChains.clear();

    if (graphMutationBatchDirtyMasterFxChain)
    {
        rewireMasterFxChain(batchUpdate);
        graphMutationBatchDirtyMasterFxChain = false;
    }
}

void JuceEngine::beginGraphMutationBatch()
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    if (graphMutationBatchDepth == 0)
    {
        graphMutationBatchDirtyRowFxChains.clear();
        graphMutationBatchDirtyTrackGroupFxChains.clear();
        graphMutationBatchDirtyMasterFxChain = false;
    }
    ++graphMutationBatchDepth;
}

void JuceEngine::endGraphMutationBatch()
{
    bool needsOutputSafety = false;
    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
        if (graphMutationBatchDepth <= 0)
            return;

        --graphMutationBatchDepth;
        if (graphMutationBatchDepth > 0)
            return;

        flushGraphMutationBatchFxRewiresLocked();

        if (graphMutationBatchNeedsRebuild)
        {
            if (isProjectClipLoadTransactionActive())
            {
                recordGraphRebuildRequest(true, false, false);
                projectClipLoadNeedsGraphRebuild = true;
                projectClipLoadNeedsOutputSafety =
                    projectClipLoadNeedsOutputSafety || graphMutationBatchNeedsOutputSafety;
            }
            else
            {
                recordGraphRebuildRequest(false, true, false);
                requestGraphRebuildAsync(graph);
            }
            graphMutationBatchNeedsRebuild = false;
        }
        if (graphMutationBatchNeedsOutputSafety)
        {
            if (isProjectClipLoadTransactionActive())
                projectClipLoadNeedsOutputSafety = true;
            else
                needsOutputSafety = true;
        }
        graphMutationBatchNeedsOutputSafety = false;
    }

    if (needsOutputSafety)
        armOutputSafetyForCurrentRoute();
}

std::shared_ptr<DecodedClipAudioAsset> JuceEngine::prepareClipAudioAsset(const juce::File &file)
{
    return getOrDecodeClipAudioAsset(file);
}

bool JuceEngine::loadClip(int clipId, int rowId, const juce::File &file,
                          double startSec, double lengthSec, double inFileOffsetSec)
{
    auto decodedAsset = prepareClipAudioAsset(file);
    return loadClipWithPreparedAudioAsset(
        clipId,
        rowId,
        file,
        std::move(decodedAsset),
        startSec,
        lengthSec,
        inFileOffsetSec);
}

bool JuceEngine::loadClipWithPreparedAudioAsset(
    int clipId,
    int rowId,
    const juce::File &file,
    std::shared_ptr<DecodedClipAudioAsset> decodedAsset,
    double startSec,
    double lengthSec,
    double inFileOffsetSec)
{
    if (clipId < 0 || clipId >= kMaxClips)
        return false;

    if (decodedAsset == nullptr)
        return false;

    auto totalLength = (juce::int64)decodedAsset->audio.getNumSamples();
    const double fileSr = decodedAsset->sampleRate > 0.0 ? decodedAsset->sampleRate : 44100.0;
    const double fileTotalSec = (double)totalLength / fileSr;
    const double safeStartSec = juce::jmax(0.0, startSec);
    const double safeOffsetSec = juce::jmax(0.0, inFileOffsetSec);
    const double resolvedLengthSec =
        (lengthSec > 0.0) ? lengthSec : juce::jmax(0.0, fileTotalSec - safeOffsetSec);

    auto player = std::make_unique<TimelineClipProcessor>(
        decodedAsset,
        file,
        &blockTransportStartSec,
        &hostSampleRateAtomic,
        &blockIsPlayingAtomic);

    player->setTimeline(safeStartSec, resolvedLengthSec, safeOffsetSec);
    player->setStretchOptions(1.0, false);
    const double prepareSampleRate =
        getKnownDeviceSampleRate(deviceManager, hostSampleRateAtomic.load(std::memory_order_relaxed));
    const int prepareBlockSize = getKnownDeviceBufferSize(deviceManager, 512);
    player->setPlayConfigDetails(0, 2, prepareSampleRate, prepareBlockSize);
    player->prepareToPlay(prepareSampleRate, prepareBlockSize);

    std::shared_ptr<juce::AudioProcessor> detachedProcessor;
    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

        if (clips.empty())
            clips.resize(kMaxClips);
        if (rows.empty())
            addRow("Row 1", 0);

        ensureBusGraphInitialised();
        beginRoutedClipScheduleMutationLocked();
        if (clips[(size_t)clipId].alive)
        {
            const bool hadGraphNodes =
                !clips[(size_t)clipId].fxChain.isEmpty() ||
                clips[(size_t)clipId].playerNode != nullptr;
            detachedProcessor =
                clearClipGraphNodes(clipId, juce::AudioProcessorGraph::UpdateKind::none);
            if (hadGraphNodes)
                commitGraphMutationLocked();
        }

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
        c.reversed = false;
        c.tempoRatio = 1.0;
        c.preservePitch = false;
        c.gainUi = kGainUiUnity;
        c.extraGainLinear = 1.0f;
        c.panNormalized = 0.0f;
        c.fadeInSec = 0.0;
        c.fadeOutSec = 0.0;
        c.fadeCurve = 0;
        c.sourceFilePath = file.getFullPathName();
        c.midiInstrumentId = {};
        c.midiInstrumentName = {};
        c.midiNotes.clear();
        c.midiParams = {};
        c.midiSourceTempoBpm = 120.0;

        std::atomic_store_explicit(
            &c.playerProcessor,
            std::shared_ptr<juce::AudioProcessor>(std::move(player)),
            std::memory_order_release);
        c.playerNode = nullptr;
        c.fxChain.clear();
        c.wired = true;
        c.lastRowInputNodeUid = 0;
        addClipToRowIndex(c.rowId, clipId);

        if (auto *p = timelineProcessorForClip(c))
        {
            p->setGainUi(kGainUiUnity);
            p->setPanNormalized(0.0f);
        }
        endRoutedClipScheduleMutationLocked();
    }

    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
        retireLiveClipProcessorLocked(std::move(detachedProcessor));
        drainRetiredLiveClipProcessorsLocked();
    }

    return true;
}

bool JuceEngine::prepareMidiClipSampleAssets(const juce::String &instrumentId,
                                             const juce::String &instrumentName,
                                             const juce::Array<TimelineMidiNote> &notes)
{
    return TimelineMidiClipProcessor::prepareSampledInstrumentAssets(
        instrumentId,
        instrumentName,
        notes);
}

bool JuceEngine::isMidiClipLoadRequestCancelled(
    int clipId,
    std::int64_t loadRequestId)
{
    if (loadRequestId <= 0)
        return false;
    const std::lock_guard<std::mutex> requestLock(midiLoadRequestMutex);
    const auto cancelled = cancelledMidiLoadRequestThrough.find(clipId);
    return cancelled != cancelledMidiLoadRequestThrough.end() &&
           loadRequestId <= cancelled->second;
}

JuceEngine::PreparedMidiClipLoadPtr JuceEngine::prepareBuiltInMidiClipLoad(
    int clipId,
    int rowId,
    const juce::String &instrumentId,
    const juce::String &instrumentName,
    const juce::Array<TimelineMidiNote> &notes,
    const juce::NamedValueSet &params,
    double sourceTempoBpm,
    double startSec,
    double lengthSec,
    double inFileOffsetSec,
    std::int64_t loadRequestId)
{
    std::uint64_t engineGeneration = 0;
    {
        const std::lock_guard<std::mutex> lifecycleLock(engineLifecycleMutex);
        if (!engineInitialized)
            return nullptr;
        engineGeneration =
            engineLifecycleGeneration.load(std::memory_order_acquire);
    }
    if (clipId < 0 || clipId >= kMaxClips ||
        !isBuiltInMidiInstrumentIdentifier(instrumentId) ||
        isMidiClipLoadRequestCancelled(clipId, loadRequestId))
        return nullptr;

    const auto requestLabel =
        "clip=" + juce::String(clipId) +
        " request=" + juce::String((juce::int64)loadRequestId);
    juce::String preparationStage = "sample assets";
    try
    {
        if (!prepareMidiClipSampleAssets(instrumentId, instrumentName, notes))
            return nullptr;
        if (isMidiClipLoadRequestCancelled(clipId, loadRequestId))
            return nullptr;

        preparationStage = "processor construction";
        const double safeSourceTempo = clampSourceTempo(sourceTempoBpm);
        const double safeStartSec = juce::jmax(0.0, startSec);
        const double safeOffsetSec = juce::jmax(0.0, inFileOffsetSec);
        const double resolvedLengthSec =
            lengthSec > 0.0
                ? juce::jmax(0.0, lengthSec)
                : estimateMidiMaterialLengthSec(
                      notes, params, safeSourceTempo, safeOffsetSec);
        if (!TimelineMidiClipProcessor::canResolveSampledInstrument(
                instrumentId, instrumentName))
            return nullptr;

        auto processor = std::make_unique<TimelineMidiClipProcessor>(
            &blockTransportStartSec,
            &hostSampleRateAtomic,
            &blockIsPlayingAtomic);
        preparationStage = "processor state";
        processor->setMidiData(
            notes, instrumentId, instrumentName, params, safeSourceTempo);
        processor->setTimeline(
            safeStartSec, resolvedLengthSec, safeOffsetSec);
        processor->setStretchOptions(1.0, true);
        const double prepareSampleRate = juce::jmax(
            1.0, hostSampleRateAtomic.load(std::memory_order_acquire));
        constexpr int prepareBlockSize = 512;
        preparationStage = "prepareToPlay";
        processor->setPlayConfigDetails(
            0, 2, prepareSampleRate, prepareBlockSize);
        processor->prepareToPlay(prepareSampleRate, prepareBlockSize);

        {
            const std::lock_guard<std::mutex> lifecycleLock(engineLifecycleMutex);
            if (!engineInitialized ||
                engineGeneration !=
                    engineLifecycleGeneration.load(std::memory_order_acquire))
                return nullptr;
        }
        if (isMidiClipLoadRequestCancelled(clipId, loadRequestId))
            return nullptr;

        auto prepared = std::make_shared<PreparedMidiClipLoad>();
        prepared->clipId = clipId;
        prepared->rowId = rowId;
        prepared->instrumentId = instrumentId;
        prepared->instrumentName = instrumentName;
        prepared->notes = notes;
        prepared->params = params;
        prepared->sourceTempoBpm = safeSourceTempo;
        prepared->startSec = safeStartSec;
        prepared->lengthSec = resolvedLengthSec;
        prepared->inFileOffsetSec = safeOffsetSec;
        prepared->loadRequestId = loadRequestId;
        prepared->engineGeneration = engineGeneration;
        prepared->processor = std::move(processor);
        return prepared;
    }
    catch (const std::exception &exception)
    {
        juce::Logger::writeToLog(
            "Android built-in MIDI preparation failed " + requestLabel +
            " stage=" + preparationStage + ": " +
            juce::String(exception.what()));
    }
    catch (...)
    {
        juce::Logger::writeToLog(
            "Android built-in MIDI preparation failed " + requestLabel +
            " stage=" + preparationStage + " with unknown exception");
    }
    return nullptr;
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
                              double inFileOffsetSec,
                              std::int64_t loadRequestId)
{
    auto prepared = prepareBuiltInMidiClipLoad(
        clipId,
        rowId,
        instrumentId,
        instrumentName,
        notes,
        params,
        sourceTempoBpm,
        startSec,
        lengthSec,
        inFileOffsetSec,
        loadRequestId);
    return installPreparedMidiClipLoad(prepared);
}

bool JuceEngine::installPreparedMidiClipLoad(
    const PreparedMidiClipLoadPtr &preparedLoad)
{
    if (preparedLoad == nullptr || preparedLoad->processor == nullptr)
        return false;

    const int clipId = preparedLoad->clipId;
    const auto loadRequestId = preparedLoad->loadRequestId;
    const std::lock_guard<std::mutex> lifecycleLock(engineLifecycleMutex);
    if (!engineInitialized ||
        preparedLoad->engineGeneration !=
            engineLifecycleGeneration.load(std::memory_order_acquire) ||
        clipId < 0 || clipId >= kMaxClips ||
        isMidiClipLoadRequestCancelled(clipId, loadRequestId))
        return false;

    std::shared_ptr<juce::AudioProcessor> detachedProcessor;
    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

        if (isMidiClipLoadRequestCancelled(clipId, loadRequestId))
            return false;

        if (clips.empty())
            clips.resize(kMaxClips);
        if (rows.empty())
            addRow("Row 1", 0);

        ensureBusGraphInitialised();
        beginRoutedClipScheduleMutationLocked();
        if (clips[(size_t)clipId].alive)
        {
            const bool hadGraphNodes =
                !clips[(size_t)clipId].fxChain.isEmpty() ||
                clips[(size_t)clipId].playerNode != nullptr;
            detachedProcessor =
                clearClipGraphNodes(clipId, juce::AudioProcessorGraph::UpdateKind::none);
            if (hadGraphNodes)
                commitGraphMutationLocked();
        }

        ClipState &c = clips[clipId];
        c.alive = true;
        c.isMidi = true;
        c.clipId = clipId;
        const int rowIndex = getRowIndexById(preparedLoad->rowId);
        c.rowId = rowIndex >= 0 ? preparedLoad->rowId : rows[0].rowId;
        c.startSec = preparedLoad->startSec;
        c.lengthSec = preparedLoad->lengthSec;
        c.inFileOffsetSec = preparedLoad->inFileOffsetSec;
        c.pitchSemitones = 0.0f;
        c.reversed = false;
        c.tempoRatio = 1.0;
        c.preservePitch = true;
        c.gainUi = kGainUiUnity;
        c.extraGainLinear = 1.0f;
        c.panNormalized = 0.0f;
        c.sourceFilePath = {};
        c.midiInstrumentId = preparedLoad->instrumentId;
        c.midiInstrumentName = preparedLoad->instrumentName;
        c.midiNotes = preparedLoad->notes;
        c.midiParams = preparedLoad->params;
        c.midiSourceTempoBpm = preparedLoad->sourceTempoBpm;
        c.midiLoadRequestId = loadRequestId;

        std::atomic_store_explicit(
            &c.playerProcessor,
            std::shared_ptr<juce::AudioProcessor>(
                std::move(preparedLoad->processor)),
            std::memory_order_release);
        c.playerNode = nullptr;
        c.fxChain.clear();
        c.wired = true;
        c.lastRowInputNodeUid = 0;
        addClipToRowIndex(c.rowId, clipId);

        if (auto *p = timelineProcessorForClip(c))
        {
            p->setGainUi(kGainUiUnity);
            p->setPanNormalized(0.0f);
        }
        endRoutedClipScheduleMutationLocked();
    }

    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
        retireLiveClipProcessorLocked(std::move(detachedProcessor));
        drainRetiredLiveClipProcessorsLocked();
    }

    return true;
}

bool JuceEngine::cancelMidiClipLoad(
    int clipId,
    std::int64_t loadRequestId)
{
    if (clipId < 0 || clipId >= kMaxClips || loadRequestId <= 0)
        return false;

    {
        const std::lock_guard<std::mutex> requestLock(midiLoadRequestMutex);
        auto &cancelledThrough = cancelledMidiLoadRequestThrough[clipId];
        cancelledThrough = juce::jmax(cancelledThrough, loadRequestId);
    }

    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    if (clips.empty() || clipId >= (int)clips.size())
        return true;
    const auto &clip = clips[(size_t)clipId];
    if (!clip.alive || !clip.isMidi ||
        clip.midiLoadRequestId != loadRequestId)
        return true;

    return unloadClip(clipId);
}

bool JuceEngine::updateMidiClipEvents(int clipId,
                                      const juce::String &instrumentId,
                                      const juce::String &instrumentName,
                                      const juce::Array<TimelineMidiNote> &notes,
                                      const juce::NamedValueSet &params,
                                      double sourceTempoBpm)
{
    const double safeSourceTempo = clampSourceTempo(sourceTempoBpm);
    if (!TimelineMidiClipProcessor::canResolveSampledInstrument(
            instrumentId,
            instrumentName))
    {
        return false;
    }

    double startSec = 0.0;
    double lengthSec = 0.0;
    double inFileOffsetSec = 0.0;
    float pitchSemitones = 0.0f;
    bool reversed = false;
    double tempoRatio = 1.0;
    bool preservePitch = true;
    float gainUi = kGainUiUnity;
    float extraGainLinear = 1.0f;
    float panNormalized = 0.0f;
    double fadeInSec = 0.0;
    double fadeOutSec = 0.0;
    int fadeCurve = 0;
    bool muted = false;

    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

        if (clips.empty() || clipId < 0 || clipId >= (int)clips.size())
            return false;

        auto &c = clips[(size_t)clipId];
        if (!c.alive || !c.isMidi || liveProcessorForClip(c) == nullptr)
            return false;

        if (dynamic_cast<TimelineMidiClipProcessor *>(liveProcessorForClip(c)) == nullptr)
            return false;

        startSec = c.startSec;
        lengthSec = c.lengthSec;
        inFileOffsetSec = c.inFileOffsetSec;
        pitchSemitones = c.pitchSemitones;
        reversed = c.reversed;
        tempoRatio = c.tempoRatio;
        preservePitch = c.preservePitch;
        gainUi = c.gainUi;
        extraGainLinear = c.extraGainLinear;
        panNormalized = c.panNormalized;
        fadeInSec = c.fadeInSec;
        fadeOutSec = c.fadeOutSec;
        fadeCurve = c.fadeCurve;
        muted = c.muted;
    }

    auto replacement = std::make_unique<TimelineMidiClipProcessor>(
        &blockTransportStartSec,
        &hostSampleRateAtomic,
        &blockIsPlayingAtomic);
    replacement->setMidiData(notes, instrumentId, instrumentName, params, safeSourceTempo);
    replacement->setTimeline(startSec, lengthSec, inFileOffsetSec);
    replacement->setStretchOptions(tempoRatio, preservePitch);
    replacement->setPitchSemitones(pitchSemitones);
    replacement->setReversed(reversed);
    replacement->setMuted(muted);
    replacement->setGainUi(gainUi);
    replacement->setExtraGainLinear(extraGainLinear);
    replacement->setPanNormalized(panNormalized);
    replacement->setFades(fadeInSec, fadeOutSec, fadeCurve);
    prepareLiveClipProcessor(*replacement);

    requestLiveMidiPanicForClip(clipId, LiveMidiPanicMode::liveOnly);
    std::shared_ptr<juce::AudioProcessor> detachedProcessor;
    bool routedProcessorReady = false;
    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

        if (clips.empty() || clipId < 0 || clipId >= (int)clips.size())
            return false;

        auto &c = clips[(size_t)clipId];
        if (!c.alive || !c.isMidi || liveProcessorForClip(c) == nullptr)
            return false;

        if (dynamic_cast<TimelineMidiClipProcessor *>(liveProcessorForClip(c)) == nullptr)
            return false;

        c.midiInstrumentId = instrumentId;
        c.midiInstrumentName = instrumentName;
        c.midiNotes = notes;
        c.midiParams = params;
        c.midiSourceTempoBpm = safeSourceTempo;
        beginRoutedClipScheduleMutationLocked();
        removeClipFromRoutedSchedule(c.rowId, clipId);
        detachedProcessor = std::atomic_exchange_explicit(
            &c.playerProcessor,
            std::shared_ptr<juce::AudioProcessor>(std::move(replacement)),
            std::memory_order_acq_rel);
        addClipToRoutedSchedule(c);
        endRoutedClipScheduleMutationLocked();

        const auto routedSnapshot =
            std::atomic_load_explicit(&routedClipItemSnapshot, std::memory_order_acquire);
        const auto *routedItem =
            routedSnapshot != nullptr ? routedSnapshot->findClip(clipId) : nullptr;
        routedProcessorReady =
            routedItem != nullptr &&
            routedItem->processor == liveProcessorSharedForClip(c);
    }

    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
        retireLiveClipProcessorLocked(std::move(detachedProcessor));
        drainRetiredLiveClipProcessorsLocked();
    }

    return routedProcessorReady;
}

void JuceEngine::requestLiveMidiPanicForClip(
    int clipId,
    LiveMidiPanicMode mode) noexcept
{
    const auto snapshot = std::atomic_load_explicit(
        &routedClipItemSnapshot, std::memory_order_acquire);
    const auto *item =
        snapshot != nullptr ? snapshot->findClip(clipId) : nullptr;
    if (item == nullptr || !item->isMidi || item->processor == nullptr)
        return;
    if (auto *processor = dynamic_cast<TimelineClipProcessorBase *>(
            item->processor.get()))
        processor->requestLiveMidiPanic(mode);
}

void JuceEngine::requestLiveMidiPanicForAll(
    LiveMidiPanicMode mode) noexcept
{
    clearLiveMidiInputAudioQueue();
    const auto snapshot = std::atomic_load_explicit(
        &routedClipItemSnapshot, std::memory_order_acquire);
    if (snapshot == nullptr)
        return;

    for (int clipId = 0; clipId < kMaxClips; ++clipId)
    {
        const auto *item = snapshot->findClip(clipId);
        if (item == nullptr || !item->isMidi || item->processor == nullptr)
            continue;
        if (auto *processor = dynamic_cast<TimelineClipProcessorBase *>(
                item->processor.get()))
            processor->requestLiveMidiPanic(mode);
    }
}

bool JuceEngine::setLiveMidiInputTargetClip(int clipId)
{
    const int previousClipId =
        liveMidiInputTargetClip.load(std::memory_order_relaxed);
    if (clipId >= 0)
    {
        const auto itemSnapshot =
            std::atomic_load_explicit(&routedClipItemSnapshot, std::memory_order_acquire);
        if (itemSnapshot == nullptr)
            return false;

        const auto *item = itemSnapshot->findClip(clipId);
        if (item == nullptr ||
            !item->isMidi ||
            item->processor == nullptr)
        {
            return false;
        }

        if (clips.empty() || clipId >= (int)clips.size())
            return false;
        const auto &clip = clips[(size_t)clipId];
        const auto currentProcessor = liveProcessorSharedForClip(clip);
        if (!clip.alive ||
            !clip.isMidi ||
            currentProcessor == nullptr ||
            item->processor != currentProcessor)
        {
            return false;
        }

        if (!midiInputCallbacksInitialized.load(std::memory_order_relaxed))
            refreshMidiInputCallbacks();
    }

    if (previousClipId == clipId)
        return true;

    liveMidiInputTargetClip.store(clipId, std::memory_order_release);
    clearLiveMidiInputAudioQueue();
    {
        const std::lock_guard<std::mutex> lock(liveMidiInputQueueMutex);
        liveMidiInputPendingForFlutter.clear();
    }
    if (previousClipId >= 0)
        requestLiveMidiPanicForClip(
            previousClipId, LiveMidiPanicMode::liveOnly);
    return true;
}

bool JuceEngine::playPreviewMidiNote(int clipId,
                                     int pitch,
                                     float velocity,
                                     int durationMs)
{
    if (clips.empty() || clipId < 0 || clipId >= (int)clips.size())
        return false;

    auto &c = clips[(size_t)clipId];
    const auto currentProcessor = liveProcessorSharedForClip(c);
    if (!c.alive || !c.isMidi || currentProcessor == nullptr)
        return false;

    const auto routedSnapshot =
        std::atomic_load_explicit(&routedClipItemSnapshot, std::memory_order_acquire);
    const auto *routedItem =
        routedSnapshot != nullptr ? routedSnapshot->findClip(clipId) : nullptr;
    if (routedItem == nullptr ||
        routedItem->processor == nullptr ||
        routedItem->processor != currentProcessor)
    {
        return false;
    }

    auto *proc = dynamic_cast<TimelineMidiClipProcessor *>(
        routedItem->processor.get());
    if (proc == nullptr)
        return false;

    const int safePitch = juce::jlimit(0, 127, pitch);
    const float safeVelocity = juce::jlimit(0.0f, 1.0f, velocity);
    const int safeDurationMs = juce::jlimit(60, 4000, durationMs);

    TimelineMidiClipProcessor::PreparedLiveSample preparedSample;
    if (!proc->prepareLiveMidiSample(
            safePitch,
            safeVelocity,
            preparedSample))
        return false;
    if (!proc->enqueueLiveMidiEvent(false, 1, safePitch, 0.0f) ||
        !proc->enqueueLiveMidiEvent(
            true,
            1,
            safePitch,
            safeVelocity,
            preparedSample))
        return false;
    const std::weak_ptr<juce::AudioProcessor> previewProcessorIdentity =
        currentProcessor;
    juce::Timer::callAfterDelay(
        safeDurationMs,
        [clipId, safePitch, previewProcessorIdentity]
        {
            juce::MessageManager::callAsync(
                [clipId, safePitch, previewProcessorIdentity]
                {
                    auto &engine = JuceEngine::get();
                    if (engine.clips.empty() ||
                        clipId < 0 ||
                        clipId >= (int)engine.clips.size())
                        return;

                    auto &clip = engine.clips[(size_t)clipId];
                    const auto expectedProcessor =
                        previewProcessorIdentity.lock();
                    const auto currentProcessor =
                        engine.liveProcessorSharedForClip(clip);
                    if (!clip.alive || !clip.isMidi ||
                        expectedProcessor == nullptr ||
                        currentProcessor != expectedProcessor)
                        return;

                    auto *activeProc = dynamic_cast<TimelineMidiClipProcessor *>(
                        currentProcessor.get());
                    if (activeProc == nullptr)
                        return;

                    activeProc->enqueueLiveMidiEvent(false, 1, safePitch, 0.0f);
                });
        });
    return true;
}

bool JuceEngine::sendLiveMidiInputEvent(bool noteOn,
                                        int channel,
                                        int pitch,
                                        float velocity)
{
    const int clipId =
        liveMidiInputTargetClip.load(std::memory_order_relaxed);
    if (clipId < 0)
        return false;

    LiveMidiInputEvent event;
    event.clipId = clipId;
    event.noteOn = noteOn;
    event.channel = juce::jlimit(1, 16, channel);
    event.pitch = juce::jlimit(0, 127, pitch);
    event.velocity = noteOn ? juce::jlimit(0.0f, 1.0f, velocity) : 0.0f;
    event.transportSec = transportSec.load(std::memory_order_relaxed);

    if (!prepareLiveMidiInputEventForAudioQueue(event) ||
        !enqueueLiveMidiInputAudioEvent(event))
        return false;

    const std::lock_guard<std::mutex> lock(liveMidiInputQueueMutex);
    event.preparedSample = {};
    liveMidiInputPendingForFlutter.push_back(event);
    constexpr size_t kMaxBufferedEvents = 4096;
    if (liveMidiInputPendingForFlutter.size() > kMaxBufferedEvents)
    {
        liveMidiInputPendingForFlutter.erase(
            liveMidiInputPendingForFlutter.begin(),
            liveMidiInputPendingForFlutter.begin() +
                (std::ptrdiff_t)(liveMidiInputPendingForFlutter.size() - kMaxBufferedEvents));
    }
    return true;
}

std::vector<JuceEngine::LiveMidiInputEvent> JuceEngine::consumeLiveMidiInputEvents()
{
    std::vector<LiveMidiInputEvent> out;
    const std::lock_guard<std::mutex> lock(liveMidiInputQueueMutex);
    out.swap(liveMidiInputPendingForFlutter);
    return out;
}

bool JuceEngine::enqueueLiveMidiInputAudioEvent(const LiveMidiInputEvent &event) noexcept
{
    auto position = liveMidiInputAudioEnqueuePosition.load(std::memory_order_relaxed);
    LiveMidiInputAudioQueueCell *cell = nullptr;

    for (;;)
    {
        cell = &liveMidiInputAudioQueue[position & kLiveMidiInputAudioQueueMask];
        const auto sequence = cell->sequence.load(std::memory_order_acquire);
        const auto diff =
            (std::intptr_t)sequence - (std::intptr_t)position;

        if (diff == 0)
        {
            if (liveMidiInputAudioEnqueuePosition.compare_exchange_weak(
                    position,
                    position + 1,
                    std::memory_order_relaxed))
            {
                break;
            }
        }
        else if (diff < 0)
        {
            return false;
        }
        else
        {
            position = liveMidiInputAudioEnqueuePosition.load(std::memory_order_relaxed);
        }
    }

    cell->event = event;
    cell->sequence.store(position + 1, std::memory_order_release);
    return true;
}

bool JuceEngine::dequeueLiveMidiInputAudioEvent(LiveMidiInputEvent &event) noexcept
{
    auto position = liveMidiInputAudioDequeuePosition.load(std::memory_order_relaxed);
    LiveMidiInputAudioQueueCell *cell = nullptr;

    for (;;)
    {
        cell = &liveMidiInputAudioQueue[position & kLiveMidiInputAudioQueueMask];
        const auto sequence = cell->sequence.load(std::memory_order_acquire);
        const auto diff =
            (std::intptr_t)sequence - (std::intptr_t)(position + 1);

        if (diff == 0)
        {
            if (liveMidiInputAudioDequeuePosition.compare_exchange_weak(
                    position,
                    position + 1,
                    std::memory_order_relaxed))
            {
                break;
            }
        }
        else if (diff < 0)
        {
            return false;
        }
        else
        {
            position = liveMidiInputAudioDequeuePosition.load(std::memory_order_relaxed);
        }
    }

    event = cell->event;
    cell->sequence.store(
        position + kLiveMidiInputAudioQueueCapacity,
        std::memory_order_release);
    return true;
}

bool JuceEngine::prepareLiveMidiInputEventForAudioQueue(
    LiveMidiInputEvent &event)
{
    std::shared_ptr<juce::AudioProcessor> routedProcessor;
    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
        const auto itemSnapshot =
            std::atomic_load_explicit(&routedClipItemSnapshot, std::memory_order_acquire);
        const auto *item = itemSnapshot != nullptr
                               ? itemSnapshot->findClip(event.clipId)
                               : nullptr;
        if (item == nullptr || !item->isMidi || item->processor == nullptr ||
            event.clipId < 0 || event.clipId >= (int)clips.size())
            return false;

        const auto &clip = clips[(size_t)event.clipId];
        routedProcessor = liveProcessorSharedForClip(clip);
        if (!clip.alive || !clip.isMidi || item->processor != routedProcessor)
            return false;
    }

    event.routedProcessorIdentity = routedProcessor.get();
    if (!event.noteOn || event.velocity <= 0.0f)
        return true;

    auto *proc =
        dynamic_cast<TimelineMidiClipProcessor *>(routedProcessor.get());
    return proc != nullptr &&
           proc->prepareLiveMidiSample(
               event.pitch,
               event.velocity,
               event.preparedSample);
}

void JuceEngine::clearLiveMidiInputAudioQueue() noexcept
{
    LiveMidiInputEvent dropped;
    while (dequeueLiveMidiInputAudioEvent(dropped))
    {
    }
}

void JuceEngine::dispatchQueuedLiveMidiInputEventsForAudioThread()
{
    std::size_t pendingCount = 0;
    while (pendingCount < liveMidiInputAudioBlockEvents.size() &&
           dequeueLiveMidiInputAudioEvent(liveMidiInputAudioBlockEvents[pendingCount]))
    {
        ++pendingCount;
    }
    if (pendingCount == 0)
        return;

    const auto *itemSnapshot =
        routedClipItemSnapshotRaw.load(std::memory_order_acquire);
    if (itemSnapshot == nullptr)
        return;

    for (std::size_t i = 0; i < pendingCount; ++i)
    {
        const auto &event = liveMidiInputAudioBlockEvents[i];
        const auto *item = itemSnapshot->findClip(event.clipId);
        if (item == nullptr)
            continue;

        if (!item->isMidi || item->processor == nullptr)
            continue;

        if (event.routedProcessorIdentity != item->processor.get())
            continue;

        auto *proc =
            dynamic_cast<TimelineMidiClipProcessor *>(item->processor.get());
        if (proc == nullptr)
            continue;

        proc->enqueueLiveMidiEvent(
            event.noteOn,
            event.channel,
            event.pitch,
            event.velocity,
            event.preparedSample);
    }
}

void JuceEngine::handleIncomingMidiMessage(juce::MidiInput *source,
                                           const juce::MidiMessage &message)
{
    juce::ignoreUnused(source);

    if (!message.isNoteOnOrOff())
        return;

    const int clipId =
        liveMidiInputTargetClip.load(std::memory_order_relaxed);
    if (clipId < 0)
        return;

    LiveMidiInputEvent event;
    event.clipId = clipId;
    event.noteOn = message.isNoteOn();
    event.channel = juce::jlimit(1, 16, message.getChannel());
    event.pitch = juce::jlimit(0, 127, message.getNoteNumber());
    event.velocity = juce::jlimit(0.0f, 1.0f, (float)message.getFloatVelocity());
    event.transportSec = transportSec.load(std::memory_order_relaxed);

    if (prepareLiveMidiInputEventForAudioQueue(event))
        juce::ignoreUnused(enqueueLiveMidiInputAudioEvent(event));

    const std::lock_guard<std::mutex> lock(liveMidiInputQueueMutex);
    event.preparedSample = {};
    liveMidiInputPendingForFlutter.push_back(event);
    constexpr size_t kMaxBufferedEvents = 4096;
    if (liveMidiInputPendingForFlutter.size() > kMaxBufferedEvents)
    {
        liveMidiInputPendingForFlutter.erase(
            liveMidiInputPendingForFlutter.begin(),
            liveMidiInputPendingForFlutter.begin() +
                (std::ptrdiff_t)(liveMidiInputPendingForFlutter.size() - kMaxBufferedEvents));
    }
}

bool JuceEngine::unloadClip(int clipId)
{
    std::shared_ptr<juce::AudioProcessor> detachedProcessor;

    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

        if (clips.empty() || clipId < 0 || clipId >= (int)clips.size())
            return false;

        ClipState &c = clips[clipId];
        if (!c.alive)
            return true;

        const bool hadGraphNodes = !c.fxChain.isEmpty() || c.playerNode != nullptr;
        constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;
        detachedProcessor = clearClipGraphNodes(clipId, batchUpdate);
        if (hadGraphNodes)
            commitGraphMutationLocked();
    }

    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
        retireLiveClipProcessorLocked(std::move(detachedProcessor));
        drainRetiredLiveClipProcessorsLocked();
    }
    return true;
}

int JuceEngine::unloadClips(const juce::Array<int> &clipIds)
{
    if (clipIds.isEmpty())
        return 0;

    std::vector<std::shared_ptr<juce::AudioProcessor>> detachedProcessors;
    int removed = 0;

    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
        if (clips.empty())
            return 0;

        bool graphChanged = false;
        beginRoutedClipScheduleMutationLocked();
        for (const int clipId : clipIds)
        {
            if (clipId < 0 || clipId >= (int)clips.size())
                continue;

            ClipState &clip = clips[(size_t)clipId];
            if (!clip.alive)
                continue;

            graphChanged = graphChanged ||
                           !clip.fxChain.isEmpty() ||
                           clip.playerNode != nullptr;
            if (auto processor = clearClipGraphNodes(
                    clipId, juce::AudioProcessorGraph::UpdateKind::none))
                detachedProcessors.push_back(std::move(processor));
            ++removed;
        }
        endRoutedClipScheduleMutationLocked();

        if (graphChanged)
            commitGraphMutationLocked();
    }

    if (!detachedProcessors.empty())
    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
        for (auto &processor : detachedProcessors)
            retireLiveClipProcessorLocked(std::move(processor));
        drainRetiredLiveClipProcessorsLocked();
    }

    return removed;
}

std::shared_ptr<juce::AudioProcessor> JuceEngine::clearClipGraphNodes(
    int clipId,
    juce::AudioProcessorGraph::UpdateKind updateKind)
{
    if (clips.empty() || clipId < 0 || clipId >= (int)clips.size())
        return {};

    ClipState &c = clips[(size_t)clipId];
    if (!c.alive)
        return {};

    const int previousRowId = c.rowId;
    std::shared_ptr<juce::AudioProcessor> detachedProcessor;
    c.wired = false;
    c.lastRowInputNodeUid = 0;

    for (auto id : c.fxChain)
        graph.removeNode(id, updateKind);

    detachedProcessor = std::atomic_exchange_explicit(
        &c.playerProcessor,
        std::shared_ptr<juce::AudioProcessor>{},
        std::memory_order_acq_rel);
    if (auto *processor = dynamic_cast<TimelineClipProcessorBase *>(
            detachedProcessor.get()))
        processor->requestLiveMidiPanic(LiveMidiPanicMode::liveOnly);

    if (c.playerNode)
        graph.removeNode(c.playerNode->nodeID, updateKind);

    removeClipFromRowIndex(previousRowId, clipId);
    c = ClipState();
    if (liveMidiInputTargetClip.load(std::memory_order_relaxed) == clipId)
    {
        liveMidiInputTargetClip.store(-1, std::memory_order_relaxed);
        clearLiveMidiInputAudioQueue();
        const std::lock_guard<std::mutex> lock(liveMidiInputQueueMutex);
        liveMidiInputPendingForFlutter.clear();
    }

    return detachedProcessor;
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
            if (c.lastRowInputNodeUid != 0)
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

    for (int ch = 0; ch < 2; ++ch)
        graph.addConnection({{c.playerNode->nodeID, ch}, {rowInputNode->nodeID, ch}}, updateKind);

    c.wired = true;
    c.lastRowInputNodeUid = (int)rowInputNode->nodeID.uid;
    if (!isProjectClipLoadTransactionActive())
        armOutputSafetyForCurrentRoute();
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
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (clips.empty() || clipId < 0 || clipId >= (int)clips.size())
        return false;

    ClipState &c = clips[clipId];
    if (!c.alive || liveProcessorForClip(c) == nullptr)
        return false;

    beginRoutedClipScheduleMutationLocked();
    removeClipFromRoutedSchedule(c.rowId, clipId);
    c.startSec = juce::jmax(0.0, startSec);
    c.lengthSec = juce::jmax(0.0, lengthSec);
    c.inFileOffsetSec = juce::jmax(0.0, inFileOffsetSec);

    if (auto *p = timelineProcessorForClip(c))
        p->setTimeline(c.startSec, c.lengthSec, c.inFileOffsetSec);
    addClipToRoutedSchedule(c);
    endRoutedClipScheduleMutationLocked();

    return true;
}

int JuceEngine::updateClipTimelineBatch(const juce::Array<juce::NamedValueSet> &updates)
{
    if (updates.isEmpty())
        return 0;

    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    if (clips.empty() || rows.empty())
        return 0;

    int applied = 0;
    beginRoutedClipScheduleMutationLocked();
    for (const auto &update : updates)
    {
        const int clipId = (int)update["clip"];
        if (clipId < 0 || clipId >= (int)clips.size())
            continue;

        ClipState &c = clips[(size_t)clipId];
        if (!c.alive || liveProcessorForClip(c) == nullptr)
            continue;

        const bool scheduleChanged = update.contains("rowId") ||
                                     update.contains("startSec") ||
                                     update.contains("lengthSec") ||
                                     update.contains("inFileOffsetSec");

        int resolvedRowId = c.rowId;
        if (update.contains("rowId"))
        {
            const int requestedRow = (int)update["rowId"];
            int rowIndex = getRowIndexById(requestedRow);
            if (rowIndex < 0 && requestedRow >= 0 && requestedRow < (int)rows.size())
            {
                rowIndex = requestedRow;
                resolvedRowId = rows[(size_t)rowIndex].rowId;
            }
            else if (rowIndex >= 0)
            {
                resolvedRowId = requestedRow;
            }

            if (rowIndex < 0)
                continue;
        }

        if (scheduleChanged)
            removeClipFromRoutedSchedule(c.rowId, clipId);
        if (c.rowId != resolvedRowId)
        {
            const auto previousIt = rowIdToClipIds.find(c.rowId);
            if (previousIt != rowIdToClipIds.end())
            {
                previousIt->second.removeAllInstancesOf(clipId);
                if (previousIt->second.isEmpty())
                    rowIdToClipIds.erase(previousIt);
            }
            c.rowId = resolvedRowId;
            rowIdToClipIds[c.rowId].addIfNotAlreadyThere(clipId);
        }

        if (update.contains("startSec"))
            c.startSec = juce::jmax(0.0, (double)update["startSec"]);
        if (update.contains("lengthSec"))
            c.lengthSec = juce::jmax(0.0, (double)update["lengthSec"]);
        if (update.contains("inFileOffsetSec"))
            c.inFileOffsetSec = juce::jmax(0.0, (double)update["inFileOffsetSec"]);

        if (auto *p = timelineProcessorForClip(c))
        {
            if (scheduleChanged)
                p->setTimeline(c.startSec, c.lengthSec, c.inFileOffsetSec);
            if (update.contains("gain"))
            {
                c.gainUi = juce::jlimit(kGainUiMin, kGainUiMax, (float)update["gain"]);
                p->setGainUi(c.gainUi);
            }
            if (update.contains("extraGainLinear"))
            {
                c.extraGainLinear = juce::jlimit(0.0f, 64.0f, (float)update["extraGainLinear"]);
                p->setExtraGainLinear(c.extraGainLinear);
            }
            if (update.contains("reversed"))
            {
                c.reversed = (bool)update["reversed"];
                p->setReversed(c.reversed);
            }
            if (update.contains("tempoRatio") || update.contains("preservePitch"))
            {
                if (update.contains("tempoRatio"))
                    c.tempoRatio = juce::jlimit(0.05, 20.0, (double)update["tempoRatio"]);
                if (update.contains("preservePitch"))
                    c.preservePitch = (bool)update["preservePitch"];
                p->setStretchOptions(c.tempoRatio, c.preservePitch);
            }
            if (update.contains("pitchSemitones"))
            {
                c.pitchSemitones = juce::jlimit(-24.0f, 24.0f, (float)update["pitchSemitones"]);
                p->setPitchSemitones(c.pitchSemitones);
            }
            if (update.contains("muted"))
            {
                c.muted = (bool)update["muted"];
                p->setMuted(c.muted);
            }
        }

        if (scheduleChanged)
            addClipToRoutedSchedule(c);
        ++applied;
    }
    endRoutedClipScheduleMutationLocked();
    return applied;
}

int JuceEngine::updateClipFadesBatch(const juce::Array<juce::NamedValueSet> &updates)
{
    if (updates.isEmpty())
        return 0;

    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    if (clips.empty())
        return 0;

    int applied = 0;
    for (const auto &update : updates)
    {
        const int clipId = (int)update["clip"];
        if (clipId < 0 || clipId >= (int)clips.size())
            continue;

        ClipState &clip = clips[(size_t)clipId];
        if (!clip.alive || liveProcessorForClip(clip) == nullptr)
            continue;

        clip.fadeInSec = juce::jmax(0.0, (double)update["fadeInSec"]);
        clip.fadeOutSec = juce::jmax(0.0, (double)update["fadeOutSec"]);
        clip.fadeCurve = juce::jlimit(0, 2, (int)update["fadeCurve"]);
        if (auto *processor = timelineProcessorForClip(clip))
            processor->setFades(clip.fadeInSec, clip.fadeOutSec, clip.fadeCurve);
        ++applied;
    }
    return applied;
}

void JuceEngine::setClipFades(int clipIndex, double fadeInSec, double fadeOutSec, int fadeCurve)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    ClipState &c = clips[clipIndex];
    if (!c.alive || liveProcessorForClip(c) == nullptr)
        return;

    c.fadeInSec = juce::jmax(0.0, fadeInSec);
    c.fadeOutSec = juce::jmax(0.0, fadeOutSec);
    c.fadeCurve = juce::jlimit(0, 2, fadeCurve);

    if (auto *p = timelineProcessorForClip(c))
        p->setFades(c.fadeInSec, c.fadeOutSec, c.fadeCurve);
}

bool JuceEngine::moveClipToRow(int clipId, int newRowId)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

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

    beginRoutedClipScheduleMutationLocked();
    removeClipFromRowIndex(c.rowId, clipId);
    c.rowId = resolvedRowId;
    addClipToRowIndex(c.rowId, clipId);
    endRoutedClipScheduleMutationLocked();
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

bool resolveKnownPluginDescription(const juce::KnownPluginList &list,
                                   const juce::String &idOrName,
                                   juce::PluginDescription &outDesc);
double getGraphTailLengthSeconds(juce::AudioProcessorGraph &graph);
void prepareGraphForOfflineRender(juce::AudioProcessorGraph &graph,
                                  double sampleRate,
                                  int blockSize);
void applyTpdfDither(juce::AudioBuffer<float> &buffer, int bitDepth);
double evaluateAutomationValueAtMs(const std::vector<AutomationPoint> &points,
                                   double timeMs,
                                   double fallbackValue);

juce::String getProcessorParameterIdentifier(juce::AudioProcessorParameter *parameter)
{
    if (parameter == nullptr)
        return {};

    if (auto *withID = dynamic_cast<juce::AudioProcessorParameterWithID *>(parameter))
        return withID->paramID;

    return parameter->getName(128).trim();
}

float normalizePanUiValue(float uiPan)
{
    return juce::jlimit(0.0f, 1.0f, uiPan);
}

bool isBuiltInEffectIdentifier(const juce::String &pluginId)
{
    static const juce::StringArray builtInEffects{
        "Gain",
        "EQ 3-Band",
        "Compressor",
        "Dynamic Softener",
        "Transient Shaper",
        "Limiter",
        "Clipper",
        "De-Esser",
        "Distortion",
        "Degrade",
        "Delay",
        "Reverb",
        "EQ Parametric",
        "Pitch Shift",
        "Pitch Corrector",
        "Chorus",
        "Vibrato",
        "Stereo",
        "Stereo Pro",
        "Volume Shaper",
        "Time Shaper",
    };

    return builtInEffects.contains(pluginId);
}

struct ExportParameterSnapshot
{
    juce::String identifier;
    float normalizedValue = 0.0f;
};

struct ExportEffectSnapshot
{
    juce::String pluginId;
    juce::MemoryBlock state;
    std::vector<ExportParameterSnapshot> parameters;
    bool bypassed = false;
};

struct ExportEffectAutomationLane
{
    int effectIndex = -1;
    juce::String paramId;
    float minValue = 0.0f;
    float maxValue = 1.0f;
    std::vector<AutomationPoint> points;
    float lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
};

struct ExportClipSnapshot
{
    bool alive = false;
    bool isMidi = false;
    bool muted = false;
    int clipId = -1;
    int rowId = 0;
    double startSec = 0.0;
    double lengthSec = 0.0;
    double inFileOffsetSec = 0.0;
    float pitchSemitones = 0.0f;
    bool reversed = false;
    double tempoRatio = 1.0;
    bool preservePitch = false;
    float gainUi = SimpleGainProcessor::kUiUnity;
    float extraGainLinear = 1.0f;
    float panNormalized = 0.0f;
    double fadeInSec = 0.0;
    double fadeOutSec = 0.0;
    int fadeCurve = 0;
    juce::String sourceFilePath;
    juce::String midiInstrumentId;
    juce::String midiInstrumentName;
    juce::Array<TimelineMidiNote> midiNotes;
    juce::NamedValueSet midiParams;
    double midiSourceTempoBpm = 120.0;
};

struct ExportRowSnapshot
{
    int rowId = 0;
    float gainUi = SimpleGainProcessor::kUiUnity;
    float panUi = 0.5f;
    bool muted = false;
    std::vector<AutomationPoint> automationPoints;
    std::vector<AutomationPoint> gainAutomationPoints;
    std::vector<AutomationPoint> panAutomationPoints;
    std::vector<ExportEffectAutomationLane> effectAutomationLanes;
    std::vector<ExportEffectSnapshot> effects;
};

struct ExportGroupSnapshot
{
    juce::String id;
    juce::Array<int> rowIds;
    float gainUi = SimpleGainProcessor::kUiUnity;
    float panUi = 0.5f;
    bool muted = false;
    std::vector<ExportEffectSnapshot> effects;
};

struct ExportProjectSnapshot
{
    std::vector<ExportClipSnapshot> clips;
    std::vector<ExportRowSnapshot> rows;
    std::vector<ExportGroupSnapshot> groups;
    std::vector<ExportEffectSnapshot> masterEffects;
    std::vector<ExportEffectAutomationLane> masterEffectAutomationLanes;
    std::vector<AutomationPoint> masterGainAutomationPoints;
    std::vector<AutomationPoint> masterPanAutomationPoints;
    float masterGainUi = SimpleGainProcessor::kUiUnity;
    float masterPanUi = 0.5f;
    bool masterMuted = false;
    double tempoBpm = 120.0;
};

void applyDryClipRenderOptions(ExportProjectSnapshot &snapshot)
{
    snapshot.masterEffects.clear();
    snapshot.masterEffectAutomationLanes.clear();
    snapshot.masterGainAutomationPoints.clear();
    snapshot.masterPanAutomationPoints.clear();
    snapshot.masterGainUi = SimpleGainProcessor::kUiUnity;
    snapshot.masterPanUi = 0.5f;
    snapshot.masterMuted = false;

    for (auto &row : snapshot.rows)
    {
        row.effects.clear();
        row.effectAutomationLanes.clear();
        row.automationPoints.clear();
        row.gainAutomationPoints.clear();
        row.panAutomationPoints.clear();
        row.gainUi = SimpleGainProcessor::kUiUnity;
        row.panUi = 0.5f;
        row.muted = false;
    }
}

struct OfflineClipRenderState
{
    ExportClipSnapshot clip;
    TimelineClipProcessorBase *processor = nullptr;
    juce::AudioProcessorGraph::Node::Ptr playerNode;
};

struct OfflineRowRenderState
{
    int rowId = 0;
    float gainUi = SimpleGainProcessor::kUiUnity;
    float panUi = 0.5f;
    bool muted = false;
    VolumeAutomationProcessor *automationProc = nullptr;
    SimpleGainProcessor *gainProc = nullptr;
    StereoPanProcessor *panProc = nullptr;
    juce::AudioProcessorGraph::Node::Ptr inputNode;
    juce::Array<juce::AudioProcessorGraph::NodeID> fxChain;
    std::vector<AutomationPoint> automationPoints;
    std::vector<AutomationPoint> gainAutomationPoints;
    std::vector<AutomationPoint> panAutomationPoints;
    std::vector<ExportEffectAutomationLane> effectAutomationLanes;
    float lastAppliedGainAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
    float lastAppliedPanAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
};

struct OfflineMasterRenderState
{
    float gainUi = SimpleGainProcessor::kUiUnity;
    float panUi = 0.5f;
    bool muted = false;
    TrackInputProcessor *inputProc = nullptr;
    SimpleGainProcessor *gainProc = nullptr;
    StereoPanProcessor *panProc = nullptr;
    juce::AudioProcessorGraph::Node::Ptr inputNode;
    juce::Array<juce::AudioProcessorGraph::NodeID> fxChain;
    std::vector<AutomationPoint> gainAutomationPoints;
    std::vector<AutomationPoint> panAutomationPoints;
    std::vector<ExportEffectAutomationLane> effectAutomationLanes;
    float lastAppliedGainAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
    float lastAppliedPanAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
};

struct OfflineGroupRenderState
{
    juce::String id;
    juce::Array<int> rowIds;
    float gainUi = SimpleGainProcessor::kUiUnity;
    float panUi = 0.5f;
    bool muted = false;
    TrackInputProcessor *inputProc = nullptr;
    SimpleGainProcessor *gainProc = nullptr;
    StereoPanProcessor *panProc = nullptr;
    juce::AudioProcessorGraph::Node::Ptr inputNode;
    juce::Array<juce::AudioProcessorGraph::NodeID> fxChain;
};

struct OfflineExportContext
{
    juce::AudioProcessorGraph graph;
    juce::AudioProcessorGraph::Node::Ptr outputNode;
    std::vector<OfflineClipRenderState> clips;
    std::vector<OfflineRowRenderState> rows;
    std::vector<OfflineGroupRenderState> groups;
    std::unordered_map<int, int> rowIdToIndex;
    std::unordered_map<int, int> rowIdToGroupIndex;
    OfflineMasterRenderState master;
    OfflineExportPlayHead playHead;
    std::atomic<double> blockTransportStartSec{0.0};
    std::atomic<double> hostSampleRate{44100.0};
    std::atomic<bool> blockIsPlaying{true};
};

std::vector<ExportParameterSnapshot> captureProcessorParameters(juce::AudioProcessor &processor)
{
    std::vector<ExportParameterSnapshot> snapshots;
    const auto parameters = processor.getParameters();
    snapshots.reserve(parameters.size());

    for (auto *parameter : parameters)
    {
        if (parameter == nullptr)
            continue;

        const auto identifier = getProcessorParameterIdentifier(parameter);
        if (identifier.isEmpty())
            continue;

        ExportParameterSnapshot snapshot;
        snapshot.identifier = identifier;
        snapshot.normalizedValue = juce::jlimit(0.0f, 1.0f, parameter->getValue());
        snapshots.push_back(std::move(snapshot));
    }

    return snapshots;
}

ExportEffectSnapshot captureEffectSnapshot(const juce::String &pluginId,
                                          const juce::AudioProcessorGraph::Node::Ptr &node)
{
    ExportEffectSnapshot snapshot;
    snapshot.pluginId = pluginId;

    if (node == nullptr || node->getProcessor() == nullptr)
        return snapshot;

    node->getProcessor()->getStateInformation(snapshot.state);
    snapshot.parameters = captureProcessorParameters(*node->getProcessor());
    snapshot.bypassed = node->isBypassed();
    return snapshot;
}

void applyNormalizedParameterSnapshots(
    juce::AudioProcessor &processor,
    const std::vector<ExportParameterSnapshot> &snapshots)
{
    for (const auto &snapshot : snapshots)
    {
        for (auto *parameter : processor.getParameters())
        {
            if (parameter == nullptr)
                continue;

            const bool matches =
                getProcessorParameterIdentifier(parameter) == snapshot.identifier ||
                parameter->getName(128) == snapshot.identifier;
            if (!matches)
                continue;

            parameter->setValueNotifyingHost(
                juce::jlimit(0.0f, 1.0f, snapshot.normalizedValue));
            break;
        }
    }
}

void setProcessorParameterValue(juce::AudioProcessor &processor,
                                const juce::String &paramName,
                                const juce::var &newValue)
{
    for (auto *parameter : processor.getParameters())
    {
        if (parameter == nullptr)
            continue;

        bool matchesParam = (parameter->getName(128) == paramName);
        if (!matchesParam)
            if (auto *withID = dynamic_cast<juce::AudioProcessorParameterWithID *>(parameter))
                matchesParam = (withID->paramID == paramName);

        if (!matchesParam)
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
            const auto text = newValue.toString();
            const int steps = parameter->getNumSteps();
            for (int i = 0; i < steps; ++i)
            {
                const float stepNormalized = (steps > 1) ? (float)i / (steps - 1) : 0.0f;
                if (parameter->getText(stepNormalized, 128) == text)
                {
                    normalized = stepNormalized;
                    break;
                }
            }
        }

        if (auto *withID = dynamic_cast<juce::AudioProcessorParameterWithID *>(parameter))
        {
            if (auto *floatParameter = dynamic_cast<juce::AudioParameterFloat *>(parameter))
            {
                const auto &range = floatParameter->range;
                const float clamped = juce::jlimit(range.start, range.end, normalized);
                const float normalizedValue = range.convertTo0to1(clamped);
                floatParameter->setValueNotifyingHost(normalizedValue);
            }
            else
            {
                withID->setValueNotifyingHost(normalized);
            }
        }
        else
        {
            parameter->setValueNotifyingHost(normalized);
        }

        return;
    }
}

std::unique_ptr<juce::AudioProcessor> createEffectProcessorFromIdentifier(
    juce::AudioPluginFormatManager &pluginFormatManager,
    const juce::KnownPluginList &pluginList,
    const juce::String &pluginId,
    double sampleRate,
    int blockSize,
    juce::String &error)
{
    if (isBuiltInEffectIdentifier(pluginId))
    {
        if (pluginId == "Reverb")
            return std::make_unique<ReverbAudioProcessor>();
        if (pluginId == "EQ Parametric")
            return std::make_unique<EQAudioProcessor>();
        if (pluginId == "EQ 3-Band")
            return std::make_unique<EQ3AudioProcessor>();
        if (pluginId == "Delay")
            return std::make_unique<DelayAudioProcessor>();
        if (pluginId == "Distortion")
            return std::make_unique<DistortionAudioProcessor>();
        if (pluginId == "Degrade")
            return std::make_unique<DegradeAudioProcessor>();
        if (pluginId == "De-Esser")
            return std::make_unique<DeesserAudioProcessor>();
        if (pluginId == "Compressor")
            return std::make_unique<CompressorAudioProcessor>();
        if (pluginId == "Dynamic Softener")
            return std::make_unique<DynamicSoftenerAudioProcessor>();
        if (pluginId == "Transient Shaper")
            return std::make_unique<TransientShaperAudioProcessor>();
        if (pluginId == "Limiter")
            return std::make_unique<LimiterAudioProcessor>();
        if (pluginId == "Clipper")
            return std::make_unique<ClipperAudioProcessor>();
        if (pluginId == "Pitch Shift")
            return std::make_unique<PitchShiftAudioProcessor>();
        if (pluginId == "Pitch Corrector")
            return std::make_unique<PitchCorrectorAudioProcessor>();
        if (pluginId == "Chorus")
            return std::make_unique<ChorusAudioProcessor>();
        if (pluginId == "Vibrato")
            return std::make_unique<VibratoAudioProcessor>();
        if (pluginId == "Stereo")
            return std::make_unique<StereoAudioProcessor>();
        if (pluginId == "Stereo Pro")
            return std::make_unique<StereoProAudioProcessor>();
        if (pluginId == "Volume Shaper")
            return std::make_unique<VolumeShaperAudioProcessor>();
        if (pluginId == "Time Shaper")
            return std::make_unique<TimeShaperAudioProcessor>();
        if (pluginId == "Gain")
            return std::make_unique<SimpleGainProcessor>();

        error = "Unknown built-in effect: " + pluginId;
        return {};
    }

    const auto requestedId = pluginId.trim();
    if (requestedId.isEmpty())
    {
        error = "Empty plugin identifier";
        return {};
    }

    juce::PluginDescription description;
    const bool resolved = resolveKnownPluginDescription(pluginList, requestedId, description);
    if (!resolved)
    {
        description.fileOrIdentifier = requestedId;
#if JUCE_IOS
        description.pluginFormatName = "AudioUnit";
#endif
    }

    try
    {
        return pluginFormatManager.createPluginInstance(
            description,
            sampleRate,
            blockSize,
            error);
    }
    catch (const std::exception &exception)
    {
        error = "exception: " + juce::String(exception.what());
    }
    catch (...)
    {
        error = "unknown exception";
    }

    return {};
}

void applyClipSnapshotToProcessor(const ExportClipSnapshot &clip,
                                  TimelineClipProcessorBase &processor)
{
    processor.setTimeline(clip.startSec, clip.lengthSec, clip.inFileOffsetSec);
    processor.setStretchOptions(clip.tempoRatio, clip.preservePitch);
    processor.setPitchSemitones(clip.pitchSemitones);
    processor.setReversed(clip.reversed);
    processor.setMuted(clip.muted);
    processor.setGainUi(clip.gainUi);
    processor.setExtraGainLinear(clip.extraGainLinear);
    processor.setPanNormalized(clip.panNormalized);
    processor.setFades(clip.fadeInSec, clip.fadeOutSec, clip.fadeCurve);
}

bool shouldUseOfflineStaticAudioClipProcessor(const ExportClipSnapshot &clip)
{
    constexpr double epsilon = 1.0e-6;
    return !clip.reversed &&
           std::abs(clip.tempoRatio - 1.0) <= epsilon &&
           std::abs((double)clip.pitchSemitones) <= epsilon;
}

double readJsonDoubleProperty(juce::DynamicObject *object,
                              const char *propertyName,
                              double fallback)
{
    if (object == nullptr || !object->hasProperty(propertyName))
        return fallback;

    const auto value = object->getProperty(propertyName);
    if (value.isDouble() || value.isInt() || value.isInt64())
        return (double)value;

    return fallback;
}

int readJsonIntProperty(juce::DynamicObject *object,
                        const char *propertyName,
                        int fallback)
{
    return (int)std::lround(readJsonDoubleProperty(object, propertyName, (double)fallback));
}

bool readJsonBoolProperty(juce::DynamicObject *object,
                          const char *propertyName,
                          bool fallback)
{
    if (object == nullptr || !object->hasProperty(propertyName))
        return fallback;

    const auto value = object->getProperty(propertyName);
    if (value.isBool())
        return (bool)value;
    if (value.isDouble() || value.isInt() || value.isInt64())
        return std::abs((double)value) > 0.5;

    const auto text = value.toString().trim().toLowerCase();
    if (text == "true" || text == "1")
        return true;
    if (text == "false" || text == "0")
        return false;
    return fallback;
}

juce::String readJsonStringProperty(juce::DynamicObject *object,
                                    const char *propertyName,
                                    const juce::String &fallback = {})
{
    if (object == nullptr || !object->hasProperty(propertyName))
        return fallback;
    return object->getProperty(propertyName).toString();
}

void parseJsonMidiNotes(const juce::var &rawNotes,
                        juce::Array<TimelineMidiNote> &notesOut)
{
    notesOut.clear();
    const auto *notesArray = rawNotes.getArray();
    if (notesArray == nullptr)
        return;

    for (const auto &noteVar : *notesArray)
    {
        auto *noteObject = noteVar.getDynamicObject();
        if (noteObject == nullptr)
            continue;

        TimelineMidiNote note;
        note.noteId = readJsonStringProperty(noteObject, "id");
        note.pitch = juce::jlimit(0, 127, readJsonIntProperty(noteObject, "pitch", 60));
        note.startBeat = juce::jmax(0.0, readJsonDoubleProperty(noteObject, "startBeat", 0.0));
        note.lengthBeats = juce::jmax(0.001, readJsonDoubleProperty(noteObject, "lengthBeats", 1.0));
        note.velocity = juce::jlimit(0.0, 1.0, readJsonDoubleProperty(noteObject, "velocity", 0.8));
        notesOut.add(note);
    }
}

void parseJsonNamedValueSet(const juce::var &rawValues,
                            juce::NamedValueSet &valuesOut)
{
    valuesOut = {};
    auto *valueObject = rawValues.getDynamicObject();
    if (valueObject == nullptr)
        return;

    const auto &properties = valueObject->getProperties();
    for (int propertyIndex = 0; propertyIndex < properties.size(); ++propertyIndex)
        valuesOut.set(properties.getName(propertyIndex), properties.getValueAt(propertyIndex));
}

bool parseExportClipSnapshotJson(const juce::String &clipSnapshotJson,
                                 std::vector<ExportClipSnapshot> &clipsOut,
                                 juce::String &error)
{
    clipsOut.clear();
    if (clipSnapshotJson.trim().isEmpty())
        return true;

    const auto parsed = juce::JSON::parse(clipSnapshotJson);
    if (parsed.isVoid())
    {
        error = "Export clip snapshot JSON could not be parsed.";
        return false;
    }

    const auto *clipArray = parsed.getArray();
    if (clipArray == nullptr)
    {
        error = "Export clip snapshot JSON must be an array.";
        return false;
    }

    clipsOut.reserve((size_t)clipArray->size());
    for (const auto &clipVar : *clipArray)
    {
        auto *clipObject = clipVar.getDynamicObject();
        if (clipObject == nullptr)
            continue;

        if (!clipObject->hasProperty("clipId"))
        {
            error = "Export clip snapshot JSON is missing clipId.";
            return false;
        }

        if (!clipObject->hasProperty("rowId") ||
            !clipObject->hasProperty("startSec") ||
            !clipObject->hasProperty("lengthSec"))
        {
            error = "Export clip snapshot JSON is missing required clip timing or routing fields.";
            return false;
        }

        ExportClipSnapshot clip;
        clip.alive = readJsonBoolProperty(clipObject, "alive", true);
        clip.isMidi = readJsonBoolProperty(clipObject, "isMidi", false);
        clip.muted = readJsonBoolProperty(clipObject, "muted", false);
        clip.clipId = readJsonIntProperty(clipObject, "clipId", -1);
        clip.rowId = readJsonIntProperty(clipObject, "rowId", 0);
        clip.startSec = juce::jmax(0.0, readJsonDoubleProperty(clipObject, "startSec", 0.0));
        clip.lengthSec = juce::jmax(0.0, readJsonDoubleProperty(clipObject, "lengthSec", 0.0));
        clip.inFileOffsetSec = juce::jmax(0.0, readJsonDoubleProperty(clipObject, "inFileOffsetSec", 0.0));
        clip.pitchSemitones = (float)juce::jlimit(-24.0, 24.0, readJsonDoubleProperty(clipObject, "pitchSemitones", 0.0));
        clip.reversed = readJsonBoolProperty(clipObject, "reversed", false);
        clip.tempoRatio = juce::jlimit(0.05, 20.0, readJsonDoubleProperty(clipObject, "tempoRatio", 1.0));
        clip.preservePitch = readJsonBoolProperty(clipObject, "preservePitch", false);
        clip.gainUi = (float)juce::jlimit(
            (double)SimpleGainProcessor::kUiMin,
            (double)SimpleGainProcessor::kUiMax,
            readJsonDoubleProperty(clipObject, "gainUi", SimpleGainProcessor::kUiUnity));
        clip.extraGainLinear = (float)juce::jlimit(
            0.0,
            64.0,
            readJsonDoubleProperty(clipObject, "extraGainLinear", 1.0));
        clip.panNormalized = (float)juce::jlimit(-1.0, 1.0, readJsonDoubleProperty(clipObject, "panNormalized", 0.0));
        clip.fadeInSec = juce::jmax(0.0, readJsonDoubleProperty(clipObject, "fadeInSec", 0.0));
        clip.fadeOutSec = juce::jmax(0.0, readJsonDoubleProperty(clipObject, "fadeOutSec", 0.0));
        clip.fadeCurve = juce::jlimit(0, 2, (int)std::round(readJsonDoubleProperty(clipObject, "fadeCurve", 0.0)));
        clip.sourceFilePath = readJsonStringProperty(clipObject, "sourceFilePath");
        clip.midiInstrumentId = readJsonStringProperty(clipObject, "midiInstrumentId");
        clip.midiInstrumentName = readJsonStringProperty(clipObject, "midiInstrumentName");
        clip.midiSourceTempoBpm =
            juce::jlimit(1.0, 400.0, readJsonDoubleProperty(clipObject, "midiSourceTempoBpm", 120.0));
        if (clipObject->hasProperty("midiNotes"))
            parseJsonMidiNotes(clipObject->getProperty("midiNotes"), clip.midiNotes);
        if (clipObject->hasProperty("midiParams"))
            parseJsonNamedValueSet(clipObject->getProperty("midiParams"), clip.midiParams);

        if (clip.clipId < 0)
            continue;

        clipsOut.push_back(std::move(clip));
    }

    return true;
}

bool mergeExportClipSnapshotsIntoProject(std::vector<ExportClipSnapshot> &projectClips,
                                         std::vector<ExportClipSnapshot> &&overrideClips,
                                         juce::String &error)
{
    if (overrideClips.empty())
        return true;

    std::unordered_map<int, size_t> projectIndexByClipId;
    projectIndexByClipId.reserve(projectClips.size());
    for (size_t i = 0; i < projectClips.size(); ++i)
        projectIndexByClipId[projectClips[i].clipId] = i;

    std::unordered_set<int> seenOverrideClipIds;
    seenOverrideClipIds.reserve(overrideClips.size());

    for (auto &overrideClip : overrideClips)
    {
        if (!seenOverrideClipIds.insert(overrideClip.clipId).second)
        {
            error = "Export clip snapshot JSON contains duplicate clip ids.";
            return false;
        }

        const auto projectIt = projectIndexByClipId.find(overrideClip.clipId);
        if (projectIt != projectIndexByClipId.end())
        {
            projectClips[projectIt->second] = std::move(overrideClip);
            continue;
        }

        projectIndexByClipId[overrideClip.clipId] = projectClips.size();
        projectClips.push_back(std::move(overrideClip));
    }

    return true;
}

void applyEffectSnapshotToNode(const ExportEffectSnapshot &snapshot,
                               const juce::AudioProcessorGraph::Node::Ptr &node)
{
    if (node == nullptr || node->getProcessor() == nullptr)
        return;

    if (!snapshot.state.isEmpty())
        node->getProcessor()->setStateInformation(snapshot.state.getData(),
                                                  (int)snapshot.state.getSize());
    applyNormalizedParameterSnapshots(*node->getProcessor(), snapshot.parameters);
    node->setBypassed(snapshot.bypassed);
}

void reapplyOfflineEffectSnapshots(OfflineExportContext &context,
                                   const ExportProjectSnapshot &snapshot)
{
    for (int effectIndex = 0; effectIndex < context.master.fxChain.size() &&
                              effectIndex < (int)snapshot.masterEffects.size();
         ++effectIndex)
    {
        applyEffectSnapshotToNode(
            snapshot.masterEffects[(size_t)effectIndex],
            context.graph.getNodeForId(context.master.fxChain.getReference(effectIndex)));
    }

    for (size_t groupIndex = 0; groupIndex < context.groups.size() &&
                                groupIndex < snapshot.groups.size();
         ++groupIndex)
    {
        auto &group = context.groups[groupIndex];
        const auto &groupSnapshot = snapshot.groups[groupIndex];
        for (int effectIndex = 0; effectIndex < group.fxChain.size() &&
                                  effectIndex < (int)groupSnapshot.effects.size();
             ++effectIndex)
        {
            applyEffectSnapshotToNode(
                groupSnapshot.effects[(size_t)effectIndex],
                context.graph.getNodeForId(group.fxChain.getReference(effectIndex)));
        }
    }

    for (size_t rowIndex = 0; rowIndex < context.rows.size() &&
                              rowIndex < snapshot.rows.size();
         ++rowIndex)
    {
        auto &row = context.rows[rowIndex];
        const auto &rowSnapshot = snapshot.rows[rowIndex];
        for (int effectIndex = 0; effectIndex < row.fxChain.size() &&
                                  effectIndex < (int)rowSnapshot.effects.size();
             ++effectIndex)
        {
            applyEffectSnapshotToNode(
                rowSnapshot.effects[(size_t)effectIndex],
                context.graph.getNodeForId(row.fxChain.getReference(effectIndex)));
        }
    }
}

void applyOfflineRowStaticState(OfflineRowRenderState &row,
                                std::atomic<double> &blockTransportStartSec)
{
    if (row.automationProc != nullptr)
    {
        row.automationProc->setBlockTransportPtr(&blockTransportStartSec);
        row.automationProc->setAutomationPoints(row.automationPoints);
    }

    if (row.gainProc != nullptr)
    {
        row.gainProc->gain->setValueNotifyingHost(
            juce::jlimit(SimpleGainProcessor::kUiMin, SimpleGainProcessor::kUiMax, row.gainUi) /
            SimpleGainProcessor::kUiMax);
        row.gainProc->setMuted(row.muted);
    }

    if (row.panProc != nullptr)
        row.panProc->pan->setValueNotifyingHost(normalizePanUiValue(row.panUi));
}

void applyOfflineMasterStaticState(OfflineMasterRenderState &master)
{
    if (master.gainProc != nullptr)
    {
        master.gainProc->gain->setValueNotifyingHost(
            juce::jlimit(SimpleGainProcessor::kUiMin, SimpleGainProcessor::kUiMax, master.gainUi) /
            SimpleGainProcessor::kUiMax);
        master.gainProc->setMuted(master.muted);
    }

    if (master.panProc != nullptr)
        master.panProc->pan->setValueNotifyingHost(normalizePanUiValue(master.panUi));
}

void applyOfflineGroupStaticState(OfflineGroupRenderState &group)
{
    if (group.gainProc != nullptr)
    {
        group.gainProc->gain->setValueNotifyingHost(
            juce::jlimit(SimpleGainProcessor::kUiMin, SimpleGainProcessor::kUiMax, group.gainUi) /
            SimpleGainProcessor::kUiMax);
        group.gainProc->setMuted(group.muted);
    }

    if (group.panProc != nullptr)
        group.panProc->pan->setValueNotifyingHost(normalizePanUiValue(group.panUi));
}

bool buildOfflineExportContext(
    const ExportProjectSnapshot &snapshot,
    double sampleRate,
    int blockSize,
    juce::AudioFormatManager &formatManager,
    juce::AudioPluginFormatManager &pluginFormatManager,
    const juce::KnownPluginList &pluginList,
    OfflineExportContext &context,
    juce::String &error)
{
    constexpr int numChannels = 2;

    context.blockTransportStartSec.store(0.0, std::memory_order_relaxed);
    context.hostSampleRate.store(sampleRate, std::memory_order_relaxed);
    context.blockIsPlaying.store(false, std::memory_order_relaxed);
    context.rows.clear();
    context.rowIdToIndex.clear();
    context.groups.clear();
    context.rowIdToGroupIndex.clear();
    context.clips.clear();
    context.playHead.setTransport(0.0, sampleRate, snapshot.tempoBpm, false);
    context.graph.setPlayHead(&context.playHead);
    context.graph.setPlayConfigDetails(0, numChannels, sampleRate, blockSize);

    context.outputNode = context.graph.addNode(
        std::make_unique<juce::AudioProcessorGraph::AudioGraphIOProcessor>(
            juce::AudioProcessorGraph::AudioGraphIOProcessor::audioOutputNode));
    if (context.outputNode == nullptr)
    {
        error = "Offline export graph could not create output node.";
        return false;
    }
    if (auto *outputProcessor = context.outputNode->getProcessor())
        outputProcessor->setPlayConfigDetails(numChannels, 0, sampleRate, blockSize);

    {
        auto inputProcessor = std::make_unique<TrackInputProcessor>();
        context.master.inputProc = inputProcessor.get();
        context.master.inputNode = context.graph.addNode(std::move(inputProcessor));

        auto gainProcessor = std::make_unique<SimpleGainProcessor>();
        context.master.gainProc = gainProcessor.get();
        auto masterGainNode = context.graph.addNode(std::move(gainProcessor));

        auto panProcessor = std::make_unique<StereoPanProcessor>();
        context.master.panProc = panProcessor.get();
        auto masterPanNode = context.graph.addNode(std::move(panProcessor));

        if (context.master.inputNode == nullptr || masterGainNode == nullptr || masterPanNode == nullptr)
        {
            error = "Offline export graph could not create master bus nodes.";
            return false;
        }

        context.master.gainUi = snapshot.masterGainUi;
        context.master.panUi = snapshot.masterPanUi;
        context.master.muted = snapshot.masterMuted;
        context.master.gainAutomationPoints = snapshot.masterGainAutomationPoints;
        context.master.panAutomationPoints = snapshot.masterPanAutomationPoints;
        context.master.effectAutomationLanes = snapshot.masterEffectAutomationLanes;

        juce::AudioProcessorGraph::NodeID previousNodeId = context.master.inputNode->nodeID;
        for (const auto &effectSnapshot : snapshot.masterEffects)
        {
            juce::String pluginError;
            auto processor = createEffectProcessorFromIdentifier(
                pluginFormatManager,
                pluginList,
                effectSnapshot.pluginId,
                sampleRate,
                blockSize,
                pluginError);
            if (!processor)
            {
                error = "Offline export could not create master effect '" +
                        effectSnapshot.pluginId + "': " + pluginError;
                return false;
            }

            if (!effectSnapshot.state.isEmpty())
                processor->setStateInformation(effectSnapshot.state.getData(),
                                               (int)effectSnapshot.state.getSize());
            applyNormalizedParameterSnapshots(*processor, effectSnapshot.parameters);

            auto node = context.graph.addNode(std::move(processor));
            if (node == nullptr)
            {
                error = "Offline export graph could not add master effect node.";
                return false;
            }

            node->setBypassed(effectSnapshot.bypassed);
            context.master.fxChain.add(node->nodeID);
            connectStereo(context.graph, previousNodeId, node->nodeID);
            previousNodeId = node->nodeID;
        }

        connectStereo(context.graph, previousNodeId, masterGainNode->nodeID);
        connectStereo(context.graph, masterGainNode->nodeID, masterPanNode->nodeID);
        connectStereo(context.graph, masterPanNode->nodeID, context.outputNode->nodeID);
    }

    context.groups.reserve(snapshot.groups.size());
    for (const auto &groupSnapshot : snapshot.groups)
    {
        if (groupSnapshot.id.trim().isEmpty() || groupSnapshot.rowIds.isEmpty())
            continue;

        OfflineGroupRenderState group;
        group.id = groupSnapshot.id;
        group.rowIds = groupSnapshot.rowIds;
        group.gainUi = groupSnapshot.gainUi;
        group.panUi = groupSnapshot.panUi;
        group.muted = groupSnapshot.muted;

        auto inputProcessor = std::make_unique<TrackInputProcessor>();
        group.inputProc = inputProcessor.get();
        group.inputNode = context.graph.addNode(std::move(inputProcessor));

        auto gainProcessor = std::make_unique<SimpleGainProcessor>();
        group.gainProc = gainProcessor.get();
        auto gainNode = context.graph.addNode(std::move(gainProcessor));

        auto panProcessor = std::make_unique<StereoPanProcessor>();
        group.panProc = panProcessor.get();
        auto panNode = context.graph.addNode(std::move(panProcessor));

        if (group.inputNode == nullptr || gainNode == nullptr || panNode == nullptr)
        {
            error = "Offline export graph could not create group bus nodes.";
            return false;
        }

        juce::AudioProcessorGraph::NodeID previousNodeId = group.inputNode->nodeID;
        for (const auto &effectSnapshot : groupSnapshot.effects)
        {
            juce::String pluginError;
            auto processor = createEffectProcessorFromIdentifier(
                pluginFormatManager,
                pluginList,
                effectSnapshot.pluginId,
                sampleRate,
                blockSize,
                pluginError);
            if (!processor)
            {
                error = "Offline export could not create group effect '" +
                        effectSnapshot.pluginId + "': " + pluginError;
                return false;
            }

            if (!effectSnapshot.state.isEmpty())
                processor->setStateInformation(effectSnapshot.state.getData(),
                                               (int)effectSnapshot.state.getSize());
            applyNormalizedParameterSnapshots(*processor, effectSnapshot.parameters);

            auto node = context.graph.addNode(std::move(processor));
            if (node == nullptr)
            {
                error = "Offline export graph could not add group effect node.";
                return false;
            }

            node->setBypassed(effectSnapshot.bypassed);
            group.fxChain.add(node->nodeID);
            connectStereo(context.graph, previousNodeId, node->nodeID);
            previousNodeId = node->nodeID;
        }

        connectStereo(context.graph, previousNodeId, gainNode->nodeID);
        connectStereo(context.graph, gainNode->nodeID, panNode->nodeID);
        connectStereo(context.graph, panNode->nodeID, context.master.inputNode->nodeID);

        const int groupIndex = (int)context.groups.size();
        for (int i = 0; i < group.rowIds.size(); ++i)
            context.rowIdToGroupIndex[group.rowIds[i]] = groupIndex;
        context.groups.push_back(std::move(group));
    }

    context.rows.reserve(snapshot.rows.size());
    for (const auto &rowSnapshot : snapshot.rows)
    {
        OfflineRowRenderState row;
        row.rowId = rowSnapshot.rowId;
        row.gainUi = rowSnapshot.gainUi;
        row.panUi = rowSnapshot.panUi;
        row.muted = rowSnapshot.muted;
        row.automationPoints = rowSnapshot.automationPoints;
        row.gainAutomationPoints = rowSnapshot.gainAutomationPoints;
        row.panAutomationPoints = rowSnapshot.panAutomationPoints;
        row.effectAutomationLanes = rowSnapshot.effectAutomationLanes;

        auto inputProcessor = std::make_unique<TrackInputProcessor>();
        row.inputNode = context.graph.addNode(std::move(inputProcessor));

        auto automationProcessor = std::make_unique<VolumeAutomationProcessor>();
        row.automationProc = automationProcessor.get();
        auto automationNode = context.graph.addNode(std::move(automationProcessor));

        auto gainProcessor = std::make_unique<SimpleGainProcessor>();
        row.gainProc = gainProcessor.get();
        auto gainNode = context.graph.addNode(std::move(gainProcessor));

        auto panProcessor = std::make_unique<StereoPanProcessor>();
        row.panProc = panProcessor.get();
        auto panNode = context.graph.addNode(std::move(panProcessor));

        if (row.inputNode == nullptr || automationNode == nullptr || gainNode == nullptr || panNode == nullptr)
        {
            error = "Offline export graph could not create row bus nodes.";
            return false;
        }

        row.automationProc->setBlockTransportPtr(&context.blockTransportStartSec);
        row.automationProc->setAutomationPoints(rowSnapshot.automationPoints);

        juce::AudioProcessorGraph::NodeID previousNodeId = row.inputNode->nodeID;
        for (const auto &effectSnapshot : rowSnapshot.effects)
        {
            juce::String pluginError;
            auto processor = createEffectProcessorFromIdentifier(
                pluginFormatManager,
                pluginList,
                effectSnapshot.pluginId,
                sampleRate,
                blockSize,
                pluginError);
            if (!processor)
            {
                error = "Offline export could not create row effect '" +
                        effectSnapshot.pluginId + "': " + pluginError;
                return false;
            }

            if (!effectSnapshot.state.isEmpty())
                processor->setStateInformation(effectSnapshot.state.getData(),
                                               (int)effectSnapshot.state.getSize());
            applyNormalizedParameterSnapshots(*processor, effectSnapshot.parameters);

            auto node = context.graph.addNode(std::move(processor));
            if (node == nullptr)
            {
                error = "Offline export graph could not add row effect node.";
                return false;
            }

            node->setBypassed(effectSnapshot.bypassed);
            row.fxChain.add(node->nodeID);
            connectStereo(context.graph, previousNodeId, node->nodeID);
            previousNodeId = node->nodeID;
        }

        connectStereo(context.graph, previousNodeId, automationNode->nodeID);
        connectStereo(context.graph, automationNode->nodeID, gainNode->nodeID);
        connectStereo(context.graph, gainNode->nodeID, panNode->nodeID);
        auto groupIt = context.rowIdToGroupIndex.find(row.rowId);
        if (groupIt != context.rowIdToGroupIndex.end() &&
            groupIt->second >= 0 &&
            groupIt->second < (int)context.groups.size() &&
            context.groups[(size_t)groupIt->second].inputNode != nullptr)
        {
            connectStereo(
                context.graph,
                panNode->nodeID,
                context.groups[(size_t)groupIt->second].inputNode->nodeID);
        }
        else
        {
            connectStereo(context.graph, panNode->nodeID, context.master.inputNode->nodeID);
        }

        context.rowIdToIndex[row.rowId] = (int)context.rows.size();
        context.rows.push_back(std::move(row));
    }

    context.clips.reserve(snapshot.clips.size());
    for (const auto &clipSnapshot : snapshot.clips)
    {
        if (!clipSnapshot.alive)
            continue;

        const auto rowIt = context.rowIdToIndex.find(clipSnapshot.rowId);
        if (rowIt == context.rowIdToIndex.end())
        {
            error = "Offline export clip could not resolve its destination row.";
            return false;
        }
        const int rowIndex = rowIt->second;

        OfflineClipRenderState clip;
        clip.clip = clipSnapshot;

        const juce::File renderedSourceFile(clipSnapshot.sourceFilePath);
        const bool canUseRenderedSource =
            clipSnapshot.isMidi &&
            clipSnapshot.midiNotes.isEmpty() &&
            clipSnapshot.sourceFilePath.isNotEmpty() &&
            renderedSourceFile.existsAsFile();

        if (canUseRenderedSource || !clipSnapshot.isMidi)
        {
            const juce::File sourceFile =
                canUseRenderedSource ? renderedSourceFile
                                     : juce::File(clipSnapshot.sourceFilePath);
            std::unique_ptr<juce::AudioFormatReader> reader(
                formatManager.createReaderFor(sourceFile));
            if (!reader)
            {
                if (!canUseRenderedSource)
                {
                    error = "Offline export could not reopen clip source file: " +
                            clipSnapshot.sourceFilePath;
                    return false;
                }
            }

            if (reader)
            {
                auto decodedAsset = decodeReaderToStereoAsset(*reader);
                if (decodedAsset == nullptr)
                {
                    error = "Offline export could not decode clip source file: " +
                            clipSnapshot.sourceFilePath;
                    return false;
                }

                if (shouldUseOfflineStaticAudioClipProcessor(clipSnapshot))
                {
                    auto processor = std::make_unique<OfflineStaticAudioClipProcessor>(
                        decodedAsset,
                        sourceFile,
                        &context.blockTransportStartSec,
                        &context.hostSampleRate,
                        &context.blockIsPlaying);
                    applyClipSnapshotToProcessor(clipSnapshot, *processor);
                    clip.processor = processor.get();
                    clip.playerNode = context.graph.addNode(std::move(processor));
                }
                else
                {
                    auto processor = std::make_unique<TimelineClipProcessor>(
                        decodedAsset,
                        sourceFile,
                        &context.blockTransportStartSec,
                        &context.hostSampleRate,
                        &context.blockIsPlaying);
                    applyClipSnapshotToProcessor(clipSnapshot, *processor);
                    clip.processor = processor.get();
                    clip.playerNode = context.graph.addNode(std::move(processor));
                }
            }
        }

        if (clip.playerNode == nullptr && clipSnapshot.isMidi)
        {
            if (!TimelineMidiClipProcessor::canResolveSampledInstrument(
                    clipSnapshot.midiInstrumentId,
                    clipSnapshot.midiInstrumentName))
            {
                error = "Offline export could not resolve MIDI instrument for clip " +
                        juce::String(clipSnapshot.clipId) + ".";
                return false;
            }

            auto processor = std::make_unique<TimelineMidiClipProcessor>(
                &context.blockTransportStartSec,
                &context.hostSampleRate,
                &context.blockIsPlaying);
            processor->setMidiData(
                clipSnapshot.midiNotes,
                clipSnapshot.midiInstrumentId,
                clipSnapshot.midiInstrumentName,
                clipSnapshot.midiParams,
                clipSnapshot.midiSourceTempoBpm);
            applyClipSnapshotToProcessor(clipSnapshot, *processor);
            clip.processor = processor.get();
            clip.playerNode = context.graph.addNode(std::move(processor));
        }

        if (clip.playerNode == nullptr)
        {
            error = "Offline export clip is missing a renderable source.";
            return false;
        }

        if (clip.playerNode == nullptr || clip.processor == nullptr)
        {
            error = "Offline export graph could not add clip node.";
            return false;
        }

        connectStereo(
            context.graph,
            clip.playerNode->nodeID,
            context.rows[(size_t)rowIndex].inputNode->nodeID);
        context.clips.push_back(std::move(clip));
    }

    context.graph.rebuild();
    prepareGraphForOfflineRender(context.graph, sampleRate, blockSize);

    reapplyOfflineEffectSnapshots(context, snapshot);
    applyOfflineMasterStaticState(context.master);
    for (auto &group : context.groups)
        applyOfflineGroupStaticState(group);
    for (auto &row : context.rows)
        applyOfflineRowStaticState(row, context.blockTransportStartSec);
    for (auto &clip : context.clips)
    {
        if (clip.processor == nullptr)
            continue;

        applyClipSnapshotToProcessor(clip.clip, *clip.processor);
        clip.processor->primeForOfflineRender();
    }

    return true;
}

void applyOfflineAutomationAtTimeSeconds(OfflineExportContext &context, double timeSeconds)
{
    constexpr float kAutomationEpsilon = 1.0e-4f;
    const double timeMs = juce::jmax(0.0, timeSeconds) * 1000.0;

    for (auto &row : context.rows)
    {
        if (!row.gainAutomationPoints.empty())
        {
            const float normalized = juce::jlimit(
                0.0f,
                1.0f,
                (float)evaluateAutomationValueAtMs(row.gainAutomationPoints, timeMs, 0.0));
            if (!std::isfinite(row.lastAppliedGainAutomationNormalized) ||
                std::abs(normalized - row.lastAppliedGainAutomationNormalized) > kAutomationEpsilon)
            {
                const float gain = SimpleGainProcessor::kUiMin +
                                   (SimpleGainProcessor::kUiMax - SimpleGainProcessor::kUiMin) *
                                       normalized;
                row.gainUi = gain;
                if (row.gainProc != nullptr)
                {
                    row.gainProc->gain->setValueNotifyingHost(gain / SimpleGainProcessor::kUiMax);
                    row.gainProc->setMuted(row.muted);
                }
                row.lastAppliedGainAutomationNormalized = normalized;
            }
        }

        if (!row.panAutomationPoints.empty())
        {
            const float pan = juce::jlimit(
                0.0f,
                1.0f,
                (float)evaluateAutomationValueAtMs(row.panAutomationPoints, timeMs, 0.5));
        if (!std::isfinite(row.lastAppliedPanAutomationNormalized) ||
            std::abs(pan - row.lastAppliedPanAutomationNormalized) > kAutomationEpsilon)
        {
            row.panUi = pan;
            if (row.panProc != nullptr)
                row.panProc->pan->setValueNotifyingHost(normalizePanUiValue(pan));
            row.lastAppliedPanAutomationNormalized = pan;
        }
        }

        for (auto &lane : row.effectAutomationLanes)
        {
            if (lane.effectIndex < 0 || lane.effectIndex >= row.fxChain.size())
                continue;
            if (lane.paramId.trim().isEmpty() || lane.points.empty())
                continue;

            const float normalized = juce::jlimit(
                0.0f,
                1.0f,
                (float)evaluateAutomationValueAtMs(lane.points, timeMs, 0.0));
            if (std::isfinite(lane.lastAppliedNormalized) &&
                std::abs(normalized - lane.lastAppliedNormalized) <= kAutomationEpsilon)
                continue;

            auto node = context.graph.getNodeForId(row.fxChain.getReference(lane.effectIndex));
            if (node == nullptr || node->getProcessor() == nullptr)
                continue;

            const float value = lane.minValue + (lane.maxValue - lane.minValue) * normalized;
            setProcessorParameterValue(*node->getProcessor(), lane.paramId, juce::var((double)value));
            lane.lastAppliedNormalized = normalized;
        }
    }

    if (!context.master.gainAutomationPoints.empty())
    {
        const float normalized = juce::jlimit(
            0.0f,
            1.0f,
            (float)evaluateAutomationValueAtMs(context.master.gainAutomationPoints, timeMs, 0.0));
        if (!std::isfinite(context.master.lastAppliedGainAutomationNormalized) ||
            std::abs(normalized - context.master.lastAppliedGainAutomationNormalized) > kAutomationEpsilon)
        {
            const float gain = SimpleGainProcessor::kUiMin +
                               (SimpleGainProcessor::kUiMax - SimpleGainProcessor::kUiMin) *
                                   normalized;
            context.master.gainUi = gain;
            if (context.master.gainProc != nullptr)
            {
                context.master.gainProc->gain->setValueNotifyingHost(
                    gain / SimpleGainProcessor::kUiMax);
                context.master.gainProc->setMuted(context.master.muted);
            }
            context.master.lastAppliedGainAutomationNormalized = normalized;
        }
    }

    if (!context.master.panAutomationPoints.empty())
    {
        const float pan = juce::jlimit(
            0.0f,
            1.0f,
            (float)evaluateAutomationValueAtMs(context.master.panAutomationPoints, timeMs, 0.5));
        if (!std::isfinite(context.master.lastAppliedPanAutomationNormalized) ||
            std::abs(pan - context.master.lastAppliedPanAutomationNormalized) > kAutomationEpsilon)
        {
            context.master.panUi = pan;
            if (context.master.panProc != nullptr)
                context.master.panProc->pan->setValueNotifyingHost(normalizePanUiValue(pan));
            context.master.lastAppliedPanAutomationNormalized = pan;
        }
    }

    for (auto &lane : context.master.effectAutomationLanes)
    {
        if (lane.effectIndex < 0 || lane.effectIndex >= context.master.fxChain.size())
            continue;
        if (lane.paramId.trim().isEmpty() || lane.points.empty())
            continue;

        const float normalized = juce::jlimit(
            0.0f,
            1.0f,
            (float)evaluateAutomationValueAtMs(lane.points, timeMs, 0.0));
        if (std::isfinite(lane.lastAppliedNormalized) &&
            std::abs(normalized - lane.lastAppliedNormalized) <= kAutomationEpsilon)
            continue;

        auto node = context.graph.getNodeForId(context.master.fxChain.getReference(lane.effectIndex));
        if (node == nullptr || node->getProcessor() == nullptr)
            continue;

        const float value = lane.minValue + (lane.maxValue - lane.minValue) * normalized;
        setProcessorParameterValue(*node->getProcessor(), lane.paramId, juce::var((double)value));
        lane.lastAppliedNormalized = normalized;
    }
}

double getSnapshotEndTimeSeconds(const ExportProjectSnapshot &snapshot)
{
    double endTime = 0.0;
    for (const auto &clip : snapshot.clips)
    {
        if (!clip.alive)
            continue;
        endTime = juce::jmax(endTime, clip.startSec + clip.lengthSec);
    }
    return endTime;
}

void sanitiseExportBuffer(juce::AudioBuffer<float> &buffer)
{
    for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
    {
        auto *samples = buffer.getWritePointer(ch);
        for (int i = 0; i < buffer.getNumSamples(); ++i)
        {
            if (!std::isfinite(samples[i]))
                samples[i] = 0.0f;
        }
    }
}

juce::String renderOfflineSnapshotToFile(
    const ExportProjectSnapshot &snapshot,
    const juce::File &outFile,
    const JuceEngine::ExportOptions &options,
    int blockSize,
    double contentDurationSeconds,
    juce::AudioFormatManager &formatManager,
    juce::AudioPluginFormatManager &pluginFormatManager,
    const juce::KnownPluginList &pluginList,
    const std::function<void(double)> &progressCallback)
{
    if (options.format == "mp3")
    {
        juceLogToFlutter("❌ JUCE native MP3 export is not available on this iOS build.");
        return {};
    }

    juce::WavAudioFormat format;
    auto stream = std::unique_ptr<juce::FileOutputStream>(outFile.createOutputStream());
    if (!stream)
        return {};

    const double sampleRate = options.sampleRate;
    const int clampedBlockSize = juce::jlimit(64, 4096, blockSize > 0 ? blockSize : 512);
    constexpr int numChannels = 2;
    const int bitDepth = options.wavBitDepth;

    auto writer = std::unique_ptr<juce::AudioFormatWriter>(
        format.createWriterFor(stream.get(),
                               sampleRate,
                               (unsigned int)numChannels,
                               bitDepth,
                               {},
                               0));
    if (!writer)
        return {};

    stream.release();

    OfflineExportContext context;
    juce::String error;
    if (!buildOfflineExportContext(snapshot,
                                   sampleRate,
                                   clampedBlockSize,
                                   formatManager,
                                   pluginFormatManager,
                                   pluginList,
                                   context,
                                   error))
    {
        if (error.isNotEmpty())
            juceLogToFlutter(error.toRawUTF8());
        return {};
    }

    const double tailSeconds = getGraphTailLengthSeconds(context.graph);
    const int64 totalSamples =
        (int64)std::ceil((contentDurationSeconds + tailSeconds) * sampleRate);
    if (totalSamples <= 0)
    {
        if (progressCallback)
            progressCallback(1.0);
        return outFile.getFullPathName();
    }

    juce::AudioBuffer<float> buffer(numChannels, clampedBlockSize);
    juce::MidiBuffer midi;
    constexpr double kOfflineStartupPrerollSeconds = 4.0;
    const int64 minPrerollSamples = std::max<int64>(
        (int64)clampedBlockSize * 2,
        (int64)std::ceil(kOfflineStartupPrerollSeconds * sampleRate));
    const int64 prerollSamples =
        ((minPrerollSamples + (int64)clampedBlockSize - 1) / (int64)clampedBlockSize) *
        (int64)clampedBlockSize;
    const int64 totalRenderSamples = prerollSamples + totalSamples;
    double transportSeconds = -((double)prerollSamples / sampleRate);

    context.blockTransportStartSec.store(transportSeconds, std::memory_order_relaxed);
    context.blockIsPlaying.store(false, std::memory_order_relaxed);
    context.playHead.setTransport(0.0, sampleRate, snapshot.tempoBpm, false);
    mixroom::fx::setGlobalTransportSeconds(0.0);
    mixroom::fx::setGlobalTransportPlaying(false);

    int64 rendered = 0;
    int64 written = 0;
    while (rendered < totalRenderSamples)
    {
        const int samplesThisBlock =
            (int)std::min<int64>((int64)clampedBlockSize, totalRenderSamples - rendered);
        if (buffer.getNumSamples() != samplesThisBlock)
            buffer.setSize(numChannels, samplesThisBlock, false, false, true);
        buffer.clear();
        midi.clear();

        const bool hostIsPlaying = transportSeconds >= 0.0;
        const double hostTransportSeconds = hostIsPlaying ? transportSeconds : 0.0;
        context.blockTransportStartSec.store(transportSeconds, std::memory_order_relaxed);
        context.blockIsPlaying.store(hostIsPlaying, std::memory_order_relaxed);
        context.playHead.setTransport(hostTransportSeconds, sampleRate, snapshot.tempoBpm, hostIsPlaying);
        mixroom::fx::setGlobalTransportSeconds(hostTransportSeconds);
        mixroom::fx::setGlobalTransportPlaying(hostIsPlaying);
        const double automationSeconds = hostTransportSeconds;
        applyOfflineAutomationAtTimeSeconds(context, automationSeconds);
        context.graph.processBlock(buffer, midi);
        sanitiseExportBuffer(buffer);

        const int64 validStartSample = std::max<int64>(
            0,
            prerollSamples - rendered);
        const int64 validEndSample = std::min<int64>(
            (int64)samplesThisBlock,
            (prerollSamples + totalSamples) - rendered);
        const int validCount = (int)std::max<int64>(
            0,
            validEndSample - validStartSample);
        if (validCount > 0)
        {
            if (options.wavDithering)
                applyTpdfDither(buffer, bitDepth);
            writer->writeFromAudioSampleBuffer(
                buffer,
                (int)validStartSample,
                validCount);
            written += (int64)validCount;
        }

        transportSeconds += (double)samplesThisBlock / sampleRate;
        rendered += samplesThisBlock;

        if (progressCallback)
        {
            progressCallback(
                juce::jlimit(0.0, 1.0, (double)written / (double)totalSamples));
        }
    }

    if (progressCallback)
        progressCallback(1.0);
    return outFile.getFullPathName();
}

double getGraphTailLengthSeconds(juce::AudioProcessorGraph &graph)
{
    double tailSeconds = 0.0;

    for (auto *node : graph.getNodes())
    {
        if (node == nullptr)
            continue;
        auto *processor = node->getProcessor();
        if (processor == nullptr)
            continue;

        const double reportedTail = processor->getTailLengthSeconds();
        if (!std::isfinite(reportedTail) || reportedTail <= 0.0)
            continue;

        tailSeconds = juce::jmax(tailSeconds, reportedTail);
    }

    return juce::jlimit(0.0, 20.0, tailSeconds);
}

void prepareGraphForOfflineRender(juce::AudioProcessorGraph &graph,
                                  double sampleRate,
                                  int blockSize)
{
    graph.setNonRealtime(true);
    graph.setPlayConfigDetails(0, 2, sampleRate, blockSize);
    graph.releaseResources();
    graph.prepareToPlay(sampleRate, blockSize);
    graph.reset();
}

void applyTpdfDither(juce::AudioBuffer<float> &buffer, int bitDepth)
{
    if (bitDepth >= 32)
        return;

    const float lsb = 1.0f / (float)(1 << (bitDepth - 1));
    juce::Random rng(0x4d697852);
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

double evaluateAutomationValueAtMs(const std::vector<AutomationPoint> &points,
                                   double timeMs,
                                   double fallbackValue = 0.0)
{
    if (points.empty())
        return fallbackValue;

    if (timeMs <= points.front().timeMs)
        return points.front().value;
    if (timeMs >= points.back().timeMs)
        return points.back().value;

    int lo = 0;
    int hi = (int)points.size() - 1;
    while (hi - lo > 1)
    {
        const int mid = (lo + hi) / 2;
        if (timeMs < points[(size_t)mid].timeMs)
            hi = mid;
        else
            lo = mid;
    }

    const auto &a = points[(size_t)lo];
    const auto &b = points[(size_t)hi];
    const double spanMs = b.timeMs - a.timeMs;
    if (std::abs(spanMs) < 1.0e-9)
        return b.value;

    const double t = juce::jlimit(0.0, 1.0, (timeMs - a.timeMs) / spanMs);
    return juce::jmap(t, (double)a.value, (double)b.value);
}

void sanitiseAutomationPoints(std::vector<AutomationPoint> &points, float maxValue)
{
    for (auto &point : points)
    {
        point.timeMs = juce::jmax(0.0, point.timeMs);
        point.value = juce::jlimit(0.0f, maxValue, point.value);
    }

    std::sort(points.begin(),
              points.end(),
              [](const AutomationPoint &a, const AutomationPoint &b)
              { return a.timeMs < b.timeMs; });
}
} // namespace

void JuceEngine::reapplyClipProcessorStateLocked()
{
    for (auto &clip : clips)
    {
        if (!clip.alive || liveProcessorForClip(clip) == nullptr)
            continue;

        if (auto *processor = timelineProcessorForClip(clip))
        {
            processor->setTimeline(
                clip.startSec,
                clip.lengthSec,
                clip.inFileOffsetSec);
            processor->setStretchOptions(
                clip.tempoRatio,
                clip.preservePitch);
            processor->setPitchSemitones(clip.pitchSemitones);
            processor->setReversed(clip.reversed);
            processor->setMuted(clip.muted);
            processor->setGainUi(clip.gainUi);
            processor->setExtraGainLinear(clip.extraGainLinear);
            processor->setPanNormalized(clip.panNormalized);
        }
    }
}

void JuceEngine::rebuildClipProcessorsFromStoredStateLocked(
    juce::AudioProcessorGraph::UpdateKind updateKind)
{
    juce::ignoreUnused(updateKind);
    ensureBusGraphInitialised();

    auto applyClipProcessorState = [](ClipState &clip, TimelineClipProcessorBase &processor)
    {
        processor.setTimeline(
            clip.startSec,
            clip.lengthSec,
            clip.inFileOffsetSec);
        processor.setStretchOptions(
            clip.tempoRatio,
            clip.preservePitch);
        processor.setPitchSemitones(clip.pitchSemitones);
        processor.setReversed(clip.reversed);
        processor.setMuted(clip.muted);
        processor.setGainUi(clip.gainUi);
        processor.setExtraGainLinear(clip.extraGainLinear);
        processor.setPanNormalized(clip.panNormalized);
    };

    beginRoutedClipScheduleMutationLocked();
    for (size_t clipIndex = 0; clipIndex < clips.size(); ++clipIndex)
    {
        auto &clip = clips[clipIndex];
        if (!clip.alive)
            continue;

        std::unique_ptr<juce::AudioProcessor> rebuiltPlayer;

        if (clip.isMidi)
        {
            if (!TimelineMidiClipProcessor::canResolveSampledInstrument(
                    clip.midiInstrumentId,
                    clip.midiInstrumentName))
            {
                juceLogToFlutter(
                    "Skipping clip rebuild for export: unresolved MIDI instrument.");
                continue;
            }

            auto player = std::make_unique<TimelineMidiClipProcessor>(
                &blockTransportStartSec,
                &hostSampleRateAtomic,
                &blockIsPlayingAtomic);
            player->setMidiData(
                clip.midiNotes,
                clip.midiInstrumentId,
                clip.midiInstrumentName,
                clip.midiParams,
                clip.midiSourceTempoBpm);
            applyClipProcessorState(clip, *player);
            rebuiltPlayer = std::move(player);
        }
        else
        {
            if (clip.sourceFilePath.isEmpty())
            {
                juceLogToFlutter(
                    "Skipping clip rebuild for export: missing audio source path.");
                continue;
            }

            const juce::File sourceFile(clip.sourceFilePath);
            auto decodedAsset = getOrDecodeClipAudioAsset(sourceFile);
            if (decodedAsset == nullptr)
            {
                juceLogToFlutter(
                    "Skipping clip rebuild for export: could not decode audio source.");
                continue;
            }
            auto player = std::make_unique<TimelineClipProcessor>(
                decodedAsset,
                sourceFile,
                &blockTransportStartSec,
                &hostSampleRateAtomic,
                &blockIsPlayingAtomic);
            applyClipProcessorState(clip, *player);
            rebuiltPlayer = std::move(player);
        }

        if (rebuiltPlayer == nullptr)
            continue;

        removeClipFromRoutedSchedule(clip.rowId, (int)clipIndex);
        auto oldProcessor = std::atomic_exchange_explicit(
            &clip.playerProcessor,
            std::shared_ptr<juce::AudioProcessor>{},
            std::memory_order_acq_rel);
        retireLiveClipProcessorLocked(std::move(oldProcessor));
        if (clip.playerNode != nullptr)
        {
            graph.removeNode(clip.playerNode->nodeID, updateKind);
            clip.playerNode = nullptr;
        }
        auto sharedPlayer =
            std::shared_ptr<juce::AudioProcessor>(std::move(rebuiltPlayer));
        prepareLiveClipProcessor(*sharedPlayer);
        std::atomic_store_explicit(
            &clip.playerProcessor,
            std::move(sharedPlayer),
            std::memory_order_release);
        addClipToRoutedSchedule(clip);
        clip.wired = true;
        clip.lastRowInputNodeUid = 0;
    }
    endRoutedClipScheduleMutationLocked();

    drainRetiredLiveClipProcessorsLocked();
}

void JuceEngine::primeClipProcessorsForOfflineRenderLocked()
{
    for (auto &clip : clips)
    {
        if (!clip.alive || liveProcessorForClip(clip) == nullptr)
            continue;

        if (auto *processor = timelineProcessorForClip(clip))
            processor->primeForOfflineRender();
    }
}

juce::String JuceEngine::exportMix(const juce::File &outFile)
{
    return exportMix(outFile, ExportOptions{});
}

double JuceEngine::getExportProgress() const
{
    const auto value = exportProgressAtomic.load(std::memory_order_relaxed);
    return juce::jlimit(0.0, 1.0, value);
}

juce::String JuceEngine::exportMix(const juce::File &outFile, const ExportOptions &rawOptions)
{
    const auto options = sanitiseExportOptions(rawOptions);
    exportInProgressAtomic.store(true, std::memory_order_relaxed);
    exportProgressAtomic.store(0.0, std::memory_order_relaxed);

    struct ExportProgressGuard
    {
        explicit ExportProgressGuard(JuceEngine &engineRef) : engine(engineRef) {}
        ~ExportProgressGuard()
        {
            engine.exportInProgressAtomic.store(false, std::memory_order_relaxed);
            engine.flushDeferredAudioRouteRefreshAsync("exportMix:complete");
        }
        JuceEngine &engine;
    } exportProgressGuard(*this);

    const bool hadLiveCallback = (metronomeCallback != nullptr);
    struct LiveCallbackRestoreGuard
    {
        JuceEngine &engine;
        bool shouldRestore = false;

        ~LiveCallbackRestoreGuard()
        {
            if (shouldRestore && engine.metronomeCallback != nullptr)
                engine.deviceManager.addAudioCallback(engine.metronomeCallback.get());
        }
    } liveCallbackRestoreGuard{*this, hadLiveCallback};

    if (hadLiveCallback)
        deviceManager.removeAudioCallback(metronomeCallback.get());
    liveCallbackRestoreGuard.shouldRestore = hadLiveCallback;

    constexpr int offlineRenderBlockSize = 512;
    const double previousFxSeconds = mixroom::fx::getGlobalTransportSeconds();
    const bool previousFxPlaying = mixroom::fx::getGlobalTransportPlaying();
    const double previousTempoBpm = mixroom::fx::getGlobalTempoBpm();
    const auto copyAutomationLane = [](const auto &lane)
    {
        ExportEffectAutomationLane snapshotLane;
        snapshotLane.effectIndex = lane.effectIndex;
        snapshotLane.paramId = lane.paramId;
        snapshotLane.minValue = lane.minValue;
        snapshotLane.maxValue = lane.maxValue;
        snapshotLane.points = lane.points;
        snapshotLane.lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
        return snapshotLane;
    };

    ExportProjectSnapshot snapshot;
    std::vector<ExportClipSnapshot> exportClipSnapshotsFromDart;
    {
        GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

        snapshot.tempoBpm = mixroom::fx::getGlobalTempoBpm();
        snapshot.masterGainUi = masterGainUi;
        snapshot.masterPanUi = masterPanUi;
        snapshot.masterMuted = masterMuted;
        compactMasterFxChain();
        snapshot.masterGainAutomationPoints = masterGainAutomationPoints;
        snapshot.masterPanAutomationPoints = masterPanAutomationPoints;
        snapshot.masterEffectAutomationLanes.clear();
        snapshot.masterEffectAutomationLanes.reserve(masterEffectAutomationLanes.size());
        for (const auto &lane : masterEffectAutomationLanes)
            snapshot.masterEffectAutomationLanes.push_back(copyAutomationLane(lane));
        if (masterEffectChain != nullptr)
        {
            for (int i = 0; i < masterEffectChain->size(); ++i)
            {
                const auto nodeId = masterEffectChain->getReference(i);
                auto node = graph.getNodeForId(nodeId);
                if (node == nullptr)
                    continue;

                const auto pluginId =
                    (i >= 0 && i < masterEffectIds.size())
                        ? masterEffectIds[i]
                        : (node->getProcessor() != nullptr ? node->getProcessor()->getName() : juce::String{});
                snapshot.masterEffects.push_back(captureEffectSnapshot(pluginId, node));
            }
        }

        snapshot.rows.reserve(rows.size());
        for (int rowIndex = 0; rowIndex < (int)rows.size(); ++rowIndex)
        {
            compactRowFxChain(rowIndex);
            const auto &rowState = rows[(size_t)rowIndex];

            ExportRowSnapshot rowSnapshot;
            rowSnapshot.rowId = rowState.rowId;
            rowSnapshot.gainUi = rowState.gainUi;
            rowSnapshot.panUi = rowState.panUi;
            rowSnapshot.muted = rowState.muted;
            rowSnapshot.automationPoints = rowState.automationPoints;
            rowSnapshot.gainAutomationPoints = rowState.gainAutomationPoints;
            rowSnapshot.panAutomationPoints = rowState.panAutomationPoints;
            rowSnapshot.effectAutomationLanes.clear();
            rowSnapshot.effectAutomationLanes.reserve(rowState.effectAutomationLanes.size());
            for (const auto &lane : rowState.effectAutomationLanes)
                rowSnapshot.effectAutomationLanes.push_back(copyAutomationLane(lane));

            for (int fxIndex = 0; fxIndex < rowState.fxChain.size(); ++fxIndex)
            {
                const auto nodeId = rowState.fxChain.getReference(fxIndex);
                auto node = graph.getNodeForId(nodeId);
                if (node == nullptr)
                    continue;

                const auto pluginId =
                    (fxIndex >= 0 && fxIndex < rowState.fxIds.size())
                        ? rowState.fxIds[fxIndex]
                        : (node->getProcessor() != nullptr ? node->getProcessor()->getName() : juce::String{});
                rowSnapshot.effects.push_back(captureEffectSnapshot(pluginId, node));
            }

            snapshot.rows.push_back(std::move(rowSnapshot));
        }

        snapshot.groups.reserve(trackGroups.size());
        for (auto &groupState : trackGroups)
        {
            compactTrackGroupFxChain(groupState);

            ExportGroupSnapshot groupSnapshot;
            groupSnapshot.id = groupState.id;
            groupSnapshot.rowIds = groupState.rowIds;
            groupSnapshot.gainUi = groupState.gainUi;
            groupSnapshot.panUi = groupState.panUi;
            groupSnapshot.muted = groupState.muted;

            for (int fxIndex = 0; fxIndex < groupState.fxChain.size(); ++fxIndex)
            {
                const auto nodeId = groupState.fxChain.getReference(fxIndex);
                auto node = graph.getNodeForId(nodeId);
                if (node == nullptr)
                    continue;

                const auto pluginId =
                    (fxIndex >= 0 && fxIndex < groupState.fxIds.size())
                        ? groupState.fxIds[fxIndex]
                        : (node->getProcessor() != nullptr ? node->getProcessor()->getName() : juce::String{});
                groupSnapshot.effects.push_back(captureEffectSnapshot(pluginId, node));
            }

            snapshot.groups.push_back(std::move(groupSnapshot));
        }

        snapshot.clips.reserve(clips.size());
        for (const auto &clip : clips)
        {
            if (!clip.alive)
                continue;

            ExportClipSnapshot clipSnapshot;
            clipSnapshot.alive = clip.alive;
            clipSnapshot.isMidi = clip.isMidi;
            clipSnapshot.muted = clip.muted;
            clipSnapshot.clipId = clip.clipId;
            clipSnapshot.rowId = clip.rowId;
            clipSnapshot.startSec = clip.startSec;
            clipSnapshot.lengthSec = clip.lengthSec;
            clipSnapshot.inFileOffsetSec = clip.inFileOffsetSec;
            clipSnapshot.pitchSemitones = clip.pitchSemitones;
            clipSnapshot.reversed = clip.reversed;
            clipSnapshot.tempoRatio = clip.tempoRatio;
            clipSnapshot.preservePitch = clip.preservePitch;
            clipSnapshot.gainUi = clip.gainUi;
            clipSnapshot.extraGainLinear = clip.extraGainLinear;
            clipSnapshot.panNormalized = clip.panNormalized;
            clipSnapshot.fadeInSec = clip.fadeInSec;
            clipSnapshot.fadeOutSec = clip.fadeOutSec;
            clipSnapshot.fadeCurve = clip.fadeCurve;
            clipSnapshot.sourceFilePath = clip.sourceFilePath;
            clipSnapshot.midiInstrumentId = clip.midiInstrumentId;
            clipSnapshot.midiInstrumentName = clip.midiInstrumentName;
            clipSnapshot.midiNotes = clip.midiNotes;
            clipSnapshot.midiParams = clip.midiParams;
            clipSnapshot.midiSourceTempoBpm = clip.midiSourceTempoBpm;
            snapshot.clips.push_back(std::move(clipSnapshot));
        }
    }

    juce::String clipSnapshotError;
    if (!parseExportClipSnapshotJson(
            options.clipSnapshotJson,
            exportClipSnapshotsFromDart,
            clipSnapshotError))
    {
        if (clipSnapshotError.isNotEmpty())
            juceLogToFlutter(clipSnapshotError.toRawUTF8());
        return {};
    }
    if (!mergeExportClipSnapshotsIntoProject(
            snapshot.clips,
            std::move(exportClipSnapshotsFromDart),
            clipSnapshotError))
    {
        if (clipSnapshotError.isNotEmpty())
            juceLogToFlutter(clipSnapshotError.toRawUTF8());
        return {};
    }

    if (options.dryClipRender)
        applyDryClipRenderOptions(snapshot);

    mixroom::fx::setGlobalTempoBpm(snapshot.tempoBpm);
    const auto result = renderOfflineSnapshotToFile(
        snapshot,
        outFile,
        options,
        offlineRenderBlockSize,
        getSnapshotEndTimeSeconds(snapshot),
        formatManager,
        pluginFormatManager,
        pluginList,
        [this](double progress)
        {
            exportProgressAtomic.store(
                juce::jlimit(0.0, 1.0, progress),
                std::memory_order_relaxed);
        });

    mixroom::fx::setGlobalTempoBpm(previousTempoBpm);
    mixroom::fx::setGlobalTransportSeconds(previousFxSeconds);
    mixroom::fx::setGlobalTransportPlaying(previousFxPlaying);
    exportProgressAtomic.store(
        result.isNotEmpty() ? 1.0 : 0.0,
        std::memory_order_relaxed);
    return result;
}

// (Your exportTrack implementation – unchanged)
juce::String JuceEngine::exportTrack(int trackIndex, const juce::File &outFile)
{
    return exportTrack(trackIndex, outFile, ExportOptions{});
}

juce::String JuceEngine::exportTrack(int trackIndex,
                                     const juce::File &outFile,
                                     const ExportOptions &rawOptions)
{
    const auto options = sanitiseExportOptions(rawOptions);
    exportInProgressAtomic.store(true, std::memory_order_relaxed);
    exportProgressAtomic.store(0.0, std::memory_order_relaxed);

    struct ExportProgressGuard
    {
        explicit ExportProgressGuard(JuceEngine &engineRef) : engine(engineRef) {}
        ~ExportProgressGuard()
        {
            engine.exportInProgressAtomic.store(false, std::memory_order_relaxed);
            engine.flushDeferredAudioRouteRefreshAsync("exportTrack:complete");
        }
        JuceEngine &engine;
    } exportProgressGuard(*this);

    const bool hadLiveCallback = (metronomeCallback != nullptr);
    struct LiveCallbackRestoreGuard
    {
        JuceEngine &engine;
        bool shouldRestore = false;

        ~LiveCallbackRestoreGuard()
        {
            if (shouldRestore && engine.metronomeCallback != nullptr)
                engine.deviceManager.addAudioCallback(engine.metronomeCallback.get());
        }
    } liveCallbackRestoreGuard{*this, hadLiveCallback};

    if (hadLiveCallback)
        deviceManager.removeAudioCallback(metronomeCallback.get());
    liveCallbackRestoreGuard.shouldRestore = hadLiveCallback;

    constexpr int offlineRenderBlockSize = 512;
    const double previousFxSeconds = mixroom::fx::getGlobalTransportSeconds();
    const bool previousFxPlaying = mixroom::fx::getGlobalTransportPlaying();
    const double previousTempoBpm = mixroom::fx::getGlobalTempoBpm();
    const auto copyAutomationLane = [](const auto &lane)
    {
        ExportEffectAutomationLane snapshotLane;
        snapshotLane.effectIndex = lane.effectIndex;
        snapshotLane.paramId = lane.paramId;
        snapshotLane.minValue = lane.minValue;
        snapshotLane.maxValue = lane.maxValue;
        snapshotLane.points = lane.points;
        snapshotLane.lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
        return snapshotLane;
    };

    ExportProjectSnapshot snapshot;
    double targetLengthSeconds = 0.0;
    bool foundTargetClip = false;
    {
        GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

        snapshot.tempoBpm = mixroom::fx::getGlobalTempoBpm();
        snapshot.masterGainUi = masterGainUi;
        snapshot.masterPanUi = masterPanUi;
        snapshot.masterMuted = masterMuted;
        compactMasterFxChain();
        snapshot.masterGainAutomationPoints = masterGainAutomationPoints;
        snapshot.masterPanAutomationPoints = masterPanAutomationPoints;
        snapshot.masterEffectAutomationLanes.clear();
        snapshot.masterEffectAutomationLanes.reserve(masterEffectAutomationLanes.size());
        for (const auto &lane : masterEffectAutomationLanes)
            snapshot.masterEffectAutomationLanes.push_back(copyAutomationLane(lane));
        if (masterEffectChain != nullptr)
        {
            for (int i = 0; i < masterEffectChain->size(); ++i)
            {
                const auto nodeId = masterEffectChain->getReference(i);
                auto node = graph.getNodeForId(nodeId);
                if (node == nullptr)
                    continue;

                const auto pluginId =
                    (i >= 0 && i < masterEffectIds.size())
                        ? masterEffectIds[i]
                        : (node->getProcessor() != nullptr ? node->getProcessor()->getName() : juce::String{});
                snapshot.masterEffects.push_back(captureEffectSnapshot(pluginId, node));
            }
        }

        snapshot.rows.reserve(rows.size());
        for (int rowIndex = 0; rowIndex < (int)rows.size(); ++rowIndex)
        {
            compactRowFxChain(rowIndex);
            const auto &rowState = rows[(size_t)rowIndex];

            ExportRowSnapshot rowSnapshot;
            rowSnapshot.rowId = rowState.rowId;
            rowSnapshot.gainUi = rowState.gainUi;
            rowSnapshot.panUi = rowState.panUi;
            rowSnapshot.muted = rowState.muted;
            rowSnapshot.automationPoints = rowState.automationPoints;
            rowSnapshot.gainAutomationPoints = rowState.gainAutomationPoints;
            rowSnapshot.panAutomationPoints = rowState.panAutomationPoints;
            rowSnapshot.effectAutomationLanes.clear();
            rowSnapshot.effectAutomationLanes.reserve(rowState.effectAutomationLanes.size());
            for (const auto &lane : rowState.effectAutomationLanes)
                rowSnapshot.effectAutomationLanes.push_back(copyAutomationLane(lane));

            for (int fxIndex = 0; fxIndex < rowState.fxChain.size(); ++fxIndex)
            {
                const auto nodeId = rowState.fxChain.getReference(fxIndex);
                auto node = graph.getNodeForId(nodeId);
                if (node == nullptr)
                    continue;

                const auto pluginId =
                    (fxIndex >= 0 && fxIndex < rowState.fxIds.size())
                        ? rowState.fxIds[fxIndex]
                        : (node->getProcessor() != nullptr ? node->getProcessor()->getName() : juce::String{});
                rowSnapshot.effects.push_back(captureEffectSnapshot(pluginId, node));
            }

            snapshot.rows.push_back(std::move(rowSnapshot));
        }

        snapshot.groups.reserve(trackGroups.size());
        for (auto &groupState : trackGroups)
        {
            compactTrackGroupFxChain(groupState);

            ExportGroupSnapshot groupSnapshot;
            groupSnapshot.id = groupState.id;
            groupSnapshot.rowIds = groupState.rowIds;
            groupSnapshot.gainUi = groupState.gainUi;
            groupSnapshot.panUi = groupState.panUi;
            groupSnapshot.muted = groupState.muted;

            for (int fxIndex = 0; fxIndex < groupState.fxChain.size(); ++fxIndex)
            {
                const auto nodeId = groupState.fxChain.getReference(fxIndex);
                auto node = graph.getNodeForId(nodeId);
                if (node == nullptr)
                    continue;

                const auto pluginId =
                    (fxIndex >= 0 && fxIndex < groupState.fxIds.size())
                        ? groupState.fxIds[fxIndex]
                        : (node->getProcessor() != nullptr ? node->getProcessor()->getName() : juce::String{});
                groupSnapshot.effects.push_back(captureEffectSnapshot(pluginId, node));
            }

            snapshot.groups.push_back(std::move(groupSnapshot));
        }

        snapshot.clips.reserve(clips.size());
        for (const auto &clip : clips)
        {
            if (!clip.alive)
                continue;

            ExportClipSnapshot clipSnapshot;
            clipSnapshot.alive = clip.alive;
            clipSnapshot.isMidi = clip.isMidi;
            clipSnapshot.muted = (clip.clipId == trackIndex) ? clip.muted : true;
            clipSnapshot.clipId = clip.clipId;
            clipSnapshot.rowId = clip.rowId;
            clipSnapshot.startSec = (clip.clipId == trackIndex) ? 0.0 : clip.startSec;
            clipSnapshot.lengthSec = clip.lengthSec;
            clipSnapshot.inFileOffsetSec = clip.inFileOffsetSec;
            clipSnapshot.pitchSemitones = clip.pitchSemitones;
            clipSnapshot.reversed = clip.reversed;
            clipSnapshot.tempoRatio = clip.tempoRatio;
            clipSnapshot.preservePitch = clip.preservePitch;
            clipSnapshot.gainUi = clip.gainUi;
            clipSnapshot.extraGainLinear = clip.extraGainLinear;
            clipSnapshot.panNormalized = clip.panNormalized;
            clipSnapshot.fadeInSec = clip.fadeInSec;
            clipSnapshot.fadeOutSec = clip.fadeOutSec;
            clipSnapshot.fadeCurve = clip.fadeCurve;
            clipSnapshot.sourceFilePath = clip.sourceFilePath;
            clipSnapshot.midiInstrumentId = clip.midiInstrumentId;
            clipSnapshot.midiInstrumentName = clip.midiInstrumentName;
            clipSnapshot.midiNotes = clip.midiNotes;
            clipSnapshot.midiParams = clip.midiParams;
            clipSnapshot.midiSourceTempoBpm = clip.midiSourceTempoBpm;

            if (clip.clipId == trackIndex)
            {
                targetLengthSeconds = clip.lengthSec;
                foundTargetClip = true;
            }

            snapshot.clips.push_back(std::move(clipSnapshot));
        }
    }

    if (!foundTargetClip)
        return {};

    mixroom::fx::setGlobalTempoBpm(snapshot.tempoBpm);
    const auto result = renderOfflineSnapshotToFile(
        snapshot,
        outFile,
        options,
        offlineRenderBlockSize,
        targetLengthSeconds,
        formatManager,
        pluginFormatManager,
        pluginList,
        [this](double progress)
        {
            exportProgressAtomic.store(
                juce::jlimit(0.0, 1.0, progress),
                std::memory_order_relaxed);
        });

    mixroom::fx::setGlobalTempoBpm(previousTempoBpm);
    mixroom::fx::setGlobalTransportSeconds(previousFxSeconds);
    mixroom::fx::setGlobalTransportPlaying(previousFxPlaying);
    exportProgressAtomic.store(
        result.isNotEmpty() ? 1.0 : 0.0,
        std::memory_order_relaxed);
    return result;
}

// ============================================================
// Transport
// ============================================================
void JuceEngine::play()
{
    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
        ensureMasterOutputRouting();
    }

    auto *dev = deviceManager.getCurrentAudioDevice();
    const bool missingOutputRoute =
        (dev == nullptr) || (dev->getActiveOutputChannels().countNumberOfSetBits() <= 0);
    if (missingOutputRoute)
    {
        if (applyPreferredAudioDeviceSetup(0, true, "play-recover-output"))
            logCurrentAudioDeviceState("play:recovered-output-route");
        else
        {
            juceLogToFlutter("play: output route still invalid after recover attempt");
            requestAudioDeviceRefreshAsync("play-recover-output");
        }
    }

    isPlayingAtomic.store(true, std::memory_order_relaxed);
    mixroom::fx::setGlobalTransportPlaying(true);

    if (metronomeCallback)
        metronomeCallback->setIsPlaying(true);
}

bool JuceEngine::playPlaybackV2Android()
{
#if JUCE_ANDROID
    auto *device = deviceManager.getCurrentAudioDevice();
    const int activeInputChannels =
        device != nullptr ? device->getActiveInputChannels().countNumberOfSetBits() : 0;
    const bool verifiedRecordingInputActive =
        wavCapture.isActive() &&
        androidV2RecordingPrepared &&
        desiredInputOpenChannels.load(std::memory_order_relaxed) > 0 &&
        activeInputChannels == desiredInputOpenChannels.load(std::memory_order_relaxed);
    if (!engineInitialized || !audioCallbackAttached ||
        metronomeCallback == nullptr || device == nullptr || !device->isOpen() ||
        device->getActiveOutputChannels().countNumberOfSetBits() <= 0 ||
        (activeInputChannels != 0 && !verifiedRecordingInputActive))
        return false;

    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
        ensureMasterOutputRouting();
    }

    isPlayingAtomic.store(true, std::memory_order_relaxed);
    mixroom::fx::setGlobalTransportPlaying(true);
    metronomeCallback->setIsPlaying(true);
    return true;
#else
    return false;
#endif
}

void JuceEngine::pause()
{
    isPlayingAtomic.store(false, std::memory_order_relaxed);
    mixroom::fx::setGlobalTransportPlaying(false);
    requestLiveMidiPanicForAll(LiveMidiPanicMode::full);

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
    mixroom::fx::setGlobalTransportSeconds(clamped);

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
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (clips.empty() || trackIndex < 0 || trackIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)trackIndex];
    if (!c.alive || liveProcessorForClip(c) == nullptr)
        return;

    c.muted = shouldBypass;
    if (auto *p = timelineProcessorForClip(c))
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
void JuceEngine::scanPluginsIfNeeded()
{
    if (pluginsScanned)
        return;

    pluginsScanned = true;

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

juce::Array<juce::PluginDescription> JuceEngine::getKnownPlugins()
{
    juceLogToFlutter("JuceEngine::getKnownPlugins()");
    scanPluginsIfNeeded();

    auto types = pluginList.getTypes();
    juceLogToFlutter((" found " + juce::String(types.size()) + " plugins").toRawUTF8());
    for (auto &pd : types)
        juceLogToFlutter(("     " + pd.name).toRawUTF8());

    return types;
}

juce::NamedValueSet JuceEngine::getEngineDiagnostics()
{
    juce::NamedValueSet out;
    auto *device = deviceManager.getCurrentAudioDevice();
    const auto sampleRate =
        getKnownDeviceSampleRate(deviceManager, hostSampleRateAtomic.load(std::memory_order_relaxed));
    const auto bufferSize = getKnownDeviceBufferSize(deviceManager, 512);

    out.set("sampleRate", sampleRate);
    out.set("bufferSize", bufferSize);
    out.set("cpuUsage", deviceManager.getCpuUsage());
    out.set("pluginsScanned", pluginsScanned);
    out.set("knownPluginCount", pluginList.getTypes().size());
    out.set("pluginScanFailureCount", 0);
    out.set("pluginScanFailures", juce::var(juce::Array<juce::var>()));
    out.set("rowCount", (int)rows.size());
    out.set("clipCount", (int)clips.size());
    out.set("deviceOpen", device != nullptr && device->isOpen());
    out.set("audioCallbackAttached", audioCallbackAttached);
    out.set("inputDeviceName", getCurrentInputDeviceName());
    out.set("outputDeviceName", getCurrentOutputDeviceName());
    out.set("inputChannelCount",
            device != nullptr ? device->getActiveInputChannels().countNumberOfSetBits() : 0);
    out.set("outputChannelCount",
            device != nullptr ? device->getActiveOutputChannels().countNumberOfSetBits() : 0);

    const auto ticksPerSecond = realtimeTicksPerSecond.load(std::memory_order_relaxed);
    const auto callbackCount = realtimeCallbackCount.load(std::memory_order_relaxed);
    const auto totalTicks = realtimeCallbackTotalTicks.load(std::memory_order_relaxed);
    const auto lastTicks = realtimeCallbackLastTicks.load(std::memory_order_relaxed);
    const auto maxTicks = realtimeCallbackMaxTicks.load(std::memory_order_relaxed);
    const auto overBudgetCount = realtimeCallbackOverBudgetCount.load(std::memory_order_relaxed);
    const auto maxSamples = realtimeCallbackMaxSamples.load(std::memory_order_relaxed);
    const auto immediateRebuilds = graphRebuildImmediateCount.load(std::memory_order_relaxed);
    const auto deferredRebuilds = graphRebuildDeferredCount.load(std::memory_order_relaxed);
    const auto batchRebuilds = graphRebuildBatchCommitCount.load(std::memory_order_relaxed);
    const auto projectLoadRebuilds = graphRebuildProjectLoadCommitCount.load(std::memory_order_relaxed);
    const auto committedRebuilds =
        immediateRebuilds + batchRebuilds + projectLoadRebuilds;

    out.set("realtimeCallbackCount", juce::var((juce::int64)callbackCount));
    out.set("realtimeCallbackLastMs", ticksToMilliseconds(lastTicks, ticksPerSecond));
    out.set("realtimeCallbackMaxMs", ticksToMilliseconds(maxTicks, ticksPerSecond));
    out.set("realtimeCallbackAvgMs",
            callbackCount > 0
                ? ticksToMilliseconds((std::int64_t)(totalTicks / callbackCount), ticksPerSecond)
                : 0.0);
    out.set("realtimeCallbackOverBudgetCount", juce::var((juce::int64)overBudgetCount));
    out.set("realtimeCallbackMaxSamples", maxSamples);
    out.set("realtimeGraphRebuildCommittedCount", juce::var((juce::int64)committedRebuilds));
    out.set("realtimeGraphRebuildImmediateCount", juce::var((juce::int64)immediateRebuilds));
    out.set("realtimeGraphRebuildDeferredCount", juce::var((juce::int64)deferredRebuilds));
    out.set("realtimeGraphRebuildBatchCommitCount", juce::var((juce::int64)batchRebuilds));
    out.set("realtimeGraphRebuildProjectLoadCommitCount", juce::var((juce::int64)projectLoadRebuilds));
    out.set("realtimeCallbackBudgetMs",
            sampleRate > 0.0 && bufferSize > 0
                ? (1000.0 * (double)bufferSize) / sampleRate
                : 0.0);

    return out;
}

juce::NamedValueSet JuceEngine::runTimelineRendererStressTest(int clipCount,
                                                              int blockCount,
                                                              int blockSize,
                                                              double sampleRate)
{
    juce::NamedValueSet out;

    clipCount = juce::jlimit(1, 1024, clipCount);
    blockCount = juce::jlimit(1, 20000, blockCount);
    blockSize = juce::jlimit(64, kMixroomRealtimeScratchMaxSamples, blockSize);
    sampleRate = juce::jlimit(8000.0, 192000.0, sampleRate);

    const double renderSeconds = ((double)blockCount * (double)blockSize) / sampleRate;
    const double assetSeconds = juce::jlimit(2.0, 30.0, renderSeconds + 1.0);
    const int assetSamples = juce::jmax(blockSize, (int)std::ceil(assetSeconds * sampleRate));

    auto decodedAsset = std::make_shared<DecodedClipAudioAsset>();
    decodedAsset->sampleRate = sampleRate;
    decodedAsset->audio.setSize(2, assetSamples, false, false, true);

    constexpr double twoPi = 6.283185307179586476925286766559;
    for (int ch = 0; ch < 2; ++ch)
    {
        float *samples = decodedAsset->audio.getWritePointer(ch);
        const double panOffset = ch == 0 ? 0.0 : 0.37;
        for (int i = 0; i < assetSamples; ++i)
        {
            const double t = (double)i / sampleRate;
            samples[i] =
                (float)(0.18 * std::sin(twoPi * (110.0 + panOffset) * t) +
                        0.08 * std::sin(twoPi * (220.5 + panOffset) * t) +
                        0.03 * std::sin(twoPi * (441.0 + panOffset) * t));
        }
    }

    std::atomic<double> stressTransport{0.0};
    std::atomic<double> stressSampleRate{sampleRate};
    std::atomic<bool> stressPlaying{true};

    std::vector<std::unique_ptr<TimelineClipProcessor>> processors;
    processors.reserve((size_t)clipCount);
    std::vector<int> rowAssignments;
    rowAssignments.reserve((size_t)clipCount);

    const int rowCount = juce::jlimit(1, 32, juce::jmax(1, clipCount / 16));
    const int pitchClipCount = clipCount >= 32 ? juce::jmax(1, clipCount / 32) : 0;
    const double clipLengthSec = renderSeconds + 0.75;

    for (int i = 0; i < clipCount; ++i)
    {
        auto processor = std::make_unique<TimelineClipProcessor>(
            decodedAsset,
            juce::File(),
            &stressTransport,
            &stressSampleRate,
            &stressPlaying);

        const double startSec = -0.25 + (double)(i % 8) * 0.01;
        const double offsetSec = (double)(i % 17) * 0.005;
        processor->setTimeline(startSec, clipLengthSec, offsetSec);
        processor->setPanNormalized(((float)(i % 9) - 4.0f) / 8.0f);
        processor->setGainUi(SimpleGainProcessor::kUiUnity);
        if (pitchClipCount > 0 && i < pitchClipCount)
            processor->setPitchSemitones((i % 2 == 0) ? -1.0f : 1.0f);
        if ((i % 23) == 0)
            processor->setFades(0.005, 0.005, 0);
        processor->prepareToPlay(sampleRate, blockSize);

        rowAssignments.push_back(i % rowCount);
        processors.push_back(std::move(processor));
    }

    std::vector<std::unique_ptr<juce::AudioBuffer<float>>> rowBuffers;
    rowBuffers.reserve((size_t)rowCount);
    for (int row = 0; row < rowCount; ++row)
        rowBuffers.push_back(std::make_unique<juce::AudioBuffer<float>>(2, blockSize));

    juce::AudioBuffer<float> clipScratch(2, blockSize);
    juce::AudioBuffer<float> masterBuffer(2, blockSize);
    juce::MidiBuffer midi;

    const auto ticksPerSecond =
        (std::int64_t)juce::Time::getHighResolutionTicksPerSecond();
    const double budgetMs = (1000.0 * (double)blockSize) / sampleRate;
    std::int64_t totalBlockTicks = 0;
    std::int64_t maxBlockTicks = 0;
    std::int64_t totalEditTicks = 0;
    std::int64_t maxEditTicks = 0;
    int overBudgetBlocks = 0;
    int editCount = 0;
    double checksum = 0.0;

    for (int block = 0; block < blockCount; ++block)
    {
        if ((block % 64) == 0)
        {
            const auto editStartTicks = juce::Time::getHighResolutionTicks();
            const int clipIndex = (block / 64) % clipCount;
            const double startSec = -0.25 + (double)((block / 64) % 8) * 0.01;
            processors[(size_t)clipIndex]->setTimeline(
                startSec,
                clipLengthSec,
                (double)(clipIndex % 17) * 0.005);
            processors[(size_t)clipIndex]->setPanNormalized(
                ((float)((clipIndex + block) % 9) - 4.0f) / 8.0f);
            const auto elapsedEditTicks =
                (std::int64_t)(juce::Time::getHighResolutionTicks() - editStartTicks);
            totalEditTicks += elapsedEditTicks;
            maxEditTicks = juce::jmax(maxEditTicks, elapsedEditTicks);
            ++editCount;
        }

        stressTransport.store(((double)block * (double)blockSize) / sampleRate,
                              std::memory_order_relaxed);

        const auto blockStartTicks = juce::Time::getHighResolutionTicks();
        for (auto &rowBuffer : rowBuffers)
            rowBuffer->clear();

        for (int i = 0; i < clipCount; ++i)
        {
            clipScratch.clear();
            midi.clear();
            processors[(size_t)i]->processBlock(clipScratch, midi);
            auto &rowBuffer = *rowBuffers[(size_t)rowAssignments[(size_t)i]];
            for (int ch = 0; ch < 2; ++ch)
                rowBuffer.addFrom(ch, 0, clipScratch, ch, 0, blockSize);
        }

        masterBuffer.clear();
        for (auto &rowBuffer : rowBuffers)
        {
            for (int ch = 0; ch < 2; ++ch)
                masterBuffer.addFrom(ch, 0, *rowBuffer, ch, 0, blockSize);
        }

        checksum += (double)masterBuffer.getSample(0, block % blockSize);
        checksum += (double)masterBuffer.getSample(1, (block * 7) % blockSize);

        const auto elapsedBlockTicks =
            (std::int64_t)(juce::Time::getHighResolutionTicks() - blockStartTicks);
        totalBlockTicks += elapsedBlockTicks;
        maxBlockTicks = juce::jmax(maxBlockTicks, elapsedBlockTicks);
        if (ticksToMilliseconds(elapsedBlockTicks, ticksPerSecond) > budgetMs)
            ++overBudgetBlocks;
    }

    const double totalBlockMs = ticksToMilliseconds(totalBlockTicks, ticksPerSecond);
    const double avgBlockMs =
        blockCount > 0 ? ticksToMilliseconds(totalBlockTicks / blockCount, ticksPerSecond) : 0.0;
    const double maxBlockMs = ticksToMilliseconds(maxBlockTicks, ticksPerSecond);
    const double avgEditMs =
        editCount > 0 ? ticksToMilliseconds(totalEditTicks / editCount, ticksPerSecond) : 0.0;
    const double maxEditMs = ticksToMilliseconds(maxEditTicks, ticksPerSecond);

    out.set("stressClipCount", clipCount);
    out.set("stressRowCount", rowCount);
    out.set("stressPitchClipCount", pitchClipCount);
    out.set("stressBlockCount", blockCount);
    out.set("stressBlockSize", blockSize);
    out.set("stressSampleRate", sampleRate);
    out.set("stressRenderedSeconds", renderSeconds);
    out.set("stressTotalBlockMs", totalBlockMs);
    out.set("stressAvgBlockMs", avgBlockMs);
    out.set("stressMaxBlockMs", maxBlockMs);
    out.set("stressCallbackBudgetMs", budgetMs);
    out.set("stressOverBudgetBlocks", overBudgetBlocks);
    out.set("stressEditCount", editCount);
    out.set("stressAvgEditMs", avgEditMs);
    out.set("stressMaxEditMs", maxEditMs);
    out.set("stressChecksum", checksum);
    out.set("stressRealtimeSafe", overBudgetBlocks == 0 && maxBlockMs <= budgetMs);

    return out;
}

// ============================================================
// Video audio lane (kept as you had; minor safety only)
// ============================================================
void JuceEngine::loadVideoAudio(const juce::File &file)
{
    auto decodedAsset = prepareClipAudioAsset(file);
    if (!loadVideoAudioWithPreparedAudioAsset(file, std::move(decodedAsset)))
        juceLogToFlutter("loadVideoAudio failed");
}

bool JuceEngine::loadVideoAudioWithPreparedAudioAsset(
    const juce::File &file,
    std::shared_ptr<DecodedClipAudioAsset> decodedAsset)
{
    if (decodedAsset == nullptr || decodedAsset->audio.getNumSamples() <= 0)
    {
        juceLogToFlutter("loadVideoAudio: decoded asset null");
        return false;
    }

    constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    try
    {
        juceLogToFlutter("loadVideoAudio()");

        if (hasVideoAudio)
        {
            juce::Array<AudioProcessorGraph::Connection> toRemove;
            for (auto &c : graph.getConnections())
            {
                if (videoAudioNode && (c.source.nodeID == videoAudioNode->nodeID ||
                                       c.destination.nodeID == videoAudioNode->nodeID))
                    toRemove.add(c);
            }
            for (auto &c : toRemove)
                graph.removeConnection(c, batchUpdate);

            if (videoGainProc)
            {
                for (auto *n : graph.getNodes())
                {
                    if (n && n->getProcessor() == videoGainProc)
                    {
                        graph.removeNode(n->nodeID, batchUpdate);
                        break;
                    }
                }
            }

            if (videoAudioNode)
                graph.removeNode(videoAudioNode->nodeID, batchUpdate);

            videoAudioNode = nullptr;
            videoGainProc = nullptr;
            hasVideoAudio = false;
        }

        auto player = std::make_unique<FilePlayerProcessor>(std::move(decodedAsset), file);
        auto node = graph.addNode(std::move(player), std::nullopt, batchUpdate);
        if (node == nullptr)
        {
            juceLogToFlutter("loadVideoAudio: graph add node failed");
            return false;
        }
        videoAudioNode = node;

        // Gain node for video
        auto gainProc = std::make_unique<SimpleGainProcessor>();
        videoGainProc = gainProc.get();
        auto gainNode = graph.addNode(std::move(gainProc), std::nullopt, batchUpdate);

        if (videoGainProc)
        {
            // videoGainProc->prepareToPlay(...) is handled by graph.prepareToPlay().
            videoGainProc->gain->setValueNotifyingHost(kGainUiUnity / kGainUiMax);
        }

        int numOutputChannels = node->getProcessor()->getTotalNumOutputChannels();

        if (gainNode != nullptr && outputNode != nullptr)
        {
            for (int ch = 0; ch < jmin(2, numOutputChannels); ++ch)
            {
                graph.addConnection({{videoAudioNode->nodeID, ch}, {gainNode->nodeID, ch}}, batchUpdate);
                graph.addConnection({{gainNode->nodeID, ch}, {outputNode->nodeID, ch}}, batchUpdate);
            }
        }

        videoAudioNode->setBypassed(true);
        hasVideoAudio = true;
        commitGraphMutationLocked(true);
        juceLogToFlutter("loadVideoAudio done");
        return true;
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

    return false;
}

void JuceEngine::unloadVideoAudio()
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

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
        graph.removeConnection(c, juce::AudioProcessorGraph::UpdateKind::none);

    if (videoGainProc)
    {
        for (auto *n : graph.getNodes())
        {
            if (n && n->getProcessor() == videoGainProc)
            {
                graph.removeNode(n->nodeID, juce::AudioProcessorGraph::UpdateKind::none);
                break;
            }
        }
    }

    if (videoAudioNode)
        graph.removeNode(videoAudioNode->nodeID, juce::AudioProcessorGraph::UpdateKind::none);

    videoAudioNode = nullptr;
    videoGainProc = nullptr;
    hasVideoAudio = false;
    commitGraphMutationLocked(true);
}

void JuceEngine::setVideoAudioGain(float gain)
{
    if (videoGainProc)
        videoGainProc->gain->setValueNotifyingHost(
            juce::jlimit(kGainUiMin, kGainUiMax, gain) / kGainUiMax);
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
void JuceEngine::rewireTrackBusFxChain(
    int row,
    juce::AudioProcessorGraph::UpdateKind updateKind)
{
    if (!busGraphInitialised)
        return;

    if (row < 0 || row >= (int)rows.size())
        return;

    compactRowFxChain(row);

    auto *inputNode = rows[(size_t)row].inputNode.get();
    auto *automationNode = rows[(size_t)row].automationNode.get();
    auto &chain = rows[(size_t)row].fxChain;

    if (!inputNode || !automationNode)
        return;

    const auto inputNodeId = inputNode->nodeID;
    const auto automationNodeId = automationNode->nodeID;
    juce::Array<AudioProcessorGraph::NodeID> localNodes;
    localNodes.add(inputNodeId);
    localNodes.add(automationNodeId);
    for (auto nodeID : chain)
        localNodes.addIfNotAlreadyThere(nodeID);
    clearStereoConnectionsBetweenNodes(graph, localNodes, updateKind);

    auto prevNodeId = inputNodeId;

    for (int i = 0; i < chain.size(); ++i)
    {
        auto nodeID = chain.getReference(i);
        if (graph.getNodeForId(nodeID) != nullptr)
        {
            connectStereo(graph, prevNodeId, nodeID, updateKind);
            prevNodeId = nodeID;
        }
    }

    connectStereo(graph, prevNodeId, automationNodeId, updateKind);

    if (!isProjectClipLoadTransactionActive() &&
        graphMutationBatchDepth <= 0)
        armOutputSafetyForCurrentRoute();
}

void JuceEngine::compactTrackGroupFxChain(TrackGroupState &group)
{
    juce::Array<AudioProcessorGraph::NodeID> compactedChain;
    juce::StringArray compactedIds;
    compactedChain.ensureStorageAllocated(group.fxChain.size());
    compactedIds.ensureStorageAllocated(group.fxIds.size());

    for (int i = 0; i < group.fxChain.size(); ++i)
    {
        const auto id = group.fxChain.getReference(i);
        if (graph.getNodeForId(id) == nullptr)
            continue;

        bool alreadySeen = false;
        for (auto existing : compactedChain)
        {
            if (existing == id)
            {
                alreadySeen = true;
                break;
            }
        }
        if (alreadySeen)
            continue;

        compactedChain.add(id);
        if (i >= 0 && i < group.fxIds.size())
            compactedIds.add(group.fxIds[i]);
    }

    group.fxChain.swapWith(compactedChain);
    group.fxIds.swapWith(compactedIds);
    while (group.fxIds.size() > group.fxChain.size())
        group.fxIds.removeRange(group.fxIds.size() - 1, 1);
}

void JuceEngine::rewireTrackGroupFxChain(
    const juce::String &groupId,
    juce::AudioProcessorGraph::UpdateKind updateKind)
{
    auto *group = trackGroupForId(groupId);
    if (group == nullptr || group->inputNode == nullptr ||
        group->gainNode == nullptr || group->panNode == nullptr ||
        group->meterTapNode == nullptr || masterInputNode == nullptr)
        return;

    compactTrackGroupFxChain(*group);

    juce::Array<AudioProcessorGraph::NodeID> localNodes;
    localNodes.add(group->inputNode->nodeID);
    localNodes.add(group->gainNode->nodeID);
    localNodes.add(group->panNode->nodeID);
    localNodes.add(group->meterTapNode->nodeID);
    localNodes.add(masterInputNode->nodeID);
    for (auto fx : group->fxChain)
        localNodes.addIfNotAlreadyThere(fx);
    clearStereoConnectionsBetweenNodes(graph, localNodes, updateKind);

    auto prevNodeId = group->inputNode->nodeID;
    for (auto fx : group->fxChain)
    {
        if (graph.getNodeForId(fx) == nullptr)
            continue;
        connectStereo(graph, prevNodeId, fx, updateKind);
        prevNodeId = fx;
    }

    connectStereo(graph, prevNodeId, group->gainNode->nodeID, updateKind);
    connectStereo(graph, group->gainNode->nodeID, group->panNode->nodeID, updateKind);
    connectStereo(graph, group->panNode->nodeID, group->meterTapNode->nodeID, updateKind);
    connectStereo(graph, group->meterTapNode->nodeID, masterInputNode->nodeID, updateKind);

    if (!isProjectClipLoadTransactionActive() &&
        graphMutationBatchDepth <= 0)
        armOutputSafetyForCurrentRoute();
}

void JuceEngine::reconnectAllRowOutputsToBuses(
    juce::AudioProcessorGraph::UpdateKind updateKind)
{
    if (masterInputNode == nullptr)
        return;

    juce::Array<AudioProcessorGraph::NodeID> destinations;
    destinations.add(masterInputNode->nodeID);
    for (auto &group : trackGroups)
    {
        if (group.inputNode != nullptr)
            destinations.addIfNotAlreadyThere(group.inputNode->nodeID);
    }

    for (auto &row : rows)
    {
        if (row.meterTapNode == nullptr)
            continue;

        for (auto destination : destinations)
            disconnectStereo(graph, row.meterTapNode->nodeID, destination, updateKind);

        if (auto *group = trackGroupForMemberRowId(row.rowId);
            group != nullptr && group->inputNode != nullptr)
        {
            connectStereo(graph, row.meterTapNode->nodeID, group->inputNode->nodeID, updateKind);
        }
        else
        {
            connectStereo(graph, row.meterTapNode->nodeID, masterInputNode->nodeID, updateKind);
        }
    }
}

// ============================================================
// Track-row FX / parameters
// ============================================================
void JuceEngine::compactRowFxChain(int row)
{
    if (row < 0 || row >= (int)rows.size())
        return;

    auto &r = rows[(size_t)row];
    juce::Array<AudioProcessorGraph::NodeID> compactedChain;
    juce::StringArray compactedIds;
    compactedChain.ensureStorageAllocated(r.fxChain.size());
    compactedIds.ensureStorageAllocated(r.fxIds.size());

    for (int i = 0; i < r.fxChain.size(); ++i)
    {
        const auto id = r.fxChain.getReference(i);
        if (graph.getNodeForId(id) == nullptr)
            continue;

        bool alreadySeen = false;
        for (auto existing : compactedChain)
        {
            if (existing == id)
            {
                alreadySeen = true;
                break;
            }
        }
        if (alreadySeen)
            continue;

        compactedChain.add(id);
        if (i >= 0 && i < r.fxIds.size())
            compactedIds.add(r.fxIds[i]);
    }

    r.fxChain.swapWith(compactedChain);
    r.fxIds.swapWith(compactedIds);

    while (r.fxIds.size() > r.fxChain.size())
        r.fxIds.removeRange(r.fxIds.size() - 1, 1);
}

juce::Array<juce::AudioProcessorGraph::NodeID> *JuceEngine::effectChainForRowApi(int rowIndex, bool forceIndividualRow)
{
    if (rowIndex < 0 || rowIndex >= (int)rows.size())
        return nullptr;
    if (!forceIndividualRow)
        if (auto *group = trackGroupForLeadRowIndex(rowIndex))
            return &group->fxChain;
    return &rows[(size_t)rowIndex].fxChain;
}

juce::StringArray *JuceEngine::effectIdsForRowApi(int rowIndex, bool forceIndividualRow)
{
    if (rowIndex < 0 || rowIndex >= (int)rows.size())
        return nullptr;
    if (!forceIndividualRow)
        if (auto *group = trackGroupForLeadRowIndex(rowIndex))
            return &group->fxIds;
    return &rows[(size_t)rowIndex].fxIds;
}

void JuceEngine::compactMasterFxChain()
{
    if (!masterEffectChain)
        return;

    juce::Array<juce::AudioProcessorGraph::NodeID> compactedChain;
    juce::StringArray compactedIds;
    compactedChain.ensureStorageAllocated(masterEffectChain->size());
    compactedIds.ensureStorageAllocated(masterEffectIds.size());

    for (int i = 0; i < masterEffectChain->size(); ++i)
    {
        const auto id = masterEffectChain->getReference(i);
        if (graph.getNodeForId(id) == nullptr)
            continue;

        bool alreadySeen = false;
        for (auto existing : compactedChain)
        {
            if (existing == id)
            {
                alreadySeen = true;
                break;
            }
        }
        if (alreadySeen)
            continue;

        compactedChain.add(id);
        if (i >= 0 && i < masterEffectIds.size())
            compactedIds.add(masterEffectIds[i]);
    }

    masterEffectChain->swapWith(compactedChain);
    masterEffectIds.swapWith(compactedIds);

    while (masterEffectIds.size() > masterEffectChain->size())
        masterEffectIds.removeRange(masterEffectIds.size() - 1, 1);
}

bool JuceEngine::isGraphConnectionPresent(juce::AudioProcessorGraph::NodeID src,
                                          juce::AudioProcessorGraph::NodeID dst,
                                          int ch) const
{
    for (const auto &connection : graph.getConnections())
    {
        if (connection.source.nodeID == src &&
            connection.destination.nodeID == dst &&
            connection.source.channelIndex == ch &&
            connection.destination.channelIndex == ch)
        {
            return true;
        }
    }

    return false;
}

void JuceEngine::ensureMasterOutputRouting()
{
    if (!busGraphInitialised)
        ensureBusGraphInitialised();

    if (!masterInputNode || !masterGainNode || !masterPanNode || !outputNode)
    {
        rebuildBusesAndRewireClips();
        return;
    }

    compactMasterFxChain();

    auto *entryNode =
        (masterEffectChain != nullptr && masterEffectChain->size() > 0)
            ? graph.getNodeForId(masterEffectChain->getReference(0))
            : masterGainNode.get();

    if (entryNode == nullptr)
    {
        rebuildBusesAndRewireClips();
        return;
    }

    bool needsRepair = false;

    for (int ch = 0; ch < 2; ++ch)
    {
        if (!isGraphConnectionPresent(masterInputNode->nodeID, entryNode->nodeID, ch) ||
            !isGraphConnectionPresent(masterGainNode->nodeID, masterPanNode->nodeID, ch) ||
            !isGraphConnectionPresent(masterPanNode->nodeID, outputNode->nodeID, ch))
        {
            needsRepair = true;
            break;
        }
    }

    if (!needsRepair)
    {
        for (auto &row : rows)
        {
            if (row.meterTapNode == nullptr)
                continue;

            juce::AudioProcessorGraph::NodeID expectedDestination =
                masterInputNode->nodeID;
            if (auto *group = trackGroupForMemberRowId(row.rowId);
                group != nullptr && group->inputNode != nullptr)
            {
                expectedDestination = group->inputNode->nodeID;
            }

            for (int ch = 0; ch < 2; ++ch)
            {
                if (!isGraphConnectionPresent(row.meterTapNode->nodeID, expectedDestination, ch))
                {
                    needsRepair = true;
                    break;
                }
            }

            if (needsRepair)
                break;
        }
    }

    if (!needsRepair)
        return;

    rewireMasterFxChain(juce::AudioProcessorGraph::UpdateKind::none);
    commitGraphMutationLocked();
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

bool JuceEngine::insertTrackEffect(int trackRow, const juce::String &pluginPath, bool forceIndividualRow)
{
    constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;
    const auto requestedId = pluginPath.trim();
    const bool isBuiltInMixroomPlugin = mixroomPlugins.contains(requestedId);

    if (requestedId.isEmpty())
    {
        juceLogToFlutter("insertTrackEffect: empty plugin identifier");
        return false;
    }

    // juceLogToFlutter("Hello from JuceEngine::insertTrackEffect");

    const auto sr = getKnownDeviceSampleRate(
        deviceManager,
        hostSampleRateAtomic.load(std::memory_order_relaxed));
    const auto bs = getKnownDeviceBufferSize(deviceManager, 512);

    juce::String error;
    std::unique_ptr<juce::AudioProcessor> builtInPlugin;
    std::unique_ptr<juce::AudioPluginInstance> externalPlugin;

    if (isBuiltInMixroomPlugin)
    {
        builtInPlugin = createEffectProcessorFromIdentifier(
            pluginFormatManager,
            pluginList,
            requestedId,
            sr,
            bs,
            error);
        if (builtInPlugin == nullptr)
        {
            juceLogToFlutter(("insertTrackEffect failed for built-in '" +
                              requestedId + "': " + error)
                                 .toRawUTF8());
            return false;
        }
    }
    else
    {
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

        try
        {
            externalPlugin = pluginFormatManager.createPluginInstance(desc, sr, bs, error);
        }
        catch (const std::exception &e)
        {
            error = "exception: " + juce::String(e.what());
        }
        catch (...)
        {
            error = "unknown exception";
        }

        if (externalPlugin == nullptr)
        {
            juceLogToFlutter(("insertTrackEffect failed for '" +
                              requestedId + "': " + error)
                                 .toRawUTF8());
            return false;
        }
    }

    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return false;
    ensureRowBusNodesAttached(trackRow, batchUpdate);
    auto *groupState = forceIndividualRow ? nullptr : trackGroupForLeadRowIndex(trackRow);
    if (groupState != nullptr)
        ensureTrackGroupBusNodesAttached(*groupState, batchUpdate);
    else
        compactRowFxChain(trackRow);
    auto &rowState = rows[(size_t)trackRow];
    auto &chain = groupState != nullptr ? groupState->fxChain : rowState.fxChain;
    auto &fxIds = groupState != nullptr ? groupState->fxIds : rowState.fxIds;

    if (isBuiltInMixroomPlugin)
    {
        auto node = graph.addNode(std::move(builtInPlugin), std::nullopt, batchUpdate);
        if (node == nullptr)
        {
            juceLogToFlutter("insertTrackEffect: graph.addNode failed for built-in");
            return false;
        }
        chain.add(node->nodeID);
        fxIds.add(requestedId);

        if (graphMutationBatchDepth > 0)
        {
            if (groupState != nullptr)
                markGraphMutationBatchTrackGroupFxDirtyLocked(groupState->id);
            else
                markGraphMutationBatchRowFxDirtyLocked(trackRow);
        }
        else if (groupState != nullptr)
            rewireTrackGroupFxChain(groupState->id, batchUpdate);
        else
            rewireTrackBusFxChain(trackRow, batchUpdate);
        commitGraphMutationLocked();
        return true;
    }

    auto pluginNode = graph.addNode(std::move(externalPlugin), std::nullopt, batchUpdate);
    if (pluginNode == nullptr)
    {
        juceLogToFlutter(("insertTrackEffect: graph.addNode failed for '" + requestedId + "'").toRawUTF8());
        return false;
    }

    chain.add(pluginNode->nodeID);
    fxIds.add(requestedId);
    if (graphMutationBatchDepth > 0)
    {
        if (groupState != nullptr)
            markGraphMutationBatchTrackGroupFxDirtyLocked(groupState->id);
        else
            markGraphMutationBatchRowFxDirtyLocked(trackRow);
    }
    else if (groupState != nullptr)
        rewireTrackGroupFxChain(groupState->id, batchUpdate);
    else
        rewireTrackBusFxChain(trackRow, batchUpdate);
    commitGraphMutationLocked();
    return true;
}

void JuceEngine::removeTrackEffect(int trackRow, int effectIndex, bool forceIndividualRow)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;

    // juceLogToFlutter("Hello from JuceEngine::removeTrackEffect");

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return;

    auto *groupState = forceIndividualRow ? nullptr : trackGroupForLeadRowIndex(trackRow);
    if (groupState != nullptr)
        compactTrackGroupFxChain(*groupState);
    else
        compactRowFxChain(trackRow);
    auto &chain = groupState != nullptr ? groupState->fxChain : rows[(size_t)trackRow].fxChain;
    if (effectIndex < 0 || effectIndex >= chain.size())
        return;

    const auto nodeID = chain.getReference(effectIndex);

    chain.removeRange(effectIndex, 1);
    auto &fxIds = groupState != nullptr ? groupState->fxIds : rows[(size_t)trackRow].fxIds;
    if (effectIndex >= 0 && effectIndex < fxIds.size())
        fxIds.removeRange(effectIndex, 1);

    if (groupState == nullptr)
    {
        auto &automationLanes = rows[(size_t)trackRow].effectAutomationLanes;
        automationLanes.erase(
            std::remove_if(
                automationLanes.begin(),
                automationLanes.end(),
                [effectIndex](const RowState::TrackEffectAutomationLane &lane)
                { return lane.effectIndex == effectIndex; }),
            automationLanes.end());
        for (auto &lane : automationLanes)
        {
            if (lane.effectIndex > effectIndex)
                lane.effectIndex -= 1;
            lane.lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
        }
        publishAutomationSnapshotLocked();
    }

    if (graphMutationBatchDepth > 0)
    {
        if (groupState != nullptr)
            markGraphMutationBatchTrackGroupFxDirtyLocked(groupState->id);
        else
            markGraphMutationBatchRowFxDirtyLocked(trackRow);
    }
    else if (groupState != nullptr)
        rewireTrackGroupFxChain(groupState->id, batchUpdate);
    else
        rewireTrackBusFxChain(trackRow, batchUpdate);

    juce::Array<AudioProcessorGraph::Connection> nodeConnections;
    for (const auto &connection : graph.getConnections())
    {
        if (connection.source.nodeID == nodeID ||
            connection.destination.nodeID == nodeID)
            nodeConnections.addIfNotAlreadyThere(connection);
    }
    for (const auto &connection : nodeConnections)
        graph.removeConnection(connection, batchUpdate);
    if (graph.getNodeForId(nodeID) != nullptr)
        graph.removeNode(nodeID, batchUpdate);
    commitGraphMutationLocked();
}

void JuceEngine::reorderTrackEffects(int trackRow, int fromIndex, int toIndex, bool forceIndividualRow)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    // juceLogToFlutter("Hello from JuceEngine::reorderTrackEffects");

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return;

    auto *groupState = forceIndividualRow ? nullptr : trackGroupForLeadRowIndex(trackRow);
    if (groupState != nullptr)
        compactTrackGroupFxChain(*groupState);
    else
        compactRowFxChain(trackRow);
    auto &chain = groupState != nullptr ? groupState->fxChain : rows[(size_t)trackRow].fxChain;

    if (fromIndex < 0 || fromIndex >= chain.size())
        return;
    if (toIndex < 0 || toIndex > chain.size())
        return;
    if (fromIndex == toIndex)
        return;

    auto nodeID = chain.getReference(fromIndex);
    juce::String fxId;
    auto &fxIds = groupState != nullptr ? groupState->fxIds : rows[(size_t)trackRow].fxIds;
    if (fromIndex >= 0 && fromIndex < fxIds.size())
        fxId = fxIds[fromIndex];

    chain.removeRange(fromIndex, 1);
    toIndex = juce::jlimit(0, chain.size(), toIndex);
    chain.insert(toIndex, nodeID);
    const int finalToIndex = toIndex;
    if (fromIndex >= 0 && fromIndex < fxIds.size())
    {
        fxIds.remove(fromIndex);
        const int idToIndex = juce::jlimit(0, fxIds.size(), finalToIndex);
        fxIds.insert(idToIndex, fxId);
    }

    if (groupState == nullptr)
    {
        auto &automationLanes = rows[(size_t)trackRow].effectAutomationLanes;
        for (auto &lane : automationLanes)
        {
            const int idx = lane.effectIndex;
            if (idx == fromIndex)
            {
                lane.effectIndex = finalToIndex;
            }
            else if (fromIndex < finalToIndex)
            {
                if (idx > fromIndex && idx <= finalToIndex)
                    lane.effectIndex = idx - 1;
            }
            else if (fromIndex > finalToIndex)
            {
                if (idx >= finalToIndex && idx < fromIndex)
                    lane.effectIndex = idx + 1;
            }
            lane.lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
        }
        publishAutomationSnapshotLocked();
    }

    if (graphMutationBatchDepth > 0)
    {
        if (groupState != nullptr)
            markGraphMutationBatchTrackGroupFxDirtyLocked(groupState->id);
        else
            markGraphMutationBatchRowFxDirtyLocked(trackRow);
    }
    else if (groupState != nullptr)
        rewireTrackGroupFxChain(groupState->id, juce::AudioProcessorGraph::UpdateKind::none);
    else
        rewireTrackBusFxChain(trackRow, juce::AudioProcessorGraph::UpdateKind::none);
    commitGraphMutationLocked();
}

juce::StringArray JuceEngine::getTrackEffectsForRow(int trackRow, bool forceIndividualRow)
{
    juce::StringArray names;

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return names;

    auto *chainPtr = effectChainForRowApi(trackRow, forceIndividualRow);
    if (chainPtr == nullptr)
        return names;
    auto &chain = *chainPtr;

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

juce::StringArray JuceEngine::getTrackEffectIdsForRow(int trackRow, bool forceIndividualRow)
{
    juce::StringArray ids;

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return ids;

    auto *chainPtr = effectChainForRowApi(trackRow, forceIndividualRow);
    auto *idsPtr = effectIdsForRowApi(trackRow, forceIndividualRow);
    if (chainPtr == nullptr || idsPtr == nullptr)
        return ids;
    auto &chain = *chainPtr;
    auto &fxIds = *idsPtr;
    if (fxIds.size() == chain.size())
        return fxIds;

    // Legacy fallback for previously-created rows without explicit IDs.
    for (auto &nodeID : chain)
    {
        if (auto node = graph.getNodeForId(nodeID))
            if (auto *processor = node->getProcessor())
                ids.add(processor->getName());
    }

    return ids;
}

juce::StringArray JuceEngine::getTrackEffectInstanceIdsForRow(int trackRow, bool forceIndividualRow)
{
    juce::StringArray ids;

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return ids;

    auto *chainPtr = effectChainForRowApi(trackRow, forceIndividualRow);
    if (chainPtr == nullptr)
        return ids;
    auto &chain = *chainPtr;

    for (auto &nodeID : chain)
        ids.add(juce::String((juce::int64)nodeID.uid));

    return ids;
}

void JuceEngine::setTrackEffectParameter(int trackRow,
                                         int effectIndex,
                                         const juce::String &paramName,
                                         const juce::var &newValue,
                                         bool forceIndividualRow)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    // juceLogToFlutter("JuceEngine::setTrackEffectParameter");

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return;

    auto *chainPtr = effectChainForRowApi(trackRow, forceIndividualRow);
    if (chainPtr == nullptr)
        return;
    auto &chain = *chainPtr;
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
        bool matchesParam = (p->getName(128) == paramName);
        if (!matchesParam)
            if (auto *withID = dynamic_cast<juce::AudioProcessorParameterWithID *>(p))
                matchesParam = (withID->paramID == paramName);

        if (!matchesParam)
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

void JuceEngine::bypassRowEffect(int trackRow, int effectIndex, bool shouldBypass, bool forceIndividualRow)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return;

    if (!forceIndividualRow)
        if (auto *group = trackGroupForLeadRowIndex(trackRow))
            compactTrackGroupFxChain(*group);
        else
            compactRowFxChain(trackRow);
    else
        compactRowFxChain(trackRow);
    auto *chainPtr = effectChainForRowApi(trackRow, forceIndividualRow);
    if (chainPtr == nullptr)
        return;
    auto &chain = *chainPtr;
    if (effectIndex < 0 || effectIndex >= chain.size())
        return;

    auto nodeID = chain.getReference(effectIndex);
    if (auto node = graph.getNodeForId(nodeID))
        node->setBypassed(shouldBypass);
}

bool JuceEngine::getRowEffectBypassState(int trackRow, int effectIndex, bool forceIndividualRow)
{
    if (trackRow < 0 || trackRow >= (int)rows.size())
        return false;

    auto *chainPtr = effectChainForRowApi(trackRow, forceIndividualRow);
    if (chainPtr == nullptr)
        return false;
    auto &chain = *chainPtr;
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
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return;

    auto safePoints = points;
    sanitiseAutomationPoints(safePoints, 1.0f);
    rows[(size_t)trackRow].automationPoints = safePoints;
    if (rows[(size_t)trackRow].automationProc != nullptr)
        rows[(size_t)trackRow].automationProc->setAutomationPoints(safePoints);
}

void JuceEngine::setTrackEffectAutomationPoints(
    int trackRow,
    int effectIndex,
    const juce::String &paramId,
    float minValue,
    float maxValue,
    const std::vector<AutomationPoint> &points)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return;
    if (effectIndex < 0)
        return;

    auto trimmedParamId = paramId.trim();
    if (trimmedParamId.isEmpty())
        return;

    auto &lanes = rows[(size_t)trackRow].effectAutomationLanes;
    std::vector<AutomationPoint> safePoints = points;
    sanitiseAutomationPoints(safePoints, 1.0f);

    auto laneIt = std::find_if(
        lanes.begin(),
        lanes.end(),
        [&](const RowState::TrackEffectAutomationLane &lane)
        {
            return lane.effectIndex == effectIndex && lane.paramId == trimmedParamId;
        });

    if (safePoints.empty())
    {
        if (laneIt != lanes.end())
            lanes.erase(laneIt);
        publishAutomationSnapshotLocked();
        return;
    }

    const float safeMin = std::isfinite(minValue) ? minValue : 0.0f;
    const float safeMax = std::isfinite(maxValue) ? maxValue : 1.0f;
    const float rangeMin = juce::jmin(safeMin, safeMax);
    const float rangeMax = juce::jmax(safeMin, safeMax);

    if (laneIt == lanes.end())
    {
        RowState::TrackEffectAutomationLane lane;
        lane.effectIndex = effectIndex;
        lane.paramId = trimmedParamId;
        lane.minValue = rangeMin;
        lane.maxValue = rangeMax;
        lane.points = std::move(safePoints);
        lane.lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
        lanes.push_back(std::move(lane));
        publishAutomationSnapshotLocked();
        return;
    }

    laneIt->minValue = rangeMin;
    laneIt->maxValue = rangeMax;
    laneIt->points = std::move(safePoints);
    laneIt->lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
    publishAutomationSnapshotLocked();
}

void JuceEngine::clearTrackEffectAutomationForRow(int trackRow)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return;
    rows[(size_t)trackRow].effectAutomationLanes.clear();
    publishAutomationSnapshotLocked();
}

void JuceEngine::setRowGainAutomationPoints(
    int row,
    const std::vector<AutomationPoint> &points)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (row < 0 || row >= (int)rows.size())
        return;

    auto safePoints = points;
    sanitiseAutomationPoints(safePoints, 1.0f);
    rows[(size_t)row].gainAutomationPoints = std::move(safePoints);
    rows[(size_t)row].lastAppliedGainAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
    publishAutomationSnapshotLocked();
}

void JuceEngine::setRowPanAutomationPoints(
    int row,
    const std::vector<AutomationPoint> &points)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (row < 0 || row >= (int)rows.size())
        return;

    auto safePoints = points;
    sanitiseAutomationPoints(safePoints, 1.0f);
    rows[(size_t)row].panAutomationPoints = std::move(safePoints);
    rows[(size_t)row].lastAppliedPanAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
    publishAutomationSnapshotLocked();
}

void JuceEngine::setMasterEffectAutomationPoints(
    int effectIndex,
    const juce::String &paramId,
    float minValue,
    float maxValue,
    const std::vector<AutomationPoint> &points)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (effectIndex < 0)
        return;

    auto trimmedParamId = paramId.trim();
    if (trimmedParamId.isEmpty())
        return;

    auto laneIt = std::find_if(
        masterEffectAutomationLanes.begin(),
        masterEffectAutomationLanes.end(),
        [&](const RowState::TrackEffectAutomationLane &lane)
        {
            return lane.effectIndex == effectIndex && lane.paramId == trimmedParamId;
        });

    auto safePoints = points;
    sanitiseAutomationPoints(safePoints, 1.0f);

    if (safePoints.empty())
    {
        if (laneIt != masterEffectAutomationLanes.end())
            masterEffectAutomationLanes.erase(laneIt);
        publishAutomationSnapshotLocked();
        return;
    }

    const float safeMin = std::isfinite(minValue) ? minValue : 0.0f;
    const float safeMax = std::isfinite(maxValue) ? maxValue : 1.0f;
    const float rangeMin = juce::jmin(safeMin, safeMax);
    const float rangeMax = juce::jmax(safeMin, safeMax);

    if (laneIt == masterEffectAutomationLanes.end())
    {
        RowState::TrackEffectAutomationLane lane;
        lane.effectIndex = effectIndex;
        lane.paramId = trimmedParamId;
        lane.minValue = rangeMin;
        lane.maxValue = rangeMax;
        lane.points = std::move(safePoints);
        lane.lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
        masterEffectAutomationLanes.push_back(std::move(lane));
        publishAutomationSnapshotLocked();
        return;
    }

    laneIt->minValue = rangeMin;
    laneIt->maxValue = rangeMax;
    laneIt->points = std::move(safePoints);
    laneIt->lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
    publishAutomationSnapshotLocked();
}

void JuceEngine::clearMasterEffectAutomation()
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    masterEffectAutomationLanes.clear();
    publishAutomationSnapshotLocked();
}

void JuceEngine::setMasterGainAutomationPoints(
    const std::vector<AutomationPoint> &points)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    auto safePoints = points;
    sanitiseAutomationPoints(safePoints, 1.0f);
    masterGainAutomationPoints = std::move(safePoints);
    lastAppliedMasterGainAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
    publishAutomationSnapshotLocked();
}

void JuceEngine::setMasterPanAutomationPoints(
    const std::vector<AutomationPoint> &points)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    auto safePoints = points;
    sanitiseAutomationPoints(safePoints, 1.0f);
    masterPanAutomationPoints = std::move(safePoints);
    lastAppliedMasterPanAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
    publishAutomationSnapshotLocked();
}

void JuceEngine::applyTrackEffectAutomationAtCurrentBlockStart()
{
    applyTrackEffectAutomationAtTimeSeconds(
        blockTransportStartSec.load(std::memory_order_relaxed));
}

void JuceEngine::setAutomationTransport(double timeSeconds)
{
    setTransportSeconds(timeSeconds);
}

std::shared_ptr<JuceEngine::AutomationLatchState>
JuceEngine::rowAutomationLatchesLocked(int rowId)
{
    auto &entry = rowAutomationLatches[rowId];
    if (entry == nullptr)
        entry = std::make_shared<AutomationLatchState>();
    return entry;
}

std::shared_ptr<JuceEngine::AutomationLaneLatch>
JuceEngine::automationLaneLatchLocked(const std::string &key)
{
    auto &entry = automationLaneLatches[key];
    if (entry == nullptr)
        entry = std::make_shared<AutomationLaneLatch>();
    return entry;
}

std::string JuceEngine::automationLaneKeyForRow(
    int rowId,
    int effectIndex,
    const juce::String &paramId)
{
    return "row:" + std::to_string(rowId) + ":" +
           std::to_string(effectIndex) + ":" + paramId.toStdString();
}

std::string JuceEngine::automationLaneKeyForMaster(
    int effectIndex,
    const juce::String &paramId)
{
    return "master:" + std::to_string(effectIndex) + ":" +
           paramId.toStdString();
}

bool JuceEngine::automationParameterMatches(
    juce::AudioProcessorParameter &parameter,
    const juce::String &paramId)
{
    if (parameter.getName(128) == paramId)
        return true;

    if (auto *withID = dynamic_cast<juce::AudioProcessorParameterWithID *>(&parameter))
        return withID->paramID == paramId;

    return false;
}

JuceEngine::AutomationParameterTarget
JuceEngine::resolveTrackAutomationParameterTargetLocked(
    int rowIndex,
    int effectIndex,
    const juce::String &paramId)
{
    AutomationParameterTarget target;
    if (rowIndex < 0 || rowIndex >= (int)rows.size())
        return target;

    auto *chainPtr = effectChainForRowApi(rowIndex);
    if (chainPtr == nullptr)
        return target;

    auto &chain = *chainPtr;
    if (effectIndex < 0 || effectIndex >= chain.size())
        return target;

    auto node = graph.getNodeForId(chain.getReference(effectIndex));
    if (node == nullptr || node->getProcessor() == nullptr)
        return target;

    for (auto *parameter : node->getProcessor()->getParameters())
    {
        if (parameter == nullptr || !automationParameterMatches(*parameter, paramId))
            continue;

        target.node = node;
        target.parameter = parameter;
        const juce::String rawParameterId =
            dynamic_cast<juce::AudioProcessorParameterWithID *>(parameter) != nullptr
                ? dynamic_cast<juce::AudioProcessorParameterWithID *>(parameter)->paramID
                : paramId;
        target.realtimeRawValue =
            mixroom::fx::rawParameterValueForBuiltInEffect(
                *node->getProcessor(),
                rawParameterId);
        if (auto *floatParameter = dynamic_cast<juce::AudioParameterFloat *>(parameter))
        {
            target.usesFloatRange = true;
            target.floatRange = floatParameter->range;
            if (target.realtimeRawValue != nullptr)
                target.realtimeWriteKind =
                    AutomationParameterTarget::RealtimeWriteKind::floatActual;
        }
        else if (dynamic_cast<juce::AudioParameterBool *>(parameter) != nullptr)
        {
            if (target.realtimeRawValue != nullptr)
                target.realtimeWriteKind =
                    AutomationParameterTarget::RealtimeWriteKind::boolNormalized;
        }
        else if (auto *choiceParameter = dynamic_cast<juce::AudioParameterChoice *>(parameter))
        {
            if (target.realtimeRawValue != nullptr)
            {
                target.realtimeWriteKind =
                    AutomationParameterTarget::RealtimeWriteKind::choiceNormalized;
                target.realtimeChoiceMaxIndex =
                    juce::jmax(0, choiceParameter->choices.size() - 1);
            }
        }
        else if (target.realtimeRawValue != nullptr)
        {
            target.realtimeWriteKind =
                AutomationParameterTarget::RealtimeWriteKind::normalized;
        }
        return target;
    }

    return target;
}

JuceEngine::AutomationParameterTarget
JuceEngine::resolveMasterAutomationParameterTargetLocked(
    int effectIndex,
    const juce::String &paramId)
{
    AutomationParameterTarget target;
    if (masterEffectChain == nullptr)
        return target;

    if (effectIndex < 0 || effectIndex >= masterEffectChain->size())
        return target;

    auto node = graph.getNodeForId(masterEffectChain->getReference(effectIndex));
    if (node == nullptr || node->getProcessor() == nullptr)
        return target;

    for (auto *parameter : node->getProcessor()->getParameters())
    {
        if (parameter == nullptr || !automationParameterMatches(*parameter, paramId))
            continue;

        target.node = node;
        target.parameter = parameter;
        const juce::String rawParameterId =
            dynamic_cast<juce::AudioProcessorParameterWithID *>(parameter) != nullptr
                ? dynamic_cast<juce::AudioProcessorParameterWithID *>(parameter)->paramID
                : paramId;
        target.realtimeRawValue =
            mixroom::fx::rawParameterValueForBuiltInEffect(
                *node->getProcessor(),
                rawParameterId);
        if (auto *floatParameter = dynamic_cast<juce::AudioParameterFloat *>(parameter))
        {
            target.usesFloatRange = true;
            target.floatRange = floatParameter->range;
            if (target.realtimeRawValue != nullptr)
                target.realtimeWriteKind =
                    AutomationParameterTarget::RealtimeWriteKind::floatActual;
        }
        else if (dynamic_cast<juce::AudioParameterBool *>(parameter) != nullptr)
        {
            if (target.realtimeRawValue != nullptr)
                target.realtimeWriteKind =
                    AutomationParameterTarget::RealtimeWriteKind::boolNormalized;
        }
        else if (auto *choiceParameter = dynamic_cast<juce::AudioParameterChoice *>(parameter))
        {
            if (target.realtimeRawValue != nullptr)
            {
                target.realtimeWriteKind =
                    AutomationParameterTarget::RealtimeWriteKind::choiceNormalized;
                target.realtimeChoiceMaxIndex =
                    juce::jmax(0, choiceParameter->choices.size() - 1);
            }
        }
        else if (target.realtimeRawValue != nullptr)
        {
            target.realtimeWriteKind =
                AutomationParameterTarget::RealtimeWriteKind::normalized;
        }
        return target;
    }

    return target;
}

void JuceEngine::applyAutomationParameterTarget(
    const AutomationParameterTarget &target,
    float value)
{
    if (!target.isValid())
        return;

    if (target.realtimeRawValue != nullptr)
    {
        float rawValue = juce::jlimit(0.0f, 1.0f, value);
        switch (target.realtimeWriteKind)
        {
            case AutomationParameterTarget::RealtimeWriteKind::floatActual:
                rawValue = target.usesFloatRange
                               ? juce::jlimit(target.floatRange.start,
                                              target.floatRange.end,
                                              value)
                               : value;
                break;
            case AutomationParameterTarget::RealtimeWriteKind::boolNormalized:
                rawValue = value >= 0.5f ? 1.0f : 0.0f;
                break;
            case AutomationParameterTarget::RealtimeWriteKind::choiceNormalized:
                rawValue = (float)juce::jlimit(
                    0,
                    juce::jmax(0, target.realtimeChoiceMaxIndex),
                    juce::roundToInt(juce::jlimit(0.0f, 1.0f, value) *
                                     (float)juce::jmax(0, target.realtimeChoiceMaxIndex)));
                break;
            case AutomationParameterTarget::RealtimeWriteKind::normalized:
            case AutomationParameterTarget::RealtimeWriteKind::none:
                rawValue = juce::jlimit(0.0f, 1.0f, value);
                break;
        }
        target.realtimeRawValue->store(rawValue, std::memory_order_relaxed);
        return;
    }

    if (target.usesFloatRange)
    {
        const float clamped =
            juce::jlimit(target.floatRange.start, target.floatRange.end, value);
        target.parameter->setValue(target.floatRange.convertTo0to1(clamped));
        return;
    }

    target.parameter->setValue(juce::jlimit(0.0f, 1.0f, value));
}

void JuceEngine::publishAutomationSnapshotLocked()
{
    auto next = std::make_shared<AutomationSnapshot>();
    next->rows.reserve(rows.size());

    std::unordered_set<std::string> activeLaneKeys;
    std::unordered_set<int> activeRowIds;

    for (int rowIndex = 0; rowIndex < (int)rows.size(); ++rowIndex)
    {
        const auto &rowState = rows[(size_t)rowIndex];
        activeRowIds.insert(rowState.rowId);

        RowAutomationSnapshot rowSnapshot;
        rowSnapshot.rowIndex = rowIndex;
        rowSnapshot.rowId = rowState.rowId;
        rowSnapshot.gainAutomationPoints = rowState.gainAutomationPoints;
        rowSnapshot.panAutomationPoints = rowState.panAutomationPoints;
        rowSnapshot.muted = rowState.muted;
        if (rowState.gainProc != nullptr && rowState.gainAutomationPoints.empty())
            rowState.gainProc->clearAutomationGainOverride();
        if (rowState.panProc != nullptr && rowState.panAutomationPoints.empty())
            rowState.panProc->clearAutomationPanOverride();
        if (rowState.gainNode != nullptr && rowState.gainProc != nullptr && rowState.gainProc->gain != nullptr)
        {
            rowSnapshot.gainTarget.node = rowState.gainNode;
            rowSnapshot.gainTarget.parameter =
                static_cast<juce::AudioProcessorParameter *>(rowState.gainProc->gain);
        }
        if (rowState.panNode != nullptr && rowState.panProc != nullptr && rowState.panProc->pan != nullptr)
        {
            rowSnapshot.panTarget.node = rowState.panNode;
            rowSnapshot.panTarget.parameter =
                static_cast<juce::AudioProcessorParameter *>(rowState.panProc->pan);
        }
        rowSnapshot.latches = rowAutomationLatchesLocked(rowState.rowId);
        if (rowSnapshot.latches != nullptr)
            rowSnapshot.latches->reset();

        rowSnapshot.effectAutomationLanes.reserve(rowState.effectAutomationLanes.size());
        for (const auto &lane : rowState.effectAutomationLanes)
        {
            AutomationEffectLaneSnapshot laneSnapshot;
            laneSnapshot.effectIndex = lane.effectIndex;
            laneSnapshot.paramId = lane.paramId;
            laneSnapshot.minValue = lane.minValue;
            laneSnapshot.maxValue = lane.maxValue;
            laneSnapshot.points = lane.points;
            laneSnapshot.target = resolveTrackAutomationParameterTargetLocked(
                rowIndex,
                lane.effectIndex,
                lane.paramId);

            const auto key = automationLaneKeyForRow(rowState.rowId, lane.effectIndex, lane.paramId);
            activeLaneKeys.insert(key);
            laneSnapshot.latch = automationLaneLatchLocked(key);
            if (laneSnapshot.latch != nullptr)
                laneSnapshot.latch->reset();

            rowSnapshot.effectAutomationLanes.push_back(std::move(laneSnapshot));
        }

        next->rows.push_back(std::move(rowSnapshot));
    }

    next->masterGainAutomationPoints = masterGainAutomationPoints;
    next->masterPanAutomationPoints = masterPanAutomationPoints;
    next->masterMuted = masterMuted;
    if (masterGainProcessor != nullptr && masterGainAutomationPoints.empty())
        masterGainProcessor->clearAutomationGainOverride();
    if (masterPanProcessor != nullptr && masterPanAutomationPoints.empty())
        masterPanProcessor->clearAutomationPanOverride();
    if (masterGainNode != nullptr && masterGainProcessor != nullptr && masterGainProcessor->gain != nullptr)
    {
        next->masterGainTarget.node = masterGainNode;
        next->masterGainTarget.parameter =
            static_cast<juce::AudioProcessorParameter *>(masterGainProcessor->gain);
    }
    if (masterPanNode != nullptr && masterPanProcessor != nullptr && masterPanProcessor->pan != nullptr)
    {
        next->masterPanTarget.node = masterPanNode;
        next->masterPanTarget.parameter =
            static_cast<juce::AudioProcessorParameter *>(masterPanProcessor->pan);
    }
    next->masterLatches = masterAutomationLatches;
    if (next->masterLatches != nullptr)
        next->masterLatches->reset();

    next->masterEffectAutomationLanes.reserve(masterEffectAutomationLanes.size());
    for (const auto &lane : masterEffectAutomationLanes)
    {
        AutomationEffectLaneSnapshot laneSnapshot;
        laneSnapshot.effectIndex = lane.effectIndex;
        laneSnapshot.paramId = lane.paramId;
        laneSnapshot.minValue = lane.minValue;
        laneSnapshot.maxValue = lane.maxValue;
        laneSnapshot.points = lane.points;
        laneSnapshot.target = resolveMasterAutomationParameterTargetLocked(
            lane.effectIndex,
            lane.paramId);

        const auto key = automationLaneKeyForMaster(lane.effectIndex, lane.paramId);
        activeLaneKeys.insert(key);
        laneSnapshot.latch = automationLaneLatchLocked(key);
        if (laneSnapshot.latch != nullptr)
            laneSnapshot.latch->reset();

        next->masterEffectAutomationLanes.push_back(std::move(laneSnapshot));
    }

    for (auto it = rowAutomationLatches.begin(); it != rowAutomationLatches.end();)
    {
        if (activeRowIds.find(it->first) == activeRowIds.end())
            it = rowAutomationLatches.erase(it);
        else
            ++it;
    }

    for (auto it = automationLaneLatches.begin(); it != automationLaneLatches.end();)
    {
        if (activeLaneKeys.find(it->first) == activeLaneKeys.end())
            it = automationLaneLatches.erase(it);
        else
            ++it;
    }

    if (automationSnapshot != nullptr)
    {
        retiredAutomationSnapshots.push_back(
            {std::move(automationSnapshot),
             routedAudioRenderGeneration.load(std::memory_order_acquire)});
    }

    automationSnapshot = std::shared_ptr<const AutomationSnapshot>(std::move(next));
    automationSnapshotRaw.store(automationSnapshot.get(), std::memory_order_release);
    drainRetiredAutomationSnapshotsLocked();
}

void JuceEngine::drainRetiredAutomationSnapshotsLocked()
{
    constexpr uint64_t kRetireAfterRenderGenerations = 16;
    const uint64_t currentGeneration =
        routedAudioRenderGeneration.load(std::memory_order_acquire);

    for (auto it = retiredAutomationSnapshots.begin();
         it != retiredAutomationSnapshots.end();)
    {
        const bool renderGraceElapsed =
            currentGeneration >= it->retiredAtRenderGeneration &&
            (currentGeneration - it->retiredAtRenderGeneration) >=
                kRetireAfterRenderGenerations;
        if (!renderGraceElapsed)
        {
            ++it;
            continue;
        }

        it = retiredAutomationSnapshots.erase(it);
    }
}

void JuceEngine::applyTrackEffectAutomationAtTimeSeconds(double timeSeconds)
{
    constexpr float kAutomationEpsilon = 1.0e-4f;
    const auto *snapshot = automationSnapshotRaw.load(std::memory_order_acquire);
    if (snapshot == nullptr)
        return;

    const double timeMs = juce::jmax(0.0, timeSeconds) * 1000.0;

    for (const auto &rowAutomation : snapshot->rows)
    {
        if (!rowAutomation.gainAutomationPoints.empty())
        {
            const float normalized = juce::jlimit(
                0.0f,
                1.0f,
                (float)evaluateAutomationValueAtMs(rowAutomation.gainAutomationPoints, timeMs, 0.0));
            const float lastApplied = rowAutomation.latches != nullptr
                                          ? rowAutomation.latches->lastAppliedGainNormalized.load(std::memory_order_relaxed)
                                          : std::numeric_limits<float>::quiet_NaN();
            if (!std::isfinite(lastApplied) ||
                std::abs(normalized - lastApplied) > kAutomationEpsilon)
            {
                const float gain = kGainUiMin + (kGainUiMax - kGainUiMin) * normalized;
                if (rowAutomation.gainTarget.node != nullptr)
                {
                    if (auto *gainProc = dynamic_cast<SimpleGainProcessor *>(
                            rowAutomation.gainTarget.node->getProcessor()))
                    {
                        gainProc->setAutomationGainUiRealtime(gain);
                        gainProc->setMuted(rowAutomation.muted);
                    }
                    else
                    {
                        applyAutomationParameterTarget(rowAutomation.gainTarget, gain);
                    }
                }
                if (rowAutomation.latches != nullptr)
                    rowAutomation.latches->lastAppliedGainNormalized.store(normalized, std::memory_order_relaxed);
            }
        }

        if (!rowAutomation.panAutomationPoints.empty())
        {
            const float pan = juce::jlimit(
                0.0f,
                1.0f,
                (float)evaluateAutomationValueAtMs(rowAutomation.panAutomationPoints, timeMs, 0.5));
            const float lastApplied = rowAutomation.latches != nullptr
                                          ? rowAutomation.latches->lastAppliedPanNormalized.load(std::memory_order_relaxed)
                                          : std::numeric_limits<float>::quiet_NaN();
            if (!std::isfinite(lastApplied) ||
                std::abs(pan - lastApplied) > kAutomationEpsilon)
            {
                if (rowAutomation.panTarget.node != nullptr)
                {
                    if (auto *panProc = dynamic_cast<StereoPanProcessor *>(
                            rowAutomation.panTarget.node->getProcessor()))
                    {
                        panProc->setAutomationPanNormalizedRealtime(pan);
                    }
                    else
                    {
                        applyAutomationParameterTarget(
                            rowAutomation.panTarget,
                            juce::jmap(pan, -1.0f, 1.0f));
                    }
                }
                if (rowAutomation.latches != nullptr)
                    rowAutomation.latches->lastAppliedPanNormalized.store(pan, std::memory_order_relaxed);
            }
        }

        if (rowAutomation.effectAutomationLanes.empty())
            continue;

        for (const auto &lane : rowAutomation.effectAutomationLanes)
        {
            if (!lane.target.isValid())
                continue;
            if (lane.paramId.trim().isEmpty())
                continue;
            if (lane.points.empty())
                continue;

            const float normalized = juce::jlimit(
                0.0f,
                1.0f,
                (float)evaluateAutomationValueAtMs(lane.points, timeMs, 0.0));
            const float lastApplied = lane.latch != nullptr
                                          ? lane.latch->lastAppliedNormalized.load(std::memory_order_relaxed)
                                          : std::numeric_limits<float>::quiet_NaN();
            if (std::isfinite(lastApplied) &&
                std::abs(normalized - lastApplied) <= kAutomationEpsilon)
                continue;

            const float value = lane.minValue + (lane.maxValue - lane.minValue) * normalized;
            applyAutomationParameterTarget(lane.target, value);
            if (lane.latch != nullptr)
                lane.latch->lastAppliedNormalized.store(normalized, std::memory_order_relaxed);
        }
    }

    if (!snapshot->masterGainAutomationPoints.empty())
    {
        const float normalized = juce::jlimit(
            0.0f,
            1.0f,
            (float)evaluateAutomationValueAtMs(snapshot->masterGainAutomationPoints, timeMs, 0.0));
        const float lastApplied = snapshot->masterLatches != nullptr
                                      ? snapshot->masterLatches->lastAppliedGainNormalized.load(std::memory_order_relaxed)
                                      : std::numeric_limits<float>::quiet_NaN();
        if (!std::isfinite(lastApplied) ||
            std::abs(normalized - lastApplied) > kAutomationEpsilon)
        {
            const float gain = kGainUiMin + (kGainUiMax - kGainUiMin) * normalized;
            if (snapshot->masterGainTarget.node != nullptr)
            {
                if (auto *gainProc = dynamic_cast<SimpleGainProcessor *>(
                        snapshot->masterGainTarget.node->getProcessor()))
                {
                    gainProc->setAutomationGainUiRealtime(gain);
                    gainProc->setMuted(snapshot->masterMuted);
                }
                else
                {
                    applyAutomationParameterTarget(snapshot->masterGainTarget, gain);
                }
            }
            if (snapshot->masterLatches != nullptr)
                snapshot->masterLatches->lastAppliedGainNormalized.store(normalized, std::memory_order_relaxed);
        }
    }

    if (!snapshot->masterPanAutomationPoints.empty())
    {
        const float pan = juce::jlimit(
            0.0f,
            1.0f,
            (float)evaluateAutomationValueAtMs(snapshot->masterPanAutomationPoints, timeMs, 0.5));
        const float lastApplied = snapshot->masterLatches != nullptr
                                      ? snapshot->masterLatches->lastAppliedPanNormalized.load(std::memory_order_relaxed)
                                      : std::numeric_limits<float>::quiet_NaN();
        if (!std::isfinite(lastApplied) ||
            std::abs(pan - lastApplied) > kAutomationEpsilon)
        {
            if (snapshot->masterPanTarget.node != nullptr)
            {
                if (auto *panProc = dynamic_cast<StereoPanProcessor *>(
                        snapshot->masterPanTarget.node->getProcessor()))
                {
                    panProc->setAutomationPanNormalizedRealtime(pan);
                }
                else
                {
                    applyAutomationParameterTarget(
                        snapshot->masterPanTarget,
                        juce::jmap(pan, -1.0f, 1.0f));
                }
            }
            if (snapshot->masterLatches != nullptr)
                snapshot->masterLatches->lastAppliedPanNormalized.store(pan, std::memory_order_relaxed);
        }
    }

    if (snapshot->masterEffectAutomationLanes.empty())
        return;

    for (const auto &lane : snapshot->masterEffectAutomationLanes)
    {
        if (!lane.target.isValid())
            continue;
        if (lane.paramId.trim().isEmpty())
            continue;
        if (lane.points.empty())
            continue;

        const float normalized = juce::jlimit(
            0.0f,
            1.0f,
            (float)evaluateAutomationValueAtMs(lane.points, timeMs, 0.0));
        const float lastApplied = lane.latch != nullptr
                                      ? lane.latch->lastAppliedNormalized.load(std::memory_order_relaxed)
                                      : std::numeric_limits<float>::quiet_NaN();
        if (std::isfinite(lastApplied) &&
            std::abs(normalized - lastApplied) <= kAutomationEpsilon)
            continue;
        const float value = lane.minValue + (lane.maxValue - lane.minValue) * normalized;
        applyAutomationParameterTarget(lane.target, value);
        if (lane.latch != nullptr)
            lane.latch->lastAppliedNormalized.store(normalized, std::memory_order_relaxed);
    }
}

void JuceEngine::resetTrackEffectAutomationLatches()
{
    for (int row = 0; row < (int)rows.size(); ++row)
        resetTrackEffectAutomationLatchesForRow(row);
    for (auto &lane : masterEffectAutomationLanes)
        lane.lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
    lastAppliedMasterGainAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
    lastAppliedMasterPanAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
    if (masterAutomationLatches != nullptr)
        masterAutomationLatches->reset();
    for (auto &entry : automationLaneLatches)
        if (entry.second != nullptr)
            entry.second->reset();
}

void JuceEngine::resetTrackEffectAutomationLatchesForRow(int row)
{
    if (row < 0 || row >= (int)rows.size())
        return;

    auto &lanes = rows[(size_t)row].effectAutomationLanes;
    for (auto &lane : lanes)
        lane.lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
    rows[(size_t)row].lastAppliedGainAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
    rows[(size_t)row].lastAppliedPanAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
    const auto latchIt = rowAutomationLatches.find(rows[(size_t)row].rowId);
    if (latchIt != rowAutomationLatches.end() && latchIt->second != nullptr)
        latchIt->second->reset();
}

void JuceEngine::addClipToRowIndex(int rowId, int clipId)
{
    rowIdToClipIds[rowId].addIfNotAlreadyThere(clipId);
    if (clipId >= 0 && clipId < (int)clips.size())
        addClipToRoutedSchedule(clips[(size_t)clipId]);
}

void JuceEngine::removeClipFromRowIndex(int rowId, int clipId)
{
    removeClipFromRoutedSchedule(rowId, clipId);

    const auto it = rowIdToClipIds.find(rowId);
    if (it == rowIdToClipIds.end())
        return;

    it->second.removeAllInstancesOf(clipId);
    if (it->second.isEmpty())
        rowIdToClipIds.erase(it);
}

long long JuceEngine::routedClipBucketForTime(double timeSec) const noexcept
{
    const double safeTime = std::isfinite(timeSec) ? juce::jmax(0.0, timeSec) : 0.0;
    return (long long)std::floor(safeTime / kMixroomRoutedClipBucketSeconds);
}

double JuceEngine::routedClipScheduleEndSec(const ClipState &clip) const noexcept
{
    const double safeStart =
        std::isfinite(clip.startSec) ? juce::jmax(0.0, clip.startSec) : 0.0;
    const double safeLength =
        std::isfinite(clip.lengthSec) ? juce::jmax(0.0, clip.lengthSec) : 0.0;
    double endSec = safeStart + safeLength;
    if (clip.isMidi)
        endSec += kMixroomRoutedMidiTailSeconds;
    return juce::jmax(safeStart, endSec);
}

bool JuceEngine::routedClipMayRenderBlock(const RoutedClipRenderItem &item,
                                          double blockStartSec,
                                          double blockEndSec) const noexcept
{
    if (item.processor == nullptr || item.clipId < 0)
        return false;

    if (item.isMidi &&
        liveMidiInputTargetClip.load(std::memory_order_relaxed) == item.clipId)
    {
        return true;
    }

    return blockEndSec > item.startSec && blockStartSec < item.endSec;
}

void JuceEngine::clearRoutedClipSchedules()
{
    rowRoutedClipSchedules.clear();
    dirtyRoutedClipScheduleRows.clear();
    routedClipItemsById.clear();
    requestRoutedClipSchedulePublishLocked();
}

void JuceEngine::beginRoutedClipScheduleMutationLocked() noexcept
{
    ++routedClipScheduleMutationDepth;
}

void JuceEngine::endRoutedClipScheduleMutationLocked()
{
    if (routedClipScheduleMutationDepth <= 0)
        return;

    --routedClipScheduleMutationDepth;
    if (routedClipScheduleMutationDepth > 0)
        return;

    if (!routedClipSchedulePublishPending || isProjectClipLoadTransactionActive())
        return;

    routedClipSchedulePublishPending = false;
    publishRoutedClipSchedulesLocked();
}

void JuceEngine::requestRoutedClipSchedulePublishLocked()
{
    if (routedClipScheduleMutationDepth > 0 || isProjectClipLoadTransactionActive())
    {
        routedClipSchedulePublishPending = true;
        return;
    }

    publishRoutedClipSchedulesLocked();
}

void JuceEngine::publishRoutedClipSchedulesLocked()
{
    if (rowRoutedClipScheduleSnapshot != nullptr)
    {
        retiredRoutedClipScheduleSnapshots.push_back({
            rowRoutedClipScheduleSnapshot,
            routedAudioRenderGeneration.load(std::memory_order_acquire)});
    }
    const auto previousSnapshot = rowRoutedClipScheduleSnapshot;
    auto nextSnapshot = std::make_shared<RoutedClipSchedules>();
    nextSnapshot->reserve(rowRoutedClipSchedules.size());
    for (const auto &rowEntry : rowRoutedClipSchedules)
    {
        const bool rowDirty =
            previousSnapshot == nullptr ||
            dirtyRoutedClipScheduleRows.find(rowEntry.first) != dirtyRoutedClipScheduleRows.end();
        if (!rowDirty)
        {
            const auto previousRow = previousSnapshot->find(rowEntry.first);
            if (previousRow != previousSnapshot->end() &&
                previousRow->second != nullptr)
            {
                nextSnapshot->emplace(rowEntry.first, previousRow->second);
                continue;
            }
        }

        RowRoutedClipSchedule publishedRow;
        publishedRow.bucketItems.reserve(rowEntry.second.bucketItems.size());

        for (const auto &bucketEntry : rowEntry.second.bucketItems)
        {
            RoutedClipBucketItems bucket;
            bucket.bucket = bucketEntry.first;
            bucket.items = bucketEntry.second;
            publishedRow.bucketItems.push_back(std::move(bucket));
        }

        std::sort(
            publishedRow.bucketItems.begin(),
            publishedRow.bucketItems.end(),
            [](const RoutedClipBucketItems &a,
               const RoutedClipBucketItems &b) noexcept
            {
                return a.bucket < b.bucket;
            });

        for (const auto &clipEntry : rowEntry.second.clipItemsById)
        {
            const int clipId = clipEntry.first;
            if (clipId < 0 || clipId >= kMaxClips)
                continue;

            const auto index = static_cast<size_t>(clipId);
            publishedRow.clipItemsById[index] = clipEntry.second;
            publishedRow.clipItemPresent.set(index);
        }

        nextSnapshot->emplace(
            rowEntry.first,
            std::make_shared<const RowRoutedClipSchedule>(std::move(publishedRow)));
    }

    auto nextItemSnapshot = std::make_shared<RoutedClipItemsSnapshot>();
    for (const auto &clipEntry : routedClipItemsById)
    {
        const int clipId = clipEntry.first;
        if (clipId < 0 || clipId >= kMaxClips)
            continue;

        const auto index = static_cast<size_t>(clipId);
        nextItemSnapshot->itemsById[index] = clipEntry.second;
        nextItemSnapshot->itemPresent.set(index);
    }
    std::shared_ptr<const RoutedClipItemsSnapshot> publishedItemSnapshot =
        std::move(nextItemSnapshot);
    const auto *nextItemSnapshotRaw = publishedItemSnapshot.get();

    rowRoutedClipScheduleSnapshot =
        std::shared_ptr<const RoutedClipSchedules>(std::move(nextSnapshot));
    dirtyRoutedClipScheduleRows.clear();
    auto previousItemSnapshot = std::atomic_exchange_explicit(
        &routedClipItemSnapshot,
        std::move(publishedItemSnapshot),
        std::memory_order_acq_rel);
    if (previousItemSnapshot != nullptr)
    {
        retiredRoutedClipItemSnapshots.push_back({
            std::move(previousItemSnapshot),
            routedAudioRenderGeneration.load(std::memory_order_acquire)});
    }
    routedClipItemSnapshotRaw.store(
        nextItemSnapshotRaw,
        std::memory_order_release);
    refreshRowRoutedSchedulePointersLocked();
    drainRetiredRoutedClipScheduleSnapshotsLocked();
}

void JuceEngine::refreshRowRoutedSchedulePointersLocked()
{
    const auto *snapshot = rowRoutedClipScheduleSnapshot.get();
    for (auto &row : rows)
    {
        const void *schedule = nullptr;
        if (snapshot != nullptr)
        {
            if (const auto it = snapshot->find(row.rowId);
                it != snapshot->end() &&
                it->second != nullptr)
            {
                schedule = it->second.get();
            }
        }

        if (row.inputProc != nullptr)
            row.inputProc->setRoutedClipSchedule(schedule);
    }
}

void JuceEngine::drainRetiredRoutedClipScheduleSnapshotsLocked()
{
    constexpr uint64_t kRetireAfterRenderGenerations = 16;
    const auto currentGeneration =
        routedAudioRenderGeneration.load(std::memory_order_acquire);

    for (auto it = retiredRoutedClipScheduleSnapshots.begin();
         it != retiredRoutedClipScheduleSnapshots.end();)
    {
        const bool renderGraceElapsed =
            currentGeneration >= it->retiredAtRenderGeneration &&
            (currentGeneration - it->retiredAtRenderGeneration) >=
                kRetireAfterRenderGenerations;
        if (!renderGraceElapsed)
        {
            ++it;
            continue;
        }

        it = retiredRoutedClipScheduleSnapshots.erase(it);
    }

    for (auto it = retiredRoutedClipItemSnapshots.begin();
         it != retiredRoutedClipItemSnapshots.end();)
    {
        const bool renderGraceElapsed =
            currentGeneration >= it->retiredAtRenderGeneration &&
            (currentGeneration - it->retiredAtRenderGeneration) >=
                kRetireAfterRenderGenerations;
        if (!renderGraceElapsed)
        {
            ++it;
            continue;
        }

        it = retiredRoutedClipItemSnapshots.erase(it);
    }
}

void JuceEngine::addClipToRoutedSchedule(const ClipState &clip)
{
    auto processor = liveProcessorSharedForClip(clip);
    if (!clip.alive || processor == nullptr || clip.clipId < 0)
        return;

    const double startSec =
        std::isfinite(clip.startSec) ? juce::jmax(0.0, clip.startSec) : 0.0;
    const double endSec = routedClipScheduleEndSec(clip);
    if (endSec <= startSec)
        return;

    auto &schedule = rowRoutedClipSchedules[clip.rowId];
    dirtyRoutedClipScheduleRows.insert(clip.rowId);
    RoutedClipRenderItem item;
    item.clipId = clip.clipId;
    item.rowId = clip.rowId;
    item.isMidi = clip.isMidi;
    item.startSec = startSec;
    item.endSec = endSec;
    item.processor = std::move(processor);
    schedule.clipItemsById[clip.clipId] = item;
    routedClipItemsById[clip.clipId] = item;

    const long long firstBucket = routedClipBucketForTime(startSec);
    const long long lastBucket =
        routedClipBucketForTime(juce::jmax(startSec, endSec - 1.0e-9));

    for (long long bucket = firstBucket; bucket <= lastBucket; ++bucket)
    {
        auto &bucketItems = schedule.bucketItems[bucket];
        const auto existing = std::find_if(
            bucketItems.begin(),
            bucketItems.end(),
            [clipId = clip.clipId](const RoutedClipRenderItem &candidate)
            {
                return candidate.clipId == clipId;
            });
        if (existing == bucketItems.end())
        {
            bucketItems.push_back(item);
        }
    }

    requestRoutedClipSchedulePublishLocked();
}

void JuceEngine::removeClipFromRoutedSchedule(int rowId, int clipId)
{
    int resolvedRowId = rowId;
    RoutedClipRenderItem indexedItem;
    bool hasIndexedItem = false;
    if (const auto globalIt = routedClipItemsById.find(clipId);
        globalIt != routedClipItemsById.end())
    {
        indexedItem = globalIt->second;
        hasIndexedItem = true;
        resolvedRowId = globalIt->second.rowId;
    }
    routedClipItemsById.erase(clipId);
    dirtyRoutedClipScheduleRows.insert(resolvedRowId);

    auto rowIt = rowRoutedClipSchedules.find(resolvedRowId);
    if (rowIt == rowRoutedClipSchedules.end())
    {
        requestRoutedClipSchedulePublishLocked();
        return;
    }

    if (const auto clipIt = rowIt->second.clipItemsById.find(clipId);
        clipIt != rowIt->second.clipItemsById.end())
    {
        indexedItem = clipIt->second;
        hasIndexedItem = true;
        rowIt->second.clipItemsById.erase(clipIt);
    }

    auto &buckets = rowIt->second.bucketItems;
    if (hasIndexedItem && indexedItem.endSec > indexedItem.startSec)
    {
        const long long firstBucket =
            routedClipBucketForTime(juce::jmax(0.0, indexedItem.startSec));
        const long long lastBucket =
            routedClipBucketForTime(
                juce::jmax(indexedItem.startSec,
                           indexedItem.endSec - 1.0e-9));

        for (long long bucket = firstBucket; bucket <= lastBucket; ++bucket)
        {
            auto bucketIt = buckets.find(bucket);
            if (bucketIt == buckets.end())
                continue;

            auto &items = bucketIt->second;
            items.erase(
                std::remove_if(
                    items.begin(),
                    items.end(),
                    [clipId](const RoutedClipRenderItem &item)
                    {
                        return item.clipId == clipId;
                    }),
                items.end());
            if (items.empty())
                buckets.erase(bucketIt);
        }
    }
    else
    {
        for (auto bucketIt = buckets.begin(); bucketIt != buckets.end();)
        {
            auto &items = bucketIt->second;
            items.erase(
                std::remove_if(
                    items.begin(),
                    items.end(),
                    [clipId](const RoutedClipRenderItem &item)
                    {
                        return item.clipId == clipId;
                    }),
                items.end());
            if (items.empty())
                bucketIt = buckets.erase(bucketIt);
            else
                ++bucketIt;
        }
    }

    if (buckets.empty() && rowIt->second.clipItemsById.empty())
        rowRoutedClipSchedules.erase(rowIt);

    requestRoutedClipSchedulePublishLocked();
}

std::shared_ptr<juce::AudioProcessor> JuceEngine::liveProcessorSharedForClip(
    const ClipState &clip) const noexcept
{
    return std::atomic_load_explicit(
        &clip.playerProcessor,
        std::memory_order_acquire);
}

juce::AudioProcessor *JuceEngine::liveProcessorForClip(ClipState &clip) noexcept
{
    if (auto processor = liveProcessorSharedForClip(clip))
        return processor.get();
    return clip.playerNode != nullptr ? clip.playerNode->getProcessor() : nullptr;
}

const juce::AudioProcessor *JuceEngine::liveProcessorForClip(const ClipState &clip) const noexcept
{
    if (auto processor = liveProcessorSharedForClip(clip))
        return processor.get();
    return clip.playerNode != nullptr ? clip.playerNode->getProcessor() : nullptr;
}

TimelineClipProcessorBase *JuceEngine::timelineProcessorForClip(ClipState &clip) noexcept
{
    return asTimelineProcessor(liveProcessorForClip(clip));
}

void JuceEngine::prepareLiveClipProcessor(juce::AudioProcessor &processor)
{
    const double sampleRate =
        getKnownDeviceSampleRate(deviceManager, hostSampleRateAtomic.load(std::memory_order_relaxed));
    const int blockSize = getKnownDeviceBufferSize(deviceManager, 512);
    processor.setPlayConfigDetails(0, 2, sampleRate, blockSize);
    processor.prepareToPlay(sampleRate, blockSize);
}

void JuceEngine::releaseLiveClipProcessor(juce::AudioProcessor &processor)
{
    processor.releaseResources();
}

void JuceEngine::retireLiveClipProcessorLocked(std::shared_ptr<juce::AudioProcessor> processor)
{
    if (processor == nullptr)
        return;

    retiredLiveClipProcessors.push_back({
        std::move(processor),
        routedAudioRenderGeneration.load(std::memory_order_acquire)});
}

void JuceEngine::drainRetiredLiveClipProcessorsLocked()
{
    drainRetiredRoutedClipScheduleSnapshotsLocked();

    constexpr uint64_t kRetireAfterRenderGenerations = 8;
    const auto currentGeneration =
        routedAudioRenderGeneration.load(std::memory_order_acquire);

    for (auto it = retiredLiveClipProcessors.begin();
         it != retiredLiveClipProcessors.end();)
    {
        const bool renderGraceElapsed =
            currentGeneration >= it->retiredAtRenderGeneration &&
            (currentGeneration - it->retiredAtRenderGeneration) >=
                kRetireAfterRenderGenerations;
        if (!renderGraceElapsed || it->processor.use_count() > 1)
        {
            ++it;
            continue;
        }

        releaseLiveClipProcessor(*it->processor);
        it = retiredLiveClipProcessors.erase(it);
    }
}

void JuceEngine::prepareLiveClipProcessorsForCurrentDevice()
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    for (auto &clip : clips)
    {
        if (clip.alive)
        {
            if (auto processor = liveProcessorSharedForClip(clip))
                prepareLiveClipProcessor(*processor);
        }
    }
}

void JuceEngine::processRoutedClipsForRow(int rowId,
                                          const void *rowSchedule,
                                          juce::AudioBuffer<float> &buffer,
                                          juce::MidiBuffer &midi,
                                          juce::AudioBuffer<float> &scratchBuffer,
                                          juce::MidiBuffer &scratchMidi)
{
    juce::ignoreUnused(midi, rowId);

    const int numSamples = buffer.getNumSamples();
    if (numSamples <= 0)
        return;

    if (numSamples > scratchBuffer.getNumSamples())
    {
        jassertfalse;
        return;
    }

    const double sr = hostSampleRateAtomic.load(std::memory_order_relaxed);
    if (sr <= 0.0)
        return;

    const double blockStart = blockTransportStartSec.load(std::memory_order_relaxed);
    const double blockEnd = blockStart + ((double)numSamples / sr);

    std::array<const RoutedClipRenderItem *, kMaxClips> activeClipItems{};
    std::bitset<kMaxClips> activeClipPresent;
    int activeClipCount = 0;
    auto addActiveClipIfNeeded =
        [this,
         blockStart,
         blockEnd,
         &activeClipItems,
         &activeClipPresent,
         &activeClipCount](
            const RoutedClipRenderItem &item) noexcept
    {
        const int clipId = item.clipId;
        if (clipId < 0 || clipId >= kMaxClips)
            return;

        if (!routedClipMayRenderBlock(item, blockStart, blockEnd))
            return;

        const auto index = static_cast<size_t>(clipId);
        if (activeClipPresent.test(index))
            return;
        activeClipPresent.set(index);

        if (activeClipCount < kMaxClips)
            activeClipItems[(size_t)activeClipCount++] = &item;
    };

    const auto *schedule =
        static_cast<const RowRoutedClipSchedule *>(rowSchedule);
    if (schedule == nullptr)
        return;

    const long long firstBucket = routedClipBucketForTime(blockStart);
    const long long lastBucket =
        routedClipBucketForTime(juce::jmax(blockStart, blockEnd - 1.0e-9));
    const auto bucketBegin = std::lower_bound(
        schedule->bucketItems.begin(),
        schedule->bucketItems.end(),
        firstBucket,
        [](const RoutedClipBucketItems &bucket,
           long long targetBucket) noexcept
        {
            return bucket.bucket < targetBucket;
        });

    for (auto bucketIt = bucketBegin;
         bucketIt != schedule->bucketItems.end() && bucketIt->bucket <= lastBucket;
         ++bucketIt)
    {
        for (const auto &item : bucketIt->items)
            addActiveClipIfNeeded(item);
    }

    const int liveMidiClipId =
        liveMidiInputTargetClip.load(std::memory_order_relaxed);
    if (const auto *item = schedule->findClip(liveMidiClipId))
        addActiveClipIfNeeded(*item);

    if (activeClipCount <= 0)
        return;

    for (int activeIndex = 0; activeIndex < activeClipCount; ++activeIndex)
    {
        const auto *item = activeClipItems[(size_t)activeIndex];
        if (item == nullptr)
            continue;

        auto *processor = item->processor.get();
        if (processor == nullptr)
            continue;

        scratchBuffer.clear();
        scratchMidi.clear();
        processor->processBlock(scratchBuffer, scratchMidi);

        const int channelsToMix =
            juce::jmin(buffer.getNumChannels(), scratchBuffer.getNumChannels());
        for (int ch = 0; ch < channelsToMix; ++ch)
            buffer.addFrom(ch, 0, scratchBuffer, ch, 0, numSamples);
    }
}

// ============================================================
// Row-level gain / mute / pan
// ============================================================
void JuceEngine::setRowGain(int row, float gain)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    if (row < 0 || row >= (int)rows.size())
        return;

    rows[(size_t)row].gainUi = juce::jlimit(kGainUiMin, kGainUiMax, gain);
    if (rows[(size_t)row].gainProc != nullptr)
        rows[(size_t)row].gainProc->gain->setValueNotifyingHost(
            rows[(size_t)row].gainUi / kGainUiMax);
    publishAutomationSnapshotLocked();
}

void JuceEngine::muteRow(int row, bool mute)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    if (row < 0 || row >= (int)rows.size())
        return;

    rows[(size_t)row].muted = mute;
    if (rows[(size_t)row].gainProc != nullptr)
        rows[(size_t)row].gainProc->setMuted(mute);
    publishAutomationSnapshotLocked();
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
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    if (row < 0 || row >= (int)rows.size())
        return;

    rows[(size_t)row].panUi = pan;
    if (rows[(size_t)row].panProc != nullptr)
        rows[(size_t)row].panProc->pan->setValueNotifyingHost(panUIToNormalized(pan));
    publishAutomationSnapshotLocked();
}

void JuceEngine::configureTrackGroups(const juce::Array<juce::NamedValueSet> &groups)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    juce::StringArray seenIds;
    for (const auto &entry : groups)
    {
        const auto groupId = entry["id"].toString().trim();
        if (groupId.isEmpty())
            continue;

        auto *group = trackGroupForId(groupId);
        if (group == nullptr)
        {
            TrackGroupState next;
            next.id = groupId;
            trackGroups.push_back(std::move(next));
            group = &trackGroups.back();
        }

        seenIds.addIfNotAlreadyThere(groupId);
        group->rowIds.clear();
        if (auto *array = entry["rowIds"].getArray())
        {
            for (const auto &value : *array)
            {
                const int rowId = (int)value;
                if (rowId >= 0)
                    group->rowIds.addIfNotAlreadyThere(rowId);
            }
        }
        group->gainUi = juce::jlimit(kGainUiMin, kGainUiMax, (float)entry["gain"]);
        group->panUi = juce::jlimit(0.0f, 1.0f, (float)entry["pan"]);
        group->muted = (bool)entry["muted"];
        group->soloed = (bool)entry["soloed"];

        if (busGraphInitialised)
        {
            ensureTrackGroupBusNodesAttached(*group, juce::AudioProcessorGraph::UpdateKind::none);
            if (group->gainProc != nullptr)
            {
                group->gainProc->gain->setValueNotifyingHost(group->gainUi / kGainUiMax);
                group->gainProc->setMuted(group->muted);
            }
            if (group->panProc != nullptr)
                group->panProc->pan->setValueNotifyingHost(panUIToNormalized(group->panUi));
        }
    }

    for (auto it = trackGroups.begin(); it != trackGroups.end();)
    {
        if (seenIds.contains(it->id))
        {
            ++it;
            continue;
        }

        for (auto fx : it->fxChain)
            if (graph.getNodeForId(fx) != nullptr)
                graph.removeNode(fx, juce::AudioProcessorGraph::UpdateKind::none);
        if (it->inputNode)
            graph.removeNode(it->inputNode->nodeID, juce::AudioProcessorGraph::UpdateKind::none);
        if (it->gainNode)
            graph.removeNode(it->gainNode->nodeID, juce::AudioProcessorGraph::UpdateKind::none);
        if (it->panNode)
            graph.removeNode(it->panNode->nodeID, juce::AudioProcessorGraph::UpdateKind::none);
        if (it->meterTapNode)
            graph.removeNode(it->meterTapNode->nodeID, juce::AudioProcessorGraph::UpdateKind::none);
        it = trackGroups.erase(it);
    }

    reconnectAllRowOutputsToBuses(juce::AudioProcessorGraph::UpdateKind::none);
    retargetRowMeterTapPointers();
    publishMeterReadoutSnapshotLocked();
    commitGraphMutationLocked();
}

void JuceEngine::assignRowToGroup(int row, const juce::String &groupId)
{
    if (row < 0 || row >= (int)rows.size())
        return;
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    const int rowId = rows[(size_t)row].rowId;
    for (auto &group : trackGroups)
        group.rowIds.removeAllInstancesOf(rowId);
    if (auto *group = trackGroupForId(groupId))
        group->rowIds.addIfNotAlreadyThere(rowId);
    reconnectAllRowOutputsToBuses(juce::AudioProcessorGraph::UpdateKind::none);
    publishMeterReadoutSnapshotLocked();
    commitGraphMutationLocked();
}

void JuceEngine::setTrackGroupMixState(const juce::String &groupId,
                                       float gain,
                                       float pan,
                                       bool muted,
                                       bool soloed)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    auto *group = trackGroupForId(groupId);
    if (group == nullptr)
        return;
    group->gainUi = juce::jlimit(kGainUiMin, kGainUiMax, gain);
    group->panUi = juce::jlimit(0.0f, 1.0f, pan);
    group->muted = muted;
    group->soloed = soloed;
    ensureTrackGroupBusNodesAttached(*group);
    if (group->gainProc != nullptr)
    {
        group->gainProc->gain->setValueNotifyingHost(group->gainUi / kGainUiMax);
        group->gainProc->setMuted(group->muted);
    }
    if (group->panProc != nullptr)
        group->panProc->pan->setValueNotifyingHost(panUIToNormalized(group->panUi));
}

// ============================================================
// Master bus FX
// ============================================================
bool JuceEngine::insertMasterEffect(const juce::String &pluginPath)
{
    constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;
    const auto requestedId = pluginPath.trim();
    const bool isBuiltInMixroomPlugin = mixroomPlugins.contains(requestedId);

    if (requestedId.isEmpty())
    {
        juceLogToFlutter("insertMasterEffect: empty plugin identifier");
        return false;
    }

    const auto sr = getKnownDeviceSampleRate(
        deviceManager,
        hostSampleRateAtomic.load(std::memory_order_relaxed));
    const auto bs = getKnownDeviceBufferSize(deviceManager, 512);

    juce::String error;
    std::unique_ptr<juce::AudioProcessor> builtInPlugin;
    std::unique_ptr<juce::AudioPluginInstance> externalPlugin;

    if (isBuiltInMixroomPlugin)
    {
        builtInPlugin = createEffectProcessorFromIdentifier(
            pluginFormatManager,
            pluginList,
            requestedId,
            sr,
            bs,
            error);
        if (builtInPlugin == nullptr)
        {
            juceLogToFlutter(("insertMasterEffect failed for built-in '" +
                              requestedId + "': " + error)
                                 .toRawUTF8());
            return false;
        }
    }
    else
    {
        juce::PluginDescription desc;
        const bool resolved = resolveKnownPluginDescription(pluginList, requestedId, desc);
        if (!resolved)
        {
            desc.fileOrIdentifier = requestedId;
#if JUCE_IOS
            desc.pluginFormatName = "AudioUnit";
#endif
        }

        try
        {
            externalPlugin = pluginFormatManager.createPluginInstance(desc, sr, bs, error);
        }
        catch (const std::exception &e)
        {
            error = "exception: " + juce::String(e.what());
        }
        catch (...)
        {
            error = "unknown exception";
        }

        if (externalPlugin == nullptr)
        {
            juceLogToFlutter(("insertMasterEffect failed for '" +
                              requestedId + "': " + error)
                                 .toRawUTF8());
            return false;
        }
    }

    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (!masterEffectChain)
        masterEffectChain = new juce::Array<AudioProcessorGraph::NodeID>();
    compactMasterFxChain();

    std::unique_ptr<juce::AudioProcessor> processorToInsert;
    if (isBuiltInMixroomPlugin)
        processorToInsert = std::move(builtInPlugin);
    else
        processorToInsert = std::move(externalPlugin);

    auto pluginNode = graph.addNode(std::move(processorToInsert), std::nullopt, batchUpdate);
    if (pluginNode == nullptr)
    {
        juceLogToFlutter(("insertMasterEffect: graph.addNode failed for '" + requestedId + "'").toRawUTF8());
        return false;
    }

    masterEffectChain->add(pluginNode->nodeID);
    masterEffectIds.add(requestedId);
    if (graphMutationBatchDepth > 0)
        markGraphMutationBatchMasterFxDirtyLocked();
    else
        rewireMasterFxChain(batchUpdate);
    commitGraphMutationLocked();
    return true;
}

void JuceEngine::removeMasterEffect(int effectIndex)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;

    if (!masterEffectChain)
        return;
    compactMasterFxChain();

    if (effectIndex < 0 || effectIndex >= masterEffectChain->size())
        return;

    const auto nodeID = masterEffectChain->getReference(effectIndex);

    masterEffectChain->removeRange(effectIndex, 1);
    if (effectIndex >= 0 && effectIndex < masterEffectIds.size())
        masterEffectIds.removeRange(effectIndex, 1);

    masterEffectAutomationLanes.erase(
        std::remove_if(
            masterEffectAutomationLanes.begin(),
            masterEffectAutomationLanes.end(),
            [effectIndex](const RowState::TrackEffectAutomationLane &lane)
            { return lane.effectIndex == effectIndex; }),
        masterEffectAutomationLanes.end());
    for (auto &lane : masterEffectAutomationLanes)
    {
        if (lane.effectIndex > effectIndex)
            lane.effectIndex -= 1;
        lane.lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
    }
    publishAutomationSnapshotLocked();

    if (graphMutationBatchDepth > 0)
        markGraphMutationBatchMasterFxDirtyLocked();
    else
        rewireMasterFxChain(batchUpdate);

    juce::Array<AudioProcessorGraph::Connection> nodeConnections;
    for (const auto &connection : graph.getConnections())
    {
        if (connection.source.nodeID == nodeID ||
            connection.destination.nodeID == nodeID)
            nodeConnections.addIfNotAlreadyThere(connection);
    }
    for (const auto &connection : nodeConnections)
        graph.removeConnection(connection, batchUpdate);
    if (graph.getNodeForId(nodeID) != nullptr)
        graph.removeNode(nodeID, batchUpdate);
    commitGraphMutationLocked();
}

void JuceEngine::reorderMasterEffects(int fromIndex, int toIndex)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

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

    const int finalToIndex = toIndex;
    for (auto &lane : masterEffectAutomationLanes)
    {
        const int idx = lane.effectIndex;
        if (idx == fromIndex)
        {
            lane.effectIndex = finalToIndex;
        }
        else if (fromIndex < finalToIndex)
        {
            if (idx > fromIndex && idx <= finalToIndex)
                lane.effectIndex = idx - 1;
        }
        else if (fromIndex > finalToIndex)
        {
            if (idx >= finalToIndex && idx < fromIndex)
                lane.effectIndex = idx + 1;
        }
        lane.lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
    }
    publishAutomationSnapshotLocked();

    if (graphMutationBatchDepth > 0)
        markGraphMutationBatchMasterFxDirtyLocked();
    else
        rewireMasterFxChain(juce::AudioProcessorGraph::UpdateKind::none);
    commitGraphMutationLocked();
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

juce::StringArray JuceEngine::getMasterEffectIds()
{
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
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

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
        bool matchesParam = (p->getName(128) == paramName);
        if (!matchesParam)
            if (auto *withID = dynamic_cast<juce::AudioProcessorParameterWithID *>(p))
                matchesParam = (withID->paramID == paramName);

        if (!matchesParam)
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
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

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

    if (effectIndex < 0 || effectIndex >= masterEffectChain->size())
        return false;

    auto nodeID = masterEffectChain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    return node ? node->isBypassed() : false;
}

void JuceEngine::setMasterGain(float gain)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    masterGainUi = juce::jlimit(kGainUiMin, kGainUiMax, gain);
    if (masterGainProcessor)
        masterGainProcessor->gain->setValueNotifyingHost(
            masterGainUi / kGainUiMax);
    publishAutomationSnapshotLocked();
}

void JuceEngine::muteMaster(bool mute)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    masterMuted = mute;
    if (masterGainProcessor)
        masterGainProcessor->setMuted(mute);
    publishAutomationSnapshotLocked();
}

void JuceEngine::setMasterPan(float pan)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    masterPanUi = juce::jlimit(0.0f, 1.0f, pan);
    if (masterPanProcessor)
        masterPanProcessor->pan->setValueNotifyingHost(
            panUIToNormalized(masterPanUi));
    publishAutomationSnapshotLocked();
}

// ============================================================
// Master FX Chain Rewire
// ============================================================
void JuceEngine::rewireMasterFxChain(
    juce::AudioProcessorGraph::UpdateKind updateKind)
{
    if (!masterInputNode || !masterGainNode || !masterPanNode || !outputNode)
        return;
    if (!masterEffectChain)
        masterEffectChain = new juce::Array<AudioProcessorGraph::NodeID>();

    compactMasterFxChain();

    juce::Array<AudioProcessorGraph::NodeID> localNodes;
    localNodes.add(masterInputNode->nodeID);
    localNodes.add(masterGainNode->nodeID);
    localNodes.add(masterPanNode->nodeID);
    localNodes.add(outputNode->nodeID);
    for (auto fx : *masterEffectChain)
        localNodes.addIfNotAlreadyThere(fx);
    clearStereoConnectionsBetweenNodes(graph, localNodes, updateKind);

    auto prevNodeId = masterInputNode->nodeID;
    for (auto fx : *masterEffectChain)
    {
        if (graph.getNodeForId(fx) == nullptr)
            continue;
        connectStereo(graph, prevNodeId, fx, updateKind);
        prevNodeId = fx;
    }

    connectStereo(graph, prevNodeId, masterGainNode->nodeID, updateKind);
    connectStereo(graph, masterGainNode->nodeID, masterPanNode->nodeID, updateKind);
    connectStereo(graph, masterPanNode->nodeID, outputNode->nodeID, updateKind);

    if (!isProjectClipLoadTransactionActive() &&
        graphMutationBatchDepth <= 0)
        armOutputSafetyForCurrentRoute();
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
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)clipIndex];
    if (!c.alive || liveProcessorForClip(c) == nullptr)
        return;

    c.gainUi = juce::jlimit(kGainUiMin, kGainUiMax, gain);

    if (auto *p = timelineProcessorForClip(c))
        p->setGainUi(c.gainUi);
}

void JuceEngine::setClipExtraGainLinear(int clipIndex, float gainLinear)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)clipIndex];
    if (!c.alive || liveProcessorForClip(c) == nullptr)
        return;

    c.extraGainLinear = juce::jlimit(0.0f, 64.0f, gainLinear);

    if (auto *p = timelineProcessorForClip(c))
        p->setExtraGainLinear(c.extraGainLinear);
}

void JuceEngine::muteClip(int clipIndex, bool shouldMute)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)clipIndex];
    if (!c.alive || liveProcessorForClip(c) == nullptr)
        return;

    c.muted = shouldMute;

    if (auto *p = timelineProcessorForClip(c))
        p->setMuted(shouldMute);
}

void JuceEngine::setClipPan(int clipIndex, float pan)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)clipIndex];
    if (!c.alive || liveProcessorForClip(c) == nullptr)
        return;

    c.panNormalized = panUIToNormalized(pan);

    if (auto *p = timelineProcessorForClip(c))
        p->setPanNormalized(c.panNormalized);
}

void JuceEngine::setClipPitch(int clipIndex, float semitones)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)clipIndex];
    if (!c.alive || liveProcessorForClip(c) == nullptr)
        return;

    c.pitchSemitones = juce::jlimit(-24.0f, 24.0f, semitones);

    if (auto *p = timelineProcessorForClip(c))
        p->setPitchSemitones(c.pitchSemitones);
}

void JuceEngine::setClipReversed(int clipIndex, bool shouldReverse)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)clipIndex];
    if (!c.alive || liveProcessorForClip(c) == nullptr)
        return;

    c.reversed = shouldReverse;

    if (auto *p = timelineProcessorForClip(c))
        p->setReversed(c.reversed);
}

void JuceEngine::setClipStretchOptions(int clipIndex, double tempoRatio, bool preservePitch)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)clipIndex];
    if (!c.alive || liveProcessorForClip(c) == nullptr)
        return;

    c.tempoRatio = juce::jlimit(0.05, 20.0, tempoRatio);
    c.preservePitch = preservePitch;

    if (auto *p = timelineProcessorForClip(c))
        p->setStretchOptions(c.tempoRatio, c.preservePitch);
}

juce::Array<juce::NamedValueSet> JuceEngine::getTrackPluginParameterInfo(int row, int effectIndex, bool forceIndividualRow)
{
    // juceLogToFlutter("Hello from JuceEngine::getTrackPluginParameterInfo");
    juce::Array<juce::NamedValueSet> results;

    if (row < 0 || row >= (int)rows.size())
        return results;

    auto *chainPtr = effectChainForRowApi(row, forceIndividualRow);
    if (chainPtr == nullptr)
        return results;
    auto &chain = *chainPtr;
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
            if (auto *withID = dynamic_cast<juce::AudioProcessorParameterWithID *>(p))
                e.set("id", withID->paramID);
            else
                e.set("id", p->getName(128));
            e.set("name", p->getName(128));
            e.set("unit", p->getLabel());

            if (auto *fp = dynamic_cast<juce::AudioParameterFloat *>(p))
            {
                e.set("type", "float");
                e.set("min", fp->range.start);
                e.set("max", fp->range.end);
                e.set("interval", fp->range.interval);
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
            if (auto *withID = dynamic_cast<juce::AudioProcessorParameterWithID *>(p))
                e.set("id", withID->paramID);
            else
                e.set("id", p->getName(128));
            e.set("name", p->getName(128));
            e.set("unit", p->getLabel());

            if (auto *fp = dynamic_cast<juce::AudioParameterFloat *>(p))
            {
                e.set("type", "float");
                e.set("min", fp->range.start);
                e.set("max", fp->range.end);
                e.set("interval", fp->range.interval);
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
    mixroom::fx::setGlobalTempoBpm(bpm);
    if (metronomeCallback)
        metronomeCallback->setBpm(bpm);
}

void JuceEngine::setMetronomeTimeSignature(int numerator, int denominator)
{
    if (metronomeCallback)
        metronomeCallback->setTimeSignature(numerator, denominator);
}

void JuceEngine::setMetronomeTransportMs(double ms)
{
    if (metronomeCallback)
        metronomeCallback->setTransportMs(ms);
}

namespace
{
constexpr double kPromptAnalysisSampleRate = 16000.0;
constexpr int kPromptStatsWindowSamples = 12000;
constexpr int kPromptStatsWindowCount = 6;
constexpr int kPromptStatsMaxSamples = kPromptStatsWindowSamples * kPromptStatsWindowCount;

struct PromptShortTermRmsStats
{
    double mean = 0.0;
    double p95 = 0.0;
    double std = 0.0;
    double transientDensity = 0.0;
};

struct PromptLufsStats
{
    double integratedLufs = -120.0;
    double shortMeanLufs = -120.0;
    double shortP95Lufs = -120.0;
    double lra = 0.0;
};

double clamp01(double value)
{
    return juce::jlimit(0.0, 1.0, value);
}

double percentileSorted(const std::vector<double> &sorted, double q)
{
    if (sorted.empty())
        return 0.0;
    if (sorted.size() == 1)
        return sorted.front();

    const double qq = juce::jlimit(0.0, 1.0, q);
    const double pos = qq * (double)(sorted.size() - 1);
    const int lo = (int)std::floor(pos);
    const int hi = (int)std::ceil(pos);
    if (lo == hi)
        return sorted[(size_t)lo];

    const double t = pos - (double)lo;
    return sorted[(size_t)lo] * (1.0 - t) + sorted[(size_t)hi] * t;
}

double linearToDb(double linear)
{
    return 20.0 * std::log10(std::max(linear, 1.0e-9));
}

double goertzelMag(const std::vector<float> &x, double fs, double freq)
{
    const double w = 2.0 * juce::MathConstants<double>::pi * (freq / fs);
    const double cosw = std::cos(w);
    const double sinw = std::sin(w);
    const double coeff = 2.0 * cosw;

    double s0 = 0.0;
    double s1 = 0.0;
    double s2 = 0.0;
    for (const float sample : x)
    {
        s0 = (double)sample + coeff * s1 - s2;
        s2 = s1;
        s1 = s0;
    }

    const double real = s1 - s2 * cosw;
    const double imag = s2 * sinw;
    return std::sqrt(real * real + imag * imag);
}

PromptShortTermRmsStats windowedRmsStats(const std::vector<float> &x, int frameSize, int hop)
{
    PromptShortTermRmsStats out;
    if (x.empty() || frameSize <= 0 || hop <= 0)
        return out;

    std::vector<double> frames;
    for (int start = 0; start < (int)x.size(); start += hop)
    {
        const int end = juce::jmin(start + frameSize, (int)x.size());
        if (end <= start)
            break;

        double sumSq = 0.0;
        for (int i = start; i < end; ++i)
        {
            const double v = (double)x[(size_t)i];
            sumSq += v * v;
        }

        frames.push_back(juce::jlimit(0.0, 1.0, std::sqrt(sumSq / (double)(end - start))));
        if (end == (int)x.size())
            break;
    }

    if (frames.empty())
        return out;

    const double mean = std::accumulate(frames.begin(), frames.end(), 0.0) / (double)frames.size();
    double varAcc = 0.0;
    for (const double v : frames)
    {
        const double d = v - mean;
        varAcc += d * d;
    }

    std::vector<double> sorted = frames;
    std::sort(sorted.begin(), sorted.end());

    int transientCount = 0;
    for (size_t i = 1; i < frames.size(); ++i)
    {
        if ((frames[i] - frames[i - 1]) > 0.06)
            transientCount++;
    }

    out.mean = juce::jlimit(0.0, 1.0, mean);
    out.p95 = juce::jlimit(0.0, 1.0, percentileSorted(sorted, 0.95));
    out.std = juce::jlimit(0.0, 1.0, std::sqrt(varAcc / (double)frames.size()));
    out.transientDensity = juce::jlimit(0.0, 1.0, (double)transientCount / (double)juce::jmax(1, (int)frames.size() - 1));
    return out;
}

PromptLufsStats lufsStats16k(const std::vector<float> &x)
{
    PromptLufsStats out;
    if (x.empty())
        return out;

    std::vector<double> kw((size_t)x.size(), 0.0);
    kw[0] = (double)x[0];
    for (size_t i = 1; i < x.size(); ++i)
        kw[i] = (double)x[i] - (0.97 * (double)x[i - 1]);

    double sumSq = 0.0;
    for (const double v : kw)
        sumSq += v * v;

    const double meanSq = sumSq / (double)juce::jmax(1, (int)kw.size());
    out.integratedLufs = juce::jlimit(-120.0, 0.0, -0.691 + 10.0 * std::log10(std::max(meanSq, 1.0e-12)));

    constexpr int frame = 6400;
    constexpr int hop = 3200;
    std::vector<double> shortLufs;
    for (int s = 0; s < (int)kw.size(); s += hop)
    {
        const int e = juce::jmin(s + frame, (int)kw.size());
        if (e <= s)
            break;

        double ss = 0.0;
        for (int i = s; i < e; ++i)
        {
            const double v = kw[(size_t)i];
            ss += v * v;
        }

        const double ms = ss / (double)(e - s);
        shortLufs.push_back(juce::jlimit(-120.0, 0.0, -0.691 + 10.0 * std::log10(std::max(ms, 1.0e-12))));
        if (e == (int)kw.size())
            break;
    }

    if (shortLufs.empty())
    {
        out.shortMeanLufs = out.integratedLufs;
        out.shortP95Lufs = out.integratedLufs;
        out.lra = 0.0;
        return out;
    }

    std::vector<double> sorted = shortLufs;
    std::sort(sorted.begin(), sorted.end());
    const double mean = std::accumulate(shortLufs.begin(), shortLufs.end(), 0.0) / (double)shortLufs.size();
    const double p95 = percentileSorted(sorted, 0.95);
    const double p10 = percentileSorted(sorted, 0.10);
    out.shortMeanLufs = juce::jlimit(-120.0, 0.0, mean);
    out.shortP95Lufs = juce::jlimit(-120.0, 0.0, p95);
    out.lra = juce::jlimit(0.0, 40.0, p95 - p10);
    return out;
}

double spectralFlatness(const std::vector<std::pair<double, double>> &mags)
{
    if (mags.empty())
        return 0.0;

    double logSum = 0.0;
    double arith = 0.0;
    for (const auto &[_, mag] : mags)
    {
        const double safe = std::max(mag, 1.0e-12);
        logSum += std::log(safe);
        arith += safe;
    }

    const double geo = std::exp(logSum / (double)mags.size());
    const double arithMean = arith / (double)mags.size();
    return juce::jlimit(0.0, 1.0, geo / std::max(arithMean, 1.0e-12));
}

double spectralRolloffHz(const std::vector<std::pair<double, double>> &mags, double pct)
{
    if (mags.empty())
        return 0.0;

    double total = 0.0;
    for (const auto &[_, mag] : mags)
        total += mag;
    if (total <= 1.0e-12)
        return 0.0;

    const double target = total * juce::jlimit(0.0, 1.0, pct);
    double acc = 0.0;
    for (const auto &[freq, mag] : mags)
    {
        acc += mag;
        if (acc >= target)
            return freq;
    }
    return mags.back().first;
}

double spectralSlope(const std::vector<std::pair<double, double>> &mags)
{
    if (mags.size() < 2)
        return 0.0;

    std::vector<double> xs;
    std::vector<double> ys;
    xs.reserve(mags.size());
    ys.reserve(mags.size());
    for (const auto &[freq, mag] : mags)
    {
        xs.push_back(std::log(std::max(freq, 1.0)));
        ys.push_back(std::log(std::max(mag, 1.0e-12)));
    }

    const double mx = std::accumulate(xs.begin(), xs.end(), 0.0) / (double)xs.size();
    const double my = std::accumulate(ys.begin(), ys.end(), 0.0) / (double)ys.size();
    double num = 0.0;
    double den = 0.0;
    for (size_t i = 0; i < xs.size(); ++i)
    {
        const double dx = xs[i] - mx;
        num += dx * (ys[i] - my);
        den += dx * dx;
    }
    if (den <= 1.0e-12)
        return 0.0;
    return num / den;
}

double spectralBandwidthHz(const std::vector<std::pair<double, double>> &mags, double centroidHz)
{
    if (mags.empty())
        return 0.0;

    double total = 0.0;
    double num = 0.0;
    for (const auto &[freq, mag] : mags)
    {
        total += mag;
        const double d = freq - centroidHz;
        num += mag * d * d;
    }
    if (total <= 1.0e-12)
        return 0.0;
    return std::sqrt(num / total);
}

double onsetRateHz(const std::vector<float> &x, double sampleRate)
{
    if (x.size() < 1024 || sampleRate <= 0.0)
        return 0.0;

    constexpr int frame = 512;
    constexpr int hop = 256;
    std::vector<double> frameRms;
    for (int s = 0; s + frame <= (int)x.size(); s += hop)
    {
        double sumSq = 0.0;
        for (int i = s; i < s + frame; ++i)
        {
            const double v = (double)x[(size_t)i];
            sumSq += v * v;
        }
        frameRms.push_back(std::sqrt(sumSq / (double)frame));
    }

    if (frameRms.size() < 2)
        return 0.0;

    int onsets = 0;
    for (size_t i = 1; i < frameRms.size(); ++i)
    {
        const double delta = frameRms[i] - frameRms[i - 1];
        if (delta > 0.06 && frameRms[i] > 0.02)
            onsets++;
    }

    const double durationSec = (double)x.size() / sampleRate;
    if (durationSec <= 1.0e-6)
        return 0.0;
    return onsets / durationSec;
}

double spectralFluxProxy(const std::vector<float> &x, double fs)
{
    if (x.size() < 1024)
        return 0.0;

    constexpr double freqs[] = {100.0, 250.0, 500.0, 1000.0, 3000.0, 6000.0};
    constexpr int frame = 512;
    constexpr int hop = 256;
    std::vector<double> prev;
    double fluxAcc = 0.0;
    int count = 0;

    for (int s = 0; s + frame <= (int)x.size(); s += hop)
    {
        std::vector<float> chunk(x.begin() + s, x.begin() + s + frame);
        std::vector<double> cur;
        cur.reserve(std::size(freqs));
        for (const double f : freqs)
            cur.push_back(goertzelMag(chunk, fs, f));

        if (!prev.empty())
        {
            double ss = 0.0;
            for (size_t i = 0; i < cur.size(); ++i)
            {
                const double d = cur[i] - prev[i];
                if (d > 0.0)
                    ss += d * d;
            }
            fluxAcc += std::sqrt(ss / (double)cur.size());
            count++;
        }
        prev = cur;
    }

    if (count == 0)
        return 0.0;
    return juce::jlimit(0.0, 1.0, fluxAcc / (double)count / 2.5);
}

std::vector<double> keyChroma16k(const std::vector<float> &x, double fs)
{
    constexpr int chromaBins = 12;
    constexpr int minMidi = 36; // C2
    constexpr int maxMidi = 84; // C6
    std::vector<double> chroma((size_t)chromaBins, 0.0);
    if (x.size() < 2048 || fs <= 0.0)
        return chroma;

    double sumSq = 0.0;
    for (const float sample : x)
        sumSq += (double)sample * (double)sample;
    const double rms = std::sqrt(sumSq / (double)juce::jmax(1, (int)x.size()));
    if (rms < 0.003)
        return chroma;

    for (int midi = minMidi; midi <= maxMidi; ++midi)
    {
        const double freq = 440.0 * std::pow(2.0, ((double)midi - 69.0) / 12.0);
        if (freq <= 45.0 || freq >= fs * 0.45)
            continue;
        const double mag = goertzelMag(x, fs, freq);
        chroma[(size_t)(midi % chromaBins)] += (mag * mag) / std::sqrt(freq);
    }

    const double floor = *std::min_element(chroma.begin(), chroma.end());
    for (double &value : chroma)
        value = std::max(0.0, value - floor * 0.75);

    const double peak = *std::max_element(chroma.begin(), chroma.end());
    if (peak <= 1.0e-12)
        return std::vector<double>((size_t)chromaBins, 0.0);

    double sum = 0.0;
    for (double &value : chroma)
    {
        value = std::sqrt(value / peak);
        sum += value;
    }
    if (sum <= 1.0e-12)
        return std::vector<double>((size_t)chromaBins, 0.0);

    for (double &value : chroma)
        value = juce::jlimit(0.0, 1.0, value / sum);
    return chroma;
}

int estimateOutputSamples(const juce::AudioFormatReader &reader, int inputSamples)
{
    if (inputSamples <= 0)
        return 0;
    if (reader.sampleRate == kPromptAnalysisSampleRate)
        return inputSamples;
    const double speedRatio = reader.sampleRate / kPromptAnalysisSampleRate;
    return juce::jmax(0, (int)std::ceil((double)inputSamples / speedRatio));
}

std::pair<int, int> promptAnalysisOutputRange(
    int totalOutputSamples,
    double trimStartMs,
    double trimEndMs)
{
    if (totalOutputSamples <= 0)
        return {0, 0};

    const int startSample = juce::jlimit(
        0,
        totalOutputSamples,
        (int)std::floor(juce::jmax(0.0, trimStartMs) * (kPromptAnalysisSampleRate / 1000.0)));
    int endSample = totalOutputSamples;
    if (trimEndMs > trimStartMs)
    {
        endSample = juce::jlimit(
            startSample,
            totalOutputSamples,
            (int)std::ceil(juce::jmax(trimStartMs, trimEndMs) * (kPromptAnalysisSampleRate / 1000.0)));
    }

    if (endSample <= startSample)
        endSample = totalOutputSamples;

    return {startSample, endSample};
}

std::vector<float> decodeMono16kWindow(juce::AudioFormatReader &reader, int totalInputSamples, int outputStartSample, int outputSamples)
{
    std::vector<float> out((size_t)juce::jmax(0, outputSamples), 0.0f);
    if (out.empty() || totalInputSamples <= 0)
        return out;

    if (reader.sampleRate == kPromptAnalysisSampleRate)
    {
        const int inputStart = juce::jlimit(0, totalInputSamples, outputStartSample);
        const int inputToRead = juce::jlimit(0, totalInputSamples - inputStart, outputSamples);
        if (inputToRead <= 0)
            return out;

        juce::AudioBuffer<float> mono(1, inputToRead);
        reader.read(&mono, 0, inputToRead, inputStart, true, false);
        std::memcpy(out.data(), mono.getReadPointer(0), (size_t)inputToRead * sizeof(float));
        return out;
    }

    const double speedRatio = reader.sampleRate / kPromptAnalysisSampleRate;
    const int inputStart = juce::jlimit(0, totalInputSamples, (int)std::floor((double)outputStartSample * speedRatio));
    const int inputNeeded = juce::jmax(1, (int)std::ceil((double)outputSamples * speedRatio) + 8);
    const int inputToRead = juce::jlimit(0, totalInputSamples - inputStart, inputNeeded);
    if (inputToRead <= 0)
        return out;

    juce::AudioBuffer<float> mono(1, inputToRead);
    reader.read(&mono, 0, inputToRead, inputStart, true, false);

    juce::LagrangeInterpolator resampler;
    resampler.reset();
    resampler.process(
        speedRatio,
        mono.getReadPointer(0),
        out.data(),
        outputSamples,
        mono.getNumSamples(),
        0);

    return out;
}

juce::NamedValueSet analyzePromptStatsFromMono(const std::vector<float> &pcm, const juce::NamedValueSet &stereoStats)
{
    juce::NamedValueSet out;
    auto putDefaults = [&]()
    {
        out.set("centroid_hz", 0.0);
        out.set("zcr", 0.0);
        out.set("hf_rms", 0.0);
        out.set("st_rms_mean", 0.0);
        out.set("st_rms_p95", 0.0);
        out.set("st_rms_std", 0.0);
        out.set("transient_density", 0.0);
        out.set("true_peak_dbfs", -120.0);
        out.set("integrated_lufs_est", -120.0);
        out.set("short_lufs_mean", -120.0);
        out.set("short_lufs_p95", -120.0);
        out.set("lra_est", 0.0);
        out.set("clip_ratio", 0.0);
        out.set("spectral_flatness", 0.0);
        out.set("spectral_rolloff_hz", 0.0);
        out.set("spectral_slope", 0.0);
        out.set("spectral_flux", 0.0);
        out.set("spectral_bandwidth_hz", 0.0);
        out.set("silence_ratio", 0.0);
        out.set("activity_ratio", 0.0);
        out.set("onset_rate_hz", 0.0);
        out.set("noise_floor_dbfs", -120.0);
        out.set("phase_corr", 1.0);
        out.set("side_ratio", 0.0);
        out.set("stereo_imbalance", 0.0);
        out.set("low", 0.0);
        out.set("lowmid", 0.0);
        out.set("mid", 0.0);
        out.set("high", 0.0);
        out.set("sibilance", 0.0);
        out.set("bassiness", 0.0);
        for (int i = 0; i < 12; ++i)
            out.set(juce::String("key_pc_") + juce::String(i), 0.0);
    };

    if (pcm.empty())
    {
        putDefaults();
        return out;
    }

    const int n = juce::jmin((int)pcm.size(), kPromptStatsMaxSamples);
    std::vector<float> x(pcm.begin(), pcm.begin() + n);

    double sumSq = 0.0;
    for (const float v : x)
        sumSq += (double)v * (double)v;
    const double baseRms = juce::jlimit(0.0, 1.0, std::sqrt(sumSq / (double)juce::jmax(1, n)));

    int zc = 0;
    for (int i = 1; i < n; ++i)
    {
        const float a = x[(size_t)(i - 1)];
        const float b = x[(size_t)i];
        if ((a >= 0.0f && b < 0.0f) || (a < 0.0f && b >= 0.0f))
            zc++;
    }
    const double zcr = juce::jlimit(0.0, 1.0, (double)zc / (double)juce::jmax(1, n - 1));

    double hfSumSq = 0.0;
    for (int i = 1; i < n; ++i)
    {
        const double hp = (double)x[(size_t)i] - (double)x[(size_t)(i - 1)];
        hfSumSq += hp * hp;
    }
    const double hfRaw = std::sqrt(hfSumSq / (double)juce::jmax(1, n - 1));
    const double hfRms = juce::jlimit(0.0, 1.0, hfRaw / (baseRms + 1.0e-9));

    const auto st = windowedRmsStats(x, 512, 256);
    const auto lufs = lufsStats16k(x);

    std::vector<std::pair<double, double>> mags;
    mags.reserve(7);
    mags.emplace_back(100.0, goertzelMag(x, kPromptAnalysisSampleRate, 100.0));
    mags.emplace_back(250.0, goertzelMag(x, kPromptAnalysisSampleRate, 250.0));
    mags.emplace_back(500.0, goertzelMag(x, kPromptAnalysisSampleRate, 500.0));
    mags.emplace_back(1000.0, goertzelMag(x, kPromptAnalysisSampleRate, 1000.0));
    mags.emplace_back(3000.0, goertzelMag(x, kPromptAnalysisSampleRate, 3000.0));
    mags.emplace_back(6000.0, goertzelMag(x, kPromptAnalysisSampleRate, 6000.0));
    mags.emplace_back(7500.0, goertzelMag(x, kPromptAnalysisSampleRate, 7500.0));

    const double low = mags[0].second + mags[1].second;
    const double lowmid = mags[2].second;
    const double mid = mags[3].second + mags[4].second;
    const double high = mags[5].second + mags[6].second;

    double centroidNum = 0.0;
    double centroidDen = 1.0e-9;
    for (const auto &[freq, mag] : mags)
    {
        centroidNum += freq * mag;
        centroidDen += mag;
    }
    const double centroidHz = juce::jlimit(0.0, 8000.0, centroidNum / centroidDen);

    const double sibilance = juce::jlimit(0.0, 5.0, high / (mid + lowmid + low + 1.0e-9));
    const double bassiness = juce::jlimit(0.0, 5.0, low / (mid + high + 1.0e-9));

    double truePeak = 0.0;
    int clipCount = 0;
    int silenceCount = 0;
    std::vector<double> absValues;
    absValues.reserve((size_t)n);
    for (const float sample : x)
    {
        const double absV = std::abs((double)sample);
        truePeak = std::max(truePeak, absV);
        if (absV >= 0.995)
            clipCount++;
        if (absV < 0.01)
            silenceCount++;
        absValues.push_back(absV);
    }
    std::sort(absValues.begin(), absValues.end());

    const double clipRatio = juce::jlimit(0.0, 1.0, (double)clipCount / (double)juce::jmax(1, n));
    const double silenceRatio = juce::jlimit(0.0, 1.0, (double)silenceCount / (double)juce::jmax(1, n));
    const double activityRatio = juce::jlimit(0.0, 1.0, 1.0 - silenceRatio);
    const double noiseFloorDbfs = juce::jlimit(-120.0, 0.0, linearToDb(percentileSorted(absValues, 0.10)));

    out.set("centroid_hz", centroidHz);
    out.set("zcr", zcr);
    out.set("hf_rms", hfRms);
    out.set("st_rms_mean", st.mean);
    out.set("st_rms_p95", st.p95);
    out.set("st_rms_std", st.std);
    out.set("transient_density", st.transientDensity);
    out.set("true_peak_dbfs", juce::jlimit(-120.0, 0.0, linearToDb(truePeak)));
    out.set("integrated_lufs_est", lufs.integratedLufs);
    out.set("short_lufs_mean", lufs.shortMeanLufs);
    out.set("short_lufs_p95", lufs.shortP95Lufs);
    out.set("lra_est", lufs.lra);
    out.set("clip_ratio", clipRatio);
    out.set("spectral_flatness", spectralFlatness(mags));
    out.set("spectral_rolloff_hz", juce::jlimit(0.0, 8000.0, spectralRolloffHz(mags, 0.85)));
    out.set("spectral_slope", juce::jlimit(-2.0, 2.0, spectralSlope(mags)));
    out.set("spectral_flux", spectralFluxProxy(x, kPromptAnalysisSampleRate));
    out.set("spectral_bandwidth_hz", juce::jlimit(0.0, 8000.0, spectralBandwidthHz(mags, centroidHz)));
    out.set("silence_ratio", silenceRatio);
    out.set("activity_ratio", activityRatio);
    out.set("onset_rate_hz", juce::jlimit(0.0, 20.0, onsetRateHz(x, kPromptAnalysisSampleRate)));
    out.set("noise_floor_dbfs", noiseFloorDbfs);
    out.set("phase_corr", juce::jlimit(-1.0, 1.0, (double)stereoStats.getWithDefault("phase_corr", 1.0)));
    out.set("side_ratio", juce::jlimit(0.0, 2.0, (double)stereoStats.getWithDefault("side_ratio", 0.0)));
    out.set("stereo_imbalance", juce::jlimit(0.0, 1.0, (double)stereoStats.getWithDefault("stereo_imbalance", 0.0)));
    out.set("low", low);
    out.set("lowmid", lowmid);
    out.set("mid", mid);
    out.set("high", high);
    out.set("sibilance", sibilance);
    out.set("bassiness", bassiness);
    const auto keyChroma = keyChroma16k(x, kPromptAnalysisSampleRate);
    for (int i = 0; i < (int)keyChroma.size(); ++i)
        out.set(juce::String("key_pc_") + juce::String(i), keyChroma[(size_t)i]);
    return out;
}
} // namespace

std::vector<float> JuceEngine::decodeAudioMono16k(const juce::File &file, int maxOutputSamples)
{
    std::unique_ptr<juce::AudioFormatReader> reader(formatManager.createReaderFor(file));
    if (!reader)
        return {};

    const int64 totalSamples64 = reader->lengthInSamples;
    const int totalSamples = (int)totalSamples64;
    if (totalSamples <= 0)
        return {};

    int inputSamplesToRead = totalSamples;
    if (maxOutputSamples > 0)
    {
        const double inputPerOutput = reader->sampleRate / 16000.0;
        const double cappedInputSamples = std::ceil((double)maxOutputSamples * inputPerOutput);
        inputSamplesToRead = juce::jlimit(0, totalSamples, (int)cappedInputSamples);
    }
    if (inputSamplesToRead <= 0)
        return {};

    juce::AudioBuffer<float> mono(1, inputSamplesToRead);
    reader->read(&mono, 0, inputSamplesToRead, 0, true, false);

    if (reader->sampleRate != 16000.0)
    {
        juce::LagrangeInterpolator resampler;
        resampler.reset();

        const double speedRatio = reader->sampleRate / 16000.0; // input per output
        int outSamples = (int)std::ceil(inputSamplesToRead / speedRatio);
        if (maxOutputSamples > 0)
            outSamples = juce::jmin(outSamples, maxOutputSamples);
        if (outSamples <= 0)
            return {};

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
    else if (maxOutputSamples > 0 && mono.getNumSamples() > maxOutputSamples)
    {
        juce::AudioBuffer<float> trimmed(1, maxOutputSamples);
        trimmed.copyFrom(0, 0, mono, 0, 0, maxOutputSamples);
        mono = std::move(trimmed);
    }

    std::vector<float> out(mono.getNumSamples());
    std::memcpy(out.data(), mono.getReadPointer(0), out.size() * sizeof(float));
    return out;
}

std::vector<std::vector<float>> JuceEngine::sampleAudioMono16kWindows(
    const juce::File &file,
    int windowOutputSamples,
    int windowCount,
    double trimStartMs,
    double trimEndMs)
{
    std::vector<std::vector<float>> windows;
    if (windowOutputSamples <= 0 || windowCount <= 0)
        return windows;

    std::unique_ptr<juce::AudioFormatReader> reader(formatManager.createReaderFor(file));
    if (!reader)
        return windows;

    const int64 totalSamples64 = reader->lengthInSamples;
    const int totalSamples = (int)totalSamples64;
    if (totalSamples <= 0)
        return windows;

    const int totalOutputSamples = estimateOutputSamples(*reader, totalSamples);
    if (totalOutputSamples <= 0)
        return windows;

    const auto region =
        promptAnalysisOutputRange(totalOutputSamples, trimStartMs, trimEndMs);
    const int regionStartSample = region.first;
    const int regionEndSample = region.second;
    const int regionOutputSamples = juce::jmax(0, regionEndSample - regionStartSample);
    if (regionOutputSamples <= 0)
        return windows;

    if (regionOutputSamples <= windowOutputSamples)
    {
        windows.push_back(
            decodeMono16kWindow(*reader, totalSamples, regionStartSample, windowOutputSamples));
        return windows;
    }

    windows.reserve((size_t)windowCount);
    for (int i = 0; i < windowCount; ++i)
    {
        const double t = windowCount <= 1 ? 0.5 : (double)i / (double)(windowCount - 1);
        const int maxOffset = juce::jmax(0, regionOutputSamples - windowOutputSamples);
        const int offset =
            regionStartSample +
            juce::jlimit(0, maxOffset, (int)std::round(t * (double)maxOffset));
        windows.push_back(decodeMono16kWindow(*reader, totalSamples, offset, windowOutputSamples));
    }

    return windows;
}

juce::NamedValueSet JuceEngine::analyzeAudioPrompt16k(
    const juce::File &file,
    double trimStartMs,
    double trimEndMs)
{
    std::vector<float> mono;
    const auto windows = sampleAudioMono16kWindows(
        file,
        kPromptStatsWindowSamples,
        kPromptStatsWindowCount,
        trimStartMs,
        trimEndMs);
    for (const auto &window : windows)
    {
        mono.insert(mono.end(), window.begin(), window.end());
    }
    const auto stereo = analyzeAudioStereo16k(file);
    return analyzePromptStatsFromMono(mono, stereo);
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

    const int64 totalSamples = reader->lengthInSamples;
    if (totalSamples <= 0)
        return out;

    const int readChannels = reader->numChannels >= 2 ? 2 : 1;
    constexpr int kAnalysisChunkSamples = 32768;
    juce::AudioBuffer<float> inBuffer(readChannels, kAnalysisChunkSamples);

    double sumL2 = 0.0;
    double sumR2 = 0.0;
    double sumLR = 0.0;
    double sumMid2 = 0.0;
    double sumSide2 = 0.0;
    int64 samplesAnalyzed = 0;

    for (int64 position = 0; position < totalSamples; position += kAnalysisChunkSamples)
    {
        const int64 remainingSamples = totalSamples - position;
        const int samplesThisChunk = (int)(remainingSamples < (int64)kAnalysisChunkSamples
            ? remainingSamples
            : (int64)kAnalysisChunkSamples);
        if (samplesThisChunk <= 0)
            break;

        if (inBuffer.getNumSamples() != samplesThisChunk)
            inBuffer.setSize(readChannels, samplesThisChunk, false, false, true);
        inBuffer.clear();

        reader->read(&inBuffer, 0, samplesThisChunk, position, true, readChannels >= 2);

        const float *left = inBuffer.getReadPointer(0);
        const float *right = readChannels >= 2 ? inBuffer.getReadPointer(1) : left;
        for (int i = 0; i < samplesThisChunk; ++i)
        {
            const double l = (double)left[i];
            const double r = (double)right[i];
            sumL2 += l * l;
            sumR2 += r * r;
            sumLR += l * r;

            const double mid = 0.5 * (l + r);
            const double side = 0.5 * (l - r);
            sumMid2 += mid * mid;
            sumSide2 += side * side;
        }
        samplesAnalyzed += samplesThisChunk;
    }

    if (samplesAnalyzed <= 0)
        return out;

    const double phaseCorr =
        sumLR / std::sqrt((sumL2 * sumR2) + 1.0e-12);
    const double rmsL = std::sqrt(sumL2 / (double)samplesAnalyzed);
    const double rmsR = std::sqrt(sumR2 / (double)samplesAnalyzed);
    const double midRms = std::sqrt(sumMid2 / (double)samplesAnalyzed);
    const double sideRms = std::sqrt(sumSide2 / (double)samplesAnalyzed);
    const double sideRatio = sideRms / (midRms + 1.0e-9);
    const double stereoImbalance = std::abs(rmsL - rmsR) / (rmsL + rmsR + 1.0e-9);

    out.set("phase_corr", juce::jlimit(-1.0, 1.0, phaseCorr));
    out.set("side_ratio", juce::jlimit(0.0, 2.0, sideRatio));
    out.set("stereo_imbalance", juce::jlimit(0.0, 1.0, stereoImbalance));
    return out;
}

juce::StringArray JuceEngine::getAvailableInputDevices()
{
    return getAvailableInputDeviceNamesForManager(deviceManager);
}

bool JuceEngine::selectInputDevice(const juce::String &name)
{
    auto setup = deviceManager.getAudioDeviceSetup();
    setup.inputDeviceName = name;
    juce::String error = deviceManager.setAudioDeviceSetup(setup, false);
    if (!error.isEmpty())
        error = deviceManager.setAudioDeviceSetup(setup, true);
    if (!error.isEmpty())
    {
        juceLogToFlutter(("selectInputDevice failed: " + error).toRawUTF8());
        return false;
    }

    const int desiredInputs =
        juce::jmax(0, desiredInputOpenChannels.load(std::memory_order_relaxed));
    if (applyPreferredAudioDeviceSetup(desiredInputs, false, "selectInputDevice"))
        return true;
    return applyPreferredAudioDeviceSetup(desiredInputs, true, "selectInputDevice-reopen");
}

juce::String JuceEngine::getCurrentInputDeviceName() const
{
    const auto setup = deviceManager.getAudioDeviceSetup();
    if (setup.inputDeviceName.isNotEmpty())
        return setup.inputDeviceName;
    if (auto *dev = deviceManager.getCurrentAudioDevice())
        return dev->getName();
    return {};
}

juce::String JuceEngine::getCurrentOutputDeviceName() const
{
    const auto setup = deviceManager.getAudioDeviceSetup();
    if (setup.outputDeviceName.isNotEmpty())
        return setup.outputDeviceName;
    if (auto *dev = deviceManager.getCurrentAudioDevice())
        return dev->getName();
    return {};
}

int JuceEngine::getNumInputChannels() const
{
    if (auto *dev = deviceManager.getCurrentAudioDevice())
    {
        const int available = dev->getInputChannelNames().size();
        if (available > 0)
            return available;
        return dev->getActiveInputChannels().countNumberOfSetBits();
    }
    return 0;
}

int JuceEngine::getActiveInputChannelCount() const
{
    if (auto *dev = deviceManager.getCurrentAudioDevice())
        return dev->getActiveInputChannels().countNumberOfSetBits();
    return 0;
}

int JuceEngine::getActiveOutputChannelCount() const
{
    if (auto *dev = deviceManager.getCurrentAudioDevice())
        return dev->getActiveOutputChannels().countNumberOfSetBits();
    return 0;
}

void JuceEngine::setLiveInputMonitoringEnabled(bool enabled)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    if (liveInputMonitoringEnabled == enabled)
        return;

    constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;
    liveInputMonitoringEnabled = enabled;
    syncLiveInputMonitorRoutingLocked(batchUpdate);
    commitGraphMutationLocked(false);
}

bool JuceEngine::isLiveInputMonitoringEnabled() const noexcept
{
    return liveInputMonitoringEnabled;
}

bool JuceEngine::setLiveInputMonitorTargetV2(int row,
                                             int channelStart,
                                             int channelCount)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    auto *device = deviceManager.getCurrentAudioDevice();
    const int activeInputs = device == nullptr
        ? 0
        : device->getActiveInputChannels().countNumberOfSetBits();
    if (!androidV2RecordingPrepared || row < 0 || row >= (int)rows.size() ||
        channelStart < 0 || (channelCount != 1 && channelCount != 2) ||
        channelStart + channelCount > activeInputs)
        return false;

    liveMonitorTargetRow = row;
    liveMonitorChannelStart = channelStart;
    liveMonitorChannelCount = channelCount;
    if (liveInputMonitoringEnabled)
    {
        constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;
        syncLiveInputMonitorRoutingLocked(batchUpdate);
        commitGraphMutationLocked(false);
    }
    return true;
}

void JuceEngine::clearLiveInputMonitorConnectionsLocked(
    juce::AudioProcessorGraph::UpdateKind updateKind)
{
    for (auto &connection : liveMonitorConnections)
        graph.removeConnection(connection, updateKind);
    liveMonitorConnections.clear();
}

void JuceEngine::syncLiveInputMonitorRoutingLocked(
    juce::AudioProcessorGraph::UpdateKind updateKind)
{
    clearLiveInputMonitorConnectionsLocked(updateKind);

    if (!liveInputMonitoringEnabled || !inputNode || rows.empty())
    {
        armOutputSafetyForCurrentRoute();
        return;
    }

    const int row = juce::jlimit(0, (int)rows.size() - 1, liveMonitorTargetRow);
    ensureRowBusNodesAttached(row, updateKind);
    auto rowInput = rows[(size_t)row].inputNode;
    if (!rowInput)
    {
        armOutputSafetyForCurrentRoute();
        return;
    }

    const int start = juce::jmax(0, liveMonitorChannelStart);
    const int chCount = juce::jlimit(0, 2, liveMonitorChannelCount);
    for (int ch = 0; ch < chCount; ++ch)
    {
        juce::AudioProcessorGraph::Connection connection{
            {inputNode->nodeID, start + ch},
            {rowInput->nodeID, ch},
        };
        if (graph.addConnection(connection, updateKind))
            liveMonitorConnections.add(connection);
    }

    armOutputSafetyForCurrentRoute();
}

void JuceEngine::routeLiveInputToRow(int row, int channelCount, int channelStart)
{
    if (androidV2RecordingPrepared)
    {
        liveMonitorTargetRow = row;
        liveMonitorChannelCount = channelCount;
        liveMonitorChannelStart = channelStart;
        return;
    }

    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    liveMonitorTargetRow = row;
    liveMonitorChannelCount = channelCount;
    liveMonitorChannelStart = channelStart;
    constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;
    syncLiveInputMonitorRoutingLocked(batchUpdate);
    commitGraphMutationLocked(false);
}

bool JuceEngine::startRecordingToWav(const juce::File &file,
                                     int channelStart,
                                     int channelCount)
{
    if (wavCapture.isActive())
        return false;

    const bool v2Recording = androidV2RecordingPrepared;
    const int previousDesiredInputs = desiredInputOpenChannels.load(std::memory_order_relaxed);
    juce::ignoreUnused(previousDesiredInputs);
    // Recording input prewarm intentionally opens inputs before capture starts.
    // Restoring that prewarm target after stop can leave Bluetooth in duplex
    // mode, so post-record should return to playback-only instead.
    recordingRestoreDesiredInputs.store(0, std::memory_order_relaxed);

    const auto failAndRestorePlaybackMode = [this, v2Recording]()
    {
        if (v2Recording)
            return false;
        applyPreferredAudioDeviceSetup(0, true, "startRecording-restore");
        return false;
    };

    const int requiredInputs = juce::jmax(1, channelStart + channelCount);
    if (v2Recording)
    {
        if (channelStart < 0 || (channelCount != 1 && channelCount != 2) ||
            requiredInputs != desiredInputOpenChannels.load(std::memory_order_relaxed))
            return false;
    }
    else if (!applyPreferredAudioDeviceSetup(requiredInputs, false, "startRecording"))
    {
        if (!applyPreferredAudioDeviceSetup(requiredInputs, true, "startRecording-reopen"))
            return false;
    }

    auto *dev = deviceManager.getCurrentAudioDevice();
    if (!dev)
        return failAndRestorePlaybackMode();

    const int outputs = dev->getActiveOutputChannels().countNumberOfSetBits();
    if (outputs <= 0)
        return failAndRestorePlaybackMode();

    int numInputs = dev->getActiveInputChannels().countNumberOfSetBits();
    if (numInputs <= 0)
        numInputs = dev->getInputChannelNames().size();
    if (numInputs <= 0)
    {
        if (v2Recording)
            return false;
        // Hard fallback for stale routes that report no active inputs right
        // after arm. Re-open a minimal mono input path and retry.
        if (!applyPreferredAudioDeviceSetup(1, true, "startRecording-fallback-mono"))
            return failAndRestorePlaybackMode();
        dev = deviceManager.getCurrentAudioDevice();
        if (!dev)
            return failAndRestorePlaybackMode();
        numInputs = dev->getActiveInputChannels().countNumberOfSetBits();
        if (numInputs <= 0)
            numInputs = dev->getInputChannelNames().size();
    }
    if (numInputs <= 0)
        return failAndRestorePlaybackMode();

    channelStart = juce::jlimit(0, numInputs - 1, channelStart);
    const int maxCount = juce::jmax(1, numInputs - channelStart);
    channelCount = juce::jlimit(1, juce::jmin(2, maxCount), channelCount);

    const double acceptedSampleRate = getKnownDeviceSampleRate(
        deviceManager,
        hostSampleRateAtomic.load(std::memory_order_relaxed));
    if (!wavCapture.start(file,
                          acceptedSampleRate,
                          channelCount,
                          channelStart))
        return failAndRestorePlaybackMode();

    if (!v2Recording || !liveInputMonitoringEnabled)
        routeLiveInputToRow(/*row=*/0, channelCount, channelStart);
    logCurrentAudioDeviceState("recording-started");
    return true;
}

void JuceEngine::discardRecordingCaptureV2Android()
{
    wavCapture.stop(true);
    routeLiveInputToRow(/*row=*/0, /*channelCount=*/0, /*channelStart=*/0);
}

RealtimeWavCapture::StopResult JuceEngine::stopRecording(bool restorePlaybackRoute)
{
    auto captureResult = finalizeRecordingCapture();
    completeRecordingStop(restorePlaybackRoute);
    return captureResult;
}

RealtimeWavCapture::StopResult JuceEngine::finalizeRecordingCapture()
{
    return wavCapture.stop();
}

void JuceEngine::completeRecordingStop(bool restorePlaybackRoute)
{
    routeLiveInputToRow(/*row=*/0, /*channelCount=*/0, /*channelStart=*/0);
    const int restoreInputs = juce::jmax(
        0,
        recordingRestoreDesiredInputs.exchange(0, std::memory_order_relaxed));
    desiredInputOpenChannels.store(restoreInputs, std::memory_order_relaxed);
    if (!restorePlaybackRoute)
    {
        logCurrentAudioDeviceState("recording-stopped-deferredRestore");
        return;
    }

    if (restoreInputs <= 0 &&
        restoreRecordingPlaybackSetup("stopRecording-restorePlaybackSetup"))
    {
        logCurrentAudioDeviceState("recording-stopped");
        return;
    }

    if (!applyPreferredAudioDeviceSetup(restoreInputs, true, "stopRecording"))
        requestAudioDeviceRefreshAsync("stopRecording");
    else
        logCurrentAudioDeviceState("recording-stopped");
}

bool JuceEngine::isRecording() const
{
    return wavCapture.isActive();
}

void JuceEngine::captureInput(const float *const *input, int numInputChannels, int numSamples)
{
    wavCapture.capture(input, numInputChannels, numSamples);
}

double JuceEngine::getRecordingPeak() const
{
    return wavCapture.consumePeak();
}

void JuceEngine::captureOutput(float *const *output,
                               int numOutputChannels,
                               int numSamples)
{
    std::array<const float *, 2> channels{{nullptr, nullptr}};
    const int availableChannels = juce::jlimit(0, 2, numOutputChannels);
    for (int channel = 0; channel < availableChannels; ++channel)
        channels[(size_t)channel] = output != nullptr ? output[channel] : nullptr;
    wavCapture.capture(channels.data(),
                       availableChannels,
                       numSamples,
                       0);
}

void JuceEngine::setMasterMeterEnabled(bool enabled)
{
    masterMeterEnabled.store(enabled, std::memory_order_relaxed);
}

void JuceEngine::armOutputSafetyFadeIn(double sampleRate) noexcept
{
    outputSafetyLastSample = {0.0f, 0.0f};
    outputSafetyMuteSamplesRemaining = 0;
    outputSafetyFadeSamplesTotal = juce::jlimit(
        64,
        9600,
        (int)std::lround(juce::jmax(8000.0, sampleRate) * 0.05));
    outputSafetyFadeSamplesRemaining = outputSafetyFadeSamplesTotal;
}

void JuceEngine::clearOutputSafetyState() noexcept
{
    outputSafetyLastSample = {0.0f, 0.0f};
    outputSafetyMuteSamplesRemaining = 0;
    outputSafetyFadeSamplesTotal = 0;
    outputSafetyFadeSamplesRemaining = 0;
}

void JuceEngine::applyOutputSafetyGuard(float *const *output,
                                        int numOutputChannels,
                                        int numSamples) noexcept
{
    if (output == nullptr || numOutputChannels <= 0 || numSamples <= 0)
        return;

    const int controlRequest =
        outputSafetyControlRequest.exchange(0, std::memory_order_acq_rel);
    if (controlRequest == kOutputSafetyRequestFadeIn)
    {
        outputSafetyLastSample = {0.0f, 0.0f};
        outputSafetyMuteSamplesRemaining = 0;
        outputSafetyFadeSamplesTotal = juce::jlimit(
            64,
            9600,
            outputSafetyRequestedFadeSamples.load(std::memory_order_acquire));
        outputSafetyFadeSamplesRemaining = outputSafetyFadeSamplesTotal;
    }
    else if (controlRequest == kOutputSafetyRequestClear)
    {
        clearOutputSafetyState();
    }

    constexpr float kSafetyCeiling = 0.92f;
    constexpr float kEmergencyAbs = 4.0f;
    const double currentRate =
        juce::jmax(8000.0, hostSampleRateAtomic.load(std::memory_order_relaxed));
    const int emergencyMuteSamples = juce::jlimit(
        256,
        48000,
        (int)std::lround(currentRate * 0.25));

    for (int sample = 0; sample < numSamples; ++sample)
    {
        bool emergencyMute = false;
        float peak = 0.0f;

        for (int ch = 0; ch < numOutputChannels; ++ch)
        {
            auto *channelData = output[ch];
            if (channelData == nullptr)
                continue;

            const float value = channelData[sample];
            if (!std::isfinite(value) || std::abs(value) > kEmergencyAbs)
            {
                emergencyMute = true;
                break;
            }

            peak = juce::jmax(peak, std::abs(value));
        }

        if (emergencyMute)
            outputSafetyMuteSamplesRemaining =
                juce::jmax(outputSafetyMuteSamplesRemaining, emergencyMuteSamples);

        if (outputSafetyMuteSamplesRemaining > 0)
        {
            for (int ch = 0; ch < numOutputChannels; ++ch)
                if (auto *channelData = output[ch])
                    channelData[sample] = 0.0f;

            --outputSafetyMuteSamplesRemaining;
            if (outputSafetyMuteSamplesRemaining == 0)
                outputSafetyFadeSamplesRemaining = outputSafetyFadeSamplesTotal;
            outputSafetyLastSample = {0.0f, 0.0f};
            continue;
        }

        const float frameGain =
            peak > kSafetyCeiling ? (kSafetyCeiling / peak) : 1.0f;
        const bool transitionGuardActive =
            outputSafetyFadeSamplesRemaining > 0 &&
            outputSafetyFadeSamplesTotal > 0;
        const float fadeGain =
            transitionGuardActive
                ? 1.0f - ((float)outputSafetyFadeSamplesRemaining /
                          (float)outputSafetyFadeSamplesTotal)
                : 1.0f;

        for (int ch = 0; ch < numOutputChannels; ++ch)
        {
            auto *channelData = output[ch];
            if (channelData == nullptr)
                continue;

            float value = channelData[sample] * frameGain * fadeGain;
            if (!std::isfinite(value))
            {
                value = 0.0f;
                outputSafetyMuteSamplesRemaining =
                    juce::jmax(outputSafetyMuteSamplesRemaining, emergencyMuteSamples);
            }

            value = juce::jlimit(-kSafetyCeiling, kSafetyCeiling, value);
            channelData[sample] = value;

            if (ch < (int)outputSafetyLastSample.size())
                outputSafetyLastSample[(size_t)ch] = value;
        }

        if (outputSafetyFadeSamplesRemaining > 0)
            --outputSafetyFadeSamplesRemaining;
    }
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
    if (numOutCh <= 0 || out == nullptr || out[0] == nullptr)
        return;
    if (numSamples <= 0)
        return;

    const float *outL = out[0];
    const float *outR = (numOutCh > 1 && out[1] != nullptr) ? out[1] : outL;

    float peakL = 0.0f, peakR = 0.0f;
    double sumSqL = 0.0, sumSqR = 0.0;

    for (int i = 0; i < numSamples; ++i)
    {
        const float rawL = outL[i];
        const float rawR = outR[i];
        const float l = std::isfinite(rawL) ? rawL : 0.0f;
        const float r = std::isfinite(rawR) ? rawR : 0.0f;

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
    const auto snapshot = std::atomic_load_explicit(&meterReadoutSnapshot, std::memory_order_acquire);
    if (snapshot == nullptr || rowIndex < 0 || rowIndex >= (int)snapshot->rowMeters.size())
        return {0, 0, 0, 0};

    const auto meter = snapshot->rowMeters[(size_t)rowIndex];
    if (meter == nullptr)
        return {0, 0, 0, 0};

    return {
        meter->peakL.load(std::memory_order_relaxed),
        meter->peakR.load(std::memory_order_relaxed),
        meter->rmsL.load(std::memory_order_relaxed),
        meter->rmsR.load(std::memory_order_relaxed),
    };
}

std::vector<float> JuceEngine::getAllMeterValues() const
{
    const auto snapshot = std::atomic_load_explicit(&meterReadoutSnapshot, std::memory_order_acquire);
    constexpr int stride = 5;
    const int rowCount = snapshot != nullptr ? (int)snapshot->rowMeters.size() : 0;
    const int total = stride * (1 + rowCount);

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
    for (int row = 0; row < rowCount; ++row)
    {
        const int base = stride * (1 + row);

        const auto meter = snapshot->rowMeters[(size_t)row];
        if (meter != nullptr)
        {
            out[base + 0] = meter->peakL.load(std::memory_order_relaxed);
            out[base + 1] = meter->peakR.load(std::memory_order_relaxed);
            out[base + 2] = meter->rmsL.load(std::memory_order_relaxed);
            out[base + 3] = meter->rmsR.load(std::memory_order_relaxed);
        }

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

    auto *chainPtr = effectChainForRowApi(row);
    if (chainPtr == nullptr)
        return {0, 0, 0, 0, 0};
    auto &chain = *chainPtr;
    if (effectIndex < 0 || effectIndex >= chain.size())
        return {0, 0, 0, 0, 0};

    auto nodeID = chain.getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (!node)
        return {0, 0, 0, 0, 0};

    auto *processor = node->getProcessor();
    if (auto *comp = dynamic_cast<CompressorAudioProcessor *>(processor))
        return comp->getMeterStrip();
    if (auto *limiter = dynamic_cast<LimiterAudioProcessor *>(processor))
        return limiter->getMeterStrip();
    if (auto *clipper = dynamic_cast<ClipperAudioProcessor *>(processor))
        return clipper->getMeterStrip();

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

    auto *processor = node->getProcessor();
    if (auto *comp = dynamic_cast<CompressorAudioProcessor *>(processor))
        return comp->getMeterStrip();
    if (auto *limiter = dynamic_cast<LimiterAudioProcessor *>(processor))
        return limiter->getMeterStrip();
    if (auto *clipper = dynamic_cast<ClipperAudioProcessor *>(processor))
        return clipper->getMeterStrip();

    return {0, 0, 0, 0, 0};
}

double JuceEngine::getHostSampleRate() const
{
    const double sr =
        getKnownDeviceSampleRate(deviceManager, hostSampleRateAtomic.load(std::memory_order_relaxed));
    return sr > 1000.0 ? sr : 44100.0;
}

std::vector<float> JuceEngine::getRowEqWaveform(int row, int effectIndex, int sampleCount)
{
    const int count = juce::jlimit(16, 1024, sampleCount);

    if (row < 0 || row >= (int)rows.size())
        return std::vector<float>((size_t)count, 0.0f);

    auto *chainPtr = effectChainForRowApi(row);
    if (chainPtr == nullptr)
        return std::vector<float>((size_t)count, 0.0f);
    auto &chain = *chainPtr;
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
    if (auto *degrade = dynamic_cast<DegradeAudioProcessor *>(node->getProcessor()))
        return degrade->getRecentWaveform(count);

    return std::vector<float>((size_t)count, 0.0f);
}

std::vector<float> JuceEngine::getMasterEqWaveform(int effectIndex, int sampleCount)
{
    const int count = juce::jlimit(16, 1024, sampleCount);

    if (!masterEffectChain)
        return std::vector<float>((size_t)count, 0.0f);

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
    if (auto *degrade = dynamic_cast<DegradeAudioProcessor *>(node->getProcessor()))
        return degrade->getRecentWaveform(count);

    return std::vector<float>((size_t)count, 0.0f);
}

std::vector<float> JuceEngine::getRowStereoScope(int row, int effectIndex, int pointCount)
{
    const int count = juce::jlimit(32, 1024, pointCount);

    if (row < 0 || row >= (int)rows.size())
        return std::vector<float>((size_t)(count * 2), 0.0f);

    auto *chainPtr = effectChainForRowApi(row);
    if (chainPtr == nullptr)
        return std::vector<float>((size_t)(count * 2), 0.0f);
    auto &chain = *chainPtr;
    if (effectIndex < 0 || effectIndex >= chain.size())
        return std::vector<float>((size_t)(count * 2), 0.0f);

    auto nodeID = chain.getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (!node)
        return std::vector<float>((size_t)(count * 2), 0.0f);

    if (auto *stereoPro = dynamic_cast<StereoProAudioProcessor *>(node->getProcessor()))
        return stereoPro->getRecentScope(count);

    return std::vector<float>((size_t)(count * 2), 0.0f);
}

std::vector<float> JuceEngine::getMasterStereoScope(int effectIndex, int pointCount)
{
    const int count = juce::jlimit(32, 1024, pointCount);

    if (!masterEffectChain)
        return std::vector<float>((size_t)(count * 2), 0.0f);

    if (effectIndex < 0 || effectIndex >= masterEffectChain->size())
        return std::vector<float>((size_t)(count * 2), 0.0f);

    auto nodeID = masterEffectChain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (!node)
        return std::vector<float>((size_t)(count * 2), 0.0f);

    if (auto *stereoPro = dynamic_cast<StereoProAudioProcessor *>(node->getProcessor()))
        return stereoPro->getRecentScope(count);

    return std::vector<float>((size_t)(count * 2), 0.0f);
}

std::vector<float> JuceEngine::getRowShaperPreview(int row, int effectIndex, int pointCount)
{
    const int count = juce::jlimit(32, 512, pointCount);

    if (row < 0 || row >= (int)rows.size())
        return std::vector<float>((size_t)(count + 1), 1.0f);

    auto *chainPtr = effectChainForRowApi(row);
    if (chainPtr == nullptr)
        return std::vector<float>((size_t)(count + 1), 1.0f);
    auto &chain = *chainPtr;
    if (effectIndex < 0 || effectIndex >= chain.size())
        return std::vector<float>((size_t)(count + 1), 1.0f);

    auto nodeID = chain.getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (!node)
        return std::vector<float>((size_t)(count + 1), 1.0f);

    if (auto *volumeShaper = dynamic_cast<VolumeShaperAudioProcessor *>(node->getProcessor()))
        return volumeShaper->getPreviewCurve(count);
    if (auto *timeShaper = dynamic_cast<TimeShaperAudioProcessor *>(node->getProcessor()))
        return timeShaper->getPreviewCurve(count);

    return std::vector<float>((size_t)(count + 1), 1.0f);
}

std::vector<float> JuceEngine::getMasterShaperPreview(int effectIndex, int pointCount)
{
    const int count = juce::jlimit(32, 512, pointCount);

    if (!masterEffectChain)
        return std::vector<float>((size_t)(count + 1), 1.0f);

    if (effectIndex < 0 || effectIndex >= masterEffectChain->size())
        return std::vector<float>((size_t)(count + 1), 1.0f);

    auto nodeID = masterEffectChain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (!node)
        return std::vector<float>((size_t)(count + 1), 1.0f);

    if (auto *volumeShaper = dynamic_cast<VolumeShaperAudioProcessor *>(node->getProcessor()))
        return volumeShaper->getPreviewCurve(count);
    if (auto *timeShaper = dynamic_cast<TimeShaperAudioProcessor *>(node->getProcessor()))
        return timeShaper->getPreviewCurve(count);

    return std::vector<float>((size_t)(count + 1), 1.0f);
}

std::vector<float> JuceEngine::getRowDynamicSoftenerFrame(int row, int effectIndex)
{
    const size_t fallbackSize = (size_t)(DynamicSoftenerModule::kBandCount * 3);

    if (row < 0 || row >= (int)rows.size())
        return std::vector<float>(fallbackSize, 0.0f);

    auto *chainPtr = effectChainForRowApi(row);
    if (chainPtr == nullptr)
        return std::vector<float>(fallbackSize, 0.0f);
    auto &chain = *chainPtr;
    if (effectIndex < 0 || effectIndex >= chain.size())
        return std::vector<float>(fallbackSize, 0.0f);

    auto nodeID = chain.getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (!node)
        return std::vector<float>(fallbackSize, 0.0f);

    if (auto *softener = dynamic_cast<DynamicSoftenerAudioProcessor *>(node->getProcessor()))
        return softener->getVisualFrame();

    return std::vector<float>(fallbackSize, 0.0f);
}

std::vector<float> JuceEngine::getMasterDynamicSoftenerFrame(int effectIndex)
{
    const size_t fallbackSize = (size_t)(DynamicSoftenerModule::kBandCount * 3);

    if (!masterEffectChain)
        return std::vector<float>(fallbackSize, 0.0f);

    if (effectIndex < 0 || effectIndex >= masterEffectChain->size())
        return std::vector<float>(fallbackSize, 0.0f);

    auto nodeID = masterEffectChain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (!node)
        return std::vector<float>(fallbackSize, 0.0f);

    if (auto *softener = dynamic_cast<DynamicSoftenerAudioProcessor *>(node->getProcessor()))
        return softener->getVisualFrame();

    return std::vector<float>(fallbackSize, 0.0f);
}

std::vector<float> JuceEngine::getRowTransientShaperVisual(int row, int effectIndex, int pointCount)
{
    const int count = juce::jlimit(32, 512, pointCount);
    const size_t fallbackSize = (size_t)(count * TransientShaperModule::kVisualStride);

    if (row < 0 || row >= (int)rows.size())
        return std::vector<float>(fallbackSize, 0.0f);

    auto *chainPtr = effectChainForRowApi(row);
    if (chainPtr == nullptr)
        return std::vector<float>(fallbackSize, 0.0f);
    auto &chain = *chainPtr;
    if (effectIndex < 0 || effectIndex >= chain.size())
        return std::vector<float>(fallbackSize, 0.0f);

    auto nodeID = chain.getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (!node)
        return std::vector<float>(fallbackSize, 0.0f);

    if (auto *transientShaper = dynamic_cast<TransientShaperAudioProcessor *>(node->getProcessor()))
        return transientShaper->getRecentVisual(count);

    return std::vector<float>(fallbackSize, 0.0f);
}

std::vector<float> JuceEngine::getMasterTransientShaperVisual(int effectIndex, int pointCount)
{
    const int count = juce::jlimit(32, 512, pointCount);
    const size_t fallbackSize = (size_t)(count * TransientShaperModule::kVisualStride);

    if (!masterEffectChain)
        return std::vector<float>(fallbackSize, 0.0f);

    if (effectIndex < 0 || effectIndex >= masterEffectChain->size())
        return std::vector<float>(fallbackSize, 0.0f);

    auto nodeID = masterEffectChain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (!node)
        return std::vector<float>(fallbackSize, 0.0f);

    if (auto *transientShaper = dynamic_cast<TransientShaperAudioProcessor *>(node->getProcessor()))
        return transientShaper->getRecentVisual(count);

    return std::vector<float>(fallbackSize, 0.0f);
}

int JuceEngine::allocateRowId(int preferredRowId)
{
    if (preferredRowId != -1)
    {
        if (preferredRowId <= 0)
            return -1;
        if (getRowIndexById(preferredRowId) >= 0)
            return -1;

        int next = nextRowId.load();
        while (next <= preferredRowId &&
               !nextRowId.compare_exchange_weak(next, preferredRowId + 1))
        {
        }
        return preferredRowId;
    }
    return nextRowId.fetch_add(1);
}

int JuceEngine::addRow(const juce::String &name, int iconId, int preferredRowId)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if ((int)rows.size() >= kMaxRows)
        return -1;

    RowState r;
    const int newRowId = allocateRowId(preferredRowId);
    if (newRowId < 0)
        return -1;
    r.rowId = newRowId;
    r.name = name.isNotEmpty() ? name : "Row";
    r.iconId = iconId;

    rows.push_back(std::move(r));
    rebuildRowIdIndexCache();
    publishAutomationSnapshotLocked();

    if (engineInitialized)
    {
        ensureRowBusNodesAttached((int)rows.size() - 1, juce::AudioProcessorGraph::UpdateKind::none);
        retargetRowMeterTapPointers();
        commitGraphMutationLocked();
    }

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

int JuceEngine::insertRowAbove(int referenceRowId, const juce::String &name, int iconId, int preferredRowId)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if ((int)rows.size() >= kMaxRows)
        return -1;

    const int refIdx = getRowIndexById(referenceRowId);
    const int insertIdx = juce::jlimit(0, (int)rows.size(), refIdx);

    RowState r;
    const int newRowId = allocateRowId(preferredRowId);
    if (newRowId < 0)
        return -1;
    r.rowId = newRowId;
    r.name = name.isNotEmpty() ? name : "Row";
    r.iconId = iconId;

    rows.insert(rows.begin() + insertIdx, std::move(r));
    rebuildRowIdIndexCache();
    publishAutomationSnapshotLocked();

    if (engineInitialized)
    {
        ensureRowBusNodesAttached(insertIdx, juce::AudioProcessorGraph::UpdateKind::none);
        retargetRowMeterTapPointers();
        commitGraphMutationLocked();
    }

    return newRowId;
}

int JuceEngine::insertRowBelow(int referenceRowId, const juce::String &name, int iconId, int preferredRowId)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

    if ((int)rows.size() >= kMaxRows)
        return -1;

    const int refIdx = getRowIndexById(referenceRowId);
    const int insertIdx = juce::jlimit(0, (int)rows.size(), refIdx + 1);

    RowState r;
    const int newRowId = allocateRowId(preferredRowId);
    if (newRowId < 0)
        return -1;
    r.rowId = newRowId;
    r.name = name.isNotEmpty() ? name : "Row";
    r.iconId = iconId;

    rows.insert(rows.begin() + insertIdx, std::move(r));
    rebuildRowIdIndexCache();
    publishAutomationSnapshotLocked();

    if (engineInitialized)
    {
        ensureRowBusNodesAttached(insertIdx, juce::AudioProcessorGraph::UpdateKind::none);
        retargetRowMeterTapPointers();
        commitGraphMutationLocked();
    }

    return newRowId;
}

bool JuceEngine::moveRowOrder(int fromIndex, int toIndex)
{
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

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
    publishAutomationSnapshotLocked();

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
    std::vector<std::shared_ptr<juce::AudioProcessor>> detachedProcessors;

    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);

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

        beginRoutedClipScheduleMutationLocked();
        // Delete clips that belong to this row only.
        juce::Array<int> removedClipIds;
        if (const auto it = rowIdToClipIds.find(rowId); it != rowIdToClipIds.end())
            removedClipIds = it->second;
        for (const auto clipId : removedClipIds)
        {
            if (auto detachedProcessor =
                    clearClipGraphNodes(clipId, juce::AudioProcessorGraph::UpdateKind::none))
            {
                detachedProcessors.push_back(std::move(detachedProcessor));
            }
        }
        rowIdToClipIds.erase(rowId);
        rowRoutedClipSchedules.erase(rowId);
        requestRoutedClipSchedulePublishLocked();

        // Remove graph nodes owned by the row being deleted (including its FX).
        auto removed = std::move(rows[(size_t)idx]);
        for (auto id : removed.fxChain)
            graph.removeNode(id, juce::AudioProcessorGraph::UpdateKind::none);
        if (removed.inputNode)
            graph.removeNode(removed.inputNode->nodeID, juce::AudioProcessorGraph::UpdateKind::none);
        if (removed.automationNode)
            graph.removeNode(removed.automationNode->nodeID, juce::AudioProcessorGraph::UpdateKind::none);
        if (removed.gainNode)
            graph.removeNode(removed.gainNode->nodeID, juce::AudioProcessorGraph::UpdateKind::none);
        if (removed.panNode)
            graph.removeNode(removed.panNode->nodeID, juce::AudioProcessorGraph::UpdateKind::none);
        if (removed.meterTapNode)
            graph.removeNode(removed.meterTapNode->nodeID, juce::AudioProcessorGraph::UpdateKind::none);

        rows.erase(rows.begin() + idx);
        rebuildRowIdIndexCache();
        publishAutomationSnapshotLocked();

        if (engineInitialized)
        {
            retargetRowMeterTapPointers();
        }
        endRoutedClipScheduleMutationLocked();

        commitGraphMutationLocked();
    }

    {
        const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
        for (auto &processor : detachedProcessors)
            retireLiveClipProcessorLocked(std::move(processor));
        drainRetiredLiveClipProcessorsLocked();
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
    const std::lock_guard<std::recursive_mutex> renderLock(graphRenderMutex);
    constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;

    // 1) Remove connections that touch any row/master nodes
    // 2) Remove row bus nodes and master gain/pan nodes (keep FX nodes/chains)
    // 3) Recreate buses via ensureBusGraphInitialised()
    // 4) Rewire row/master FX chains and every alive clip

    // Remove ALL connections first (safe & easiest)
    auto conns = graph.getConnections();
    for (auto &c : conns)
        graph.removeConnection(c, batchUpdate);
    liveMonitorConnections.clear();

    // Existing clip chains are now disconnected.
    for (auto &clip : clips)
        clip.wired = false;

    // Remove master input/gain/pan nodes only (keep master FX nodes + chain IDs).
    if (masterInputNode)
        graph.removeNode(masterInputNode->nodeID, batchUpdate);
    if (masterGainNode)
        graph.removeNode(masterGainNode->nodeID, batchUpdate);
    if (masterPanNode)
        graph.removeNode(masterPanNode->nodeID, batchUpdate);
    masterInputNode = nullptr;
    masterGainNode = nullptr;
    masterPanNode = nullptr;
    masterInputProcessor = nullptr;
    masterGainProcessor = nullptr;
    masterPanProcessor = nullptr;

    for (auto &group : trackGroups)
    {
        if (group.inputNode)
            graph.removeNode(group.inputNode->nodeID, batchUpdate);
        if (group.gainNode)
            graph.removeNode(group.gainNode->nodeID, batchUpdate);
        if (group.panNode)
            graph.removeNode(group.panNode->nodeID, batchUpdate);

        group.inputNode = nullptr;
        group.gainNode = nullptr;
        group.panNode = nullptr;
        group.inputProc = nullptr;
        group.gainProc = nullptr;
        group.panProc = nullptr;
    }

    // Remove all old row bus nodes (keep row FX nodes + chain IDs).
    for (auto &r : rows)
    {
        if (r.inputNode)
            graph.removeNode(r.inputNode->nodeID, batchUpdate);
        if (r.automationNode)
            graph.removeNode(r.automationNode->nodeID, batchUpdate);
        if (r.gainNode)
            graph.removeNode(r.gainNode->nodeID, batchUpdate);
        if (r.panNode)
            graph.removeNode(r.panNode->nodeID, batchUpdate);
        if (r.meterTapNode)
            graph.removeNode(r.meterTapNode->nodeID, batchUpdate);

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
    ensureBusGraphInitialised(false);

    // Restore row/master FX routing on top of rebuilt bus nodes.
    for (auto &group : trackGroups)
        rewireTrackGroupFxChain(group.id, batchUpdate);
    for (int i = 0; i < (int)rows.size(); ++i)
        rewireTrackBusFxChain(i, batchUpdate);
    rewireMasterFxChain(batchUpdate);
    reconnectAllRowOutputsToBuses(batchUpdate);

    syncLiveInputMonitorRoutingLocked(batchUpdate);
    commitGraphMutationLocked();
}

const juce::StringArray JuceEngine::mixroomPlugins{
    "Gain",
    "EQ 3-Band",
    "Compressor",
    "Dynamic Softener",
    "Transient Shaper",
    "Limiter",
    "Clipper",
    "De-Esser",
    "Distortion",
    "Degrade",
    "Delay",
    "Reverb",
    "EQ Parametric",
    "Pitch Shift",
    "Pitch Corrector",
    "Chorus",
    "Vibrato",
    "Stereo",
    "Stereo Pro",
    "Volume Shaper",
    "Time Shaper",
};
