#pragma once

#include "../../native/ProducerPluginIdentityCache.h"

// Model identity only. Never substitute this for an engine loading identifier.
// JUCE's createIdentifierString includes the file path, so do not use it here.
inline juce::String producerPluginIdentity(juce::AudioProcessor* processor)
{
    auto* plugin = dynamic_cast<juce::AudioPluginInstance*>(processor);
    if (plugin == nullptr) return {};
    juce::PluginDescription description;
    plugin->fillInPluginDescription(description);
    if (description.uniqueId == 0 || description.pluginFormatName.isEmpty()
        || description.manufacturerName.isEmpty() || description.name.isEmpty()) return {};
    juce::Array<juce::var> parts;
    parts.add(description.pluginFormatName);
    parts.add(description.manufacturerName);
    parts.add(description.name);
    parts.add(juce::String::toHexString(description.uniqueId));
    parts.add(description.version);
    const auto serialized = juce::JSON::toString(juce::var(parts), true);
    return "plugin_descriptor_v1:" + serialized;
}

// Call only from the existing control-thread lookup under graphRenderMutex.
// Node owns its processor for its entire lifetime, so this cache cannot outlive
// or be transferred to a replacement plugin, even if the graph reuses a node ID.
inline juce::String cachedProducerPluginIdentity(juce::AudioProcessorGraph::Node* node)
{
    if (node == nullptr) return {};
    return readCachedProducerPluginIdentity(node->properties, [node] {
        return producerPluginIdentity(node->getProcessor());
    });
}
