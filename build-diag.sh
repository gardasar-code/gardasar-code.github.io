#!/usr/bin/env bash
# Диагностическая сборка для РЕАЛЬНОГО устройства: BLE включён И System.println
# пишется в файл GARMIN/APPS/LOGS/*.TXT (для снятия лога скана/реконнекта).
#
# Почему отдельный скрипт, а не build.sh:
#   • release (-r): BLE on, но логирование в файл вырезано → лога нет.
#   • debug (F5):   логирование есть, но bleEnabled()=false → BLE off.
# Эти режимы взаимоисключающие. Здесь собираем DEBUG-сборку (логи в файле),
# но во ВРЕМЕННОЙ копии исходников форсируем BLE on и отключаем демо-цикл.
# Рабочее дерево source/ НЕ трогаем.
#
# Результат: bin/Di2App-<version>-diag.prg  (метка diag в имени — намеренно).
set -euo pipefail

cd "$(dirname "$0")"

SDK="$(tr -d '\n' < "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
MONKEYC="${SDK}bin/monkeyc"
KEY="/Volumes/WD2TB/Projects/sln_chipre/garmin/developer_key/developer_key"
DEVICE="edgeexplore2"

# Версия — источник истины manifest.xml: идёт и в имя .prg, и, как следствие,
# в имя лог-файла на устройстве (Garmin пишет в GARMIN/APPS/LOGS/<имя_prg>.TXT).
VERSION="$(sed -n 's/.* version="\([0-9.]*\)".*/\1/p' manifest.xml | tail -1)"
# Имя результата — с версией, как у .iq-бет: в Finder сразу видно, что за сборка.
#
# ВАЖНО ПРО ИМЯ ЛОГА: устройство нормализует имя приложения, заменяя точки на
# подчёркивания (в CIQ_LOG.YML это видно как `Filename: 'Di2App-0_0_47-diag'`), и
# ищет файл лога именно под нормализованным именем. Поэтому .prg остаётся с точками,
# а .TXT создаётся с подчёркиваниями — иначе имена не совпадут и лог будет пуст.
NAME="Di2App-${VERSION}-diag"
OUT="bin/${NAME}.prg"
LOGNAME="Di2App-${VERSION//./_}-diag.TXT"

SRC_TMP=".diag-src"
RES_TMP=".diag-res"
MANIFEST_TMP=".diag-manifest.xml"
JUNGLE_TMP="monkey-diag.jungle"

# Отдельный app id для диаг-сборки. Со «своим» id устройство держит её как отдельное
# поле рядом со store-версией (свои настройки, свой Storage) и, главное, не путает их
# в списке полей. Значение фиксированное, а не случайное, — иначе настройки диаг-поля
# сбрасывались бы при каждой пересборке.
DIAG_APP_ID="d1a92026aa5f4c1b9e3d70f2c48b6d10"

# Применить sed-патч и УБЕДИТЬСЯ, что он сработал. Патчи здесь молчаливые: если
# исходник переименовали или строка уехала в другой файл, sed просто ничего не найдёт
# и соберётся «диаг-сборка» без диагностики. Так уже случалось с DIAG_VERSION при
# переезде кода в Di2DiagScreen — теперь такой промах роняет сборку сразу.
patch() {
  local file="$1" expr="$2" what="$3"
  local before after
  before="$(md5 -q "$file")"
  sed -i '' "$expr" "$file"
  after="$(md5 -q "$file")"
  if [ "$before" = "$after" ]; then
    echo "✗ патч не применился: $what ($file)" >&2
    echo "  выражение: $expr" >&2
    exit 1
  fi
}

cleanup() { rm -rf "$SRC_TMP" "$RES_TMP" "$MANIFEST_TMP" "$JUNGLE_TMP"; }
trap cleanup EXIT

mkdir -p bin
rm -rf "$SRC_TMP"
cp -R source "$SRC_TMP"

# Патч 1: BLE включён и в debug-сборке (на устройстве реальный стек работает).
patch "$SRC_TMP/Di2FieldApp.mc" \
  's#(:debug)   function bleEnabled() as Lang.Boolean { return false; }#(:debug)   function bleEnabled() as Lang.Boolean { return true; }  // DIAG#' \
  "BLE on in debug build"

# Патч 2: на устройстве показываем реальные BLE-данные, а не демо-цикл.
patch "$SRC_TMP/Di2FieldView.mc" \
  's#^    function applyDebugData() as Void {$#    function applyDebugData() as Void {\n        return;  // DIAG: real BLE data, no demo#' \
  "no demo data"

# Патч 3: включаем диагностический лог (в коммите DEBUG=false для release).
patch "$SRC_TMP/Di2BleDelegate.mc" \
  's#private const DEBUG = false;#private const DEBUG = true;   // DIAG#' \
  "file logging on"

# Патч 4: форсируем diag-оверлей. В диаг-сборке экран нужен ровно один — технический,
# и полагаться на тоггл diagOverlay в настройках Connect не стоит: забытый тоггл даёт
# бесполезное фото обычного макета вместо счётчиков notify/подписки.
patch "$SRC_TMP/Di2FieldView.mc" \
  's#    private const DEBUG_OVERLAY = false;#    private const DEBUG_OVERLAY = true;   // DIAG#' \
  "diag screen drawn"

# Патч 5: имя поля с суффиксом « Diag» во ВСЕХ локалях. Иначе store-бета и диаг-сборка
# выглядят в списке полей Edge одинаково, и легко воткнуть на экран не ту (а лог пишет
# только диаг-сборка). Ресурсы патчим в копии — рабочее дерево не трогаем.
rm -rf "$RES_TMP"
mkdir -p "$RES_TMP"
cp -R resources "$RES_TMP/resources"
for loc in ara deu fre rus spa; do
  cp -R "resources-$loc" "$RES_TMP/resources-$loc"
done
# AppName: суффикс " Beta" ЗАМЕНЯЕМ на " Diag" (а не дописываем) — «Di2 Field Beta Diag»
# не влезает в список полей Edge и обрезается ровно по различающей части.
find "$RES_TMP" -name strings.xml -exec \
  sed -i '' -e 's#\(<string id="AppName">[^<]*\) Beta</string>#\1</string>#' \
            -e 's#\(<string id="AppName">[^<]*\)</string>#\1 Diag</string>#' {} \;

# Патч 6: свой app id (см. DIAG_APP_ID) — копия манифеста, оригинал не трогаем.
sed 's#id="[0-9a-f]\{32\}"#id="'"$DIAG_APP_ID"'"#' manifest.xml > "$MANIFEST_TMP"

# Патч 7: в диаг-сборке отключаем FIT-контрибьютор. Data Field на Edge Explore 2 живёт
# в жёстком лимите памяти, debug-сборка (без -r) не оптимизирована и тратит заметно
# больше релизной, а поля FIT — уже ловленный источник OOM («New Field out of memory
# for FIT data», doc/CIQ_LOG.BAK). Для разбора BLE запись в FIT не нужна.
patch "$SRC_TMP/Di2FieldView.mc" \
  's#        _fit = new Di2FitContributor(self);#        _fit = null;   // DIAG: no FIT, spare the memory#' \
  "no FIT contributor"

# Патч 8: вписываем версию в diag-экран (строка v=). В имени файла версии больше нет,
# а знать, какая сборка стоит на устройстве, по фото экрана надо.
patch "$SRC_TMP/Di2DiagScreen.mc" \
  's#    const DIAG_VERSION = "";#    const DIAG_VERSION = "'"$VERSION"'";   // DIAG#' \
  "version on diag screen"

# Патч 9: включаем СБОР диагностики. Отрисовку включает патч 4 (DEBUG_OVERLAY), но
# сырые пакеты и их длина копятся в делегате под условием _state.diagOverlay — это
# пользовательская настройка, и в диаг-сборке она оставалась выключенной. Симптом:
# счётчики pkt растут (они безусловные), а len=0 и hex-дампов на экране нет.
patch "$SRC_TMP/Di2FieldApp.mc" \
  's#_state.diagOverlay = readBooleanProperty("diagOverlay", false);#_state.diagOverlay = true;   // DIAG: collect raw packets too#' \
  "diag data collected"

# Временный jungle с источниками и ресурсами из копий. Локали перечисляем ЯВНО:
# автоматика ищет resources-<lang> относительно проекта, а не относительно нашего
# resourcePath, и без этих строк тянула бы НЕПРОПАТЧЕННЫЕ имена из рабочего дерева
# (симптом: в английском интерфейсе «… Diag», а в испанском по-прежнему «… Beta»).
cat > "$JUNGLE_TMP" <<EOF
project.manifest = $MANIFEST_TMP
base.sourcePath = $SRC_TMP
base.resourcePath = $RES_TMP/resources
base.lang.ara = $RES_TMP/resources-ara
base.lang.deu = $RES_TMP/resources-deu
base.lang.fre = $RES_TMP/resources-fre
base.lang.rus = $RES_TMP/resources-rus
base.lang.spa = $RES_TMP/resources-spa
EOF

echo "▶ diag .prg (устройство, BLE on + файловый лог), version $VERSION"
# Без -r: System.println пишется в GARMIN/APPS/LOGS/*.TXT на устройстве.
"$MONKEYC" -d "$DEVICE" -f "$JUNGLE_TMP" -o "$OUT" -y "$KEY" -w
# Готовим пустой файл лога с ПРАВИЛЬНЫМ именем: создавать его вручную — постоянный
# источник ошибок (имя обязано совпадать с именем .prg, иначе вывод молча теряется).
# Достаточно скопировать оба файла на устройство.
: > "bin/$LOGNAME"

echo "✓ $OUT      -> GARMIN/APPS/"
echo "✓ bin/$LOGNAME -> GARMIN/APPS/LOGS/   (пустой файл лога, уже с нужным именем)"
echo "  оба файла обязательны: без .TXT с таким же именем лог не пишется"
