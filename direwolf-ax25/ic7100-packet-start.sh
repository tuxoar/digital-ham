#!/usr/bin/env bash
set -euo pipefail

CALLSIGN="${CALLSIGN:-W2QS-7}"
AXPORT="${AXPORT:-radio}"
DIREWOLF_CONF="${DIREWOLF_CONF:-$HOME/direwolf.conf}"
RIG_PORT="${RIG_PORT:-/dev/serial/by-id/usb-Silicon_Labs_CP2102_USB_to_UART_Bridge_Controller_IC-7100_02014042_A-if00-port0}"
RIG_MODEL="${RIG_MODEL:-3070}"
RIG_BAUD="${RIG_BAUD:-19200}"
CIV_ADDR="${CIV_ADDR:-0x88}"
RIGCTLD_HOST="${RIGCTLD_HOST:-127.0.0.1}"
RIGCTLD_PORT="${RIGCTLD_PORT:-4532}"

RUNDIR="${XDG_RUNTIME_DIR:-/tmp}/ic7100-packet"
mkdir -p "$RUNDIR"

RIG_LOG="$RUNDIR/rigctld.log"
DW_LOG="$RUNDIR/direwolf.log"
KA_LOG="$RUNDIR/kissattach.log"
MK_LOG="$RUNDIR/mkiss.log"

PIDS=()

cleanup() {
    echo
    echo "Stopping packet stack..."
    for pid in "${PIDS[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
    sudo pkill -x kissattach 2>/dev/null || true
    pkill -x mkiss 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "== IC-7100 packet startup =="

for cmd in rigctld rigctl direwolf kissattach mkiss ip; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "ERROR: $cmd is not installed."
        exit 1
    }
done

if [[ ! -e "$RIG_PORT" ]]; then
    echo "ERROR: IC-7100 CAT device not found:"
    echo "  $RIG_PORT"
    echo
    echo "Current serial devices:"
    ls -l /dev/serial/by-id/ 2>/dev/null || true
    exit 1
fi

if [[ ! -f "$DIREWOLF_CONF" ]]; then
    echo "ERROR: Dire Wolf config not found: $DIREWOLF_CONF"
    exit 1
fi

echo "[1/7] Loading AX.25 kernel modules..."
sudo modprobe ax25
sudo modprobe mkiss

echo "[2/7] Cleaning up old packet processes..."
sudo pkill -x kissattach 2>/dev/null || true
pkill -x mkiss 2>/dev/null || true
pkill -x rigctld 2>/dev/null || true
sleep 1

echo "[3/7] Starting rigctld..."
rigctld \
    -m "$RIG_MODEL" \
    -r "$RIG_PORT" \
    -s "$RIG_BAUD" \
    -c "$CIV_ADDR" \
    -T "$RIGCTLD_HOST" \
    -t "$RIGCTLD_PORT" \
    >"$RIG_LOG" 2>&1 &
RIG_PID=$!
PIDS+=("$RIG_PID")

for _ in {1..30}; do
    if rigctl -m 2 -r "$RIGCTLD_HOST:$RIGCTLD_PORT" f >/tmp/ic7100_freq.$$ 2>/dev/null; then
        break
    fi
    sleep 0.2
done

if ! FREQ="$(cat /tmp/ic7100_freq.$$ 2>/dev/null)"; then
    FREQ=""
fi
rm -f /tmp/ic7100_freq.$$

if [[ -z "$FREQ" ]]; then
    echo "ERROR: rigctld started but the IC-7100 did not return a frequency."
    echo "See: $RIG_LOG"
    exit 1
fi

echo "      Radio frequency: $FREQ Hz"

echo "[4/7] Starting Dire Wolf..."
rm -f /tmp/kisstnc
direwolf -t 0 -p -c "$DIREWOLF_CONF" >"$DW_LOG" 2>&1 &
DW_PID=$!
PIDS+=("$DW_PID")

for _ in {1..50}; do
    if [[ -L /tmp/kisstnc ]]; then
        DW_PTY="$(readlink -f /tmp/kisstnc)"
        [[ -e "$DW_PTY" ]] && break
    fi
    sleep 0.2
done

if [[ ! -L /tmp/kisstnc ]]; then
    echo "ERROR: Dire Wolf did not create /tmp/kisstnc."
    echo "See: $DW_LOG"
    exit 1
fi

DW_PTY="$(readlink -f /tmp/kisstnc)"
echo "      Dire Wolf KISS PTY: $DW_PTY"

# Fedora/devpts can prevent root from reopening the user-created PTY.
chmod 666 "$DW_PTY" 2>/dev/null || true

echo "[5/7] Starting kissattach..."
: >"$KA_LOG"
sudo kissattach /dev/ptmx "$AXPORT" >"$KA_LOG" 2>&1 &
KA_PID=$!
PIDS+=("$KA_PID")

KA_PTY=""
for _ in {1..50}; do
    KA_PTY="$(grep -oE '/dev/pts/[0-9]+' "$KA_LOG" | tail -1 || true)"
    [[ -n "$KA_PTY" && -e "$KA_PTY" ]] && break
    sleep 0.2
done

if [[ -z "$KA_PTY" || ! -e "$KA_PTY" ]]; then
    echo "ERROR: Could not determine kissattach PTY."
    echo "kissattach output:"
    cat "$KA_LOG"
    exit 1
fi

echo "      kissattach PTY: $KA_PTY"

echo "[6/7] Bridging Dire Wolf to kernel AX.25..."
sudo chown "$(id -un)":tty "$KA_PTY"
sudo chmod 600 "$KA_PTY"

mkiss /tmp/kisstnc "$KA_PTY" >"$MK_LOG" 2>&1 &
MK_PID=$!
PIDS+=("$MK_PID")
sleep 1

if ! ip link show ax0 >/dev/null 2>&1; then
    echo "ERROR: ax0 was not created."
    echo "kissattach log:"
    cat "$KA_LOG"
    echo "mkiss log:"
    cat "$MK_LOG"
    exit 1
fi

echo "[7/7] AX.25 interface is ready."
ip -brief link show ax0

echo
echo "Packet stack is running."
echo "Connect with:"
echo "  axcall $AXPORT K1YMI-4"
echo
echo "Logs:"
echo "  rigctld:   $RIG_LOG"
echo "  Dire Wolf: $DW_LOG"
echo "  kissattach:$KA_LOG"
echo "  mkiss:     $MK_LOG"
echo
echo "Follow Dire Wolf live with:"
echo "  tail -f $DW_LOG"
echo
echo "Press Ctrl+C here when you want to tear the stack down."

while true; do
    if ! kill -0 "$RIG_PID" 2>/dev/null; then
        echo "ERROR: rigctld exited. See $RIG_LOG"
        exit 1
    fi
    if ! kill -0 "$DW_PID" 2>/dev/null; then
        echo "ERROR: Dire Wolf exited. See $DW_LOG"
        exit 1
    fi
    sleep 2
done
