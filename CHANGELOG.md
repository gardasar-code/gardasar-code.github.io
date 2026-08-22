# Changelog

All notable user-facing changes to Di2 Field. Version numbers match
`manifest.xml`. Text here is English on purpose — it feeds the Connect IQ
Store "What's New" field.

## 0.0.39

### Fixed
- If the Bluetooth stack refuses to register the gear notification profile, the
  field keeps retrying instead of giving up for the whole ride: without the
  profile the gear service is never found, no matter how often it reconnects.

## 0.0.38

### Fixed
- The gear notification profile is now registered independently of the battery
  one, so a failure to register either of them no longer leaves the field
  without the other.

### Changed
- Diagnostics mode also reports the profile registration result and the list of
  services the Bluetooth stack actually sees on the connected device.

## 0.0.37

### Fixed
- Gears stayed empty on some devices while the connection and the battery
  readout looked healthy: the notification subscription was attempted once,
  immediately after connecting, and could land before the Bluetooth stack had
  finished discovering the services. The subscription is now retried until the
  stack confirms it.

## 0.0.36

### Changed
- The on-screen diagnostics mode now reports the notification subscription
  state, packet counters and the age of the last packet, and dumps every kind
  of packet the Di2 sends instead of only the most recent one — so a photo of
  the screen tells apart "the device is silent", "the subscription was
  rejected" and "the packets look different than expected".

## 0.0.35

### Added
- Front chainring display for 2x/3x drivetrains: a bar graph of the chainrings
  (and a current-ring digit) shown alongside the rear cassette/gear. The active
  front ring lights up once it can be read; until then it shows as a dash.

### Changed
- Reworked the on-screen layout into a header (Di2 status + battery) and a body
  split into front/rear columns with graph and number blocks, so the gears use
  the available space more consistently across display modes.

## 0.0.34

### Added
- Drivetrain presets in the field settings: pick a common Shimano chainring
  setup (e.g. 50-34, 52-36, GRX 48-31) or cassette (10/11/12-speed, 10-51 to
  11-48) instead of entering every tooth count. While a preset is selected it
  sets the gearing; choose Custom to enter the count and teeth by hand.
- Automatic Di2 model detection from the connected device, with profile
  groundwork to support more Di2 series beyond the tested XT M8250.
- Full-screen on-screen diagnostics mode (a setting): a colour-coded stage
  indicator plus scan counts, signal, the detected model and the raw gear
  packet — turn it on and send a photo to report a connection problem.

### Changed
- Clearer setup guidance: the Store description now explains how presets,
  chainring count and teeth fields work together.

### Fixed
- A selected preset reliably drives the displayed gearing and ratios (presets
  override the manual count/teeth fields while selected).

## 0.0.28

### Changed
- The battery and gear display option labels in the field settings are now fully
  translated in all six supported languages (English, French, Russian, Spanish,
  German, Arabic) instead of falling back to English.

### Performance
- Faster BLE handling: the gear and battery characteristic UUIDs are now cached
  as objects instead of being rebuilt from strings on every notification.

## 0.0.27

### Changed
- Cassette graphic polish: largest sprocket on the left, inactive bars use the
  same light shade as the gear separator dot, slightly thicker bars, and proper
  top/bottom padding so the graphic and the numbers never touch the field edge
  on half/quarter layouts.
- The battery icon and the cassette graphic are now shown by default.

## 0.0.26

### Added
- Gear display options in the field settings: show the rear gear as numbers, as
  a graphic, or both (default). The graphic draws the cassette as a row of bars —
  one per sprocket, largest on the left, height following the cog sizes — with
  the current sprocket highlighted, so you can read your position at a glance.

## 0.0.25

### Added
- Battery display options in the field settings: show the D-Fly charge as a
  percentage, a colour-coded battery icon, or both (default). The icon fills in
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
