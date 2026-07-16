# bed-mode

Toggle in the battery popout (hover the battery in the topbar) for using the
laptop somewhere airflow is restricted, e.g. in bed. Keeps the power profile
at Balanced but swaps in an aggressive fan curve (up to EC-unregulated
"disengaged" full speed) and disables CPU boost — bursty light load boosting
single cores to ~4.75GHz is what overheats a blocked intake even at low
overall usage. Base clocks are untouched.

## How it's wired

The shell (`services/BedMode.qml`) never touches hardware directly — it only
writes `0`/`1` to `~/.local/state/caelestia/bed-mode`, a file it owns. A
root-owned systemd path unit watches that file and drives everything else:

```
Battery popout switch
  -> services/BedMode.qml writes ~/.local/state/caelestia/bed-mode
  -> bed-mode-sync.path (root, inotify) triggers bed-mode-sync.service
  -> bed-mode-sync (root) starts/stops thinkfan-bed.service
  -> thinkfan-bed.service runs thinkfan against thinkfan-bed.yaml,
     driving the EC fan via thinkpad_acpi
```

Stopping `thinkfan-bed.service` hands the fan back to the EC's own automatic
curve (i.e. whatever `power-profiles-daemon` has it set to), so bed-mode off
== today's default behaviour.

## One-time setup (requires root)

The shell-side toggle works out of the box; the fan curve behind it needs
root, once:

```sh
paru -S thinkfan   # AUR, not in the official repos
sudo ./install.sh
```

`install.sh` installs the modprobe option, the sensitive curve, and the
systemd units, then prints the last step: `thinkpad_acpi` needs
`fan_control=1` to accept manual fan levels, which only takes effect after a
reboot (or a live `modprobe -r thinkpad_acpi && modprobe thinkpad_acpi`).

## Tuning the curve

`thinkfan-bed.yaml` reads CPU temp (`k10temp`/Tctl) and maps it to fan levels
0-7 via `/proc/acpi/ibm/fan`. Each `[level, lower, upper]` entry drops back a
level below `lower` and steps up past `upper`; edit the numbers and
`systemctl restart thinkfan-bed.service` (only takes effect while bed-mode
is on) to try a different curve. See `man thinkfan.conf`.
