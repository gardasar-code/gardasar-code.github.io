# Di2Field — Connect IQ Data Field (Edge Explore 2)

Monkey C Data Field: отображение передач Shimano Di2 и заряда D-Fly по BLE.
Полный исходный бриф — `doc/prompt.md`. Анализ референсов — `doc/NOTES.md`.

## Архитектура

| Файл | Роль |
|---|---|
| `source/Di2FieldApp.mc` | AppBase: lifecycle, поднимает BLE, отдаёт View |
| `source/Di2BleDelegate.mc` | scan → connect → CCCD-подписка → парсинг → reconnect |
| `source/Di2FieldView.mc` | рендеринг макета (светлая тема) в `onUpdate` |
| `source/Di2State.mc` | разделяемое состояние (передачи/батарея/connected) |

Поток данных: `Di2BleDelegate` (писатель, async BLE-колбэки) → `Di2State` →
`Di2FieldView` (читатель, `onUpdate`).

## ⚠️ Статус протокола (важно)

- BLE-«сантехника» и **батарея** (`0000180f`/`00002a19`, byte[0]) — подтверждены по emtb.
- **UUID передач из prompt.md неверны.** Рабочий notify-канал — `000018ef`/`00002ac1`.
- **Байтовый формат передач дорожного Di2 неизвестен** (референсы покрывают eBike/ANT).
  Смещения `PKT_*` в `Di2BleDelegate.mc` — гипотеза, помечены `TODO: verify on real device`.
  Калибровка: `DEBUG = true` → снять `/GARMIN/APPS/LOGS/Di2Field.txt`, сопоставить байты
  с реальными переключениями, поправить `PKT_REAR_IDX` / `PKT_FRONT_IDX` / длины пакетов.

Подробности и цитаты исходников — `doc/NOTES.md`.

## Сборка

- Connect IQ SDK + VS Code расширение Monkey C (издатель Garmin), профиль `edgeexplore2`.
- `Monkey C: Build For Device` → `bin/Di2Field.prg`; `Run in Simulator` → `edgeexplore2`.
- Деплой: `.prg` в `/GARMIN/APPS/`; лог отладки `/GARMIN/APPS/LOGS/Di2Field.txt`.

## Правила кода

- API min `3.2.0`, устройство `edgeexplore2`, без сторонних зависимостей.
- Проверять `null` перед использованием; type cast через `as`.
- Все пользовательские строки — `resources/strings.xml`.
- Коммиты: `feat|fix|chore(scope): описание`.
