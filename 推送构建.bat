@echo off
rem ================================================================
rem  Five-0-K counter: push code to GitHub, cloud builds the ipa
rem  Double-click this file after any code change.
rem  First push: a browser window pops up, login GitHub once.
rem ================================================================
set GIT=C:\Users\Administrator\Tools\PortableGit\cmd\git.exe
cd /d %~dp0

echo === 1/2 commit local changes ===
"%GIT%" add -A
"%GIT%" -c user.name=wl50k-dev -c user.email=wl50k-dev@local commit -m "update"
echo (if nothing to commit, just pushing existing code)

echo.
echo === 2/2 push to GitHub ===
"%GIT%" push -u origin main

echo.
echo ================================================
echo  If push succeeded, open your repo Actions page:
echo  https://github.com/YOUR-NAME/YOUR-REPO/actions
echo  Download artifact: WeiLePoker50K-unsigned-ipa
echo ================================================
pause
