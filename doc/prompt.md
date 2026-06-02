# Di2Field — Garmin Connect IQ Data Field для Edge Explore 2

## Контекст проекта

Разрабатываем Connect IQ Data Field на Monkey C для отображения данных Shimano Di2
на Garmin Edge Explore 2 через Bluetooth LE (BLE).

Устройство Edge Explore 2 не поддерживает Di2 нативно через ANT+ (заблокировано прошивкой),
поэтому используем BLE-канал через Shimano D-Fly модуль (EW-WU111 / SC-M9051).

---

## Шаг 1 — Подготовка окружения

### Инструменты (установи если отсутствуют)

```bash
# 1. VS Code
brew install --cask visual-studio-code   # macOS

# 2. Connect IQ SDK Manager
# Скачать вручную: https://developer.garmin.com/connect-iq/sdk/
# Запустить, установить последний SDK и профиль устройства edge_explore2

# 3. Расширение Monkey C в VS Code
# Extensions → поиск "Monkey C" → установить (издатель: Garmin)

# 4. Git (если нет)
brew install git
```

---

## Шаг 2 — Инициализация репозитория и сабмодули

```bash
# Создай корневую папку проекта
mkdir Di2Field && cd Di2Field
git init

# ── Документация и референсы ────────────────────────────────────────────────

mkdir -p doc

# 1. Официальные примеры от Garmin (Connect IQ sample apps)
git submodule add https://github.com/garmin/connectiq-apps.git \
    doc/connectiq-apps

# 2. DiHack — реверс-инжиниринг Shimano Private ANT + BLE UUID/протокол
git submodule add https://github.com/cmoski/DiHack.git \
    doc/DiHack

# 3. Ki2 — Android-реализация Shimano BLE протокола (Java/Kotlin, референс)
git submodule add https://github.com/valterc/ki2.git \
    doc/ki2

# 4. Shimano STEPS e-bike Connect IQ Data Field (Monkey C + BLE, ближайший аналог)
git submodule add https://github.com/markdotai/emtb.git \
    doc/emtb

# 5. Форк emtb с фиксом для Edge-устройств (доп. референс)
git submodule add https://github.com/MarkusDatgloi/ebikeDataField.git \
    doc/ebikeDataField

# Инициализировать все сабмодули
git submodule update --init --recursive
```

---

## Шаг 3 — Изучи референсные исходники

Прежде чем писать код — прочитай следующие файлы и выпиши ключевые находки в `doc/NOTES.md`:

### Из `doc/emtb/source/`
- Прочитай все `.mc` файлы
- Найди и задокументируй:
  - BLE Service UUID
  - UUID характеристик для Notify (gear, battery)
  - Как регистрируется BLE profile: `BluetoothLowEnergy.registerProfile(...)`
  - Как включаются уведомления: `requestNotifications(...)`
  - **Формат байтов пакета**: какой байт = rear gear index, какой = total, front gear, battery %

### Из `doc/ebikeDataField/`
- Сравни с emtb, найди отличия и фиксы

### Из `doc/ki2/app/src/main/java/`
- Найди классы связанные с BLE (поиск по: `BluetoothGatt`, `UUID`, `shifting`, `gear`)
- Выпиши формат пакетов если он там задокументирован

### Из `doc/DiHack/`
- Прочитай `README.md` и `Onenote-notes.pdf`
- Выпиши ANT network key, BLE UUID, формат данных

### Из `doc/connectiq-apps/`
- Найди примеры с BLE (`BluetoothLowEnergy`)
- Изучи как правильно управлять lifecycle BLE соединения в Data Field

Сохрани все находки в `doc/NOTES.md` в структурированном виде.

---

## Шаг 4 — Создай проект Di2Field

### Структура файлов

```
Di2Field/
├── CLAUDE.md                    ← этот файл
├── .gitmodules                  ← сабмодули
├── manifest.xml
├── monkey.jungle
├── source/
│   ├── Di2FieldApp.mc           ← AppBase, lifecycle
│   ├── Di2FieldView.mc          ← UI рендеринг
│   └── Di2BleDelegate.mc        ← BLE scan/connect/notify/parse
└── resources/
    ├── strings.xml
    └── layouts/
        └── layout.xml
doc/
├── NOTES.md                     ← твои находки из шага 3
├── connectiq-apps/              ← submodule
├── DiHack/                      ← submodule
├── ki2/                         ← submodule
├── emtb/                        ← submodule
└── ebikeDataField/              ← submodule
```

---

## Шаг 5 — Реализация

### manifest.xml

```xml
<iq:manifest xmlns:iq="http://www.garmin.com/xml/connectiq" version="3">
  <iq:application entry="Di2FieldApp" id="<сгенерируй UUID>" launchType="datafield"
                  minApiLevel="3.2.0" name="@Strings.AppName" type="datafield"
                  version="1.0.0">
    <iq:products>
      <iq:product id="edge_explore2"/>
    </iq:products>
    <iq:permissions>
      <iq:uses-permission id="BluetoothLowEnergy"/>
    </iq:permissions>
    <iq:languages>
      <iq:language>eng</iq:language>
    </iq:languages>
  </iq:application>
</iq:manifest>
```

### BLE UUID константы (Di2BleDelegate.mc)

```monkey-c
// Shimano Proprietary Service
const SHIMANO_SERVICE_UUID     = "000018ff-5348-494d-414e-4f5f424c4500";

// Характеристика Notify — передачи / статус
const SHIMANO_CHAR_GEAR_UUID   = "00002af9-5348-494d-414e-4f5f424c4500";

// Характеристика Notify — батарея
const SHIMANO_CHAR_BATT_UUID   = "00002afb-5348-494d-414e-4f5f424c4500";

// Основной канал команд (Indicate + Write)
const SHIMANO_CHAR_MAIN_UUID   = "00002af3-5348-494d-414e-4f5f424c4500";
```

### Формат пакета (заполни после шага 3)

```monkey-c
// TODO: заполнить после изучения doc/emtb и doc/ki2
// Ожидаемая структура notify пакета 0x2af9:
//   Байт[?] = rear gear index   (1-based)
//   Байт[?] = rear gear total
//   Байт[?] = front gear index
//   Байт[?] = front gear total
//
// Notify пакет 0x2afb:
//   Байт[?] = battery % (0-100)
//
// Если неизвестно — включи debug mode:
//   System.println("GEAR bytes: " + data.toString());
```

### UI дизайн (Di2FieldView.mc)

Воспроизведи точно этот макет (светлая тема):

```
┌─────────────────────────────────┐
│ [Di2]  F:2/2  🔋 100%           │  ← мелкий шрифт (FONT_XTINY)
│                                 │
│           7/12                  │  ← FONT_NUMBER_THAI_HOT или крупнейший доступный
└─────────────────────────────────┘
```

- Фон: белый (`Graphics.COLOR_WHITE`)
- Текст: чёрный (`Graphics.COLOR_BLACK`)
- Верхняя строка: `[Di2]` слева, `F:{front}/{frontTotal}` по центру, `🔋{bat}%` справа
- Центр: `{rear}/{rearTotal}` — максимально крупный шрифт
- Статус без подключения: вместо цифр показывать `---`
- Состояние подключения: `•` зелёный / `○` серый рядом с `[Di2]`

### BLE lifecycle

```monkey-c
// Di2BleDelegate.mc должен реализовать:

// 1. scan() — поиск устройства с SHIMANO_SERVICE_UUID в advertisement
// 2. onScanResult(scanResult) — фильтровать по UUID, подключаться
// 3. onConnected(device) — discover services, subscribe to notify
// 4. onCharacteristicChanged(char, data) — парсить байты, обновлять state
// 5. onDisconnected() — запустить повторный scan через 3 секунды
// 6. Auto-reconnect loop (не бесконечный — максимум 10 попыток)
```

---

## Шаг 6 — Сборка и тест

```bash
# В VS Code:
# Cmd+Shift+P → "Monkey C: Build For Device" → выбрать Di2Field → Debug
# → создаст Di2Field.prg в папке bin/

# Запуск в симуляторе:
# Cmd+Shift+P → "Monkey C: Run in Simulator" → edge_explore2

# Деплой на устройство:
# Подключить Edge Explore 2 по USB
# Скопировать Di2Field.prg в /GARMIN/APPS/
# Лог-файл отладки: /GARMIN/APPS/LOGS/Di2Field.txt
```

---

## Шаг 7 — Debug режим

Если формат байтов пакета неизвестен — включи режим логирования:

```monkey-c
// В onCharacteristicChanged добавить:
var hexStr = "";
for (var i = 0; i < data.size(); i++) {
    hexStr += data[i].format("%02X") + " ";
}
System.println("[Di2] char=" + char.getUuid() + " bytes=[" + hexStr + "]");
```

Подключи Edge к Mac, скопируй `/GARMIN/APPS/LOGS/Di2Field.txt` после поездки.
Пощёлкай передачи и сопоставь изменения байтов с реальными передачами.

---

## Ограничения и правила кода

- Connect IQ API: минимум `3.2.0`
- Устройство: `edge_explore2`
- Никаких сторонних зависимостей
- Проверять все значения на `null` перед использованием
- Monkey C: использовать `as` для type casting, не `(Type)`
- Не использовать `Lang.Exception` напрямую, только `try/catch`
- Все строки через `resources/strings.xml`
- Формат коммитов: `feat|fix|chore(scope): описание`

---

## Ожидаемый результат

По завершении:
1. Проект собирается без ошибок (`Build For Device`)
2. В симуляторе для `edge_explore2` отображается UI из макета
3. При подключении реального Di2 по BLE — цифры обновляются в реальном времени
4. При потере BLE — показывается `---`, идёт переподключение
5. Все исходники аккуратно разложены по файлам согласно структуре выше
