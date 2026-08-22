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
# Имя результата — короткое слово без цифр и разделителей. Устройство ищет файл лога
# по нормализованному имени приложения, и любые точки/версии в имени приводили к тому,
# что .TXT не совпадал и лог молча оставался пустым. Постоянное имя означает ещё и то,
# что новая сборка ЗАМЕНЯЕТ старую на устройстве, а не копится рядом с ней.
# Версия сборки видна не в имени файла, а на самом diag-экране (строка v=) — см. патч 8.
NAME="DIDIAG"
OUT="bin/${NAME}.prg"
LOGNAME="${NAME}.TXT"

SRC_TMP=".diag-src"
RES_TMP=".diag-res"
MANIFEST_TMP=".diag-manifest.xml"
JUNGLE_TMP="monkey-diag.jungle"

# Отдельный app id для диаг-сборки. Со «своим» id устройство держит её как отдельное
# поле рядом со store-версией (свои настройки, свой Storage) и, главное, не путает их
# в списке полей. Значение фиксированное, а не случайное, — иначе настройки диаг-поля
# сбрасывались бы при каждой пересборке.
DIAG_APP_ID="d1a92026aa5f4c1b9e3d70f2c48b6d10"

cleanup() { rm -rf "$SRC_TMP" "$RES_TMP" "$MANIFEST_TMP" "$JUNGLE_TMP"; }
trap cleanup EXIT

mkdir -p bin
rm -rf "$SRC_TMP"
cp -R source "$SRC_TMP"

# Патч 1: BLE включён и в debug-сборке (на устройстве реальный стек работает).
sed -i '' 's#(:debug)   function bleEnabled() as Lang.Boolean { return false; }#(:debug)   function bleEnabled() as Lang.Boolean { return true; }  // DIAG#' \
  "$SRC_TMP/Di2FieldApp.mc"

# Патч 2: на устройстве показываем реальные BLE-данные, а не демо-цикл.
sed -i '' 's#^    function applyDebugData() as Void {$#    function applyDebugData() as Void {\n        return;  // DIAG: real BLE data, no demo#' \
  "$SRC_TMP/Di2FieldView.mc"

# Патч 3: включаем диагностический лог (в коммите DEBUG=false для release).
sed -i '' 's#private const DEBUG = false;#private const DEBUG = true;   // DIAG#' \
  "$SRC_TMP/Di2BleDelegate.mc"

# Патч 4: форсируем diag-оверлей. В диаг-сборке экран нужен ровно один — технический,
# и полагаться на тоггл diagOverlay в настройках Connect не стоит: забытый тоггл даёт
# бесполезное фото обычного макета вместо счётчиков notify/подписки.
sed -i '' 's#    private const DEBUG_OVERLAY = false;#    private const DEBUG_OVERLAY = true;   // DIAG#' \
  "$SRC_TMP/Di2FieldView.mc"

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
sed -i '' 's#        _fit = new Di2FitContributor(self);#        _fit = null;   // DIAG: no FIT, spare the memory#' \
  "$SRC_TMP/Di2FieldView.mc"

# Патч 8: вписываем версию в diag-экран (строка v=). В имени файла версии больше нет,
# а знать, какая сборка стоит на устройстве, по фото экрана надо.
sed -i '' 's#    private const DIAG_VERSION = "";#    private const DIAG_VERSION = "'"$VERSION"'";   // DIAG#' \
  "$SRC_TMP/Di2FieldView.mc"

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

# Архивная копия с версией — только для истории сборок в bin/ (в Finder видно, что
# за сборка). На устройство идёт ВСЕГДА короткий $OUT: имя лог-файла устройство берёт
# из имени .prg, поэтому короткий лог возможен только при коротком имени приложения.
ARCHIVE="bin/Di2App-${VERSION}-diag.prg"
cp "$OUT" "$ARCHIVE"

echo "✓ $OUT      -> GARMIN/APPS/"
echo "✓ bin/$LOGNAME -> GARMIN/APPS/LOGS/   (пустой файл лога, уже с нужным именем)"
echo "  оба файла обязательны: без .TXT с таким же именем лог не пишется"
echo "  (архивная копия с версией: $ARCHIVE — на устройство НЕ нужна)"
