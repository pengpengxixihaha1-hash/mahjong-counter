$ErrorActionPreference = "Stop"

Write-Host "=== 复制 OpenCV AAR 到项目 libs ===" -ForegroundColor Cyan

$PossibleRoots = @(
    (Join-Path $env:USERPROFILE "Downloads"),
    (Join-Path $env:USERPROFILE "Desktop"),
    "E:\",
    "D:\"
)

$sdkRoot = $null
foreach ($root in $PossibleRoots) {
    if (-not (Test-Path $root)) { continue }
    Write-Host "查找中: $root"
    $found = Get-ChildItem -Path $root -Directory -Recurse -Filter "OpenCV-android-sdk" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $sdkRoot = $found.FullName; break }
}

if (-not $sdkRoot) {
    Write-Host ""
    Write-Host "[X] 没有找到 OpenCV-android-sdk 文件夹" -ForegroundColor Red
    Write-Host "请先把 opencv-4.8.0-android-sdk.zip 解压，解压后会得到一个 OpenCV-android-sdk 文件夹。"
    Write-Host "把这个文件夹放到「下载」或「桌面」，然后再双击运行本脚本。"
    pause
    exit 1
}

Write-Host ""
Write-Host "[√] 找到 SDK: $sdkRoot" -ForegroundColor Green

$aar = Get-ChildItem -Path $sdkRoot -Recurse -File -Filter "*.aar" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $aar) {
    Write-Host ""
    Write-Host "[X] 在 SDK 里没找到 *.aar 文件" -ForegroundColor Red
    Write-Host "请打开这个文件夹看一下，确认里面有 sdk/build/outputs/aar/ 目录："
    Write-Host $sdkRoot
    pause
    exit 2
}

$destDir = "E:\微乐记牌器\app\libs"
if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
}

$destPath = Join-Path $destDir "opencv-release.aar"
Copy-Item -Force $aar.FullName $destPath

Write-Host ""
Write-Host "[√] 复制成功！" -ForegroundColor Green
Write-Host "  源文件 : $($aar.FullName)  ($([math]::Round($aar.Length/1MB,1)) MB)"
Write-Host "  目标   : $destPath"
Write-Host ""
Write-Host "下一步："
Write-Host "  1) 回到 Android Studio，点顶部工具栏大象图标 Sync Project with Gradle Files"
Write-Host "  2) 顶部菜单 Build -> Build Bundle/APK -> Build APK(s)"
Write-Host ""
pause
