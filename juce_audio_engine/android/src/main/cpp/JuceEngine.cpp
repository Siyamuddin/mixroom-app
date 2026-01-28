#include "JuceEngine.h"
#include <future>
#include "JuceLogBridge.h" // Bring in the function
#include <unordered_map>
#include <juce_core/native/juce_JNIHelpers_android.h>
#include <android/log.h>

#define TAG "JUCE"

extern "C" void juceLogToFlutter(const char *msg);

using namespace juce;

JuceEngine &JuceEngine::get()
{
    static JuceEngine instance;
    // juceLogToFlutter("✅ JuceEngine::get() - singleton accessed");
    // __android_log_print(ANDROID_LOG_INFO, "JUCE", "✅ singleton accessed");
    return instance;
}

JuceEngine::JuceEngine() {}

JuceEngine::~JuceEngine() {}

// void JuceEngine::initialiseEngine() {
//     juceLogToFlutter("Hello from JuceEngine::initialiseEngine()");
//     __android_log_print(ANDROID_LOG_INFO, "JUCE", "✅ initializeEngine started new2");
//     if (engineInitialized) {
//         juceLogToFlutter("⚠️ JuceEngine::initialiseEngine() already called — skipping register formats.");
//         // return;
//     }
//     else {
//         formatManager.registerBasicFormats();
//         pluginFormatManager.addDefaultFormats();
//     }

//     engineInitialized = false;

//     __android_log_print(ANDROID_LOG_INFO, "JUCE", "✅ initializeEngine check");

//     #if JUCE_IOS
//     // juceLogToFlutter("iOS-only code running");
//     pluginFormatManager.addFormat(new juce::AudioUnitPluginFormat());
//     // auto session = [AVAudioSession sharedInstance];
//     // [session setCategory:AVAudioSessionCategoryPlayback error:nil];
//     // [session setActive:YES error:nil];
//     #endif
//     // Create the audio-output node
//     outputNode = graph.addNode(
//         std::make_unique<AudioProcessorGraph::AudioGraphIOProcessor>(
//             AudioProcessorGraph::AudioGraphIOProcessor::audioOutputNode));
//     // end of stuff in constructor

//     __android_log_print(ANDROID_LOG_INFO, "JUCE", "✅ initializeEngine check1");
//     // Get the app bundle root directory
//     auto appBundleRoot = juce::File::getSpecialLocation(juce::File::hostApplicationPath).getParentDirectory();

//     // // Use PluginDirectoryScanner as before, but with appBundleRoot as the search path
//     // for (int i = 0; i < pluginFormatManager.getNumFormats(); ++i) {
//     //     juce::PluginDirectoryScanner scanner(pluginList,
//     //                                          *pluginFormatManager.getFormat(i),
//     //                                          juce::FileSearchPath(appBundleRoot.getFullPathName()),
//     //                                          true, juce::File());
//     //     juce::String err;
//     //     while (scanner.scanNextFile(false, err)) {}
//     // }

//     // for (auto plug : pluginList.getTypes()) {
//     //     juceLogToFlutter(plug.name.toRawUTF8());
//     // }
//     // Clear the plugin list
//     pluginList.clear();

//     __android_log_print(ANDROID_LOG_INFO, "JUCE", "✅ initializeEngine check2");
//     // Scan all plugin formats (AUv3 and VST3/VST2)
//     for (int i = 0; i < pluginFormatManager.getNumFormats(); ++i) {
//         auto* format = pluginFormatManager.getFormat(i);
//         juce::FileSearchPath searchPath;

//         if (format->getName() == "AudioUnit") {
//             // AUv3 plugins are registered system-wide — ignore the file path
//             juceLogToFlutter("Scanning AUv3 (AudioUnitPluginFormat) from registry");
//             searchPath = juce::FileSearchPath(); // <- required for AUv3
//         } else {
//             // For formats like VST3, scan from your bundle
//             juceLogToFlutter(("Scanning format " + format->getName() + " from " + appBundleRoot.getFullPathName()).toRawUTF8());
//             searchPath = juce::FileSearchPath(appBundleRoot.getFullPathName());
//         }

//         juce::PluginDirectoryScanner scanner(pluginList, *format, searchPath, true, juce::File());
//         juce::String err;
//         while (scanner.scanNextFile(false, err)) {}
//     }

//     // Log discovered plugin names
//     for (const auto& type : pluginList.getTypes()) {
//         juceLogToFlutter(("Discovered plugin: " + type.name).toRawUTF8());
//     }

//     __android_log_print(ANDROID_LOG_INFO, "JUCE", "✅ initializeEngine check3");

//     // Set up the audio device but don't start playback yet:
//     // TODO: MIGHT NEED TO CALL THIS ONLY ONCE PUT IN THE engineInitialized BLOCK ABOVE
//     deviceManager.initialise(
//         /*numInputChannels*/  0,
//         /*numOutputChannels*/ 2,
//         /*xmlSettings*/       nullptr,
//         /*selectDefaultDeviceOnFailure*/ true
//     );

//     // query the real device rate & block size
//     if (auto* dev = deviceManager.getCurrentAudioDevice())
//     {
//         auto hostRate  = dev->getCurrentSampleRate();
//         auto blockSize = dev->getCurrentBufferSizeSamples();
//         graph.prepareToPlay(hostRate, blockSize);
//         juceLogToFlutter(("graph.prepareToPlay("
//                         + juce::String(hostRate) + ", "
//                         + juce::String(blockSize)
//                         + ")").toRawUTF8());
//     }
//     else
//     {
//         // fallback if no device yet
//         graph.prepareToPlay(44100.0, 512);
//     }

//     __android_log_print(ANDROID_LOG_INFO, "JUCE", "✅ initializeEngine check4");

//     audioPlayer.setProcessor(&graph);
//     deviceManager.addAudioCallback(&audioPlayer);

//     engineInitialized = true;
//     __android_log_print(ANDROID_LOG_INFO, "JUCE", "✅ initialiseEngine done");
// }

void JuceEngine::initialiseEngine()
{
    __android_log_print(ANDROID_LOG_INFO, "JUCE", "✅ initializeEngine started");
    juceLogToFlutter("Hello from JuceEngine::initialiseEngine()");

    if (engineInitialized)
    {
        juceLogToFlutter("⚠️ JuceEngine::initialiseEngine() already called — skipping register formats.");
        // return;
    }
    else
    {
        formatManager.registerBasicFormats();
        pluginFormatManager.addDefaultFormats();
    }

    engineInitialized = false;

#if JUCE_IOS
    // juceLogToFlutter("iOS-only code running");
    pluginFormatManager.addFormat(new juce::AudioUnitPluginFormat());
    // auto session = [AVAudioSession sharedInstance];
    // [session setCategory:AVAudioSessionCategoryPlayback error:nil];
    // [session setActive:YES error:nil];
    // #endif
    // Create the audio-output node
    outputNode = graph.addNode(
        std::make_unique<AudioProcessorGraph::AudioGraphIOProcessor>(
            AudioProcessorGraph::AudioGraphIOProcessor::audioOutputNode));
#endif
    // end of stuff in constructor

    // Get the app bundle root directory
    // auto appBundleRoot = juce::File::getSpecialLocation(juce::File::hostApplicationPath).getParentDirectory();
    // auto appBundleRoot = juce::File::getSpecialLocation(juce::File::userDocumentsDirectory);  // or userApplicationDataDirectory

    // // Use PluginDirectoryScanner as before, but with appBundleRoot as the search path
    // for (int i = 0; i < pluginFormatManager.getNumFormats(); ++i) {
    //     juce::PluginDirectoryScanner scanner(pluginList,
    //                                          *pluginFormatManager.getFormat(i),
    //                                          juce::FileSearchPath(appBundleRoot.getFullPathName()),
    //                                          true, juce::File());
    //     juce::String err;
    //     while (scanner.scanNextFile(false, err)) {}
    // }

    // for (auto plug : pluginList.getTypes()) {
    //     juceLogToFlutter(plug.name.toRawUTF8());
    // }
    // Clear the plugin list
    pluginList.clear();

    // Scan all plugin formats (AUv3 and VST3/VST2)
    // for (int i = 0; i < pluginFormatManager.getNumFormats(); ++i) {
    //     auto* format = pluginFormatManager.getFormat(i);
    //     juce::FileSearchPath searchPath;

    //     if (format->getName() == "AudioUnit") {
    //         // AUv3 plugins are registered system-wide — ignore the file path
    //         juceLogToFlutter("Scanning AUv3 (AudioUnitPluginFormat) from registry");
    //         searchPath = juce::FileSearchPath(); // <- required for AUv3
    //     } else {
    //         // For formats like VST3, scan from your bundle
    //         juceLogToFlutter(("Scanning format " + format->getName() + " from " + appBundleRoot.getFullPathName()).toRawUTF8());
    //         searchPath = juce::FileSearchPath(appBundleRoot.getFullPathName());
    //     }

    //     juce::PluginDirectoryScanner scanner(pluginList, *format, searchPath, true, juce::File());
    //     juce::String err;
    //     while (scanner.scanNextFile(false, err)) {}
    // }

    // // Log discovered plugin names
    // for (const auto& type : pluginList.getTypes()) {
    //     juceLogToFlutter(("Discovered plugin: " + type.name).toRawUTF8());
    // }

    __android_log_print(ANDROID_LOG_INFO, "JUCE", "✅ JuceBridge step1");

    // Set up the audio device but don't start playback yet:
    // TODO: MIGHT NEED TO CALL THIS ONLY ONCE PUT IN THE engineInitialized BLOCK ABOVE
    deviceManager.initialise(
        /*numInputChannels*/ 0,
        /*numOutputChannels*/ 2,
        /*xmlSettings*/ nullptr,
        /*selectDefaultDeviceOnFailure*/ true);

    __android_log_print(ANDROID_LOG_INFO, "JUCE", "✅ JuceBridge step4");

    // query the real device rate & block size
    if (auto *dev = deviceManager.getCurrentAudioDevice())
    {
        auto hostRate = dev->getCurrentSampleRate();
        auto blockSize = dev->getCurrentBufferSizeSamples();
        graph.prepareToPlay(hostRate, blockSize);
        juceLogToFlutter(("graph.prepareToPlay(" + juce::String(hostRate) + ", " + juce::String(blockSize) + ")").toRawUTF8());
    }
    else
    {
        // fallback if no device yet
        graph.prepareToPlay(44100.0, 512);
    }

    if (outputNode == nullptr)
    {
        outputNode = graph.addNode(
            std::make_unique<AudioProcessorGraph::AudioGraphIOProcessor>(
                AudioProcessorGraph::AudioGraphIOProcessor::audioOutputNode));
    }

    audioPlayer.setProcessor(&graph);
    deviceManager.addAudioCallback(&audioPlayer);

    engineInitialized = true;
    __android_log_print(ANDROID_LOG_INFO, "JUCE", "✅ initializeEngine done");
}

void JuceEngine::loadTrack(int idx, const File &file)
{
    juceLogToFlutter("Hello from JuceEngine::loadTrack");

    try
    {
        if (idx < trackNodes.size() && trackNodes[idx] != nullptr)
        {
            graph.removeNode(trackNodes[idx]->nodeID);
            trackNodes.set(idx, nullptr);
        }
        // juce::WavAudioFormat wavFormat;
        // auto stream = file.createInputStream();
        // if (!stream)
        // {
        //     juceLogToFlutter("❌ Wav: Failed to create input stream");
        //     juce::Thread::sleep(100);
        //     return;
        // }
        // std::unique_ptr<juce::AudioFormatReader> reader(
        //     wavFormat.createReaderFor(stream.release(), true));

        auto reader = std::unique_ptr<juce::AudioFormatReader>(
            formatManager.createReaderFor(file));
        juceLogToFlutter("✅ WavAudioFormat successfully read the file");
        if (!reader)
            return;
        auto lengthInSamples = reader->lengthInSamples;

        juce::Thread::sleep(100);
        auto source = std::make_unique<AudioFormatReaderSource>(reader.release(), true);
        // juceLogToFlutter(("Reader length: " + juce::String(reader->lengthInSamples)).toRawUTF8());
        juce::Thread::sleep(100);
        if (source == nullptr)
        {
            juceLogToFlutter("❌ source is null before passing to FilePlayerProcessor");
            juce::Thread::sleep(100);
            return;
        }
        auto player = std::make_unique<FilePlayerProcessor>(std::move(source), lengthInSamples, file);
        auto node = graph.addNode(std::move(player));

        if (idx >= trackNodes.size())
            trackNodes.insert(idx, node.get());
        else
            trackNodes.set(idx, node.get());

        // Initialize effect chain - store NodeIDs instead of pointers
        auto *chain = new Array<AudioProcessorGraph::NodeID>();
        // chain->add(node->nodeID);  // Store ID instead of pointer
        if (idx >= trackEffectChains.size())
            trackEffectChains.insert(idx, chain);
        else
            trackEffectChains.set(idx, chain);

        // Connect file → output
        // for (int ch = 0; ch < std::min<int64>(2, node->getProcessor()->getTotalNumOutputChannels()); ++ch)
        //     graph.addConnection({{node->nodeID, ch}, {outputNode->nodeID, ch}});
        // 🔊 Create gain node and wire player → gain → output
        // 🔊 Create gain node and wire player → gain → output
        auto gainProc = std::make_unique<SimpleGainProcessor>();
        auto *gainPtr = gainProc.get(); // Keep pointer before transfer
        auto gainNode = graph.addNode(std::move(gainProc));

        // Store gain processor for volume updates
        if (idx >= gainProcessors.size())
            gainProcessors.insert(idx, gainPtr);
        else
            gainProcessors.set(idx, gainPtr);

        // query the real device rate & block size
        if (auto *dev = deviceManager.getCurrentAudioDevice())
        {
            auto hostRate = dev->getCurrentSampleRate();
            auto blockSize = dev->getCurrentBufferSizeSamples();
            graph.prepareToPlay(hostRate, blockSize);
            juceLogToFlutter(("graph.prepareToPlay(" + juce::String(hostRate) + ", " + juce::String(blockSize) + ")").toRawUTF8());
        }
        else
        {
            // fallback if no device yet
            graph.prepareToPlay(44100.0, 512);
        }

        // Now safe to inspect number of output channels
        int numOutputChannels = node->getProcessor()->getTotalNumOutputChannels();

        // Wire: player → gain → output
        if (gainNode != nullptr)
        {
            for (int ch = 0; ch < std::min<int64>(2, numOutputChannels); ++ch)
            {
                graph.addConnection({{node->nodeID, ch}, {gainNode->nodeID, ch}});
                graph.addConnection({{gainNode->nodeID, ch}, {outputNode->nodeID, ch}});
            }
        }

        // Debug: List all connections
        for (const auto &c : graph.getConnections())
        {
            juceLogToFlutter(("Graph connection: " +
                              juce::String((int)c.source.nodeID.uid) + ":" + juce::String(c.source.channelIndex) +
                              " → " +
                              juce::String((int)c.destination.nodeID.uid) + ":" + juce::String(c.destination.channelIndex))
                                 .toRawUTF8());
        }

        for (int i = 0; i < trackNodes.size(); ++i)
            trackNodes[i]->setBypassed(true); // ✅ Freeze reader
    }
    catch (const std::exception &e)
    {
        juceLogToFlutter("❗ std::exception in loadTrack:");
        juceLogToFlutter(e.what());
    }
    catch (...)
    {
        juceLogToFlutter("❗ Unknown C++ exception in loadTrack");
    }
}

// In JuceEngine.cpp
void JuceEngine::removeTrack(int trackIndex)
{
    juceLogToFlutter("Hello from JuceEngine::removeTrack");

    if (trackIndex < 0 || trackIndex >= trackNodes.size())
        return;

    // 1. Remove gain node
    if (trackIndex < gainProcessors.size())
    {
        auto *gainProc = gainProcessors[trackIndex];
        if (gainProc != nullptr)
        {
            // Find and remove the gain node
            for (auto *node : graph.getNodes())
            {
                if (node != nullptr && node->getProcessor() == gainProc)
                {
                    graph.removeNode(node->nodeID);
                    juceLogToFlutter("✅ Gain node removed from graph");
                    break;
                }
            }
        }
        gainProcessors.remove(trackIndex);
    }

    // 2. Remove FX nodes using NodeIDs
    if (trackIndex < trackEffectChains.size())
    {
        auto *fxChain = trackEffectChains[trackIndex];
        if (fxChain != nullptr)
        {
            for (auto &nodeID : *fxChain)
            {
                if (graph.getNodeForId(nodeID) != nullptr)
                {
                    graph.removeNode(nodeID);
                }
            }
            // Clear but don't delete - OwnedArray will handle deletion
        }
        trackEffectChains.remove(trackIndex);
    }

    // 3. Remove file node
    if (trackIndex < trackNodes.size() && trackNodes[trackIndex] != nullptr)
    {
        graph.removeNode(trackNodes[trackIndex]->nodeID);
        trackNodes.set(trackIndex, nullptr);
    }

    // 4. Remove references
    trackNodes.remove(trackIndex);

    juceLogToFlutter("✅ Track removed and internal state reindexed.");
}

void JuceEngine::loadVideoAudio(const juce::File &file)
{
    juceLogToFlutter("▶️ loadVideoAudio()");
    // Remove old lane if present
    unloadVideoAudio();

    // // Create reader
    // auto reader = std::unique_ptr<juce::AudioFormatReader>(formatManager.createReaderFor(file));
    // if (!reader) { juceLogToFlutter("❌ loadVideoAudio: can't open audio"); return; }

    // auto lengthInSamples = reader->lengthInSamples;
    // auto source = std::make_unique<AudioFormatReaderSource>(reader.release(), true);
    // if (!source) { juceLogToFlutter("❌ loadVideoAudio: source null"); return; }

    // // File player
    // auto player = std::make_unique<FilePlayerProcessor>(std::move(source), lengthInSamples, file);
    // auto node   = graph.addNode(std::move(player));
    // videoAudioNode = node;

    // // Gain node
    // auto gainProc     = std::make_unique<SimpleGainProcessor>();
    // videoGainProc     = gainProc.get();
    // auto videoGainNode= graph.addNode(std::move(gainProc));

    // // Prepare if needed
    // if (auto* dev = deviceManager.getCurrentAudioDevice())
    //     graph.prepareToPlay(dev->getCurrentSampleRate(), dev->getCurrentBufferSizeSamples());
    // else
    //     graph.prepareToPlay(44100.0, 512);

    //     __android_log_print(ANDROID_LOG_INFO, "JUCE", "✅ loadvidaudio before");
    // // Wire: player → gain → output (stereo)
    // for (int ch = 0; ch < 2; ++ch)
    // {
    //     graph.addConnection({{videoAudioNode->nodeID, ch}, {videoGainNode->nodeID, ch}});
    //     graph.addConnection({{videoGainNode->nodeID,  ch}, {outputNode->nodeID,    ch}});
    // }

    // videoAudioNode->setBypassed(true);

    // hasVideoAudio = true;
    // juceLogToFlutter("✅ loadVideoAudio done");

    try
    {

        auto reader = std::unique_ptr<juce::AudioFormatReader>(
            formatManager.createReaderFor(file));
        juceLogToFlutter("✅ WavAudioFormat successfully read the file");
        if (!reader)
            return;
        auto lengthInSamples = reader->lengthInSamples;

        juce::Thread::sleep(100);
        auto source = std::make_unique<AudioFormatReaderSource>(reader.release(), true);
        // juceLogToFlutter(("Reader length: " + juce::String(reader->lengthInSamples)).toRawUTF8());
        juce::Thread::sleep(100);
        if (source == nullptr)
        {
            juceLogToFlutter("❌ source is null before passing to FilePlayerProcessor");
            juce::Thread::sleep(100);
            return;
        }
        auto player = std::make_unique<FilePlayerProcessor>(std::move(source), lengthInSamples, file);
        auto node = graph.addNode(std::move(player));
        videoAudioNode = node;

        // Connect file → output
        // for (int ch = 0; ch < std::min<int64>(2, node->getProcessor()->getTotalNumOutputChannels()); ++ch)
        //     graph.addConnection({{node->nodeID, ch}, {outputNode->nodeID, ch}});
        // 🔊 Create gain node and wire player → gain → output
        // 🔊 Create gain node and wire player → gain → output
        auto gainProc = std::make_unique<SimpleGainProcessor>();
        videoGainProc = gainProc.get(); // Keep pointer before transfer
        auto gainNode = graph.addNode(std::move(gainProc));

        // query the real device rate & block size
        if (auto *dev = deviceManager.getCurrentAudioDevice())
        {
            auto hostRate = dev->getCurrentSampleRate();
            auto blockSize = dev->getCurrentBufferSizeSamples();
            graph.prepareToPlay(hostRate, blockSize);
            juceLogToFlutter(("graph.prepareToPlay(" + juce::String(hostRate) + ", " + juce::String(blockSize) + ")").toRawUTF8());
        }
        else
        {
            // fallback if no device yet
            graph.prepareToPlay(44100.0, 512);
        }

        // Now safe to inspect number of output channels
        int numOutputChannels = node->getProcessor()->getTotalNumOutputChannels();

        // Wire: player → gain → output
        if (gainNode != nullptr)
        {
            for (int ch = 0; ch < std::min<int64>(2, numOutputChannels); ++ch)
            {
                graph.addConnection({{videoAudioNode->nodeID, ch}, {gainNode->nodeID, ch}});
                graph.addConnection({{gainNode->nodeID, ch}, {outputNode->nodeID, ch}});
            }
        }

        videoAudioNode->setBypassed(true);
        hasVideoAudio = true;
        juceLogToFlutter("✅ loadVideoAudio done");
    }
    catch (const std::exception &e)
    {
        juceLogToFlutter("❗ std::exception in loadTrack:");
        juceLogToFlutter(e.what());
    }
    catch (...)
    {
        juceLogToFlutter("❗ Unknown C++ exception in loadTrack");
    }
}

void JuceEngine::unloadVideoAudio()
{
    if (!hasVideoAudio)
        return;

    juceLogToFlutter("🧹 unloadVideoAudio()");
    // Remove any connections involving video lane
    juce::Array<juce::AudioProcessorGraph::Connection> toRemove;
    for (auto &c : graph.getConnections())
    {
        if (videoAudioNode && (c.source.nodeID == videoAudioNode->nodeID || c.destination.nodeID == videoAudioNode->nodeID))
            toRemove.add(c);
    }
    for (auto &c : toRemove)
        graph.removeConnection(c);

    // Remove gain node (find by processor pointer)
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

    // Remove player node
    if (videoAudioNode)
        graph.removeNode(videoAudioNode->nodeID);

    videoAudioNode = nullptr;
    videoGainProc = nullptr;
    hasVideoAudio = false;
}

void JuceEngine::removePluginEffect(int trackIdx, int effectIndex)
{
    juceLogToFlutter("Hello from JuceEngine::removePluginEffect");
    if (trackIdx < 0 || trackIdx >= trackEffectChains.size())
        return;
    auto *chain = trackEffectChains[trackIdx];
    if (effectIndex < 0 || effectIndex >= chain->size())
        return;

    auto nodeID = chain->getReference(effectIndex);
    graph.removeNode(nodeID);
    // Fix: Use removeRange instead of remove for Array
    chain->removeRange(effectIndex, 1);

    rewireTrackChain(trackIdx);
}

void JuceEngine::reorderPluginEffects(int trackIdx, int fromIndex, int toIndex)
{
    juceLogToFlutter("Hello from JuceEngine::reorderPluginEffects");
    if (trackIdx < 0 || trackIdx >= trackEffectChains.size())
        return;
    auto *chain = trackEffectChains[trackIdx];
    if (fromIndex < 0 || fromIndex >= chain->size() || toIndex < 0 || toIndex > chain->size())
        return;

    auto nodeID = chain->getReference(fromIndex);

    chain->removeRange(fromIndex, 1);
    chain->insert(toIndex, nodeID);

    rewireTrackChain(trackIdx);
}

void JuceEngine::rewireTrackChain(int trackIdx)
{
    juceLogToFlutter("Hello from JuceEngine::rewireTrackChain");

    juceLogToFlutter(("=== rewireTrackChain debugging for track " + juce::String(trackIdx) + " ===").toRawUTF8());

    // --- Debug: print File node ---
    if (trackIdx < 0 || trackIdx >= trackNodes.size())
    {
        juceLogToFlutter("  invalid trackIdx, no file node");
    }
    else
    {
        auto fileNode = trackNodes[trackIdx];
        if (fileNode && fileNode->getProcessor() != nullptr)
            juceLogToFlutter(("  FileNode  - " + fileNode->getProcessor()->getName()).toRawUTF8());
        else
            juceLogToFlutter("  FileNode  - nullptr");
    }

    // --- Debug: print each effect in the chain order ---
    if (trackIdx < 0 || trackIdx >= trackEffectChains.size())
    {
        juceLogToFlutter("  invalid trackIdx, no effect chain");
    }
    else
    {
        auto *chain = trackEffectChains[trackIdx];
        for (int i = 0; i < chain->size(); ++i)
        {
            auto nodeID = chain->getReference(i);
            if (auto *fxNode = graph.getNodeForId(nodeID))
            {
                if (auto *proc = fxNode->getProcessor())
                    juceLogToFlutter(
                        ("  Effect[" + juce::String(i) + "] - " + proc->getName()).toRawUTF8());
                else
                    juceLogToFlutter(("  Effect[" + juce::String(i) + "] - nullptr").toRawUTF8());
            }
            else
            {
                juceLogToFlutter(
                    ("  Effect[" + juce::String(i) + "] - no node for ID " + juce::String(nodeID.uid)).toRawUTF8());
            }
        }
    }

    // --- Debug: print Gain node if any ---
    if (trackIdx < gainProcessors.size() && gainProcessors[trackIdx] != nullptr)
    {
        auto *gainProc = gainProcessors[trackIdx];
        juceLogToFlutter(("  GainNode  - " + gainProc->getName()).toRawUTF8());
    }
    else
    {
        juceLogToFlutter("  GainNode  - none");
    }

    // --- Debug: print Output node ---
    if (outputNode && outputNode->getProcessor() != nullptr)
        juceLogToFlutter(("  OutputNode - " + outputNode->getProcessor()->getName()).toRawUTF8());
    else
        juceLogToFlutter("  OutputNode - nullptr");

    juce::Thread::sleep(100);

    if (trackIdx < 0 || trackIdx >= trackEffectChains.size())
        return;

    auto *chain = trackEffectChains[trackIdx];
    if (chain == nullptr)
    {
        juceLogToFlutter(("⚠️ No effect chain allocated for track " + juce::String(trackIdx)).toRawUTF8());
        return;
    }
    auto fileNode = trackNodes[trackIdx];
    auto outID = outputNode->nodeID;

    auto isOneOfChain = [&](juce::AudioProcessorGraph::NodeID nodeID)
    {
        for (auto &id : *chain)
            if (id == nodeID)
                return true;
        return false;
    };

    // Remove old connections
    // Array<AudioProcessorGraph::Connection> toRemove;
    // for (auto& c : graph.getConnections()) {
    //     if ((c.source.nodeID == fileNode->nodeID && c.destination.nodeID == outID) ||
    //         (isOneOfChain(c.source.nodeID) && c.destination.nodeID == outID)) {
    //         toRemove.add(c);
    //     }
    // }
    // for (auto& c : toRemove)
    //     graph.removeConnection(c);
    Array<AudioProcessorGraph::Connection> toRemove;
    for (auto &c : graph.getConnections())
    {
        if (c.source.nodeID == fileNode->nodeID ||
            isOneOfChain(c.source.nodeID) ||
            isOneOfChain(c.destination.nodeID))
        {
            toRemove.add(c);
        }
    }
    for (auto &c : toRemove)
        graph.removeConnection(c);

    // Reconnect
    AudioProcessorGraph::Node::Ptr prev = fileNode;
    for (auto &fxID : *chain)
    {
        auto fxNode = graph.getNodeForId(fxID);
        if (fxNode == nullptr)
            continue;
        for (int ch = 0; ch < 2; ++ch)
            graph.addConnection({{prev->nodeID, ch}, {fxNode->nodeID, ch}});
        prev = fxNode;
    }

    // Final: connect to output or gain
    if (trackIdx < gainProcessors.size() && gainProcessors[trackIdx] != nullptr)
    {
        auto *gain = gainProcessors[trackIdx];
        auto gainNode = [&]() -> AudioProcessorGraph::Node::Ptr
        {
            for (auto *node : graph.getNodes())
                if (node->getProcessor() == gain)
                    return node;
            return nullptr;
        }();
        if (gainNode != nullptr)
        {
            for (int ch = 0; ch < 2; ++ch)
            {
                graph.addConnection({{prev->nodeID, ch}, {gainNode->nodeID, ch}});
                graph.addConnection({{gainNode->nodeID, ch}, {outID, ch}});
            }
            return;
        }
    }
    for (int ch = 0; ch < 2; ++ch)
        graph.addConnection({{prev->nodeID, ch}, {outID, ch}});
}

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

juce::StringArray JuceEngine::getTrackEffects(int trackIndex)
{
    // juceLogToFlutter("Hello from  JuceEngine::getTrackEffects");
    juce::StringArray names;

    // guard
    if (trackIndex < 0 || trackIndex >= trackEffectChains.size())
        return names;

    auto *chain = trackEffectChains[trackIndex];
    for (auto &nodeID : *chain)
    {
        if (auto node = graph.getNodeForId(nodeID))
        {
            // if (auto* plugin = dynamic_cast<juce::AudioPluginInstance*>(node->getProcessor()))
            //     names.add(plugin->getName());
            if (auto *processor = node->getProcessor())
                names.add(processor->getName());
        }
    }

    return names;
}

void JuceEngine::insertPluginEffect(int trackIdx, const juce::String &pluginPath, std::function<void(bool)> callback)
{
    juceLogToFlutter("Hello from JuceEngine::insertPluginEffect");
    // 1. Early exit if track index is invalid
    if (trackIdx >= trackEffectChains.size())
    {
        if (callback)
            callback(false);
        return;
    }

    if (pluginPath.startsWith("Mixroom "))
    {
        std::unique_ptr<juce::AudioProcessor> plugin;
        if (pluginPath == "Mixroom Reverb")
        {
            plugin = std::make_unique<ReverbAudioProcessor>();
        }
        else if (pluginPath == "Mixroom EQ")
        {
            plugin = std::make_unique<EQAudioProcessor>();
        }
        else if (pluginPath == "Mixroom Delay")
        {
            plugin = std::make_unique<DelayAudioProcessor>();
        }
        else if (pluginPath == "Mixroom Distortion")
        {
            plugin = std::make_unique<DistortionAudioProcessor>();
        }
        else if (pluginPath == "Mixroom De-Esser")
        {
            plugin = std::make_unique<DeesserAudioProcessor>();
        }
        else
        {
            juceLogToFlutter("didn't find matching Mixroom plugin");
            return;
        }

        plugin->prepareToPlay(graph.getSampleRate(), graph.getBlockSize());
        auto node = graph.addNode(std::move(plugin));
        trackEffectChains[trackIdx]->add(node->nodeID);
        rewireTrackChain(trackIdx);
        return;
    }

    // 2. Plugin loading logic
    juce::PluginDescription desc;
    desc.fileOrIdentifier = pluginPath;

    auto *format = pluginFormatManager.getFormat(0);
    if (format == nullptr)
    {
        if (callback)
            callback(false);
        return;
    }

    // 3. Async plugin loading
    format->createPluginInstanceAsync(
        desc,
        44100.0,
        512,
        [this, trackIdx, callback](std::unique_ptr<juce::AudioPluginInstance> inst, const juce::String &error)
        {
            if (!inst)
            {
                if (callback)
                    callback(false);
                return;
            }

            // 4. Schedule graph modifications on JUCE thread
            juce::MessageManager::callAsync([this, trackIdx, inst = std::move(inst), callback]() mutable
                                            {
                                                inst->prepareToPlay(graph.getSampleRate(), graph.getBlockSize());
                                                auto *chain = trackEffectChains[trackIdx];
                                                auto pluginNode = graph.addNode(std::move(inst));
                                                chain->add(pluginNode->nodeID);
                                                rewireTrackChain(trackIdx);

                                                // if (callback) callback(true); TODO probably call this function eventually
                                            });
        });
}

// void JuceEngine::setEffectParameter (int trackIndex,
//                                      int effectIndex,
//                                      const juce::String& paramID,
//                                      const juce::var& newValue)
// {
//     juceLogToFlutter("Hello from JuceEngine::setEffectParameter");
//     // 1) bounds-check the track
//     if (trackIndex < 0 || trackIndex >= trackEffectChains.size())
//         return;

//     auto* chain = trackEffectChains[trackIndex];
//     if (chain == nullptr)
//         return;

//     // 2) bounds-check the effect in that chain
//     if (effectIndex < 0 || effectIndex >= chain->size())
//         return;

//     // 3) pull out that NodeID and find its node
//     auto nodeID = chain->getReference(effectIndex);
//     auto* node  = graph.getNodeForId(nodeID);
//     if (node == nullptr)
//         return;

//     // 4) make sure it really is a plugin instance
//     if (auto* plugin = dynamic_cast<juce::AudioPluginInstance*>(node->getProcessor()))
//     {
//         // 5) scan its params for a matching paramID
//         for (auto* p : plugin->getParameters())
//         {
//             if (auto* prm = dynamic_cast<juce::AudioProcessorParameterWithID*>(p))
//             {
//                 if (prm->paramID == paramID)
//                 {
//                     prm->setValueNotifyingHost(newValue);

//                     if (auto* f = dynamic_cast<juce::AudioParameterFloat*> (p))
//                     {
//                         f->setValueNotifyingHost ((float) newValue);
//                     }
//                     else if (auto* b = dynamic_cast<juce::AudioParameterBool*> (p))
//                     {
//                         // newValue should be a bool or 0/1
//                         bool   boolVal = newValue;
//                         b->setValueNotifyingHost (boolVal ? 1.0f : 0.0f);
//                     }
//                     else if (auto* c = dynamic_cast<juce::AudioParameterChoice*> (p))
//                     {
//                         // newValue should be the index of the choice
//                         int choiceIndex = (int) newValue;
//                         c->setValueNotifyingHost ((float) choiceIndex);
//                     }
//                     else
//                     {
//                         // fallback: try to treat it as float
//                         prm->setValueNotifyingHost ((float) newValue);
//                     }

//                     return;
//                 }
//             }
//         }
//     }
// }

void JuceEngine::setEffectParameter(int trackIndex,
                                    int effectIndex,
                                    const juce::String &paramName,
                                    const juce::var &newValue)
{
    juceLogToFlutter(("JuceEngine::setEffectParameter(track=" + juce::String(trackIndex) + ", effect=" + juce::String(effectIndex) + ", name=\"" + paramName + "\")").toRawUTF8());

    // 1) Validate track & chain
    if (trackIndex < 0 || trackIndex >= trackEffectChains.size())
        return;
    auto *chain = trackEffectChains[trackIndex];
    if (chain == nullptr)
        return;

    // 2) Validate effect index
    if (effectIndex < 0 || effectIndex >= chain->size())
        return;

    // 3) Find the plugin node
    auto nodeID = chain->getReference(effectIndex);
    auto *node = graph.getNodeForId(nodeID);
    if (node == nullptr)
        return;
    // auto* plugin = dynamic_cast<juce::AudioPluginInstance*>(node->getProcessor());
    // if (plugin == nullptr)
    //     return;
    auto *processor = node->getProcessor();
    if (processor == nullptr)
        return;

    // 4) Scan parameters for matching name
    // for (auto* p : plugin->getParameters())
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
            // assume string choice: hunt for matching label
            juce::String str = newValue.toString();
            int steps = p->getNumSteps();
            for (int i = 0; i < steps; ++i)
            {
                float n = (steps > 1) ? (float)i / (float)(steps - 1) : 0.0f;
                if (p->getText(n, 128) == str)
                {
                    normalized = n;
                    break;
                }
            }
        }

        // finally, set it on the one interface all JUCE parameters expose
        if (auto *withID = dynamic_cast<juce::AudioProcessorParameterWithID *>(p))
        {
            if (auto *floatParam = dynamic_cast<juce::AudioParameterFloat *>(p))
            {
                const auto &range = floatParam->range;

                float clamped = juce::jlimit(range.start, range.end, normalized);
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
            // as a last resort, try the generic host notification on the base class
            p->setValueNotifyingHost(normalized);
            juceLogToFlutter(("  Fallback set \"" + paramName + "\" → " + juce::String(normalized)).toRawUTF8());
        }
        return;
    }
}

void JuceEngine::setTrackVolume(int trackIdx, float volume)
{
    // juceLogToFlutter("Hello from JuceEngine::setTrackVolume");
    if (trackIdx < gainProcessors.size() && gainProcessors[trackIdx] != nullptr)
    {
        // the gain seems to be recognizing volume as 0.0 to 1.0 (0% to 100%) rather than numbers above 1.0
        // gainProcessors[trackIdx]->gain->setValueNotifyingHost(volume);
        gainProcessors[trackIdx]->gain->setValueNotifyingHost(volume / 3.0); // 3.0 is max num of SimpleGainProcessor
    }
}

void JuceEngine::setVideoAudioGain(float gain)
{
    // SimpleGainProcessor is normalized 0..1 for 0..3x in your code
    if (videoGainProc)
        videoGainProc->gain->setValueNotifyingHost(gain / 3.0);
}

std::vector<String> JuceEngine::getExposedParametersForPlugin(const String &pluginId)
{
    juceLogToFlutter("Hello from JuceEngine::getExposedParametersForPlugin");
    if (pluginId.containsIgnoreCase("skynet"))
        return {"roomSize", "mix", "width"};
    if (pluginId.containsIgnoreCase("delaylux"))
        return {"feedback", "wet", "time"};
    return {};
}

Array<NamedValueSet> JuceEngine::getPluginParameterInfo(int trackIndex, int effectIndex)
{
    juceLogToFlutter("Hello from JuceEngine::getPluginParameterInfo");
    Array<NamedValueSet> results;
    if (trackIndex >= trackEffectChains.size())
        return results;
    auto *chain = trackEffectChains[trackIndex];
    if (effectIndex < 0 || effectIndex >= chain->size())
        return results;

    auto nodeID = chain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (node == nullptr)
        return results;

    // if (auto* plugin = dynamic_cast<AudioPluginInstance*>(node->getProcessor()))
    // {
    if (auto *processor = node->getProcessor())
    {
        // TODO: USE THE ALLOWED LIST AND FIX IT TO INCLUDE THE PARAMETERS YOU WANT HARDCODED FOR EVERY PLUGIN EVER
        // auto allowed = getExposedParametersForPlugin(plugin->getName());
        // IMPORTANT ABOVE

        // for (auto* p : plugin->getParameters())
        for (auto *p : processor->getParameters())
        {
            juceLogToFlutter((p->getName(100)).toRawUTF8());
            NamedValueSet e;
            // I don't think we need ID
            // 1) ID: use paramID if it's a WithID, else fallback to index
            // if (auto* withID = dynamic_cast<juce::AudioProcessorParameterWithID*>(p))
            //     e.set("id", withID->paramID);
            // else
            //     e.set("id", juce::String("param_") + juce::String(i));

            // 2) Name
            e.set("name", p->getName(128));

            // 3) Handle the known JUCE subclasses first:
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
            // 4) Fallback for all others via the base-class API
            else
            {
                const bool isChoice = p->isDiscrete(); // && p->getNumSteps() > 1;
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
                    // no real range info? fall back to [0,1]

                    // TODO: hardcode min-max for every plugin you intend to support
                    e.set("min", 0.0f);
                    e.set("max", 1.0f);
                    e.set("default", defNorm);
                    e.set("value", curNorm);
                }
            }

            results.add(e);
        }
    }

    // juceLogToFlutter("Printing results of getPluginParameterInfo()");
    // for (int i = 0; i < results.size(); ++i)
    // {
    //     const auto& e = results.getReference(i);
    //     juceLogToFlutter(("  — Param #" + juce::String(i)).toRawUTF8());
    //     if (e.contains("id"))      juceLogToFlutter(("       id:      " + e["id"].toString()).toRawUTF8());
    //     if (e.contains("name"))    juceLogToFlutter(("       name:    " + e["name"].toString()).toRawUTF8());
    //     if (e.contains("type"))    juceLogToFlutter(("       type:    " + e["type"].toString()).toRawUTF8());
    //     if (e.contains("min"))     juceLogToFlutter(("       min:     " + juce::String((double)e["min"])).toRawUTF8());
    //     if (e.contains("max"))     juceLogToFlutter(("       max:     " + juce::String((double)e["max"])).toRawUTF8());
    //     if (e.contains("default")) juceLogToFlutter(("       default: " + e["default"].toString()).toRawUTF8());
    //     if (e.contains("value"))   juceLogToFlutter(("       value:   " + e["value"].toString()).toRawUTF8());

    //     // now any choice_* entries:
    //     for (int choiceIdx = 0; ; ++choiceIdx)
    //     {
    //         auto key = "choice_" + juce::String(choiceIdx);
    //         if (! e.contains(key)) break;
    //         juceLogToFlutter(("       " + key + ": " + e[key].toString()).toRawUTF8());
    //     }
    // }
    // juceLogToFlutter("done printing results");

    return results;
}

// EXPORT OF ENTIRE MIX (NOT PER-TRACK)
String JuceEngine::exportMix(const File &outFile)
{
    juceLogToFlutter("Hello from JuceEngine::exportMix");

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
        int toWrite = (int)std::min<int64>(bs, total - written);
        w->writeFromAudioSampleBuffer(buf, 0, toWrite);
        written += toWrite;
    }

    return outFile.getFullPathName();
}

// PER-TRACK EXPORT
juce::String JuceEngine::exportTrack(int trackIndex, const juce::File &outFile)
{
    juceLogToFlutter("▶️ exportTrack (overwrite + FX + gain) BEGIN");

    // 0) Validate trackIndex & get sourceFile
    if (trackIndex < 0 || trackIndex >= trackNodes.size())
    {
        juceLogToFlutter("❌ exportTrack: invalid trackIndex");
        return {};
    }

    auto sourceNode = trackNodes[trackIndex];
    if (sourceNode == nullptr)
    {
        juceLogToFlutter("❌ exportTrack: sourceNode is null");
        return {};
    }

    // Must be a FilePlayerProcessor
    auto *fpProc = dynamic_cast<FilePlayerProcessor *>(sourceNode->getProcessor());
    if (fpProc == nullptr)
    {
        juceLogToFlutter("❌ exportTrack: sourceNode is not a FilePlayerProcessor");
        return {};
    }

    juce::File sourceFile = fpProc->getSourceFile();
    if (!sourceFile.existsAsFile())
    {
        juceLogToFlutter(("❌ exportTrack: source file does not exist: " + sourceFile.getFullPathName()).toRawUTF8());
        return {};
    }

    // Log exactly which sourceFile we are about to read
    // juceLogToFlutter(("ℹ️ exportTrack: about to use sourceFile = "
    //                   + sourceFile.getFullPathName() + "").toRawUTF8());

    // 1) If outFile already exists, delete it now so we can overwrite cleanly
    if (outFile.existsAsFile())
    {
        // juceLogToFlutter(("ℹ️ exportTrack: deleting existing outFile = "
        //                   + outFile.getFullPathName() + "").toRawUTF8());
        outFile.deleteFile();
    }

    // 2) Open an AudioFormatReader directly on sourceFile
    // formatManager.registerBasicFormats(); already called this in initialiseEngine
    std::unique_ptr<juce::AudioFormatReader> reader(
        formatManager.createReaderFor(sourceFile));

    if (reader == nullptr)
    {
        juceLogToFlutter(("❌ exportTrack: cannot open sourceFile for reading: " + sourceFile.getFullPathName() + "").toRawUTF8());
        return {};
    }

    int numChannels = (int)reader->numChannels;   // e.g. 2 if stereo
    double sampleRate = reader->sampleRate;       // e.g. 48000 if file is 48 kHz
    int64 totalSamples = reader->lengthInSamples; // total length in samples

    // juceLogToFlutter(("ℹ️ exportTrack: sourceFile → "
    //                   + String(numChannels) + "ch, "
    //                   + String(sampleRate) + "Hz, "
    //                   + String(totalSamples) + " samples").toRawUTF8());

    if (totalSamples <= 0)
    {
        juceLogToFlutter("❌ exportTrack: sourceFile has zero length");
        return {};
    }

    // 3) Build a chain of AudioProcessor* for plugin‐FX only
    juce::OwnedArray<juce::AudioProcessor> chainProcessors;

    if (auto *chain = trackEffectChains[trackIndex])
    {
        for (auto &nodeID : *chain)
        {
            if (auto origNode = graph.getNodeForId(nodeID))
            {
                if (auto *plug = dynamic_cast<juce::AudioPluginInstance *>(origNode->getProcessor()))
                {
                    juceLogToFlutter("ℹ️ exportTrack: cloning plugin FX");
                    if (origNode->isBypassed())
                    {
                        juceLogToFlutter("⏭️ Skipping bypassed FX during export");
                        continue;
                    }

                    juce::String error;
                    auto desc = plug->getPluginDescription();
                    std::unique_ptr<juce::AudioPluginInstance> inst(
                        pluginFormatManager.createPluginInstance(desc, sampleRate, 512, error));

                    if (inst == nullptr)
                    {
                        juceLogToFlutter(("❌ exportTrack: plugin clone failed: " + error).toRawUTF8());
                        continue;
                    }

                    // Copy plugin state over
                    {
                        juce::MemoryBlock mb;
                        plug->getStateInformation(mb);
                        inst->setStateInformation(mb.getData(), (int)mb.getSize());
                    }

                    inst->prepareToPlay(sampleRate, 512);

                    // copy all the parameter values (maybe unnecessary?)
                    int n = plug->getParameters().size();
                    for (int pi = 0; pi < n; ++pi)
                    {
                        auto *liveParam = plug->getParameters()[pi];
                        auto *cloneParam = inst->getParameters()[pi];

                        // copy normalized value (0..1) exactly
                        float val = liveParam->getValue();
                        cloneParam->setValueNotifyingHost(val);
                    }

                    chainProcessors.add(inst.release());
                    juceLogToFlutter("ℹ️ exportTrack: plugin FX cloned");
                }
                else
                {
                    // juceLogToFlutter("ℹ️ exportTrack: chain node is not a plugin, skipping");

                    juceLogToFlutter("ℹ️ exportTrack: cloning native Mixroom FX");
                    if (origNode->isBypassed())
                    {
                        juceLogToFlutter("⏭️ Skipping bypassed FX during export");
                        continue;
                    }

                    auto *processor = origNode->getProcessor();
                    std::unique_ptr<juce::AudioProcessor> cloned;

                    juce::String name = processor->getName();
                    if (name == "Mixroom Reverb")
                        cloned = std::make_unique<ReverbAudioProcessor>();
                    else if (name == "Mixroom EQ")
                        cloned = std::make_unique<EQAudioProcessor>();
                    else if (name == "Mixroom Delay")
                        cloned = std::make_unique<DelayAudioProcessor>();
                    else if (name == "Mixroom Distortion")
                        cloned = std::make_unique<DistortionAudioProcessor>();
                    else if (name == "Mixroom De-Esser")
                        cloned = std::make_unique<DeesserAudioProcessor>();
                    else
                    {
                        juceLogToFlutter("❌ exportTrack: unsupported native FX");
                        continue;
                    }

                    // Copy parameter values
                    auto &liveParams = processor->getParameters();
                    auto &copyParams = cloned->getParameters();
                    for (int pi = 0; pi < std::min(liveParams.size(), copyParams.size()); ++pi)
                        copyParams[pi]->setValueNotifyingHost(liveParams[pi]->getValue());

                    cloned->prepareToPlay(sampleRate, 512);
                    chainProcessors.add(cloned.release());

                    juceLogToFlutter("ℹ️ exportTrack: native Mixroom FX cloned");
                }
            }
        }
    }
    else
    {
        juceLogToFlutter("ℹ️ exportTrack: no plugin FX to apply");
    }

    // 4) Create a WAV writer that writes to exactly 'outFile'
    WavAudioFormat wavFormat;

    // 4a) Obtain a unique_ptr<FileOutputStream> from outFile
    auto fs = outFile.createOutputStream();
    if (!fs || fs->failedToOpen())
    {
        juceLogToFlutter(("❌ exportTrack: cannot open " + outFile.getFullPathName() + " for writing").toRawUTF8());
        return {};
    }

    const int bitsPerSample = 16;
    std::unique_ptr<juce::AudioFormatWriter> writer(
        wavFormat.createWriterFor(
            fs.get(), // <– raw pointer to FileOutputStream
            sampleRate,
            numChannels,
            bitsPerSample,
            juce::StringPairArray(), // no extra metadata
            0                        // unused by WAV
            ));

    if (!writer)
    {
        juceLogToFlutter(("❌ exportTrack: cannot create WAV writer at " + outFile.getFullPathName() + "").toRawUTF8());
        return {};
    }

    // Give ownership of the stream to the writer
    fs.release();
    // juceLogToFlutter(("ℹ️ exportTrack: WAV writer created at "
    //                   + outFile.getFullPathName() + "").toRawUTF8());

    // 5) Process block‐by‐block: read from reader → FX → gain → write to WAV
    const int blockSize = 512;
    juce::AudioBuffer<float> buffer(numChannels, blockSize);
    juce::MidiBuffer midiBuffer;
    int64 samplesWritten = 0;

    while (samplesWritten < totalSamples)
    {
        int64 samplesRemaining = totalSamples - samplesWritten;
        int howMany = (int)std::min<int64>((int64)blockSize, samplesRemaining);

        // 5a) Read raw samples into 'buffer'
        buffer.clear();
        reader->read(
            &buffer,          // destination buffer
            0,                // dest start sample
            howMany,          // how many samples to read
            samplesWritten,   // read from this sample in sourceFile
            true,             // fill channel 0 (left)
            (numChannels > 1) // fill channel 1 (right) if stereo
        );

        // 5b) Apply each FX plugin in order
        for (auto *proc : chainProcessors)
            proc->processBlock(buffer, midiBuffer);

        // 5c) Apply the "live" per‐track gain multiplier (0.0 → 3.0)
        float userGain = 1.0f;
        if (trackIndex < gainProcessors.size() && gainProcessors[trackIndex] != nullptr)
            userGain = gainProcessors[trackIndex]->gain->get();
        float perceptualGain = std::min<float>(userGain * userGain, 9.0f); // std::min<int64>(userGain * userGain, 9.0f);
        buffer.applyGain(perceptualGain);

        // 5d) Write that block into WAV
        writer->writeFromAudioSampleBuffer(buffer, 0, howMany);
        samplesWritten += howMany;
    }

    // 6) Cleanup
    writer.reset();          // ensures file is closed/flushed
    chainProcessors.clear(); // delete all cloned FX

    // 7) Finally, report the modification time of outFile
    // auto newModTime = outFile.getLastModificationTime().toISO8601(true);
    // juceLogToFlutter(("ℹ️ exportTrack: new outFile modification time = "
    //                   + newModTime).toRawUTF8());

    // juceLogToFlutter(("✅ exportTrack done; final output = "
    //                   + outFile.getFullPathName() + "").toRawUTF8());

    return outFile.getFullPathName();
}

void JuceEngine::play()
{
    // juceLogToFlutter("Hello from JuceEngine::play");
    // Start sending audio to the device
    // deviceManager.addAudioCallback(&audioPlayer);

    for (int i = 0; i < trackNodes.size(); ++i)
        trackNodes[i]->setBypassed(false); // ✅ Resume
    // audioPlayer.setProcessor(&graph);
    // deviceManager.addAudioCallback(&audioPlayer);
    if (videoAudioNode)
        videoAudioNode->setBypassed(false);
}

void JuceEngine::pause()
{
    // juceLogToFlutter("Hello from JuceEngine::pause");
    // Stop sending audio
    // deviceManager.removeAudioCallback(&audioPlayer);
    for (int i = 0; i < trackNodes.size(); ++i)
        trackNodes[i]->setBypassed(true); // ✅ Freeze reader

    // deviceManager.removeAudioCallback(&audioPlayer);
    // audioPlayer.setProcessor(nullptr);
    if (videoAudioNode)
        videoAudioNode->setBypassed(true);
}

void JuceEngine::seek(int trackIndex, double positionSeconds)
{
    // juceLogToFlutter("Hello from JuceEngine::seek");
    if (trackIndex < 0 || trackIndex >= trackNodes.size())
        return;

    auto node = trackNodes[trackIndex];
    if (node != nullptr)
    {
        if (auto *fp = dynamic_cast<FilePlayerProcessor *>(node->getProcessor()))
        {
            fp->setPosition(positionSeconds);
        }
    }
}

void JuceEngine::seekVideoAudio(double seconds)
{
    if (videoAudioNode)
        if (auto *fp = dynamic_cast<FilePlayerProcessor *>(videoAudioNode->getProcessor()))
            fp->setPosition(seconds);
}

void JuceEngine::bypassPlugin(int trackIndex, int effectIndex, bool shouldBypass)
{
    juceLogToFlutter("Hello from JuceEngine::bypassPlugin");
    if (trackIndex < 0 || trackIndex >= trackEffectChains.size())
        return;

    auto *chain = trackEffectChains[trackIndex];
    if (effectIndex < 0 || effectIndex >= chain->size())
        return;

    auto nodeID = chain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (node != nullptr)
        node->setBypassed(shouldBypass);
}

bool JuceEngine::getPluginBypassState(int trackIndex, int effectIndex)
{
    juceLogToFlutter("Hello from JuceEngine::getPluginBypassState");
    if (trackIndex < 0 || trackIndex >= trackEffectChains.size())
        return false;

    auto *chain = trackEffectChains[trackIndex];
    if (effectIndex < 0 || effectIndex >= chain->size())
        return false;

    auto nodeID = chain->getReference(effectIndex);
    auto node = graph.getNodeForId(nodeID);
    if (node != nullptr)
        return node->isBypassed();
    return false;
}

void JuceEngine::bypassTrack(int trackIndex, bool shouldBypass)
{
    // juceLogToFlutter("Hello from JuceEngine::bypassTrack");
    if (trackIndex < 0 || trackIndex >= trackNodes.size())
        return;

    // JUCE Node::setBypassed(true) skips processing (freezes reader)
    trackNodes[trackIndex]->setBypassed(shouldBypass);
}

juce::Array<juce::PluginDescription> JuceEngine::getKnownPlugins() const
{
    // 1) log entry
    juceLogToFlutter("JuceEngine::getKnownPlugins()");

    // 2) grab the list by value
    auto types = pluginList.getTypes();

    // 3) debug-print how many and what they are
    juceLogToFlutter((" found " + juce::String(types.size()) + " plugins").toRawUTF8());
    for (auto &pd : types)
        juceLogToFlutter(("     " + pd.name).toRawUTF8());

    // 4) return the owned copy
    return types;
}

void JuceEngine::shutdownEngine()
{
    juceLogToFlutter("JuceEngine::shutdownEngine called");

    // add a safety check so it doesn't crash when nothing was initialized
    if (!engineInitialized)
    {
        juceLogToFlutter("⚠️ JuceEngine::shutdownEngine skipped — engine not initialized yet.");
        return;
    }

    audioPlayer.setProcessor(nullptr); // Disconnect from graph
    deviceManager.closeAudioDevice();  // Stop and release audio hardware
    deviceManager.removeAudioCallback(&audioPlayer);

    graph.clear(); // Remove all nodes/connections
    trackNodes.clear();
    gainProcessors.clear();
    trackEffectChains.clear();

    outputNode = nullptr;
    engineInitialized = false;
}
