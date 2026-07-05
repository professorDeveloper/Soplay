; Inno Setup script for the Sozo Windows desktop app.
; Build the app first:  flutter build windows --release
; Then compile this:    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" windows\installer\Sozo.iss
; Output: Sozo-Setup.exe on the Desktop.

#define MyAppName "Sozo"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Azamov"
#define MyAppURL "https://sozo.azamov.me"
#define MyAppExeName "soplay.exe"
#define SourceDir "..\..\build\windows\x64\runner\Release"
#define IconFile "..\runner\resources\app_icon.ico"

[Setup]
; A stable AppId so upgrades replace the previous install (do NOT change it).
AppId={{C84B2ADE-1E25-4A1D-96F1-80943040A908}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
; Per-user install -> no admin / UAC prompt, so anyone can install it.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Compile-time output folder (relative to this .iss). The setup.exe is copied to
; the Desktop by the build step afterwards.
OutputDir=..\..\build\installer
OutputBaseFilename=Sozo-Setup
SetupIconFile={#IconFile}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; The whole build output. Skip linker artifacts and the runtime WebView2
; user-data folder (it is recreated on first run).
Source: "{#SourceDir}\*"; DestDir: "{app}"; \
  Flags: recursesubdirs createallsubdirs ignoreversion; \
  Excludes: "*.lib,*.exp,*.pdb,soplay.exe.WebView2,soplay.exe.WebView2\*"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; \
  Flags: nowait postinstall skipifsilent
