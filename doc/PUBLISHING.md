# Публикация в Connect IQ Store

Полный гайд по выкладке Di2 Field. Версия — источник истины `manifest.xml` → `version`.

## App ID и ветки

Beta и публичная версии — РАЗНЫЕ app id (требование Garmin). Различие вынесено в ветки.

| Ветка | App ID | launcherIcon | AppName | Назначение |
|---|---|---|---|---|
| **main** | `a46118db030d4d489268501a3e80547d` | `@Drawables.LauncherIconBeta` | `… Beta` (суффикс во всех локалях) | beta — разработка, «Upload New Version» в beta-приложение |
| **prod** | `a7fea1a873694f3ba5c27c4312b4062a` | `@Drawables.LauncherIcon` | без суффикса | публичный релиз — загрузка БЕЗ галочки Beta |

Расхождения beta↔prod (что правится при мердже main→prod):

1. `manifest.xml`, строка `<iq:application>`: атрибуты `id` И `launcherIcon`
   (бета-иконка с оранжевым уголком vs обычная) — даёт git-конфликт, оставить prod-значения.
2. **`AppName` в strings.xml** (6 локалей: `resources*/strings.xml`): на main суффикс
   ` Beta` (`Di2 Field Beta`, `Поле Di2 Beta`, …), в prod — без него.
   ⚠️ КОНФЛИКТА git НЕ будет (строки одинаковы в обеих ветках) → **легко забыть**.
   Перед сборкой prod вручную убрать ` Beta`/` Beta` из `AppName` во всех 6 файлах.

Оба drawable (`LauncherIcon`, `LauncherIconBeta`) есть на обеих ветках — отличается
только ссылка в manifest.

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
# ВРУЧНУЮ: убрать суффикс " Beta" из AppName во всех 6 resources*/strings.xml
# (git-конфликта тут НЕТ — строки одинаковы, легко пропустить)
./build.sh store           # -> bin/Di2App.iq с публичным id, обычной иконкой и без "Beta"
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
Di2 Field shows your current Di2 (tested with RD-M8250-SGS 12-speed) rear gear
(e.g. 5•12) and the wireless unit battery level right on your Edge data screen.

It connects over Bluetooth Low Energy — no ANT+ needed.

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

SETTING UP YOUR DRIVETRAIN
For correct gears and ratios, tell the field your gearing — two ways:
- Preset (easiest): pick a built-in Shimano preset for the chainrings and the
  cassette (e.g. 50-34, 11-34, 10-51). It sets your gearing in one tap.
- Manual: set the preset to Custom, then choose the chainring count (1–3) and
  cassette size and enter the teeth of each ring and cog (comma-separated, one
  value per gear, from smallest to largest).
While a preset is selected it takes over the chainring count and teeth — the
manual fields keep their own values and are used only when the preset is Custom.
Note: the settings screen won't copy a preset's numbers into those fields, and
the prompt under each setting may not show on iOS — that's a Garmin Connect
display limitation, not a problem with your setup.

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
- Rear gear as numbers, a cassette graphic, or both
- Built-in Shimano presets for popular chainrings and cassettes
  (10/11/12-speed), or enter your own teeth for any drivetrain
- Battery percentage or a color-coded battery icon
- Color-coded connection status dot with auto-reconnect
- Automatic Di2 model detection
- On-screen diagnostics overlay to help troubleshoot connection
- Day / night color theme
- Six languages: English, French, Spanish, Russian, German, Arabic

RECORDS TO YOUR ACTIVITY (Connect IQ data in Garmin Connect)
- Per-second: rear & front gear, rear & front teeth, gear ratio, battery
- Ride summary: average & maximum gear ratio, front & rear shift counts,
  most-used gear combo with time share, top-3 most-used rear sprockets,
  highest rear gear used, lowest battery
- Viewable in the Connect IQ section of the activity and any FIT-aware service

REQUIREMENTS
- Shimano Di2 advertising over BLE.

Confirmed on Shimano XT Di2 RD-M8250-SGS (12-speed) with Garmin Edge Explore 2.
Other Di2 series that broadcast the same BLE data may also work — the field
detects the model, and the diagnostics overlay helps add support for new ones.

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
Connects to your Shimano Di2 to read gear position and battery level.
```

## На что обратить внимание при ревью
- **Торговая марка Shimano:** не подавать как официальное; «unofficial / not affiliated» в описании это закрывает.
- **Версионирование:** следующие апдейты — поднимать `version` в `manifest.xml`, подпись тем же ключом.

---

## Локализованные Title + Description

### 🇫🇷 Français — Title: `Champ Di2`
```
Champ Di2 affiche votre vitesse arrière Di2 actuelle (testé avec RD-M8250-SGS
12 vitesses, p. ex. 5•12) et le niveau de batterie du module sans fil
directement sur votre écran de données Edge.

Il se connecte en Bluetooth Low Energy — pas besoin d'ANT+.

CONFIGURER VOTRE TRANSMISSION
Pour des vitesses et rapports corrects, indiquez votre transmission — deux façons :
- Préréglage (le plus simple) : choisissez un préréglage Shimano intégré pour les
  plateaux et la cassette (p. ex. 50-34, 11-34, 10-51). Il règle tout en un geste.
- Manuel : réglez le préréglage sur Personnalisé, puis choisissez le nombre de
  plateaux (1–3) et la taille de cassette et saisissez les dents de chaque plateau
  et pignon (séparées par des virgules, une par vitesse, de la plus petite à la
  plus grande).
Tant qu'un préréglage est sélectionné, il prend le dessus sur le nombre de plateaux
et les dents — les champs manuels gardent leurs valeurs et ne servent que si le
préréglage est sur Personnalisé. Remarque : l'écran de réglages ne recopie pas les
valeurs d'un préréglage dans ces champs, et l'aide sous chaque réglage peut ne pas
s'afficher sur iOS — c'est une limite d'affichage de Garmin Connect, pas un problème
de votre configuration.

FONCTIONNALITÉS
- Vitesse arrière grande et lisible avec la taille de cassette (actuelle • totale)
- Indicateur de plateau avant
- Vitesse arrière en chiffres, en graphique de cassette, ou les deux
- Préréglages Shimano intégrés pour plateaux et cassettes courants
  (10/11/12 vitesses), ou saisissez vos propres dents pour toute transmission
- Pourcentage de batterie ou icône de batterie colorée
- Indicateur de connexion avec reconnexion automatique
- Détection automatique du modèle Di2
- Superposition de diagnostic à l'écran pour résoudre les problèmes de connexion
- Thème de couleur jour / nuit
- Six langues : anglais, français, espagnol, russe, allemand, arabe

ENREGISTREMENT DANS L'ACTIVITÉ (données Connect IQ dans Garmin Connect)
- Par seconde : vitesse avant et arrière, dents avant et arrière, rapport, batterie
- Résumé de sortie : rapport moyen et maximal, nombre de changements avant et arrière,
  combinaison la plus utilisée avec part de temps, top-3 des pignons arrière les plus
  utilisés, plus grande vitesse arrière, batterie minimale
- Visible dans la section Connect IQ de l'activité et tout service compatible FIT

PRÉREQUIS
- Shimano Di2 diffusant en BLE.

Confirmé avec Shimano XT Di2 RD-M8250-SGS (12 vitesses) sur Garmin Edge Explore 2.
D'autres séries Di2 diffusant les mêmes données BLE peuvent aussi fonctionner — le
champ détecte le modèle, et la superposition de diagnostic aide à prendre en charge
de nouveaux modèles.

Application indépendante et non officielle — sans lien ni approbation de Shimano.
```

### 🇪🇸 Español — Title: `Campo Di2`
```
Campo Di2 muestra tu marcha trasera Di2 actual (probado con RD-M8250-SGS
12 velocidades, p. ej. 5•12) y el nivel de batería del módulo inalámbrico
directamente en tu pantalla de datos Edge.

Se conecta por Bluetooth Low Energy — sin necesidad de ANT+.

CONFIGURAR TU TRANSMISIÓN
Para marchas y relaciones correctas, indica tu transmisión — dos formas:
- Preajuste (lo más fácil): elige un preajuste Shimano integrado para los platos
  y el cassette (p. ej. 50-34, 11-34, 10-51). Lo configura todo con un toque.
- Manual: pon el preajuste en Personalizado, luego elige el número de platos (1–3)
  y el tamaño del cassette e introduce los dientes de cada plato y piñón (separados
  por comas, uno por marcha, de menor a mayor).
Mientras hay un preajuste seleccionado, prevalece sobre el número de platos y los
dientes — los campos manuales conservan sus valores y solo se usan si el preajuste
está en Personalizado. Nota: la pantalla de ajustes no copia los valores de un
preajuste en esos campos, y la ayuda bajo cada ajuste puede no mostrarse en iOS —
es una limitación de Garmin Connect, no un problema de tu configuración.

CARACTERÍSTICAS
- Marcha trasera grande y clara con el tamaño del cassette (actual • total)
- Indicador de plato delantero
- Marcha trasera en números, en gráfico de cassette, o ambos
- Preajustes Shimano integrados para platos y cassettes comunes
  (10/11/12 velocidades), o introduce tus propios dientes para cualquier transmisión
- Porcentaje de batería o icono de batería con color
- Indicador de conexión con reconexión automática
- Detección automática del modelo Di2
- Superposición de diagnóstico en pantalla para resolver problemas de conexión
- Tema de color día / noche
- Seis idiomas: inglés, francés, español, ruso, alemán, árabe

REGISTRO EN LA ACTIVIDAD (datos Connect IQ en Garmin Connect)
- Por segundo: marcha delantera y trasera, dientes delanteros y traseros, relación, batería
- Resumen de la ruta: relación media y máxima, número de cambios delanteros y traseros,
  combinación más usada con porcentaje de tiempo, top-3 de piñones traseros más usados,
  marcha trasera más alta, batería mínima
- Visible en la sección Connect IQ de la actividad y cualquier servicio compatible con FIT

REQUISITOS
- Shimano Di2 emitiendo por BLE.

Confirmado con Shimano XT Di2 RD-M8250-SGS (12 velocidades) en Garmin Edge Explore 2.
Otras series Di2 que emitan los mismos datos BLE también pueden funcionar — el campo
detecta el modelo, y la superposición de diagnóstico ayuda a añadir compatibilidad
con nuevos modelos.

App independiente y no oficial — sin afiliación ni respaldo de Shimano.
```

### 🇷🇺 Русский — Title: `Поле Di2`
```
Поле Di2 показывает текущую заднюю передачу Di2 (протестировано на RD-M8250-SGS
12 скоростей, например 5•12) и заряд беспроводного модуля прямо на экране данных
вашего Edge.

Подключается по Bluetooth Low Energy — ANT+ не требуется.

НАСТРОЙКА ТРАНСМИССИИ
Чтобы передачи и отношения были верными, укажите трансмиссию — два способа:
- Пресет (проще всего): выберите встроенный пресет Shimano для звёзд и кассеты
  (например, 50-34, 11-34, 10-51). Он задаёт всё в одно касание.
- Вручную: поставьте пресет «Свой», затем выберите число передних звёзд (1–3)
  и размер кассеты и введите зубья каждой звезды (через запятую, по одному
  значению на передачу, от меньшей к большей).
Пока выбран пресет, он имеет приоритет над числом звёзд и зубьями — ручные поля
сохраняют свои значения и используются только при пресете «Свой». Примечание:
экран настроек не копирует значения пресета в эти поля, а подсказки под каждым
пунктом могут не отображаться на iOS — это ограничение Garmin Connect, а не
проблема вашей настройки.

ВОЗМОЖНОСТИ
- Крупная, читаемая задняя передача с размером кассеты (текущая • всего)
- Индикатор передней звезды
- Задняя передача цифрами, графиком кассеты или вместе
- Встроенные пресеты Shimano для популярных звёзд и кассет
  (10/11/12 скоростей) или ввод своих зубьев для любой трансмиссии
- Процент заряда или цветная иконка батареи
- Индикатор соединения с автопереподключением
- Автоматическое распознавание модели Di2
- Экранный диагностический оверлей для разбора проблем подключения
- Дневная / ночная цветовая тема
- Шесть языков: английский, французский, испанский, русский, немецкий, арабский

ЗАПИСЬ В АКТИВНОСТЬ (данные Connect IQ в Garmin Connect)
- Посекундно: передняя и задняя передача, зубья спереди и сзади, передаточное, заряд
- Сводка за заезд: среднее и максимальное передаточное, число переключений спереди и сзади,
  самая используемая комбинация с долей времени, топ-3 самых используемых задних звёзд,
  наибольшая задняя передача, минимальный заряд
- Видно в разделе Connect IQ активности и в любом сервисе, читающем FIT

ТРЕБОВАНИЯ
- Shimano Di2, вещающий по BLE.

Подтверждено на Shimano XT Di2 RD-M8250-SGS (12 скоростей) с Garmin Edge Explore 2.
Другие серии Di2, вещающие те же BLE-данные, тоже могут работать — поле распознаёт
модель, а диагностический оверлей помогает добавить поддержку новых.

Независимое неофициальное приложение — не связано с Shimano и не одобрено ею.
```

### 🇩🇪 Deutsch — Title: `Di2 Feld`
```
Di2 Feld zeigt deinen aktuellen Di2 Gang hinten (getestet mit RD-M8250-SGS
12-fach, z. B. 5•12) und den Akkustand des kabellosen Moduls direkt auf deinem
Edge-Datenbildschirm.

Es verbindet sich per Bluetooth Low Energy — kein ANT+ nötig.

ANTRIEB EINRICHTEN
Für korrekte Gänge und Übersetzungen gib deinen Antrieb an — zwei Wege:
- Vorlage (am einfachsten): wähle eine integrierte Shimano-Vorlage für Kettenblätter
  und Kassette (z. B. 50-34, 11-34, 10-51). Sie stellt alles mit einem Tippen ein.
- Manuell: stelle die Vorlage auf „Benutzerdefiniert“, dann wähle die Anzahl der
  Kettenblätter (1–3) und die Kassettengröße und gib die Zähne jedes Blatts und
  Ritzels ein (durch Komma getrennt, ein Wert pro Gang, vom kleinsten zum größten).
Solange eine Vorlage gewählt ist, hat sie Vorrang vor Kettenblattanzahl und Zähnen —
die manuellen Felder behalten ihre Werte und gelten nur bei „Benutzerdefiniert“.
Hinweis: der Einstellungsbildschirm kopiert die Werte einer Vorlage nicht in diese
Felder, und der Hinweistext unter jeder Einstellung wird auf iOS evtl. nicht
angezeigt — eine Anzeigegrenze von Garmin Connect, kein Problem deiner Einrichtung.

FUNKTIONEN
- Großer, klarer Gang hinten mit Kassettengröße (aktuell • gesamt)
- Anzeige des vorderen Kettenblatts
- Gang hinten als Zahlen, als Kassettengrafik oder beides
- Integrierte Shimano-Vorlagen für gängige Kettenblätter und Kassetten
  (10/11/12-fach), oder gib eigene Zähne für jeden Antrieb ein
- Akkustand in Prozent oder farbcodiertes Akkusymbol
- Verbindungsanzeige mit automatischer Wiederverbindung
- Automatische Erkennung des Di2 Modells
- Diagnose-Overlay auf dem Bildschirm zur Behebung von Verbindungsproblemen
- Tag-/Nacht-Farbschema
- Sechs Sprachen: Englisch, Französisch, Spanisch, Russisch, Deutsch, Arabisch

AUFZEICHNUNG IN DER AKTIVITÄT (Connect IQ Daten in Garmin Connect)
- Pro Sekunde: Gang vorne und hinten, Zähne vorne und hinten, Übersetzung, Akku
- Fahrt-Zusammenfassung: durchschnittliche und maximale Übersetzung, Anzahl der
  Schaltvorgänge vorne und hinten, häufigste Kombination mit Zeitanteil, Top-3 der
  meistgenutzten hinteren Ritzel, höchster Gang hinten, niedrigster Akku
- Sichtbar im Connect IQ Bereich der Aktivität und in jedem FIT-fähigen Dienst

VORAUSSETZUNGEN
- Shimano Di2, das über BLE sendet.

Bestätigt mit Shimano XT Di2 RD-M8250-SGS (12-fach) auf Garmin Edge Explore 2.
Andere Di2 Serien, die dieselben BLE-Daten senden, können ebenfalls funktionieren —
das Feld erkennt das Modell, und das Diagnose-Overlay hilft, neue Modelle zu
unterstützen.

Unabhängige, inoffizielle App — nicht mit Shimano verbunden oder unterstützt.
```

### 🇸🇦 العربية — Title: `حقل Di2`
```
يعرض حقل Di2 سرعتك الخلفية الحالية من Di2 (تم اختباره مع RD-M8250-SGS بـ 12 سرعة،
مثل 5•12) ومستوى بطارية الوحدة اللاسلكية مباشرة على شاشة بيانات جهاز Edge.

يتصل عبر Bluetooth Low Energy — دون الحاجة إلى ANT+.

إعداد مجموعة النقل
للحصول على سرعات ونسب صحيحة، حدّد مجموعة النقل — بطريقتين:
- إعداد مسبق (الأسهل): اختر إعداداً مسبقاً من Shimano للنجوم الأمامية والكاسيت
  (مثل 50-34، 11-34، 10-51). يضبط كل شيء بلمسة واحدة.
- يدوي: اضبط الإعداد المسبق على مخصص، ثم اختر عدد النجوم الأمامية (1–3) وحجم
  الكاسيت وأدخل أسنان كل نجمة وترس (مفصولة بفواصل، قيمة لكل سرعة، من الأصغر للأكبر).
طالما أن إعداداً مسبقاً مختار، فإنه يتجاوز عدد النجوم والأسنان — تحتفظ الحقول اليدوية
بقيمها وتُستخدم فقط عندما يكون الإعداد المسبق مخصصاً. ملاحظة: لا تنسخ شاشة الإعدادات
قيم الإعداد المسبق إلى تلك الحقول، وقد لا يظهر النص الإرشادي أسفل كل إعداد على iOS —
هذا قيد عرض في Garmin Connect، وليس مشكلة في إعدادك.

الميزات
- سرعة خلفية كبيرة وواضحة مع حجم الكاسيت (الحالية • الإجمالي)
- مؤشر النجمة الأمامية
- السرعة الخلفية بالأرقام، أو كرسم للكاسيت، أو كليهما
- إعدادات Shimano المسبقة للنجوم والكاسيتات الشائعة
  (10/11/12 سرعة)، أو أدخل أسنانك الخاصة لأي مجموعة نقل
- نسبة البطارية أو أيقونة بطارية ملونة
- مؤشر الاتصال مع إعادة اتصال تلقائية
- كشف تلقائي لطراز Di2
- طبقة تشخيص على الشاشة للمساعدة في حل مشكلات الاتصال
- سمة ألوان نهارية / ليلية
- ست لغات: الإنجليزية، الفرنسية، الإسبانية، الروسية، الألمانية، العربية

التسجيل في النشاط (بيانات Connect IQ في Garmin Connect)
- كل ثانية: السرعة الأمامية والخلفية، الأسنان الأمامية والخلفية، النسبة، البطارية
- ملخص الرحلة: متوسط وأقصى نسبة، عدد التبديلات الأمامية والخلفية، أكثر تركيبة استخداماً
  مع نسبة الوقت، أفضل 3 تروس خلفية استخداماً، أعلى سرعة خلفية، أدنى بطارية
- يظهر في قسم Connect IQ للنشاط وفي أي خدمة تدعم FIT

المتطلبات
- نظام Shimano Di2 يبث عبر BLE.

تم التأكيد مع Shimano XT Di2 RD-M8250-SGS (12 سرعة) على Garmin Edge Explore 2.
قد تعمل أيضاً سلاسل Di2 أخرى تبث نفس بيانات BLE — يكتشف الحقل الطراز، وتساعد طبقة
التشخيص في إضافة دعم لطُرز جديدة.

تطبيق مستقل غير رسمي — غير مرتبط بشركة Shimano أو معتمد منها.
```
