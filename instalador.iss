; Script do Inno Setup: gera um instalador de verdade para o Ponte Remota
; (atalho no Menu Iniciar, ícone opcional na Área de Trabalho, aparece em
; "Aplicativos instalados" com desinstalador). Não precisa de administrador.

#define MyAppName "Ponte Remota"
#define MyAppVersion "1.0"
#define MyAppExeName "PonteRemota.exe"
#define MyAppPublisher "Ponte Remota"

[Setup]
AppId={{8C1B5E2A-3D47-4F6B-9A0E-5B7C2D9E4F31}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=dist
OutputBaseFilename=PonteRemota-Instalador
SetupIconFile=icone.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ShowLanguageDialog=no

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar um atalho na área de trabalho"; GroupDescription: "Atalhos adicionais:"

[Files]
Source: "dist\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "liberar_firewall.bat"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Liberar no firewall"; Filename: "{app}\liberar_firewall.bat"
Name: "{group}\Desinstalar {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir o {#MyAppName} agora"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "reg.exe"; Parameters: "delete HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v PonteRemota /f"; Flags: runhidden; RunOnceId: "TirarInicio"
