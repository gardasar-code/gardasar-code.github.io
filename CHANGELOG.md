# Changelog

All notable user-facing changes to Di2 Field. Version numbers match
`manifest.xml`. Text here is English on purpose — it feeds the Connect IQ
Store "What's New" field.

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
