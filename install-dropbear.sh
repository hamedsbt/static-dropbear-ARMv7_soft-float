#!/usr/bin/env bash

set -e
set -u

# ============================================================
# Huawei B612s-25d Dropbear Installer
#
# ADB endpoint : supplied by user, default 192.168.8.1:5555
# Router IP    : extracted from DEVICE
# SSH address  : ${ROUTER_IP}:22
#
# Persistent startup mechanism:
#   /system/etc/autorun.sh
#       -> /system/bin/dropbear-start &
#
# No /init.rc modification.
# No /init.huawei.rc modification.
# No /system/etc/init/dropbear.rc.
#
# Installation does NOT start Dropbear.
# Reboot is required.
# ============================================================

# ------------------------------------------------------------
# Connection parameters
# ------------------------------------------------------------

DEFAULT_DEVICE="192.168.8.1:5555"
SSH_PORT="22"

if [ "$#" -ge 1 ] && [ -n "$1" ]; then
    DEVICE="$1"
else
    DEVICE="$DEFAULT_DEVICE"
fi

# Accept either:
#   192.168.8.1:5555
# or:
#   192.168.8.1
#
# If no ADB port is supplied, use TCP port 5555.

case "$DEVICE" in
    *:*)
        ROUTER_IP="${DEVICE%:*}"
        ;;
    *)
        ROUTER_IP="$DEVICE"
        DEVICE="${DEVICE}:5555"
        ;;
esac

ADB=(adb -s "$DEVICE")

echo "ADB device : $DEVICE"
echo "Router IP  : $ROUTER_IP"
echo "SSH port   : $SSH_PORT"

DROPBEAR_LOCAL="./dropbear"
DROPBEARKEY_LOCAL="./dropbearkey"

SYSTEM_BIN="/system/bin"
DROPBEAR_DIR="/system/etc/dropbear"

DROPBEAR_REMOTE="${SYSTEM_BIN}/dropbear"
DROPBEARKEY_REMOTE="${SYSTEM_BIN}/dropbearkey"
DROPBEAR_START="${SYSTEM_BIN}/dropbear-start"

AUTORUN="/system/etc/autorun.sh"
AUTORUN_BACKUP="/system/etc/autorun.sh.dropbear.orig"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo
echo "============================================================"
echo " Huawei B612s-25d Dropbear Installer"
echo "============================================================"
echo " ADB endpoint : $DEVICE"
echo " Router IP    : $ROUTER_IP"
echo " SSH address  : $ROUTER_IP:$SSH_PORT"
echo

# ------------------------------------------------------------
# 1/12 - Local files
# ------------------------------------------------------------

echo "[1/12] Checking local Dropbear binaries..."

if [ ! -f "$DROPBEAR_LOCAL" ]; then
    echo "ERROR: $DROPBEAR_LOCAL not found."
    exit 1
fi

if [ ! -f "$DROPBEARKEY_LOCAL" ]; then
    echo "ERROR: $DROPBEARKEY_LOCAL not found."
    exit 1
fi

chmod +x "$DROPBEAR_LOCAL" "$DROPBEARKEY_LOCAL"

# ------------------------------------------------------------
# 2/12 - ADB
# ------------------------------------------------------------

echo "[2/12] Checking ADB connection..."

if ! "${ADB[@]}" get-state >/dev/null 2>&1; then
    adb connect "$DEVICE" >/dev/null 2>&1 || true
fi

if ! "${ADB[@]}" get-state >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to $DEVICE"
    exit 1
fi

echo "ADB connection OK."

# ------------------------------------------------------------
# 3/12 - Root ADB
# ------------------------------------------------------------

echo "[3/12] Requesting root ADB..."

"${ADB[@]}" root >/dev/null 2>&1 || true

sleep 2

# Reconnect because adbd may restart after adb root.
"${ADB[@]}" wait-for-device

ROOT_CHECK="$("${ADB[@]}" shell id 2>/dev/null | tr -d '\r')"

echo "Checking root shell..."
echo "$ROOT_CHECK"

case "$ROOT_CHECK" in
    *"uid=0(root)"*)
        ;;
    *)
        echo "ERROR: ADB shell is not root."
        exit 1
        ;;
esac

# ------------------------------------------------------------
# 4/12 - Device and root home directory
# ------------------------------------------------------------

echo "[4/12] Checking device..."

UNAME="$("${ADB[@]}" shell 'busyboxx uname -a' 2>/dev/null | tr -d '\r')"
echo "$UNAME"

case "$UNAME" in
    *armv7l*)
        ;;
    *)
        echo "WARNING: Device does not report armv7l."
        ;;
esac

echo
echo "Extracting root home directory from /etc/passwd..."

ROOT_PASSWD_ENTRY="$(
    "${ADB[@]}" shell 'busyboxx grep "^root:" /etc/passwd' 2>/dev/null |
    tr -d '\r'
)"

if [ -z "$ROOT_PASSWD_ENTRY" ]; then
    echo "ERROR: Could not find root entry in /etc/passwd."
    exit 1
fi

# /etc/passwd format:
#
# name:password:UID:GID:GECOS:directory:shell
#
# Field 6 = user's home directory.

ROOT_HOME="$(
    printf '%s\n' "$ROOT_PASSWD_ENTRY" |
    cut -d: -f6
)"

if [ -z "$ROOT_HOME" ]; then
    echo "ERROR: Root home directory is empty."
    exit 1
fi

case "$ROOT_HOME" in
    /*)
        ;;
    *)
        echo "ERROR: Root home directory is not absolute: $ROOT_HOME"
        exit 1
        ;;
esac

ROOT_SSH_DIR="${ROOT_HOME}/.ssh"

echo "Root passwd entry : $ROOT_PASSWD_ENTRY"
echo "Root home          : $ROOT_HOME"
echo "Root SSH directory : $ROOT_SSH_DIR"

# ------------------------------------------------------------
# 5/12 - Mounts
# ------------------------------------------------------------

echo "[5/12] Remounting /system..."

"${ADB[@]}" shell '
    mount -o remount,rw /system 2>/dev/null ||
    mount -o remount,rw /dev/block/mtdblock20 /system 2>/dev/null ||
    true
'

SYSTEM_MOUNT="$(
    "${ADB[@]}" shell 'mount | grep " /system "' 2>/dev/null |
    tr -d '\r'
)"

echo "$SYSTEM_MOUNT"

case "$SYSTEM_MOUNT" in
    *" rw,"*|*" rw "*|*" rw"*)
        ;;
    *)
        echo "ERROR: /system is not writable."
        exit 1
        ;;
esac

# ------------------------------------------------------------
# 6/12 - Directories
# ------------------------------------------------------------

echo "[6/12] Creating Dropbear directories..."

"${ADB[@]}" shell "
    mkdir -p '$DROPBEAR_DIR'
    chmod 0755 '$SYSTEM_BIN'
    chmod 0700 '$DROPBEAR_DIR'

    # Root SSH directory is derived from /etc/passwd.
    mkdir -p '$ROOT_SSH_DIR'
    chown root:root '$ROOT_SSH_DIR'
    chmod 0700 '$ROOT_SSH_DIR'

    # Preserve an existing authorized_keys file.
    if [ -f '$ROOT_SSH_DIR/authorized_keys' ]; then
        chown root:root '$ROOT_SSH_DIR/authorized_keys'
        chmod 0600 '$ROOT_SSH_DIR/authorized_keys'
    fi
"

# ------------------------------------------------------------
# 7/12 - Dropbear binaries
# ------------------------------------------------------------

echo "[7/12] Installing Dropbear binaries..."

"${ADB[@]}" push "$DROPBEAR_LOCAL" "$DROPBEAR_REMOTE"
"${ADB[@]}" push "$DROPBEARKEY_LOCAL" "$DROPBEARKEY_REMOTE"

"${ADB[@]}" shell "
    chown root:root '$DROPBEAR_REMOTE' '$DROPBEARKEY_REMOTE'
    chmod 0755 '$DROPBEAR_REMOTE' '$DROPBEARKEY_REMOTE'
"

echo "Installed:"
"${ADB[@]}" shell "
    ls -l '$DROPBEAR_REMOTE' '$DROPBEARKEY_REMOTE'
"

# ------------------------------------------------------------
# 8/12 - Host keys
# ------------------------------------------------------------

echo "[8/12] Generating Dropbear host keys..."

"${ADB[@]}" shell "
    if [ ! -s '$DROPBEAR_DIR/dropbear_rsa_host_key' ]; then
        '$DROPBEARKEY_REMOTE' \
            -t rsa \
            -f '$DROPBEAR_DIR/dropbear_rsa_host_key' \
            -s 2048
    fi

    if [ ! -s '$DROPBEAR_DIR/dropbear_ecdsa_host_key' ]; then
        '$DROPBEARKEY_REMOTE' \
            -t ecdsa \
            -f '$DROPBEAR_DIR/dropbear_ecdsa_host_key' \
            -s 256
    fi

    if [ ! -s '$DROPBEAR_DIR/dropbear_ed25519_host_key' ]; then
        '$DROPBEARKEY_REMOTE' \
            -t ed25519 \
            -f '$DROPBEAR_DIR/dropbear_ed25519_host_key'
    fi

    chmod 0600 '$DROPBEAR_DIR/dropbear_'*_host_key
    chown root:root '$DROPBEAR_DIR/dropbear_'*_host_key
"

echo
echo "Host keys:"
"${ADB[@]}" shell "ls -l '$DROPBEAR_DIR'/dropbear_*_host_key"

# ------------------------------------------------------------
# 9/12 - Verify Dropbear
# ------------------------------------------------------------

echo "[9/12] Verifying Dropbear..."

DROPBEAR_VERSION="$(
    "${ADB[@]}" shell "'$DROPBEAR_REMOTE' -V" 2>&1 |
    tr -d '\r'
)"

echo "$DROPBEAR_VERSION"

# Make sure the binary can execute, but DO NOT start the server.
"${ADB[@]}" shell "'$DROPBEAR_REMOTE' -h >/dev/null 2>&1 || true"

# ------------------------------------------------------------
# 10/12 - Install persistent launcher
# ------------------------------------------------------------

echo "[10/12] Installing Dropbear launcher..."

LAUNCHER="$TMP_DIR/dropbear-start"

cat > "$LAUNCHER" <<EOF
#!/system/bin/sh

# Huawei B612s-25d
# Persistent Dropbear startup helper.
#
# Root home directory was extracted from /etc/passwd
# by the installer.
#
# Wait for br0 to receive the router LAN address before binding.
# Dropbear is deliberately NOT run with -F so it daemonizes.

IP="$ROUTER_IP"
PORT="$SSH_PORT"
ROOT_HOME="$ROOT_HOME"
ROOT_SSH_DIR="\${ROOT_HOME}/.ssh"

while true
do
    if /system/bin/busyboxx ifconfig br0 2>/dev/null |
        /system/bin/busyboxx grep -q "inet addr:\${IP} "
    then
        break
    fi

    sleep 2
done

# If Dropbear is already running, do nothing.
if ps 2>/dev/null |
    /system/bin/busyboxx grep '[d]ropbear' >/dev/null 2>&1
then
    exit 0
fi

# Start Dropbear in normal daemon mode.
# Explicitly specify the authorized_keys directory.
/system/bin/dropbear \
    -E \
    -D "\${ROOT_SSH_DIR}" \
    -r /system/etc/dropbear/dropbear_rsa_host_key \
    -r /system/etc/dropbear/dropbear_ecdsa_host_key \
    -r /system/etc/dropbear/dropbear_ed25519_host_key \
    -p "\${IP}:\${PORT}"

sleep 2

# If it successfully daemonized, finish.
if ps 2>/dev/null |
    /system/bin/busyboxx grep '[d]ropbear' >/dev/null 2>&1
then
    exit 0
fi

# One delayed retry. This protects against a transient boot race.
sleep 3

/system/bin/dropbear \
    -E \
    -D "\${ROOT_SSH_DIR}" \
    -r /system/etc/dropbear/dropbear_rsa_host_key \
    -r /system/etc/dropbear/dropbear_ecdsa_host_key \
    -r /system/etc/dropbear/dropbear_ed25519_host_key \
    -p "\${IP}:\${PORT}"
EOF

"${ADB[@]}" push "$LAUNCHER" "$DROPBEAR_START"

"${ADB[@]}" shell "
    chown root:root '$DROPBEAR_START'
    chmod 0755 '$DROPBEAR_START'
"

echo
echo "Installed launcher:"
"${ADB[@]}" shell "ls -l '$DROPBEAR_START'"

echo
echo "Launcher configuration:"
"${ADB[@]}" shell "cat '$DROPBEAR_START'"

# ------------------------------------------------------------
# 11/12 - Install autorun hook
# ------------------------------------------------------------

echo "[11/12] Installing persistent autorun hook..."

AUTORUN_BLOCK="$TMP_DIR/dropbear-autorun-block"

cat > "$AUTORUN_BLOCK" <<'EOF'

# ============================================================
# DROPBEAR SSH SERVER
# Huawei B612s-25d
#
# Dropbear is started by a separate background launcher.
# The launcher waits for br0 / router IP before binding.
# ============================================================

/system/bin/dropbear-start >/dev/null 2>&1 &

# ============================================================
# END DROPBEAR SSH SERVER
# ============================================================
EOF

"${ADB[@]}" push "$AUTORUN_BLOCK" /tmp/dropbear-autorun-block

# Preserve the first pristine autorun.sh.
"${ADB[@]}" shell "
    if [ ! -f '$AUTORUN_BACKUP' ]; then
        cp '$AUTORUN' '$AUTORUN_BACKUP'
        chmod 0700 '$AUTORUN_BACKUP'
        chown root:root '$AUTORUN_BACKUP'
    fi

    # Always rebuild autorun.sh from the original backup.
    # This makes repeated installer runs idempotent.
    cp '$AUTORUN_BACKUP' '$AUTORUN'

    cat /tmp/dropbear-autorun-block >> '$AUTORUN'

    chmod 0700 '$AUTORUN'
    chown root:root '$AUTORUN'

    rm -f /tmp/dropbear-autorun-block
"

echo
echo "Dropbear autorun hook:"
"${ADB[@]}" shell "
    tail -15 '$AUTORUN'
"

# ------------------------------------------------------------
# 12/12 - Final verification
# ------------------------------------------------------------

echo "[12/12] Verifying installation..."

echo
echo "=== Root home directory ==="
echo "$ROOT_HOME"

echo
echo "=== Root SSH directory ==="
"${ADB[@]}" shell "ls -ld '$ROOT_SSH_DIR'"

echo
echo "=== authorized_keys ==="
"${ADB[@]}" shell "
    if [ -f '$ROOT_SSH_DIR/authorized_keys' ]; then
        ls -l '$ROOT_SSH_DIR/authorized_keys'
    else
        echo 'authorized_keys not present yet.'
    fi
"

echo
echo "=== Dropbear binary ==="
"${ADB[@]}" shell "ls -l '$DROPBEAR_REMOTE'"

echo
echo "=== Dropbear launcher ==="
"${ADB[@]}" shell "ls -l '$DROPBEAR_START'"

echo
echo "=== Host keys ==="
"${ADB[@]}" shell "ls -l '$DROPBEAR_DIR'/dropbear_*_host_key"

echo
echo "=== Autorun backup ==="
"${ADB[@]}" shell "ls -l '$AUTORUN_BACKUP'"

echo
echo "=== Autorun Dropbear hook ==="
"${ADB[@]}" shell "
    grep -n -A12 -B2 'DROPBEAR SSH SERVER' '$AUTORUN'
"

echo
echo "=== Current Dropbear processes ==="
"${ADB[@]}" shell "ps | grep '[d]ropbear' || true"

echo
echo "=== Current SSH port ==="
"${ADB[@]}" shell "
    busyboxx netstat -tunlp 2>/dev/null |
    grep ':$SSH_PORT' || true
"

echo
echo "============================================================"
echo "Dropbear installation is finished. Please reboot"
echo "============================================================"
echo