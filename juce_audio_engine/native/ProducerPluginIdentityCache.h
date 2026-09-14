#pragma once

// Separate from the plugin API so the cache can be tested without hosting audio.
// Empty identities are cached too: unsupported/builtin plugins need no retries.
template <typename Properties, typename ReadIdentity>
auto readCachedProducerPluginIdentity(Properties& properties, ReadIdentity readIdentity)
{
    const auto key = "mixroom.producerPluginIdentity.v1";
    if (!properties.contains(key))
        properties.set(key, readIdentity());
    return properties[key].toString();
}
