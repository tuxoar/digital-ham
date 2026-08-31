# direwolf-ax25

Packet radio (1200-baud AFSK / AX.25) on Linux with an Icom IC-7100, using
Dire Wolf as the software TNC and Hamlib for CAT control and DATA PTT.

## Files

- **IC-7100_Fedora_Packet_Setup_Guide.md** — full walkthrough of the working Fedora setup: USB device discovery, CI-V/Hamlib verification, Dire Wolf config, the `/dev/ptmx` + `mkiss` KISS/PTY bridge, and troubleshooting
- **IC-7100_Ubuntu_Packet_Setup_Guide.md** — the same setup adapted for Ubuntu 22.04/24.04 (package names, PipeWire/PulseAudio conflicts, kernel AX.25 availability)
- **direwolf.conf** — working Dire Wolf configuration (USB audio codec, Hamlib PTT via `rigctld`, KISS/AGW ports, APRS beacon)
- **ic7100-packet-start.sh** — interactive script that brings up the full kernel AX.25 stack: `rigctld` → Dire Wolf → `kissattach` → `mkiss` → `ax0`, with cleanup on Ctrl+C
- **direwolf-bpq-start.sh** — leaner startup for a BPQ node: `rigctld` + Dire Wolf with KISS-over-TCP on `127.0.0.1:8001`, suitable for running under systemd

## Quick start

Read the setup guide for your distro first — the scripts assume the radio-side
settings (CI-V address `0x88`, 19200 baud, DATA mode, USB modulation) are already
in place and that your user can access the serial and audio devices.
