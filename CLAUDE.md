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
- **Формат пакета передач подтверждён на реальном Di2** (XT M8250, 12-sp; снято дважды:
  лог 2026-06-02 и фото-оверлей 2026-06-04). Пакет 17 байт:
  **байт 5 = текущая задняя передача**, **байт 6 = число задних звёзд** (0x0C=12).
  Отдельного байта передней звезды не выявлено — на тесте 1x, число звёзд берётся из настроек.
- Открыто: байт **передней** звезды для **2x/3x** (нужен дамп с переключением переда).
  Калибровка остального: `DEBUG_OVERLAY` во View (или `DEBUG=true` → лог) → сопоставить байты.

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
