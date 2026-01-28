// // ====== FORCE-INCLUDE CRITICAL HEADERS ======
// // This file acts as a precompiled header/central compilation unit for JUCE modules.

// // ====== JUCE GLOBAL CONFIGURATION (MUST BE FIRST!) ======
// // These defines MUST come before any JUCE headers to correctly configure JUCE.
// #define JUCE_IOS 1
// #define JUCE_PLUGINHOST_AU 1
// #define JUCE_USE_CURL 0
// #define JUCE_GLOBAL_MODULE_SETTINGS_INCLUDED 1
// #define JUCE_USE_CURL 0 // Redundant with above, but harmless. Ensure it's off if not used.
// #define JUCE_WEB_BROWSER 0
// #define JUCE_USE_CAMERA 0
// #define JUCE_DONT_DECLARE_PROJECTINFO 1 // Important for library builds
// #define JUCE_MODAL_LOOPS_PERMITTED 1
// #define JUCE_STRICT_REFCOUNTEDPOINTER 1

// // ====== FORCE-INCLUDE CRITICAL HEADERS FOR SYSTEM DEFS ======
// // Include system headers that define FLT_MAX/FLT_MIN *before* any other headers
// // that might implicitly depend on them (like UIKit).
// // These should generally be early includes in a compilation unit.
// #include <float.h>       // Defines FLT_MAX, FLT_MIN
// #include <limits>        // C++ numeric limits
// #include <CoreFoundation/CoreFoundation.h> // iOS base
// #include "JuceHeader.h"

// // #include <unistd.h>     // for getcwd(), chdir(), access(), chmod()
// // #include <sys/stat.h>   // for struct stat, stat(), statfs()
// // #include <sys/types.h>

// // JUCE configuration flags - these must be set before including JUCE headers
// // #define JUCE_PLUGINHOST_AU 1
// // #define JUCE_USE_CURL 0
// // #define JUCE_WEB_BROWSER 0
// // #define JUCE_USE_CAMERA 0
// // #define JUCE_DONT_DECLARE_PROJECTINFO 1
// // #define JUCE_MODAL_LOOPS_PERMITTED 1
// // #define JUCE_STRICT_REFCOUNTEDPOINTER 1

// // Include JUCE module implementations - this is the ONLY place these should be included
// // #include "juce/modules/juce_core/juce_core.cpp"
// // #include "juce/modules/juce_events/juce_events.cpp"
// // #include "juce/modules/juce_data_structures/juce_data_structures.cpp"
// // #include "juce/modules/juce_graphics/juce_graphics.cpp"
// // #include "juce/modules/juce_gui_basics/juce_gui_basics.cpp"
// // #include "juce/modules/juce_gui_extra/juce_gui_extra.cpp"
// // #include "juce/modules/juce_audio_basics/juce_audio_basics.cpp"
// // #include "juce/modules/juce_audio_devices/juce_audio_devices.cpp"
// // #include "juce/modules/juce_audio_formats/juce_audio_formats.cpp"
// // #include "juce/modules/juce_audio_processors/juce_audio_processors.cpp"
// // #include "juce/modules/juce_audio_utils/juce_audio_utils.cpp"