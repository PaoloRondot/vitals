# Vitals

<img src="Resources/AppIcon-1024.png" width="128" align="right" alt="Vitals icon">

A tiny iStat Menus–style system monitor for the macOS menu bar. Shows CPU
temperature, CPU load, and RAM in the bar (e.g. `53° 22% 27G`); click for a
popover with sparkline history, per-metric detail, swap, network throughput,
fan RPM, and power draw.

Built with Swift + SwiftUI `MenuBarExtra`. No dependencies, no Xcode project —
just Swift Package Manager.

## How it reads the hardware

| Metric | Source |
|---|---|
| CPU load | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` tick deltas |
| CPU temperature | AppleVendor HID temperature sensors (`PMU tdie*`) via `IOHIDEventSystemClient` (private IOKit API, C shim in `Sources/SensorShims`) |
| CPU frequency | IOReport "CPU Complex Performance States" residencies weighted by the pmgr `voltage-states*-sram` frequency tables |
| Top processes | `/bin/ps` (sampled only while the popover is open) |
| RAM | `host_statistics64` (anonymous + wired + compressed pages) |
| Swap | `sysctl vm.swapusage` |
| Network | `getifaddrs` byte-counter deltas over `en*` interfaces |
| Fans / power | AppleSMC user client (`FNum`/`F*Ac`, `PSTR`) |
| Fan control | SMC writes (`F*Md`/`F*Tg`), clamped to `F0Mn`–`F0Mx`; runs the app's own binary as root via an admin prompt. Hidden on chips without `F0Md` (e.g. M5), whose firmware overrides target writes |
| GPU | IOReport "GPU Performance States" residencies + pmgr `voltage-states9-sram` |
| Battery | `AppleSmartBattery` registry (percent, watts, health, cycles, temperature) |
| Disk | `IOBlockStorageDriver` statistics deltas + FileManager volume capacities |
| Notifications | UserNotifications on critical transitions (temp, memory pressure, offline), 10 min cooldown |
| Connection quality | TCP connect latency to 1.1.1.1 every ~10 s |
| Memory pressure | `sysctl kern.memorystatus_vm_pressure_level` (drives the RAM color coding) |

No sudo, entitlements, or permission prompts needed.

## Build & run

```sh
swift run Vitals                 # dev run (menu bar item, no bundle)
./scripts/bundle.sh              # release build -> dist/Vitals.app
./scripts/bundle.sh --install    # ...and install to /Applications + launch
```

Debugging the sensors without the GUI:

```sh
VITALS_DEBUG=1 swift run Vitals --sample   # dump all sensors + one snapshot
```

## Notes

- Launch at Login (toggle in the popover) requires running the bundled app,
  and macOS ties the registration to the signed binary — after rebuilding,
  re-toggle it.
- The app is ad-hoc signed; fine for personal use on this machine.
