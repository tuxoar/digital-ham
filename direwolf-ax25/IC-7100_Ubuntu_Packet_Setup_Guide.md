# IC-7100 Packet Radio on Ubuntu Linux

**USB audio + Hamlib CAT/Data PTT + Dire Wolf + Linux AX.25**

Ubuntu adaptation of the working Fedora 2 m APRS/packet configuration. Radio settings, Hamlib model, CI-V values, Dire Wolf config, and the KISS/PTY bridge are the same. Package names, kernel modules, audio stack, and a few permission details differ.

This guide targets **Ubuntu 22.04 LTS** and **24.04 LTS**. Newer Ubuntu kernels may no longer ship in-tree AX.25 modules; see [section 2](#2-install-packages).

---

## 1. What this setup does

The IC-7100 is connected to Ubuntu over one USB cable. The USB connection exposes:

- A USB audio codec
- Two serial interfaces
- CI-V/CAT control
- USB TX/RX audio

Dire Wolf uses the USB audio device as a 1200-baud AFSK modem. Hamlib controls the radio over CI-V and, critically for this radio, uses **DATA PTT** rather than ordinary microphone PTT.

Linux AX.25 can then be attached to Dire Wolf through KISS for connected-mode packet.

Useful frequencies:

- **145.070 MHz** — example 2 m connected-mode packet frequency
- **144.390 MHz** — standard APRS frequency in North America

Known working IC-7100 values:

- CI-V address: `88h` / `0x88`
- Hamlib model: `3070`
- CI-V baud: `19200`

---

## 2. Install packages

Ham radio packages live in the **universe** repository. Enable it if it is not already on:

```bash
sudo add-apt-repository universe
sudo apt update
```

Install the user-space tools:

```bash
sudo apt install direwolf libhamlib-utils ax25-tools ax25-apps
sudo apt install alsa-utils psmisc lsof
```

Ubuntu package names that differ from Fedora:

| Role | Fedora | Ubuntu |
| --- | --- | --- |
| Dire Wolf | `direwolf` | `direwolf` |
| Hamlib (`rigctl` / `rigctld`) | `hamlib` | `libhamlib-utils` |
| AX.25 tools (`kissattach`, `mkiss`) | `ax25-tools` | `ax25-tools` |
| AX.25 apps (`axcall`) | `ax25-apps` | `ax25-apps` |
| Extra kernel modules | `kernel-modules-extra-$(uname -r)` | `linux-modules-extra-$(uname -r)` |

Install matching extra kernel modules if your kernel still ships them as a separate package:

```bash
sudo apt install linux-modules-extra-$(uname -r)
```

On some newer Ubuntu kernels that package no longer exists, and the modules are either in the default `linux-modules` package or have been removed upstream. Always verify the load:

```bash
sudo modprobe ax25
sudo modprobe mkiss
lsmod | grep -E 'ax25|mkiss'
```

If `modprobe` reports that the module is not found, this kernel does not provide in-tree AX.25. APRS and Dire Wolf still work without kernel AX.25; connected-mode `axcall` / `ax0` will not.

Install Dire Wolf from **apt**, not from a Snap. Snap confinement often blocks USB audio and serial devices.

`kissattach` and `mkiss` are typically in `/usr/sbin`. If a command is not found as your normal user, call it with the full path, for example `/usr/sbin/kissattach`.

---

## 3. Identify the IC-7100 USB devices

### 3.1 USB audio

Run:

```bash
lsusb
aplay -l
arecord -l
cat /proc/asound/cards
```

The IC-7100 USB audio side appears as a Texas Instruments PCM2903-series USB audio codec.

In the working setup:

```text
card 0: CODEC [USB AUDIO CODEC], device 0
```

So Dire Wolf used:

```text
ADEVICE plughw:0,0
```

Do not assume the IC-7100 will always remain ALSA card 0. Re-run `aplay -l` / `arecord -l` after hardware changes.

A more stable form, if ALSA shows the card name `CODEC`, is:

```text
ADEVICE plughw:CODEC,0
```

Ubuntu desktop systems usually run **PipeWire** (24.04) or **PulseAudio** (many 22.04 installs). Either can claim the USB codec and make `plughw` fail or glitch. If Dire Wolf cannot open the device, see [USB audio claimed by PipeWire or PulseAudio](#usb-audio-claimed-by-pipewire-or-pulseaudio).

---

### 3.2 Serial ports: do not trust ttyUSB numbers

Run:

```bash
ls -l /dev/serial/by-id/
ls -l /dev/ttyUSB*
```

The working IC-7100 exposed:

```text
...IC-7100_02014042_A-if00-port0 -> ../../ttyUSB0
...IC-7100_02014042_B-if00-port0 -> ../../ttyUSB3
```

The important part is the **A** and **B** identity, not the current `ttyUSB` number.

Use the stable by-id path for CAT:

```text
/dev/serial/by-id/usb-Silicon_Labs_CP2102_USB_to_UART_Bridge_Controller_IC-7100_02014042_A-if00-port0
```

The **A port** is the correct CI-V/CAT interface for this setup.

---

### 3.3 If multiple radios are attached

If you are unsure which serial ports belong to the IC-7100:

```bash
ls -l /dev/serial/by-id/
```

Unplug only the IC-7100, run it again, reconnect the IC-7100, and run it again.

The newly appearing entries belong to the IC-7100.

This is much safer than assuming `/dev/ttyUSB0` or `/dev/ttyUSB1`.

---

## 4. Linux permissions

Check:

```bash
groups
ls -l /dev/ttyUSB*
```

Your user should be in the `dialout` group for the CAT serial ports, and in the `audio` group for raw ALSA access.

If necessary:

```bash
sudo usermod -aG dialout,audio "$USER"
```

Then log out and back in. `newgrp dialout` is not a substitute for a full session restart if you also added `audio`.

If direct `rigctl` can open the by-id serial device and read the frequency, serial permissions are good.

---

## 5. IC-7100 radio settings

On the IC-7100:

- Use **FM-D / DATA mode**
- Use simplex
- Disable repeater offset
- Disable CTCSS/tone unless specifically required
- Disable speech compression
- Set CI-V address to `88h`
- Set CI-V baud to `19200`
- Set DATA modulation source to **USB**
- Start USB modulation level conservatively and adjust only if necessary

For K1YMI testing:

```text
145.070 MHz
```

For APRS testing:

```text
144.390 MHz
```

---

## 6. Prove CI-V works before starting Dire Wolf

Check the Hamlib model:

```bash
rigctl -l | grep -i 7100
```

Expected:

```text
3070  Icom  IC-7100
```

Then query the radio directly:

```bash
rigctl -m 3070 \
  -r /dev/serial/by-id/usb-Silicon_Labs_CP2102_USB_to_UART_Bridge_Controller_IC-7100_02014042_A-if00-port0 \
  -s 19200 \
  -c 0x88 \
  f
```

On 145.070 MHz, expected output:

```text
145070000
```

For detailed debugging:

```bash
rigctl -vvvv -m 3070 \
  -r /dev/serial/by-id/usb-Silicon_Labs_CP2102_USB_to_UART_Bridge_Controller_IC-7100_02014042_A-if00-port0 \
  -s 19200 \
  -c 0x88 \
  f
```

A successful trace shows:

- Serial device opens
- CI-V request is transmitted
- IC-7100 responds
- Final frequency is printed

A communication timeout usually means:

- Wrong serial device
- Wrong baud
- Wrong CI-V address
- Another process already owns the port
- Radio-side CI-V configuration issue

---

## 7. Start rigctld

Use:

```bash
rigctld -m 3070 \
  -r /dev/serial/by-id/usb-Silicon_Labs_CP2102_USB_to_UART_Bridge_Controller_IC-7100_02014042_A-if00-port0 \
  -s 19200 \
  -c 0x88 \
  -T 127.0.0.1
```

Do **not** force `-P RIG` in this working configuration.

From another terminal:

```bash
rigctl -m 2 -r 127.0.0.1:4532 f
```

Expected:

```text
145070000
```

### Test DATA PTT

Key the radio:

```bash
rigctl -m 2 -r 127.0.0.1:4532 T 3
```

Release:

```bash
rigctl -m 2 -r 127.0.0.1:4532 T 0
```

Important:

- `T 1` did **not** key the working data path
- `T 3` **did**
- `T 0` releases PTT

If `T 3` works, the CAT/PTT layer is ready.

---

## 8. Dire Wolf configuration

Example `~/direwolf.conf`:

```text
ADEVICE plughw:0,0
ACHANNELS 1

CHANNEL 0
MYCALL W2QS-7

MODEM 1200

PTT RIG 2 127.0.0.1:4532

TXDELAY 40
TXTAIL 5
PERSIST 63
SLOTTIME 10

AGWPORT 8000
KISSPORT 8001
```

If the ALSA card number moves around, prefer the card name:

```text
ADEVICE plughw:CODEC,0
```

Start `rigctld` first.

Then:

```bash
direwolf -t 0 -p -c ~/direwolf.conf
```

The `-p` option creates a virtual KISS pseudo-terminal and a symlink:

```text
/tmp/kisstnc -> /dev/pts/X
```

The PTY number changes whenever Dire Wolf restarts.

If Dire Wolf prints:

```text
Retrying Hamlib Rig open...
```

stop and fix `rigctld` before continuing.

If Dire Wolf cannot open the audio device, see [USB audio claimed by PipeWire or PulseAudio](#usb-audio-claimed-by-pipewire-or-pulseaudio).

---

## 9. Quick Dire Wolf PTT test

Before AX.25, force a PTT-only test:

```bash
direwolf -t 0 -c ~/direwolf.conf -x p
```

The IC-7100 should key.

Press `Ctrl+C` afterward.

This confirms:

```text
Dire Wolf -> Hamlib -> IC-7100 DATA PTT
```

---

## 10. APRS sanity test

APRS is an excellent end-to-end sanity test because it proves:

- USB TX audio
- Dire Wolf AFSK generation
- DATA PTT
- RF output
- Antenna/feedline
- Over-the-air decodability

Tune:

```text
144.390 MHz FM-D
```

Example Dire Wolf beacon pattern:

```text
PBEACON delay=1 every=2 overlay=S symbol=">" \
  lat=43^04.00N long=075^30.00W \
  via=WIDE1-1,WIDE2-1 \
  comment="W2QS-7 IC-7100 Dire Wolf test"
```

Replace the coordinates with your own appropriate position.

If an APRS digipeater/iGate receives the packet, your transmit chain is working.

In the original setup, APRS worked successfully.

---

## 11. Linux AX.25 setup

Create the AX.25 configuration directory:

```bash
sudo mkdir -p /etc/ax25
```

Edit:

```bash
sudo nano /etc/ax25/axports
```

Example entry:

```text
radio W2QS-7 0 255 2 IC-7100 145.070 Packet
```

Load kernel support:

```bash
sudo modprobe ax25
sudo modprobe mkiss
```

---

## 12. PTY/KISS workaround

On this stack, directly running:

```bash
sudo kissattach /tmp/kisstnc radio
```

failed because Dire Wolf's PTY was created as a user-owned `/dev/pts/X` device.

Running `kissattach` without sudo then failed with:

```text
TIOCSETD: Operation not permitted
```

The same failure occurs on Ubuntu. Setting the AX.25 line discipline needs privileges; opening Dire Wolf's user-owned PTY as root often fails on modern `devpts`. The working solution is a **two-PTY bridge**.

### Step 1: Start Dire Wolf

```bash
direwolf -t 0 -p -c ~/direwolf.conf
```

Example:

```text
Virtual KISS TNC is available on /dev/pts/7
Created symlink /tmp/kisstnc -> /dev/pts/7
```

### Step 2: Start kissattach against `/dev/ptmx`

```bash
sudo kissattach /dev/ptmx radio
```

If `kissattach` is not in your PATH:

```bash
sudo /usr/sbin/kissattach /dev/ptmx radio
```

Example output:

```text
AX.25 port radio bound to device ax0
Awaiting client connects on
/dev/pts/6
```

Keep this process running.

### Step 3: Fix ownership of the kissattach PTY

Replace `/dev/pts/6` with whatever `kissattach` printed:

```bash
sudo chown "$USER":tty /dev/pts/6
sudo chmod 600 /dev/pts/6
```

### Step 4: Bridge Dire Wolf to kissattach

Run as your normal user:

```bash
mkiss /tmp/kisstnc /dev/pts/6
```

Or:

```bash
/usr/sbin/mkiss /tmp/kisstnc /dev/pts/6
```

Keep `mkiss` running.

The final chain is:

```text
Dire Wolf
   |
   +-- /tmp/kisstnc
           |
         mkiss
           |
      /dev/pts/X
           |
      kissattach
           |
          ax0
           |
        axcall
```

---

## 13. Verify AX.25

Check:

```bash
ip link show ax0
```

A healthy interface looks similar to:

```text
ax0: <BROADCAST,UP,LOWER_UP>
link/ax25 W2QS-7
```

Check active sessions:

```bash
cat /proc/net/ax25
```

An empty file is normal when there are no active AX.25 connections.

---

## 14. Connect to a packet station

Example:

```bash
axcall radio K1YMI-4
```

`axcall` can look like it is hanging while waiting for the remote UA response.

Watch the Dire Wolf console.

If Dire Wolf shows an outgoing AX.25 SABM/connect frame and the IC-7100 keys, then:

- Linux AX.25 is working
- KISS is working
- Dire Wolf is receiving the AX.25 frame
- Radio PTT is working

If there is no response, investigate:

- Remote station availability
- RF path
- Exact SSID
- Frequency
- Receive path

---

## 15. Recommended startup order

1. Connect and power on the IC-7100.
2. Confirm `/dev/serial/by-id/` contains the IC-7100 A and B ports.
3. Verify direct `rigctl` frequency query.
4. Start `rigctld`.
5. Verify `rigctld` frequency query.
6. Verify DATA PTT with `T 3` and `T 0`.
7. Start Dire Wolf with `-p`.
8. Start `kissattach /dev/ptmx radio`.
9. Note the PTY printed by `kissattach`.
10. `chown`/`chmod` that PTY.
11. Run `mkiss /tmp/kisstnc /dev/pts/X`.
12. Verify `ax0`.
13. Run `axcall`.

---

## 16. Troubleshooting

### No frequency from rigctl

Use the **IC-7100 A by-id device**, not a guessed `ttyUSB` number.

Check:

```text
CI-V Address = 88h
CI-V Baud    = 19200
```

Check for stale processes:

```bash
pkill rigctld
sudo fuser -v /dev/ttyUSB0
sudo lsof /dev/ttyUSB0
```

Use verbose mode:

```bash
rigctl -vvvv ...
```

---

### Frequency works, PTT does not

Use DATA PTT:

```bash
rigctl -m 2 -r 127.0.0.1:4532 T 3
```

Release:

```bash
rigctl -m 2 -r 127.0.0.1:4532 T 0
```

Do not assume `T 1` will work.

Also verify:

```bash
direwolf -t 0 -c ~/direwolf.conf -x p
```

---

### Dire Wolf says `Retrying Hamlib Rig open...`

Start `rigctld` first.

Verify:

```bash
rigctl -m 2 -r 127.0.0.1:4532 f
```

works before restarting Dire Wolf.

---

### USB audio claimed by PipeWire or PulseAudio

If Dire Wolf reports that it cannot open `plughw:0,0` or the card number keeps changing:

```bash
aplay -l
arecord -l
pactl info
```

Identify what holds the USB codec:

```bash
sudo fuser -v /dev/snd/*
sudo lsof /dev/snd/* 2>/dev/null
```

Prefer the ALSA card name in `direwolf.conf`:

```text
ADEVICE plughw:CODEC,0
```

On PulseAudio (typical Ubuntu 22.04):

```bash
pasuspender -- direwolf -t 0 -p -c ~/direwolf.conf
```

On PipeWire (typical Ubuntu 24.04), temporarily stop the user session only if you need exclusive ALSA access:

```bash
systemctl --user stop pipewire pipewire-pulse wireplumber
```

Start it again afterward:

```bash
systemctl --user start pipewire pipewire-pulse wireplumber
```

Do not leave PipeWire stopped if you still need desktop audio.

---

### `kissattach` says permission denied

Do not rely on:

```bash
sudo kissattach /tmp/kisstnc radio
```

Use the `/dev/ptmx` + `mkiss` bridge instead.

---

### `mkiss` or `kissattach` is not found

They live in `/usr/sbin` and may be missing from a non-root PATH:

```bash
sudo /usr/sbin/kissattach /dev/ptmx radio
/usr/sbin/mkiss /tmp/kisstnc /dev/pts/X
```

---

### `mkiss` says permission denied

Make sure the PTY printed by `kissattach` belongs to your user:

```bash
sudo chown "$USER":tty /dev/pts/X
sudo chmod 600 /dev/pts/X
```

Then run `mkiss` **without sudo**:

```bash
mkiss /tmp/kisstnc /dev/pts/X
```

If needed, inspect:

```bash
ls -l /dev/pts/X
aa-status
```

Ubuntu uses AppArmor, not SELinux. A serial or audio denial is uncommon for this stack, but worth checking if a profile is in enforce mode and blocking `rigctld` or Dire Wolf.

---

### `modprobe ax25` fails

Confirm extra modules for this exact kernel:

```bash
uname -r
apt list --installed 'linux-modules-extra-*'
modinfo ax25
modinfo mkiss
```

If the modules are absent, kernel AX.25 (`ax0`, `kissattach`, `axcall`) is not available on that kernel. Dire Wolf APRS and KISS-over-TCP still work.

---

### `axcall` sends but never connects

First prove APRS works.

If APRS works, your local transmit chain is probably healthy.

Then:

- Watch Dire Wolf for outgoing AX.25 frames
- Listen for/decode the remote station
- Confirm frequency and SSID
- Confirm remote service availability
- Only then tune TX timing or deviation

---

## 17. Useful discovery commands

```bash
# USB devices
lsusb

# Audio
aplay -l
arecord -l
cat /proc/asound/cards

# What holds the USB codec
sudo fuser -v /dev/snd/*
pactl info

# Stable serial identity
ls -l /dev/serial/by-id/

# Resolve the current ttyUSB target
readlink -f /dev/serial/by-id/*IC-7100*A*

# Serial permissions
ls -l /dev/ttyUSB*
groups

# Find a process using the CAT port
sudo fuser -v /dev/ttyUSB0
sudo lsof /dev/ttyUSB0

# Packet kernel modules
lsmod | grep -E 'ax25|mkiss'
modinfo ax25
modinfo mkiss

# AX.25 interface
ip link show ax0

# Active AX.25 sessions
cat /proc/net/ax25
```

---

## 18. Working architecture

```text
IC-7100
   |
   +-- USB audio (PCM2903) ---> Dire Wolf 1200 AFSK
   |
   +-- IC-7100 A serial -----> rigctld / Hamlib
                                 |
                                 +-- frequency/CAT
                                 +-- DATA PTT (T 3)

Dire Wolf
   |
   +-- virtual KISS PTY
           |
         mkiss
           |
      kissattach
           |
          ax0
           |
        axcall
```

---

## 19. Important things to remember

- Use `/dev/serial/by-id/` instead of hard-coding `ttyUSB0`, `ttyUSB2`, etc.
- The IC-7100 **A port** is the CAT/CI-V interface used here.
- Re-check the ALSA card number after hardware changes; card name `plughw:CODEC,0` is more stable.
- Start `rigctld` before Dire Wolf.
- DATA PTT is `T 3`; release is `T 0`.
- Install Hamlib as `libhamlib-utils`, not `hamlib`.
- Install Dire Wolf from apt, not Snap.
- Add your user to both `dialout` and `audio`.
- PipeWire or PulseAudio can claim the USB codec; fix that before chasing radio settings.
- `kissattach` and `mkiss` may need `/usr/sbin/` on the command line.
- Dire Wolf's `/tmp/kisstnc` PTY changes whenever Dire Wolf restarts.
- Rebuild the `kissattach` / `mkiss` bridge after Dire Wolf restarts.
- APRS on 144.390 is a very useful end-to-end sanity test.
- Kernel AX.25 is not guaranteed on every Ubuntu kernel; verify `modprobe ax25` before depending on `axcall`.
