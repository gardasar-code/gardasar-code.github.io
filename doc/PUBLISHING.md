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
Di2 Field puts your current Di2 rear gear (e.g. 5•12) and the wireless unit
battery level on your Edge data screen. It connects over Bluetooth Low Energy —
no ANT+ needed.

There is no button to press: add the field to a data screen, tap any shifter to
wake the Di2, and the field finds it and connects on its own. It then sticks to
that unit and reconnects automatically on every ride. A colour-coded dot shows
the state: blue searching, yellow connecting, green connected, dark blue locked
onto your Di2, orange retrying.

WHAT IT SHOWS
- Rear gear as large numbers, a cassette graphic, or both
- Front chainring indicator for 2x/3x
- Di2 battery as a percentage, a colour-coded icon, or both
- Day / night theme, six languages (EN, FR, ES, RU, DE, AR)

SETTING UP YOUR DRIVETRAIN
Pick a built-in Shimano preset for your chainrings and cassette (e.g. 50-34,
11-34, 10-51), or choose Custom and enter the teeth by hand.

RECORDS TO YOUR ACTIVITY
Per-second gear, teeth, ratio and battery, plus a ride summary: highest rear
gear, maximum ratio, lowest battery and shift counts. Visible in the Connect IQ
section of the activity.

SWITCHING BIKES
Turn on "Forget paired Di2" in the field settings — the field drops the current
unit and locks onto the nearest awake Di2 on the next scan.

TESTED SETUP
Built and tested on my own bike: Shimano XT Di2 RD-M8250-SGS (12-speed) with a
Garmin Edge Explore 2. Other Di2 series that broadcast the same Bluetooth data
should work too, but I cannot verify them myself.

IF SOMETHING DOESN'T WORK
Turn on "Diagnostics overlay" in the field settings. The field then shows a
technical screen instead of the normal layout — connection state, the detected
model and the raw data from your Di2. Send me a photo of that screen and I can
tell what is happening on your setup, and often add support for it.

Known issue: on Edge Explore 2 firmware 31.33 the device itself refuses to
register the Bluetooth service the Di2 uses, so no third-party app can read
gears (the battery still works). Reported to Garmin and acknowledged
(CIQQA-4662), waiting for a firmware fix. Firmware 30.23 is unaffected.

Independent, unofficial app — not affiliated with or endorsed by Shimano.
```

**What's New (0.0.34):** полный список — `CHANGELOG.md`. Текст для поля стора
покрывает всё, что появилось с последнего публичного релиза (0.0.28):
```
Faster setup and broader Di2 support.

- Drivetrain presets: pick a common Shimano chainring or cassette setup
  (e.g. 50-34, 11-34, 10-51) instead of typing every tooth count. While a
  preset is selected it sets your gearing; choose Custom to enter values by hand.
- Automatic Di2 model detection, with the groundwork to support more Di2
  series beyond the tested XT M8250.
- New full-screen diagnostics mode (a setting): shows connection state, signal,
  the detected model and the raw data — turn it on and send a photo if a
  connection issue comes up.
- Clearer in-store setup guidance and reliability fixes under the hood.
```

> Предыдущий публичный What's New (0.0.28): новые варианты показа передачи
> (цифры / график кассеты / оба) и батареи (процент / иконка / оба), полная
> локализация меток настроек, ускоренный BLE.

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
Champ Di2 affiche votre vitesse arrière Di2 actuelle (p. ex. 5•12) et le niveau
de batterie du module sans fil sur votre écran de données Edge. La liaison se
fait en Bluetooth Low Energy — pas besoin d'ANT+.

Aucun bouton à presser : ajoutez le champ à un écran de données, réveillez le
Di2 en actionnant une manette, et le champ le trouve et s'y connecte tout seul.
Il reste ensuite attaché à ce module et se reconnecte à chaque sortie. Un point
coloré indique l'état : bleu recherche, jaune connexion, vert connecté, bleu
foncé attaché à votre Di2, orange nouvelle tentative.

CE QUE VOUS VOYEZ
- Vitesse arrière en grands chiffres, en graphique de cassette, ou les deux
- Indicateur de plateau avant pour 2x/3x
- Batterie Di2 en pourcentage, en icône colorée, ou les deux
- Thème jour / nuit, six langues (EN, FR, ES, RU, DE, AR)

CONFIGURER VOTRE TRANSMISSION
Choisissez un préréglage Shimano intégré pour les plateaux et la cassette
(p. ex. 50-34, 11-34, 10-51), ou sélectionnez Personnalisé et saisissez les
dents à la main.

ENREGISTREMENT DANS L'ACTIVITÉ
Vitesses, dents, rapport et batterie chaque seconde, plus un résumé : plus
grande vitesse arrière, rapport maximal, batterie minimale et nombre de
changements. Visible dans la section Connect IQ de l'activité.

CHANGER DE VÉLO
Activez « Oublier le Di2 associé » dans les réglages du champ : il abandonne le
module actuel et s'attache au Di2 éveillé le plus proche au scan suivant.

CONFIGURATION TESTÉE
Développé et testé sur mon propre vélo : Shimano XT Di2 RD-M8250-SGS
(12 vitesses) avec un Garmin Edge Explore 2. D'autres séries Di2 diffusant les
mêmes données Bluetooth devraient fonctionner, mais je ne peux pas les vérifier
moi-même.

SI QUELQUE CHOSE NE FONCTIONNE PAS
Activez « Superposition de diagnostic » dans les réglages du champ. Le champ
affiche alors un écran technique à la place de l'affichage normal : état de la
liaison, modèle détecté et données brutes de votre Di2. Envoyez-moi une photo
de cet écran et je pourrai voir ce qui se passe sur votre installation, et
souvent ajouter la prise en charge.

Problème connu : sur le firmware 31.33 de l'Edge Explore 2, l'appareil refuse
d'enregistrer le service Bluetooth utilisé par le Di2 — aucune application
tierce ne peut lire les vitesses (la batterie reste affichée). Signalé à Garmin
et pris en compte (CIQQA-4662), correctif firmware en attente. Le firmware
30.23 n'est pas concerné.

Application indépendante et non officielle — non affiliée à Shimano.
```

### 🇪🇸 Español — Title: `Campo Di2`
```
Campo Di2 muestra tu marcha trasera Di2 actual (p. ej. 5•12) y el nivel de
batería del módulo inalámbrico en la pantalla de datos de tu Edge. Se conecta
por Bluetooth Low Energy — sin ANT+.

No hay ningún botón que pulsar: añade el campo a una pantalla de datos,
despierta el Di2 accionando cualquier maneta y el campo lo encuentra y se
conecta solo. Después se queda con esa unidad y se reconecta en cada salida. Un
punto de color indica el estado: azul buscando, amarillo conectando, verde
conectado, azul oscuro fijado a tu Di2, naranja reintentando.

QUÉ MUESTRA
- Marcha trasera en números grandes, gráfico de cassette, o ambos
- Indicador de plato delantero para 2x/3x
- Batería Di2 en porcentaje, icono de color, o ambos
- Tema día / noche, seis idiomas (EN, FR, ES, RU, DE, AR)

CONFIGURAR TU TRANSMISIÓN
Elige un preajuste Shimano integrado para platos y cassette (p. ej. 50-34,
11-34, 10-51), o selecciona Personalizado e introduce los dientes a mano.

REGISTRO EN LA ACTIVIDAD
Marchas, dientes, relación y batería cada segundo, más un resumen: marcha
trasera más alta, relación máxima, batería mínima y número de cambios. Visible
en la sección Connect IQ de la actividad.

CAMBIAR DE BICICLETA
Activa «Olvidar Di2 emparejado» en los ajustes del campo: suelta la unidad
actual y se fija al Di2 despierto más cercano en el siguiente escaneo.

CONFIGURACIÓN PROBADA
Desarrollado y probado en mi propia bici: Shimano XT Di2 RD-M8250-SGS
(12 velocidades) con un Garmin Edge Explore 2. Otras series Di2 que emitan los
mismos datos Bluetooth deberían funcionar, pero no puedo comprobarlas yo mismo.

SI ALGO NO FUNCIONA
Activa «Superposición de diagnóstico» en los ajustes del campo. El campo
mostrará una pantalla técnica en lugar del diseño normal: estado de la
conexión, modelo detectado y datos en bruto de tu Di2. Envíame una foto de esa
pantalla y podré ver qué ocurre en tu equipo, y a menudo añadir compatibilidad.

Problema conocido: con el firmware 31.33 del Edge Explore 2 el propio
dispositivo se niega a registrar el servicio Bluetooth que usa el Di2, así que
ninguna app de terceros puede leer las marchas (la batería sigue funcionando).
Reportado a Garmin y aceptado (CIQQA-4662), a la espera de la corrección del
firmware. El firmware 30.23 no está afectado.

Aplicación independiente y no oficial — no afiliada a Shimano.
```

### 🇷🇺 Русский — Title: `Поле Di2`
```
Поле Di2 показывает текущую заднюю передачу Di2 (например, 5•12) и заряд
беспроводного модуля прямо на экране данных Edge. Связь по Bluetooth Low
Energy — ANT+ не нужен.

Нажимать нечего: добавьте поле на экран данных, разбудите Di2 щелчком любой
манетки — поле само его найдёт и подключится. Дальше оно «прилипает» к этому
модулю и переподключается к нему каждую поездку. Цветная точка показывает
состояние: синяя — поиск, жёлтая — подключение, зелёная — связь есть,
тёмно-синяя — привязка к вашему Di2, оранжевая — переподключение.

ЧТО ПОКАЗЫВАЕТ
- Задняя передача крупными цифрами, графиком кассеты или и тем, и другим
- Индикатор передней звезды для 2x/3x
- Заряд Di2 процентом, цветной иконкой или и тем, и другим
- Дневная / ночная тема, шесть языков (EN, FR, ES, RU, DE, AR)

НАСТРОЙКА ТРАНСМИССИИ
Выберите готовый пресет Shimano для звёзд и кассеты (например, 50-34, 11-34,
10-51) либо режим Custom и введите зубья вручную.

ЗАПИСЬ В АКТИВНОСТЬ
Передачи, зубья, передаточное и заряд каждую секунду, плюс сводка: наибольшая
задняя передача, максимальное передаточное, минимальный заряд и число
переключений. Видно в разделе Connect IQ в активности.

СМЕНА ВЕЛОСИПЕДА
Включите «Забыть привязанный Di2» в настройках поля — оно отпустит текущий
модуль и привяжется к ближайшему проснувшемуся Di2 при следующем скане.

НА ЧЁМ ПРОВЕРЕНО
Сделано и протестировано на моём собственном велосипеде: Shimano XT Di2
RD-M8250-SGS (12 скоростей) и Garmin Edge Explore 2. Другие серии Di2, которые
вещают те же данные по Bluetooth, скорее всего тоже работают, но проверить их
сам я не могу.

ЕСЛИ ЧТО-ТО НЕ РАБОТАЕТ
Включите «Диагностический режим» в настройках поля. Вместо обычного макета
поле покажет технический экран: состояние связи, распознанную модель и сырые
данные от вашего Di2. Пришлите мне фото этого экрана — по нему видно, что
происходит именно у вас, и часто это позволяет добавить поддержку.

Известная проблема: на прошивке Edge Explore 2 31.33 сам навигатор отказывается
регистрировать Bluetooth-сервис, который использует Di2, поэтому ни одно
стороннее приложение не может читать передачи (заряд при этом работает).
Передано в Garmin и принято (CIQQA-4662), ждём исправления прошивки. Прошивки
30.23 это не касается.

Независимое, неофициальное приложение — не связано с Shimano.
```

### 🇩🇪 Deutsch — Title: `Di2 Feld`
```
Di2 Feld zeigt deinen aktuellen Di2-Gang hinten (z. B. 5•12) und den Akkustand
der Funkeinheit direkt auf dem Datenbildschirm deines Edge. Die Verbindung läuft
über Bluetooth Low Energy — kein ANT+ nötig.

Es gibt keinen Knopf: Feld auf einen Datenbildschirm legen, Di2 mit einem
Schalthebel wecken — das Feld findet ihn und verbindet sich von selbst. Danach
bleibt es bei dieser Einheit und verbindet sich bei jeder Fahrt automatisch neu.
Ein farbiger Punkt zeigt den Zustand: blau sucht, gelb verbindet, grün
verbunden, dunkelblau an deinen Di2 gebunden, orange erneuter Versuch.

WAS ES ANZEIGT
- Gang hinten als große Zahlen, als Kassettengrafik oder beides
- Kettenblatt-Anzeige für 2x/3x
- Di2-Akku als Prozentwert, als farbiges Symbol oder beides
- Tag- / Nacht-Design, sechs Sprachen (EN, FR, ES, RU, DE, AR)

ANTRIEB EINRICHTEN
Wähle eine eingebaute Shimano-Voreinstellung für Kettenblätter und Kassette
(z. B. 50-34, 11-34, 10-51) oder Custom und trage die Zähnezahlen selbst ein.

AUFZEICHNUNG IN DIE AKTIVITÄT
Gänge, Zähne, Übersetzung und Akku im Sekundentakt, dazu eine Zusammenfassung:
größter Gang hinten, maximale Übersetzung, niedrigster Akkustand und
Schaltvorgänge. Sichtbar im Connect-IQ-Bereich der Aktivität.

RAD WECHSELN
Aktiviere „Gekoppelten Di2 vergessen" in den Feldeinstellungen — das Feld gibt
die aktuelle Einheit frei und bindet sich beim nächsten Scan an den nächsten
wachen Di2.

GETESTETE KONFIGURATION
Entwickelt und getestet an meinem eigenen Rad: Shimano XT Di2 RD-M8250-SGS
(12-fach) mit einem Garmin Edge Explore 2. Andere Di2-Serien, die dieselben
Bluetooth-Daten senden, sollten ebenfalls funktionieren — überprüfen kann ich
sie selbst aber nicht.

WENN ETWAS NICHT FUNKTIONIERT
Aktiviere „Diagnose-Overlay" in den Feldeinstellungen. Das Feld zeigt dann statt
der normalen Ansicht einen technischen Bildschirm: Verbindungszustand, erkanntes
Modell und Rohdaten deines Di2. Schick mir ein Foto davon — daran sehe ich, was
bei dir passiert, und kann oft Unterstützung ergänzen.

Bekanntes Problem: Mit Edge-Explore-2-Firmware 31.33 weigert sich das Gerät
selbst, den vom Di2 genutzten Bluetooth-Dienst zu registrieren — keine
Drittanbieter-App kann die Gänge lesen (der Akkustand funktioniert weiter). An
Garmin gemeldet und bestätigt (CIQQA-4662), ein Firmware-Fix steht aus. Firmware
30.23 ist nicht betroffen.

Unabhängige, inoffizielle App — nicht mit Shimano verbunden.
```

### 🇸🇦 العربية — Title: `حقل Di2`
```
يعرض حقل Di2 الترس الخلفي الحالي لنظام Di2 (مثل 5•12) ومستوى بطارية الوحدة
اللاسلكية مباشرة على شاشة بيانات جهاز Edge. الاتصال عبر Bluetooth Low Energy —
دون الحاجة إلى ANT+.

لا يوجد زر للضغط: أضف الحقل إلى شاشة بيانات، وأيقظ Di2 بتحريك أي ذراع تبديل،
فيعثر عليه الحقل ويتصل تلقائيًا. بعدها يظل مرتبطًا بتلك الوحدة ويعيد الاتصال بها
في كل رحلة. تشير النقطة الملونة إلى الحالة: أزرق بحث، أصفر اتصال، أخضر متصل،
أزرق داكن مرتبط بجهاز Di2 الخاص بك، برتقالي إعادة محاولة.

ما الذي يعرضه
- الترس الخلفي بأرقام كبيرة أو كرسم للكاسيت أو كليهما
- مؤشر الترس الأمامي لأنظمة 2x/3x
- بطارية Di2 كنسبة مئوية أو أيقونة ملونة أو كليهما
- مظهر نهاري / ليلي، وست لغات (EN, FR, ES, RU, DE, AR)

إعداد نظام النقل
اختر إعدادًا مسبقًا من Shimano للتروس الأمامية والكاسيت (مثل 50-34 أو 11-34 أو
10-51)، أو اختر Custom وأدخل عدد الأسنان يدويًا.

التسجيل في النشاط
التروس والأسنان والنسبة والبطارية كل ثانية، مع ملخص: أعلى ترس خلفي، وأقصى نسبة،
وأدنى بطارية، وعدد التبديلات. يظهر في قسم Connect IQ داخل النشاط.

تبديل الدراجة
فعّل «نسيان Di2 المقترن» في إعدادات الحقل — يترك الوحدة الحالية ويرتبط بأقرب
جهاز Di2 مستيقظ عند الفحص التالي.

الإعداد الذي جُرّب عليه
طُوِّر وجُرِّب على دراجتي الشخصية: Shimano XT Di2 RD-M8250-SGS (12 سرعة) مع
Garmin Edge Explore 2. من المرجّح أن تعمل سلاسل Di2 الأخرى التي تبث البيانات
نفسها عبر Bluetooth، لكن لا يمكنني التحقق منها بنفسي.

إذا لم يعمل شيء ما
فعّل «شاشة التشخيص» في إعدادات الحقل. عندها يعرض الحقل شاشة تقنية بدل التخطيط
المعتاد: حالة الاتصال، والطراز المكتشف، والبيانات الخام من جهاز Di2 لديك. أرسل
لي صورة لتلك الشاشة، فأرى ما يجري في إعدادك، وغالبًا ما أتمكن من إضافة الدعم.

مشكلة معروفة: مع إصدار البرنامج 31.33 على Edge Explore 2 يرفض الجهاز نفسه تسجيل
خدمة البلوتوث التي يستخدمها Di2، لذا لا يمكن لأي تطبيق خارجي قراءة التروس (تظل
البطارية تعمل). أُبلغت Garmin وتم اعتماد البلاغ (CIQQA-4662) بانتظار إصلاح
البرنامج. الإصدار 30.23 غير متأثر.

تطبيق مستقل غير رسمي — غير تابع لشركة Shimano.
```
