; Build with Inno Setup Compiler (ISCC.exe).
; Expected input: build\\windows\\x64\\runner\\Release\\

#define MyAppName "MindBubble"
#define MyAppVersion "0.4.0"
#define MyAppPublisher "MindBubble"
#define MyAppExeName "mind_bubble.exe"
#define BuildDir "..\\build\\windows\\x64\\runner\\Release"
#define OutputDir "..\\dist"

[Setup]
AppId={{B3D1A6F8-3B5D-4B4E-9A7E-7C4A5F2C1D90}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir={#OutputDir}
OutputBaseFilename=MindBubble-{#MyAppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#MyAppExeName}
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
