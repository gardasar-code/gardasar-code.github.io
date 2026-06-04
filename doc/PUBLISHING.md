# Публикация в Connect IQ Store

Полный гайд по выкладке Di2 Field. Версия — источник истины `manifest.xml` → `version`.

## App ID и ветки

Beta и публичная версии — РАЗНЫЕ app id (требование Garmin). Различие вынесено в ветки.
Расхождение между ветками — ровно одна строка `<iq:application>` в `manifest.xml`:
атрибуты `id` И `launcherIcon` (бета-иконка с оранжевым уголком vs обычная).

| Ветка | App ID | launcherIcon | Назначение |
|---|---|---|---|
| **main** | `a46118db030d4d489268501a3e80547d` | `@Drawables.LauncherIconBeta` | beta — разработка, «Upload New Version» в beta-приложение |
| **prod** | `a7fea1a873694f3ba5c27c4312b4062a` | `@Drawables.LauncherIcon` | публичный релиз — загрузка БЕЗ галочки Beta |

Оба drawable (`LauncherIcon`, `LauncherIconBeta`) есть на обеих ветках — отличается
только ссылка в manifest. При мердже main→prod конфликт будет в той же строке
`<iq:application>` → оставить prod-значения (prod-id + `@Drawables.LauncherIcon`).

### Сборка .iq
```bash
./build.sh store           # -> bin/Di2App.iq (release, все продукты/языки)
```
Эквивалент в VS Code: **Monkey C: Export Project**.

### Релиз публичной версии
```bash
git checkout prod
git merge main             # конфликт в строке <iq:application>: оставить prod-id
                           # (a7fea1a8...) И launcherIcon=@Drawables.LauncherIcon
./build.sh store           # -> bin/Di2App.iq с публичным id и обычной иконкой
git checkout main
```

> ⚠️ **Ключ подписи** `…/garmin/developer_key/developer_key` — приложение привязано к нему.
> Все обновления подписывать тем же ключом, иначе стор не примет апдейт.

---

## Параметры приложения
- Тип: Data Field. Продукт: только **`edgeexplore2`** (единственное протестированное устройство).
- Языки: **eng, fre, spa, rus, deu, ara** (6). Имя/подписи/настройки/FIT-поля локализованы.
- Permissions: **BluetoothLowEnergy** (Communication & Data Transmission) + **FitContributor** (запись в активность).

---

## Загрузка: шаг 1 — App File
- **File:** `bin/Di2App.iq`
- **App Version:** значение из `manifest.xml` (текущее — `0.0.28`)
- **Beta App:** ❌ снять галочку для публичного релиза (поставить — для beta-теста).

## Шаг 2 — Title and Description

**Title (EN):** `Di2 Field` · **Category:** Data Fields → Cycling

**Description (EN):**
```
Di2 Field shows your current Shimano Di2 rear gear (e.g. 5•12) and the D-Fly
wireless unit battery level right on your Edge data screen.

It connects over Bluetooth Low Energy to a Shimano D-Fly module
(EW-WU111 / SC-M9051) — no ANT+ needed.

GETTING CONNECTED
There is no button to press — it's a data field. Connection is automatic:
1. Add the Di2 field to a data screen on your Edge.
2. Wake your Di2 by tapping any shifter (it sleeps when idle and stays
   invisible on the air until then).
3. The field finds the nearest Di2 and connects on its own — the status dot
   turns green and the gear numbers appear.
4. It then sticks to that Di2 (the dot turns dark blue) and reconnects to the
   same one automatically on every future ride.

If the link drops, the field keeps retrying on its own and reconnects as soon
as the Di2 is awake again — for a short break there's nothing to do. If the Di2
has been asleep for a long time it stops broadcasting entirely (a Shimano
power-saving behaviour); when that happens the hint changes to "Hold Di2 button"
— put the unit back into pairing mode once and the field reconnects.

The status dot next to "Di2" is color-coded:
- Blue — searching for a Di2 (pulsing while it scans)
- Yellow — connecting
- Green — connected and receiving data
- Dark blue — connected to your paired Di2 (the one it locked onto)
- Orange — link lost, retrying

SWITCHING OR FORGETTING A DI2
Riding a different bike, or want to pair with another unit?
1. Open the field settings in Garmin Connect Mobile.
2. Turn on "Forget paired Di2" and save.
3. The field drops the current unit and locks onto the nearest awake Di2 on
   the next scan. The toggle switches itself back off — it's a one-shot button.
To pick a specific Di2 when two are nearby: bring your Edge close to the right
bike (or keep the other Di2 asleep), then use Forget — it grabs the nearest
one that's awake.

FEATURES
- Large, clear rear gear with cassette size (current • total)
- Front chainring indicator
- Configurable drivetrain: pick front chainrings (1–3) and cassette size,
  then enter the teeth of each ring/cog for accurate gear ratios
- D-Fly battery percentage
- Color-coded connection status dot with auto-reconnect
- Day / night color theme
- Six languages: English, French, Spanish, Russian, German, Arabic

RECORDS TO YOUR ACTIVITY (Connect IQ data in Garmin Connect)
- Per-second: rear & front gear, rear & front teeth, gear ratio, D-Fly battery
- Ride summary: average & maximum gear ratio, front & rear shift counts,
  most-used gear combo with time share, top-3 most-used rear sprockets,
  highest rear gear used, lowest D-Fly battery
- Viewable in the Connect IQ section of the activity and any FIT-aware service

REQUIREMENTS
- Shimano Di2 with a D-Fly module (EW-WU111 or SC-M9051) advertising over BLE.

Tested with Shimano XT Di2 RD-M8250-SGS (12-speed) on Garmin Edge Explore 2.

Independent, unofficial app — not affiliated with or endorsed by Shimano.
```

**What's New (0.0.28):** полный список — `CHANGELOG.md`. Текст для поля стора
покрывает всё, что появилось с последнего публичного релиза (0.0.24):
```
New display options and a clearer readout. You can now show the rear gear as
numbers, as a cassette graphic, or both: the graphic draws every sprocket as a
bar — largest on the left, height following the cog sizes — with your current
sprocket highlighted, so you can read your position at a glance. The D-Fly
battery can be shown as a percentage, a colour-coded battery icon, or both; the
icon fills with the charge and turns orange below 40% and red below 15%. The
battery icon and cassette graphic are now on by default, and the settings option
labels are fully translated in all six languages. Plus faster, more efficient
Bluetooth handling under the hood.
```

## Шаг 3 — Изображения
- **Cover Image 500×500** (<300 КБ): `store/cover.png`
- **Screen Images** (<150 КБ): фото экрана Edge с работающим полем
- **Add Icons for Device:** No · **Hero / Preview Video:** опционально

## Шаг 4 — Переключатели
| Поле | Значение |
|---|---|
| Privacy Policy — collect user data? | **No** |
| ANT+ Profiles | **No** |
| Regional Limits | **No** |
| Review Notification | **Yes** |
| App Migration | **No** (тестировано только Edge Explore 2) |
| Monetization | **No** |

## Шаг 5 — Activity Types
**Cycling** (road/gravel/mountain по желанию).

## Шаг 6 — Additional Information
- **Email Address:** публичный контакт (рекомендуется не личный)
- **Source Code URL:** ссылка на репозиторий (если есть), иначе пусто
- **Companion App:** пусто
- **Additional Hardware → Product URL:** опц. ссылка на Shimano D-Fly (EW-WU111)

**Bluetooth permission justification:**
```
Connects to the Shimano D-Fly module to read gear position and battery level.
```

## На что обратить внимание при ревью
- **Торговая марка Shimano:** не подавать как официальное; «unofficial / not affiliated» в описании это закрывает.
- **Версионирование:** следующие апдейты — поднимать `version` в `manifest.xml`, подпись тем же ключом.

---

## Локализованные Title + Description

### 🇫🇷 Français — Title: `Champ Di2`
```
Champ Di2 affiche votre vitesse arrière Shimano Di2 actuelle (p. ex. 5•12) et le
niveau de batterie du module sans fil D-Fly directement sur votre écran de données Edge.

Il se connecte en Bluetooth Low Energy à un module Shimano D-Fly
(EW-WU111 / SC-M9051) — pas besoin d'ANT+.

FONCTIONNALITÉS
- Vitesse arrière grande et lisible avec la taille de cassette (actuelle • totale)
- Indicateur de plateau avant
- Transmission configurable : choisissez les plateaux avant (1–3) et la taille de
  cassette, puis saisissez le nombre de dents de chaque plateau/pignon pour des
  rapports précis
- Pourcentage de batterie D-Fly
- Indicateur de connexion avec reconnexion automatique
- Thème de couleur jour / nuit
- Six langues : anglais, français, espagnol, russe, allemand, arabe

ENREGISTREMENT DANS L'ACTIVITÉ (données Connect IQ dans Garmin Connect)
- Par seconde : vitesse avant et arrière, dents avant et arrière, rapport, batterie D-Fly
- Résumé de sortie : rapport moyen et maximal, nombre de changements avant et arrière,
  combinaison la plus utilisée avec part de temps, top-3 des pignons arrière les plus
  utilisés, plus grande vitesse arrière, batterie D-Fly minimale
- Visible dans la section Connect IQ de l'activité et tout service compatible FIT

PRÉREQUIS
- Shimano Di2 avec un module D-Fly (EW-WU111 ou SC-M9051) diffusant en BLE.

Testé avec Shimano XT Di2 RD-M8250-SGS (12 vitesses) sur Garmin Edge Explore 2.

Application indépendante et non officielle — sans lien ni approbation de Shimano.
```

### 🇪🇸 Español — Title: `Campo Di2`
```
Campo Di2 muestra tu marcha trasera Shimano Di2 actual (p. ej. 5•12) y el nivel
de batería del módulo inalámbrico D-Fly directamente en tu pantalla de datos Edge.

Se conecta por Bluetooth Low Energy a un módulo Shimano D-Fly
(EW-WU111 / SC-M9051) — sin necesidad de ANT+.

CARACTERÍSTICAS
- Marcha trasera grande y clara con el tamaño del cassette (actual • total)
- Indicador de plato delantero
- Transmisión configurable: elige los platos delanteros (1–3) y el tamaño del
  cassette, luego introduce los dientes de cada plato/piñón para relaciones precisas
- Porcentaje de batería D-Fly
- Indicador de conexión con reconexión automática
- Tema de color día / noche
- Seis idiomas: inglés, francés, español, ruso, alemán, árabe

REGISTRO EN LA ACTIVIDAD (datos Connect IQ en Garmin Connect)
- Por segundo: marcha delantera y trasera, dientes delanteros y traseros, relación, batería D-Fly
- Resumen de la ruta: relación media y máxima, número de cambios delanteros y traseros,
  combinación más usada con porcentaje de tiempo, top-3 de piñones traseros más usados,
  marcha trasera más alta, batería D-Fly mínima
- Visible en la sección Connect IQ de la actividad y cualquier servicio compatible con FIT

REQUISITOS
- Shimano Di2 con un módulo D-Fly (EW-WU111 o SC-M9051) emitiendo por BLE.

Probado con Shimano XT Di2 RD-M8250-SGS (12 velocidades) en Garmin Edge Explore 2.

App independiente y no oficial — sin afiliación ni respaldo de Shimano.
```

### 🇷🇺 Русский — Title: `Поле Di2`
```
Поле Di2 показывает текущую заднюю передачу Shimano Di2 (например, 5•12) и заряд
беспроводного модуля D-Fly прямо на экране данных вашего Edge.

Подключается по Bluetooth Low Energy к модулю Shimano D-Fly
(EW-WU111 / SC-M9051) — ANT+ не требуется.

ВОЗМОЖНОСТИ
- Крупная, читаемая задняя передача с размером кассеты (текущая • всего)
- Индикатор передней звезды
- Настраиваемая трансмиссия: выберите число передних звёзд (1–3) и размер кассеты,
  затем введите зубья каждой звезды для точных передаточных отношений
- Процент заряда D-Fly
- Индикатор соединения с автопереподключением
- Дневная / ночная цветовая тема
- Шесть языков: английский, французский, испанский, русский, немецкий, арабский

ЗАПИСЬ В АКТИВНОСТЬ (данные Connect IQ в Garmin Connect)
- Посекундно: передняя и задняя передача, зубья спереди и сзади, передаточное, заряд D-Fly
- Сводка за заезд: среднее и максимальное передаточное, число переключений спереди и сзади,
  самая используемая комбинация с долей времени, топ-3 самых используемых задних звёзд,
  наибольшая задняя передача, минимальный заряд D-Fly
- Видно в разделе Connect IQ активности и в любом сервисе, читающем FIT

ТРЕБОВАНИЯ
- Shimano Di2 с модулем D-Fly (EW-WU111 или SC-M9051), вещающим по BLE.

Протестировано на Shimano XT Di2 RD-M8250-SGS (12 скоростей) на Garmin Edge Explore 2.

Независимое неофициальное приложение — не связано с Shimano и не одобрено ею.
```

### 🇩🇪 Deutsch — Title: `Di2 Feld`
```
Di2 Feld zeigt deinen aktuellen Shimano Di2 Gang hinten (z. B. 5•12) und den
Akkustand des kabellosen D-Fly Moduls direkt auf deinem Edge-Datenbildschirm.

Es verbindet sich per Bluetooth Low Energy mit einem Shimano D-Fly Modul
(EW-WU111 / SC-M9051) — kein ANT+ nötig.

FUNKTIONEN
- Großer, klarer Gang hinten mit Kassettengröße (aktuell • gesamt)
- Anzeige des vorderen Kettenblatts
- Konfigurierbarer Antrieb: wähle die vorderen Kettenblätter (1–3) und die
  Kassettengröße, dann gib die Zähnezahl jedes Blatts/Ritzels für genaue
  Übersetzungen ein
- D-Fly Akkustand in Prozent
- Verbindungsanzeige mit automatischer Wiederverbindung
- Tag-/Nacht-Farbschema
- Sechs Sprachen: Englisch, Französisch, Spanisch, Russisch, Deutsch, Arabisch

AUFZEICHNUNG IN DER AKTIVITÄT (Connect IQ Daten in Garmin Connect)
- Pro Sekunde: Gang vorne und hinten, Zähne vorne und hinten, Übersetzung, D-Fly Akku
- Fahrt-Zusammenfassung: durchschnittliche und maximale Übersetzung, Anzahl der
  Schaltvorgänge vorne und hinten, häufigste Kombination mit Zeitanteil, Top-3 der
  meistgenutzten hinteren Ritzel, höchster Gang hinten, niedrigster D-Fly Akku
- Sichtbar im Connect IQ Bereich der Aktivität und in jedem FIT-fähigen Dienst

VORAUSSETZUNGEN
- Shimano Di2 mit einem D-Fly Modul (EW-WU111 oder SC-M9051), das über BLE sendet.

Getestet mit Shimano XT Di2 RD-M8250-SGS (12-fach) auf Garmin Edge Explore 2.

Unabhängige, inoffizielle App — nicht mit Shimano verbunden oder unterstützt.
```

### 🇸🇦 العربية — Title: `حقل Di2`
```
يعرض حقل Di2 سرعتك الخلفية الحالية من Shimano Di2 (مثل 5•12) ومستوى بطارية وحدة
D-Fly اللاسلكية مباشرة على شاشة بيانات جهاز Edge.

يتصل عبر Bluetooth Low Energy بوحدة Shimano D-Fly
(EW-WU111 / SC-M9051) — دون الحاجة إلى ANT+.

الميزات
- سرعة خلفية كبيرة وواضحة مع حجم الكاسيت (الحالية • الإجمالي)
- مؤشر النجمة الأمامية
- مجموعة نقل قابلة للضبط: اختر النجوم الأمامية (1–3) وحجم الكاسيت، ثم أدخل عدد
  أسنان كل نجمة/ترس للحصول على نسب دقيقة
- نسبة بطارية D-Fly
- مؤشر الاتصال مع إعادة اتصال تلقائية
- سمة ألوان نهارية / ليلية
- ست لغات: الإنجليزية، الفرنسية، الإسبانية، الروسية، الألمانية، العربية

التسجيل في النشاط (بيانات Connect IQ في Garmin Connect)
- كل ثانية: السرعة الأمامية والخلفية، الأسنان الأمامية والخلفية، النسبة، بطارية D-Fly
- ملخص الرحلة: متوسط وأقصى نسبة، عدد التبديلات الأمامية والخلفية، أكثر تركيبة استخداماً
  مع نسبة الوقت، أفضل 3 تروس خلفية استخداماً، أعلى سرعة خلفية، أدنى بطارية D-Fly
- يظهر في قسم Connect IQ للنشاط وفي أي خدمة تدعم FIT

المتطلبات
- نظام Shimano Di2 مع وحدة D-Fly (EW-WU111 أو SC-M9051) تبث عبر BLE.

تم اختباره مع Shimano XT Di2 RD-M8250-SGS (12 سرعة) على Garmin Edge Explore 2.

تطبيق مستقل غير رسمي — غير مرتبط بشركة Shimano أو معتمد منها.
```
