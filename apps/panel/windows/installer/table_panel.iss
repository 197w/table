; Instalator panelu Table na Windows (Inno Setup 6).
; Buduje go GitHub Actions (.github/workflows/panel-windows-release.yml):
;   iscc /DAppVersion=0.2.0 /DSourceDir=<folder Release> /DOutputDir=<folder wyjścia> table_panel.iss
;
; Instalacja idzie do folderu użytkownika, bez uprawnień administratora. Dzięki temu
; aktualizacja z panelu instaluje się po cichu, bez okna z pytaniem o zgodę systemu.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\installer"
#endif

[Setup]
; Stały identyfikator: każda nowa wersja nadpisuje poprzednią zamiast instalować się obok.
AppId={{7D4E2B1A-3C5F-4E8A-9B61-2F0C8D5A7E34}
AppName=Table Panel
AppVersion={#AppVersion}
AppVerName=Table Panel {#AppVersion}
AppPublisher=Table
DefaultDirName={localappdata}\Programs\Table Panel
DefaultGroupName=Table
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=TablePanelSetup-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\table_panel.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=force
RestartApplications=no

[Languages]
Name: "polish"; MessagesFile: "compiler:Languages\Polish.isl"

[Tasks]
Name: "desktopicon"; Description: "Skrót na pulpicie"; GroupDescription: "Skróty:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Table Panel"; Filename: "{app}\table_panel.exe"
Name: "{userdesktop}\Table Panel"; Filename: "{app}\table_panel.exe"; Tasks: desktopicon

[Run]
; Po instalacji, także cichej przy aktualizacji, panel uruchamia się sam.
Filename: "{app}\table_panel.exe"; Description: "Uruchom Table Panel"; Flags: nowait postinstall
