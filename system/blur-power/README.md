# Blur power-sync

Frosted glass on AC, flat and cool on battery.

Compositor blur over translucent windows costs ~10 GPU percentage points
while video plays (measured on the 680M: 30.5% -> 20.7% average GPU busy
with blur off) and drives repeated max-clock DPM bursts. On battery that is
heat and runtime for a purely cosmetic effect, so this feature drops blur
the moment the charger is pulled and restores it when plugged back in.

## How it works

- `blur-power-sync` (python, `/usr/local/bin`): reads the AC state from
  `/sys/class/power_supply/*/online` and flips
  `decoration.blur.enabled` live over the Hyprland IPC socket
  (`eval hl.config(...)` — no reload, no flicker).
- `~/.config/hypr/variables.lua` `blurEnabled` stays the single source of
  truth: battery always forces blur off, but AC only re-enables it if the
  user setting says so.
- `90-blur-power.rules` (udev): runs the sync on every power_supply change.
- `execs.lua` runs the sync once at Hyprland startup so a session started
  on battery comes up with blur off.

## Install

    sudo ./install.sh
