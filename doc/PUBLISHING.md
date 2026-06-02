# Публикация в Connect IQ Store

> Черновик и чеклист для выкладки приложения. Вернёмся позже.

## Артефакт

- Пакет для загрузки: **`bin/Di2App.iq`** (генерируется командой ниже).
- Текущая версия: **0.0.1** (`manifest.xml` → `version`).
- Продукты: только **`edgeexplore2`** (Edge Explore 2) — единственное протестированное устройство.

### Пересобрать .iq

```bash
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b"
KEY="/Volumes/WD2TB/Projects/sln_chipre/garmin/developer_key/developer_key"
cd /Volumes/WD2TB/Projects/sln_chipre/garmin/Di2App
"$SDK/bin/monkeyc" -e -o bin/Di2App.iq -f monkey.jungle -y "$KEY" -r -w
```

Эквивалент в VS Code: команда палитры **Monkey C: Export Project**.

## Порядок загрузки

1. **apps.garmin.com** → Sign In аккаунтом Garmin-разработчика → **Dashboard → Upload an App**.
2. Загрузить **`bin/Di2App.iq`**. Сервис проверит бинарь (формат/разрешения).
3. После валидации заполнить карточку (описание, скриншоты, категория) и отправить на ревью.

> ⚠️ **Ключ подписи.** Приложение привязывается к ключу `…/garmin/developer_key/developer_key`
> при первой загрузке. Хранить и не терять — все будущие обновления подписывать **им же**,
> иначе стор не примет апдейт.

## Карточка приложения (English — store-facing)

**Name:** `Di2 Field`
**Category:** Data Fields

**Description:**
```
Di2 Field shows your current Shimano Di2 rear gear (e.g. 10/12) and the
D-Fly wireless unit battery level right on your Edge data screen.

It connects over Bluetooth Low Energy to a Shimano D-Fly module
(EW-WU111 / SC-M9051).

Features
- Large, clear rear gear / cassette size
- Front chainring indicator
- D-Fly battery percentage
- Connection status dot with auto-reconnect

Requirements
- Shimano Di2 with a D-Fly module (EW-WU111 or SC-M9051) advertising over BLE.

Independent, unofficial app — not affiliated with or endorsed by Shimano.
```

**Bluetooth permission justification:**
```
Connects to the Shimano D-Fly module to read gear position and battery level.
```

## Скриншоты

- Минимум 1 скриншот. Проще всего — фото экрана Edge с работающим полем
  (текущая сборка уже без отладочной строки).
- Альтернатива — чистый скриншот симулятора: собрать с `ENABLE_BLE = false`
  (`Di2FieldApp.mc`), `Run → F5`, заскринить окно симулятора.

## На что обратить внимание при ревью

- **Торговая марка Shimano:** не подавать как официальное приложение; фраза
  «unofficial / not affiliated» в описании это закрывает.
- **BLE-разрешение:** Garmin может запросить обоснование — текст готов выше.
- **Версионирование:** следующие правки поднимать `0.0.2`, `0.1.0` и т.д., подпись — тем же ключом.

## TODO перед публичным релизом (опционально)

- [ ] Решить судьбу `F:1/1` для 1x (оставить / убрать переднюю).
- [ ] Если потребуется 2x — снять дамп с переключением передней звезды (`DEBUG_OVERLAY = true`),
      определить `PKT_FRONT_IDX`, добавить разбор передней.
- [ ] При желании расширить список устройств (скачать профили в SDK Manager, протестировать layout).
- [ ] Short description под лимит стора (если понадобится).
