#!/usr/bin/env bash
# Start the IC-7100 CAT/PTT service and Dire Wolf for a BPQ KISS-over-TCP link.
# BPQ should connect to 127.0.0.1:8001 when it runs on this same machine.

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly DIREWOLF_CONFIG="${DIREWOLF_CONFIG:-${SCRIPT_DIR}/direwolf.conf}"
readonly RIG_MODEL="${RIG_MODEL:-3070}"
readonly RIG_BAUD="${RIG_BAUD:-19200}"
readonly RIG_CIV_ADDRESS="${RIG_CIV_ADDRESS:-0x88}"
readonly RIG_HOST="${RIG_HOST:-127.0.0.1}"
readonly RIG_PORT="${RIG_PORT:-4532}"

rigctld_pid=""

log() {
    printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" >&2
}

cleanup() {
    # Make a best effort to release PTT before stopping CAT control.
    rigctl -m 2 -r "${RIG_HOST}:${RIG_PORT}" T 0 >/dev/null 2>&1 || true
    if [[ -n "${rigctld_pid}" ]]; then
        kill "${rigctld_pid}" >/dev/null 2>&1 || true
        wait "${rigctld_pid}" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM HUP

for command_name in direwolf rigctld rigctl; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        log "ERROR: ${command_name} is not installed or is not in PATH"
        exit 127
    fi
done

if [[ ! -r "${DIREWOLF_CONFIG}" ]]; then
    log "ERROR: cannot read Dire Wolf configuration: ${DIREWOLF_CONFIG}"
    exit 1
fi

rig_device="${RIG_DEVICE:-}"
if [[ -z "${rig_device}" ]]; then
    shopt -s nullglob
    rig_candidates=(/dev/serial/by-id/*IC-7100*_A-if00-port0)
    shopt -u nullglob

    if (( ${#rig_candidates[@]} != 1 )); then
        log "ERROR: expected exactly one IC-7100 A-port, found ${#rig_candidates[@]}"
        log "Set RIG_DEVICE to its stable /dev/serial/by-id/... path"
        exit 1
    fi
    rig_device="${rig_candidates[0]}"
fi

if [[ ! -r "${rig_device}" || ! -w "${rig_device}" ]]; then
    log "ERROR: CAT device is not accessible: ${rig_device}"
    log "The service user normally needs membership in the dialout group"
    exit 1
fi

log "Starting rigctld on ${RIG_HOST}:${RIG_PORT} using ${rig_device}"
rigctld \
    -m "${RIG_MODEL}" \
    -r "${rig_device}" \
    -s "${RIG_BAUD}" \
    -c "${RIG_CIV_ADDRESS}" \
    -T "${RIG_HOST}" \
    -t "${RIG_PORT}" &
rigctld_pid=$!

rig_ready=false
for _attempt in {1..20}; do
    if ! kill -0 "${rigctld_pid}" 2>/dev/null; then
        log "ERROR: rigctld exited before it became ready"
        exit 1
    fi
    if rigctl -m 2 -r "${RIG_HOST}:${RIG_PORT}" f >/dev/null 2>&1; then
        rig_ready=true
        break
    fi
    sleep 0.5
done

if [[ "${rig_ready}" != true ]]; then
    log "ERROR: IC-7100 did not answer through rigctld"
    exit 1
fi

log "CAT/PTT is ready; starting Dire Wolf with KISS TCP for BPQ"
# Foreground operation is intentional: systemd can supervise and restart this script.
direwolf -t 0 -c "${DIREWOLF_CONFIG}"
