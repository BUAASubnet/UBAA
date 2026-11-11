; 安装器身份固定，后续版本覆盖安装到同一目录。
#ifndef AppVersion
  #error AppVersion 必须由发布工作流提供
#endif
[Setup]
AppId={{7C793D0E-4CE3-4469-88D5-4A0561DC894E}
AppName=UBAA
AppVersion={#AppVersion}
AppPublisher=UBAA
DefaultDirName={localappdata}\Programs\UBAA
DefaultGroupName=UBAA
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=../../../.ubaa_local/release/public
OutputBaseFilename=UBAA-{#AppVersion}-windows-x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\ubaa_flutter.exe
[Files]
Source: "../../../apps/ubaa_flutter/build/windows/x64/runner/Release/*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\UBAA"; Filename: "{app}\ubaa_flutter.exe"
Name: "{autodesktop}\UBAA"; Filename: "{app}\ubaa_flutter.exe"; Tasks: desktopicon
[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; Flags: unchecked
[Run]
Filename: "{app}\ubaa_flutter.exe"; Description: "启动 UBAA"; Flags: nowait postinstall skipifsilent
