@echo off
rem pull_cloud_work.bat (About Fishing F1 cloud work; Cloud, 2026-10-06)
rem Pulls the cloud_work branch of adriyunn/roblox into a folder NEXT TO the GameOne tree and opens the
rem handoff for the Coordinator. It never writes into GameOne itself: the Coordinator decides what to
rem copy, file by file, after reading HANDOFF_COORDINATOR.md.
rem
rem Usage (cmd, from anywhere):  pull_cloud_work.bat [target-folder]
rem   default target: %USERPROFILE%\OneDrive\Desktop\Claude\Roblox\cloud_work_repo
rem Needs: git on PATH (https://git-scm.com), and GitHub access to adriyunn/roblox.

setlocal
set "BRANCH=claude/hello-b2aghd"
set "REPO=https://github.com/adriyunn/roblox.git"
set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=%USERPROFILE%\OneDrive\Desktop\Claude\Roblox\cloud_work_repo"

where git >nul 2>nul
if errorlevel 1 (
  echo git is not on PATH. Install it from https://git-scm.com and run this again.
  exit /b 1
)

if exist "%TARGET%\.git" (
  echo Updating %TARGET% from %BRANCH% ...
  git -C "%TARGET%" fetch origin %BRANCH%
  if errorlevel 1 exit /b 1
  git -C "%TARGET%" checkout -q %BRANCH%
  git -C "%TARGET%" reset -q --hard origin/%BRANCH%
) else (
  echo Cloning %REPO% [%BRANCH%] into %TARGET% ...
  git clone -q --branch %BRANCH% --single-branch "%REPO%" "%TARGET%"
  if errorlevel 1 exit /b 1
)

echo.
echo Pulled. Commit:
git -C "%TARGET%" log -1 --format="  %%h  %%ad  %%s" --date=short
echo.
echo Handoff for the Coordinator:
echo   %TARGET%\cloud_work\HANDOFF_COORDINATOR.md
echo.
echo To run the offline gate on Windows (needs the team's Luau CLI on PATH as luau / luau-compile):
echo   bash "%TARGET%\cloud_work\tests\run_all.sh"      (Git Bash)
echo or run each suite from its folder:  luau tacklebox_test.luau
echo.
echo Paste this line into the Coordinator chat:
echo   Coordinator: cloud work pulled to %TARGET%\cloud_work - read HANDOFF_COORDINATOR.md and route each item.
start "" "%TARGET%\cloud_work\HANDOFF_COORDINATOR.md"
endlocal
