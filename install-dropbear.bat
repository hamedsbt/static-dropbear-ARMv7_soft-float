@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM Huawei B612s-25d
REM Static Dropbear SSH installer - Windows
REM
REM Requirements:
REM   - adb.exe available in PATH
REM   - USB/TCP ADB access to the router
REM   - Router must already have root ADB access
REM
REM Default ADB endpoint:
REM   192.168.0.217:5555
REM
REM This installer:
REM   1. Connects to ADB
REM   2. Requests root ADB
REM   3. Remounts /system read-write
REM   4. Installs dropbear and dropbearkey
REM   5. Installs host keys
REM   6. Installs dropbear-start
REM   7. Installs a persistent autorun hook
REM   8. Does NOT start Dropbear immediately
REM   9. Requests a router reboot
REM ============================================================

set "DEVICE=192.168.0.217:5555"
set "REMOTE_BIN=/system/bin"
set "REMOTE_ETC=/system/etc"
set "DROPBEAR_DIR=/system/etc/dropbear"

echo.
echo ============================================================
echo   Huawei B612s-25d Dropbear SSH Installer
echo ============================================================
echo.
echo Target: %DEVICE%
echo.

REM ------------------------------------------------------------
REM Check ADB
REM ------------------------------------------------------------

where adb >nul 2>&1
if errorlevel 1 (
echo ERROR: adb.exe was not found in PATH.
echo.
echo Install Android Platform Tools and make sure adb.exe
echo is available from the command prompt.
echo.
pause
exit /b 1
)

echo [1/10] Checking ADB...
adb version
if errorlevel 1 (
echo ERROR: adb.exe is not working.
pause
exit /b 1
)

REM ------------------------------------------------------------
REM Connect
REM ------------------------------------------------------------

echo.
echo [2/10] Connecting to %DEVICE%...
adb connect %DEVICE%

if errorlevel 1 (
echo ERROR: Could not connect to %DEVICE%.
echo.
echo Check:
echo   - Router IP address
echo   - TCP ADB port 5555
echo   - Network connectivity
echo.
pause
exit /b 1
)

adb -s %DEVICE% get-state >nul 2>&1
if errorlevel 1 (
echo ERROR: ADB connection is not ready.
pause
exit /b 1
)

echo ADB connection established.

REM ------------------------------------------------------------
REM Check root
REM ------------------------------------------------------------

echo.
echo [3/10] Requesting root ADB...
adb -s %DEVICE% root

REM Give adbd a moment to restart.
timeout /t 2 /nobreak >nul

adb -s %DEVICE% wait-for-device

REM Verify root.
for /f "delims=" %%A in ('adb -s %DEVICE% shell id 2^>nul') do (
set "ADB_ID=%%A"
)

echo ADB identity: !ADB_ID!

echo !ADB_ID! | findstr /C:"uid=0" >nul
if errorlevel 1 (
echo.
echo ERROR: ADB is not running as root.
echo.
echo The router must support "adb root".
echo.
pause
exit /b 1
)

echo Root ADB confirmed.

REM ------------------------------------------------------------
REM Check required local files
REM ------------------------------------------------------------

echo.
echo [4/10] Checking installer files...

if not exist "%~dp0dropbear" (
echo ERROR: dropbear was not found beside this installer.
echo.
echo Expected:
echo   %~dp0dropbear
echo.
pause
exit /b 1
)

if not exist "%~dp0dropbearkey" (
echo ERROR: dropbearkey was not found beside this installer.
echo.
echo Expected:
echo   %~dp0dropbearkey
echo.
pause
exit /b 1
)

if not exist "%~dp0dropbear-start" (
echo ERROR: dropbear-start was not found beside this installer.
echo.
echo Expected:
echo   %~dp0dropbear-start
echo.
pause
exit /b 1
)

REM ------------------------------------------------------------
REM Remount /system
REM ------------------------------------------------------------

echo.
echo [5/10] Remounting /system read-write...

adb -s %DEVICE% shell "mount -o remount,rw /system"

if errorlevel 1 (
echo ERROR: Failed to remount /system read-write.
pause
exit /b 1
)

echo /system remounted read-write.

REM ------------------------------------------------------------
REM Create directories
REM ------------------------------------------------------------

echo.
echo [6/10] Creating Dropbear directories...

adb -s %DEVICE% shell "mkdir -p %DROPBEAR_DIR%"
if errorlevel 1 (
echo ERROR: Failed to create %DROPBEAR_DIR%.
pause
exit /b 1
)

REM ------------------------------------------------------------
REM Push binaries
REM ------------------------------------------------------------

echo.
echo [7/10] Installing Dropbear binaries...

adb -s %DEVICE% push "%~dp0dropbear" "%REMOTE_BIN%/dropbear"
if errorlevel 1 (
echo ERROR: Failed to push dropbear.
pause
exit /b 1
)

adb -s %DEVICE% push "%~dp0dropbearkey" "%REMOTE_BIN%/dropbearkey"
if errorlevel 1 (
echo ERROR: Failed to push dropbearkey.
pause
exit /b 1
)

adb -s %DEVICE% shell "chmod 0755 /system/bin/dropbear /system/bin/dropbearkey"
if errorlevel 1 (
echo ERROR: Failed to set binary permissions.
pause
exit /b 1
)

REM ------------------------------------------------------------
REM Install host keys
REM ------------------------------------------------------------

echo.
echo [8/10] Checking/generating Dropbear host keys...

adb -s %DEVICE% shell "mkdir -p /system/etc/dropbear"

REM Generate RSA host key if absent.
adb -s %DEVICE% shell "test -f /system/etc/dropbear/dropbear_rsa_host_key || /system/bin/dropbearkey -t rsa -f /system/etc/dropbear/dropbear_rsa_host_key"

REM Generate ECDSA host key if absent.
adb -s %DEVICE% shell "test -f /system/etc/dropbear/dropbear_ecdsa_host_key || /system/bin/dropbearkey -t ecdsa -f /system/etc/dropbear/dropbear_ecdsa_host_key"

REM Generate Ed25519 host key if absent.
adb -s %DEVICE% shell "test -f /system/etc/dropbear/dropbear_ed25519_host_key || /system/bin/dropbearkey -t ed25519 -f /system/etc/dropbear/dropbear_ed25519_host_key"

adb -s %DEVICE% shell "chmod 0600 /system/etc/dropbear/dropbear_**host_key"
adb -s %DEVICE% shell "chown root:root /system/etc/dropbear/dropbear**_host_key"

REM ------------------------------------------------------------
REM Install launcher
REM ------------------------------------------------------------

echo.
echo [9/10] Installing dropbear-start...

adb -s %DEVICE% push "%~dp0dropbear-start" "/system/bin/dropbear-start"
if errorlevel 1 (
echo ERROR: Failed to install dropbear-start.
pause
exit /b 1
)

adb -s %DEVICE% shell "chmod 0755 /system/bin/dropbear-start"
if errorlevel 1 (
echo ERROR: Failed to set dropbear-start permissions.
pause
exit /b 1
)

REM ------------------------------------------------------------
REM Install persistent autorun hook
REM ------------------------------------------------------------

echo.
echo Installing persistent boot hook...

adb -s %DEVICE% shell "test -f /system/etc/autorun.sh.dropbear.orig"
if errorlevel 1 (
echo Saving original autorun.sh...
adb -s %DEVICE% shell "cp /system/etc/autorun.sh /system/etc/autorun.sh.dropbear.orig"
)

REM Create a temporary Dropbear block on the Windows side.
set "AUTORUN_BLOCK=%TEMP%\dropbear-autorun-block-%RANDOM%.txt"

(
echo.
echo # ============================================================
echo # DROPBEAR SSH SERVER
echo # Huawei B612s-25d
echo #
echo # Dropbear is started by a separate background launcher.
echo # The launcher waits for br0 / router IP before binding.
echo # ============================================================
echo.
echo /system/bin/dropbear-start ^>/dev/null 2^>^&1 ^&
echo.
echo # ============================================================
echo # END DROPBEAR SSH SERVER
echo # ============================================================
) > "%AUTORUN_BLOCK%"

REM Always rebuild autorun.sh from the pristine original.
adb -s %DEVICE% shell "cp /system/etc/autorun.sh.dropbear.orig /system/etc/autorun.sh"

REM Push block to router.
adb -s %DEVICE% push "%AUTORUN_BLOCK%" "/data/dropbear-autorun-block.txt" >nul
del "%AUTORUN_BLOCK%" >nul 2>&1

REM Append the block.
adb -s %DEVICE% shell "cat /data/dropbear-autorun-block.txt >> /system/etc/autorun.sh"
adb -s %DEVICE% shell "rm /data/dropbear-autorun-block.txt"

adb -s %DEVICE% shell "chmod 0700 /system/etc/autorun.sh"
adb -s %DEVICE% shell "chown root:root /system/etc/autorun.sh"

REM ------------------------------------------------------------
REM Verify installation
REM ------------------------------------------------------------

echo.
echo [10/10] Verifying installation...

adb -s %DEVICE% shell "ls -l /system/bin/dropbear /system/bin/dropbearkey /system/bin/dropbear-start"
if errorlevel 1 (
echo ERROR: Binary verification failed.
pause
exit /b 1
)

adb -s %DEVICE% shell "ls -l /system/etc/dropbear"
if errorlevel 1 (
echo ERROR: Host-key directory verification failed.
pause
exit /b 1
)

adb -s %DEVICE% shell "grep -n 'DROPBEAR SSH SERVER' /system/etc/autorun.sh"
if errorlevel 1 (
echo ERROR: autorun.sh verification failed.
pause
exit /b 1
)

echo.
echo ============================================================
echo   Dropbear installation completed successfully.
echo ============================================================
echo.
echo Installed:
echo   /system/bin/dropbear
echo   /system/bin/dropbearkey
echo   /system/bin/dropbear-start
echo   /system/etc/dropbear/*
echo.
echo Persistent startup:
echo   /system/etc/autorun.sh
echo.
echo The installer does NOT start Dropbear immediately.
echo.
echo Please reboot the router to activate the persistent
echo Dropbear SSH service.
echo.
echo After reboot, test:
echo.
echo   ssh root@192.168.0.217
echo.
echo ============================================================
echo.

set /p "REBOOT=Reboot the router now? [y/N]: "

if /I "!REBOOT!"=="Y" (
echo.
echo Rebooting router...
adb -s %DEVICE% shell reboot
) else (
echo.
echo Router was not rebooted.
echo Reboot manually when ready.
)

echo.
pause
exit /b 0
