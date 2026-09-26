@echo off
title Copy OpenCV AAR

set "SRC=E:\垃圾桶\OpenCV-android-sdk\sdk\build\outputs\aar"
set "DST=E:\微乐记牌器\app\libs"

echo === Source search: %SRC% ===

if not exist "%SRC%\opencv-release.aar" (
    echo [FAIL] opencv-release.aar not found in:
    echo   %SRC%
    echo.
    echo Open E:\垃圾桶\OpenCV-android-sdk\sdk in explorer and check
    echo if there is a folder "build\outputs\aar" with opencv-release.aar
    pause
    exit /b 1
)

if not exist "%DST%" mkdir "%DST%"

copy /y "%SRC%\opencv-release.aar" "%DST%\opencv-release.aar"

if errorlevel 1 (
    echo [FAIL] Copy error.
    pause
    exit /b 2
)

echo.
echo === SUCCESS: opencv-release.aar copied ===
echo   From: %SRC%\opencv-release.aar
echo   To  : %DST%\opencv-release.aar
echo.
echo === Next steps in Android Studio ===
echo 1. Click the elephant icon (Sync Project with Gradle Files)
echo 2. Menu Build - Build Bundle/APK - Build APK(s)
echo 3. Install APK on phone, watch Logcat for "PokerCounter" and copy 3 lines:
echo    found XX card boxes: hand=?, playOut=?
echo    stable-hits-details: ...
echo    COUNTS >>> K(..) 7(..) xiaoWang(..) daWang(..)
echo.
pause
