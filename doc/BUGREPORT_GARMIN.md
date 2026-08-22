# Bug report для Garmin Connect IQ

Текст ниже — на английском (внешняя коммуникация), готов к копированию в форум.
Куда и как публиковать — в конце файла.

---

## Title

Edge Explore 2 FW 31.33: `Ble.registerProfile()` with a custom 128-bit service UUID crashes the data field with System Error (regression from FW 30.23)

## Body

**Device:** Edge Explore 2 (Part-Number 006-B4169-00)
**Firmware:** 31.33 — broken. 30.23 — worked.
**Connect IQ version on device:** 6.0.2 (API 6.0.0)
**SDK:** 9.2.0 (2026-06-09)
**App type:** data field
**Permissions:** `BluetoothLowEnergy`, `FitContributor`

### Summary

On firmware 31.33, calling `BluetoothLowEnergy.registerProfile()` with a custom
128-bit service UUID kills the data field from inside the call. The failure is a
`System Error: 'Failed invoking <symbol>'`, which cannot be caught by `try/catch`,
so an application has no way to recover or degrade gracefully.

The same code runs correctly on firmware 30.23 on the same device with the same
peripheral, so this is a regression.

### Profile being registered

```monkeyc
private const MODE_SERVICE_UUID = "000018ef-5348-494d-414e-4f5f424c4500";
private const MODE_CHAR_UUID    = "00002ac1-5348-494d-414e-4f5f424c4500";

Ble.registerProfile({
    :uuid => Ble.stringToUuid(MODE_SERVICE_UUID),
    :characteristics => [
        {
            :uuid => Ble.stringToUuid(MODE_CHAR_UUID),
            :descriptors => [Ble.cccdUuid()]
        }
    ]
});
```

Registering the same profile **without** the explicit CCCD descriptor crashes as well:

```monkeyc
:characteristics => [ { :uuid => Ble.stringToUuid(MODE_CHAR_UUID) } ]
```

### Crash log (GARMIN/APPS/LOGS/CIQ_LOG.YML)

```yaml
Error: System Error
Details: 'Failed invoking <symbol>'
Time: 2026-08-22T12:42:54Z
Part-Number: 006-B4169-00
Firmware-Version: '31.33'
ConnectIQ-Version: 6.0.2
Stack:
  - pc: 0x100028a6
    File: 'Di2BleDelegate.mc'
    Line: 396          # the Ble.registerProfile(...) call itself
    Function: registerModeProfile
  - pc: 0x1000325d
    File: 'Di2BleDelegate.mc'
    Line: 358
    Function: registerProfiles
  - pc: 0x10003682
    File: 'Di2BleDelegate.mc'
    Line: 143
    Function: start
  - pc: 0x1000041a
    File: 'Di2FieldApp.mc'
    Line: 33
    Function: onStart
```

### Standard service registers fine in the same run

Registering the standard Battery Service in the same application succeeds, so
`registerProfile()` itself works — only the custom 128-bit UUID above is fatal:

```
register mode profile skipped after 2 crashes
profile register 180F:ok
services n=1 [0000180F-0000-1000-8000-00805F9B34FB ]
```

### Earlier symptom on the same firmware

Before the call became fatal, an earlier build received an **undocumented
`status = 2`** in `onProfileRegister()` for this profile, while the battery
profile got `STATUS_SUCCESS`:

```
reg=18EF:e2 180F:ok
```

`2` is not among the documented `Status` values (0 SUCCESS, 1 NOT_ENOUGH_RESOURCES,
12 READ_FAIL, 14 WRITE_FAIL, 18/19 authentication/encryption). A similar
undocumented `status = 2` on profile registration was reported for VivoActive 4
and fixed in FW 5.63, so this may be the same defect resurfacing on Edge.

### Minimal reproduction project

A stand-alone data field that only registers the profile and draws the result is
attached (`repro/`, SDK 9.2.0, ~60 lines). No peripheral is needed — the crash
happens during registration, before any scan or connection.

```monkeyc
const SERVICE_UUID = "000018ef-5348-494d-414e-4f5f424c4500";
const CHAR_UUID    = "00002ac1-5348-494d-414e-4f5f424c4500";
const WITH_CCCD    = true;   // false crashes as well

function onStart(state) {
    var d = new ReproDelegate();
    Ble.setDelegate(d);

    var chr = WITH_CCCD
        ? { :uuid => Ble.stringToUuid(CHAR_UUID), :descriptors => [Ble.cccdUuid()] }
        : { :uuid => Ble.stringToUuid(CHAR_UUID) };
    try {
        // FW 31.33: the application dies here. No exception is delivered.
        Ble.registerProfile({
            :uuid => Ble.stringToUuid(SERVICE_UUID),
            :characteristics => [chr]
        });
    } catch (e) {
        d.status = "exception";   // never reached
    }
}
```

On FW 30.23 the field draws `registered`; on FW 31.33 it is replaced by the
Connect IQ error icon.

### Steps to reproduce

1. Build a data field with the `BluetoothLowEnergy` permission.
2. In `AppBase.onStart()`, call `Ble.setDelegate(...)` and then
   `Ble.registerProfile(...)` with the custom profile shown above.
3. Install on an Edge Explore 2 running FW 31.33 and add the field to a data screen.
4. The field shows the Connect IQ error icon immediately; `CIQ_LOG.YML` contains
   the stack above.

Only one BLE profile is registered at this point, so this is not the
"3 profiles maximum" limit. Reordering registrations, dropping the descriptor and
registering before/after `setDelegate` make no difference.

### Impact

Third-party fields that talk to a peripheral over a vendor-specific GATT service
cannot run at all on this firmware — the app dies at startup and cannot detect,
catch or work around the failure. On 30.23 the identical build connects,
subscribes to the characteristic and receives notifications normally.

### Request

1. Restore the ability to register custom 128-bit service UUIDs, as on FW 30.23.
2. If registration must fail, please fail through `onProfileRegister(uuid, status)`
   with a documented status instead of terminating the application from inside the
   call — an app cannot catch a System Error.
3. Please document `status = 2`.

---

## Куда публиковать

Garmin принимает баг-репорты Connect IQ **только на форуме разработчиков**
(отдельного трекера нет, поддержка Garmin по «пользовательской» линии такие
обращения не берёт).

1. Раздел: **Connect IQ → Bug Reports** —
   https://forums.garmin.com/developer/connect-iq/i/bug-reports
2. Нужен обычный аккаунт Garmin (тот же, что в Garmin Connect).
3. Кнопка **New** → вставить Title и Body из этого файла.
4. Приложить файлом `CIQ_LOG.YML` с устройства — сотрудники Garmin
   (`Brad.ConnectIQ` и коллеги) обычно просят именно его.
5. Пометить, что это **регрессия** и указать обе прошивки (30.23 → 31.33):
   регрессии приоритизируются заметно быстрее новых дефектов.

Полезно продублировать ссылкой в **Edge Explore 2 → Cycling** форуме
(https://forums.garmin.com/sports-fitness/cycling/f/edge-explore-2) — там сидят
владельцы устройства, и подтверждения от других пользователей ускоряют разбор.
Есть похожая тема про ActiveLook Engo 2 с тем же симптомом — стоит сослаться на
неё как на второй случай.

## Что приложить к репорту

| Файл | Откуда |
|---|---|
| `CIQ_LOG.YML` / `CIQ_LOG.BAK` | `GARMIN/APPS/LOGS/` на устройстве |
| `DIDIAG.TXT` | лог диаг-сборки: видно `18EF:skip`, `180F:ok`, `services n=1` |
| `doc/repro/` | минимальный проект-репро (исходник + jungle + manifest) |
| `bin/repro.prg` | собранный репро для быстрой проверки на устройстве |

Репро-проект удобнее приложить архивом папки `doc/repro` — Garmin обычно просит
исходники, а не только `.prg`.

Оба файла уже есть в `bin/` после последнего снятия.
