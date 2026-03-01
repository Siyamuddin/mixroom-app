#include <windows.h>

#include <string>

extern "C" void juceLogToFlutter(const char* msg) {
  if (msg == nullptr) {
    return;
  }

  std::string line("[JUCE] ");
  line += msg;
  line += "\n";
  OutputDebugStringA(line.c_str());
}
