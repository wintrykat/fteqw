; fteqw.iss — Inno Setup script for the FTEQW Windows-on-ARM (arm64) installer.
; Built by windows/scripts/make-installer.sh, which passes the package dir and
; version on the ISCC command line:
;   ISCC /DSrcDir=<pkg> /DAppVersion=<ver> fteqw.iss
;
; Produces a native ARM64 installer. Unsigned builds trip SmartScreen; sign the
; output with an EV/OV Authenticode cert for real distribution (see
; docs/PORTING-WINDOWS.md). No game data is bundled — the user supplies id1/ etc.

#ifndef SrcDir
  #define SrcDir "..\dist\FTEQW"
#endif
#ifndef AppVersion
  #define AppVersion "dev"
#endif

[Setup]
AppName=FTEQW
AppVerName=FTEQW {#AppVersion}
AppPublisher=FTE Team (Windows-on-ARM fork)
DefaultDirName={autopf}\FTEQW
DefaultGroupName=FTEQW
UninstallDisplayIcon={app}\fteqw.exe
OutputDir=..\dist
OutputBaseFilename=FTEQW-{#AppVersion}-win-arm64-setup
Compression=lzma2
SolidCompression=yes
; Native ARM64 install; the app is arm64 only.
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
WizardStyle=modern

[Files]
; The entire self-contained package (exe + plugins + bundled DLLs).
Source: "{#SrcDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{group}\FTEQW"; Filename: "{app}\fteqw.exe"
Name: "{group}\Uninstall FTEQW"; Filename: "{uninstallexe}"
Name: "{autodesktop}\FTEQW"; Filename: "{app}\fteqw.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\fteqw.exe"; Description: "Launch FTEQW"; Flags: nowait postinstall skipifsilent
