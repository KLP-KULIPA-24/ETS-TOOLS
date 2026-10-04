; E听说助手 Windows 安装包脚本（Inno Setup 6）
; 编译：ISCC.exe windows\installer.iss
; 前置：先执行 flutter build windows --release

#define MyAppName "E听说助手"
#define MyAppVersion "0.8.2"
#define MyAppPublisher "苦力怕.KULIPA"
#define MyAppURL "https://github.com/KLP-KULIPA-24"
#define MyAppExeName "e_ets_helper.exe"

[Setup]
AppId={{7E3B7C42-8D14-4F6A-9C21-5A8E1F0B3D99}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} V0.8.2
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
; 图标
SetupIconFile=runner\resources\runner.exe.ico
; 品牌横幅（左侧向导图：logo + 名称 + V0.8.2）
WizardImageFile=..\assets\branding\installer-banner.bmp
WizardSmallImageFile=..\assets\branding\installer-banner.bmp
; 品牌配色（主色 #4F7CFF、浅底）
WizardStyle=modern
WizardResizable=no
DisableProgramGroupPage=yes
DisableWelcomePage=no
SetupLogging=yes
UninstallDisplaySize=70
; 安装目录允许用户修改
UsePreviousAppDir=yes
AllowNoIcons=yes
; 输出
OutputDir=..\build\windows\installer
OutputBaseFilename=ETS-TOOLS-Setup-{#MyAppVersion}-x64
; 压缩
Compression=lzma2/max
SolidCompression=yes
; 架构
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
; 若应用正在运行，尝试关闭
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "chinese"; MessagesFile: "..\tools\third_party\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; 卸载时清理安装目录残留
Type: filesandordirs; Name: "{app}\data"
