# Changelog

All notable user-facing changes to Di2 Field. Version numbers match
`manifest.xml`. Text here is English on purpose — it feeds the Connect IQ
Store "What's New" field.

## 0.0.23

### Fixed
- Faster recovery from a failed weak-signal connect: when a connection attempt
  drops before it goes live (a brief advertisement from a Di2 that is far away
  or only half-awake), the field now resumes scanning immediately instead of
  waiting out a back-off, so it has more chances to catch the next wake blip.
  (A fully asleep Di2 still has to be woken with a shifter tap.)

## 0.0.22 (beta, diagnostic)

### Debug
- Notify logging is now throttled like scan logging: a packet is written only
  when the rear gear byte changes or once every ~30 s. Previously every notify
  (tens per second) flooded the 5 KB device log with identical packets and
  pushed the connect/reconnect/stranger events out of the window.

## 0.0.21

### Fixed
- Automatic reconnect now actually works between rides: the field no longer
  drops the Bluetooth pairing when it stops, so it relinks to your Di2 on its
  own as soon as the unit is awake — no need to put the Di2 back into pairing
  mode. (If the Di2 has been asleep for a long time, just wake it by tapping a
  shifter and the field reconnects.)
- Sticky-lock is now reliable: because the unit's name is not present in the
  Bluetooth advertisement, the field verifies the unit's identity right after
  connecting and drops a different Di2 if it isn't your paired one. Your lock no
  longer silently jumps to another nearby unit.

### Changed
- While connecting, the status screen shows an elapsed-seconds counter under
  "Connecting" so a weak-signal link (which can take ~15+ seconds) clearly looks
  like progress, not a freeze.

## 0.0.20 (beta, diagnostic)

### Debug
- Scan logging is now throttled: a `scan:` line is written only when the Di2
  candidate count changes (e.g. 0→1 when the unit wakes) or once every ~30 s as
  a heartbeat. Previously every `onScanResults` callback was logged (tens per
  second), flooding the 5 KB device log and rolling the interesting wake moment
  out of the window before it could be captured.

## 0.0.19 (beta, diagnostic)

### Debug
- Sideload test build of the keep-pair reconnect change plus the timestamped
  `Di2Log` logger. Version bumped so the build is distinguishable on-device
  (Connect IQ → app info). Same diagnostic channel as 0.0.18
  (`build-diag.sh` → `DI2DIAG.prg`, log in `GARMIN/APPS/LOGS/DI2DIAG.TXT`).

## 0.0.18 (beta, diagnostic)

### Debug
- Diagnostic sideload build (`build-diag.sh` → `Di2App-<ver>-diag.prg`): BLE is
  forced on in a debug build so `System.println` is written to the on-device log
  `GARMIN/APPS/LOGS/*.TXT`. Lets us capture scan results and confirm whether the
  Di2 re-advertises after a wake without manual pairing. Source tree stays clean
  (the script patches a temp copy and reverts).

## 0.0.17 (beta)

### Changed
- The field no longer drops the BLE pairing when it stops. Keeping the bond
  gives the BLE stack a chance to reconnect on its own once the Di2 shows up
  on air again — so you should not have to put the Di2 back into pairing mode
  every ride. (Under evaluation; depends on Di2 advertising behavior.)

### Debug
- Diagnostic build: raw notify bytes and scan results are written to
  `/GARMIN/APPS/LOGS/Di2Field.txt` to confirm whether the Di2 re-advertises
  after a wake without manual pairing.

## 0.0.16

### Added
- Connection phases with a live status screen while linking up — "Searching…"
  / "Connecting…" with a "Wake the Di2" hint — instead of a blank "---".
- Sticky-lock: the field remembers your Di2 and reconnects to that same unit
  automatically on every ride.
- "Forget paired Di2" setting — a one-shot switch that releases the current
  unit and pairs with the nearest one on the next scan (for a different bike).
- Color-coded connection status dot: blue = searching, yellow = connecting,
  green = connected, dark blue = connected to your paired Di2, orange =
  reconnecting.

### Fixed
- Status dot alignment: now centered on the "Di2" label in every data-field
  layout (full, half, third, quarter), including the larger pulsing dot shown
  while searching.

### Docs
- Store description now explains how to connect, how to switch bikes with
  Forget, and what each dot color means.

## 0.0.12

- Top rear sprockets in the ride summary are reported in teeth instead of an
  index number.

## 0.0.11

- Fixed an out-of-memory crash by fitting the FIT session fields within the
  32-byte limit.

## 0.0.10

- Ride summary recorded to the activity: average & maximum gear ratio, front &
  rear shift counts, most-used gear combo with time share, top-3 most-used rear
  sprockets, highest rear gear, lowest D-Fly battery.

## 0.0.1 – 0.0.9

- Initial development: Shimano Di2 rear/front gear and D-Fly battery over BLE,
  configurable drivetrain (chainrings, cassette, teeth), per-second FIT logging
  of gears/teeth/ratio/battery, day-night theme, and six languages (English,
  French, Spanish, Russian, German, Arabic).
