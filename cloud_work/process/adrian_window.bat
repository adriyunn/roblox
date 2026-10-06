@REM Written by Cloud (session roblox-9d) on 2026-10-06 from the team transcripts, without access to the project files.
@REM Numbers are from the transcripts; the proposals are for the Coordinator to rule on.
@echo off
setlocal EnableExtensions
title Adrian's window (About Fishing F1)

REM adrian_window.bat: the four hand steps of ADRIAN_WINDOW.md, one at a time, with a pause after each.
REM Safe by design: it reads files, runs verify_all.py (a dry run that reads), and opens one document.
REM It never copies FishingServer (team rule: no agent writes that file), never deletes, never writes under src\.
REM Run on the MSI. Step 2 is done on the Alienware by hand; this script waits for it.
REM Before running, set the project root (no trailing backslash):
REM   set GAMEONE=C:\Users\adria\OneDrive\Desktop\Claude\Roblox\GameOne
REM Optional, from the WINDOW READY lines:
REM   set LIVE_JSON=<live inventory json the holder names>
REM   set DEV3_STATUS=<Dev3's STATUS file>
REM   set FS_STAGED=<the re-frozen FishingServer in staging>

if not defined GAMEONE (
  echo GAMEONE is not set. In this window type, for example:
  echo    set GAMEONE=C:\Users\adria\OneDrive\Desktop\Claude\Roblox\GameOne
  echo then run this script again.
  goto :stop
)
if not exist "%GAMEONE%\Phase4\closeout\verify_all.py" (
  echo verify_all.py was not found at "%GAMEONE%\Phase4\closeout\verify_all.py". Check GAMEONE.
  goto :stop
)

set "AF=%GAMEONE%\Phase5_AF"
if not defined LIVE_JSON set "LIVE_JSON=%GAMEONE%\Phase4\closeout\live_inventory.json"
if not defined FS_STAGED set "FS_STAGED=%AF%\w3\Phase5_AF\src\FishingServer.server.lua"
set "REPORT_DIR=%AF%\evidence\window"
set "REPORT=%REPORT_DIR%\verify_window_step3.txt"
set "STEP=0"

echo ============================================================
echo  Adrian's window: four hand steps, about 10 minutes.
echo  Project root  : %GAMEONE%
echo  Live inventory: %LIVE_JSON%
echo  Report        : %REPORT%
echo  Stop rule     : if a check fails, answer anything but y. The script stops.
echo                  Post the failing line to the Coordinator. Undo nothing by hand.
echo ============================================================
echo.
echo Before step 1 the Coordinator has posted WINDOW READY with three lines:
echo   1. Dev1  : RE-FREEZE DONE FishingServer.server.lua ^<size^> / ^<hash^>
echo   2. Holder: BATCH 2 PROMOTED, dry run MATCH ^<n^> / UNMANAGED 0, FishingServer pending
echo   3. Holder: PLAY CHECK DONE, Place1 saved, Rojo connected
set "OK="
set /p OK=WINDOW READY is posted with all three lines? (y = start, anything else = stop):
if /i not "%OK%"=="y" goto :stop

:step1
set "STEP=1"
echo.
echo ===== STEP 1 of 4: resume Dev3 (this MSI) =====
echo  Waits on : nothing.
echo  Do       : in Dev3's Claude Code chat on this machine, type exactly:   resume
echo  Check    : within 5 minutes Dev3 writes a new STATUS line (BACK ... or its W2.1 verdict).
if defined DEV3_STATUS if exist "%DEV3_STATUS%" (
  echo  --- newest 3 lines of "%DEV3_STATUS%" ---
  powershell -NoProfile -Command "Get-Content -LiteralPath '%DEV3_STATUS%' -Tail 3"
  echo  -------------------------------------------
)
set "OK="
set /p OK=Dev3 answered with a new STATUS line? (y = continue, anything else = stop):
if /i not "%OK%"=="y" goto :stop

:step2
set "STEP=2"
echo.
echo ===== STEP 2 of 4: paste FishingServer into Dev1's test copy (Alienware) =====
echo  Waits on : Dev1's line  RE-FREEZE DONE FishingServer.server.lua ^<size^> / ^<hash^>
echo  Do       : on the Alienware, follow Phase5_AF\W2_ADRIAN_SERVER_INSTALL.md with the re-frozen script,
echo             into Dev1's test copy only. Never Place1.
echo  Check    : the size below equals the size in Dev1's line. The hash is checked by the dry run in step 3.
if exist "%FS_STAGED%" (
  for %%A in ("%FS_STAGED%") do echo  staged FishingServer: %%~zA bytes   "%%~fA"
) else (
  echo  staged FishingServer not found at "%FS_STAGED%". Set FS_STAGED to the path Dev1 named, or compare the size on the Alienware.
)
echo             Then Dev1 confirms in STATUS:  TEST COPY INSTALLED ^<size^> / ^<hash^>
set "OK="
set /p OK=Size matches and Dev1 confirmed TEST COPY INSTALLED? (y = continue, anything else = stop):
if /i not "%OK%"=="y" goto :stop

:step3
set "STEP=3"
echo.
echo ===== STEP 3 of 4: the FishingServer copy (this MSI, Place1) =====
echo  Waits on : the holder's lines  BATCH 2 PROMOTED, dry run MATCH ^<n^> / UNMANAGED 0, FishingServer pending
echo             and  PLAY CHECK DONE, Place1 saved, Rojo connected
echo  Do       : run the ONE copy command from ADRIAN_FS_COPY.md yourself, in another window, exactly once.
echo             This script does not run it: no agent writes that file.
echo             Wait for the holder's SYNCED line, then come back here.
if exist "%AF%\ADRIAN_FS_COPY.md" (
  echo  --- ADRIAN_FS_COPY.md ---
  type "%AF%\ADRIAN_FS_COPY.md"
  echo  -------------------------
) else (
  echo  ADRIAN_FS_COPY.md not found under "%AF%". Stop and ask the holder.
  goto :stop
)
set "OK="
set /p OK=Copy command run exactly once and the holder posted SYNCED? (y = run the dry run, anything else = stop):
if /i not "%OK%"=="y" goto :stop
if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%"
echo  Dry run : python Phase4\closeout\verify_all.py "%LIVE_JSON%" "%REPORT%"
pushd "%GAMEONE%"
python Phase4\closeout\verify_all.py "%LIVE_JSON%" "%REPORT%"
set "RC=%ERRORLEVEL%"
popd
echo  verify_all exit code: %RC%
if exist "%REPORT%" (
  echo  --- MATCH / UNMANAGED / MISMATCH / MISSING lines from the report ---
  findstr /i /c:"MATCH" /c:"UNMANAGED" /c:"MISMATCH" /c:"MISSING" "%REPORT%"
  echo  --------------------------------------------------------------------
) else (
  echo  No report was written at "%REPORT%". Treat this as a failed check.
)
echo  Check    : MATCH count equals the holder's ^<n^>, UNMANAGED 0, no MISMATCH, exit code 0,
echo             and the FishingServer row shows the new size.
set "OK="
set /p OK=Dry run reads MATCH as expected and UNMANAGED 0? (y = continue, anything else = stop):
if /i not "%OK%"=="y" goto :stop

:step4
set "STEP=4"
echo.
echo ===== STEP 4 of 4: the feel review (about 30 minutes) =====
echo  Waits on : step 3 passed.
echo  Do       : play the F1 loop in the order F1_FEEL_REVIEW.md gives; write one line per item in that document.
echo  Check    : none. This is the review. Post FEEL REVIEW DONE to the Coordinator when finished.
if exist "%AF%\F1_FEEL_REVIEW.md" (
  start "" "%AF%\F1_FEEL_REVIEW.md"
) else (
  echo  F1_FEEL_REVIEW.md not found under "%AF%". Open it by hand.
)
echo.
echo  Window steps done. Post to the Coordinator:
echo    WINDOW DONE: Dev3 resumed; test copy installed; FS copied, dry run MATCH ^<n^> / UNMANAGED 0; feel review started
echo    report: %REPORT%
goto :end

:stop
echo.
echo  STOPPED at step %STEP%. Post the last check line, and the report path if step 3 ran, to the Coordinator.
echo  Do not continue the remaining steps by hand. The holder rolls back if needed, not you.
pause
endlocal
exit /b 1

:end
pause
endlocal
exit /b 0
