# digital-ham

Notes, configuration files, and helper scripts for working digital modes in amateur radio.

The focus is on Linux-based setups built around sound-card modems and CAT control —
getting a radio, a computer, and the AX.25 stack talking to each other reliably,
and writing down what actually worked so it doesn't have to be rediscovered.

## Contents

| Folder | What's in it |
| --- | --- |
| [`direwolf-ax25/`](direwolf-ax25/) | Dire Wolf + Hamlib + Linux AX.25 packet setup for the Icom IC-7100: setup guides for Fedora and Ubuntu, a working `direwolf.conf`, and startup scripts |

## General approach

- One USB cable to the radio for both audio (sound-card modem) and CI-V/CAT control
- [Dire Wolf](https://github.com/wb2osz/direwolf) as the software TNC
- [Hamlib](https://hamlib.github.io/) (`rigctld`) for frequency control and DATA PTT
- Kernel AX.25 (`kissattach`/`mkiss`) or KISS-over-TCP for connected-mode packet and BPQ

Configs here reference the station callsign W2QS. If you adapt them, replace the
callsign, beacon position, and serial-device paths with your own.
