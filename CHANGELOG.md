# Changelog

All notable user-facing changes to Di2 Field. Version numbers match
`manifest.xml`. Text here is English on purpose — it feeds the Connect IQ
Store "What's New" field.

## 0.0.26

### Added
- Gear display options in the field settings: show the rear gear as numbers
  (default), as a graphic, or both. The graphic draws the cassette as a row of
  bars — one per sprocket, height following the cog sizes — with the current
  sprocket highlighted, so you can read your position at a glance.

## 0.0.25

### Added
- Battery display options in the field settings: show the D-Fly charge as a
  percentage (default), a colour-coded battery icon, or both. The icon fills in
  proportion to the charge and turns orange below 40% and red below 15%.

## 0.0.24

Connection reliability overhaul (consolidates the 0.0.17–0.0.23 beta builds).

### Fixed
- Automatic reconnect between rides: the field no longer drops the Bluetooth
  pairing when it stops, so it relinks to your Di2 on its own as soon as the
  unit is awake — no need to re-pair after a short break.
- Reliable sticky-lock: the Di2 name is not present in the Bluetooth
  advertisement, so the field now verifies the unit's identity right after
  connecting and drops a different Di2 if it isn't your paired one. Your lock no
  longer silently jumps to another nearby unit.
- Faster recovery on a weak signal: when a connect attempt drops before it goes
  live (a brief advertisement from a far-away or half-awake Di2), the field
  resumes scanning immediately instead of waiting out a back-off.

### Changed
- While connecting, the status screen shows an elapsed-seconds counter under
  "Connecting", so a weak-signal link (which can take 15+ seconds) clearly looks
  like progress rather than a freeze.

### Added
- After about a minute of unsuccessful searching the hint changes from
  "Wake the Di2" to "Hold Di2 button" — a reminder that a Di2 left asleep for a
  long time stops broadcasting entirely and has to be put back into pairing
  mode. (Confirmed by device logs: after deep sleep, tapping shifters and
  pedalling does not restart the D-Fly's Bluetooth advertising; only the pairing
  button does. This is a Shimano firmware limitation and cannot be worked around
  in software.)

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
