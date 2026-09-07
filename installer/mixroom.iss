#ifndef MyAppVersion
  #define MyAppVersion "1.3.5"
#endif

#define MyAppName "Mixroom"
#define MyAppPublisher "Mixroom"
#define MyAppExeName "mixroom.exe"

[Setup]
AppId={{8DA39B51-604E-4B37-A36E-C944B9883DE8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\Mixroom
DefaultGroupName=Mixroom
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=Mixroom-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Mixroom"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\Mixroom"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Mixroom"; Flags: nowait postinstall skipifsilent
