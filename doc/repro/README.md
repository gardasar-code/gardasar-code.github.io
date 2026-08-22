# Minimal reproduction — custom BLE service registration crash

A stand-alone Connect IQ **data field** that does nothing but register one custom
128-bit BLE service and draw the result.

* **Edge Explore 2 / FW 30.23** — the field draws `registered`.
* **Edge Explore 2 / FW 31.33** — the field is replaced by the Connect IQ error
  icon; `GARMIN/APPS/LOGS/CIQ_LOG.YML` reports
  `System Error: 'Failed invoking <symbol>'` with `registerProfile` on the stack.

No peripheral is required: the crash happens during registration, before any
scanning or connection.

## Build

```bash
monkeyc -d edgeexplore2 -f monkey.jungle -o repro.prg -y <developer_key>
```

Built with SDK 9.2.0. Copy `repro.prg` to `GARMIN/APPS/` and add the field
"BLE Profile Repro" to a data screen.

## Variants tried, all with the same result

* `WITH_CCCD = true` — characteristic with an explicit `Ble.cccdUuid()` descriptor.
* `WITH_CCCD = false` — characteristic without any descriptor.
* Registering before / after `Ble.setDelegate()`.
* Registering the standard Battery Service (`0000180f-...`) instead — **this one
  succeeds**, which is why the problem looks specific to custom 128-bit UUIDs.
