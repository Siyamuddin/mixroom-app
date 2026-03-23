#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shellapi.h>
#include <windows.h>

#include <algorithm>
#include <cctype>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kMixroomExtension[] = L".mixroom";
constexpr wchar_t kMixroomProgId[] = L"mixroom.project";
constexpr wchar_t kMixroomDocumentIconFile[] = L"mixroom_document.ico";

std::wstring GetExecutablePath() {
  std::wstring buffer(MAX_PATH, L'\0');
  const DWORD length = ::GetModuleFileNameW(nullptr, buffer.data(),
                                            static_cast<DWORD>(buffer.size()));
  if (length == 0) {
    return std::wstring();
  }
  buffer.resize(length);
  return buffer;
}

std::wstring QuotePath(const std::wstring& path) {
  return L"\"" + path + L"\"";
}

std::wstring GetExecutableDirectory(const std::wstring& executable_path) {
  const size_t separator = executable_path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return std::wstring();
  }
  return executable_path.substr(0, separator);
}

std::wstring BuildDocumentIconValue(const std::wstring& executable_path) {
  const std::wstring executable_dir = GetExecutableDirectory(executable_path);
  if (!executable_dir.empty()) {
    const std::wstring icon_path =
        executable_dir + L"\\" + kMixroomDocumentIconFile;
    const DWORD attributes = ::GetFileAttributesW(icon_path.c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES &&
        (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
      return QuotePath(icon_path);
    }
  }

  return QuotePath(executable_path) + L",0";
}

bool SetRegistryStringValue(HKEY root, const std::wstring& subkey,
                            const std::wstring& name,
                            const std::wstring& value) {
  HKEY key = nullptr;
  if (::RegCreateKeyExW(root, subkey.c_str(), 0, nullptr, 0, KEY_SET_VALUE,
                        nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return false;
  }

  const wchar_t* value_ptr = value.c_str();
  const DWORD size_bytes =
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
  const LONG result = ::RegSetValueExW(
      key, name.empty() ? nullptr : name.c_str(), 0, REG_SZ,
      reinterpret_cast<const BYTE*>(value_ptr), size_bytes);
  ::RegCloseKey(key);
  return result == ERROR_SUCCESS;
}

void RegisterMixroomFileAssociation() {
  const std::wstring executable_path = GetExecutablePath();
  if (executable_path.empty()) {
    return;
  }

  const std::wstring command = QuotePath(executable_path) + L" \"%1\"";
  const std::wstring icon = BuildDocumentIconValue(executable_path);

  bool changed = false;
  changed |= SetRegistryStringValue(HKEY_CURRENT_USER,
                                    L"Software\\Classes\\.mixroom", L"",
                                    kMixroomProgId);
  changed |= SetRegistryStringValue(HKEY_CURRENT_USER,
                                    L"Software\\Classes\\.mixroom",
                                    L"Content Type",
                                    L"application/x-mixroom");
  changed |= SetRegistryStringValue(HKEY_CURRENT_USER,
                                    L"Software\\Classes\\.mixroom",
                                    L"PerceivedType", L"document");
  changed |= SetRegistryStringValue(HKEY_CURRENT_USER,
                                    L"Software\\Classes\\mixroom.project", L"",
                                    L"Mixroom Project");
  changed |= SetRegistryStringValue(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\mixroom.project\\DefaultIcon", L"", icon);
  changed |= SetRegistryStringValue(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\mixroom.project\\shell\\open\\command", L"",
      command);

  if (changed) {
    ::SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
  }
}

std::string FindInitialMixroomPath(
    const std::vector<std::string>& command_line_arguments) {
  for (const auto& argument : command_line_arguments) {
    std::string lower = argument;
    std::transform(lower.begin(), lower.end(), lower.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    if (lower.size() >= 8 &&
        lower.compare(lower.size() - 8, 8, ".mixroom") == 0) {
      return argument;
    }
  }
  return std::string();
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const std::string initial_mixroom_path =
      FindInitialMixroomPath(command_line_arguments);

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  RegisterMixroomFileAssociation();

  FlutterWindow window(project, initial_mixroom_path);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1440, 900);
  if (!window.Create(L"mixroom", origin, size))
  {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
