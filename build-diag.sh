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

# Версия — источник истины manifest.xml (для лога сборки; в имя файла не кладём,
# чтобы имя совпадало с лог-файлом DI2DIAG.TXT без FAT/8.3-усечения).
VERSION="$(sed -n 's/.* version="\([0-9.]*\)".*/\1/p' manifest.xml | tail -1)"
# Два имени результата:
#   OUT      — фикс-имя ДЛЯ УСТРОЙСТВА. Лог пишется в GARMIN/APPS/LOGS/<имя_prg>.TXT и
#              создаётся вручную, поэтому имя не должно меняться от версии к версии —
#              иначе после каждой пересборки пришлось бы заводить новый пустой .TXT.
#   OUT_VER  — копия с версией ДЛЯ АРХИВА в bin/ (рядом с .iq-бетами, чтобы в Finder
#              было видно, что за сборка).
OUT="bin/DI2DIAG.prg"

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

# Временный jungle с источниками и ресурсами из копий. Локали (resources-<lang>)
# компилятор подхватывает сам — они лежат рядом с базовой папкой, как в рабочем дереве.
cat > "$JUNGLE_TMP" <<EOF
project.manifest = $MANIFEST_TMP
base.sourcePath = $SRC_TMP
base.resourcePath = $RES_TMP/resources
EOF

echo "▶ diag .prg (устройство, BLE on + файловый лог), version $VERSION"
# Без -r: System.println пишется в GARMIN/APPS/LOGS/*.TXT на устройстве.
"$MONKEYC" -d "$DEVICE" -f "$JUNGLE_TMP" -o "$OUT" -y "$KEY" -w
OUT_VER="bin/Di2App-${VERSION}-diag.prg"
cp "$OUT" "$OUT_VER"
echo "✓ $OUT — залей в GARMIN/APPS/"
echo "  (архивная копия: $OUT_VER)"
echo "  ВАЖНО: заранее создай ПУСТОЙ файл GARMIN/APPS/LOGS/DI2DIAG.TXT (см. doc/LOGGING.md)"
