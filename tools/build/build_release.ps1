# ============================================================
#  E听说助手 · 固定出包流程（三件套）
#  1) 绿色便携版 Windows  2) Windows 安装包  3) 安卓 APK
#  用法：双击 tools\build\build_release.bat
#  本脚本 UTF-8 with BOM，由 build_release.bat 转调
# ============================================================

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Windows 构建需要 nuget.exe 在 PATH（flutter_tts 的 CMake 会 find_program）
$thirdParty = Join-Path $root 'tools' 'third_party'
$env:PATH = $thirdParty + ';' + $env:PATH

$OUT = Join-Path $root '产物'
$WIN_OUT = Join-Path $OUT 'Windows'
$PORTABLE_DIR = Join-Path $WIN_OUT '绿色便携版'
$DEV_DIR = Join-Path $WIN_OUT '开发者使用版'
$SETUP_DIR = Join-Path $WIN_OUT '安装版'
$APK_DIR = Join-Path $OUT '安卓'

$ver = '0.0.0'
foreach ($line in Get-Content pubspec.yaml -Encoding UTF8) {
  if ($line -match '^version:\s*([0-9.]+)') { $ver = $Matches[1]; break }
}
$today = Get-Date -Format 'yyyyMMdd'

function Step($n, $total, $msg) {
  Write-Host ''
  Write-Host "[$n/$total] $msg" -ForegroundColor Cyan
}
function Die($msg) {
  Write-Host ''
  Write-Host "[出包失败] $msg" -ForegroundColor Red
  exit 1
}
function Run($exe, $argList, $label) {
  & $exe @argList
  if ($LASTEXITCODE -ne 0) { Die "$label 失败（退出码 $LASTEXITCODE）" }
}

Write-Host ''
Write-Host '==============================================' -ForegroundColor Green
Write-Host "  E听说助手 出包  v$ver  $today" -ForegroundColor Green
Write-Host '==============================================' -ForegroundColor Green

Step 1 7 '静态检查 flutter analyze'
Run 'flutter' @('analyze') '静态检查'

Step 2 7 '单元测试 flutter test'
Run 'flutter' @('test') '单元测试'

Step 3 7 '构建 Windows release'
# CMake 缓存会记住 nuget 缺失导致后续构建持续失败，先清缓存
$cache = Join-Path $root 'build\windows\x64'
foreach ($c in @('CMakeCache.txt', 'CMakeFiles', 'flutter\CMakeCache.txt')) {
  $path = Join-Path $cache $c
  if (Test-Path $path) { Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue }
}
Run 'flutter' @('build', 'windows', '--release') 'Windows 构建'

Step 4 7 '打包 绿色便携版'
New-Item -ItemType Directory -Force -Path $PORTABLE_DIR | Out-Null
$releaseDir = Join-Path $root 'build\windows\x64\runner\Release'
# 产物名与 GitHub Release 的资产名保持一致（ETS-TOOLS-*），拖上去不用再手动改名
$zipPath = Join-Path $PORTABLE_DIR "ETS-TOOLS-$ver-win.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $zipPath -Force
if (-not (Test-Path $zipPath)) { Die '便携版 zip 未生成' }
Write-Host '      便携版 zip 已生成（解压即用）' -ForegroundColor DarkGray

Step 5 7 '展开 开发者使用版（免解压）'
# 直接把 Release 目录整份拷过去，解压就能双击运行，方便改完立刻验证
$devTarget = Join-Path $DEV_DIR "E听说助手-$ver-开发者版"
if (Test-Path $devTarget) { Remove-Item $devTarget -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $devTarget | Out-Null
Copy-Item (Join-Path $releaseDir '*') $devTarget -Recurse -Force
if (-not (Test-Path (Join-Path $devTarget 'e_ets_helper.exe'))) {
  Die '开发者版未生成 exe'
}
Write-Host '      开发者版已生成（解压即用，与便携版内容一致）' -ForegroundColor DarkGray

Step 6 7 '生成 Windows 安装包（Inno Setup）'
$iscc = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
if (-not (Test-Path $iscc)) { Die "找不到 Inno Setup：$iscc" }
Run $iscc @('windows\installer.iss') 'Inno Setup 编译'
$setupSrc = Get-ChildItem (Join-Path $root 'build\windows\installer') -Filter '*.exe' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $setupSrc) { Die 'installer 目录未找到 Setup exe' }
New-Item -ItemType Directory -Force -Path $SETUP_DIR | Out-Null
Copy-Item $setupSrc.FullName (Join-Path $SETUP_DIR $setupSrc.Name) -Force
Write-Host '      安装包 exe 已生成（双击安装）' -ForegroundColor DarkGray

Step 7 7 '构建 Android APK'
Run 'flutter' @('build', 'apk', '--release', '--target-platform', 'android-arm64,android-x64') 'APK 构建（仅 arm64+x86_64，去掉 32 位省约 33MB）'
$apkSrc = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $apkSrc)) { Die 'APK 未生成' }
New-Item -ItemType Directory -Force -Path $APK_DIR | Out-Null
Copy-Item $apkSrc (Join-Path $APK_DIR "ETS-TOOLS-Android-$ver.apk") -Force
Write-Host '      APK 已生成（装手机）' -ForegroundColor DarkGray

Write-Host ''
Write-Host '==============================================' -ForegroundColor Green
Write-Host "  出包完成 v$ver  ($today)" -ForegroundColor Green
Write-Host '==============================================' -ForegroundColor Green
Write-Host ''
Write-Host '产物清单：' -ForegroundColor Yellow
Get-ChildItem $OUT -Recurse -File |
  Where-Object { $_.Extension -in '.exe', '.zip', '.apk' } |
  Where-Object { $_.FullName -notlike "$DEV_DIR*" } |
  ForEach-Object {
    $sizeMB = [math]::Round($_.Length / 1MB, 1)
    Write-Host ('  {0,-44} {1,7} MB' -f $_.FullName.Replace($root + '\', ''), $sizeMB)
  }
# 开发者版是整份目录，按目录汇总一行（否则会把每个 dll 都列出来）
if (Test-Path $devTarget) {
  $devMB = [math]::Round(((Get-ChildItem $devTarget -Recurse -File |
    Measure-Object Length -Sum).Sum) / 1MB, 1)
  Write-Host ('  {0,-44} {1,7} MB' -f $devTarget.Replace($root + '\', ''), $devMB)
}
Write-Host ''
Write-Host '用法区别：' -ForegroundColor Yellow
Write-Host '  安装版     = 双击 Setup 装到系统，适合发给别人'
Write-Host '  绿色便携版 = 解压即用不写注册表，适合自用/U盘'
Write-Host '  开发者版   = 已展开的免解压目录，改完可直接双击验证'
Write-Host '  安卓 APK   = 装到手机'
Write-Host ''
exit 0
