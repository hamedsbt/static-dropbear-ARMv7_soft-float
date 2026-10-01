@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM Huawei B612s-25d Dropbear Installer
REM
REM Windows CMD equivalent of install-dropbear.sh
REM
REM ADB endpoint : supplied by argument, default 192.168.8.1:5555
REM Router IP    : extracted from DEVICE
REM SSH address  : ROUTER_IP:22
REM
REM Persistent startup mechanism:
REM   /system/etc/autorun.sh
REM       -> /system/bin/dropbear-start &
REM
REM No /init.rc modification.
REM No /init.huawei.rc modification.
REM No /system/etc/init/dropbear.rc.
REM
REM Installation does NOT start Dropbear.
REM Reboot is required.
REM ============================================================

set "DEFAULT_DEVICE=192.168.8.1:5555"
set "SSH_PORT=22"

set "DROPBEAR_LOCAL=dropbear"
set "DROPBEARKEY_LOCAL=dropbearkey"

set "SYSTEM_BIN=/system/bin"
set "DROPBEAR_DIR=/system/etc/dropbear"

set "DROPBEAR_REMOTE=%SYSTEM_BIN%/dropbear"
set "DROPBEARKEY_REMOTE=%SYSTEM_BIN%/dropbearkey"
set "DROPBEAR_START=%SYSTEM_BIN%/dropbear-start"

set "AUTORUN=/system/etc/autorun.sh"
set "AUTORUN_BACKUP=/system/etc/autorun.sh.dropbear.orig"

REM ------------------------------------------------------------
REM 0/12 - Connection parameters
REM ------------------------------------------------------------

if "%~1"=="" (
    set "DEVICE=%DEFAULT_DEVICE%"
) else (
    set "DEVICE=%~1"
)

REM Accept:
REM   192.168.8.1:5555
REM or:
REM   192.168.8.1
REM
REM If no ADB port is supplied, use 5555.

echo %DEVICE% | findstr /C:":" >nul
if errorlevel 1 (
    set "ROUTER_IP=%DEVICE%"
    set "DEVICE=%DEVICE%:5555"
) else (
    for /f "tokens=1 delims=:" %%A in ("%DEVICE%") do set "ROUTER_IP=%%A"
)

echo.
echo ADB device : %DEVICE%
echo Router IP  : %ROUTER_IP%
echo SSH port   : %SSH_PORT%

echo.
echo ============================================================
echo  Huawei B612s-25d Dropbear Installer
echo ============================================================
echo  ADB endpoint : %DEVICE%
echo  Router IP    : %ROUTER_IP%
echo  SSH address  : %ROUTER_IP%:%SSH_PORT%
echo.

REM ------------------------------------------------------------
REM 1/12 - Local files
REM ------------------------------------------------------------

echo [1/12] Checking local Dropbear binaries...

if not exist "%DROPBEAR_LOCAL%" (
    echo ERROR: %DROPBEAR_LOCAL% not found.
    echo.
    echo Place "dropbear" in the same directory as this installer.
    exit /b 1
)

if not exist "%DROPBEARKEY_LOCAL%" (
    echo ERROR: %DROPBEARKEY_LOCAL% not found.
    echo.
    echo Place "dropbearkey" in the same directory as this installer.
    exit /b 1
)

echo Local Dropbear binaries found.

REM ------------------------------------------------------------
REM 2/12 - ADB
REM ------------------------------------------------------------

echo.
echo [2/12] Checking ADB connection...

where adb >nul 2>&1
if errorlevel 1 (
    echo ERROR: adb.exe was not found in PATH.
    echo.
    echo Install Android Platform Tools and add adb.exe to PATH.
    exit /b 1
)

adb -s "%DEVICE%" get-state >nul 2>&1

if errorlevel 1 (
    echo Connecting to %DEVICE%...
    adb connect "%DEVICE%" >nul 2>&1
)

adb -s "%DEVICE%" get-state >nul 2>&1

if errorlevel 1 (
    echo ERROR: Cannot connect to %DEVICE%
    echo.
    echo Make sure ADB over TCP is enabled on the router.
    exit /b 1
)

echo ADB connection OK.

REM ------------------------------------------------------------
REM 3/12 - Root ADB
REM ------------------------------------------------------------

echo.
echo [3/12] Requesting root ADB...

adb -s "%DEVICE%" root >nul 2>&1

timeout /t 2 /nobreak >nul

REM adbd may restart after adb root.
adb -s "%DEVICE%" wait-for-device >nul 2>&1

set "ROOT_CHECK="

for /f "delims=" %%A in ('adb -s "%DEVICE%" shell id 2^>nul') do (
    set "ROOT_CHECK=%%A"
)

echo Checking root shell...
echo %ROOT_CHECK%

echo %ROOT_CHECK% | findstr /C:"uid=0(root)" >nul

if errorlevel 1 (
    echo ERROR: ADB shell is not root.
    exit /b 1
)

echo Root ADB confirmed.

REM ------------------------------------------------------------
REM 4/12 - Device and root home directory
REM ------------------------------------------------------------

echo.
echo [4/12] Checking device...

set "UNAME="

for /f "delims=" %%A in ('adb -s "%DEVICE%" shell busyboxx uname -a 2^>nul') do (
    set "UNAME=%%A"
)

echo %UNAME%

echo %UNAME% | findstr /C:"armv7l" >nul

if errorlevel 1 (
    echo WARNING: Device does not report armv7l.
)

echo.
echo Extracting root home directory from /etc/passwd...

set "ROOT_PASSWD_ENTRY="

for /f "delims=" %%A in ('adb -s "%DEVICE%" shell "busyboxx grep ^root: /etc/passwd" 2^>nul') do (
    set "ROOT_PASSWD_ENTRY=%%A"
)

if not defined ROOT_PASSWD_ENTRY (
    echo ERROR: Could not find root entry in /etc/passwd.
    exit /b 1
)

REM /etc/passwd:
REM
REM name:password:UID:GID:GECOS:directory:shell
REM
REM Field 6 = user's home directory.

for /f "tokens=1-6 delims=:" %%A in ("%ROOT_PASSWD_ENTRY%") do (
    set "ROOT_HOME=%%F"
)

if not defined ROOT_HOME (
    echo ERROR: Root home directory is empty.
    exit /b 1
)

echo %ROOT_HOME% | findstr /B /C:"/" >nul

if errorlevel 1 (
    echo ERROR: Root home directory is not absolute: %ROOT_HOME%
    exit /b 1
)

set "ROOT_SSH_DIR=%ROOT_HOME%/.ssh"

echo Root passwd entry : %ROOT_PASSWD_ENTRY%
echo Root home          : %ROOT_HOME%
echo Root SSH directory : %ROOT_SSH_DIR%

REM ------------------------------------------------------------
REM 5/12 - Mounts
REM ------------------------------------------------------------

echo.
echo [5/12] Remounting /system...

adb -s "%DEVICE%" shell "mount -o remount,rw /system 2>/dev/null || mount -o remount,rw /dev/block/mtdblock20 /system 2>/dev/null || true"

set "SYSTEM_MOUNT="

for /f "delims=" %%A in ('adb -s "%DEVICE%" shell "mount ^| grep ^" /system ^"" 2^>nul') do (
    set "SYSTEM_MOUNT=%%A"
)

echo %SYSTEM_MOUNT%

echo %SYSTEM_MOUNT% | findstr /C:" rw," /C:" rw " /C:" rw" >nul

if errorlevel 1 (
    echo ERROR: /system is not writable.
    exit /b 1
)

echo /system is writable.

REM ------------------------------------------------------------
REM 6/12 - Directories
REM ------------------------------------------------------------

echo.
echo [6/12] Creating Dropbear directories...

adb -s "%DEVICE%" shell "mkdir -p %DROPBEAR_DIR% && chmod 0755 %SYSTEM_BIN% && chmod 0700 %DROPBEAR_DIR% && mkdir -p %ROOT_SSH_DIR% && chown root:root %ROOT_SSH_DIR% && chmod 0700 %ROOT_SSH_DIR% && if [ -f %ROOT_SSH_DIR%/authorized_keys ]; then chown root:root %ROOT_SSH_DIR%/authorized_keys; chmod 0600 %ROOT_SSH_DIR%/authorized_keys; fi"

if errorlevel 1 (
    echo ERROR: Failed to create Dropbear directories.
    exit /b 1
)

REM ------------------------------------------------------------
REM 7/12 - Dropbear binaries
REM ------------------------------------------------------------

echo.
echo [7/12] Installing Dropbear binaries...

adb -s "%DEVICE%" push "%DROPBEAR_LOCAL%" "%DROPBEAR_REMOTE%"

if errorlevel 1 (
    echo ERROR: Failed to push dropbear.
    exit /b 1
)

adb -s "%DEVICE%" push "%DROPBEARKEY_LOCAL%" "%DROPBEARKEY_REMOTE%"

if errorlevel 1 (
    echo ERROR: Failed to push dropbearkey.
    exit /b 1
)

adb -s "%DEVICE%" shell "chown root:root %DROPBEAR_REMOTE% %DROPBEARKEY_REMOTE% && chmod 0755 %DROPBEAR_REMOTE% %DROPBEARKEY_REMOTE%"

echo.
echo Installed:
adb -s "%DEVICE%" shell "ls -l %DROPBEAR_REMOTE% %DROPBEARKEY_REMOTE%"

REM ------------------------------------------------------------
REM 8/12 - Host keys
REM ------------------------------------------------------------

echo.
echo [8/12] Generating Dropbear host keys...

adb -s "%DEVICE%" shell "if [ ! -s %DROPBEAR_DIR%/dropbear_rsa_host_key ]; then %DROPBEARKEY_REMOTE% -t rsa -f %DROPBEAR_DIR%/dropbear_rsa_host_key -s 2048; fi; if [ ! -s %DROPBEAR_DIR%/dropbear_ecdsa_host_key ]; then %DROPBEARKEY_REMOTE% -t ecdsa -f %DROPBEAR_DIR%/dropbear_ecdsa_host_key -s 256; fi; if [ ! -s %DROPBEAR_DIR%/dropbear_ed25519_host_key ]; then %DROPBEARKEY_REMOTE% -t ed25519 -f %DROPBEAR_DIR%/dropbear_ed25519_host_key; fi; chmod 0600 %DROPBEAR_DIR%/dropbear_*_host_key; chown root:root %DROPBEAR_DIR%/dropbear_*_host_key"

if errorlevel 1 (
    echo ERROR: Host-key generation failed.
    exit /b 1
)

echo.
echo Host keys:
adb -s "%DEVICE%" shell "ls -l %DROPBEAR_DIR%/dropbear_*_host_key"

REM ------------------------------------------------------------
REM 9/12 - Verify Dropbear
REM ------------------------------------------------------------

echo.
echo [9/12] Verifying Dropbear...

adb -s "%DEVICE%" shell "%DROPBEAR_REMOTE% -V"

if errorlevel 1 (
    echo ERROR: Dropbear binary could not be executed.
    exit /b 1
)

REM Make sure the binary can execute, but DO NOT start server.
adb -s "%DEVICE%" shell "%DROPBEAR_REMOTE% -h >/dev/null 2>&1 || true"

REM ------------------------------------------------------------
REM 10/12 - Install persistent launcher
REM ------------------------------------------------------------

echo.
echo [10/12] Installing Dropbear launcher...

set "LAUNCHER=%TEMP%\b612-dropbear-start-%RANDOM%.sh"

> "%LAUNCHER%" echo #!/system/bin/sh
>>"%LAUNCHER%" echo.
>>"%LAUNCHER%" echo # Huawei B612s-25d
>>"%LAUNCHER%" echo # Persistent Dropbear startup helper.
>>"%LAUNCHER%" echo #
>>"%LAUNCHER%" echo # Root home directory was extracted from /etc/passwd
>>"%LAUNCHER%" echo # by the Windows installer.
>>"%LAUNCHER%" echo #
>>"%LAUNCHER%" echo # Wait for br0 to receive the router LAN address before binding.
>>"%LAUNCHER%" echo # Dropbear is deliberately NOT run with -F so it daemonizes.
>>"%LAUNCHER%" echo.
>>"%LAUNCHER%" echo IP="%ROUTER_IP%"
>>"%LAUNCHER%" echo PORT="%SSH_PORT%"
>>"%LAUNCHER%" echo ROOT_HOME="%ROOT_HOME%"
>>"%LAUNCHER%" echo ROOT_SSH_DIR="${ROOT_HOME}/.ssh"
>>"%LAUNCHER%" echo.
>>"%LAUNCHER%" echo while true
>>"%LAUNCHER%" echo do
>>"%LAUNCHER%" echo     if /system/bin/busyboxx ifconfig br0 2^>/dev/null ^|
>>"%LAUNCHER%" echo         /system/bin/busyboxx grep -q "inet addr:${IP} "
>>"%LAUNCHER%" echo     then
>>"%LAUNCHER%" echo         break
>>"%LAUNCHER%" echo     fi
>>"%LAUNCHER%" echo.
>>"%LAUNCHER%" echo     sleep 2
>>"%LAUNCHER%" echo done
>>"%LAUNCHER%" echo.
>>"%LAUNCHER%" echo # If Dropbear is already running, do nothing.
>>"%LAUNCHER%" echo if ps 2^>/dev/null ^|
>>"%LAUNCHER%" echo     /system/bin/busyboxx grep '[d]ropbear' ^>/dev/null 2^>&1
>>"%LAUNCHER%" echo then
>>"%LAUNCHER%" echo     exit 0
>>"%LAUNCHER%" echo fi
>>"%LAUNCHER%" echo.
>>"%LAUNCHER%" echo # Start Dropbear in normal daemon mode.
>>"%LAUNCHER%" echo # Explicitly specify the authorized_keys directory.
>>"%LAUNCHER%" echo /system/bin/dropbear \
>>"%LAUNCHER%" echo     -E \
>>"%LAUNCHER%" echo     -D "${ROOT_SSH_DIR}" \
>>"%LAUNCHER%" echo     -r /system/etc/dropbear/dropbear_rsa_host_key \
>>"%LAUNCHER%" echo     -r /system/etc/dropbear/dropbear_ecdsa_host_key \
>>"%LAUNCHER%" echo     -r /system/etc/dropbear/dropbear_ed25519_host_key \
>>"%LAUNCHER%" echo     -p "${IP}:${PORT}"
>>"%LAUNCHER%" echo.
>>"%LAUNCHER%" echo sleep 2
>>"%LAUNCHER%" echo.
>>"%LAUNCHER%" echo # If it successfully daemonized, finish.
>>"%LAUNCHER%" echo if ps 2^>/dev/null ^|
>>"%LAUNCHER%" echo     /system/bin/busyboxx grep '[d]ropbear' ^>/dev/null 2^>&1
>>"%LAUNCHER%" echo then
>>"%LAUNCHER%" echo     exit 0
>>"%LAUNCHER%" echo fi
>>"%LAUNCHER%" echo.
>>"%LAUNCHER%" echo # One delayed retry. This protects against a transient boot race.
>>"%LAUNCHER%" echo sleep 3
>>"%LAUNCHER%" echo.
>>"%LAUNCHER%" echo /system/bin/dropbear \
>>"%LAUNCHER%" echo     -E \
>>"%LAUNCHER%" echo     -D "${ROOT_SSH_DIR}" \
>>"%LAUNCHER%" echo     -r /system/etc/dropbear/dropbear_rsa_host_key \
>>"%LAUNCHER%" echo     -r /system/etc/dropbear/dropbear_ecdsa_host_key \
>>"%LAUNCHER%" echo     -r /system/etc/dropbear/dropbear_ed25519_host_key \
>>"%LAUNCHER%" echo     -p "${IP}:${PORT}"

echo Launcher created:
echo %LAUNCHER%

adb -s "%DEVICE%" push "%LAUNCHER%" "%DROPBEAR_START%"

if errorlevel 1 (
    echo ERROR: Failed to install Dropbear launcher.
    del /q "%LAUNCHER%" >nul 2>&1
    exit /b 1
)

adb -s "%DEVICE%" shell "chown root:root %DROPBEAR_START% && chmod 0755 %DROPBEAR_START%"

echo.
echo Installed launcher:
adb -s "%DEVICE%" shell "ls -l %DROPBEAR_START%"

echo.
echo Launcher configuration:
adb -s "%DEVICE%" shell "cat %DROPBEAR_START%"

del /q "%LAUNCHER%" >nul 2>&1

REM ------------------------------------------------------------
REM 11/12 - Install autorun hook
REM ------------------------------------------------------------

echo.
echo [11/12] Installing persistent autorun hook...

set "AUTORUN_BLOCK=%TEMP%\b612-dropbear-autorun-%RANDOM%.txt"

> "%AUTORUN_BLOCK%" echo.
>>"%AUTORUN_BLOCK%" echo # ============================================================
>>"%AUTORUN_BLOCK%" echo # DROPBEAR SSH SERVER
>>"%AUTORUN_BLOCK%" echo # Huawei B612s-25d
>>"%AUTORUN_BLOCK%" echo #
>>"%AUTORUN_BLOCK%" echo # Dropbear is started by a separate background launcher.
>>"%AUTORUN_BLOCK%" echo # The launcher waits for br0 / router IP before binding.
>>"%AUTORUN_BLOCK%" echo # ============================================================
>>"%AUTORUN_BLOCK%" echo.
>>"%AUTORUN_BLOCK%" echo /system/bin/dropbear-start ^>/dev/null 2^>&1 ^&
>>"%AUTORUN_BLOCK%" echo.
>>"%AUTORUN_BLOCK%" echo # ============================================================
>>"%AUTORUN_BLOCK%" echo # END DROPBEAR SSH SERVER
>>"%AUTORUN_BLOCK%" echo # ============================================================

adb -s "%DEVICE%" push "%AUTORUN_BLOCK%" /tmp/dropbear-autorun-block

if errorlevel 1 (
    echo ERROR: Failed to push autorun block.
    del /q "%AUTORUN_BLOCK%" >nul 2>&1
    exit /b 1
)

REM Preserve first pristine autorun.sh.
REM Every subsequent installation rebuilds autorun.sh from this backup.

adb -s "%DEVICE%" shell "if [ ! -f %AUTORUN_BACKUP% ]; then cp %AUTORUN% %AUTORUN_BACKUP%; chmod 0700 %AUTORUN_BACKUP%; chown root:root %AUTORUN_BACKUP%; fi; cp %AUTORUN_BACKUP% %AUTORUN%; cat /tmp/dropbear-autorun-block >> %AUTORUN%; chmod 0700 %AUTORUN%; chown root:root %AUTORUN%; rm -f /tmp/dropbear-autorun-block"

if errorlevel 1 (
    echo ERROR: Failed to install autorun hook.
    del /q "%AUTORUN_BLOCK%" >nul 2>&1
    exit /b 1
)

del /q "%AUTORUN_BLOCK%" >nul 2>&1

echo.
echo Dropbear autorun hook:
adb -s "%DEVICE%" shell "tail -15 %AUTORUN%"

REM ------------------------------------------------------------
REM 12/12 - Final verification
REM ------------------------------------------------------------

echo.
echo [12/12] Verifying installation...

echo.
echo === Root home directory ===
echo %ROOT_HOME%

echo.
echo === Root SSH directory ===
adb -s "%DEVICE%" shell "ls -ld %ROOT_SSH_DIR%"

echo.
echo === authorized_keys ===
adb -s "%DEVICE%" shell "if [ -f %ROOT_SSH_DIR%/authorized_keys ]; then ls -l %ROOT_SSH_DIR%/authorized_keys; else echo authorized_keys not present yet.; fi"

echo.
echo === Dropbear binary ===
adb -s "%DEVICE%" shell "ls -l %DROPBEAR_REMOTE%"

echo.
echo === Dropbear launcher ===
adb -s "%DEVICE%" shell "ls -l %DROPBEAR_START%"

echo.
echo === Host keys ===
adb -s "%DEVICE%" shell "ls -l %DROPBEAR_DIR%/dropbear_*_host_key"

echo.
echo === Autorun backup ===
adb -s "%DEVICE%" shell "ls -l %AUTORUN_BACKUP%"

echo.
echo === Autorun Dropbear hook ===
adb -s "%DEVICE%" shell "grep -n -A12 -B2 'DROPBEAR SSH SERVER' %AUTORUN%"

echo.
echo === Current Dropbear processes ===
adb -s "%DEVICE%" shell "ps ^| grep '[d]ropbear' || true"

echo.
echo === Current SSH port ===
adb -s "%DEVICE%" shell "busyboxx netstat -tunlp 2>/dev/null ^| grep ':%SSH_PORT%' || true"

echo.
echo ============================================================
echo Dropbear installation is finished.
echo ============================================================
echo.
echo IMPORTANT:
echo   Dropbear was NOT started by the installer.
echo   Reboot the Huawei B612s-25d to activate persistent startup.
echo.
echo SSH address after reboot:
echo   ssh root@%ROUTER_IP%
echo.
echo authorized_keys location:
echo   %ROOT_SSH_DIR%/authorized_keys
echo.

endlocal
exit /b 0