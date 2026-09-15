#include <juce_core/juce_core.h>
#include "../ProducerPluginIdentityCache.h"
#include <cstdlib>
#include <iostream>

void check(bool condition)
{
    if (!condition) { std::cerr << "identity cache test failed\n"; std::exit(1); }
}

int main()
{
    int reads = 0;
    juce::NamedValueSet firstNode;
    auto first = [&] { ++reads; return juce::String("plugin-A"); };
    for (int i = 0; i < 1000; ++i)
        check(readCachedProducerPluginIdentity(firstNode, first) == "plugin-A");
    check(reads == 1);
    // Other node properties are unaffected.
    firstNode.set("unrelated", 42);
    check(firstNode["unrelated"] == juce::var(42));
    // A replacement node starts empty, including when its graph ID is reused.
    juce::NamedValueSet replacementNode;
    check(readCachedProducerPluginIdentity(replacementNode, [&] {
        ++reads; return juce::String("plugin-B");
    }) == "plugin-B");
    check(reads == 2);
    // Empty/unsupported results must not repeatedly query the processor.
    juce::NamedValueSet unsupportedNode;
    for (int i = 0; i < 1000; ++i)
        check(readCachedProducerPluginIdentity(unsupportedNode, [&] {
            ++reads; return juce::String();
        }).isEmpty());
    check(reads == 3);
    std::cout << "identity cache tests passed\n";
}
