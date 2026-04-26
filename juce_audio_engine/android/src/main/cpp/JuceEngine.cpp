#include "JuceEngine.h"
#include <algorithm>
#include <cmath>
#include <unordered_set>

using namespace juce;

namespace
{
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
                   juce::AudioProcessorGraph::NodeID dst)
{
    for (int ch = 0; ch < 2; ++ch)
        graph.addConnection({{src, ch}, {dst, ch}});
}

void disconnectStereo(juce::AudioProcessorGraph &graph,
                      juce::AudioProcessorGraph::NodeID src,
                      juce::AudioProcessorGraph::NodeID dst)
{
    for (int ch = 0; ch < 2; ++ch)
        graph.removeConnection({{src, ch}, {dst, ch}});
}

void clearStereoConnectionsBetweenNodes(
    juce::AudioProcessorGraph &graph,
    const juce::Array<juce::AudioProcessorGraph::NodeID> &nodeIds)
{
    for (auto src : nodeIds)
    {
        for (auto dst : nodeIds)
        {
            if (src == dst)
                continue;
            disconnectStereo(graph, src, dst);
        }
    }
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
    if (desiredInputChannels <= 0 || recordingActive)
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

        if (recordingActive)
            routeLiveInputToRow(/*row=*/0, recordChannelCount, recordChannelOffset); });
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
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);
    outputSafetyLastSample = {0.0f, 0.0f};
    outputSafetyMuteSamplesRemaining = 0;
    if (fadeIn)
    {
        armOutputSafetyFadeIn(getKnownDeviceSampleRate(
            deviceManager,
            hostSampleRateAtomic.load(std::memory_order_relaxed)));
        return;
    }

    outputSafetyFadeSamplesTotal = 0;
    outputSafetyFadeSamplesRemaining = 0;
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
void JuceEngine::initialiseEngine()
{
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

    if (!formatsRegistered)
    {
        // Audio formats
        formatManager.registerBasicFormats();
        // Plugin formats
        pluginFormatManager.addDefaultFormats();
#if JUCE_IOS
        pluginFormatManager.addFormat(new juce::AudioUnitPluginFormat());
#endif
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

        formatsRegistered = true;
    }
    deviceManager.removeChangeListener(this);
    deviceManager.addChangeListener(this);

#if JUCE_ANDROID
    if (applyPreferredAudioDeviceSetup(0, true, "initialise-playback-buffer"))
        logCurrentAudioDeviceState("initialise-playback-buffer");
#endif

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

    // Only expose the live callback after the graph and IO nodes are fully ready.
    deviceManager.addAudioCallback(metronomeCallback.get());

    // Register plugin/MIDI input callbacks lazily on demand.
    // Eager scanning here can stall first project open on iOS route discovery.
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
    {
        const std::lock_guard<std::mutex> lock(liveMidiInputQueueMutex);
        liveMidiInputPendingForAudio.clear();
        liveMidiInputPendingForFlutter.clear();
    }
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
    r.gainProc->gain->setValueNotifyingHost(
        juce::jlimit(kGainUiMin, kGainUiMax, r.gainUi) / kGainUiMax);
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
        {
            sanitiseAutomationPoints(r.automationPoints, 1.0f);
            r.automationProc->setAutomationPoints(r.automationPoints);
        }
    }

    for (int ch = 0; ch < 2; ++ch)
    {
        graph.addConnection({{r.inputNode->nodeID, ch}, {r.automationNode->nodeID, ch}});
        graph.addConnection({{r.automationNode->nodeID, ch}, {r.gainNode->nodeID, ch}});
        graph.addConnection({{r.gainNode->nodeID, ch}, {r.panNode->nodeID, ch}});
        graph.addConnection({{r.panNode->nodeID, ch}, {r.meterTapNode->nodeID, ch}});
    }

    if (masterInputNode != nullptr)
        connectStereo(graph, r.meterTapNode->nodeID, masterInputNode->nodeID);
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

    if (!isProjectClipLoadTransactionActive())
        armOutputSafetyForCurrentRoute();
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

    const double sampleRate =
        getKnownDeviceSampleRate(deviceManager, hostSampleRateAtomic.load(std::memory_order_relaxed));
    const int blockSize = getKnownDeviceBufferSize(deviceManager, 512);

    hostSampleRateAtomic.store(sampleRate, std::memory_order_relaxed);

    // MASTER gain + pan
    {
        auto mi = std::make_unique<TrackInputProcessor>();
        masterInputProcessor = mi.get();
        masterInputNode = graph.addNode(std::move(mi));

        auto mg = std::make_unique<SimpleGainProcessor>();
        masterGainProcessor = mg.get();
        masterGainNode = graph.addNode(std::move(mg));
        masterGainProcessor->gain->setValueNotifyingHost(
            juce::jlimit(kGainUiMin, kGainUiMax, masterGainUi) / kGainUiMax);
        masterGainProcessor->setMuted(masterMuted);

        auto mp = std::make_unique<StereoPanProcessor>();
        masterPanProcessor = mp.get();
        masterPanNode = graph.addNode(std::move(mp));
        masterPanProcessor->pan->setValueNotifyingHost(
            panUIToNormalized(masterPanUi));

        if (masterInputNode != nullptr)
            connectStereo(graph, masterInputNode->nodeID, masterGainNode->nodeID);
        connectStereo(graph, masterGainNode->nodeID, masterPanNode->nodeID);
        connectStereo(graph, masterPanNode->nodeID, outputNode->nodeID);
    }

    if (masterEffectChain == nullptr)
        masterEffectChain = new juce::Array<juce::AudioProcessorGraph::NodeID>();

    // Row meters enabled already exist (atomic)
    // Create per-row chain: Input -> [Row FX] -> Automation -> Gain -> Pan -> MeterTap -> Master input
    for (auto &r : rows)
        attachRowBusNodes(r);

    busGraphInitialised = true;
    if (!isProjectClipLoadTransactionActive())
        armOutputSafetyForCurrentRoute();
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

void JuceEngine::beginProjectClipLoadTransaction()
{
    ++projectClipLoadTransactionDepth;
}

void JuceEngine::endProjectClipLoadTransaction()
{
    if (projectClipLoadTransactionDepth <= 0)
        return;

    --projectClipLoadTransactionDepth;
    if (projectClipLoadTransactionDepth > 0)
        return;

    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);
    graph.rebuild();
    armOutputSafetyForCurrentRoute();
}

bool JuceEngine::loadClip(int clipId, int rowId, const juce::File &file,
                          double startSec, double lengthSec, double inFileOffsetSec)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
        &blockIsPlayingAtomic);

    player->setTimeline(safeStartSec, resolvedLengthSec, safeOffsetSec);
    player->setStretchOptions(1.0, false);

    // Batch graph mutations for clip insertion so large sessions (many rows/nodes)
    // pay one graph rebuild instead of many synchronous rebuilds.
    constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;

    auto playerNode = graph.addNode(std::move(player), std::nullopt, batchUpdate);

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
    c.panNormalized = 0.0f;
    c.sourceFilePath = file.getFullPathName();
    c.midiInstrumentId = {};
    c.midiInstrumentName = {};
    c.midiNotes.clear();
    c.midiParams = {};
    c.midiSourceTempoBpm = 120.0;

    c.playerNode = playerNode;
    c.fxChain.clear();
    c.wired = false;
    c.lastRowInputNodeUid = 0;
    addClipToRowIndex(c.rowId, clipId);

    if (auto *p = asTimelineProcessor(c.playerNode))
    {
        p->setGainUi(kGainUiUnity);
        p->setPanNormalized(0.0f);
    }

    rewireTrackChain(clipId, batchUpdate);
    if (isProjectClipLoadTransactionActive())
        return true;

    graph.rebuild();
    armOutputSafetyForCurrentRoute();
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
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
        &blockIsPlayingAtomic);
    player->setTimeline(safeStartSec, resolvedLengthSec, safeOffsetSec);
    player->setStretchOptions(1.0, true);
    if (!TimelineMidiClipProcessor::canResolveSampledInstrument(
            instrumentId,
            instrumentName))
    {
        juce::Logger::writeToLog(
            "Live MIDI load failed sampled instrument resolution. instrumentId=" +
            instrumentId +
            " instrumentName=" + instrumentName);
        return false;
    }
    player->setMidiData(notes, instrumentId, instrumentName, params, safeSourceTempo);

    constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;
    auto playerNode = graph.addNode(std::move(player), std::nullopt, batchUpdate);

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
    c.reversed = false;
    c.tempoRatio = 1.0;
    c.preservePitch = true;
    c.gainUi = kGainUiUnity;
    c.panNormalized = 0.0f;
    c.sourceFilePath = {};
    c.midiInstrumentId = instrumentId;
    c.midiInstrumentName = instrumentName;
    c.midiNotes = notes;
    c.midiParams = params;
    c.midiSourceTempoBpm = safeSourceTempo;

    c.playerNode = playerNode;
    c.fxChain.clear();
    c.wired = false;
    c.lastRowInputNodeUid = 0;
    addClipToRowIndex(c.rowId, clipId);

    if (auto *p = asTimelineProcessor(c.playerNode))
    {
        p->setGainUi(kGainUiUnity);
        p->setPanNormalized(0.0f);
    }

    rewireTrackChain(clipId, batchUpdate);
    if (isProjectClipLoadTransactionActive())
        return true;

    graph.rebuild();
    armOutputSafetyForCurrentRoute();
    return true;
}

bool JuceEngine::updateMidiClipEvents(int clipId,
                                      const juce::String &instrumentId,
                                      const juce::String &instrumentName,
                                      const juce::Array<TimelineMidiNote> &notes,
                                      const juce::NamedValueSet &params,
                                      double sourceTempoBpm)
{
    if (!TimelineMidiClipProcessor::canResolveSampledInstrument(
            instrumentId,
            instrumentName))
    {
        return false;
    }

    if (clips.empty() || clipId < 0 || clipId >= (int)clips.size())
        return false;

    auto &c = clips[(size_t)clipId];
    if (!c.alive || !c.isMidi || c.playerNode == nullptr)
        return false;

    auto *p = dynamic_cast<TimelineMidiClipProcessor *>(c.playerNode->getProcessor());
    if (p == nullptr)
        return false;

    const double safeSourceTempo = clampSourceTempo(sourceTempoBpm);
    c.midiInstrumentId = instrumentId;
    c.midiInstrumentName = instrumentName;
    c.midiNotes = notes;
    c.midiParams = params;
    c.midiSourceTempoBpm = safeSourceTempo;
    p->setMidiData(notes, instrumentId, instrumentName, params, safeSourceTempo);
    return true;
}

bool JuceEngine::setLiveMidiInputTargetClip(int clipId)
{
    if (clipId >= 0)
    {
        if (clips.empty() || clipId >= (int)clips.size())
            return false;

        const auto &c = clips[(size_t)clipId];
        if (!c.alive || !c.isMidi || c.playerNode == nullptr)
            return false;

        if (!midiInputCallbacksInitialized.load(std::memory_order_relaxed))
            refreshMidiInputCallbacks();
    }

    liveMidiInputTargetClip.store(clipId, std::memory_order_relaxed);
    const std::lock_guard<std::mutex> lock(liveMidiInputQueueMutex);
    liveMidiInputPendingForAudio.clear();
    liveMidiInputPendingForFlutter.clear();
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
    if (!c.alive || !c.isMidi || c.playerNode == nullptr)
        return false;

    auto *proc = dynamic_cast<TimelineMidiClipProcessor *>(c.playerNode->getProcessor());
    if (proc == nullptr)
        return false;

    const int safePitch = juce::jlimit(0, 127, pitch);
    const float safeVelocity = juce::jlimit(0.0f, 1.0f, velocity);
    const int safeDurationMs = juce::jlimit(60, 4000, durationMs);

    proc->enqueueLiveMidiEvent(false, 1, safePitch, 0.0f);
    proc->enqueueLiveMidiEvent(true, 1, safePitch, safeVelocity);
    juce::Timer::callAfterDelay(
        safeDurationMs,
        [clipId, safePitch]
        {
            juce::MessageManager::callAsync(
                [clipId, safePitch]
                {
                    auto &engine = JuceEngine::get();
                    if (engine.clips.empty() ||
                        clipId < 0 ||
                        clipId >= (int)engine.clips.size())
                        return;

                    auto &clip = engine.clips[(size_t)clipId];
                    if (!clip.alive || !clip.isMidi || clip.playerNode == nullptr)
                        return;

                    auto *activeProc = dynamic_cast<TimelineMidiClipProcessor *>(
                        clip.playerNode->getProcessor());
                    if (activeProc == nullptr)
                        return;

                    activeProc->enqueueLiveMidiEvent(false, 1, safePitch, 0.0f);
                });
        });
    return true;
}

std::vector<JuceEngine::LiveMidiInputEvent> JuceEngine::consumeLiveMidiInputEvents()
{
    std::vector<LiveMidiInputEvent> out;
    const std::lock_guard<std::mutex> lock(liveMidiInputQueueMutex);
    out.swap(liveMidiInputPendingForFlutter);
    return out;
}

void JuceEngine::dispatchQueuedLiveMidiInputEventsForAudioThread()
{
    std::vector<LiveMidiInputEvent> pending;
    {
        std::unique_lock<std::mutex> lock(liveMidiInputQueueMutex, std::try_to_lock);
        if (!lock.owns_lock())
            return;
        if (liveMidiInputPendingForAudio.empty())
            return;
        pending.swap(liveMidiInputPendingForAudio);
    }

    for (const auto &event : pending)
    {
        if (event.clipId < 0 || event.clipId >= (int)clips.size())
            continue;

        auto &c = clips[(size_t)event.clipId];
        if (!c.alive || !c.isMidi || c.playerNode == nullptr)
            continue;

        auto *proc =
            dynamic_cast<TimelineMidiClipProcessor *>(c.playerNode->getProcessor());
        if (proc == nullptr)
            continue;

        proc->enqueueLiveMidiEvent(
            event.noteOn,
            event.channel,
            event.pitch,
            event.velocity);
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

    const std::lock_guard<std::mutex> lock(liveMidiInputQueueMutex);
    liveMidiInputPendingForAudio.push_back(event);
    liveMidiInputPendingForFlutter.push_back(event);

    constexpr size_t kMaxBufferedEvents = 4096;
    if (liveMidiInputPendingForAudio.size() > kMaxBufferedEvents)
    {
        liveMidiInputPendingForAudio.erase(
            liveMidiInputPendingForAudio.begin(),
            liveMidiInputPendingForAudio.begin() +
                (std::ptrdiff_t)(liveMidiInputPendingForAudio.size() - kMaxBufferedEvents));
    }
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
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

    if (clips.empty() || clipId < 0 || clipId >= (int)clips.size())
        return false;

    ClipState &c = clips[clipId];
    if (!c.alive)
        return true;

    constexpr auto batchUpdate = juce::AudioProcessorGraph::UpdateKind::none;
    clearClipGraphNodes(clipId, batchUpdate);
    if (isProjectClipLoadTransactionActive())
        return true;

    graph.rebuild();
    armOutputSafetyForCurrentRoute();
    return true;
}

void JuceEngine::clearClipGraphNodes(
    int clipId,
    juce::AudioProcessorGraph::UpdateKind updateKind)
{
    if (clips.empty() || clipId < 0 || clipId >= (int)clips.size())
        return;

    ClipState &c = clips[(size_t)clipId];
    if (!c.alive)
        return;

    const int previousRowId = c.rowId;
    c.wired = false;
    c.lastRowInputNodeUid = 0;

    for (auto id : c.fxChain)
        graph.removeNode(id, updateKind);

    if (c.playerNode)
        graph.removeNode(c.playerNode->nodeID, updateKind);

    removeClipFromRowIndex(previousRowId, clipId);
    c = ClipState();
    if (liveMidiInputTargetClip.load(std::memory_order_relaxed) == clipId)
    {
        liveMidiInputTargetClip.store(-1, std::memory_order_relaxed);
        const std::lock_guard<std::mutex> lock(liveMidiInputQueueMutex);
        liveMidiInputPendingForAudio.clear();
        liveMidiInputPendingForFlutter.clear();
    }
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
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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

    removeClipFromRowIndex(c.rowId, clipId);
    c.rowId = resolvedRowId;
    addClipToRowIndex(c.rowId, clipId);
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
        "Limiter",
        "Clipper",
        "De-Esser",
        "Distortion",
        "Degrade",
        "Delay",
        "Reverb",
        "EQ Parametric",
        "Pitch Shift",
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
    float panNormalized = 0.0f;
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

struct ExportProjectSnapshot
{
    std::vector<ExportClipSnapshot> clips;
    std::vector<ExportRowSnapshot> rows;
    std::vector<ExportEffectSnapshot> masterEffects;
    std::vector<ExportEffectAutomationLane> masterEffectAutomationLanes;
    std::vector<AutomationPoint> masterGainAutomationPoints;
    std::vector<AutomationPoint> masterPanAutomationPoints;
    float masterGainUi = SimpleGainProcessor::kUiUnity;
    float masterPanUi = 0.5f;
    bool masterMuted = false;
    double tempoBpm = 120.0;
};

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

struct OfflineExportContext
{
    juce::AudioProcessorGraph graph;
    juce::AudioProcessorGraph::Node::Ptr outputNode;
    std::vector<OfflineClipRenderState> clips;
    std::vector<OfflineRowRenderState> rows;
    std::unordered_map<int, int> rowIdToIndex;
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
        if (pluginId == "Limiter")
            return std::make_unique<LimiterAudioProcessor>();
        if (pluginId == "Clipper")
            return std::make_unique<ClipperAudioProcessor>();
        if (pluginId == "Pitch Shift")
            return std::make_unique<PitchShiftAudioProcessor>();
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
    processor.setPanNormalized(clip.panNormalized);
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
        clip.panNormalized = (float)juce::jlimit(-1.0, 1.0, readJsonDoubleProperty(clipObject, "panNormalized", 0.0));
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
        connectStereo(context.graph, panNode->nodeID, context.master.inputNode->nodeID);

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
                if (shouldUseOfflineStaticAudioClipProcessor(clipSnapshot))
                {
                    auto processor = std::make_unique<OfflineStaticAudioClipProcessor>(
                        std::move(reader),
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
                    const auto totalLength = reader->lengthInSamples;
                    auto readerSource =
                        std::make_unique<juce::AudioFormatReaderSource>(reader.release(), true);
                    auto processor = std::make_unique<TimelineClipProcessor>(
                        std::move(readerSource),
                        totalLength,
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
        if (!clip.alive || clip.playerNode == nullptr)
            continue;

        if (auto *processor = asTimelineProcessor(clip.playerNode))
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
            processor->setPanNormalized(clip.panNormalized);
        }
    }
}

void JuceEngine::rebuildClipProcessorsFromStoredStateLocked(
    juce::AudioProcessorGraph::UpdateKind updateKind)
{
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
        processor.setPanNormalized(clip.panNormalized);
    };

    bool rebuiltAny = false;

    for (size_t clipIndex = 0; clipIndex < clips.size(); ++clipIndex)
    {
        auto &clip = clips[clipIndex];
        if (!clip.alive)
            continue;

        juce::AudioProcessorGraph::Node::Ptr rebuiltPlayerNode;

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
            rebuiltPlayerNode = graph.addNode(std::move(player), std::nullopt, updateKind);
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
            std::unique_ptr<juce::AudioFormatReader> reader(
                formatManager.createReaderFor(sourceFile));
            if (!reader)
            {
                juceLogToFlutter(
                    "Skipping clip rebuild for export: could not reopen audio source.");
                continue;
            }

            const auto totalLength = reader->lengthInSamples;
            auto readerSource =
                std::make_unique<juce::AudioFormatReaderSource>(reader.release(), true);
            auto player = std::make_unique<TimelineClipProcessor>(
                std::move(readerSource),
                totalLength,
                sourceFile,
                &blockTransportStartSec,
                &hostSampleRateAtomic,
                &blockIsPlayingAtomic);
            applyClipProcessorState(clip, *player);
            rebuiltPlayerNode = graph.addNode(std::move(player), std::nullopt, updateKind);
        }

        if (rebuiltPlayerNode == nullptr)
            continue;

        const auto previousNode = clip.playerNode;
        clip.playerNode = rebuiltPlayerNode;
        clip.wired = false;
        clip.lastRowInputNodeUid = 0;
        if (previousNode != nullptr)
            graph.removeNode(previousNode->nodeID, updateKind);
        rewireTrackChain((int)clipIndex, updateKind);
        rebuiltAny = true;
    }

    if (rebuiltAny)
        graph.rebuild();
}

void JuceEngine::primeClipProcessorsForOfflineRenderLocked()
{
    for (auto &clip : clips)
    {
        if (!clip.alive || clip.playerNode == nullptr)
            continue;

        if (auto *processor = asTimelineProcessor(clip.playerNode))
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
            clipSnapshot.panNormalized = clip.panNormalized;
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
            clipSnapshot.panNormalized = clip.panNormalized;
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
        GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);
        ensureMasterOutputRouting();
    }

    auto *dev = deviceManager.getCurrentAudioDevice();
    const bool missingOutputRoute =
        (dev == nullptr) || (dev->getActiveOutputChannels().countNumberOfSetBits() <= 0);
    if (missingOutputRoute)
    {
        const int desiredInputs =
            desiredInputOpenChannels.load(std::memory_order_relaxed);
        if (applyPreferredAudioDeviceSetup(desiredInputs, true, "play-recover-output"))
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

void JuceEngine::pause()
{
    isPlayingAtomic.store(false, std::memory_order_relaxed);
    mixroom::fx::setGlobalTransportPlaying(false);

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
    if (clips.empty() || trackIndex < 0 || trackIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)trackIndex];
    if (!c.alive || c.playerNode == nullptr)
        return;

    c.muted = shouldBypass;
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

// ============================================================
// Video audio lane (kept as you had; minor safety only)
// ============================================================
void JuceEngine::loadVideoAudio(const juce::File &file)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
                graph.addConnection({{videoAudioNode->nodeID, ch}, {gainNode->nodeID, ch}});
                graph.addConnection({{gainNode->nodeID, ch}, {outputNode->nodeID, ch}});
            }
        }

        videoAudioNode->setBypassed(true);
        hasVideoAudio = true;
        armOutputSafetyForCurrentRoute();
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
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
    armOutputSafetyForCurrentRoute();
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
void JuceEngine::rewireTrackBusFxChain(int row)
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
    clearStereoConnectionsBetweenNodes(graph, localNodes);

    auto prevNodeId = inputNodeId;

    for (int i = 0; i < chain.size(); ++i)
    {
        auto nodeID = chain.getReference(i);
        if (graph.getNodeForId(nodeID) != nullptr)
        {
            connectStereo(graph, prevNodeId, nodeID);
            prevNodeId = nodeID;
        }
    }

    connectStereo(graph, prevNodeId, automationNodeId);

    if (!isProjectClipLoadTransactionActive())
        armOutputSafetyForCurrentRoute();
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

            for (int ch = 0; ch < 2; ++ch)
            {
                if (!isGraphConnectionPresent(row.meterTapNode->nodeID, masterInputNode->nodeID, ch))
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

    rewireMasterFxChain();
    graph.rebuild();
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
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
        else if (pluginPath == "Degrade")
            plugin = std::make_unique<DegradeAudioProcessor>();
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
        else if (pluginPath == "Stereo")
            plugin = std::make_unique<StereoAudioProcessor>();
        else if (pluginPath == "Stereo Pro")
            plugin = std::make_unique<StereoProAudioProcessor>();
        else if (pluginPath == "Volume Shaper")
            plugin = std::make_unique<VolumeShaperAudioProcessor>();
        else if (pluginPath == "Time Shaper")
            plugin = std::make_unique<TimeShaperAudioProcessor>();
        else if (pluginPath == "Gain")
            plugin = std::make_unique<SimpleGainProcessor>();
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
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

    // juceLogToFlutter("Hello from JuceEngine::removeTrackEffect");

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return;

    compactRowFxChain(trackRow);
    auto &chain = rows[(size_t)trackRow].fxChain;
    if (effectIndex < 0 || effectIndex >= chain.size())
        return;

    const auto nodeID = chain.getReference(effectIndex);

    chain.removeRange(effectIndex, 1);
    auto &fxIds = rows[(size_t)trackRow].fxIds;
    if (effectIndex >= 0 && effectIndex < fxIds.size())
        fxIds.removeRange(effectIndex, 1);

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

    rewireTrackBusFxChain(trackRow);

    juce::Array<AudioProcessorGraph::Connection> nodeConnections;
    for (const auto &connection : graph.getConnections())
    {
        if (connection.source.nodeID == nodeID ||
            connection.destination.nodeID == nodeID)
            nodeConnections.addIfNotAlreadyThere(connection);
    }
    for (const auto &connection : nodeConnections)
        graph.removeConnection(connection);
    if (graph.getNodeForId(nodeID) != nullptr)
        graph.removeNode(nodeID);
}

void JuceEngine::reorderTrackEffects(int trackRow, int fromIndex, int toIndex)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
    const int finalToIndex = toIndex;
    if (fromIndex >= 0 && fromIndex < fxIds.size())
    {
        fxIds.remove(fromIndex);
        const int idToIndex = juce::jlimit(0, fxIds.size(), finalToIndex);
        fxIds.insert(idToIndex, fxId);
    }

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

    rewireTrackBusFxChain(trackRow);
}

juce::StringArray JuceEngine::getTrackEffectsForRow(int trackRow)
{
    juce::StringArray names;

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return names;

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

juce::StringArray JuceEngine::getTrackEffectInstanceIdsForRow(int trackRow)
{
    juce::StringArray ids;

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return ids;

    auto &chain = rows[(size_t)trackRow].fxChain;

    for (auto &nodeID : chain)
        ids.add(juce::String((juce::int64)nodeID.uid));

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

void JuceEngine::bypassRowEffect(int trackRow, int effectIndex, bool shouldBypass)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
        return;
    }

    laneIt->minValue = rangeMin;
    laneIt->maxValue = rangeMax;
    laneIt->points = std::move(safePoints);
    laneIt->lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
}

void JuceEngine::clearTrackEffectAutomationForRow(int trackRow)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

    if (trackRow < 0 || trackRow >= (int)rows.size())
        return;
    rows[(size_t)trackRow].effectAutomationLanes.clear();
}

void JuceEngine::setRowGainAutomationPoints(
    int row,
    const std::vector<AutomationPoint> &points)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

    if (row < 0 || row >= (int)rows.size())
        return;

    auto safePoints = points;
    sanitiseAutomationPoints(safePoints, 1.0f);
    rows[(size_t)row].gainAutomationPoints = std::move(safePoints);
    rows[(size_t)row].lastAppliedGainAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
}

void JuceEngine::setRowPanAutomationPoints(
    int row,
    const std::vector<AutomationPoint> &points)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

    if (row < 0 || row >= (int)rows.size())
        return;

    auto safePoints = points;
    sanitiseAutomationPoints(safePoints, 1.0f);
    rows[(size_t)row].panAutomationPoints = std::move(safePoints);
    rows[(size_t)row].lastAppliedPanAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
}

void JuceEngine::setMasterEffectAutomationPoints(
    int effectIndex,
    const juce::String &paramId,
    float minValue,
    float maxValue,
    const std::vector<AutomationPoint> &points)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
        return;
    }

    laneIt->minValue = rangeMin;
    laneIt->maxValue = rangeMax;
    laneIt->points = std::move(safePoints);
    laneIt->lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
}

void JuceEngine::clearMasterEffectAutomation()
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);
    masterEffectAutomationLanes.clear();
}

void JuceEngine::setMasterGainAutomationPoints(
    const std::vector<AutomationPoint> &points)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

    auto safePoints = points;
    sanitiseAutomationPoints(safePoints, 1.0f);
    masterGainAutomationPoints = std::move(safePoints);
    lastAppliedMasterGainAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
}

void JuceEngine::setMasterPanAutomationPoints(
    const std::vector<AutomationPoint> &points)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

    auto safePoints = points;
    sanitiseAutomationPoints(safePoints, 1.0f);
    masterPanAutomationPoints = std::move(safePoints);
    lastAppliedMasterPanAutomationNormalized = std::numeric_limits<float>::quiet_NaN();
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

void JuceEngine::applyTrackEffectAutomationAtTimeSeconds(double timeSeconds)
{
    constexpr float kAutomationEpsilon = 1.0e-4f;
    const double timeMs = juce::jmax(0.0, timeSeconds) * 1000.0;

    for (int rowIndex = 0; rowIndex < (int)rows.size(); ++rowIndex)
    {
        auto &rowState = rows[(size_t)rowIndex];

        if (!rowState.gainAutomationPoints.empty())
        {
            const float normalized = juce::jlimit(
                0.0f,
                1.0f,
                (float)evaluateAutomationValueAtMs(rowState.gainAutomationPoints, timeMs, 0.0));
            if (!std::isfinite(rowState.lastAppliedGainAutomationNormalized) ||
                std::abs(normalized - rowState.lastAppliedGainAutomationNormalized) > kAutomationEpsilon)
            {
                const float gain = kGainUiMin + (kGainUiMax - kGainUiMin) * normalized;
                setRowGain(rowIndex, gain);
                rowState.lastAppliedGainAutomationNormalized = normalized;
            }
        }

        if (!rowState.panAutomationPoints.empty())
        {
            const float pan = juce::jlimit(
                0.0f,
                1.0f,
                (float)evaluateAutomationValueAtMs(rowState.panAutomationPoints, timeMs, 0.5));
            if (!std::isfinite(rowState.lastAppliedPanAutomationNormalized) ||
                std::abs(pan - rowState.lastAppliedPanAutomationNormalized) > kAutomationEpsilon)
            {
                setRowPan(rowIndex, pan);
                rowState.lastAppliedPanAutomationNormalized = pan;
            }
        }

        if (rowState.effectAutomationLanes.empty())
            continue;

        for (auto &lane : rowState.effectAutomationLanes)
        {
            if (lane.effectIndex < 0 || lane.effectIndex >= rowState.fxChain.size())
                continue;
            if (lane.paramId.trim().isEmpty())
                continue;
            if (lane.points.empty())
                continue;

            const float normalized = juce::jlimit(
                0.0f,
                1.0f,
                (float)evaluateAutomationValueAtMs(lane.points, timeMs, 0.0));
            if (std::isfinite(lane.lastAppliedNormalized) &&
                std::abs(normalized - lane.lastAppliedNormalized) <= kAutomationEpsilon)
                continue;

            const float value = lane.minValue + (lane.maxValue - lane.minValue) * normalized;
            setTrackEffectParameter(
                rowIndex,
                lane.effectIndex,
                lane.paramId,
                juce::var((double)value));
            lane.lastAppliedNormalized = normalized;
        }
    }

    if (!masterGainAutomationPoints.empty())
    {
        const float normalized = juce::jlimit(
            0.0f,
            1.0f,
            (float)evaluateAutomationValueAtMs(masterGainAutomationPoints, timeMs, 0.0));
        if (!std::isfinite(lastAppliedMasterGainAutomationNormalized) ||
            std::abs(normalized - lastAppliedMasterGainAutomationNormalized) > kAutomationEpsilon)
        {
            const float gain = kGainUiMin + (kGainUiMax - kGainUiMin) * normalized;
            setMasterGain(gain);
            lastAppliedMasterGainAutomationNormalized = normalized;
        }
    }

    if (!masterPanAutomationPoints.empty())
    {
        const float pan = juce::jlimit(
            0.0f,
            1.0f,
            (float)evaluateAutomationValueAtMs(masterPanAutomationPoints, timeMs, 0.5));
        if (!std::isfinite(lastAppliedMasterPanAutomationNormalized) ||
            std::abs(pan - lastAppliedMasterPanAutomationNormalized) > kAutomationEpsilon)
        {
            setMasterPan(pan);
            lastAppliedMasterPanAutomationNormalized = pan;
        }
    }

    if (masterEffectAutomationLanes.empty())
        return;

    for (auto &lane : masterEffectAutomationLanes)
    {
        if (lane.effectIndex < 0 || masterEffectChain == nullptr ||
            lane.effectIndex >= masterEffectChain->size())
            continue;
        if (lane.paramId.trim().isEmpty())
            continue;
        if (lane.points.empty())
            continue;

        const float normalized = juce::jlimit(
            0.0f,
            1.0f,
            (float)evaluateAutomationValueAtMs(lane.points, timeMs, 0.0));
        if (std::isfinite(lane.lastAppliedNormalized) &&
            std::abs(normalized - lane.lastAppliedNormalized) <= kAutomationEpsilon)
            continue;
        const float value = lane.minValue + (lane.maxValue - lane.minValue) * normalized;
        setMasterEffectParameter(
            lane.effectIndex,
            lane.paramId,
            juce::var((double)value));
        lane.lastAppliedNormalized = normalized;
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
}

void JuceEngine::addClipToRowIndex(int rowId, int clipId)
{
    rowIdToClipIds[rowId].addIfNotAlreadyThere(clipId);
}

void JuceEngine::removeClipFromRowIndex(int rowId, int clipId)
{
    const auto it = rowIdToClipIds.find(rowId);
    if (it == rowIdToClipIds.end())
        return;

    it->second.removeAllInstancesOf(clipId);
    if (it->second.isEmpty())
        rowIdToClipIds.erase(it);
}

// ============================================================
// Row-level gain / mute / pan
// ============================================================
void JuceEngine::setRowGain(int row, float gain)
{
    if (row < 0 || row >= (int)rows.size())
        return;

    rows[(size_t)row].gainUi = juce::jlimit(kGainUiMin, kGainUiMax, gain);
    if (rows[(size_t)row].gainProc != nullptr)
        rows[(size_t)row].gainProc->gain->setValueNotifyingHost(
            rows[(size_t)row].gainUi / kGainUiMax);
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
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
        else if (pluginPath == "Degrade")
            plugin = std::make_unique<DegradeAudioProcessor>();
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
        else if (pluginPath == "Stereo")
            plugin = std::make_unique<StereoAudioProcessor>();
        else if (pluginPath == "Stereo Pro")
            plugin = std::make_unique<StereoProAudioProcessor>();
        else if (pluginPath == "Volume Shaper")
            plugin = std::make_unique<VolumeShaperAudioProcessor>();
        else if (pluginPath == "Time Shaper")
            plugin = std::make_unique<TimeShaperAudioProcessor>();
        else if (pluginPath == "Gain")
            plugin = std::make_unique<SimpleGainProcessor>();
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
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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

    rewireMasterFxChain();

    juce::Array<AudioProcessorGraph::Connection> nodeConnections;
    for (const auto &connection : graph.getConnections())
    {
        if (connection.source.nodeID == nodeID ||
            connection.destination.nodeID == nodeID)
            nodeConnections.addIfNotAlreadyThere(connection);
    }
    for (const auto &connection : nodeConnections)
        graph.removeConnection(connection);
    if (graph.getNodeForId(nodeID) != nullptr)
        graph.removeNode(nodeID);
}

void JuceEngine::reorderMasterEffects(int fromIndex, int toIndex)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
    masterGainUi = juce::jlimit(kGainUiMin, kGainUiMax, gain);
    if (masterGainProcessor)
        masterGainProcessor->gain->setValueNotifyingHost(
            masterGainUi / kGainUiMax);
}

void JuceEngine::muteMaster(bool mute)
{
    masterMuted = mute;
    if (masterGainProcessor)
        masterGainProcessor->setMuted(mute);
}

void JuceEngine::setMasterPan(float pan)
{
    masterPanUi = juce::jlimit(0.0f, 1.0f, pan);
    if (masterPanProcessor)
        masterPanProcessor->pan->setValueNotifyingHost(
            panUIToNormalized(masterPanUi));
}

// ============================================================
// Master FX Chain Rewire
// ============================================================
void JuceEngine::rewireMasterFxChain()
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
    clearStereoConnectionsBetweenNodes(graph, localNodes);

    for (auto &row : rows)
    {
        if (row.meterTapNode == nullptr)
            continue;

        disconnectStereo(graph, row.meterTapNode->nodeID, masterInputNode->nodeID);
        disconnectStereo(graph, row.meterTapNode->nodeID, masterGainNode->nodeID);
        disconnectStereo(graph, row.meterTapNode->nodeID, masterPanNode->nodeID);
        disconnectStereo(graph, row.meterTapNode->nodeID, outputNode->nodeID);
        for (auto fx : *masterEffectChain)
            disconnectStereo(graph, row.meterTapNode->nodeID, fx);
        connectStereo(graph, row.meterTapNode->nodeID, masterInputNode->nodeID);
    }

    auto prevNodeId = masterInputNode->nodeID;
    for (auto fx : *masterEffectChain)
    {
        if (graph.getNodeForId(fx) == nullptr)
            continue;
        connectStereo(graph, prevNodeId, fx);
        prevNodeId = fx;
    }

    connectStereo(graph, prevNodeId, masterGainNode->nodeID);
    connectStereo(graph, masterGainNode->nodeID, masterPanNode->nodeID);
    connectStereo(graph, masterPanNode->nodeID, outputNode->nodeID);

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
    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)clipIndex];
    if (!c.alive || c.playerNode == nullptr)
        return;

    c.gainUi = juce::jlimit(kGainUiMin, kGainUiMax, gain);

    if (auto *p = asTimelineProcessor(c.playerNode))
        p->setGainUi(c.gainUi);
}

void JuceEngine::muteClip(int clipIndex, bool shouldMute)
{
    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)clipIndex];
    if (!c.alive || c.playerNode == nullptr)
        return;

    c.muted = shouldMute;

    if (auto *p = asTimelineProcessor(c.playerNode))
        p->setMuted(shouldMute);
}

void JuceEngine::setClipPan(int clipIndex, float pan)
{
    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)clipIndex];
    if (!c.alive || c.playerNode == nullptr)
        return;

    c.panNormalized = panUIToNormalized(pan);

    if (auto *p = asTimelineProcessor(c.playerNode))
        p->setPanNormalized(c.panNormalized);
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

void JuceEngine::setClipReversed(int clipIndex, bool shouldReverse)
{
    if (clips.empty() || clipIndex < 0 || clipIndex >= (int)clips.size())
        return;

    auto &c = clips[(size_t)clipIndex];
    if (!c.alive || c.playerNode == nullptr)
        return;

    c.reversed = shouldReverse;

    if (auto *p = asTimelineProcessor(c.playerNode))
        p->setReversed(c.reversed);
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

void JuceEngine::setLiveInputMonitoringEnabled(bool enabled)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);
    if (liveInputMonitoringEnabled == enabled)
        return;

    liveInputMonitoringEnabled = enabled;
    syncLiveInputMonitorRoutingLocked();
}

bool JuceEngine::isLiveInputMonitoringEnabled() const noexcept
{
    return liveInputMonitoringEnabled;
}

void JuceEngine::clearLiveInputMonitorConnectionsLocked()
{
    for (auto &connection : liveMonitorConnections)
        graph.removeConnection(connection);
    liveMonitorConnections.clear();
}

void JuceEngine::syncLiveInputMonitorRoutingLocked()
{
    clearLiveInputMonitorConnectionsLocked();

    if (!liveInputMonitoringEnabled || !inputNode || rows.empty())
    {
        armOutputSafetyForCurrentRoute();
        return;
    }

    const int row = juce::jlimit(0, (int)rows.size() - 1, liveMonitorTargetRow);
    ensureRowBusNodesAttached(row);
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
        if (graph.addConnection(connection))
            liveMonitorConnections.add(connection);
    }

    armOutputSafetyForCurrentRoute();
}

void JuceEngine::routeLiveInputToRow(int row, int channelCount, int channelStart)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

    liveMonitorTargetRow = row;
    liveMonitorChannelCount = channelCount;
    liveMonitorChannelStart = channelStart;
    syncLiveInputMonitorRoutingLocked();
}

bool JuceEngine::startRecordingToWav(const juce::File &file,
                                     int channelStart,
                                     int channelCount)
{
    if (recordingActive)
        return false;

    const int previousDesiredInputs = desiredInputOpenChannels.load(std::memory_order_relaxed);
    juce::ignoreUnused(previousDesiredInputs);
    // Recording input prewarm intentionally opens inputs before capture starts.
    // Restoring that prewarm target after stop can leave Bluetooth in duplex
    // mode, so post-record should return to playback-only instead.
    recordingRestoreDesiredInputs.store(0, std::memory_order_relaxed);

    const auto failAndRestorePlaybackMode = [this]()
    {
        applyPreferredAudioDeviceSetup(0, true, "startRecording-restore");
        return false;
    };

    const int requiredInputs = juce::jmax(1, channelStart + channelCount);
    if (!applyPreferredAudioDeviceSetup(requiredInputs, false, "startRecording"))
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

    recorderStream.reset(file.createOutputStream().release());
    if (!recorderStream)
        return failAndRestorePlaybackMode();

    juce::WavAudioFormat wav;
    recorderWriter.reset(
        wav.createWriterFor(
            recorderStream.get(),
            getKnownDeviceSampleRate(
                deviceManager,
                hostSampleRateAtomic.load(std::memory_order_relaxed)),
            (unsigned int)channelCount,
            24,
            {},
            0));

    if (!recorderWriter)
        return failAndRestorePlaybackMode();

    recorderStream.release();

    recordChannelStart = channelStart;
    recordChannelOffset = channelStart;
    recordChannelCount = channelCount;

    routeLiveInputToRow(/*row=*/0, channelCount, channelStart);

    recordingActive = true;
    logCurrentAudioDeviceState("recording-started");
    return true;
}

void JuceEngine::stopRecording(bool restorePlaybackRoute)
{
    recordingActive = false;

    {
        juce::SpinLock::ScopedLockType lock(recordLock);
        recorderWriter.reset(); // flush + finalize WAV
        recorderStream.reset();
    }

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

    auto &chain = rows[(size_t)row].fxChain;
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

    auto &chain = rows[(size_t)row].fxChain;
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

    auto &chain = rows[(size_t)row].fxChain;
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

int JuceEngine::addRow(const juce::String &name, int iconId)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

    if ((int)rows.size() >= kMaxRows)
        return -1;

    RowState r;
    const int newRowId = nextRowId.fetch_add(1);
    r.rowId = newRowId;
    r.name = name.isNotEmpty() ? name : "Row";
    r.iconId = iconId;

    rows.push_back(std::move(r));
    rebuildRowIdIndexCache();

    if (engineInitialized)
    {
        ensureRowBusNodesAttached((int)rows.size() - 1);
        retargetRowMeterTapPointers();
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

int JuceEngine::insertRowAbove(int referenceRowId, const juce::String &name, int iconId)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
        ensureRowBusNodesAttached(insertIdx);
        retargetRowMeterTapPointers();
    }

    return newRowId;
}

int JuceEngine::insertRowBelow(int referenceRowId, const juce::String &name, int iconId)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
        ensureRowBusNodesAttached(insertIdx);
        retargetRowMeterTapPointers();
    }

    return newRowId;
}

bool JuceEngine::moveRowOrder(int fromIndex, int toIndex)
{
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

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

    // Delete clips that belong to this row only.
    juce::Array<int> removedClipIds;
    if (const auto it = rowIdToClipIds.find(rowId); it != rowIdToClipIds.end())
        removedClipIds = it->second;
    for (const auto clipId : removedClipIds)
        clearClipGraphNodes(clipId, juce::AudioProcessorGraph::UpdateKind::none);
    rowIdToClipIds.erase(rowId);

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

    graph.rebuild();
    armOutputSafetyForCurrentRoute();
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
    GraphMutationScope renderLock(deviceManager.getAudioCallbackLock(), graphRenderMutex);

    // 1) Remove connections that touch any row/master nodes
    // 2) Remove row bus nodes and master gain/pan nodes (keep FX nodes/chains)
    // 3) Recreate buses via ensureBusGraphInitialised()
    // 4) Rewire row/master FX chains and every alive clip

    // Remove ALL connections first (safe & easiest)
    auto conns = graph.getConnections();
    for (auto &c : conns)
        graph.removeConnection(c);
    liveMonitorConnections.clear();

    // Existing clip chains are now disconnected.
    for (auto &clip : clips)
        clip.wired = false;

    // Remove master input/gain/pan nodes only (keep master FX nodes + chain IDs).
    if (masterInputNode)
        graph.removeNode(masterInputNode->nodeID);
    if (masterGainNode)
        graph.removeNode(masterGainNode->nodeID);
    if (masterPanNode)
        graph.removeNode(masterPanNode->nodeID);
    masterInputNode = nullptr;
    masterGainNode = nullptr;
    masterPanNode = nullptr;
    masterInputProcessor = nullptr;
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

    syncLiveInputMonitorRoutingLocked();
    if (!isProjectClipLoadTransactionActive())
        armOutputSafetyForCurrentRoute();
}

const juce::StringArray JuceEngine::mixroomPlugins{
    "Gain",
    "EQ 3-Band",
    "Compressor",
    "Limiter",
    "Clipper",
    "De-Esser",
    "Distortion",
    "Degrade",
    "Delay",
    "Reverb",
    "EQ Parametric",
    "Pitch Shift",
    "Chorus",
    "Vibrato",
    "Stereo",
    "Stereo Pro",
    "Volume Shaper",
    "Time Shaper",
};
