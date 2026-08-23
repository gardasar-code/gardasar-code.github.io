# ANT-подход для Di2 Field — исследование осуществимости (СПАЙК)

> Итог: **ANT из Connect IQ нереализуем** для стороннего приложения.
> BLE остаётся единственным возможным путём. Ветка `feature/ant-dfly` — этот
> документ-спайк; кода реализации нет (он гарантированно крашит на устройстве).

## Что хотелось

Из анализа DiHack/ki2 (см. `NOTES.md`) видно: на **ANT** D-Fly будится щелчком и
вещает broadcast без паринга. Идея — открыть приватный ANT-канал Shimano из
дата-филда (`Toybox.Ant.GenericChannel`), как Ki2 на Android, и тем самым убрать
боль с перепарингом BLE.

## Почему невозможно (три независимых подтверждения)

### 1. В `Toybox.Ant` нет API для сетевого ключа

Проверка SDK `connectiq-sdk-mac-9.1.0` (`bin/api.debug.xml`):

- `Ant.ChannelAssignment` — методы только: `initialize(channelType, networkType)`,
  `setBackgroundScan`, `isBackgroundScanEnabled`. **Сеттера ключа нет.**
- `Ant.DeviceConfig` — опции `deviceNumber/deviceType/transmissionType/`
  `messagePeriod/radioFrequency/searchTimeout*/searchThreshold`. **networkKey нет.**
- Поиск `setNetworkKey` по всему `Toybox.Ant` — пусто.
- `NETWORK_PRIVATE` существует как константа, но передать в неё 64/128-битный ключ
  Shimano нечем.

Конструктор: `ChannelAssignment.initialize(c as ChannelType, n as NetworkType)`,
где `n ∈ {NETWORK_PUBLIC, NETWORK_PLUS(ANT+), NETWORK_PRIVATE}`. Доступны реально
только PUBLIC и PLUS(ANT+). Di2 вещает в **приватной** сети — не ANT+.

### 2. На устройстве падает

Forum: «Establishing an ANT connection with the Shimano Di2 groupset»
<https://forums.garmin.com/developer/connect-iq/f/discussion/257390/>
— код с приватным ключом работает в симуляторе, но на Edge 830 даёт
**«No network key given, the ANT Private network requires a valid network key»**
и краш.

Bug report: «CIQ apps on EDGE devices can't communicate via ANT PRIVATE channel»
<https://forums.garmin.com/developer/connect-iq/i/bug-reports/ciq-apps-on-edge-devices-can-t-communicate-via-ant-private-channel>

### 3. Ключ Shimano закрыт лицензией

Shimano выдаёт секретный ключ Private ANT только лицензированным производителям
велокомпьютеров (Garmin-прошивка, Wahoo, Lezyne, …) — он зашит на уровне
firmware, не доступен CIQ-приложениям. Поэтому:

- **Ki2** (Android) может — там полный DSI ANT SDK + `acquireChannelOnPrivateNetwork`
  с ключом из ресурса (ключ добыт реверсом).
- **CIQ-дата-филд** — не может: нет ни API для ключа, ни доступа к приватной сети.
- Наш референс **emtb** не зря на BLE.

Контекст: Shimano даже заставила Hammerhead убрать Di2-функции из Karoo
(DC Rainmaker, 2022) — экосистема закрытая.

## Технические параметры ANT-канала D-Fly (на случай, если платформа изменится)

Из ki2 `data/configuration/ConfigurationStore.java:28,41`:
- RF frequency = 57 (2457 MHz), channel period = 8198 (~4 Гц / 250 мс beacon).
- Режим Rx scan (slave receive-only); кнопки — `D_FLY_CH1..CH4`.
- Нужен приватный сетевой ключ Shimano (в референсах не лежит).

## Решение

ANT-ветку **не развиваем**. Остаёмся на BLE (`main`): авто-реконнект для коротких
пауз работает, после глубокого сна подсказываем паринг (ограничение прошивки
D-Fly на BLE-радио, тоже неустранимое софтом).

Эта ветка остаётся как задокументированный тупик; в `main` можно не мёржить
(или смёржить только этот документ для истории).
