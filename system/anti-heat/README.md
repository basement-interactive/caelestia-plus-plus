# Anti-Heat mode

Cooler laptop at the SAME performance. Two levers, neither throttles:

1. **Curve Optimizer undervolt** — `ryzenadj --set-coall=-10`. The SMU runs
   identical clocks at a lower voltage point on the V/F curve, so the package
   dissipates fewer watts for the same work. Re-applied every 30s because
   suspend/EC events reset the curve. (This is the AMD analogue of the Intel
   MSR temp-target tricks floating around for older ThinkPads; on Rembrandt
   the voltage curve is the knob that gives heat back without costing speed.)
2. **Early fan curve** — `/etc/thinkfan-cool.yaml`. The EC's automatic curve
   waits until ~75-80C before really moving air; this one starts a whisper
   level at 40C so heat never accumulates. Level 7 only from 70C — much
   quieter than bed-mode. Yields to the bed/max curves via `Conflicts=` and
   is re-acquired by the applier loop once they stop.

## Architecture (bed-mode/max-perf pattern)

`services/AntiHeat.qml` writes `~/.local/state/caelestia/anti-heat`
→ root `anti-heat-sync.path` (inotify) → `anti-heat-sync`
→ starts/stops `anti-heat.service` (30s applier loop, `ExecStopPost` resets
the offset to 0) and `thinkfan-cool.service`.

One-time root setup: `sudo ./install.sh` (needs `ryzen_smu` for ryzenadj —
see max-perf's README for the CachyOS IO_STRICT_DEVMEM story).

## Tuning

- Offset lives in `CO_OFFSET` at the top of `anti-heat-apply` (installed at
  `/usr/local/bin/anti-heat-apply`). Typical Rembrandt headroom is -15..-30;
  -10 is deliberately conservative. Step by -5 and live with each step for
  days: undervolt instability appears at LIGHT load, not under stress.
- Verify the offset took: `journalctl -u anti-heat.service` logs
  "curve optimizer offset applied" once per transition, and loudly when
  ryzenadj fails.
- Watch package power: `cat /sys/class/hwmon/*/power1_input` on the hwmon
  whose name is `amdgpu` (label PPT) — same load should read lower W with
  the mode on.

## Interactions

- Coexists with max-perf and bed-mode (the undervolt HELPS max-perf: more
  thermal headroom before the 95C Tctl target). Only the fan is arbitrated:
  bed/max curves win while active; cool curve returns automatically after.
