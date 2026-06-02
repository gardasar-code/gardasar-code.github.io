# NOTES — анализ референсов Shimano Di2 BLE (шаг 3 prompt.md)

> Источник находок: сабмодули в `doc/` (emtb, ebikeDataField, ki2, DiHack, connectiq-apps).
> Все UUID/смещения байтов подтверждены прямым чтением исходников с указанием `файл:строка`.

---

## ✅ ПОДТВЕРЖДЕНО на реальном Di2 (Edge Explore 2, 2026-06-02)

Notify-пакет gear (17 байт) на характеристике `00002ac1`. Реальный дамп:
```
idx:  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16
hex: 00 00 03 FF FF 0A 0C 80 80 80 FF EE 12 FF FF 15 00
```
- **байт 5 = текущая задняя передача** (0x0A = 10) — подтверждено переключениями.
- **байт 6 = число задних передач** (0x0C = 12) — подтверждено (12-скор. кассета).
- Отдельного байта **передней** в пакете не выявлено; на тестовом байке **1x**,
  поэтому в коде передняя зафиксирована `1/1` (`FRONT_CHAINRINGS`).
  Для **2x** нужен ещё один дамп с переключением передней звезды (включить
  `DEBUG_OVERLAY` во View) — найти байт, меняющийся 0↔1.
- байты `FF`/`80` — padding; байты 2,11,12,15 — пока не интерпретированы.

---

## ⚠️ Главный вывод (читать первым)

1. **UUID из `prompt.md` (`000018ff` + `2af9`/`2afb`/`2af3`) для передач — НЕВЕРНЫ.**
   В `emtb/source/emtbDelegate.mc:249` сервис `000018ff` помечен автором реверса дословно:
   `"we don't use this service (no idea what the data is)"`. Это просто advertised-маркер
   устройства Shimano, по нему удобно фильтровать скан, но полезных данных он не отдаёт.

2. **Рабочий канал нотификаций — сервис `000018ef` / характеристика `00002ac1`** (CCCD).
   НО это телеметрия **eBike-мотора Shimano STEPS** (mode / cadence / speed / assist / motor-gear),
   а НЕ передний/задний переключатель дорожного Di2.

3. **Точного BLE-формата передних/задних передач дорожного Di2 в референсах НЕТ.**
   - `ki2` и `DiHack` документируют **private ANT / ANT+**, а не BLE.
   - `emtb`/`ebikeDataField` — eBike по BLE, не road-shifting.
   Поэтому байтовый формат передач Di2 надо **снимать с реального устройства** в debug-режиме
   (шаг 7 prompt.md). Реализация делает именно это: логирует все notify-байты и парсит по
   легко настраиваемым константам смещений.

4. **Надёжно подтверждено и переиспользуется как есть:** вся BLE-«сантехника»
   (registerProfile / scan / pairDevice / CCCD-подписка / onCharacteristicChanged) и
   **батарея** через стандартный сервис.

---

## UUIDs (подтверждено)

| Назначение | UUID | Источник |
|---|---|---|
| Advertised marker (фильтр скана) | `000018ff-5348-494d-414e-4f5f424c4500` | `emtbDelegate.mc:249` |
| Notifications service (mode/gear, eBike) | `000018ef-5348-494d-414e-4f5f424c4500` | `emtbDelegate.mc:257` |
| Notifications characteristic (Notify + CCCD) | `00002ac1-5348-494d-414e-4f5f424c4500` | `emtbDelegate.mc:258` |
| Battery service (стандартный BLE) | `0000180f-0000-1000-8000-00805f9b34fb` | `emtbDelegate.mc:254` |
| Battery characteristic (Read) | `00002a19-0000-1000-8000-00805f9b34fb` | `emtbDelegate.mc:255` |
| MAC service (идентификация, опц.) | `000018fe-1212-efde-1523-785feabcd123` | `emtbDelegate.mc:260` |
| MAC characteristic (Read) | `00002ae3-1212-efde-1523-785feabcd123` | `emtbDelegate.mc:261` |

CCCD = `Ble.cccdUuid()` (стандартный `0x2902`).

---

## Формат пакетов notify на `00002ac1` (eBike, emtb)

Shimano шлёт **3 разных пакета** в одну характеристику; различать по длине (`value.size()`).
Источник парсинга: `emtbDelegate.mc:640-661`.

| Длина | Содержимое (eBike) | Парсинг |
|---|---|---|
| 10 байт | mode / speed / cadence / assist | `value[1]`=mode, `value[4]`=assist, `value[5]`=cadence, `(value[3]<<8)|value[2]`=speed/10 |
| 17 байт | gear (мотора) | `value[5]` = gear index |
| прочее | служебные | игнор |

> Для дорожного Di2 эти смещения **не гарантированы**. В нашем коде они вынесены в
> именованные константы `PKT_*` и помечены `TODO: verify on real device`.

### Батарея — подтверждено надёжно
`requestRead()` по `00002a19`, ответ в `onCharacteristicRead`: `value[0]` = процент 0..100.
Источник: `emtbDelegate.mc:598`.

---

## Подсказки по формату передач из ANT (ki2 / DiHack) — для калибровки

BLE-формат неизвестен, но ANT-страницы дают ориентир, какие поля вообще есть:

- **ki2** `ShimanoShiftingProfileHandler.java` — ANT page 0:
  `byte2`=front gear, `byte3`=rear gear, `byte4`=battery %, `byte5`=mode;
  ANT page 17 (BIKE_STATUS): `byte2`=front max, `byte3`=rear max.
- **DiHack** `Onenote-notes.pdf`: private Shimano ANT network key `A9-AD-32-68-3D-76-C7-4D`,
  частота 57; page 00: `[02]`=front ring, `[09]`=rear, `[64]`=battery %.

> Используем как гипотезу при сопоставлении реальных BLE-байтов: ищем в дампе
> правдоподобные пары (front 1..3 / rear 1..12) и значение батареи ~0..100.

---

## Канонические паттерны Connect IQ BLE (connectiq-apps + emtb)

Подтверждённые сигнатуры (используются в `Di2BleDelegate.mc`):

```monkey-c
Ble.registerProfile({ :uuid => svc, :characteristics => [
    { :uuid => ch, :descriptors => [Ble.cccdUuid()] } ] });   // в onStart приложения
Ble.setDelegate(delegate);                                    // onStart
Ble.setScanState(Ble.SCAN_STATE_SCANNING);                    // старт скана
// onScanResults(iter): iter.next(); r.getServiceUuids(); r.getRssi(); r.isSameDevice(x)
Ble.pairDevice(scanResult);   // -> Device; иногда сразу device.isConnected()==true
// onConnectedStateChanged(device, state): state==Ble.CONNECTION_STATE_CONNECTED
var c = device.getService(svc).getCharacteristic(ch);
c.getDescriptor(Ble.cccdUuid()).requestWrite([0x01,0x00]b);   // включить notify
c.requestRead();                                              // onCharacteristicRead(c,status,value)
// onCharacteristicChanged(characteristic, value): value — ByteArray
Ble.getPairedDevices().next(); Ble.unpairDevice(device);
```

Замечания из emtb (важные для надёжности):
- После `pairDevice` `onConnectedStateChanged` иногда НЕ вызывается → проверять
  `device.isConnected()` сразу (`emtbDelegate.mc:565-568`).
- `requestRead` батареи нельзя дёргать пока не пришёл `onCharacteristicRead` —
  иначе краш после выключения устройства (`emtbDelegate.mc:386-399`).
- При старте/стопе скана чистить список кандидатов (`onScanStateChange`).
- Подключаться к одному устройству; выбирать по сильнейшему RSSI.

---

## Калибровка байтов передач на реальном устройстве (шаг 6/7)

Цель: определить, какой байт в notify-пакете `00002ac1` = задняя передача,
какой = передняя, какой = их количество, и поправить константы `PKT_*` в
`Di2BleDelegate.mc`. Без этого UI покажет передачу неверно или как `---`.

### A. Подготовка
1. `DEBUG = true` в `Di2BleDelegate.mc` (уже включено).
2. Собрать `Build for Device` → `bin/Di2Field.prg`, скопировать в `/GARMIN/APPS/` на Edge.
3. Добавить поле Di2 на экран данных активности (Edge показывает Data Field только
   внутри запущенной/приостановленной активности — иначе лог пустой).
4. Включить Di2 (D-Fly EW-WU111/SC-M9051), дождаться зелёной точки подключения.

### B. Снятие лога (методично, велосипед на станке)
Лог `System.println` пишется в `/GARMIN/APPS/LOGS/Di2Field.txt`. Каждое уведомление —
строка вида `[Di2] char=... len=N bytes=[AA BB CC ...]`.

Переключай по одной передаче с паузой ~2–3 с и веди бумажный протокол «время → действие»:
1. Старт активности (можно без движения).
2. **Зад**: с самой малой звезды до самой большой, по одному клику, пауза между кликами.
   Записывай: «клик 1→2», «2→3», … до максимума, затем обратно.
3. **Перёд** (если 2x): переключи большую/малую звезду 2–3 раза.
4. Останови активность (лог флашится), подключи Edge по USB, скопируй `.txt` на Mac.

### C. Анализ дампа
1. Сгруппируй строки по `len`. Игнорируй пакеты, которые «спамятся» без изменений.
2. Найди байт, чьё значение растёт/падает на 1 синхронно с твоими кликами зада →
   это `PKT_REAR_IDX`, а его диапазон значений (мин..макс) = число задних передач.
3. То же для переда → `PKT_FRONT_IDX`; диапазон = число передних.
4. Уточни длину пакета с передачами → `PKT_GEAR_LEN` (может отличаться от 17).
5. Поищи «статический» пакет с байтами, равными числу передач (напр. 12 и 2) —
   это кандидат на `frontTotal`/`rearTotal` (страница bike-status, ср. ANT page 17).
   Эталон значений и смещений (для проверки гипотез):
   ki2 ANT page0 `byte2`=front,`byte3`=rear; page17 `byte2`=front max,`byte3`=rear max.

### D. Правка кода и релиз
1. Обнови в `Di2BleDelegate.mc`: `PKT_GEAR_LEN`, `PKT_REAR_IDX`, `PKT_FRONT_IDX`.
2. Если нашёл counts — добавь их разбор в `parseGearPacket` и присвой
   `_state.rearTotal` / `_state.frontTotal` (тогда UI покажет `7/12`, а не `7`).
3. Если индекс 0-based, а нужен «человеческий» 1..N — прибавь `+1` при присвоении.
4. Пересобери, проверь на устройстве, затем `DEBUG = false` для релиза.

> Подсказки сопоставления: задняя передача меняется в диапазоне ~1..11/12,
> передняя ~1..2/3, батарея ~0..100. Значения вне этих диапазонов — это не передача.

## Риски / открытые вопросы

1. **BLE на Edge Explore 2 работает** в Data Field — подтверждено на устройстве
   (firmware 30.23, CIQ 6.0.0): происходит `onConnectedStateChanged → CONNECTED`.
2. **Формат передач Di2** — главный неизвестный; финализируется после дампа реальных байтов.
3. emtb рассчитан на eBike; для road Di2 командной инициализации (write) может НЕ требоваться —
   достаточно подписки на notify. Проверяется на устройстве.

## Показ developer-полей FIT в Garmin Connect (важно)

Чтобы кастомные FIT-поля **рисовались в Garmin Connect** (графики + сводка), мало
писать их кодом через `FitContributor` — нужно ещё:
1. Ресурс **`resources/fitContributions.xml`** с `<fitField>` на каждое поле:
   `id` (= fieldId в коде), `dataLabel`, `unitLabel`, `sortOrder` (обязательные),
   плюс `displayInChart`/`displayInActivitySummary`, `precision`, `fillColor`, `chartTitle`.
   Все `*Label` — ссылки на строки (`@Strings.X`), литералы запрещены; пустые строки
   дают warning (для ratio задали `:1`).
2. **Загрузка в Connect IQ Store** (beta достаточно). **Сайдлоад (OpenMTP/прямой `.prg`)
   данные пишет в FIT, но Garmin Connect их НЕ показывает** — конфиг отображения
   берётся из стора/`.iq`.
3. Локальная проверка без стора — инструмент **MonkeyGraph** из SDK.

Источник: forums.garmin.com (Connect IQ App Development), схема `fitFieldType` в
`bin/resources.xsd` SDK.

## Подтверждённые ограничения устройства (из CIQ_LOG.BAK)

- **`Toybox.Timer` НЕДОСТУПЕН в Data Field** — `new Timer.Timer()` бросает Unhandled
  Exception (значок «Q» на экране, поле падает). Декодировано по `bin/*.prg.debug.xml`
  через смещения PC из `CIQ_LOG.BAK`.
  **Решение:** периодику (реконнект, опрос батареи) гоним из `View.compute()` —
  система вызывает его ~раз в секунду; делегат считает «тики» вместо таймеров
  (`Di2BleDelegate.onTick()`).
- Диагностика крашей на устройстве: лог `GARMIN/APPS/LOGS/CIQ_LOG.BAK` (не `Di2Field.txt`!),
  PC-смещения декодируются по `.prg.debug.xml` от **той же** сборки.
